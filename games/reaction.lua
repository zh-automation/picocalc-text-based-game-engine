-- reaction.lua — test your reflexes; saves your best time.
-- The worked example from docs/game-development.md.

local best = tonumber(pc.load("reaction.best") or "")

pc.cls()
pc.color(pc.BRIGHT_CYAN)
pc.center(2, "REACTION TIMER")
pc.reset()
if best then
  pc.center(4, "Best: " .. best .. " ms")
end
pc.center(7, "Wait for GO, then press any key.")
pc.center(9, "Press a key to start...")
pc.getkey()

-- Random delay so you can't anticipate it.
pc.cls()
pc.center(11, "Get ready...")
pc.sleep(pc.random(1000, 4000))

-- GO!
pc.cls()
pc.color(pc.BRIGHT_GREEN)
pc.center(11, ">>> GO <<<")
pc.reset()
pc.beep()

local start = pc.time()
pc.getkey()
local elapsed = pc.time() - start

pc.cls()
pc.center(11, "You reacted in " .. elapsed .. " ms")

if not best or elapsed < best then
  pc.save("reaction.best", tostring(elapsed))
  pc.color(pc.BRIGHT_YELLOW)
  pc.center(13, "New best time!")
  pc.reset()
  pc.tone(880, 120)
  pc.tone(1175, 200)
end
