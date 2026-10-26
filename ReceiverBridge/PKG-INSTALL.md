# macBitdo-Ultimate 1.1 — macOS Installer package

Quit Moonlight and other controller apps, then double-click
**macBitdo-Ultimate-1.1.pkg** and install for your user account. Do not use sudo
or a system-wide destination. The package installs one signed background app
and registers login startup. Moonlight is not a prerequisite.

Open **ordinary Moonlight** or another controller-compatible app afterward.
No separate launcher or Terminal window is needed. An old
`~/Applications/Moonlight for 8BitDo.app` is moved to Trash during upgrade.
Moonlight, global SDL hints, gesture preferences, and controller firmware are
not modified. Keep the receiver's existing USB/2.4 GHz XInput mode (`2DC8:3106`).

## Installed files

Paths are relative to your home folder:

- `Library/Application Support/ReceiverBridge/ReceiverBridge.app`
- `Library/Application Support/ReceiverBridge/Source.zip` — exact release source snapshot
- `Library/Application Support/ReceiverBridge/README.md`
- `Library/Application Support/ReceiverBridge/Status.command`
- `Library/Application Support/ReceiverBridge/Uninstall.command`
- `Library/LaunchAgents/com.zbreilly.ReceiverBridge.agent.plist`
- `Library/Logs/ReceiverBridge/service.log`

The bridge waits for an absent receiver. On removal or input failure it
neutralizes controls and exits; launchd restarts it and waits for the receiver.
Check input/rumble, unplug/replug, controller power cycling, login, and
sleep/wake after installing. This revised installed lifecycle and the actual
Installer transaction still require hardware verification.

Run **Status.command** for logs. **Uninstall.command** stops the login agent,
removes startup, and moves its files to Trash; diagnostic logs remain.

## Development signing

The app is Apple Development-signed and provisioned for the build's registered
Macs. This `.pkg` is unsigned and not notarized for public distribution. Other
people need their own signing/provisioning before building and installing.
The maintainer's current profile expires October 26, 2027; the Installer's
conclusion displays the expiration read from the actual packaged profile.

After extracting Source.zip, see `ReceiverBridge/BUILDING.md` for requirements,
assembly, and package commands. No credentials, private signing keys, or
provisioning profiles are included in the source archive.
