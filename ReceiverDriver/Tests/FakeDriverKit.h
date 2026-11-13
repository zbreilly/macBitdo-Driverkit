// Test transport only. The lifecycle harness compiles the actual driver method
// bodies against this deterministic adapter; this is not a DriverKit emulator.
#pragma once
#include <algorithm>
#include <cassert>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <functional>
#include <vector>
#include <Block.h>

using kern_return_t=int;
using IOReturn=int;
using IOOptionBits=uint64_t;
using IOHIDReportType=int;
constexpr int kIOReturnSuccess=0,kIOReturnUnsupported=-1,kIOReturnNotReady=-2,
    kIOReturnNoSpace=-3,kIOReturnBadArgument=-4,kIOReturnAborted=-5,kIOReturnError=-6;
constexpr int kIOHIDReportTypeInput=0,kIOHIDReportTypeOutput=1;
constexpr int kIOMemoryDirectionIn=1,kIOMemoryDirectionOut=2,kIOMemoryDirectionInOut=3;
constexpr int kIOMemoryMapReadOnly=1,kIOTimerClockMonotonicRaw=0;
constexpr uint32_t kIOServicePowerCapabilityOn=2,kIOServicePowerCapabilityLow=0x10000;
constexpr const char *kIOServiceDefaultQueueName="Default";
inline uint64_t testNow=1000000000;
#define clock_gettime_nsec_np(...) testNow
inline uint64_t mach_absolute_time(){return testNow;}
#define OS_LOG_DEFAULT 0
template<class... Args> inline void testLog(Args...){ }
#define os_log testLog
#define IONewZero(T,N) new T{}
#define IODelete(P,T,N) delete P
#define OSDynamicCast(T,P) dynamic_cast<T *>(P)
#define OSSafeReleaseNULL(P) do {if(P){(P)->release();(P)=nullptr;}}while(0)

struct OSObject {
    int refs=1;
    virtual ~OSObject()=default;
    void retain(){assert(refs>0);++refs;}
    // Leave a tombstone so the test detects a released async buffer/action.
    void release(){assert(refs>0);--refs;}
};
struct OSDictionary:OSObject {
    static OSDictionary *withCapacity(unsigned){return new OSDictionary;}
    void setObject(const char *,OSObject *){}
};
struct OSNumber:OSObject {static OSNumber *withNumber(unsigned,unsigned){return new OSNumber;}};
struct OSString:OSObject {static OSString *withCString(const char *){return new OSString;}};
struct OSData:OSObject {static OSData *withBytes(const void *,size_t){return new OSData;}};
inline OSObject testTrue;
inline OSObject *kOSBooleanTrue=&testTrue;
#define kIOHIDVendorIDKey "VendorID"
#define kIOHIDProductIDKey "ProductID"
#define kIOHIDReportIntervalKey "ReportInterval"
#define kIOHIDTransportKey "Transport"
#define kIOHIDProductKey "Product"
#define kIOHIDManufacturerKey "Manufacturer"

