hl.config({
	input = {
		kb_layout    = "us",
		kb_variant   = "",
		kb_model     = "",
<<<<<<< HEAD
		kb_options   = "caps:super",
=======
		-- kb_options   = "caps:super",
>>>>>>> 1728d4b (mew)
		kb_rules     = "",

		follow_mouse = 1,

		sensitivity  = 0, -- -1.0 - 1.0, 0 means no modification.

		touchpad     = {
			natural_scroll = true,
		},
	},
})

-- Scroll workspace through 3 fingers vertical
hl.gesture({
	fingers = 3,
	direction = "vertical",
	action = "workspace"
})

-- Scrolling with 3 fingers horizontal
hl.gesture({
	fingers = 3,
	direction = "horizontal",
	action = "scroll_move",
	scale = 0.9,
})

-- Fullscreen on with 4 finger pinchout
hl.gesture({
	fingers = 3,
	direction = "pinchin",
	action = function()
		hl.dispatch(hl.dsp.window.fullscreen({ action = "set" }))
	end
})

-- Fullscreen off with 4 finger pinchin
hl.gesture({
	fingers = 3,
	direction = "pinchout",
	action = function()
		hl.dispatch(hl.dsp.window.fullscreen({ action = "unset" }))
	end
})
