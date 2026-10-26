#!/usr/bin/env python3
"""Package the existing signed release for a CurrentUserHome Installer domain."""
import argparse
import pathlib
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

source = pathlib.Path(__file__).resolve().parent
p = argparse.ArgumentParser()
p.add_argument('--release', type=pathlib.Path, default=pathlib.Path('/tmp/ReceiverBridge-1.0'))
p.add_argument('--output', type=pathlib.Path, default=pathlib.Path('/tmp/ReceiverBridge-1.0.pkg'))
args = p.parse_args()
release = args.release.resolve()
output = args.output.resolve()
identifier = 'com.zbreilly.ReceiverBridge.installer'
for app in ('ReceiverBridge.app', 'Moonlight for 8BitDo.app'):
    subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(release / app)], check=True)
with tempfile.TemporaryDirectory(prefix='receiver-pkg-build-') as temporary:
    work = pathlib.Path(temporary)
    payload = work / 'payload'
    support = payload / 'Library/Application Support/ReceiverBridge'
    applications = payload / 'Applications'
    support.mkdir(parents=True)
    applications.mkdir()
    shutil.copytree(release / 'ReceiverBridge.app', support / 'ReceiverBridge.app')
    shutil.copytree(release / 'Moonlight for 8BitDo.app', applications / 'Moonlight for 8BitDo.app')
    for name in ('Status.command', 'Uninstall.command'):
        shutil.copy2(source / name, support / name)
        (support / name).chmod(0o755)
    shutil.copy2(source / 'PKG-INSTALL.md', support / 'README.md')
    # Keep source plist files inside an archive so pkgbuild does not mistake
    # the source tree's Info.plist for another installable application bundle.
    with zipfile.ZipFile(support / 'Source.zip', 'w', zipfile.ZIP_DEFLATED) as z:
        for path in sorted(source.rglob('*')):
            if path.is_file() and not any(part.startswith('.') or part in ('xcuserdata', '__pycache__', 'build')
                                          for part in path.relative_to(source).parts):
                z.write(path, pathlib.Path('ReceiverBridge') / path.relative_to(source))
    scripts = work / 'scripts'
    scripts.mkdir()
    for name in ('preinstall', 'postinstall'):
        shutil.copy2(source / 'pkg-scripts' / name, scripts / name)
        (scripts / name).chmod(0o755)
        subprocess.run(['/bin/zsh', '-n', str(scripts / name)], check=True)
    component_plist = work / 'components.plist'
    subprocess.run(['/usr/bin/pkgbuild', '--analyze', '--root', str(payload), str(component_plist)], check=True)
    components = plistlib.loads(component_plist.read_bytes())
    for component in components:
        # Never relocate onto an older prototype with the same bundle ID.
        component['BundleIsRelocatable'] = False
        component['BundleIsVersionChecked'] = False
        component['BundleHasStrictIdentifier'] = True
        component['BundleOverwriteAction'] = 'upgrade'
    component_plist.write_bytes(plistlib.dumps(components))
    component_pkg = work / 'ReceiverBridge-component.pkg'
    subprocess.run(['/usr/bin/pkgbuild', '--root', str(payload), '--component-plist', str(component_plist),
                    '--scripts', str(scripts), '--identifier', identifier, '--version', '1.0',
                    '--install-location', '/', '--ownership', 'recommended', str(component_pkg)], check=True)
    resources = work / 'resources'
    resources.mkdir()
    (resources / 'welcome.html').write_text('''<!doctype html><html><body>
<h1>ReceiverBridge</h1><p>8BitDo Ultimate 2.4 GHz receiver support for this Mac.</p>
<p>Installs a silent background service with login startup, automatic USB
reconnection, and the Moonlight for 8BitDo launcher. Input and both rumble
motors retain the settings verified during testing.</p>
<p>Install for your user account. Quit Moonlight first.</p>
<p>The apps are development-signed. This installer package is unsigned and
is intended for local use on this provisioned Mac.</p></body></html>''')
    (resources / 'conclusion.html').write_text('''<!doctype html><html><body>
<h1>Ready to play</h1><p>The bridge runs in the background now and at login.
No Terminal or Xcode window is required.</p><p>Open <strong>Moonlight for 8BitDo</strong>
in your home Applications folder. You can drag it to the Dock.</p>
<p>Reconnect the receiver once and confirm input and rumble after reconnection.</p>
<p>Status and Uninstall commands are in Library/Application Support/ReceiverBridge
inside your home folder. The development profile expires October 26, 2027.</p></body></html>''')
    distribution = ET.Element('installer-gui-script', {'minSpecVersion': '2'})
    ET.SubElement(distribution, 'title').text = 'ReceiverBridge 1.0'
    ET.SubElement(distribution, 'options', {'customize': 'never', 'require-scripts': 'true', 'hostArchitectures': 'arm64'})
    ET.SubElement(distribution, 'domains', {'enable_anywhere': 'false', 'enable_currentUserHome': 'true', 'enable_localSystem': 'false'})
    ET.SubElement(distribution, 'welcome', {'file': 'welcome.html', 'mime-type': 'text/html'})
    ET.SubElement(distribution, 'conclusion', {'file': 'conclusion.html', 'mime-type': 'text/html'})
    ET.SubElement(distribution, 'installation-check', {'script': 'checkHost()'})
    ET.SubElement(distribution, 'script').text = '''
function checkHost() {
    if (system.compareVersions(system.version.ProductVersion, '13.0') < 0) {
        my.result.type='Fatal'; my.result.message='macOS 13 or newer is required.'; return false;
    }
    if (!system.files.fileExistsAtPath('/Applications/Moonlight.app')) {
        my.result.type='Fatal'; my.result.message='Install Moonlight in Applications first.'; return false;
    }
    return true;
}
'''
    outline = ET.SubElement(distribution, 'choices-outline')
    ET.SubElement(outline, 'line', {'choice': 'bridge'})
    choice = ET.SubElement(distribution, 'choice', {'id': 'bridge', 'visible': 'false', 'title': 'ReceiverBridge'})
    ET.SubElement(choice, 'pkg-ref', {'id': identifier})
    ET.SubElement(distribution, 'pkg-ref', {'id': identifier, 'version': '1.0', 'onConclusion': 'None'}).text = component_pkg.name
    dist_path = work / 'Distribution.xml'
    ET.ElementTree(distribution).write(dist_path, encoding='utf-8', xml_declaration=True)
    subprocess.run(['/usr/bin/productbuild', '--distribution', str(dist_path), '--package-path', str(work),
                    '--resources', str(resources), str(output)], check=True)
print(output)
