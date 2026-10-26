#!/usr/bin/env python3
"""Build the signed local bridge and a self-contained per-user install package."""
import argparse
import pathlib
import shutil
import subprocess
import zipfile

root = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path('/tmp/ReceiverBridge-1.1'))
parser.add_argument('--derived-data', type=pathlib.Path, default=pathlib.Path('/tmp/ReceiverBridge-release-build'))
parser.add_argument('--team', help='Apple Developer team ID (overrides the Xcode project default)')
parser.add_argument('--bundle-id', help='Provisioned App ID (overrides the Xcode project default)')
parser.add_argument('--allow-provisioning-updates', action='store_true',
                    help='Allow Xcode to contact Apple for signing assets')
args = parser.parse_args()
output = args.output.resolve()
if output.exists():
    raise SystemExit(f'Refusing to overwrite existing package: {output}')
derived_data = args.derived_data.resolve()
command = ['xcodebuild', '-quiet', '-project', str(root / 'ReceiverBridge.xcodeproj'),
           '-scheme', 'ReceiverBridge', '-configuration', 'Debug',
           '-destination', 'platform=macOS,arch=arm64', '-derivedDataPath', str(derived_data)]
if args.team:
    command.append(f'DEVELOPMENT_TEAM={args.team}')
if args.bundle_id:
    command.append(f'PRODUCT_BUNDLE_IDENTIFIER={args.bundle_id}')
if args.allow_provisioning_updates:
    command.append('-allowProvisioningUpdates')
subprocess.run(command + ['build'], check=True)
built = derived_data / 'Build/Products/Debug/ReceiverBridge.app'
output.mkdir(parents=True)
shutil.copytree(built, output / 'ReceiverBridge.app')
for name in ('Install.command', 'Status.command', 'Uninstall.command'):
    shutil.copy2(root / name, output / name)
    (output / name).chmod(0o755)
shutil.copy2(root / 'INSTALL.md', output / 'README.md')
shutil.copytree(root, output / 'Source',
                ignore=shutil.ignore_patterns('xcuserdata', '.DS_Store', '__pycache__', 'build',
                                             '.git', '*.p12', '*.key', '*.pem',
                                             '*.provisionprofile', '*.mobileprovision',
                                             '*.app', '*.pkg', '*.zip'))
subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(output / 'ReceiverBridge.app')], check=True)
subprocess.run([str(output / 'ReceiverBridge.app/Contents/MacOS/ReceiverBridge'), '--self-test'], check=True)
subprocess.run(['/bin/zsh', str(output / 'Install.command'), '--check'], check=True)
archive = pathlib.Path(str(output) + '.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for path in sorted(output.rglob('*')):
        if path.is_file():
            z.write(path, path.relative_to(output.parent))
print(f'Package: {output}\nArchive: {archive}')
