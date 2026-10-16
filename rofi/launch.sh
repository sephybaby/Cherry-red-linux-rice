#!/usr/bin/env bash

(pidof rofi && pkill rofi) || rofi \
    -show drun \
    -theme ~/.config/rofi/config.rasi \
	-matching fuzzy
