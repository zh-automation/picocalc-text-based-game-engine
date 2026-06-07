-- ===========================================================================
-- tools/pc_stub.lua -- play a PicoCalc game on your PC in the terminal.
-- ===========================================================================
-- The device exposes a global `pc` table (screen, keyboard, saves, audio...).
-- This file implements just enough of that table with plain terminal I/O so a
-- game written for the engine can run under desktop Lua 5.4.
--
-- Usage (from the repo root):
--     lua5.4 tools/pc_stub.lua                      -- runs games/escapethetower.lua
--     lua5.4 tools/pc_stub.lua games/ett_proto.lua  -- runs a specific game
--
-- It also works with input piped in, which is handy for scripted playtests:
--     Get-Content solve.txt | lua5.4 tools/pc_stub.lua      (PowerShell)
--     lua5.4 tools/pc_stub.lua < solve.txt                  (bash)
--
-- Saves are written to ./saves/<name> instead of the device's /saves.
-- ===========================================================================

-- where to keep save files, and whether we're on Windows (for the mkdir flavor)
local SAVE_DIR  = "saves"
local IS_WINDOWS = package.config:sub(1, 1) == "\\"

local function ensure_save_dir()
   -- best-effort: ignore "already exists" errors from the shell
   if IS_WINDOWS then
      os.execute('if not exist "' .. SAVE_DIR .. '" mkdir "' .. SAVE_DIR .. '"')
   else
      os.execute('mkdir -p "' .. SAVE_DIR .. '" 2>/dev/null')
   end
end

-- join print arguments the way the device does: concatenated, no separators
local function joined(...)
   local n = select("#", ...)
   local parts = {}
   for i = 1, n do parts[i] = tostring((select(i, ...))) end
   return table.concat(parts)
end

-- The global the game expects.
pc = {}

-- --- screen ---------------------------------------------------------------
-- These mirror the device's game_api.c, which drives an ANSI terminal. Emitting
-- the same escape sequences lets the boxed layout render in an ANSI terminal
-- (e.g. Windows Terminal) exactly as it does on the PicoCalc.
local COLS, ROWS = 40, 32

function pc.cls()
   io.write("\27[2J\27[H")        -- ANSI clear + home
   io.flush()
end
function pc.print(...) io.write(joined(...), "\n"); io.flush() end
function pc.write(...) io.write(joined(...)); io.flush() end

-- pc.at(x, y) -- move the cursor to column x, row y (1-based). ANSI is row;col.
function pc.at(x, y)
   io.write(string.format("\27[%d;%dH", y, x))
   io.flush()
end

-- pc.center(y, text) -- print text horizontally centred on row y.
function pc.center(y, text)
   local x = math.floor((COLS - #text) / 2) + 1
   if x < 1 then x = 1 end
   io.write(string.format("\27[%d;%dH", y, x), text)
   io.flush()
end

-- map a 0-15 palette index to its ANSI SGR foreground/background code
local function ansi_fg(i) i = math.max(0, math.min(15, i)); return (i >= 8) and (90 + i - 8) or (30 + i) end
local function ansi_bg(i) i = math.max(0, math.min(15, i)); return (i >= 8) and (100 + i - 8) or (40 + i) end

function pc.color(fg, bg)
   io.write(string.format("\27[%dm", ansi_fg(fg)))
   if bg then io.write(string.format("\27[%dm", ansi_bg(bg))) end
   io.flush()
end
function pc.fg(r, g, b) io.write(string.format("\27[38;2;%d;%d;%dm", r, g, b)); io.flush() end
function pc.bg(r, g, b) io.write(string.format("\27[48;2;%d;%d;%dm", r, g, b)); io.flush() end
function pc.reset() io.write("\27[0m"); io.flush() end
function pc.cursor(on) io.write(on and "\27[?25h" or "\27[?25l"); io.flush() end

-- pc.box(x, y, w, h) -- draw a box border using the DEC line-drawing charset,
-- the same way the device does (ESC(0 ... l q k / x / m q j ... ESC(B).
function pc.box(x, y, w, h)
   if w < 2 or h < 2 then return end
   local clips = (y + h - 1 >= ROWS) and (x + w - 1 >= COLS)
   io.write("\27(0")                               -- select DEC special graphics
   io.write(string.format("\27[%d;%dH", y, x), "l", string.rep("q", w - 2), "k")
   for r = y + 1, y + h - 2 do
      io.write(string.format("\27[%d;%dHx", r, x))
      io.write(string.format("\27[%d;%dHx", r, x + w - 1))
   end
   io.write(string.format("\27[%d;%dH", y + h - 1, x), "m", string.rep("q", w - 2))
   if not clips then io.write("j") end
   io.write("\27(B")                               -- back to ASCII
   io.flush()
end

function pc.size() return COLS, ROWS end

-- --- keyboard --------------------------------------------------------------
function pc.input(prompt)
   if prompt then io.write(prompt) end
   io.flush()
   local line = io.read("l")
   if line == nil then return "quit" end   -- EOF (piped input ran out) -> quit cleanly
   return line
end
function pc.getkey() return 0 end
function pc.keyhit() return false end

-- key-code / colour constants the engine might reference (values are arbitrary)
for i, name in ipairs({
   "KEY_UP", "KEY_DOWN", "KEY_LEFT", "KEY_RIGHT", "KEY_ENTER", "KEY_ESC",
   "KEY_SPACE", "KEY_BACKSPACE", "KEY_TAB",
}) do pc[name] = -i end
for i, name in ipairs({
   "BLACK", "RED", "GREEN", "YELLOW", "BLUE", "MAGENTA", "CYAN", "WHITE",
   "GREY", "BRIGHT_RED", "BRIGHT_GREEN", "BRIGHT_YELLOW",
   "BRIGHT_BLUE", "BRIGHT_MAGENTA", "BRIGHT_CYAN", "BRIGHT_WHITE",
}) do pc[name] = i - 1 end

-- --- audio (no-ops) --------------------------------------------------------
function pc.beep() end
function pc.tone() end
function pc.sound() end
function pc.stop() end

-- --- timing / randomness ---------------------------------------------------
function pc.sleep(ms) end
function pc.time() return math.floor(os.clock() * 1000) end
function pc.random(m, n)
   if not m then return math.random() end
   if not n then return math.random(m) end
   return math.random(m, n)
end

-- --- saves (use local files under ./saves) ---------------------------------
local function save_path(name) return SAVE_DIR .. "/" .. name end

function pc.save(name, data)
   ensure_save_dir()
   local f = io.open(save_path(name), "w")
   if not f then return false end
   f:write(data)
   f:close()
   return true
end
function pc.load(name)
   local f = io.open(save_path(name), "r")
   if not f then return nil end
   local data = f:read("a")
   f:close()
   return data
end
function pc.saves()
   -- not needed by the current game; return an empty list
   return {}
end

-- ---------------------------------------------------------------------------
-- run the requested game
-- ---------------------------------------------------------------------------
local game = arg and arg[1] or "games/escapethetower.lua"
local ok, err = pcall(dofile, game)
if not ok then
   io.write("\n[pc_stub] the game raised an error:\n", tostring(err), "\n")
   os.exit(1)
end
