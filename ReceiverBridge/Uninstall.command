#!/bin/zsh
set -eu
if (( $(id -u) == 0 )); then print -u2 'Run as your normal user, without sudo.'; exit 1; fi
/bin/launchctl bootout "gui/$(id -u)/com.zbreilly.ReceiverBridge.agent" 2>/dev/null || true
trash_dir="$HOME/.Trash/ReceiverBridge-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$trash_dir"
for installed in "$HOME/Library/LaunchAgents/com.zbreilly.ReceiverBridge.agent.plist" \
    "$HOME/Applications/Moonlight for 8BitDo.app" \
    "$HOME/Library/Application Support/ReceiverBridge"; do
    if [[ -e "$installed" ]]; then mv "$installed" "$trash_dir/"; fi
done
print 'ReceiverBridge stopped and removed from login startup. Files moved to Trash.'
print 'Your Moonlight installation and controller firmware were not changed.'
