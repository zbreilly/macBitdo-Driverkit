#include <DriverKit/IOLib.h>
#include <DriverKit/OSData.h>
#include <DriverKit/OSDictionary.h>
#include <DriverKit/OSNumber.h>
#include <DriverKit/OSString.h>
#include <DriverKit/OSBoolean.h>
#include <DriverKit/IOBufferMemoryDescriptor.h>
#include <DriverKit/IOMemoryMap.h>
#include <USBDriverKit/IOUSBHostInterface.h>
#include <USBDriverKit/USBDriverKitDefs.h>
#include <HIDDriverKit/IOHIDDeviceKeys.h>
#include <os/log.h>
#include <time.h>
#include "UltimateReceiverHID.h"
#include "ReceiverProtocol.h"

using namespace ReceiverProtocol;

// All device callbacks run on the service's default serial dispatch queue.
// Buffers/actions stay retained until aborted transfers and timer cancellation
// have completed; Stop does not block the queue that delivers completions.
struct UltimateReceiverHID_IVars {
    IOUSBHostInterface *interface;
    IODispatchQueue *queue;
    IOUSBHostPipe *inputPipe,*outputPipe;
    IOBufferMemoryDescriptor *input,*output,*request,*hidInput,*hidGuide;
    uint8_t *inputBytes,*outputBytes,*requestBytes,*hidBytes,*guideBytes;
    OSAction *inputAction,*outputAction,*timerAction;
    IOTimerDispatchSource *timer;
    IOService *stopProvider;
    bool opened,inputPending,outputPending,stopping,timerCancelled,cancellingTimer;
    bool ledPending,outputFailed,haveOutput,stopFinished;
    bool suspended,powerChangePending,resetPipesPending;
    uint32_t pendingPowerFlags;
    uint8_t outputLow,outputHigh,submittedLow,submittedHigh;
    uint32_t submittedLength;
    uint64_t outputStarted,retryInputAt,retryResetAt,retryOutputAt;
    unsigned inputErrors;
    RumbleEffect effect;
    double effectStarted;
};

static uint64_t nowNanos(){return clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);}
static double nowSeconds(){return (double)nowNanos()/1e9;}

static bool mapBuffer(IOBufferMemoryDescriptor *buffer,uint8_t **bytes) {
    IOAddressSegment range{};
    if(!buffer||buffer->GetAddressRange(&range)!=kIOReturnSuccess)return false;
    *bytes=reinterpret_cast<uint8_t *>(range.address);return *bytes!=nullptr;
}

bool UltimateReceiverHID::init() {
    ivars=nullptr;
    if(!super::init())return false;
    ivars=IONewZero(UltimateReceiverHID_IVars,1);
    return ivars!=nullptr;
}

void UltimateReceiverHID::free() {
    if(ivars){
        ReleaseTransport();
        IODelete(ivars,UltimateReceiverHID_IVars,1);
    }
    super::free();
}

void UltimateReceiverHID::ReleaseTransport() {
        if(ivars->opened){ivars->interface->Close(this,0);ivars->opened=false;}
        OSSafeReleaseNULL(ivars->timer);
        OSSafeReleaseNULL(ivars->timerAction);
        OSSafeReleaseNULL(ivars->inputAction);
        OSSafeReleaseNULL(ivars->outputAction);
        OSSafeReleaseNULL(ivars->input);OSSafeReleaseNULL(ivars->output);
        OSSafeReleaseNULL(ivars->request);OSSafeReleaseNULL(ivars->hidInput);
        OSSafeReleaseNULL(ivars->hidGuide);
        OSSafeReleaseNULL(ivars->inputPipe);OSSafeReleaseNULL(ivars->outputPipe);
        OSSafeReleaseNULL(ivars->interface);OSSafeReleaseNULL(ivars->queue);
        // The mapped addresses die with their descriptors.
        ivars->inputBytes=ivars->outputBytes=ivars->requestBytes=ivars->hidBytes=ivars->guideBytes=nullptr;
}

