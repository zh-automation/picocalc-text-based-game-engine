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
function pc.cls()
   io.write("\27[2J\27[H")        -- ANSI clear + home (Windows Terminal/most shells)
   io.flush()
end
function pc.print(...) io.write(joined(...), "\n") end
function pc.write(...) io.write(joined(...)) end
function pc.center(y, text) pc.print(text) end          -- ignore positioning here
function pc.at() end
function pc.color() end
function pc.fg() end
function pc.bg() end
function pc.reset() end
function pc.cursor() end
function pc.box() end
function pc.size() return 40, 32 end

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
