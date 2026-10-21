#!/bin/sh
# Toggle the razp dashboard; start razp first if it isn't running.
export PATH="$HOME/.local/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
LOG=/tmp/razp-toggle.log
echo "--- $(date) click" >> "$LOG"
if ! qs -c razp ipc call razp toggle >> "$LOG" 2>&1; then
    echo "toggle failed, starting razp" >> "$LOG"
    qs -c razp -d >> "$LOG" 2>&1
    sleep 1.5
    qs -c razp ipc call razp show >> "$LOG" 2>&1
fi