bool UltimateReceiverHID::handleStart(IOService *provider) {
    if(!super::handleStart(provider))return false;
    ivars->interface=OSDynamicCast(IOUSBHostInterface,provider);
    if(!ivars->interface)return false;
    ivars->interface->retain();
    uint8_t alternate=0;
    if(ivars->interface->Open(this,0,&alternate)!=kIOReturnSuccess)return false;
    ivars->opened=true;
    const auto configuration=ivars->interface->CopyConfigurationDescriptor();
    const auto descriptor=configuration?ivars->interface->GetInterfaceDescriptor(configuration):nullptr;
    bool expected=descriptor&&descriptor->bInterfaceNumber==0&&descriptor->bAlternateSetting==0&&
        descriptor->bInterfaceClass==0xff&&descriptor->bInterfaceSubClass==0x5d&&descriptor->bInterfaceProtocol==1;
    if(configuration)IOUSBHostFreeDescriptor(configuration);
    if(!expected)return false;
    if(ivars->interface->CopyPipe(0x81,&ivars->inputPipe)!=kIOReturnSuccess||
       ivars->interface->CopyPipe(0x02,&ivars->outputPipe)!=kIOReturnSuccess)return false;
    if(ivars->interface->CreateIOBuffer(kIOMemoryDirectionIn,32,&ivars->input)!=kIOReturnSuccess||
       ivars->interface->CreateIOBuffer(kIOMemoryDirectionInOut,8,&ivars->output)!=kIOReturnSuccess||
       ivars->interface->CreateIOBuffer(kIOMemoryDirectionIn,20,&ivars->request)!=kIOReturnSuccess||
       IOBufferMemoryDescriptor::Create(kIOMemoryDirectionInOut,17,0,&ivars->hidInput)!=kIOReturnSuccess||
       IOBufferMemoryDescriptor::Create(kIOMemoryDirectionInOut,2,0,&ivars->hidGuide)!=kIOReturnSuccess)return false;
    if(!mapBuffer(ivars->input,&ivars->inputBytes)||!mapBuffer(ivars->output,&ivars->outputBytes)||
       !mapBuffer(ivars->request,&ivars->requestBytes)||!mapBuffer(ivars->hidInput,&ivars->hidBytes)||
       !mapBuffer(ivars->hidGuide,&ivars->guideBytes))return false;
    encode({},ivars->hidBytes);ivars->guideBytes[0]=2;
    if(CopyDispatchQueue(kIOServiceDefaultQueueName,&ivars->queue)!=kIOReturnSuccess||
       CreateActionInputComplete(0,&ivars->inputAction)!=kIOReturnSuccess||
       CreateActionOutputComplete(0,&ivars->outputAction)!=kIOReturnSuccess||
       CreateActionTick(0,&ivars->timerAction)!=kIOReturnSuccess||
       IOTimerDispatchSource::Create(ivars->queue,&ivars->timer)!=kIOReturnSuccess||
       ivars->timer->SetHandler(ivars->timerAction)!=kIOReturnSuccess||
       ivars->timer->SetEnable(true)!=kIOReturnSuccess)return false;
    // The first output is the proven receiver player-indicator initialization.
    // Its completion queues IN before the vendor startup request.
    ivars->ledPending=true;
    return true;
}

kern_return_t IMPL(UltimateReceiverHID, Start) {
    auto result=Start(provider,SUPERDISPATCH);
    if(result!=kIOReturnSuccess){
        // handleStart may succeed before superclass HID publication fails.
        // No USB transfer or timer deadline has been submitted yet.
        if(ivars->timer){
            retain();
            ivars->timer->Cancel(^{ReleaseTransport();release();});
        }else ReleaseTransport();
        return result;
    }
    ivars->timer->WakeAtTime(kIOTimerClockMonotonicRaw,nowNanos()+10000000,1000000);
    os_log(OS_LOG_DEFAULT,"macBitdo DriverKit: receiver interface started");
    return kIOReturnSuccess;
}

