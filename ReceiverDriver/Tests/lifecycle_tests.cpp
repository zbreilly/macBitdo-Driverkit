// Appended to the actual native driver method bodies by test_driver.py.
// Fake USB completions remain explicitly pending so cancellation order varies.
struct Rig {
    UltimateReceiverHID driver;
    IOUSBHostInterface usb;
    IOTimerDispatchSource *timer;
    Rig(){assert(driver.init());assert(driver.Start(&usb)==0);timer=driver.ivars->timer;}
    void tick(){testNow+=10000000;timer->fire();}
    void ready(){tick();usb.output->complete();usb.output->complete();assert(usb.input->pending&&usb.controlCount==1);}
    void rumble(){
        IOMemoryDescriptor report(9);report.bytes={3,15,0,0,100,100,100,0,0};
        assert(driver.setReport(&report,kIOHIDReportTypeOutput,3,0,nullptr)==0);
        assert(usb.output->pending&&usb.output->writes.back()[3]==255);
    }
    void drainStop(){
        driver.Stop(&usb);
        if(usb.input->pending)usb.input->complete(kIOReturnAborted);
        while(usb.output->pending)usb.output->complete();
        assert(timer->cancelHandler);timer->finishCancel();
        assert(driver.superStops==1&&usb.closeCount==1&&driver.refs==1);
        for(auto b:usb.buffers)assert(b->refs==0);
        driver.free();
    }
};

