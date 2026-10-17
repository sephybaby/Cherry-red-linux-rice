hl.config({
	debug = {
		vfr = true
	}
})

local function apply_ac_profile()
	hl.config({
		animations = { enabled = true },
		decoration = {
			inactive_opacity = 0.8,
			blur = { enabled = true },
			shadow = { enabled = true },
		},
	})

	hl.animation({ leaf = "windows", enabled = true, speed = 3, bezier = "overshot", style = "slide" })
	hl.animation({ leaf = "windowsOut", enabled = true, speed = 100, bezier = "easeOutExpo" })
	hl.animation({ leaf = "windowsIn", enabled = true, speed = 7, bezier = "easeOutBack" })
	hl.animation({ leaf = "windowsMove", enabled = true, speed = 6, bezier = "easeInOutBack", style = "slide" })
	hl.animation({ leaf = "border", enabled = true, speed = 5, bezier = "default" })
	hl.animation({ leaf = "fade", enabled = true, speed = 5, bezier = "easeOutBack" })
	hl.animation({ leaf = "fadeDim", enabled = true, speed = 5, bezier = "easeOutBack" })
	hl.animation({ leaf = "workspaces", enabled = true, speed = 10, bezier = "easeOutExpo" })
end

local function apply_battery_profile()
	hl.config({
		animations = { enabled = false },
		decoration = {
			inactive_opacity = 1.0,
			blur = { enabled = false },
			shadow = { enabled = false },
		},
	})

	hl.animation({ leaf = "windows", enabled = false })
	hl.animation({ leaf = "windowsOut", enabled = false })
	hl.animation({ leaf = "windowsIn", enabled = false })
	hl.animation({ leaf = "windowsMove", enabled = false })
	hl.animation({ leaf = "border", enabled = false })
	hl.animation({ leaf = "fade", enabled = false })
	hl.animation({ leaf = "fadeDim", enabled = false })
	hl.animation({ leaf = "workspaces", enabled = false })
end

local AC_PATH = "/sys/class/power_supply/ACAD/online"
local function is_on_ac()
	local f = io.open(AC_PATH, "r")
	if not f then return true end
	local val = f:read("*l")
	f:close()
	return val == "1"
end

local last_state = nil
hl.timer(function()
	local on_ac = is_on_ac()
	if on_ac ~= last_state then
		last_state = on_ac
		if on_ac then
			apply_ac_profile()
			hl.print("[power] AC connected — animations enabled")
		else
			apply_battery_profile()
			hl.print("[power] On battery — animations disabled")
		end
	end
end, { timeout = 5000, type = "repeat" })