OSDictionary *UltimateReceiverHID::newDeviceDescription() {
    auto description=OSDictionary::withCapacity(8);
    if(!description)return nullptr;
    auto vendor=OSNumber::withNumber(0x045e,32);
    auto product=OSNumber::withNumber(0x02fd,32);
    auto interval=OSNumber::withNumber(4000,32);
    auto transport=OSString::withCString("Bluetooth");
    auto name=OSString::withCString("8BitDo Ultimate 2.4 GHz Driver");
    auto manufacturer=OSString::withCString("macBitdo");
    if(!vendor||!product||!interval||!transport||!name||!manufacturer){
        OSSafeReleaseNULL(vendor);OSSafeReleaseNULL(product);OSSafeReleaseNULL(interval);
        OSSafeReleaseNULL(transport);OSSafeReleaseNULL(name);OSSafeReleaseNULL(manufacturer);
        description->release();return nullptr;
    }
    description->setObject(kIOHIDVendorIDKey,vendor);description->setObject(kIOHIDProductIDKey,product);
    description->setObject(kIOHIDReportIntervalKey,interval);description->setObject(kIOHIDTransportKey,transport);
    description->setObject(kIOHIDProductKey,name);description->setObject(kIOHIDManufacturerKey,manufacturer);
    description->setObject("RegisterService",kOSBooleanTrue);
    vendor->release();product->release();interval->release();transport->release();name->release();manufacturer->release();
    // Bluetooth identifies the published Xbox report format for SDL. The
    // physical transport remains the receiver's USB/2.4 GHz radio link.
    return description;
}

OSData *UltimateReceiverHID::newReportDescriptor() {
    return OSData::withBytes(hidDescriptor,sizeof(hidDescriptor));
}

void UltimateReceiverHID::QueueInput() {
    if(ivars->stopping||ivars->suspended||ivars->resetPipesPending||ivars->inputPending)return;
    ivars->inputPending=true;
    auto result=ivars->inputPipe->AsyncIO(ivars->input,32,ivars->inputAction,0);
    if(result!=kIOReturnSuccess){
        ivars->inputPending=false;ivars->retryInputAt=nowNanos()+100000000;
        if(ivars->inputErrors++<5)os_log(OS_LOG_DEFAULT,"macBitdo: input submit 0x%x",result);
    }
}

void UltimateReceiverHID::BeginReceiverInput() {
    // LED output is cosmetic. A failed submission has no completion callback,
    // so both immediate failure and completion must advance startup here.
    if(!ivars->ledPending||ivars->stopping||ivars->suspended)return;
    ivars->ledPending=false;
    QueueInput();
    uint16_t replyLength=0;
    auto result=ivars->interface->DeviceRequest(0xc1,1,0x0100,0,20,ivars->request,&replyLength,1000);
    os_log(OS_LOG_DEFAULT,"macBitdo: XInput startup 0x%x reply bytes %u",result,replyLength);
}

void IMPL(UltimateReceiverHID, InputComplete) {
    (void)action;
    ivars->inputPending=false;
    if(ivars->stopping||ivars->suspended){FinishQuiesceIfReady();return;}
    State state{};
    if(status==kIOReturnSuccess&&actualByteCount<=32){
        ivars->inputErrors=0;
        if(decode(ivars->inputBytes,actualByteCount,&state)){
            encode(state,ivars->hidBytes);
            bool guide=!!(state.buttons&0x400),changed=guide!=ivars->guideBytes[1];
            ivars->guideBytes[1]=guide;
            auto result=handleReport(completionTimestamp,ivars->hidInput,17);
            if(result!=kIOReturnSuccess)os_log(OS_LOG_DEFAULT,"macBitdo: HID input 0x%x",result);
            if(changed)handleReport(completionTimestamp,ivars->hidGuide,2);
        }
        QueueInput();
    }else{
        PublishNeutral();
        ivars->retryInputAt=nowNanos()+100000000;
        if(ivars->inputErrors++<5)os_log(OS_LOG_DEFAULT,"macBitdo: input completion 0x%x",status);
    }
}

