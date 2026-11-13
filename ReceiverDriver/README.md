# Native DriverKit implementation

This directory contains a DriverKit driver for the 8BitDo Ultimate 2.4 GHz
USB receiver (`2DC8:3106`). It is separate from the existing ReceiverBridge.
It contains no IOHIDUserDevice app client and requires no login-agent data
path. The activation app does not read controller USB input or publish input.

**Current status (2026-11-13):** a development-signed build is activated and
working on hardware. Sticks, buttons, D-pad, triggers, L3/R3, Guide and both
rumble motors were verified in ordinary Moonlight with the host app closed, and
the driver loads on its own after a restart. Build 3 is the installed build;
it replaced build 2 in place and passed the same input and rumble check. Its
rumble-recovery and wake-ordering paths are covered by the offline lifecycle
tests only, since those failures cannot be forced on the real receiver. The
system power log recorded no sleep while build 3 was running, so sleep/wake is
not yet confirmed by logs. Public distribution signing and the installer are
not done.

The receiver enumerates as `2DC8:3106` only in XInput mode. In its HID mode it
is `2DC8:3109` with a class-3 interface owned by Apple's HID driver; this
driver does not attach to that mode.

## Architecture

- `UltimateReceiverDevice` matches only `2DC8:3106` at IOUSBHostDevice, opens
  the receiver, selects configuration 1, and lets macOS enumerate interfaces.
- `UltimateReceiverHID` subclasses IOUserHIDDevice, matching interface 0 with
  class/subclass/protocol `FF/5D/01`. It owns interrupt pipes 81/02, initializes
  the receiver, submits native HID reports, and handles HID rumble output.
- The existing XInput decoder, Xbox HID descriptor/mapping and body-rumble
  conversion are ported into `ReceiverProtocol.h`. USB startup order and
  zero-timeout interrupt transfers follow the tested receiver implementation.
- Input and output are asynchronous; a serial queue owns state. A timer
  schedules output effects, backs off input retries and watches stalled output.
  Stop neutralizes controls, attempts motor OFF, aborts pending IN safely and
  drains transfers/timer cancellation before releasing buffers/actions.
- USB starts only after superclass HID publication succeeds. Failed publication
  cancels the timer and releases the receiver open. Failed player-indicator
  output still advances input startup and leaves rumble usable. A failed rumble
  write is retried after a one-second backoff and the motor state is resent.
- The USB output buffer must be created read/write (`kIOMemoryDirectionInOut`).
  An out-only buffer is mapped read-only in the driver process and the first
  write crashes the driver; the offline harness cannot detect this.
- Power transitions neutralize input, discard the active effect, drain pending
  transfers and attempt motor OFF before acknowledging sleep. The timer parks
  while suspended. Wake clears halted pipes and repeats receiver initialization;
  it does not replay the pre-sleep rumble effect. A wake that arrives before the
  sleep drain finishes acknowledges the low-power state first.
- The HID provider describes the existing Xbox Bluetooth wire format so SDL
  selects the matching parser. This is controller report metadata; the physical
  receiver remains USB/2.4 GHz and no Bluetooth connection is made.
- The host app uses SystemExtensions activation/removal requests. After
  activation, macOS manages driver/device attachment; the host can be closed.

## Build and offline checks

Run from the repository root:

```sh
python3 ReceiverDriver/build_driver.py --unsigned
python3 ReceiverDriver/test_driver.py --app '/tmp/ReceiverDriver-build/Build/Products/Debug/macBitdo Driver.app'
```

The tests include wire fixtures for neutral/boundary controls, D-pad and
triggers, descriptor/report lengths, narrow USB matching, product platform,
65,536 button combinations and 625 stick-boundary combinations against the
original decoder/encoder, and 1,048,576 motor mask/magnitude comparisons against the legacy C rumble
implementation. They exercise no USB hardware and perform no activation.

The lifecycle harness compiles the actual `UltimateReceiverHID.cpp` method
bodies against a deterministic test adapter. It checks failed superclass
publication, removal before/during initialization, immediate and asynchronous
LED failure, rumble after LED failure, recovery from a failed rumble write,
wake during an unfinished sleep transition, stalled-output watchdog handling, input/output cancellation in
both completion orders, motor OFF failure, sleep/wake with halted pipes and
removal during a pending sleep transition. Buffers must stay retained through
USB completion and timer cancellation. This adapter does not reproduce macOS
dispatch, power-management or USB-stack behavior; those require hardware tests.

`generate_project.py` regenerates the checked-in Xcode project and plists.
Keep edits to generated settings in that script so regeneration is stable.

