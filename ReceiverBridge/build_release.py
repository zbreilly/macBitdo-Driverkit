#!/usr/bin/env python3
"""Build the signed local bridge and a self-contained per-user install package."""
import argparse
import pathlib
import plistlib
import re
import shutil
import subprocess
import zipfile

root = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument('--output', type=pathlib.Path, default=pathlib.Path('/tmp/ReceiverBridge-1.0'))
parser.add_argument('--derived-data', type=pathlib.Path, default=pathlib.Path('/tmp/ReceiverBridge-release-build'))
args = parser.parse_args()
output = args.output.resolve()
if output.exists():
    raise SystemExit(f'Refusing to overwrite existing package: {output}')
subprocess.run(['xcodebuild', '-quiet', '-project', str(root / 'ReceiverBridge.xcodeproj'),
                '-scheme', 'ReceiverBridge', '-configuration', 'Debug',
                '-derivedDataPath', str(args.derived_data), 'build'], check=True)
built = args.derived_data / 'Build/Products/Debug/ReceiverBridge.app'
identity_output = subprocess.run(['/usr/bin/codesign', '-dv', '--verbose=4', str(built)],
                                 capture_output=True, text=True, check=True).stderr
identity = re.search(r'^Authority=(.+)$', identity_output, re.MULTILINE)
if not identity:
    raise SystemExit('The bridge has no usable development signing identity.')
output.mkdir(parents=True)
shutil.copytree(built, output / 'ReceiverBridge.app')
launcher = output / 'Moonlight for 8BitDo.app/Contents'
(launcher / 'MacOS').mkdir(parents=True)
(launcher / 'Resources').mkdir()
with (launcher / 'Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleIdentifier': 'com.zbreilly.ReceiverBridge.Moonlight',
                  'CFBundleExecutable': 'MoonlightLauncher',
                  'CFBundleName': 'Moonlight for 8BitDo',
                  'CFBundlePackageType': 'APPL', 'CFBundleShortVersionString': '1.0',
                  'CFBundleVersion': '10', 'LSMinimumSystemVersion': '13.0',
                  'LSUIElement': True, 'CFBundleIconFile': 'moonlight.icns'}, f)
icon = pathlib.Path('/Applications/Moonlight.app/Contents/Resources/moonlight.icns')
if icon.exists():
    shutil.copy2(icon, launcher / 'Resources/moonlight.icns')
subprocess.run(['xcrun', 'clang', '-Wall', '-Wextra', '-Werror', '-fobjc-arc', '-fblocks',
                '-mmacosx-version-min=13.0', str(root / 'MoonlightLauncher.m'),
                '-framework', 'Foundation', '-framework', 'AppKit',
                '-o', str(launcher / 'MacOS/MoonlightLauncher')], check=True)
subprocess.run(['/usr/bin/codesign', '--force', '--sign', identity.group(1),
                '--timestamp=none', str(launcher.parent)], check=True)
for name in ('Install.command', 'Status.command', 'Uninstall.command'):
    shutil.copy2(root / name, output / name)
    (output / name).chmod(0o755)
shutil.copy2(root / 'INSTALL.md', output / 'README.md')
shutil.copytree(root, output / 'Source',
                ignore=shutil.ignore_patterns('xcuserdata', '.DS_Store', '__pycache__', 'build'))
for app in (output / 'ReceiverBridge.app', launcher.parent):
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
subprocess.run([str(output / 'ReceiverBridge.app/Contents/MacOS/ReceiverBridge'), '--self-test'], check=True)
subprocess.run(['/bin/zsh', str(output / 'Install.command'), '--check'], check=True)
archive = pathlib.Path(str(output) + '.zip')
with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as z:
    for path in sorted(output.rglob('*')):
        if path.is_file():
            z.write(path, path.relative_to(output.parent))
print(f'Package: {output}\nArchive: {archive}')