void UltimateReceiverHID::ServiceOutput() {
    if(ivars->suspended&&!ivars->powerChangePending&&!ivars->stopping)return;
    if(ivars->resetPipesPending&&!ivars->suspended&&!ivars->stopping)return;
    if(!ivars->outputPipe||!ivars->outputBytes||!ivars->outputAction){ivars->outputFailed=true;return;}
    if(ivars->outputPending||ivars->outputFailed)return;
    uint8_t low=0,high=0;
    uint32_t length=8;
    if(ivars->ledPending&&!ivars->stopping&&!ivars->suspended){
        const uint8_t led[]={1,3,2};memcpy(ivars->outputBytes,led,3);length=3;
    }else{
        if(!ivars->stopping&&!ivars->suspended)rumbleAt(ivars->effect,nowSeconds()-ivars->effectStarted,&low,&high);
        if(ivars->haveOutput&&low==ivars->outputLow&&high==ivars->outputHigh)return;
        encodeRumble(low,high,ivars->outputBytes);
    }
    ivars->outputPending=true;ivars->outputStarted=nowNanos();
    ivars->submittedLow=low;ivars->submittedHigh=high;ivars->submittedLength=length;
    auto result=ivars->outputPipe->AsyncIO(ivars->output,length,ivars->outputAction,0);
    if(result!=kIOReturnSuccess){
        ivars->outputPending=false;
        os_log(OS_LOG_DEFAULT,"macBitdo: USB output submit 0x%x",result);
        // The LED write is cosmetic: its failure must not disable rumble.
        if(length==3)BeginReceiverInput();
        else{ivars->outputFailed=true;ivars->retryOutputAt=nowNanos()+1000000000;}
    }
}

void IMPL(UltimateReceiverHID, OutputComplete) {
    (void)action;(void)completionTimestamp;
    ivars->outputPending=false;
    bool wasLed=ivars->submittedLength==3;
    if(status!=kIOReturnSuccess||actualByteCount!=ivars->submittedLength){
        os_log(OS_LOG_DEFAULT,"macBitdo: USB output completion 0x%x bytes %u",status,actualByteCount);
        // A failed LED write (including a watchdog abort) leaves rumble usable.
        if(wasLed){ivars->outputFailed=false;BeginReceiverInput();}
        else{ivars->outputFailed=true;ivars->retryOutputAt=nowNanos()+1000000000;}
    }else if(wasLed){
        BeginReceiverInput();
    }else{
        ivars->haveOutput=true;ivars->outputLow=ivars->submittedLow;ivars->outputHigh=ivars->submittedHigh;
    }
    ServiceOutput();
    FinishQuiesceIfReady();
}

void IMPL(UltimateReceiverHID, Tick) {
    (void)action;(void)time;
    uint64_t current=nowNanos();
    if(!ivars->stopping&&!ivars->suspended&&ivars->resetPipesPending&&current>=ivars->retryResetAt){
        auto inputResult=ivars->inputPipe->ClearStall(true);
        auto outputResult=ivars->outputPipe->ClearStall(true);
        if(inputResult==kIOReturnSuccess&&outputResult==kIOReturnSuccess)ivars->resetPipesPending=false;
        else ivars->retryResetAt=current+100000000;
    }
    if(ivars->outputPending&&!ivars->outputFailed&&current-ivars->outputStarted>1000000000){
        ivars->outputFailed=true;
        ivars->outputPipe->Abort(0,kIOReturnAborted,nullptr);
        os_log(OS_LOG_DEFAULT,"macBitdo: rumble watchdog aborted a stalled USB write");
    }
    // A failed rumble write is retried after a backoff instead of disabling
    // rumble until replug. The current motor state is sent again afterwards.
    if(ivars->outputFailed&&ivars->outputPipe&&!ivars->outputPending&&!ivars->stopping&&!ivars->suspended&&
       !ivars->resetPipesPending&&current>=ivars->retryOutputAt){
        if(ivars->outputPipe->ClearStall(true)==kIOReturnSuccess){ivars->outputFailed=false;ivars->haveOutput=false;}
        else ivars->retryOutputAt=current+1000000000;
    }
    if(!ivars->stopping&&!ivars->suspended&&!ivars->inputPending&&ivars->retryInputAt&&current>=ivars->retryInputAt){
        auto result=ivars->inputPipe->ClearStall(true);
        if(result==kIOReturnSuccess){ivars->retryInputAt=0;QueueInput();}
        else ivars->retryInputAt=current+100000000;
    }
    ServiceOutput();
    if(!ivars->cancellingTimer&&(!ivars->suspended||ivars->powerChangePending||ivars->stopping))
        ivars->timer->WakeAtTime(kIOTimerClockMonotonicRaw,current+10000000,1000000);
    // Last operation: completing Stop may release this service.
    FinishQuiesceIfReady();
}

