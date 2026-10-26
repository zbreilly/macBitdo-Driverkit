// Local HID bridge for 8BitDo receiver 2dc8:3106.
// --service runs under the per-user login agent; no firmware changes.
#import <Foundation/Foundation.h>
#import <IOUSBHost/IOUSBHost.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/IOMessage.h>
#import <IOKit/hidsystem/IOHIDUserDevice.h>
#import <IOKit/hid/IOHIDKeys.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <pthread.h>
#include <mach/mach_time.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <sys/file.h>
#include <unistd.h>
#include <stdatomic.h>
#include <sys/stat.h>
#import <Security/SecTask.h>
#import <GameController/GameController.h>
#import <AppKit/AppKit.h>
#include "Rumble.h"

static volatile sig_atomic_t stopped;
static BOOL sdlProbeRequested,moonlightLaunchRequested;
static BOOL sdlNativeProbeRequested;
static BOOL rumbleTestRequested;
static BOOL sdlRumbleTestRequested;
static BOOL motorChannelTestRequested;
static BOOL serviceMode;
static int instanceLock=-1;
static void stop(int sig) { (void)sig; stopped=1; }
typedef struct { uint16_t buttons; uint8_t lt,rt; int16_t lx,ly,rx,ry; } State;
static int16_t le16(const uint8_t *p) { return (int16_t)((uint16_t)p[0]|((uint16_t)p[1]<<8)); }
static BOOL decode(const uint8_t *p, NSUInteger n, State *s) {
    if(n!=20 || p[0]!=0 || p[1]!=20) return NO;
    *s=(State){(uint16_t)le16(p+2),p[4],p[5],le16(p+6),le16(p+8),le16(p+10),le16(p+12)};
    return YES;
}
// Xbox One S report layout: report 1 = sticks, triggers, hat, buttons, Back;
// report 2 = Guide. Matches Android CTS's captured 045e:02fd descriptor.
// These are virtual-device reports only; the USB/radio input remains XInput.
static const uint8_t hidDescriptor[]={
 0x05,0x01,0x09,0x05,0xa1,0x01,0x85,0x01,
 0x09,0x01,0xa1,0x00,0x09,0x30,0x09,0x31,0x15,0x00,
 0x27,0xff,0xff,0x00,0x00,0x95,0x02,0x75,0x10,0x81,0x02,0xc0,
 0x09,0x01,0xa1,0x00,0x09,0x32,0x09,0x35,0x15,0x00,
 0x27,0xff,0xff,0x00,0x00,0x95,0x02,0x75,0x10,0x81,0x02,0xc0,
 0x05,0x02,0x09,0xc5,0x15,0x00,0x26,0xff,0x03,0x95,0x01,
 0x75,0x0a,0x81,0x02,0x15,0x00,0x25,0x00,0x75,0x06,0x95,0x01,0x81,0x03,
 0x05,0x02,0x09,0xc4,0x15,0x00,0x26,0xff,0x03,0x95,0x01,
 0x75,0x0a,0x81,0x02,0x15,0x00,0x25,0x00,0x75,0x06,0x95,0x01,0x81,0x03,
 0x05,0x01,0x09,0x39,0x15,0x01,0x25,0x08,0x35,0x00,0x46,0x3b,0x01,
 0x66,0x14,0x00,0x75,0x04,0x95,0x01,0x81,0x42,
 0x75,0x04,0x95,0x01,0x15,0x00,0x25,0x00,0x35,0x00,0x45,0x00,0x65,0x00,0x81,0x03,
 0x05,0x09,0x19,0x01,0x29,0x0f,0x15,0x00,0x25,0x01,0x75,0x01,0x95,0x0f,0x81,0x02,
 0x15,0x00,0x25,0x00,0x75,0x01,0x95,0x01,0x81,0x03,
 0x05,0x0c,0x0a,0x24,0x02,0x15,0x00,0x25,0x01,0x95,0x01,0x75,0x01,0x81,0x02,
 0x15,0x00,0x25,0x00,0x75,0x07,0x95,0x01,0x81,0x03,
 0x05,0x0c,0x09,0x01,0x85,0x02,0xa1,0x01,
 0x05,0x0c,0x0a,0x23,0x02,0x15,0x00,0x25,0x01,0x95,0x01,0x75,0x01,0x81,0x02,
 0x15,0x00,0x25,0x00,0x75,0x07,0x95,0x01,0x81,0x03,0xc0,
 // Xbox output report 3: motor mask, four magnitudes, on/delay/loop.
 0x05,0x0f,0x09,0x21,0x85,0x03,0xa1,0x02,
 0x09,0x97,0x15,0x00,0x25,0x01,0x75,0x04,0x95,0x01,0x91,0x02,
 0x25,0x00,0x91,0x03,
 0x09,0x70,0x25,0x64,0x75,0x08,0x95,0x04,0x91,0x02,
 0x09,0x50,0x66,0x01,0x10,0x55,0x0e,0x26,0xff,0x00,0x95,0x01,0x91,0x02,
 0x09,0xa7,0x91,0x02,0x65,0x00,0x55,0x00,0x09,0x7c,0x91,0x02,
 0xc0,0xc0
};
static uint8_t hat(uint16_t b) {
    int x=!!(b&8)-!!(b&4),y=!!(b&2)-!!(b&1);
    if(y<0)return x<0?7:x>0?1:0;
    if(y>0)return x<0?5:x>0?3:4;
    return x<0?6:x>0?2:8;
}
static uint16_t axisUnsigned(int16_t v,BOOL invert) {
    return invert?(uint16_t)(32767-(int32_t)v):(uint16_t)((int32_t)v+32768);
}
static void put16(uint8_t *p,uint16_t v){p[0]=v&255;p[1]=v>>8;}
static void encode(State s,uint8_t out[17]) {
    static const uint16_t bits[]={0x1000,0x2000,0x4000,0x8000,
        0x0100,0x0200,0x0020,0x0010,0x0040,0x0080,0x0400};
    static const uint8_t positions[]={0,1,3,4,6,7,10,11,13,14,12};
    uint16_t buttons=0;
    for(unsigned i=0;i<sizeof(bits)/sizeof(bits[0]);i++)if(s.buttons&bits[i])buttons|=1u<<positions[i];
    memset(out,0,17);out[0]=1;
    put16(out+1,axisUnsigned(s.lx,NO));put16(out+3,axisUnsigned(s.ly,YES));
    put16(out+5,axisUnsigned(s.rx,NO));put16(out+7,axisUnsigned(s.ry,YES));
    put16(out+9,((unsigned)s.lt*1023+127)/255);
    put16(out+11,((unsigned)s.rt*1023+127)/255);
    uint8_t h=hat(s.buttons);out[13]=h==8?0:h+1;
    put16(out+14,buttons);out[16]=!!(s.buttons&0x20);
}
static IOHIDUserDeviceRef virtualDevice;
static pthread_mutex_t reportLock=PTHREAD_MUTEX_INITIALIZER;
static uint8_t latestReport[17];
static uint8_t latestGuide[2]={2,0};
static State latestUSB;
// HID callbacks only store the newest effect. The input thread submits at most
// one asynchronous USB output, so neither HID callbacks nor input block on it.
static pthread_mutex_t rumbleLock=PTHREAD_MUTEX_INITIALIZER;
static IOUSBHostInterface *rumbleInterface;
static IOUSBHostPipe *rumblePipe;
static RumbleEffect rumbleEffect;
static double rumbleStart,rumbleSubmitted;
static BOOL rumbleReady,rumbleInFlight,rumbleFailed,rumbleHaveOutput;
static uint8_t rumbleLow,rumbleHigh;
static unsigned rumbleWrites,rumbleReports;
static double motorTestStart;
static int motorTestPhase=-1;
static double monotonicSeconds(void) {
    static mach_timebase_info_data_t scale;
    static dispatch_once_t once;
    dispatch_once(&once,^{mach_timebase_info(&scale);});
    return mach_absolute_time()*(double)scale.numer/scale.denom/1e9;
}
static IOReturn receiveRumble(IOHIDReportType type,uint32_t reportID,const uint8_t *report,CFIndex length) {
    RumbleEffect effect;
    if(type!=kIOHIDReportTypeOutput||length<0||!decodeRumble(reportID,report,(size_t)length,&effect)){
        static unsigned shown;
        if(shown++<8)printf("Unhandled HID output: type=%u id=%u length=%ld\n",type,reportID,(long)length);
        return kIOReturnUnsupported;
    }
    pthread_mutex_lock(&rumbleLock);
    if(!rumbleReady||rumbleFailed){pthread_mutex_unlock(&rumbleLock);return kIOReturnNotReady;}
    rumbleEffect=effect;rumbleStart=monotonicSeconds();rumbleReports++;
    if(motorChannelTestRequested&&rumbleReports<=16){
        printf("HID rumble id=%u bytes=",reportID);
        for(CFIndex i=0;i<length;i++)printf("%s%02x",i?" ":"",report[i]);
        printf(" -> large=%u small=%u on=%.2fs delay=%.2fs cycles=%u\n",
            effect.low,effect.high,effect.on,effect.delay,effect.cycles);
    }
    pthread_mutex_unlock(&rumbleLock);
    return kIOReturnSuccess;
}
static void serviceRumble(void) {
    pthread_mutex_lock(&rumbleLock);
    if(!rumblePipe||rumbleFailed){pthread_mutex_unlock(&rumbleLock);return;}
    if(rumbleInFlight){
        BOOL timeout=monotonicSeconds()-rumbleSubmitted>1;
        if(timeout)rumbleFailed=YES;
        pthread_mutex_unlock(&rumbleLock);
        if(timeout){
            [rumblePipe abortWithOption:IOUSBHostAbortOptionAsynchronous error:nil];
            puts("Rumble USB timeout; output disabled. Input remains available.");
        }
        return;
    }
    uint8_t low,high;rumbleAt(rumbleEffect,monotonicSeconds()-rumbleStart,&low,&high);
    if(rumbleHaveOutput&&low==rumbleLow&&high==rumbleHigh){pthread_mutex_unlock(&rumbleLock);return;}
    uint8_t bytes[8];encodeRumble(low,high,bytes);
    rumbleInFlight=YES;rumbleSubmitted=monotonicSeconds();
    pthread_mutex_unlock(&rumbleLock);
    NSError *error=nil;
    NSMutableData *buffer=[rumbleInterface ioDataWithCapacity:sizeof(bytes) error:&error];
    if(buffer)memcpy(buffer.mutableBytes,bytes,sizeof(bytes));
    BOOL queued=buffer&&[rumblePipe enqueueIORequestWithData:buffer completionTimeout:0 error:&error
        completionHandler:^(IOReturn status,NSUInteger count){
            (void)buffer; // USB must retain this allocation through cancellation.
            pthread_mutex_lock(&rumbleLock);
            rumbleInFlight=NO;
            BOOL ok=status==kIOReturnSuccess&&count==8;
            if(ok){rumbleHaveOutput=YES;rumbleLow=low;rumbleHigh=high;rumbleWrites++;}
            else rumbleFailed=YES;
            unsigned writes=rumbleWrites;
            pthread_mutex_unlock(&rumbleLock);
            if(!ok)printf("Rumble USB completion failed: status=0x%08x bytes=%lu\n",status,(unsigned long)count);
            else if(!serviceMode&&(writes<=20||!(writes%100)))printf("Rumble USB: low=%u high=%u; output accepted (%u writes)\n",low,high,writes);
        }];
    if(!queued){
        pthread_mutex_lock(&rumbleLock);rumbleInFlight=NO;rumbleFailed=YES;pthread_mutex_unlock(&rumbleLock);
        printf("Rumble USB submit failed: %s\n",error.description.UTF8String?:"allocation failed");
    }
}
static void finishRumble(void) {
    pthread_mutex_lock(&rumbleLock);
    rumbleReady=NO;rumbleEffect=(RumbleEffect){0};
    pthread_mutex_unlock(&rumbleLock);
    // Flush an explicit stop without waiting indefinitely for an OUT transfer.
    double deadline=monotonicSeconds()+1.2;
    while(monotonicSeconds()<deadline){
        serviceRumble();
        pthread_mutex_lock(&rumbleLock);
        BOOL complete=!rumbleInFlight&&rumbleHaveOutput&&!rumbleLow&&!rumbleHigh;
        BOOL failed=rumbleFailed;
        pthread_mutex_unlock(&rumbleLock);
        if(complete||failed)break;
        [NSThread sleepForTimeInterval:.01];
    }
    if(rumblePipe)[rumblePipe abortWithOption:IOUSBHostAbortOptionAsynchronous error:nil];
    pthread_mutex_lock(&rumbleLock);
    if(rumbleInFlight||!rumbleHaveOutput||rumbleLow||rumbleHigh)
        puts("Motor OFF was not confirmed by USB; physical rumble state is unknown.");
    printf("Rumble summary: %u HID commands, %u completed USB writes%s.\n",rumbleReports,rumbleWrites,rumbleFailed?", output error":"");
    pthread_mutex_unlock(&rumbleLock);
}
static BOOL createVirtualDevice(void) {
    SecTaskRef task=SecTaskCreateFromSelf(kCFAllocatorDefault);
    CFErrorRef error=NULL;
    CFTypeRef entitlement=task?SecTaskCopyValueForEntitlement(task,CFSTR("com.apple.developer.hid.virtual.device"),&error):NULL;
    printf("Runtime HID entitlement: %s\n",entitlement&&CFEqual(entitlement,kCFBooleanTrue)?"YES":"NO");
    if(error){CFShow(error);CFRelease(error);}
    if(entitlement)CFRelease(entitlement);
    if(task)CFRelease(task);
    encode((State){0},latestReport);
    GCController.shouldMonitorBackgroundEvents=YES;
    NSDictionary *props=@{@"ReportDescriptor":[NSData dataWithBytes:hidDescriptor length:sizeof(hidDescriptor)],
        @"Product":@"Ultimate 2.4 GHz Local Bridge",@"Manufacturer":@"Local Controller Bridge",
        @"VendorID":@0x045e,@"ProductID":@0x02fd,@"PrimaryUsagePage":@1,@"PrimaryUsage":@5,
        // Match the Bluetooth Xbox report format so SDL selects its Bluetooth
        // parser. This describes the virtual pad, not the physical USB radio.
        @"Transport":@kIOHIDTransportBluetoothValue,@"MaxInputReportSize":@17,@"MaxOutputReportSize":@9};
    virtualDevice=IOHIDUserDeviceCreateWithProperties(kCFAllocatorDefault,
        (__bridge CFDictionaryRef)props,IOHIDUserDeviceOptionsCreateOnActivate);
    if(!virtualDevice){
        puts("Virtual HID creation failed. Use a development-signed build with a profile authorizing com.apple.developer.hid.virtual.device.");
        return NO;
    }
    IOHIDUserDeviceRegisterGetReportBlock(virtualDevice, ^IOReturn(IOHIDReportType type,uint32_t reportID,uint8_t *report,CFIndex *length){
        if(type!=kIOHIDReportTypeInput||(reportID!=1&&reportID!=2))return kIOReturnUnsupported;
        CFIndex size=reportID==1?17:2;
        if(*length<size)return kIOReturnNoSpace;
        pthread_mutex_lock(&reportLock);
        memcpy(report,reportID==1?latestReport:latestGuide,size);
        pthread_mutex_unlock(&reportLock);
        *length=size;return kIOReturnSuccess;
    });
    IOHIDUserDeviceRegisterSetReportBlock(virtualDevice,^IOReturn(IOHIDReportType type,uint32_t reportID,const uint8_t *report,CFIndex length){
        return receiveRumble(type,reportID,report,length);
    });
    IOHIDUserDeviceSetDispatchQueue(virtualDevice,dispatch_queue_create("local.receiver.hid",DISPATCH_QUEUE_SERIAL));
    IOHIDUserDeviceActivate(virtualDevice);
    // macOS forces Transport=Virtual during user-device creation for the
    // developer entitlement. Apply the report-format metadata to the live
    // device through the public property API, then verify what it exposes.
    Boolean transportSet=IOHIDUserDeviceSetProperty(virtualDevice,CFSTR(kIOHIDTransportKey),CFSTR(kIOHIDTransportBluetoothValue));
    CFTypeRef transport=IOHIDUserDeviceCopyProperty(virtualDevice,CFSTR(kIOHIDTransportKey));
    BOOL bluetooth=transport&&CFEqual(transport,CFSTR(kIOHIDTransportBluetoothValue));
    printf("Virtual HID created; Bluetooth transport metadata: %s (setter %s).\n",bluetooth?"verified":"NOT applied",transportSet?"accepted":"rejected");
    if(transport)CFRelease(transport);
    if(!bluetooth){
        IOHIDUserDeviceCancel(virtualDevice);CFRelease(virtualDevice);virtualDevice=NULL;
        return NO;
    }
    return YES;
}
static IOReturn publish(State s) {
    uint8_t report[17];encode(s,report);uint8_t guide[]={2,!!(s.buttons&0x400)};
    pthread_mutex_lock(&reportLock);
    BOOL guideChanged=guide[1]!=latestGuide[1];
    BOOL buttonsChanged=s.buttons!=latestUSB.buttons;
    memcpy(latestReport,report,17);memcpy(latestGuide,guide,2);latestUSB=s;
    pthread_mutex_unlock(&reportLock);
    if(buttonsChanged&&!serviceMode)printf("USB buttons=%04x L3=%d R3=%d Home=%d\n",s.buttons,!!(s.buttons&0x40),!!(s.buttons&0x80),!!(s.buttons&0x400));
    IOReturn result=IOHIDUserDeviceHandleReportWithTimeStamp(virtualDevice,mach_absolute_time(),report,sizeof(report));
    if(result==kIOReturnSuccess&&guideChanged)
        result=IOHIDUserDeviceHandleReportWithTimeStamp(virtualDevice,mach_absolute_time(),guide,sizeof(guide));

    return result;
}
static void cleanupHID(void) {
    if(!virtualDevice)return;
    (void)publish((State){0});
    IOHIDUserDeviceCancel(virtualDevice);CFRelease(virtualDevice);virtualDevice=NULL;
}
static int selfTest(void) {
    if(rumbleSelfTest()){puts("Rumble packet self-test: FAIL");return 1;}
    uint8_t p[20]={0,20,0x11,0x90,255,128,0,128,255,127,255,255,0,0};State s;
    if(!decode(p,20,&s)||s.buttons!=0x9011||s.lt!=255||s.rt!=128||s.lx!=-32768||s.ly!=32767||s.rx!=-1||s.ry!=0)return 1;
    if(decode(p,19,&s))return 1;
    p[0]=1;if(decode(p,20,&s))return 1;
    uint8_t r[17];encode(s,r);
    const uint8_t expected[]={1,0,0,0,0,255,127,255,127,255,3,2,2,1,0x11,8,0};
    if(memcmp(r,expected,17))return 1;
    // Independent wire-layout fixtures: neutral, signed endpoints, all buttons,
    // hat directions and 8-to-10-bit trigger scaling.
    encode((State){0},r);
    const uint8_t neutral[]={1,0,128,255,127,0,128,255,127,0,0,0,0,0,0,0,0};
    if(memcmp(r,neutral,17))return 1;
    encode((State){.lx=32767,.ly=-32768,.rx=-32768,.ry=32767,.lt=255,.rt=255},r);
    const uint8_t endpoints[]={1,255,255,255,255,0,0,0,0,255,3,255,3,0,0,0,0};
    if(memcmp(r,endpoints,17))return 1;
    for(int i=0;i<11;i++){
        const uint16_t bits[]={0x1000,0x2000,0x4000,0x8000,0x100,0x200,0x20,0x10,0x40,0x80,0x400};
        encode((State){.buttons=bits[i]},r);
        const uint8_t positions[]={0,1,3,4,6,7,10,11,13,14,12};
        if((r[14]|(r[15]<<8))!=(1<<positions[i]))return 1;
        if(r[16]!=(i==6))return 1;
    }
    const uint16_t dpad[]={1,9,8,10,2,6,4,5,0,15};
    for(unsigned i=0;i<10;i++){encode((State){.buttons=dpad[i]},r);if(r[13]!=(i<8?i+1:0))return 1;}
    puts("XInput decode, HID mapping, and rumble packet self-test: PASS");return 0;
}
// Diagnostic observer for the SDL libraries shipped in the installed Moonlight.
// It is opt-in; normal bridge startup does not load SDL or launch Moonlight.
static void *sdlLibrary,*sdlPad;
static int (*sdlNum)(void);
static int (*sdlIsPad)(int);
static void *(*sdlOpen)(int);
static void (*sdlPump)(void);
static int16_t (*sdlAxis)(void *,int);
static uint8_t (*sdlButton)(void *,int);
static const char *(*sdlName)(void *);
static void launchMoonlightNative(void) {
    if([NSRunningApplication runningApplicationsWithBundleIdentifier:@"com.moonlight-stream.Moonlight"].count){
        puts("Moonlight already running; compatibility environment cannot be changed in place.");return;
    }
    NSWorkspaceOpenConfiguration *configuration=[NSWorkspaceOpenConfiguration configuration];
    configuration.environment=@{@"SDL_JOYSTICK_HIDAPI_XBOX":@"0",@"SDL_JOYSTICK_MFI":@"1"};
    [[NSWorkspace sharedWorkspace] openApplicationAtURL:[NSURL fileURLWithPath:@"/Applications/Moonlight.app"]
        configuration:configuration completionHandler:^(NSRunningApplication *application,NSError *error){
        if(error)printf("Moonlight compatibility launch failed: %s\n",error.description.UTF8String);
        else printf("Moonlight native-backend launch OK; pid=%d\n",application.processIdentifier);
    }];
}
static BOOL initSDLProbe(void) {
    sdlLibrary=dlopen("/Applications/Moonlight.app/Contents/Frameworks/libSDL2.dylib",RTLD_NOW|RTLD_LOCAL);
    if(!sdlLibrary){printf("Moonlight SDL load failed: %s\n",dlerror());return NO;}
    int (*init)(uint32_t)=dlsym(sdlLibrary,"SDL_InitSubSystem");
    int (*hint)(const char *,const char *)=dlsym(sdlLibrary,"SDL_SetHint");
    const char *(*getHint)(const char *)=dlsym(sdlLibrary,"SDL_GetHint");
    const char *(*error)(void)=dlsym(sdlLibrary,"SDL_GetError");
    sdlNum=dlsym(sdlLibrary,"SDL_NumJoysticks");sdlIsPad=dlsym(sdlLibrary,"SDL_IsGameController");
    sdlOpen=dlsym(sdlLibrary,"SDL_GameControllerOpen");sdlPump=dlsym(sdlLibrary,"SDL_PumpEvents");
    sdlAxis=dlsym(sdlLibrary,"SDL_GameControllerGetAxis");sdlButton=dlsym(sdlLibrary,"SDL_GameControllerGetButton");
    sdlName=dlsym(sdlLibrary,"SDL_GameControllerName");
    if(!init||!hint||!getHint||!error||!sdlNum||!sdlIsPad||!sdlOpen||!sdlPump||!sdlAxis||!sdlButton||!sdlName){puts("SDL probe: missing exported API");return NO;}
    hint("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS","1");
    if(sdlNativeProbeRequested){
        hint("SDL_JOYSTICK_HIDAPI_XBOX","0");
        hint("SDL_JOYSTICK_MFI","1");
        puts("SDL observer test: native backend (Xbox HIDAPI disabled).");
    }else{
        const char *xbox=getHint("SDL_JOYSTICK_HIDAPI_XBOX");
        const char *mfi=getHint("SDL_JOYSTICK_MFI");
        printf("SDL default backend hints: XBOX=%s MFI=%s\n",xbox?xbox:"unset",mfi?mfi:"unset");
        if(xbox||mfi){
            puts("Default SDL probe requires both backend hints unset; remove them from this process's environment and retry.");
            return NO;
        }
        puts("SDL observer test: default backend (no backend overrides).");
    }
    int result=init(0x2000);
    printf("Moonlight SDL init: %d (%s)\n",result,error());
    return result==0;
}
static void checkSDL(void) {
    if(!sdlPump)return;
    sdlPump();
    if(!sdlPad){
        for(int i=0;i<sdlNum();i++)if(sdlIsPad(i)){
            sdlPad=sdlOpen(i);
            if(sdlPad){
                printf("Moonlight SDL opened: %s\n",sdlName(sdlPad));
                int (*hasRumble)(void *)=dlsym(sdlLibrary,"SDL_GameControllerHasRumble");
                printf("Moonlight SDL rumble capability: %s\n",hasRumble?(hasRumble(sdlPad)?"YES":"NO"):"API unavailable");
                char *(*mapping)(void *)=dlsym(sdlLibrary,"SDL_GameControllerMapping");
                void (*release)(void *)=dlsym(sdlLibrary,"SDL_free");
                if(mapping&&release){char *m=mapping(sdlPad);if(m){printf("Moonlight SDL mapping: %s\n",m);release(m);}}
                break;
            }
        }
    }
    if(!sdlPad)return;
    if(sdlRumbleTestRequested){
        static double openedAt;static BOOL attempted;static int previousPhase=-1;
        if(!openedAt)openedAt=monotonicSeconds();
        if(motorChannelTestRequested){
            double elapsed=monotonicSeconds()-openedAt;
            int phase=elapsed<1?-1:elapsed<3?0:elapsed<5?1:elapsed<7?2:3;
            if(phase!=previousPhase){
                previousPhase=phase;
                const char *labels[]={"LARGE / low-frequency only","SMALL / high-frequency only","BOTH","OFF"};
                uint16_t low=(phase==0||phase==2)?65535:0;
                uint16_t high=(phase==1||phase==2)?65535:0;
                int (*rumble)(void *,uint16_t,uint16_t,uint32_t)=dlsym(sdlLibrary,"SDL_GameControllerRumble");
                const char *(*error)(void)=dlsym(sdlLibrary,"SDL_GetError");
                int result=rumble?rumble(sdlPad,low,high,1000):-1;
                printf("SDL motor test: %s; requested low=%u high=%u for 1 second; result=%d error=%s\n",
                    labels[phase],low,high,result,result==0?"none":error?error():"API unavailable");
            }
        }
        if(!motorChannelTestRequested&&!attempted&&monotonicSeconds()-openedAt>=1){
            attempted=YES;
            int (*rumble)(void *,uint16_t,uint16_t,uint32_t)=dlsym(sdlLibrary,"SDL_GameControllerRumble");
            const char *(*error)(void)=dlsym(sdlLibrary,"SDL_GetError");
            int result=rumble?rumble(sdlPad,32768,32768,500):-1;
            printf("Moonlight SDL half-second rumble request: result=%d, error=%s\n",result,
                result==0?"none":error?error():"API unavailable");
        }
    }
    static CFAbsoluteTime next;
    static unsigned previousButtons;
    unsigned buttons=0;for(int i=0;i<15;i++)if(sdlButton(sdlPad,i))buttons|=1u<<i;
    if(CFAbsoluteTimeGetCurrent()<next && buttons==previousButtons)return;
    next=CFAbsoluteTimeGetCurrent()+0.25;previousButtons=buttons;
    printf("Moonlight SDL state: buttons=%04x L=(%d,%d) R=(%d,%d) LT=%d RT=%d\n",buttons,
        sdlAxis(sdlPad,0),sdlAxis(sdlPad,1),sdlAxis(sdlPad,2),sdlAxis(sdlPad,3),sdlAxis(sdlPad,4),sdlAxis(sdlPad,5));
}
static void printGC(GCExtendedGamepad *g,const char *prefix) {
    printf("%s A=%.0f B=%.0f X=%.0f Y=%.0f LB=%.0f RB=%.0f LT=%.2f RT=%.2f L=(%.2f,%.2f) R=(%.2f,%.2f) D=(%.0f,%.0f) L3=%.0f R3=%.0f Home=%.0f Menu=%.0f Back=%.0f\n",
        prefix,g.buttonA.value,g.buttonB.value,g.buttonX.value,g.buttonY.value,
        g.leftShoulder.value,g.rightShoulder.value,g.leftTrigger.value,g.rightTrigger.value,
        g.leftThumbstick.xAxis.value,g.leftThumbstick.yAxis.value,g.rightThumbstick.xAxis.value,g.rightThumbstick.yAxis.value,
        g.dpad.xAxis.value,g.dpad.yAxis.value,
        g.leftThumbstickButton.value,g.rightThumbstickButton.value,g.buttonHome.value,g.buttonMenu.value,g.buttonOptions.value);
}
static void checkProgress(unsigned packets) {
    if(sdlRumbleTestRequested&&monotonicSeconds()-motorTestStart>=10)stopped=1;
    if(rumbleTestRequested&&!stopped){
        double elapsed=monotonicSeconds()-motorTestStart;
        if(elapsed>=(motorChannelTestRequested?10:5)){stopped=1;return;}
        int phase=(int)(elapsed/(motorChannelTestRequested?2:1));
        if(phase!=motorTestPhase){
            motorTestPhase=phase;
            uint8_t strength=motorChannelTestRequested?255:128;
            RumbleEffect effect={.low=(phase==1||phase==3)?strength:0,
                .high=(phase==2||phase==3)?strength:0,.on=motorChannelTestRequested?1:.5,.cycles=1};
            pthread_mutex_lock(&rumbleLock);rumbleEffect=effect;rumbleStart=monotonicSeconds();pthread_mutex_unlock(&rumbleLock);
            const char *labels[]={"initializing / OFF","LARGE / low-frequency only","SMALL / high-frequency only","BOTH","OFF"};
            printf("Motor test: %s\n",labels[phase]);
        }
    }
    serviceRumble();
    if(rumbleTestRequested)return;
    [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.0001]];
    if(serviceMode)return;
    checkSDL();
    if(sdlLibrary)return; // SDL owns its GameController callbacks during this comparison.
    static NSHashTable *observed;
    if(!observed)observed=[NSHashTable weakObjectsHashTable];
    NSArray<GCController *> *controllers=GCController.controllers;
    for(GCController *c in controllers){
        if([observed containsObject:c])continue;
        [observed addObject:c];
        GCControllerButtonInput *home=c.physicalInputProfile.buttons[GCInputButtonHome];
        printf("Home capability: physical=%s legacy=%s systemGesture=%s\n",home?"YES":"NO",c.extendedGamepad.buttonHome?"YES":"NO",home.isBoundToSystemGesture?"YES":"NO");
        if(home){
            home.preferredSystemGestureState=GCSystemGestureStateDisabled;
            home.pressedChangedHandler=^(GCControllerButtonInput *button,float value,BOOL pressed){
                (void)button;printf("GC physical Home: pressed=%d value=%.0f\n",pressed,value);
            };
        }
        printf("Controller haptics: %s; localities=%s\n",c.haptics?"YES":"NO",c.haptics.supportedLocalities.description.UTF8String?:"none");
        c.extendedGamepad.valueChangedHandler=^(GCExtendedGamepad *g,GCControllerElement *element){
            static CFAbsoluteTime lastPrint;
            if(![element isKindOfClass:GCControllerButtonInput.class] && CFAbsoluteTimeGetCurrent()-lastPrint<0.1)return;
            lastPrint=CFAbsoluteTimeGetCurrent();printGC(g,"GC input:");
        };
    }
    static NSDate *next;
    if(next && next.timeIntervalSinceNow>0)return;
    next=[NSDate dateWithTimeIntervalSinceNow:5];
    printf("Bridge v2: %u forwarded reports; GameController devices: %lu\n",packets,(unsigned long)controllers.count);
    printf("USB state: buttons=%04x LT=%u RT=%u L=(%d,%d) R=(%d,%d)\n",latestUSB.buttons,latestUSB.lt,latestUSB.rt,latestUSB.lx,latestUSB.ly,latestUSB.rx,latestUSB.ry);
    for(GCController *c in controllers){
        printf("  %s; extended gamepad: %s\n",c.vendorName.UTF8String?:"Unnamed",c.extendedGamepad?"YES":"NO");
        if(c.extendedGamepad)printGC(c.extendedGamepad,"GC state:");
    }
}
static io_service_t findInterface(io_service_t device) {
    io_iterator_t it=0; io_service_t result=0;
    if(IORegistryEntryGetChildIterator(device,kIOServicePlane,&it)!=KERN_SUCCESS) return 0;
    io_registry_entry_t c;
    while((c=IOIteratorNext(it))) {
        if(IOObjectConformsTo(c,"IOUSBHostInterface")){result=c;break;}
        IOObjectRelease(c);
    }
    IOObjectRelease(it);return result;
}
static void setPlayerIndicator(IOUSBHostInterface *interface) {
    NSError *error=nil;
    IOUSBHostPipe *output=[interface copyPipeWithAddress:0x02 error:&error];
    NSMutableData *command=[interface ioDataWithCapacity:3 error:&error];
    if(!output||!command){printf("Player indicator setup failed: %s\n",error.description.UTF8String);return;}
    const uint8_t bytes[]={0x01,0x03,0x02};
    memcpy(command.mutableBytes,bytes,sizeof(bytes));
    dispatch_semaphore_t done=dispatch_semaphore_create(0);
    __block IOReturn status=kIOReturnError;__block NSUInteger count=0;
    if(![output enqueueIORequestWithData:command completionTimeout:0 error:&error completionHandler:^(IOReturn result,NSUInteger transferred){
        (void)command;status=result;count=transferred;dispatch_semaphore_signal(done);
    }]){printf("Player indicator submit failed: %s\n",error.description.UTF8String);return;}
    if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))!=0){
        [output abortWithOption:IOUSBHostAbortOptionAsynchronous error:&error];
        dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC));
        puts("Player indicator output timed out; continuing input capture.");return;
    }
    printf("Player indicator command 01 03 02: status=0x%08x, bytes=%lu\n",(unsigned)status,(unsigned long)count);
}
int main(int argc,const char **argv) { @autoreleasepool {
    setbuf(stdout,NULL);
    if(argc==2&&!strcmp(argv[1],"--self-test")) return selfTest();
    if(argc==2&&!strcmp(argv[1],"--virtual-test")){BOOL ok=createVirtualDevice();cleanupHID();return ok?0:1;}
    // Xcode adds Foundation launch preferences when running an app bundle.
    for(int i=1;i<argc;i++){
        if(!strcmp(argv[i],"--service")){serviceMode=YES;continue;}
        if(!strcmp(argv[i],"--sdl-probe")){sdlProbeRequested=YES;continue;}
        if(!strcmp(argv[i],"--sdl-probe-native")){sdlProbeRequested=YES;sdlNativeProbeRequested=YES;continue;}
        if(!strcmp(argv[i],"--moonlight-compat")){moonlightLaunchRequested=YES;continue;}
        if(!strcmp(argv[i],"--rumble-test")){rumbleTestRequested=YES;continue;}
        if(!strcmp(argv[i],"--sdl-rumble-test")){sdlProbeRequested=YES;sdlRumbleTestRequested=YES;continue;}
        if(!strcmp(argv[i],"--sdl-motor-test")){sdlProbeRequested=YES;sdlRumbleTestRequested=YES;motorChannelTestRequested=YES;continue;}
        if(!strcmp(argv[i],"--usb-motor-test")){rumbleTestRequested=YES;motorChannelTestRequested=YES;continue;}
        if(!strncmp(argv[i],"-NS",3)||!strcmp(argv[i],"-ApplePersistenceIgnoreState")){
            if(i+1<argc)i++;
            continue;
        }
        if(!strncmp(argv[i],"-psn_",5))continue;
        fprintf(stderr,"Unknown option: %s\nUsage: %s [--service | --self-test | --virtual-test | --sdl-probe | --sdl-probe-native | --moonlight-compat | --rumble-test | --sdl-rumble-test | --sdl-motor-test | --usb-motor-test]\n",argv[i],argv[0]);return 2;
    }
    if(serviceMode&&(rumbleTestRequested||sdlProbeRequested||moonlightLaunchRequested)){
        fputs("--service cannot be combined with diagnostic or Moonlight launch options.\n",stderr);return 2;
    }
    if(rumbleTestRequested&&(sdlProbeRequested||moonlightLaunchRequested)){
        fputs("--rumble-test cannot be combined with SDL/Moonlight options.\n",stderr);return 2;
    }
    signal(SIGINT,stop);signal(SIGTERM,stop);
    // One service instance per login session. A stale lock file is harmless:
    // the kernel releases flock on process exit; never unlink a held lock.
    if(serviceMode){
        // launchd directs both streams to our event log. Bound disk use on
        // restarts; per-input logging is disabled in service mode.
        struct stat logInfo;
        if(fstat(STDOUT_FILENO,&logInfo)==0&&S_ISREG(logInfo.st_mode)&&logInfo.st_size>1024*1024)
            (void)ftruncate(STDOUT_FILENO,0);
        NSString *lockPath=[NSTemporaryDirectory() stringByAppendingPathComponent:@"com.zbreilly.ReceiverBridge.lock"];
        instanceLock=open(lockPath.fileSystemRepresentation,O_CREAT|O_RDWR|O_CLOEXEC|O_NOFOLLOW,0600);
        if(instanceLock<0||flock(instanceLock,LOCK_EX|LOCK_NB)!=0){
            fputs("Another service is already running, or the instance lock is unavailable.\n",stderr);return 1;
        }
    }
    atexit(cleanupHID);
    // Don't publish a phantom controller at login when the receiver is absent.
    // launchd restarts us after USB removal or a failed open; this wait then
    // sleeps until the physical receiver reappears, without spinning/relaunching.
    if(serviceMode){
        puts("ReceiverBridge 1.0: waiting for receiver 2dc8:3106.");
        while(!stopped){@autoreleasepool{
            CFMutableDictionaryRef waitingMatch=IOServiceMatching("IOUSBHostDevice");
            if(!waitingMatch){fputs("USB matching allocation failed.\n",stderr);return 1;}
            CFDictionarySetValue(waitingMatch,CFSTR("idVendor"),(__bridge CFNumberRef)@0x2dc8);
            CFDictionarySetValue(waitingMatch,CFSTR("idProduct"),(__bridge CFNumberRef)@0x3106);
            io_service_t found=IOServiceGetMatchingService(kIOMainPortDefault,waitingMatch);
            if(found){IOObjectRelease(found);break;}
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:1]];
        }}
        if(stopped)return 0;
    }
    if(!rumbleTestRequested&&!createVirtualDevice())return 1;
    if(sdlProbeRequested&&!initSDLProbe())return 1;
    if(moonlightLaunchRequested)launchMoonlightNative();
    NSMutableDictionary *match=[@{@"IOProviderClass":@"IOUSBHostDevice",@"idVendor":@0x2dc8,@"idProduct":@0x3106} mutableCopy];
    io_service_t svc=IOServiceGetMatchingService(kIOMainPortDefault,(__bridge_retained CFDictionaryRef)match);
    if(!svc){puts("Receiver 2dc8:3106 absent. Keep it connected in its current XInput mode.");return 1;}
    NSError *e=nil;
    __block atomic_int receiverRemoved;
    atomic_init(&receiverRemoved,0);
    IOUSBHostDevice *device=[[IOUSBHostDevice alloc] initWithIOService:svc options:IOUSBHostObjectInitOptionsNone queue:nil error:&e interestHandler:^(IOUSBHostObject *object,uint32_t message,void *argument){
        (void)object;(void)argument;
        if(message==kIOMessageServiceIsTerminated)atomic_store(&receiverRemoved,1);
    }];
    if(!device){printf("USB device access failed: %s\n",e.description.UTF8String);IOObjectRelease(svc);return 1;}
    printf("USB device access: OK; currently configured: %s\n",device.configurationDescriptor?"yes":"no");
    const IOUSBConfigurationDescriptor *cfg=[device configurationDescriptorWithIndex:0 error:&e];
    if(!cfg||cfg->bConfigurationValue!=1||cfg->bNumInterfaces!=1){puts("Unexpected USB configuration; stopping.");[device destroy];IOObjectRelease(svc);return 1;}
    if(!device.configurationDescriptor && ![device configureWithValue:1 matchInterfaces:YES error:&e]){
        printf("Configure failed: %s\n",e.description.UTF8String);[device destroy];IOObjectRelease(svc);return 1;
    }
    io_service_t isvc=0;
    // Registration may finish after configure returns. Wait at most two seconds.
    for(int i=0;i<100&&!stopped;i++){isvc=findInterface(svc);if(isvc)break;[NSThread sleepForTimeInterval:0.02];}
    IOObjectRelease(svc);
    if(!isvc){puts("Configured, but interface 0 did not register.");[device destroy];return 1;}
    IOUSBHostInterface *interface=[[IOUSBHostInterface alloc] initWithIOService:isvc options:IOUSBHostObjectInitOptionsNone queue:nil error:&e interestHandler:nil];
    IOObjectRelease(isvc);
    if(!interface){printf("Interface access failed: %s\n",e.description.UTF8String);[device destroy];return 1;}
    const IOUSBInterfaceDescriptor *id=interface.interfaceDescriptor;
    if(id->bInterfaceNumber!=0||id->bInterfaceClass!=255||id->bInterfaceSubClass!=0x5d||id->bInterfaceProtocol!=1){puts("Unexpected interface; stopping.");[interface destroy];[device destroy];return 1;}
    IOUSBHostPipe *pipe=[interface copyPipeWithAddress:0x81 error:&e];
    if(!pipe){printf("Input endpoint failed: %s\n",e.description.UTF8String);[interface destroy];[device destroy];return 1;}
    NSMutableData *data=[interface ioDataWithCapacity:32 error:&e];
    if(!data){printf("Input buffer allocation failed: %s\n",e.description.UTF8String);[interface destroy];[device destroy];return 1;}
    puts(rumbleTestRequested?(motorChannelTestRequested?"Receiver motor-channel test: USB only; exits after 10 seconds.":"Receiver rumble test: USB only, no virtual controller or Moonlight; exits after 5 seconds."):
        "ReceiverBridge 1.0: input and two-motor rumble active.");
    setPlayerIndicator(interface);
    rumblePipe=[interface copyPipeWithAddress:0x02 error:&e];
    if(!rumblePipe){printf("Rumble output endpoint unavailable: %s\n",e.description.UTF8String);}
    else {rumbleInterface=interface;pthread_mutex_lock(&rumbleLock);rumbleReady=YES;pthread_mutex_unlock(&rumbleLock);}
    if(rumbleTestRequested&&!rumblePipe){[interface destroy];[device destroy];return 1;}
    puts(rumbleTestRequested?"Expected: LEFT pulse, RIGHT pulse, BOTH pulse, then OFF. Hold the paired controller.":
        "Forwarding endpoint 0x81 to virtual HID until Ctrl-C or disconnect.");
    unsigned packets=0,decoded=0;
    BOOL startupSent=NO;
    motorTestStart=monotonicSeconds();
    while(!stopped&&!atomic_load(&receiverRemoved)){@autoreleasepool{
        checkProgress(decoded);
        if(stopped)break;
        // Interrupt pipes require completionTimeout == 0. Use asynchronous I/O
        // so Ctrl-C can cancel a silent receiver.
        dispatch_semaphore_t done=dispatch_semaphore_create(0);
        __block NSUInteger count=0;__block IOReturn status=kIOReturnError;e=nil;
        if(![pipe enqueueIORequestWithData:data completionTimeout:0 error:&e completionHandler:^(IOReturn result,NSUInteger transferred){
            (void)data; // Retain the backing buffer through completion.
            status=result;count=transferred;dispatch_semaphore_signal(done);
        }]){
            printf("USB submit failed: %s\n",e.description.UTF8String);break;
        }
        if(!startupSent){
            startupSent=YES;
            // Same USB transaction used by Linux xpad's xpad_start_input:
            // vendor/interface IN, request 1, value 0x100, index 0, length 20.
            // Queue input first, matching the driver's startup ordering.
            NSError *startupError=nil;NSUInteger replyLength=0;
            NSMutableData *reply=[device ioDataWithCapacity:20 error:&startupError];
            IOUSBDeviceRequest request={.bmRequestType=0xc1,.bRequest=0x01,
                .wValue=CFSwapInt16HostToLittle(0x0100),.wIndex=0,
                .wLength=CFSwapInt16HostToLittle(20)};
            if(reply&&[device sendDeviceRequest:request data:reply bytesTransferred:&replyLength completionTimeout:1 error:&startupError]){
                printf("XInput startup response (%lu bytes):",(unsigned long)replyLength);
                const uint8_t *bytes=reply.bytes;for(NSUInteger i=0;i<MIN(replyLength,reply.length);i++)printf(" %02x",bytes[i]);puts("");
            }else printf("XInput startup request failed: %s (continuing input capture)\n",startupError.description.UTF8String);
        }
        BOOL cancelled=NO;
        while(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,10*NSEC_PER_MSEC))!=0){
            checkProgress(decoded);
            if(stopped||atomic_load(&receiverRemoved)){
                NSError *abortError=nil;
                if(![pipe abortWithOption:IOUSBHostAbortOptionAsynchronous error:&abortError])
                    printf("Abort failed: %s\n",abortError.description.UTF8String);
                // The completion block owns its buffer until completion. A
                // bounded drain avoids waiting indefinitely on device removal.
                if(dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC))!=0)
                    puts("Cancelled; completion did not drain within one second.");
                cancelled=YES;break;
            }
        }
        if(cancelled)break;
        if(status!=kIOReturnSuccess){printf("USB completion failed: 0x%08x\n",(unsigned)status);break;}
        if(count>data.length){puts("Invalid transfer byte count; stopping.");break;}
        packets++;const uint8_t *p=data.bytes;State s;
        if(decode(p,count,&s)){
            decoded++;
            IOReturn result=rumbleTestRequested?kIOReturnSuccess:publish(s);
            if(result!=kIOReturnSuccess){printf("HID report failed: 0x%08x\n",(unsigned)result);break;}
        }else if(packets<=10){printf("Other packet (%lu bytes):",(unsigned long)count);for(NSUInteger i=0;i<count;i++)printf(" %02x",p[i]);puts("");}
    }}
    printf("Summary: %u USB packets, %u valid XInput reports.\n",packets,decoded);
    if(virtualDevice)(void)publish((State){0});
    finishRumble();
    [interface destroy];[device destroy];
    pthread_mutex_lock(&rumbleLock);BOOL outputFailed=rumbleFailed;pthread_mutex_unlock(&rumbleLock);
    return (stopped&&!outputFailed)?0:1;
}}
