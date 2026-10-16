
#!/usr/bin/env bash

config="$HOME/.config/quickshell/cherry-red/shell.qml"

if qs list --all 2>/dev/null | grep -Fq "$config"; then
    qs -c cherry-red ipc call cherry-red toggle
else
    qs -c cherry-red -d
fi

