#!/bin/bash

STATE="/tmp/hp-micmute-led"

# Make sure GPIO0 is enabled before controlling the mic LED
hda-verb /dev/snd/hwC1D0 0x01 0x716 0x01
hda-verb /dev/snd/hwC1D0 0x01 0x717 0x01

if [ -f "$STATE" ]; then
    # Mic is currently muted → unmute → LED OFF
    hda-verb /dev/snd/hwC1D0 0x01 0x717 0x00
    rm -f "$STATE"
else
    # Mic is currently unmuted → mute → LED ON
    for i in 1 2 3 4 5
    do
        hda-verb /dev/snd/hwC1D0 0x01 0x717 0x01
        sleep 0.2
    done
    touch "$STATE"
fi
