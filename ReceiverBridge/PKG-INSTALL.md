# ReceiverBridge 1.0 — macOS Installer package

Double-click ReceiverBridge-1.0.pkg and install for your user account.
Quit Moonlight first. The package installs the signed background bridge,
registers login startup, and installs Moonlight for 8BitDo in your home
Applications folder. No Terminal commands are needed for installation.

After installation, open **Moonlight for 8BitDo** when streaming. It launches
your existing Moonlight with the native SDL backend used in the successful
tests. The ordinary Moonlight icon may select the incompatible Xbox backend.
The launcher can be added to the Dock. The bridge has no visible window or icon.

The bridge waits if the receiver is absent. On USB removal it releases input
and exits; launchd restarts it and waits for reconnection. Try one unplug/replug
after installation and confirm the game rediscovers the controller.
The background startup and reconnect lifecycle still needs this live check.

Installed files, inside your home folder:

- Library/Application Support/ReceiverBridge/ReceiverBridge.app
- Library/Application Support/ReceiverBridge/Source.zip (rebuildable source)
- Library/LaunchAgents/com.zbreilly.ReceiverBridge.agent.plist
- Applications/Moonlight for 8BitDo.app
- Library/Logs/ReceiverBridge/service.log

Status.command and Uninstall.command are in the support folder. Uninstall
stops the service, removes login startup, and moves its installed files to Trash.
Logs remain. Moonlight and controller firmware are not modified.

The package is unsigned: no Developer ID Installer certificate was available.
Both contained apps remain signed. The virtual HID development profile is for
this Mac and expires October 26, 2027. Rebuild with a renewed profile before
then. This is a local developer build, not a notarized public distribution.

Input and both rumble motors were verified through Moonlight before packaging.
Package structure, signatures, install domains, script syntax and agent plist
generation are checked during preparation; an actual Installer transaction
and subsequent reconnect check must be performed on this Mac.

Rebuild with `python3 build_pkg.py --release /path/to/ReceiverBridge-1.0`,
using the signed apps produced by build_release.py.
