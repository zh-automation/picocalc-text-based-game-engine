# Writing games for the PicoCalc Lua Game Engine

A game is a single [Lua 5.4](https://www.lua.org/manual/5.4/) script that lives
on the SD card under `/games`. You write it on your computer, copy it to the
card, and pick it from the launcher. No compiling, no flashing — the firmware
is flashed once and runs any game you drop on the card.

This guide covers the execution model, the full `pc` API, input/drawing/audio
patterns, saving progress, and the limitations worth knowing. For a one-page
cheat sheet, see [`games/README.md`](../games/README.md).

## Contents

- [Your first game](#your-first-game)
- [How a game runs](#how-a-game-runs)
- [The `pc` API reference](#the-pc-api-reference)
- [Screen and layout](#screen-and-layout)
- [Keyboard input](#keyboard-input)
- [Audio](#audio)
- [Timing and randomness](#timing-and-randomness)
- [Saving progress](#saving-progress)
- [The Lua environment](#the-lua-environment)
- [Limitations and gotchas](#limitations-and-gotchas)
- [A complete example](#a-complete-example)

## Your first game

Create `hello.lua` and copy it to `/games` on the SD card:

```lua
pc.cls()
pc.print("Hello, PicoCalc!")
pc.print("Press any key.")
pc.getkey()
```

Boot the device, select **hello** from the menu, and it runs. When the script
finishes, you return to the launcher. Press **R** in the launcher to rescan the
card after adding new files.

While developing, the launcher's **[ Lua console ]** entry gives you an
interactive prompt — handy for trying `pc.*` calls one at a time. Type `exit`
to return to the menu.

## How a game runs

- The engine runs your script with Lua's `dofile()`. The script executes top to
  bottom; when it returns (reaches the end, calls `return`, or errors), control
  goes back to the launcher.
- There is no built-in game loop — you write your own `while` loop and decide
  when to break out of it.
- After the script ends, the launcher prints "Press any key to return to the
  menu", so you don't need a final pause of your own.
- If your script raises an error, the launcher shows it in red and returns to
  the menu instead of crashing.

A typical game has this shape:

```lua
-- setup
pc.cls()
local running = true

-- main loop
while running do
  local k = pc.getkey()
  if k == pc.KEY_ESC then
    running = false      -- exit the loop -> back to the launcher
  else
    -- handle input, update state, redraw
  end
end
```

## The `pc` API reference

Everything the hardware exposes is on the global `pc` table.

### Screen and layout

| Function | Description |
|---|---|
| `pc.cls()` | Clear the screen and move the cursor to the top-left. |
| `pc.print(...)` | Print the arguments (joined, numbers converted) followed by a newline. |
| `pc.write(...)` | Like `pc.print` but with **no** trailing newline. |
| `pc.at(x, y)` | Move the cursor to column `x`, row `y` (both 1-based, top-left is 1,1). |
| `pc.color(fg [, bg])` | Set the foreground (and optional background) colour by 0-15 palette index. |
| `pc.fg(r, g, b)` | Set a 24-bit truecolor foreground (each 0-255). |
| `pc.bg(r, g, b)` | Set a 24-bit truecolor background. |
| `pc.reset()` | Reset colours and text attributes to their defaults. |
| `pc.size()` | Return two values: `columns, rows`. |
| `pc.cursor(on)` | Show (`true`) or hide (`false`) the text cursor. |
| `pc.center(y, text)` | Print `text` horizontally centred on row `y`. |
| `pc.box(x, y, w, h)` | Draw a `w`x`h` box border with its top-left cell at `(x, y)`. |

### Keyboard

| Function | Description |
|---|---|
| `pc.getkey()` | Block until a key is pressed; return its code (integer). |
| `pc.keyhit()` | Return `true` if a key is waiting (non-blocking). |
| `pc.input([prompt])` | Print the optional prompt, then read and return a line of text (with echo and backspace). |

### Audio

| Function | Description |
|---|---|
| `pc.beep()` | Play a short high beep. |
| `pc.tone(freq [, ms])` | Play `freq` Hz for `ms` milliseconds (default 200). Blocks until done. |
| `pc.sound(freq)` | Start a continuous tone without blocking. `pc.sound(0)` silences it. |
| `pc.stop()` | Stop a tone started with `pc.sound`. |

### Timing and randomness

| Function | Description |
|---|---|
| `pc.sleep(ms)` | Pause for `ms` milliseconds. |
| `pc.time()` | Milliseconds elapsed since the device booted. |
| `pc.random()` | Random float in `[0, 1)`. |
| `pc.random(m)` | Random integer in `[1, m]`. |
| `pc.random(m, n)` | Random integer in `[m, n]`. |

### Saves

| Function | Description |
|---|---|
| `pc.save(name, data)` | Write the string `data` to `/saves/<name>`; returns `true` on success. |
| `pc.load(name)` | Return the contents of `/saves/<name>` as a string, or `nil` if absent. |
| `pc.saves()` | Return an array (table) of the save file names in `/saves`. |

### Constants

Key codes (compare against `pc.getkey()`):

| Constant | Constant | Constant |
|---|---|---|
| `pc.KEY_UP` | `pc.KEY_DOWN` | `pc.KEY_LEFT` |
| `pc.KEY_RIGHT` | `pc.KEY_ENTER` | `pc.KEY_ESC` |
| `pc.KEY_SPACE` | `pc.KEY_BACKSPACE` | `pc.KEY_TAB` |
| `pc.KEY_F1` … `pc.KEY_F10` | | |

Colour palette indices (for `pc.color`):

| 0-7 (normal) | 8-15 (bright) |
|---|---|
| `pc.BLACK` `pc.RED` `pc.GREEN` `pc.YELLOW` | `pc.GREY` `pc.BRIGHT_RED` `pc.BRIGHT_GREEN` `pc.BRIGHT_YELLOW` |
| `pc.BLUE` `pc.MAGENTA` `pc.CYAN` `pc.WHITE` | `pc.BRIGHT_BLUE` `pc.BRIGHT_MAGENTA` `pc.BRIGHT_CYAN` `pc.BRIGHT_WHITE` |

## Screen and layout

The screen is a grid of character cells. Coordinates are **1-based** with
`(1, 1)` at the top-left; `x` is the column, `y` is the row.

The default font gives a **40 x 32** grid, but don't hard-code that — always
ask:

```lua
local cols, rows = pc.size()
```

Colours come in two flavours. The 16-colour palette is simplest:

```lua
pc.color(pc.BRIGHT_GREEN)            -- foreground only
pc.color(pc.WHITE, pc.BLUE)          -- foreground on background
pc.reset()                           -- back to defaults
```

For exact colours use truecolor:

```lua
pc.fg(255, 128, 0)                   -- orange text
pc.bg(0, 0, 64)                      -- dark blue background
```

Position text precisely and draw frames:

```lua
pc.cls()
pc.box(1, 1, cols, rows)             -- a frame around the screen
pc.center(2, "= MY GAME =")          -- centred title
pc.at(3, 5); pc.write("Score: 0")    -- exact placement
```

## Keyboard input

`pc.getkey()` blocks and returns an integer code. For letters and digits the
code is the ASCII value, so compare with `string.byte`:

```lua
local k = pc.getkey()
if k == string.byte("y") then ... end
if k == pc.KEY_UP then ... end
```

For a non-blocking loop (e.g. animation that keeps running until a key is hit):

```lua
while not pc.keyhit() do
  -- update animation
  pc.sleep(50)
end
local k = pc.getkey()   -- consume the key that was pressed
```

For typed text or numbers, use `pc.input`:

```lua
local name = pc.input("Your name: ")
local n = tonumber(pc.input("Pick 1-10: "))
```

> Input lines are limited to about 127 characters.

## Audio

```lua
pc.beep()                 -- quick feedback blip
pc.tone(440, 300)         -- A4 for 300 ms (blocks)
pc.tone(880, 150)         -- chain tones for melodies

pc.sound(220)             -- start a drone, returns immediately
pc.sleep(1000)            -- ...do something for a second...
pc.stop()                 -- silence it
```

`pc.tone` blocks while it plays; `pc.sound` does not, so use `pc.sound` when the
game needs to keep responding while a tone holds.

## Timing and randomness

`pc.random` is backed by the RP2350 hardware RNG, so you never need to seed it:

```lua
local roll = pc.random(1, 6)        -- a die
local chance = pc.random()          -- 0.0 .. <1.0
```

`pc.time()` returns milliseconds since boot — use it to measure how long
something took or to pace a loop:

```lua
local start = pc.time()
pc.getkey()
local elapsed = pc.time() - start
pc.print("That took " .. elapsed .. " ms")
```

## Saving progress

Saves are just files of text under `/saves`. `pc.save` takes a **string**, so
you decide the format. For a single value, convert it:

```lua
pc.save("score", tostring(highscore))
local hi = tonumber(pc.load("score") or "0")
```

For structured data, format it yourself and parse it back. A simple approach is
one value per line:

```lua
-- save
local data = table.concat({ level, hp, gold }, "\n")
pc.save("progress", data)

-- load
local s = pc.load("progress")
if s then
  local level, hp, gold = s:match("(%d+)\n(%d+)\n(%d+)")
  level, hp, gold = tonumber(level), tonumber(hp), tonumber(gold)
end
```

Use `pc.saves()` to build a "continue" or "load" menu:

```lua
for _, name in ipairs(pc.saves()) do
  pc.print(name)
end
```

Save names must be plain filenames — no `/` or `\`. Prefix them with your
game's name (e.g. `"maze.progress"`) so different games don't collide.

## The Lua environment

The full Lua 5.4 standard library is available **except** `io`, `os`, and
`package`, which are left out because they need operating-system facilities the
PicoCalc doesn't have. So `string`, `table`, `math`, `utf8`, `coroutine`, and
the base functions all work — but reach for the `pc` equivalents instead of the
missing ones:

| Instead of | Use |
|---|---|
| `io.read` / `io.write` | `pc.input` / `pc.write` |
| `io.open` (files) | `pc.save` / `pc.load` |
| `os.time` (seeding) | not needed — `pc.random` is pre-seeded |
| `os.clock` / timing | `pc.time` |

`math.random` still exists, but `pc.random` is the better choice here because it
needs no seed.

## Limitations and gotchas

- **Games must end.** Your loop has to break eventually (usually on a quit key);
  otherwise you can never get back to the launcher.
- **One shared interpreter.** All games run in the same Lua state, so globals
  leak between runs. Always declare your variables `local` and don't rely on a
  global being unset when your game starts.
- **The bottom-right cell.** Writing the screen's very last cell scrolls the
  whole display up one line. `pc.box` already works around this (a full-screen
  box leaves that one corner blank); just avoid writing a character at
  `(cols, rows)` yourself.
- **Screen size varies.** It depends on the active font. Call `pc.size()` rather
  than assuming 40 x 32.
- **`pc.getkey` blocks.** If you need the game to keep moving without input, poll
  with `pc.keyhit()` and only call `pc.getkey()` once one is available.

## A complete example

`reaction.lua` — a reaction-timer game that uses input, randomness, timing,
audio, drawing, and a saved best score. This file is included in
[`games/`](../games/reaction.lua).

```lua
-- reaction.lua — test your reflexes; saves your best time.
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
```

From here, explore the other games in [`games/`](../games/) and start building
your own. Happy hacking.
