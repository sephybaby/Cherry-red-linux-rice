#!/bin/bash

IFACE="wlan0"
THEME="$HOME/.config/rofi/themes/wifi.rasi"
CACHE="/tmp/rofi-wifi-cache"

# Refresh Wi-Fi scan in the background
(
    iw dev "$IFACE" scan 2>/dev/null |
    awk '
    /signal:/ {
			signal=$2
    }

    /SSID:/ {
        ssid=$0
        sub(/^[[:space:]]*SSID: /, "", ssid)

        if (ssid != "") {
            rssi=signal
            sub(/\..*/, "", rssi)

            percent=int((rssi + 90) * 100 / 60)

            if (percent > 100) percent=100
            if (percent < 0) percent=0

            print ssid "\t" percent
        }
    }
    ' > "$CACHE"
) &

# Get connected network
connected=$(iwctl station "$IFACE" show 2>/dev/null |
    awk '/Connected network/ {
        sub(/^[[:space:]]*Connected network[[:space:]]*/, "")
        print
        exit
    }')

# Use cached results
if [ -f "$CACHE" ]; then

    list=$(awk -v connected="$connected" '
    {
        ssid=$1
        percent=$2

        if (ssid == connected)
            printf "%s  •  %s%%  •  Connected\n", ssid, percent
        else
            printf "%s  •  %s%%\n", ssid, percent
    }
    ' "$CACHE")

else
    list="Scanning for networks..."
fi

# Show menu immediately
choice=$(printf '%s\n' "$list" |
    rofi -dmenu \
    -i \
    -p "Wi-Fi" \
    -theme "$THEME")

[ -z "$choice" ] && exit 0

# Extract SSID
ssid="${choice%%  •*}"

# Already connected
if [ "$ssid" = "$connected" ]; then
    notify-send "Wi-Fi" "$ssid is already connected"
    exit 0
fi

# Password
password=$(rofi -dmenu \
    -password \
    -p "Password" \
    -theme "$THEME")

[ -z "$password" ] && exit 0

if iwctl --passphrase "$password" station "$IFACE" connect "$ssid"; then
    notify-send "Wi-Fi" "Connected to $ssid"
else
    notify-send "Wi-Fi" "Failed to connect to $ssid"
fi
