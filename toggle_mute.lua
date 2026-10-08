#!/usr/bin/env lua

-- 1. Execute system audio switch
os.execute("/usr/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle")

-- 2. Open a pipe stream to safely parse the exact status string
local pipe = io.popen("/usr/bin/wpctl get-volume @DEFAULT_AUDIO_SINK@")
if not pipe then return end
local output = pipe:read("*a")
pipe:close()

-- 3. Direct lane hex maps for your Realtek ALC236 hardware
os.execute("/usr/bin/hda-verb /dev/snd/hwC1D0 0x01 0x717 0x01")
os.execute("/usr/bin/hda-verb /dev/snd/hwC1D0 0x01 0x716 0x01")

-- 4. Evaluate and commit the target state (0x00 = ON, 0x01 = OFF)
if string.find(string.lower(output), "muted") then
	os.execute("/usr/bin/hda-verb /dev/snd/hwC1D0 0x01 0x715 0x00")
else
	os.execute("/usr/bin/hda-verb /dev/snd/hwC1D0 0x01 0x715 0x01")
end
