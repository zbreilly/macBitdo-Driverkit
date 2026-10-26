# ReceiverBridge 1.1 — ZIP installation

Use this signed development build only on a Mac authorized by its provisioning
profile. For a different Mac, rebuild with your own signing setup as described
in `Source/BUILDING.md`. The physical receiver must be in its tested XInput
mode (`2DC8:3106`); no firmware change or Bluetooth pairing is needed.

## Install

1. Quit Moonlight and other controller apps.
2. Extract the ZIP and double-click **Install.command**. Run as your regular
   user without sudo. It verifies the app signature, stops earlier bridges,
   installs the app, and registers a login agent.
3. Open **ordinary Moonlight** or another controller-compatible app. No
   separate launcher is needed. Terminal and Xcode can be closed.

The installer moves an older `~/Applications/Moonlight for 8BitDo.app` to
Trash. It does not modify Moonlight, controller firmware, global SDL hints,
or system gesture settings. Moonlight need not be installed to use the bridge.

## Installed files and removal

The app, Status.command, Uninstall.command, and these instructions are under
`~/Library/Application Support/ReceiverBridge`. The login agent is
`~/Library/LaunchAgents/com.zbreilly.ReceiverBridge.agent.plist`; logs are in
`~/Library/Logs/ReceiverBridge/service.log`.

Run **Status.command** to inspect startup and logs. Run **Uninstall.command**
to stop the agent, remove startup, and move installed files to Trash. Logs
remain. Previous manual-install builds are kept as timestamped backups in
the support folder until removal.

The bridge waits while the receiver is absent. After installation, test
input/rumble, receiver unplug/replug, controller sleep/power cycling, login,
and system sleep/wake. The revised installed lifecycle is not yet verified.

## Signing

The app is development-signed, not a notarized public distribution. The
maintainer's current profile expires October 26, 2027; another builder's
profile may differ. Rebuild before your profile expires. Signatures and
protocol self-tests do not establish that an unregistered Mac can run it.
