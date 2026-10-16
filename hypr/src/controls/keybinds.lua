local mainMod = "SUPER"

-- Applications & Actions
hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("kitty"))
hl.bind("ALT + SPACE", hl.dsp.exec_cmd("~/.config/rofi/launch.sh"))

-- Screenshot
hl.bind("PRINT", hl.dsp.exec_cmd("hyprshot -m region --clipboard-only --freeze"))
hl.bind("SHIFT + PRINT", hl.dsp.exec_cmd("hyprshot -m region --freeze --raw | satty --filename -"))

-- Clipboard
hl.bind(mainMod .. " + V",
	hl.dsp.exec_cmd(
		"cliphist list | rofi -dmenu -theme ~/.config/rofi/clipboard.rasi | cliphist decode | wl-copy"))

-- Requires :D
require("src.controls.keybinds.window_workspace")
require("src.controls.keybinds.fn_keys")
