# macBitdo-Ultimate 1.1

ReceiverBridge translates the 8BitDo Ultimate 2.4 GHz receiver's XInput USB
reports (`2DC8:3106`) into a macOS virtual Xbox controller (`045E:02FD`). It
supports sticks, D-pad, buttons, analog triggers, L3/R3, and both body rumble
motors. The radio remains in its existing 2.4 GHz mode.

After installation, open **Moonlight normally**. The bridge runs silently at
login; it does not launch or modify Moonlight. Apps using GameController or a
compatible HID/SDL backend can receive the controller. Apps must implement
controller input and rumble themselves.

See [BUILDING.md](BUILDING.md) for dependencies, assembly, provisioning, and
packaging; [PKG-INSTALL.md](PKG-INSTALL.md) for the `.pkg`; and
[INSTALL.md](INSTALL.md) for manual ZIP installation.

## Architecture

`main.m` owns USB initialization, XInput decode, virtual HID creation, input
encoding, HID callbacks, the service loop, and diagnostics. `Rumble.h` decodes
output report 3 and translates it to the receiver motor command. The Xcode
project builds a background app with `LSUIElement=true`.

The receiver uses vendor interface `FF/5D/01`, input endpoint `0x81` and output
endpoint `0x02`. Initialization opens configuration 1/interface 0, sends
`01 03 02` for the player indicator, queues input, and performs the XInput
vendor startup request. Interrupt I/O is asynchronous with
`completionTimeout=0`; cancellation is bounded.

The virtual controller uses the Xbox Bluetooth HID wire format: report 1 is
17 bytes including its ID (sticks, 10-bit triggers, hat, buttons, Back);
report 2 carries Guide; report 3 carries rumble. The receiver's two motors
receive `00 08 00 LL RR 00 00 00`. Trigger-motor values are ignored because
this hardware exposes only the two body motors. The tested rumble scaling
is preserved.

### Native Moonlight compatibility

The installed Moonlight's SDL2 library forwards to SDL3. SDL3 uses the HID
transport property to select between Bluetooth Xbox reports and wired GIP
reports. Publishing this descriptor with `Transport=Virtual` selected the
wrong parser: discovery succeeded while input stayed zero.

macOS forces `Virtual` at user-device creation with the developer HID
entitlement. The bridge therefore uses the public
`IOHIDUserDeviceSetProperty` API after activation to apply Bluetooth transport
metadata and verifies it. This changes the virtual device's metadata; it
does not pair the receiver over Bluetooth. The corrected default SDL GUID was
`05006d105e040000fd02000000006800`, named Xbox One S Controller.

The old Moonlight wrapper and `--moonlight-compat` option have been removed.
Installers move an older wrapper from `~/Applications` to Trash on upgrade.

## Background operation

`--service` waits for a receiver before publishing a controller and holds a
per-user advisory instance lock. USB removal or read failure neutralizes
controls and exits. The login agent uses KeepAlive with a three-second
throttle to restart the bridge; receiver absence is checked once per second.
Rumble has an output watchdog and a shutdown stop command. Service mode
suppresses per-input logging and bounds the service log on restart.

Only one process can own the physical receiver. Stop the installed service
before running a foreground diagnostic; do not run competing bridge copies.

## Diagnostics

Run the signed app's `Contents/MacOS/ReceiverBridge` executable with one of
these options. Start from a normal local Terminal or Xcode context; virtual
HID creation was blocked in the development automation process despite a
valid entitlement, while the normal app launch succeeded.

| Option | Purpose |
| --- | --- |
| `--self-test` | Protocol fixtures for decode, mapping, triggers, and rumble; no hardware required. |
| `--virtual-test` | Create and release the virtual controller; requires valid HID provisioning. |
| `--service` | Silent persistent operation; waits for the receiver. |
| `--sdl-probe` | Input observer using Moonlight's default SDL backend. |
| `--sdl-probe-native` | Explicit comparison using GameController/MFI instead of Xbox HIDAPI. |
| `--sdl-rumble-test` | Default SDL half-second rumble request; exits after about ten seconds. |
| `--sdl-motor-test` | Default SDL large, small, and both motor pulses with OFF commands. |
| `--rumble-test` | Direct USB half-strength motor sequence; no virtual controller. |
| `--usb-motor-test` | Direct USB separate motor pulses at full strength. |

The SDL diagnostics require `/Applications/Moonlight.app` and its bundled
`libSDL2.dylib`. Normal bridge operation has no Moonlight or SDL dependency.
Default probes reject inherited `SDL_JOYSTICK_HIDAPI_XBOX` and
`SDL_JOYSTICK_MFI` hints. For a clean one-process test, unset them with
`env -u SDL_JOYSTICK_HIDAPI_XBOX -u SDL_JOYSTICK_MFI` before the executable;
do not set global hints. Add `--sdl-probe-native` to an SDL motor test only
when deliberately comparing the native backend.

## Verification and limits

On October 26, 2026, the owner confirmed the updated bridge works through the
ordinary Moonlight launch. A separate observer using Moonlight's default SDL
backend recorded live stick changes with both backend hints unset. Earlier
hardware tests verified buttons, D-pad, analog triggers, L3/R3, separate large
and small motor channels, and streamed in-game rumble.

Version 1.1 removes the launcher requirement from the package and ZIP
installers. Build/signature checks, protocol fixtures, script syntax, package
payload inspection, and source-archive checks can be performed without a real
installation. Actual Installer execution, login with receiver present/absent,
unplug/replug, controller sleep/power cycling, system sleep/wake, and uninstall
still need end-to-end checks. Do not equate package inspection with those tests.

Home/Guide can interact with macOS system gestures. A Moonlight-specific
gesture override was present during development; this installer does not
change app gesture preferences. Test its behavior under the target user's
settings. Trigger rumble may be advertised by SDL although only the two body
motors are implemented. Battery reporting is not implemented. Other macOS,
SDL, controller firmware, and receiver variants have not been validated.

This is an Apple Development build. The current maintainer profile expires
October 26, 2027. Other builders need their own provisioning; other Macs are
not automatically authorized by this source repository. The `.pkg` is unsigned
and the app is not notarized for public distribution.

## Primary references

- [Apple virtual HID entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device)
- [Apple IOHIDUserDevice transport implementation](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDUserDevice.cpp)
- [SDL 3.4.18 macOS HID transport classification](https://github.com/libsdl-org/SDL/blob/release-3.4.18/src/hidapi/mac/hid.c)
- [SDL 3.4.18 Xbox report handling](https://github.com/libsdl-org/SDL/blob/release-3.4.18/src/joystick/hidapi/SDL_hidapi_xboxone.c)
- [Linux xpad USB protocol implementation](https://github.com/torvalds/linux/blob/master/drivers/input/joystick/xpad.c)
