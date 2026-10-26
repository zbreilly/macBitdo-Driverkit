# ReceiverBridge 1.0

Local macOS support for the 8BitDo Ultimate 2.4 GHz USB receiver (2DC8:3106)
in its existing XInput mode. Input and both rumble motors have been verified
through Moonlight by the user. No firmware changes or Bluetooth are used.

## Validated development checkpoint — October 26, 2026

The user confirmed the current test build works through the ordinary Moonlight
app. No compatibility launcher or SDL backend overrides are required for this
build. The physical connection remains USB/2.4 GHz.

The virtual Xbox reports use the Bluetooth wire format. macOS overrides the
creation-time Transport property to Virtual with the developer HID entitlement,
so the bridge applies Bluetooth metadata through IOHIDUserDeviceSetProperty
after activation and verifies it. A default SDL observer then identified an
Xbox One S Controller (GUID 05006d105e040000fd02000000006800) and received live
stick input. Build, code signature, and packet/mapping/rumble self-tests passed.

`--sdl-probe`, `--sdl-rumble-test`, and `--sdl-motor-test` now use default SDL
backend selection and reject inherited Xbox/MFI backend hints. Add
`--sdl-probe-native` only for an explicit comparison with the old native backend.

The installer scripts and the installation instructions below still describe
the earlier launcher-based package. They need cleanup and a newly validated
package before distribution. Login/reconnect/sleep lifecycle testing remains
pending; this checkpoint records the working foreground-launched test service.

## Install (previous package)

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


## Development notes

The physical receiver stays at 2DC8:3106. The virtual gamepad emulates the
045E:02FD Xbox HID layout recognized by macOS. Input report 1 contains the
sticks, 10-bit triggers, hat and buttons; report 2 carries Guide. Output
report 3 carries the two rumble magnitudes. Rumble.h translates these to
the receiver command `00 08 00 LL RR 00 00 00` on endpoint 0x02. Input
uses endpoint 0x81, zero-timeout asynchronous interrupt I/O, player-indicator
initialization `01 03 02`, then the existing XInput vendor startup request.

Service mode suppresses input-event diagnostics, uses a per-user advisory
instance lock, waits for a receiver before publishing a virtual device, and
handles removal notifications. It neutralizes controls and exits on removal
or read failure; launchd KeepAlive restarts it with a three-second throttle.
A one-second wait loop covers a receiver absent at startup or replug. The
rumble output watchdog and bounded cancellation remain active. Service mode
cannot be combined with diagnostic or auto-launch flags.

Available diagnostics: `--self-test`, `--virtual-test`, `--sdl-probe`,
`--rumble-test`, `--sdl-rumble-test`, `--sdl-motor-test`, `--usb-motor-test`.
`--moonlight-compat` remains available for a manual foreground prototype run.
Use the installed Moonlight launcher while the background service is active
to avoid competing USB clients.

Build the bridge with the Xcode project and existing Apple Development
signing setup. Team B7MRCR9852; App ID com.zbreilly.ReceiverBridge; restricted
capability com.apple.developer.hid.virtual.device. The standalone Moonlight
launcher uses the same existing signing identity and no restricted entitlement.

The user verified sticks, buttons, analog triggers, L3/R3 and both rumble
channels locally and input/rumble in Moonlight. Home follows macOS system
gesture policy and has a Moonlight-specific override set during prototyping.
No changes to that policy or rumble gain were made in this packaging step.

Protocol references:
https://github.com/torvalds/linux/blob/master/drivers/input/joystick/xpad.c
https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device
