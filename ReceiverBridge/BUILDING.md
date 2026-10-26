# Building macBitdo-Ultimate

These steps build the background app, assemble a manual-install release/ZIP,
and create a `.pkg`. Run commands from the repository root unless stated
otherwise. If working from a release's `Source/` directory, use that directory
as the source root and omit the `ReceiverBridge/` path prefix below.

## Requirements

- An Apple Silicon Mac. The project targets macOS 13 or newer; older macOS
  versions and Intel Macs have not been validated on hardware. The current
  development host runs macOS 27.2.
- Full Xcode with its macOS SDK and command-line tools selected. The current
  development build uses Xcode 27.1. Command Line Tools alone are insufficient
  for the Xcode project and account/provisioning setup.
- Python 3.9 or newer for the release/package scripts; standard library only.
- Git for cloning. GitHub CLI is optional and only needed for repository work.
- For a working virtual controller: an Apple Developer signing identity,
  an App ID/profile that authorizes
  `com.apple.developer.hid.virtual.device`, and a profile covering your Mac.
  Apple capability approval/account availability must be resolved with Apple.

Runtime dependencies are macOS frameworks: Foundation, IOKit, IOUSBHost,
Security, and GameController. There are no Homebrew, pip, CocoaPods, libusb,
or bundled SDL dependencies. Optional SDL diagnostics load the SDL2 library
inside `/Applications/Moonlight.app` and therefore need that app installed.

## Toolchain and source

```sh
git clone https://github.com/zbreilly/macBitdo-Ultimate.git
cd macBitdo-Ultimate
xcodebuild -version
xcrun --show-sdk-path
python3 --version
```

The repository is private during development; cloning requires account access.
If Xcode tools point to Command Line Tools, select the installed Xcode in
Xcode Settings > Locations > Command Line Tools and complete Xcode's initial
component installation/license prompts.

## Signing setup

