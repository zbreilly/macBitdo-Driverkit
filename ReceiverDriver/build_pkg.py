#!/usr/bin/env python3
"""Package a signed development DriverKit host; refuse unsigned prototypes."""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess
import tempfile

p=argparse.ArgumentParser()
p.add_argument('--app',type=Path,required=True)
p.add_argument('--output',type=Path,required=True)
a=p.parse_args();app=a.app.resolve()
extensions=list((app/'Contents/Library/SystemExtensions').glob('*.dext'))
if len(extensions)!=1:raise SystemExit('Expected exactly one embedded DriverKit extension.')
dext=extensions[0]
for code,profile in [(app,app/'Contents/embedded.provisionprofile'),(dext,dext/'embedded.provisionprofile')]:
    if not profile.is_file():raise SystemExit(f'Missing development provisioning profile: {profile}. Build and sign in Xcode first.')
    subprocess.run(['/usr/bin/codesign','--verify','--deep','--strict',str(code)],check=True)
with tempfile.TemporaryDirectory(prefix='receiver-driver-pkg-') as directory:
    work=Path(directory);payload=work/'payload';payload.mkdir()
    shutil.copytree(app,payload/app.name)
    components=work/'components.plist'
    subprocess.run(['pkgbuild','--analyze','--root',str(payload),str(components)],check=True)
    items=plistlib.loads(components.read_bytes())
    for item in items:
        item['BundleIsRelocatable']=False
        item['BundleHasStrictIdentifier']=True
    components.write_bytes(plistlib.dumps(items))
    subprocess.run(['pkgbuild','--root',str(payload),'--component-plist',str(components),
        '--identifier','com.zbreilly.macBitdo.DriverHost.installer','--version','0.1',
        '--install-location','/Applications',str(a.output.resolve())],check=True)
print('Package built. Open /Applications/macBitdo Driver.app and request activation; macOS approval is still required.')
print('The package is not distribution-signed/notarized. This development build is for provisioned devices only.')