## Development signing — paid individual membership is sufficient

Use the existing Apple Development account and development capabilities;
special distribution entitlement approval is not a prerequisite for this
local development build. Apple DTS describes the current process here:
https://developer.apple.com/forums/thread/809202

The driver entitlements are DriverKit, HID Device family, App Sandbox and the
USB **development-only** wildcard transport entitlement. Hardware matching in
Info.plist remains restricted to the one receiver. Never use the wildcard
development entitlement as a public distribution configuration.

1. Open `ReceiverDriver/ReceiverDriver.xcodeproj` in Xcode.
2. Select the `macBitdo Driver` scheme. Use your existing developer account /
   team for both targets with Automatic Signing. The defaults use this
   project's maintainer team `B7MRCR9852`.
3. Confirm the host's System Extension capability and the driver's DriverKit,
   HID Device and USB development capabilities. Let Xcode create profiles for
   the two new App IDs. The old bridge's profile is not reused.
4. Build and inspect both the host and nested driver signatures/profiles.

Signing succeeded on 2026-11-13 with Automatic Signing once Xcode had the
Apple ID signed in and the current Program License Agreement was accepted.
Xcode created a Mac Team profile for the host and a DriverKit Team profile for
the driver. Xcode drops `com.apple.security.app-sandbox` from the signed
driver; macOS applies its own driver sandbox and the driver loads without it.

The signing build from the command line:

```sh
python3 ReceiverDriver/build_driver.py --allow-provisioning-updates --derived-data /tmp/ReceiverDriver-signed-build
```

Default IDs:

- Host: `com.zbreilly.macBitdo.DriverHost`
- Driver: `com.zbreilly.macBitdo.DriverHost.Receiver`

If changing IDs, update the host's requested identifier and generated
project/plists together. The driver's `.dext` filename must equal its ID.

## First activation and migration

After signing succeeds, copy the host app to `/Applications`. Open that copy
and choose **Activate Driver**, then approve the driver in macOS Settings if
asked. Keep the app open until the request completes. Do not attempt to
activate the unsigned compile-only bundle.

Activation stops the previous per-user ReceiverBridge login agent and requests
termination of its old app. Before requesting activation, the old agent
plist is saved outside LaunchAgents, including when a reboot is required.
The old source and app are retained. If activation fails, the host restores
the saved bridge automatically and reports the error. If a manually launched
old binary still holds USB, stop it and reconnect the receiver. Only one
implementation can own the physical device.

The activation app also provides removal and an explicit rollback action.
Rollback requests DriverKit removal before bootstrapping the saved bridge,
avoiding two active implementations.

Updating an installed driver: raise `CFBundleVersion` in `generate_project.py`
so macOS treats the new copy as a replacement, then activate again. If the old
copy stays listed as terminating and the new one never starts, unplug the
receiver; if that is not enough, restart the Mac.

## Hardware validation

1. Driver appears in `systemextensionsctl list` and matches the physical USB
   device and interface. No ReceiverBridge process is handling input.
2. Initial USB configuration works after a fresh unplug/replug.
3. GameController and ordinary Moonlight receive sticks, buttons, D-pad,
   analog triggers, L3/R3 and menu/back input. Verify Home gesture behavior.
4. Both body rumble motors receive separate and combined effects; OFF works.
5. Unplug, power cycling, sleep/wake, removal and app updates drain callbacks
   without stuck buttons, vibration, crashes or retained exclusive USB access.
6. Close the host app and verify input/rumble continue through DriverKit.

Items 1 to 4 and 6 passed on 2026-11-13, and a physical disconnect tore the
driver down without a crash. An in-place update from build 2 to build 3 also
worked. Sleep/wake confirmed against the power log and removal through the host
app are still open.

## Installer

`build_pkg.py` accepts only a signed host containing a profiled, signed driver;
it refuses the unsigned prototype. It installs the activation app in
`/Applications`, not a new launch agent. Activation and macOS approval are a
separate, explicit first-run step.

```sh
python3 ReceiverDriver/build_pkg.py --app '/tmp/ReceiverDriver-signed-build/Build/Products/Debug/macBitdo Driver.app' --output /tmp/macBitdo-DriverKit-development.pkg
```

No installer has been built yet. Public distribution signing, distribution entitlements,
installer signing and notarization are separate future work.

## Repository

Distributed from `https://github.com/zbreilly/macBitdo-Driverkit`. The driver
was built on top of macBitdo-Ultimate commit
`dba4aa993205510c0e47ad9ab4d8a2ed85bf5bdd`.
