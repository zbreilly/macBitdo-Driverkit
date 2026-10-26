#!/bin/zsh
set -eu
umask 077
package_dir=${0:A:h}
support_dir="$HOME/Library/Application Support/ReceiverBridge"
agent_dir="$HOME/Library/LaunchAgents"
log_dir="$HOME/Library/Logs/ReceiverBridge"
agent_file="$agent_dir/com.zbreilly.ReceiverBridge.agent.plist"
job="gui/$(id -u)/com.zbreilly.ReceiverBridge.agent"
stamp=$(date +%Y%m%d-%H%M%S)
if [[ $# -gt 1 || ( $# == 1 && $1 != --check ) ]]; then
    print -u2 'Usage: Install.command [--check]'; exit 2
fi

if (( $(id -u) == 0 )); then
    print -u2 'Run this installer as your normal user, without sudo.'; exit 1
fi
/usr/bin/codesign --verify --deep --strict "$package_dir/ReceiverBridge.app"
team=$(/usr/bin/codesign -dv "$package_dir/ReceiverBridge.app" 2>&1 | /usr/bin/sed -n 's/^TeamIdentifier=//p')
[[ -n $team && $team != 'not set' ]] || { print -u2 'The bridge needs a provisioning-backed signing identity.'; exit 1; }
if [[ ${1:-} == --check ]]; then
    print "Bridge signature validated (team $team). No installation changes made."; exit 0
fi

mkdir -p "$support_dir" "$agent_dir" "$log_dir"
stage_dir=$(mktemp -d "$support_dir/.install.XXXXXX")
trap '[[ ! -d "$stage_dir" ]] || /bin/rm -rf -- "$stage_dir"' EXIT
/usr/bin/ditto "$package_dir/ReceiverBridge.app" "$stage_dir/ReceiverBridge.app"

# Stop this job on upgrades before moving its executable. Stop only the named
# prototype binaries of the current user; unrelated apps and Moonlight stay open.
/bin/launchctl bootout "$job" 2>/dev/null || true
for bridge_pid in $(/usr/bin/pgrep -u "$(id -u)" -x ReceiverBridge || true); do
    /bin/kill -TERM "$bridge_pid" 2>/dev/null || true
done
for attempt in {1..30}; do
    if ! /usr/bin/pgrep -u "$(id -u)" -x ReceiverBridge >/dev/null; then break; fi
    /bin/sleep .1
done
if /usr/bin/pgrep -u "$(id -u)" -x ReceiverBridge >/dev/null; then
    print -u2 'A previous bridge is still stopping. Stop it in Xcode or Terminal, then rerun Install.command.'; exit 1
fi

if [[ -e "$support_dir/ReceiverBridge.app" ]]; then
    mv "$support_dir/ReceiverBridge.app" "$support_dir/ReceiverBridge.previous-$stamp.app"
fi
legacy_launcher="$HOME/Applications/Moonlight for 8BitDo.app"
if [[ -e "$legacy_launcher" || -L "$legacy_launcher" ]]; then
    legacy_trash="$HOME/.Trash/ReceiverBridge-legacy-launcher-$stamp-$$"
    mkdir -p "$legacy_trash"
    mv "$legacy_launcher" "$legacy_trash/"
fi
mv "$stage_dir/ReceiverBridge.app" "$support_dir/ReceiverBridge.app"
cp "$package_dir/Uninstall.command" "$package_dir/Status.command" "$support_dir/"
cp "$package_dir/README.md" "$support_dir/README.md"
chmod 700 "$support_dir/Uninstall.command" "$support_dir/Status.command"

# plutil receives paths as arguments, so spaces and XML characters are preserved.
plist_stage="$stage_dir/agent.plist"
/usr/bin/plutil -create xml1 "$plist_stage"
/usr/bin/plutil -insert Label -string com.zbreilly.ReceiverBridge.agent "$plist_stage"
/usr/bin/plutil -insert ProgramArguments -json '[]' "$plist_stage"
/usr/bin/plutil -insert ProgramArguments.0 -string "$support_dir/ReceiverBridge.app/Contents/MacOS/ReceiverBridge" "$plist_stage"
/usr/bin/plutil -insert ProgramArguments.1 -string --service "$plist_stage"
/usr/bin/plutil -insert RunAtLoad -bool YES "$plist_stage"
/usr/bin/plutil -insert KeepAlive -bool YES "$plist_stage"
/usr/bin/plutil -insert ThrottleInterval -integer 3 "$plist_stage"
/usr/bin/plutil -insert ProcessType -string Interactive "$plist_stage"
/usr/bin/plutil -insert LimitLoadToSessionType -string Aqua "$plist_stage"
/usr/bin/plutil -insert ExitTimeOut -integer 5 "$plist_stage"
/usr/bin/plutil -insert StandardOutPath -string "$log_dir/service.log" "$plist_stage"
/usr/bin/plutil -insert StandardErrorPath -string "$log_dir/service.log" "$plist_stage"
/usr/bin/plutil -lint "$plist_stage" >/dev/null
if [[ -f "$agent_file" ]]; then cp "$agent_file" "$support_dir/agent.previous-$stamp.plist"; fi
mv "$plist_stage" "$agent_file"
chmod 600 "$agent_file"
if ! /bin/launchctl bootstrap "gui/$(id -u)" "$agent_file"; then
    print -u2 "Installation files are ready, but macOS could not register the login agent. Run $support_dir/Status.command for details."; exit 1
fi
/bin/launchctl kickstart "$job" 2>/dev/null || true
print 'Installed. The bridge runs now and at login, without Terminal or Xcode.'
print 'Open Moonlight or another controller-compatible app normally.'
print "Status: $support_dir/Status.command"
print "Uninstall: $support_dir/Uninstall.command"
print 'You can close this Terminal window.'
