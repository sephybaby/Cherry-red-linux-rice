#!/bin/bash

wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
sleep 0.1

if wpctl get-volume @DEFAULT_AUDIO_SINK@ | grep -q MUTED; then
    systemd-run --user --machine=@.host --quiet /home/sephy/set_speaker_led.sh on
else
    systemd-run --user --machine=@.host --quiet /home/sephy/set_speaker_led.sh off
fi
