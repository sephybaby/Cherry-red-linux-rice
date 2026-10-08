#!/bin/bash

hda-verb /dev/snd/hwC1D0 0x20 0x500 0x07

CURRENT=$(hda-verb /dev/snd/hwC1D0 0x20 0xf00 0x00 | awk '/value =/ {print $3}')

if [ "$1" = "on" ]; then
    NEW=$((CURRENT | 1))
else
    NEW=$((CURRENT & ~1))
fi

hda-verb /dev/snd/hwC1D0 0x20 0x400 "$NEW"
