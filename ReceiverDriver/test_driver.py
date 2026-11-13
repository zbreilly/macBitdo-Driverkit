#!/usr/bin/env python3
"""Offline protocol and product checks. No device access or activation."""
from pathlib import Path
import argparse
import plistlib
import re
import subprocess
import tempfile

root=Path(__file__).resolve().parent
p=argparse.ArgumentParser()
p.add_argument('--app',type=Path,help='Also inspect a built activation app and its embedded DriverKit executable.')
a=p.parse_args()
legacy_source=(root.parent/'ReceiverBridge/main.m').read_text()
with tempfile.TemporaryDirectory(prefix='receiver-driver-tests-') as directory:
    work=Path(directory)
    # Compile the original C-compatible decoder/encoder bodies as a separate
    # reference, not a second copy of the new driver's implementation.
    original_decode=legacy_source.split('typedef struct { uint16_t buttons;',1)[1].split('// Xbox One S report layout:',1)[0]
    original_encode=legacy_source.split('static uint8_t hat(',1)[1].split('static IOHIDUserDeviceRef virtualDevice;',1)[0]
    reference='#include <stdint.h>\n#include <stddef.h>\n#include <string.h>\ntypedef size_t NSUInteger;\ntypedef int BOOL;\n#define YES 1\n#define NO 0\n'
    reference+='typedef struct { uint16_t buttons;'+original_decode+'\nstatic uint8_t hat('+original_encode
    reference+='\nint legacy_input(const uint8_t *packet,size_t count,uint8_t output[17]){State s;if(!decode(packet,count,&s))return 0;encode(s,output);return 1;}\n'
    (work/'legacy_input.c').write_text(reference)
    subprocess.run(['xcrun','clang','-O2','-Wall','-Wextra','-Werror','-c',str(work/'legacy_input.c'),'-o',str(work/'legacy_input.o')],check=True)
    subprocess.run(['xcrun','clang','-O2','-Wall','-Wextra','-Werror','-c',str(root/'Tests/legacy_reference.c'),'-o',str(work/'legacy.o')],check=True)
    subprocess.run(['xcrun','clang++','-std=c++17','-O2','-Wall','-Wextra','-Werror',str(root/'Tests/protocol_tests.cpp'),str(work/'legacy.o'),str(work/'legacy_input.o'),'-o',str(work/'protocol-tests')],check=True)
    subprocess.run([str(work/'protocol-tests')],check=True)
    # Exercise the actual driver method bodies with deterministic transport
    # callbacks, including failures and cancellation in different orders.
    native=(root/'Driver/UltimateReceiverHID.cpp').read_text()
    native='\n'.join(line for line in native.splitlines() if not line.startswith('#include'))
    harness='#include "FakeDriverKit.h"\n#include "ReceiverProtocol.h"\n'+native+'\n'+(root/'Tests/lifecycle_tests.cpp').read_text()
    (work/'lifecycle.cpp').write_text(harness)
    subprocess.run(['xcrun','clang++','-std=c++17','-fblocks','-O1','-Wall','-Wextra','-Werror',
                    '-I'+str(root/'Tests'),'-I'+str(root/'Driver'),str(work/'lifecycle.cpp'),'-o',str(work/'lifecycle-tests')],check=True)
    subprocess.run([str(work/'lifecycle-tests')],check=True)

protocol=(root/'Driver/ReceiverProtocol.h').read_text()
legacy=(root.parent/'ReceiverBridge/main.m').read_text()
pattern=r'static const uint8_t hidDescriptor\[\]=\{(.*?)\};'
def descriptor(s):
    return bytes(int(x,16) for x in re.findall(r'0x([0-9a-fA-F]{2})',re.search(pattern,s,re.S).group(1)))
raw=descriptor(protocol)
assert raw==descriptor(legacy),'The verified HID descriptor changed during the port'
size=count=report_id=0
bits={};offset=0
while offset<len(raw):
    prefix=raw[offset];offset+=1
    width=(0,1,2,4)[prefix&3]
    value=int.from_bytes(raw[offset:offset+width],'little');offset+=width
    kind=(prefix>>2)&3;tag=prefix>>4
    if kind==1:
        if tag==7:size=value
        elif tag==8:report_id=value
        elif tag==9:count=value
    elif kind==0 and tag in (8,9):bits[tag,report_id]=bits.get((tag,report_id),0)+size*count
assert bits=={(8,1):128,(8,2):8,(9,3):64},bits
print('PASS: original HID descriptor and exact input/output wire lengths')

info=plistlib.loads((root/'Driver/Info.plist').read_bytes())
personalities=info['IOKitPersonalities']
assert len(personalities)==2
for personality in personalities.values():
    assert personality['idVendor']==0x2dc8 and personality['idProduct']==0x3106
assert personalities['Receiver HID Interface']['IOProviderClass']=='IOUSBHostInterface'
assert personalities['Receiver USB Device']['IOProviderClass']=='IOUSBHostDevice'
ent=plistlib.loads((root/'Driver/Driver.entitlements').read_bytes())
assert ent['com.apple.developer.driverkit'] and ent['com.apple.developer.driverkit.family.hid.device']
assert ent['com.apple.developer.driverkit.transport.usb']==[{'idVendor':'*'}]
assert 'com.apple.developer.hid.virtual.device' not in ent
assert not any('IOHIDUserDevice' in x.read_text() for x in (root/'Driver').glob('*.cpp'))
print('PASS: narrow physical matching, development DriverKit capabilities, no app virtual-HID client')

if a.app:
    extensions=list((a.app/'Contents/Library/SystemExtensions').glob('*.dext'))
    assert len(extensions)==1
    extension=extensions[0]
    d=plistlib.loads((extension/'Info.plist').read_bytes())
    assert extension.name==d['CFBundleIdentifier']+'.dext'
    executable=extension/d['CFBundleExecutable']
    architecture=subprocess.run(['/usr/bin/file',str(executable)],capture_output=True,text=True,check=True).stdout
    platform=subprocess.run(['xcrun','vtool','-show-build',str(executable)],capture_output=True,text=True,check=True).stdout
    assert 'arm64e' in architecture and 'platform DRIVERKIT' in platform
    assert not list(a.app.rglob('*LaunchAgent*'))
    print('PASS: embedded arm64e DRIVERKIT executable and activation-app bundle layout')
print('These checks do not establish signing, activation, USB input, rumble, or lifecycle behavior on hardware.')
