#!/usr/bin/env bash
# Closes the Wi-Fi / Bluetooth popups when you switch workspace.
# Start it once from hyprland.conf:  exec-once = ~/path/to/portal/wifi-close.sh

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
PIDFILES=(/tmp/waybar-wifi.pid /tmp/waybar-bluetooth.pid)

close_popups() {
    local file pid
    for file in "${PIDFILES[@]}"; do
        [[ -f "$file" ]] || continue
        pid=$(<"$file")
        # only kill it if it is still one of our popups (guards against reused PIDs)
        if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null \
            && tr '\0' ' ' < "/proc/$pid/cmdline" | grep -Eq 'wifi\.py|bluetooth\.py'; then
            kill "$pid" 2>/dev/null
        fi
        rm -f "$file"
    done
}

socat -u "UNIX-CONNECT:$SOCKET" STDOUT | while IFS= read -r event; do
    case "$event" in
        workspace\>\>*|workspacev2\>\>*) close_popups ;;
    esac
done
