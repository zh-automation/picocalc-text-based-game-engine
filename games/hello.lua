-- hello.lua — the simplest PicoCalc Lua engine demo.
-- When this script finishes, the engine returns to the launcher menu.

pc.cls()
pc.color(pc.BRIGHT_MAGENTA)
pc.print("Hello from a game on the SD card!")
pc.reset()
pc.print("")
pc.print("Press any key and I'll show its code.")

local k = pc.getkey()
pc.print("You pressed code " .. k .. ".")
pc.tone(660, 150)