**Account-free builds:** compilation and `--self-test` work without a Developer
account (see the unsigned command below). A working, self-built virtual
controller does not. The macOS user-device client requires an authorized HID
entitlement and has no root fallback. A future prebuilt distribution-signed
bridge could support account-free installation. Alternatively, a signed HID
helper could be reused while building the rest of the bridge, but that split
is not implemented. Neither option makes rebuilding the protected HID
component from source account-free. See Apple's
[entitlement checks in IOHIDResourceUserClient](https://github.com/apple-oss-distributions/IOHIDFamily/blob/main/IOHIDFamily/IOHIDResourceUserClient.cpp).

1. Open `ReceiverBridge/ReceiverBridge.xcodeproj` in Xcode. Add your Apple
   Developer account under Xcode Settings > Accounts.
2. Select the ReceiverBridge target and Signing & Capabilities. Choose your
   team, automatic signing, and your own unique bundle identifier/App ID.
3. Ensure your App ID and provisioning profile authorize the virtual HID
   entitlement declared in `ReceiverBridge.entitlements`. Register the Mac
   with your team and include it in the development profile.
4. Build/run once from Xcode to resolve signing. Merely adding the entitlement
   to a plist or applying an ad hoc signature does not grant HID capability.

The checked-in project preserves the maintainer's team/App ID as defaults;
these identifiers are not credentials. Other builders must override them.
Certificates, private keys, and profiles are not in this repository.

See Apple's [virtual HID entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device)
and [registered-device distribution](https://developer.apple.com/documentation/xcode/distributing-your-app-to-registered-devices)
documentation.

## Compile and check protocol fixtures

Replace `YOUR_TEAM_ID` and `com.example.ReceiverBridge` with your provisioned
values. Omit those two overrides if using the maintainer's existing setup.

```sh
xcodebuild -quiet \
  -project ReceiverBridge/ReceiverBridge.xcodeproj \
  -scheme ReceiverBridge -configuration Debug \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/macBitdo-Ultimate-build \
  DEVELOPMENT_TEAM=YOUR_TEAM_ID \
  PRODUCT_BUNDLE_IDENTIFIER=com.example.ReceiverBridge \
  build

/tmp/macBitdo-Ultimate-build/Build/Products/Debug/ReceiverBridge.app/Contents/MacOS/ReceiverBridge --self-test
codesign --verify --deep --strict \
  /tmp/macBitdo-Ultimate-build/Build/Products/Debug/ReceiverBridge.app
```

If you explicitly want Xcode to fetch signing assets, add
`-allowProvisioningUpdates`. Builds otherwise use assets already installed.

For a compile/protocol-only check without signing, replace the signing
overrides with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=`. The unsigned
build can run `--self-test`; it cannot create the operational virtual pad.

## Assemble the signed release and `.pkg`

Both output destinations must be new. The scripts refuse to overwrite them.
There is no download/install step for third-party dependencies.

```sh
mkdir -p dist
python3 ReceiverBridge/build_release.py \
  --output "$PWD/dist/macBitdo-Ultimate-1.1" \
  --derived-data /tmp/macBitdo-Ultimate-build \
  --team YOUR_TEAM_ID \
  --bundle-id com.example.ReceiverBridge

python3 ReceiverBridge/build_pkg.py \
  --release "$PWD/dist/macBitdo-Ultimate-1.1" \
  --output "$PWD/dist/macBitdo-Ultimate-1.1.pkg"
```

`build_release.py` accepts `--allow-provisioning-updates` as an explicit opt-in.
It builds the signed app, runs signature/protocol/manual-installer preflight
checks, and assembles the app, install/status/uninstall scripts, source tree,
and ZIP. It creates no Moonlight wrapper. `build_pkg.py` uses that release's
source snapshot and scripts so the package does not silently pick up later
working-tree edits. The package contains the bridge, helpers, instructions,
and Source.zip, with a current-user-only Installer domain.

The app remains development-signed. The package builder does not sign or
notarize the `.pkg`. Do not distribute this local development package as a
general-use public driver. Public binary distribution requires an appropriate
Apple-approved signing/provisioning arrangement, distribution signing,
hardened-runtime/release configuration, installer signing, and notarization;
that workflow is not implemented here. See Apple's
[notarization requirements](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).

## Hardware validation

Use only one bridge process at a time. If the service is installed, stop its
agent before foreground diagnostics:

```sh
launchctl bootout "gui/$(id -u)/com.zbreilly.ReceiverBridge.agent"
```

Run the signed executable with `--sdl-probe` for default-SDL input or
`--sdl-motor-test` for separate motors. These require the receiver and installed
Moonlight. The direct USB alternatives are `--rumble-test` and
`--usb-motor-test`. Run from normal Terminal/Xcode; the development automation
process could not create virtual HID devices even with the runtime entitlement.

Restore the installed service afterward with:

```sh
launchctl bootstrap "gui/$(id -u)" \
  "$HOME/Library/LaunchAgents/com.zbreilly.ReceiverBridge.agent.plist"
```

For installed lifecycle testing, use the package/ZIP instructions, launch
ordinary Moonlight, verify all controls and both motors, then test login with
the receiver present/absent, USB unplug/replug, controller sleep/power cycling,
system sleep/wake, upgrade from a launcher-based build, and uninstall.
Confirm neutral controls and motor OFF after interruption. Check Home/Guide
with your macOS gesture settings. Record OS, firmware, Moonlight, and SDL
versions when reporting results. These lifecycle checks are still pending for
the revised installer; successful packaging alone does not establish them.

## Troubleshooting

- **Virtual HID creation failed:** verify the signature, embedded profile,
  authorized entitlement, target Mac, and profile expiration. An unsigned or
  ad hoc build is not sufficient. Compare a normal local launch if automation
  alone fails.
- **Receiver absent:** the bridge waits for `2DC8:3106`. Wake the controller
  and check its current receiver identity before treating absence as a crash.
- **Exclusive USB open failed:** another bridge or configuration tool may own
  the receiver. Stop the conflicting client and retry.
- **SDL sees a controller but input is zero:** check the live top-level HID
  `Transport` property and GUID. The bridge verifies its Bluetooth metadata
  after activation. Quit/reopen a consumer that cached the old properties.
- **SDL diagnostic refuses backend hints:** remove the two hints from that
  process's environment; use `--sdl-probe-native` only for a deliberate native
  comparison. Do not set global hints as a workaround.
- **Profile expiry:** renew provisioning and rebuild; do not strip or bypass
  signing. The package conclusion reads expiration from the packaged profile.
