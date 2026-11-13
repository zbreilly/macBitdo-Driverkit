#include <DriverKit/IOLib.h>
#include <USBDriverKit/IOUSBHostDevice.h>
#include <USBDriverKit/USBDriverKitDefs.h>
#include <os/log.h>
#include "UltimateReceiverDevice.h"
#include "ReceiverProtocol.h"

kern_return_t IMPL(UltimateReceiverDevice, Start) {
    kern_return_t result=Start(provider,SUPERDISPATCH);
    if(result!=kIOReturnSuccess)return result;
    auto device=OSDynamicCast(IOUSBHostDevice,provider);
    if(!device)return kIOReturnBadArgument;
    result=device->Open(this,0,0);
    if(result!=kIOReturnSuccess)return result;
    const auto descriptor=device->CopyDeviceDescriptor();
    bool expected=descriptor&&descriptor->idVendor==ReceiverProtocol::Vendor&&
        descriptor->idProduct==ReceiverProtocol::Product;
    if(descriptor)IOUSBHostFreeDescriptor(descriptor);
    if(expected)result=device->SetConfiguration(1,true);
    else result=kIOReturnUnsupported;
    device->Close(this,0);
    os_log(OS_LOG_DEFAULT,"macBitdo: receiver configuration result 0x%x",result);
    return result;
}

kern_return_t IMPL(UltimateReceiverDevice, Stop) {
    return Stop(provider,SUPERDISPATCH);
}
