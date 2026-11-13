# macBitdo-Driverkit

A native macOS driver for the **8BitDo Ultimate 2.4 GHz USB receiver** in
XInput mode (`2DC8:3106`), including both body rumble motors.

The driver is a DriverKit system extension. Once it is activated, macOS loads
it whenever the receiver is connected and the controller appears as a standard
Xbox-style gamepad. Open **Moonlight** or another controller-aware app normally.
No background app, login item, modified Moonlight build, Bluetooth pairing or
firmware change is involved.

## Status

This is a development preview.

- **Works on hardware:** sticks, buttons, D-pad, analog triggers, L3/R3, Guide
  and both rumble motors, tested in Moonlight on an Apple silicon Mac. The
  driver loads on its own after a restart and survives the receiver being
  unplugged.
- **Not yet confirmed:** sleep/wake, and removal through the activation app.
- **No installable release yet.** There is no notarized download. To run the
  driver today you must build and sign it yourself with a paid Apple Developer
  account, and it will run only on Macs registered in your development
  provisioning profile.
- **Not ready for public distribution signing.** The driver currently uses
  Apple's development-only USB entitlement. A public release needs the
  distribution entitlement for this vendor ID, granted by Apple.

## Requirements

- An Apple silicon Mac running macOS 14 or later
- The 8BitDo Ultimate 2.4 GHz receiver with the controller in XInput mode
- To build: full Xcode with the DriverKit SDK, Python 3, and a paid Apple
  Developer account

### Receiver mode

The driver attaches only when the receiver enumerates as `2DC8:3106`. In its
other mode the receiver appears as `2DC8:3109`, a generic HID gamepad that
macOS handles itself; the driver ignores it. Check **System Information → USB**
if the controller is not picked up.

## Build and install

All commands run from the repository root.

1. Set your own Apple Developer team ID and bundle identifiers in
   [`ReceiverDriver/generate_project.py`](ReceiverDriver/generate_project.py),
   then regenerate the project:

   ```sh
   python3 ReceiverDriver/generate_project.py
   ```

   If you change the bundle identifiers, also change `driverID` in
   [`ReceiverDriver/Host/main.m`](ReceiverDriver/Host/main.m).

2. Sign in to your Apple ID in Xcode (Settings → Accounts), then build:

   ```sh
   python3 ReceiverDriver/build_driver.py --allow-provisioning-updates --derived-data /tmp/ReceiverDriver-signed-build
   ```

3. Copy the app to `/Applications`. System extensions can only be activated
   from there.

   ```sh
   cp -R "/tmp/ReceiverDriver-signed-build/Build/Products/Debug/macBitdo Driver.app" /Applications/
   ```

4. Open **macBitdo Driver**, choose **Activate Driver**, and approve it in
   System Settings → General → Login Items & Extensions when macOS asks. Keep
   the app open until it reports that the driver is activated; after that it
   can be closed.

5. Unplug and replug the receiver.

To check the result:

```sh
systemextensionsctl list
```

The driver should be listed as `[activated enabled]`.

### Updating and removing

- **Update:** raise `CFBundleVersion` in `generate_project.py`, rebuild, replace
  the app in `/Applications`, and activate again. If the old copy stays listed
  as terminating, unplug the receiver; restart the Mac if that is not enough.
- **Remove:** open the app and choose **Remove Driver**.

## Checks without hardware or signing

You can compile the driver and run the offline tests with no developer account:

```sh
python3 ReceiverDriver/build_driver.py --unsigned
python3 ReceiverDriver/test_driver.py --app '/tmp/ReceiverDriver-build/Build/Products/Debug/macBitdo Driver.app'
```

The tests compare the protocol code byte for byte against the original
implementation and run the driver's lifecycle logic against a simulated USB
transport. They do not touch a real device, and an unsigned build cannot be
activated.

## How it works

- `UltimateReceiverDevice` matches the USB device and selects its
  configuration so macOS exposes the vendor-specific interface.
- `UltimateReceiverHID` owns that interface, reads controller reports,
  publishes them as an Xbox-style HID gamepad, and turns HID rumble output into
  the receiver's motor command.
- The activation app only asks macOS to install or remove the extension. It
  never reads controller input.

Details, design notes and the validation checklist are in
[`ReceiverDriver/README.md`](ReceiverDriver/README.md).

## Limits

- Controller and rumble support depend on the app you use; it must handle
  gamepad input and rumble itself.
- The receiver has two body motors. Trigger rumble is ignored.
- Guide/Home follows macOS's own gesture handling.
- Intel Macs are not supported by the current build settings.

## ReceiverBridge (previous approach)

[`ReceiverBridge/`](ReceiverBridge/) is the earlier implementation: a
background app that translated receiver packets into a virtual controller. The
driver replaces it and the two must not run at once. If the bridge's login
agent is installed, activating the driver stops it and saves its launch agent;
**Restore Old Bridge** in the activation app removes the driver and puts the
bridge back. The driver's tests use the bridge source as their reference, so it
stays in the repository.
