# ReceiverBridge 1.0

Local macOS support for the 8BitDo Ultimate 2.4 GHz USB receiver (2DC8:3106)
in its existing XInput mode. Input and both rumble motors have been verified
through Moonlight by the user. No firmware changes or Bluetooth are used.

## Install

Quit Moonlight first. Double-click **Install.command**, or run it in Terminal.
Run as your regular user, without sudo. It stops earlier ReceiverBridge
prototypes, installs the signed bridge, and registers a login agent.
After installation, close Terminal and Xcode.

Open **Moonlight for 8BitDo** in your home Applications folder when streaming.
You can put this launcher in the Dock. It starts your existing, unmodified
Moonlight with the SDL native backend verified on this Mac. Launching the
ordinary Moonlight icon may select its incompatible Xbox HIDAPI backend.
The launcher does not change global environment variables or Moonlight files.
If Moonlight is already running, quit it and reopen the launcher.

The bridge has no window, Dock icon, or menu bar item. It runs at login and
waits for the receiver. USB removal releases the virtual controls and exits;
launchd restarts the bridge after a short delay. On replug it initializes the
receiver and publishes the controller again. A game may need a moment to
rediscover the reconnected gamepad. The bridge does not launch Moonlight at login.

## Installed files

- `~/Library/Application Support/ReceiverBridge/ReceiverBridge.app`
- `~/Library/LaunchAgents/com.zbreilly.ReceiverBridge.agent.plist`
- `~/Applications/Moonlight for 8BitDo.app`
- `~/Library/Logs/ReceiverBridge/service.log`

Run **Status.command** from this package or the installed support folder to
inspect registration and recent events. Service mode does not log individual
buttons or axes. The log is trimmed if larger than 1 MiB on a service restart.
The installer keeps timestamped copies of previous installed builds.

## Remove

Run **Uninstall.command**. It unregisters the login agent, stops the service,
and moves installed files to Trash. Moonlight, your signing credentials, and
controller firmware are unaffected. Logs remain available for diagnosis.

## Signing and scope

This build is development-signed for this Mac and the user's Apple Developer
team, with an embedded virtual HID provisioning profile. Its current profile
expires October 26, 2027; rebuild with a renewed profile before then.
It is a user-session compatibility service, not a kernel extension or a
redistributable driver. Other Macs need appropriate development provisioning.

Background startup, USB reconnection and the new launcher require a live
post-install check. The underlying input and rumble path was verified before
packaging; compilation, signatures, packet/mapping checks, shell syntax, and
installer preflight are checked during release preparation.

## Source and rebuilding

Source is included in `Source/`. Open its Xcode project with the existing
development account, or run `python3 Source/build_release.py` with an output
directory that does not already exist. The scripts require only macOS system
tools; rebuilding also requires Xcode and the configured signing identity.

Apple launch-agent reference:
https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html