kern_return_t UltimateReceiverHID::getReport(IOMemoryDescriptor *report,IOHIDReportType type,
    IOOptionBits options,uint32_t completionTimeout,OSAction *action) {
    (void)completionTimeout;
    uint32_t reportID=options&0xff;
    uint32_t count=reportID==1?17:2;
    kern_return_t status=kIOReturnUnsupported;
    IOMemoryMap *mapping=nullptr;uint64_t capacity=0;
    if(ivars->stopping||ivars->suspended||ivars->resetPipesPending)status=kIOReturnNotReady;
    else if(type==kIOHIDReportTypeInput&&(reportID==1||reportID==2)){
        status=report->GetLength(&capacity);
        if(status==kIOReturnSuccess&&capacity<count)status=kIOReturnNoSpace;
        if(status==kIOReturnSuccess)status=report->CreateMapping(0,0,0,0,0,&mapping);
        if(status==kIOReturnSuccess){
            if(mapping->GetLength()<count)status=kIOReturnNoSpace;
            else memcpy(reinterpret_cast<void *>(mapping->GetAddress()),reportID==1?ivars->hidBytes:ivars->guideBytes,count);
        }
    }
    OSSafeReleaseNULL(mapping);
    if(action){CompleteReport(action,status,status==kIOReturnSuccess?count:0);return kIOReturnSuccess;}
    return status;
}

kern_return_t UltimateReceiverHID::setReport(IOMemoryDescriptor *report,IOHIDReportType type,
    IOOptionBits options,uint32_t completionTimeout,OSAction *action) {
    (void)completionTimeout;
    kern_return_t status=kIOReturnUnsupported;
    IOMemoryMap *mapping=nullptr;uint64_t length=0;
    if(ivars->stopping||ivars->suspended||ivars->resetPipesPending||ivars->outputFailed)status=kIOReturnNotReady;
    else if(type==kIOHIDReportTypeOutput&&(options&0xff)==3){
        status=report->GetLength(&length);
        if(status==kIOReturnSuccess&&(length!=8&&length!=9))status=kIOReturnBadArgument;
        if(status==kIOReturnSuccess)status=report->CreateMapping(kIOMemoryMapReadOnly,0,0,0,0,&mapping);
        if(status==kIOReturnSuccess){
            RumbleEffect effect{};
            if(mapping->GetLength()<length||!decodeRumble(3,reinterpret_cast<uint8_t *>(mapping->GetAddress()),length,&effect))
                status=kIOReturnBadArgument;
            else{ivars->effect=effect;ivars->effectStarted=nowSeconds();ServiceOutput();}
        }
    }
    OSSafeReleaseNULL(mapping);
    if(action){CompleteReport(action,status,status==kIOReturnSuccess?(uint32_t)length:0);return kIOReturnSuccess;}
    return status;
}

void UltimateReceiverHID::PublishNeutral() {
    if(!ivars->hidBytes||!ivars->guideBytes)return;
    encode({},ivars->hidBytes);ivars->guideBytes[1]=0;
    handleReport(mach_absolute_time(),ivars->hidInput,17);
    handleReport(mach_absolute_time(),ivars->hidGuide,2);
}