struct IOAddressSegment {uint64_t address,length;};
struct IOMemoryMap:OSObject {
    uint8_t *address;size_t length;
    IOMemoryMap(uint8_t *p,size_t n):address(p),length(n){}
    uint64_t GetAddress(){return reinterpret_cast<uint64_t>(address);}
    uint64_t GetLength(){return length;}
};
struct IOMemoryDescriptor:OSObject {
    std::vector<uint8_t> bytes;
    explicit IOMemoryDescriptor(size_t n):bytes(n){}
    int GetLength(uint64_t *n){assert(refs>0);*n=bytes.size();return 0;}
    int CreateMapping(uint64_t,uint64_t,uint64_t,uint64_t,uint64_t,IOMemoryMap **m){
        assert(refs>0);*m=new IOMemoryMap(bytes.data(),bytes.size());return 0;
    }
};
struct IOBufferMemoryDescriptor:IOMemoryDescriptor {
    using IOMemoryDescriptor::IOMemoryDescriptor;
    int GetAddressRange(IOAddressSegment *r){assert(refs>0);*r={reinterpret_cast<uint64_t>(bytes.data()),bytes.size()};return 0;}
    static int Create(int,size_t n,int,IOBufferMemoryDescriptor **p){*p=new IOBufferMemoryDescriptor(n);return 0;}
};
struct OSAction:OSObject {
    std::function<void(int,uint32_t,uint64_t)> complete;
    std::function<void()> tick;
};
struct IOService:OSObject {};
struct IODispatchQueue:OSObject {};
struct IOUSBHostPipe:OSObject {
    int nextSubmit=0,clearResult=0,clearCount=0,abortCount=0;
    OSAction *pending=nullptr;
    IOMemoryDescriptor *buffer=nullptr;
    uint32_t submittedLength=0;
    std::vector<std::vector<uint8_t>> writes;
    int AsyncIO(IOMemoryDescriptor *b,uint32_t n,OSAction *a,uint32_t timeout){
        assert(timeout==0&&pending==nullptr&&b->refs>0&&a->refs>0);
        int result=nextSubmit;nextSubmit=0;if(result)return result;
        pending=a;buffer=b;submittedLength=n;
        writes.emplace_back(b->bytes.begin(),b->bytes.begin()+n);return 0;
    }
    int Abort(IOOptionBits,int,IOService *){++abortCount;return 0;}
    int ClearStall(bool request){assert(request&&pending==nullptr);++clearCount;return clearResult;}
    void complete(int result=0,int count=-1){
        assert(pending&&pending->refs>0&&buffer->refs>0);
        auto a=pending;auto n=count<0?submittedLength:static_cast<uint32_t>(count);
        pending=nullptr;buffer=nullptr;a->retain();
        a->complete(result,n,testNow);a->release();
    }
};
struct TestInterfaceDescriptor {
    uint8_t bInterfaceNumber=0,bAlternateSetting=0,bInterfaceClass=0xff,bInterfaceSubClass=0x5d,bInterfaceProtocol=1;
};
struct TestConfiguration {};
inline void IOUSBHostFreeDescriptor(const TestConfiguration *p){delete p;}
struct IOUSBHostInterface:IOService {
    IOUSBHostPipe *input=new IOUSBHostPipe,*output=new IOUSBHostPipe;
    TestInterfaceDescriptor descriptor;
    int controlCount=0,closeCount=0;
    std::vector<IOBufferMemoryDescriptor *> buffers;
    int Open(IOService *,int,uint8_t *a){*a=0;return 0;}
    int Close(IOService *,int){++closeCount;return 0;}
    const TestConfiguration *CopyConfigurationDescriptor(){return new TestConfiguration;}
    const TestInterfaceDescriptor *GetInterfaceDescriptor(const TestConfiguration *){return &descriptor;}
    int CopyPipe(uint8_t endpoint,IOUSBHostPipe **p){*p=endpoint==0x81?input:output;(*p)->retain();return 0;}
    int CreateIOBuffer(int,size_t n,IOBufferMemoryDescriptor **p){*p=new IOBufferMemoryDescriptor(n);buffers.push_back(*p);return 0;}
    int DeviceRequest(int type,int req,int value,int index,int length,IOBufferMemoryDescriptor *,uint16_t *count,int timeout){
        assert(type==0xc1&&req==1&&value==0x100&&index==0&&length==20&&timeout==1000);
        assert(input->pending);++controlCount;*count=2;return 0;
    }
};
struct IOTimerDispatchSource:OSObject {
    OSAction *handler=nullptr;
    void (^cancelHandler)()=nullptr;
    bool scheduled=false,cancelled=false;
    static int Create(IODispatchQueue *,IOTimerDispatchSource **p){*p=new IOTimerDispatchSource;return 0;}
    int SetHandler(OSAction *a){handler=a;return 0;}
    int SetEnable(bool){return 0;}
    int WakeAtTime(int,uint64_t,uint64_t){assert(!cancelled);scheduled=true;return 0;}
    int Cancel(void (^block)()){
        assert(!cancelHandler&&!cancelled);scheduled=false;cancelled=true;cancelHandler=Block_copy(block);return 0;
    }
    void fire(){assert(scheduled&&!cancelled);scheduled=false;handler->retain();handler->tick();handler->release();}
    void finishCancel(){assert(cancelHandler);auto b=cancelHandler;cancelHandler=nullptr;b();Block_release(b);}
};
struct SuperDispatch {};
#define SUPERDISPATCH SuperDispatch{}
struct FakeHIDDevice:IOService {
    int superStops=0;
    bool failAfterHandleStart=false;
    std::vector<uint32_t> powerAcks;
    std::vector<std::vector<uint8_t>> reports;
    bool init(){return true;}
    void free(){}
    virtual bool handleStart(IOService *){return true;}
    int Start(IOService *provider,SuperDispatch){return handleStart(provider)&&!failAfterHandleStart?0:kIOReturnError;}
    int Stop(IOService *,SuperDispatch){++superStops;return 0;}
    int SetPowerState(uint32_t flags,SuperDispatch){powerAcks.push_back(flags);return 0;}
    int handleReport(uint64_t,IOMemoryDescriptor *b,int n){assert(b->refs>0);reports.emplace_back(b->bytes.begin(),b->bytes.begin()+n);return 0;}
    int CompleteReport(OSAction *,int,uint32_t){return 0;}
    int CopyDispatchQueue(const char *,IODispatchQueue **p){*p=new IODispatchQueue;return 0;}
};
struct UltimateReceiverHID_IVars;
struct UltimateReceiverHID:FakeHIDDevice {
    using FakeHIDDevice::Start;
    using FakeHIDDevice::Stop;
    using FakeHIDDevice::SetPowerState;
    UltimateReceiverHID_IVars *ivars;
    bool init();void free();bool handleStart(IOService *) override;
    OSDictionary *newDeviceDescription();OSData *newReportDescriptor();
    int Start(IOService *);int Stop(IOService *);int SetPowerState(uint32_t);
    int getReport(IOMemoryDescriptor *,IOHIDReportType,IOOptionBits,uint32_t,OSAction *);
    int setReport(IOMemoryDescriptor *,IOHIDReportType,IOOptionBits,uint32_t,OSAction *);
    void InputComplete(OSAction *,IOReturn,uint32_t,uint64_t);
    void OutputComplete(OSAction *,IOReturn,uint32_t,uint64_t);
    void Tick(OSAction *,uint64_t);
    void QueueInput();void BeginReceiverInput();void ServiceOutput();void PublishNeutral();
    void FinishQuiesceIfReady();void ReleaseTransport();
    int CreateActionInputComplete(int,OSAction **p){
        *p=new OSAction;auto a=*p;a->complete=[this,a](int s,uint32_t n,uint64_t t){InputComplete(a,s,n,t);};return 0;
    }
    int CreateActionOutputComplete(int,OSAction **p){
        *p=new OSAction;auto a=*p;a->complete=[this,a](int s,uint32_t n,uint64_t t){OutputComplete(a,s,n,t);};return 0;
    }
    int CreateActionTick(int,OSAction **p){
        *p=new OSAction;auto a=*p;a->tick=[this,a]{Tick(a,testNow);};return 0;
    }
};
#define super FakeHIDDevice
#define IMPL(C,M) IMPL_##M
#define IMPL_InputComplete UltimateReceiverHID::InputComplete(OSAction *action,IOReturn status,uint32_t actualByteCount,uint64_t completionTimestamp)
#define IMPL_OutputComplete UltimateReceiverHID::OutputComplete(OSAction *action,IOReturn status,uint32_t actualByteCount,uint64_t completionTimestamp)
#define IMPL_Tick UltimateReceiverHID::Tick(OSAction *action,uint64_t time)
#define IMPL_Stop UltimateReceiverHID::Stop(IOService *provider)
#define IMPL_Start UltimateReceiverHID::Start(IOService *provider)
#define IMPL_SetPowerState UltimateReceiverHID::SetPowerState(uint32_t powerFlags)
