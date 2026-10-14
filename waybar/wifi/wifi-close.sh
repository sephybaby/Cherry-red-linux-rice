#!/usr/bin/env bash

SOCKET="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
PIDFILE="/tmp/waybar-wifi.pid"

socat -u "UNIX-CONNECT:$SOCKET" STDOUT | while IFS= read -r event; do
    case "$event" in
        workspace\>\>*|workspacev2\>\>*)
            if [[ -f "$PIDFILE" ]]; then
                PID=$(cat "$PIDFILE")

                if [[ "$PID" =~ ^[0-9]+$ ]] && kill -0 "$PID" 2>/dev/null; then
                    kill "$PID" 2>/dev/null
                fi

                rm -f "$PIDFILE"
            fi
            ;;
    esac
done
