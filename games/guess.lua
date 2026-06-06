-- guess.lua — Guess the Number, a small demo game for the PicoCalc engine.
-- Shows text colours, line input (pc.input), the hardware RNG (pc.random),
-- and audio. The engine returns to the launcher when this script finishes.

local secret = pc.random(1, 100)
local tries = 0

pc.cls()
pc.color(pc.BRIGHT_CYAN)
pc.print("=== Guess the Number ===")
pc.reset()
pc.print("I'm thinking of a number from 1 to 100.")
pc.print("")

while true do
  local line = pc.input("Your guess (or 'q' to quit): ")

  if line == "q" or line == "Q" then
    pc.print("The number was " .. secret .. ". Bye!")
    break
  end

  local guess = tonumber(line)
  if not guess then
    pc.color(pc.YELLOW)
    pc.print("Please type a whole number.")
    pc.reset()
  elseif guess < secret then
    pc.print("Too low.")
    pc.tone(220, 80)
  elseif guess > secret then
    pc.print("Too high.")
    pc.tone(220, 80)
  else
    tries = tries + 1
    pc.color(pc.BRIGHT_GREEN)
    pc.print("Correct! You got it in " .. tries .. " guesses.")
    pc.reset()
    pc.tone(880, 120)
    pc.tone(1175, 200)
    break
  end

  tries = tries + 1
end
