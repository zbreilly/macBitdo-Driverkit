# ReceiverBridge

Native macOS controller support for the **8BitDo Ultimate 2.4 GHz USB receiver**
in XInput mode (`2DC8:3106`), including both body rumble motors.

A silent background app translates receiver USB packets into a virtual Xbox
controller. Open **ordinary Moonlight** or another controller-compatible app
normally. No separate launcher, modified Moonlight build, global SDL hints,
Bluetooth pairing, or firmware changes are required.

This repository is a private development preview. Source is in
[`ReceiverBridge/`](ReceiverBridge/). The current signed build is provisioned
for the maintainer's Mac; it is not yet a public, notarized driver distribution.

## Getting started

- [Build, dependencies, signing, and packaging](ReceiverBridge/BUILDING.md)
- [Install the `.pkg`](ReceiverBridge/PKG-INSTALL.md)
- [Install a ZIP build](ReceiverBridge/INSTALL.md)
- [Architecture, diagnostics, and validation status](ReceiverBridge/README.md)

Building needs an Apple Silicon Mac, full Xcode with a macOS SDK, Python 3.9+
for the packaging scripts, and Apple signing/provisioning that authorizes
`com.apple.developer.hid.virtual.device`. No third-party runtime libraries are
needed. Moonlight's SDL library is loaded only by optional diagnostics.

### Without an Apple Developer account

You can compile and run protocol self-tests without signing. You cannot run
a fully self-built virtual-controller bridge without authorized provisioning
with the current architecture. Using sudo or adding an ad hoc entitlement is
not a substitute. A future distribution-signed binary could let end users
install without an account; that release workflow is not implemented yet.

## Current verification

The owner confirmed ordinary Moonlight works with the transport-metadata fix.
USB input, analog controls, and the two rumble motors were tested during
development. The build, signature checks, and protocol self-tests are automated.
The revised installer still needs an actual installation and login, reconnect,
sleep/wake, and uninstall checks on hardware.

Controller and rumble support depend on the consuming app. Home/Guide follows
macOS gesture policy. See the source README for the remaining limits.
