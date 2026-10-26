#!/bin/zsh
set -u
print 'Background service:'
/bin/launchctl print "gui/$(id -u)/com.zbreilly.ReceiverBridge.agent" 2>&1 | /usr/bin/sed -n '1,45p'
print '\nRecent log:'
/usr/bin/tail -n 25 "$HOME/Library/Logs/ReceiverBridge/service.log" 2>/dev/null || true