kern_return_t IMPL(UltimateReceiverHID, Stop) {
    if(!ivars)return Stop(provider,SUPERDISPATCH);
    if(ivars->stopping)return kIOReturnSuccess;
    // DriverKit retains provider until the deferred superclass Stop. Keep this
    // service alive while transfer completions and timer cancellation drain.
    retain();
    ivars->stopping=true;ivars->stopProvider=provider;
    PublishNeutral();
    if(ivars->inputPending)ivars->inputPipe->Abort(0,kIOReturnAborted,nullptr);
    ServiceOutput(); // OFF after the current write completes, if USB is present.
    FinishQuiesceIfReady();
    return kIOReturnSuccess;
}

// Defer the power acknowledgement just like Stop: USB buffers cannot be
// reused on wake until all pre-sleep transfers have completed.
kern_return_t IMPL(UltimateReceiverHID, SetPowerState) {
    if(!ivars||!ivars->timer||ivars->stopping)
        return SetPowerState(powerFlags,SUPERDISPATCH);
    if(powerFlags&kIOServicePowerCapabilityOn){
        if(ivars->powerChangePending){
            // Wake arrived before the sleep drain finished: acknowledge the
            // low-power state first so it is never acknowledged after On.
            uint32_t flags=ivars->pendingPowerFlags;
            ivars->powerChangePending=false;
            SetPowerState(flags,SUPERDISPATCH);
        }
        if(ivars->suspended){
            ivars->suspended=false;
            ivars->effect={};ivars->retryInputAt=0;
            ivars->haveOutput=false;ivars->outputFailed=false;ivars->ledPending=true;
            ivars->resetPipesPending=true;ivars->retryResetAt=0;
            // Reinitialize asynchronously after the superclass acknowledges
            // the powered-on state. No old rumble effect is replayed.
            ivars->timer->WakeAtTime(kIOTimerClockMonotonicRaw,nowNanos()+10000000,1000000);
        }
        return SetPowerState(powerFlags,SUPERDISPATCH);
    }
    ivars->suspended=true;ivars->effect={};ivars->retryInputAt=0;
    ivars->powerChangePending=true;ivars->pendingPowerFlags=powerFlags;
    PublishNeutral();
    if(ivars->inputPending)ivars->inputPipe->Abort(0,kIOReturnAborted,nullptr);
    ServiceOutput();
    // A second low-power transition can arrive while the timer is parked.
    ivars->timer->WakeAtTime(kIOTimerClockMonotonicRaw,nowNanos()+10000000,1000000);
    FinishQuiesceIfReady();
    return kIOReturnSuccess;
}

void UltimateReceiverHID::FinishQuiesceIfReady() {
    if((!ivars->stopping&&!ivars->powerChangePending)||ivars->stopFinished||ivars->inputPending||ivars->outputPending)return;
    if(!ivars->outputFailed&&(!ivars->haveOutput||ivars->outputLow||ivars->outputHigh)){
        ServiceOutput();return;
    }
    if(ivars->powerChangePending){
        uint32_t flags=ivars->pendingPowerFlags;
        ivars->powerChangePending=false;
        if(ivars->outputFailed)os_log(OS_LOG_DEFAULT,"macBitdo: power transition without confirmed USB motor OFF");
        SetPowerState(flags,SUPERDISPATCH);
    }
    if(!ivars->stopping)return;
    if(!ivars->timerCancelled){
        if(!ivars->timer){ivars->timerCancelled=true;FinishQuiesceIfReady();return;}
        if(!ivars->cancellingTimer){
            ivars->cancellingTimer=true;
            ivars->timer->Cancel(^{ivars->timerCancelled=true;FinishQuiesceIfReady();});
        }
        return;
    }
    ivars->stopFinished=true;
    if(ivars->outputFailed)os_log(OS_LOG_DEFAULT,"macBitdo: stopping without confirmed USB motor OFF");
    IOService *provider=ivars->stopProvider;ivars->stopProvider=nullptr;
    ReleaseTransport();
    Stop(provider,SUPERDISPATCH);
    release(); // Balance the deferred Stop retain; no provider access here.
}
