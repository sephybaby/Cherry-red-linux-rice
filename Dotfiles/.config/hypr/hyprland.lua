require("src.monitors")

require("src.autostarts")

require("src.systems.environments")
require("src.systems.permissions")

require("src.look_and_feel.decorations")
require("src.look_and_feel.animations")

require("src.look_and_feel.layouts")

require("src.controls.keybinds")
require("src.controls.inputs")

require("src.systems.window_rules")

require("src.power") -- goes last


hl.window_rule({
	name = "wifi-bluetooth-popup",
	match = { class = "^.*(iwgtk|blueman).*$" },
	float = true,
	size = { "560", "640" },
	move = { "(monitor_w-window_w)/2", "20" },
})
