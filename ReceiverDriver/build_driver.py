#!/usr/bin/env python3
"""Build the DriverKit extension and its activation app (never activates it)."""
from pathlib import Path
import argparse
import subprocess

root=Path(__file__).resolve().parent
p=argparse.ArgumentParser()
p.add_argument('--unsigned',action='store_true',help='Compile only; the app cannot activate the unsigned driver.')
p.add_argument('--allow-provisioning-updates',action='store_true',help='Allow Xcode to use the existing developer account to obtain development profiles.')
p.add_argument('--derived-data',type=Path,default=Path('/tmp/ReceiverDriver-build'))
p.add_argument('--configuration',choices=('Debug','Release'),default='Debug')
a=p.parse_args()
cmd=['xcodebuild','-quiet','-project',str(root/'ReceiverDriver.xcodeproj'),'-scheme','macBitdo Driver',
     '-configuration',a.configuration,'-derivedDataPath',str(a.derived_data)]
if a.unsigned:cmd+=['CODE_SIGNING_ALLOWED=NO','CODE_SIGNING_REQUIRED=NO']
elif a.allow_provisioning_updates:cmd+=['-allowProvisioningUpdates']
subprocess.run(cmd+['build'],check=True)
print(a.derived_data/'Build/Products'/a.configuration/'macBitdo Driver.app')
if a.unsigned:print('Compile-only result: not signed, not activated, not hardware-tested.')