int main(){
    {
        Rig r;r.drainStop();assert(r.usb.controlCount==0); // removed before the first timer fires
    }
    {
        UltimateReceiverHID driver;IOUSBHostInterface usb;
        assert(driver.init());driver.failAfterHandleStart=true;
        assert(driver.Start(&usb)==kIOReturnError);
        auto timer=driver.ivars->timer;
        assert(!usb.input->pending&&!usb.output->pending&&!timer->scheduled);
        timer->finishCancel();assert(usb.closeCount==1&&driver.refs==1);
        for(auto b:usb.buffers)assert(b->refs==0);
        driver.free(); // failed superclass publication also releases the USB open
    }
    {
        Rig r;r.usb.output->nextSubmit=kIOReturnError;r.tick();
        assert(r.usb.input->pending&&r.usb.controlCount==1); // immediate LED failure never suppresses input
        r.drainStop();
    }
    {
        Rig r;r.tick();r.usb.output->complete(kIOReturnError,0);
        assert(r.usb.input->pending&&r.usb.controlCount==1); // asynchronous LED failure
        r.drainStop();
    }
    {
        Rig r;r.tick();r.drainStop();assert(r.usb.controlCount==0); // removed with LED transfer pending
    }
    {
        Rig r;r.tick();testNow+=1000000001;r.tick();
        assert(r.usb.output->abortCount==1&&r.usb.controlCount==0);
        r.usb.output->complete(kIOReturnAborted,0);
        assert(r.usb.input->pending&&r.usb.controlCount==1); // watchdog preserves input fallback
        r.drainStop();
    }
    for(bool inputFirst:{false,true}){
        Rig r;r.ready();r.rumble();auto buffer=r.usb.output->buffer;
        r.driver.Stop(&r.usb);assert(r.driver.refs==2&&buffer->refs>0&&r.driver.superStops==0);
        if(inputFirst)r.usb.input->complete(kIOReturnAborted);
        r.usb.output->complete(); // active effect drains before explicit OFF
        assert(r.usb.output->pending&&r.usb.output->writes.back()[3]==0&&r.usb.output->writes.back()[4]==0);
        r.usb.output->complete();
        if(!inputFirst){assert(!r.timer->cancelHandler);r.usb.input->complete(kIOReturnAborted);}
        assert(buffer->refs>0&&r.driver.superStops==0);
        r.timer->finishCancel();assert(buffer->refs==0&&r.driver.superStops==1&&r.driver.refs==1);
        r.driver.free();
    }
    {
        Rig r;r.ready();r.rumble();
        r.driver.SetPowerState(0);
        assert(r.driver.powerAcks.empty()&&r.usb.input->abortCount==1);
        r.usb.input->complete(kIOReturnAborted);
        r.usb.output->complete();assert(r.usb.output->writes.back()[3]==0);
        assert(r.driver.powerAcks.empty());r.usb.output->complete();
        assert(r.driver.powerAcks==std::vector<uint32_t>{0});
        IOMemoryDescriptor report(9);report.bytes={3,15,0,0,100,100,100,0,0};
        assert(r.driver.setReport(&report,kIOHIDReportTypeOutput,3,0,nullptr)==kIOReturnNotReady);
        r.tick();assert(!r.timer->scheduled&&!r.usb.input->pending&&!r.usb.output->pending);
        r.driver.SetPowerState(kIOServicePowerCapabilityOn);
        r.usb.output->clearResult=kIOReturnError;r.tick(); // wake must not submit to halted pipes
        assert(!r.usb.input->pending&&!r.usb.output->pending);
        r.usb.output->clearResult=0;testNow+=100000000;r.tick();
        assert(r.usb.output->writes.back()==std::vector<uint8_t>({1,3,2}));
        r.usb.output->complete();assert(r.usb.controlCount==2&&r.usb.input->pending);
        assert(r.usb.output->writes.back()[3]==0&&r.usb.output->writes.back()[4]==0); // old effect not replayed
        r.usb.output->complete();r.drainStop();
    }
    {
        Rig r;r.ready();r.driver.SetPowerState(0);r.driver.Stop(&r.usb);
        assert(r.driver.powerAcks.empty()&&r.driver.superStops==0);
        r.usb.input->complete(kIOReturnAborted);
        assert(r.driver.powerAcks==std::vector<uint32_t>{0});
        r.timer->finishCancel();assert(r.driver.superStops==1);r.driver.free();
    }
    {
        Rig r;r.ready();r.rumble();r.usb.output->complete();
        r.usb.output->nextSubmit=kIOReturnError;r.driver.Stop(&r.usb);
        r.usb.input->complete(kIOReturnAborted);
        r.timer->finishCancel();assert(r.driver.superStops==1);r.driver.free(); // failed OFF does not deadlock removal
    }
    {
        Rig r;r.tick();r.usb.output->complete(kIOReturnError,0); // LED fails
        assert(r.usb.output->pending&&r.usb.output->writes.back().size()==8); // OFF still sent
        r.usb.output->complete();r.rumble();r.usb.output->complete(); // rumble not disabled
        r.drainStop();
    }
    {
        Rig r;r.ready();r.rumble();r.usb.output->complete(kIOReturnError,0); // rumble write fails
        IOMemoryDescriptor report(9);report.bytes={3,15,0,0,100,100,100,0,0};
        assert(r.driver.setReport(&report,kIOHIDReportTypeOutput,3,0,nullptr)==kIOReturnNotReady);
        r.tick();assert(!r.usb.output->pending&&r.usb.output->clearCount==0); // backoff
        testNow+=1000000000;r.tick();
        assert(r.usb.output->clearCount==1&&r.usb.output->pending); // recovered, state resent
        assert(r.usb.output->writes.back()[3]==0&&r.usb.output->writes.back()[4]==0);
        r.usb.output->complete();r.rumble();r.usb.output->complete();
        r.drainStop();
    }
    {
        Rig r;r.ready();r.rumble();
        r.driver.SetPowerState(0);assert(r.driver.powerAcks.empty());
        r.driver.SetPowerState(kIOServicePowerCapabilityOn); // wake before the sleep drain ends
        assert(r.driver.powerAcks==(std::vector<uint32_t>{0,kIOServicePowerCapabilityOn}));
        r.usb.input->complete(kIOReturnAborted);r.usb.output->complete();
        r.tick();assert(r.usb.output->writes.back()==std::vector<uint8_t>({1,3,2}));
        r.usb.output->complete();assert(r.usb.controlCount==2&&r.usb.input->pending);
        assert(r.usb.output->writes.back()[3]==0&&r.usb.output->writes.back()[4]==0);
        r.usb.output->complete();
        assert(r.driver.powerAcks.size()==2); // no stale low-power acknowledgement
        r.drainStop();
    }
    puts("PASS: actual driver lifecycle methods, LED-failure and rumble-failure recovery, wake during sleep, failed LED startup, watchdog, transfer drain ordering, sleep/wake and removal");
}
