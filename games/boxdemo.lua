-- boxdemo.lua — shows the richer screen API: pc.size, pc.box, pc.center,
-- and pc.cursor. Press any key to exit.

local cols, rows = pc.size()

pc.cls()
pc.cursor(false) -- hide the cursor for a cleaner display

-- Frame around the whole screen.
pc.color(pc.BRIGHT_BLUE)
pc.box(1, 1, cols, rows)
pc.reset()

-- A centred title near the top.
pc.color(pc.BRIGHT_WHITE)
pc.center(3, "PicoCalc Screen API")
pc.reset()
pc.center(5, "Screen is " .. cols .. " x " .. rows .. " cells")

-- A smaller inner box with a label.
local bw, bh = 24, 5
local bx = (cols - bw) // 2 + 1
local by = 9
pc.color(pc.GREEN)
pc.box(bx, by, bw, bh)
pc.reset()
pc.center(by + 2, "boxes!")

pc.center(rows - 2, "Press any key...")
pc.getkey()

pc.cursor(true) -- restore the cursor before returning to the launcher
