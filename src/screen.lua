-- ===========================================================================
-- screen.lua -- a boxed, buffered view over the raw pc display.
-- ===========================================================================
-- The game code keeps calling pc.print/pc.write exactly as before. This module
-- WRAPS those functions so that, instead of streaming straight down the screen,
-- output collects in a buffer and is drawn inside a box in the top 2/3 of the
-- screen. The bottom third holds a second box where the player types commands.
--
-- There is no scrolling: each new response clears the box and redraws. The
-- buffer is cleared lazily -- the first print of a NEW response wipes the old
-- one -- so pressing Enter on an empty line just redraws the current screen
-- rather than blanking it.
--
-- LUA REMINDER: we grab the ORIGINAL pc functions into locals first ("raw_*"),
-- then replace pc.print/pc.write/pc.input/pc.cls with our own. Our versions
-- call the raw ones to actually touch the hardware. Capturing them up front is
-- what lets us override the public names without losing the real behaviour.
-- ===========================================================================

local M = {}

-- the genuine display primitives, captured before we shadow the public names
local raw_cls   = pc.cls
local raw_print = pc.print
local raw_write = pc.write
local raw_input = pc.input
local raw_at    = pc.at
local raw_box   = pc.box

-- --- layout geometry (computed once from the real screen size) -------------
local COLS, ROWS = pc.size()                 -- 40 x 32 on the PicoCalc

-- response box: the top two-thirds
local RESP_X, RESP_Y = 1, 1
local RESP_W = COLS
local RESP_H = math.floor(ROWS * 2 / 3)      -- 21 rows (1..21)

-- a 2-cell margin between the text and the box border, all the way around
local MARGIN = 2
local TEXT_X = RESP_X + 1 + MARGIN           -- col 4
local TEXT_W = RESP_W - 2 * (1 + MARGIN)     -- 34 chars per line
local TEXT_Y = RESP_Y + 1 + MARGIN           -- row 4
local TEXT_H = RESP_H - 2 * (1 + MARGIN)     -- 15 text rows (4..18)

-- input box: a thin box near the top of the bottom third
local IN_X, IN_Y = 1, RESP_Y + RESP_H + 1    -- row 23 (one blank row below the response box)
local IN_W, IN_H = COLS, 3                    -- rows 23..25
local PROMPT_X = IN_X + 1 + MARGIN           -- col 4, lined up with the text
local PROMPT_Y = IN_Y + 1                     -- row 24, the box interior

-- --- output buffer ----------------------------------------------------------
local buffer = {}        -- list of already-wrapped display lines
local pending = nil      -- partial line built up by pc.write (no newline yet)
local fresh = true       -- true => the next print starts a brand new response

-- concatenate args the way the device's pc.print does: tostring, no separators
local function joined(...)
   local n = select("#", ...)
   local parts = {}
   for i = 1, n do parts[i] = tostring((select(i, ...))) end
   return table.concat(parts)
end

-- word-wrap one logical line (which may contain \n) to TEXT_W columns,
-- preserving any leading indentation on continuation lines.
local function wrap(text)
   local out = {}
   for raw in (text .. "\n"):gmatch("(.-)\n") do      -- split on explicit newlines
      raw = raw:gsub("\t", "   ")
      if raw == "" then
         out[#out + 1] = ""                            -- keep blank lines for spacing
      else
         local indent = raw:match("^(%s*)")
         local line = nil
         for word in raw:gmatch("%S+") do
            if line == nil then
               line = indent .. word
            elseif #line + 1 + #word <= TEXT_W then
               line = line .. " " .. word
            else
               out[#out + 1] = line
               line = indent .. word                   -- wrapped piece keeps the indent
            end
            while #line > TEXT_W do                     -- a single over-long word: hard-split
               out[#out + 1] = line:sub(1, TEXT_W)
               line = indent .. line:sub(TEXT_W + 1)
            end
         end
         out[#out + 1] = line
      end
   end
   return out
end

-- append a chunk of text to the buffer, clearing first if a new response began
local function append(text)
   if fresh then buffer = {}; pending = nil; fresh = false end
   if pending then text = pending .. text; pending = nil end
   for _, l in ipairs(wrap(text)) do buffer[#buffer + 1] = l end
end

-- draw the boxes and the buffered text (showing the last TEXT_H lines)
local function render()
   raw_cls()
   raw_box(RESP_X, RESP_Y, RESP_W, RESP_H)
   raw_box(IN_X, IN_Y, IN_W, IN_H)

   local n = #buffer
   local first = math.max(1, n - TEXT_H + 1)            -- only the newest lines fit
   local y = TEXT_Y
   for i = first, n do
      raw_at(TEXT_X, y)
      raw_write(buffer[i])
      y = y + 1
   end
end

-- --- the wrapped public API -------------------------------------------------

local function w_print(...)
   append(joined(...))           -- wrap() supplies the line break; don't add one here
end

local function w_write(...)
   if fresh then buffer = {}; pending = nil; fresh = false end
   pending = (pending or "") .. joined(...)
end

local function w_cls()
   buffer = {}; pending = nil; fresh = false
   raw_cls()
end

-- pc.input([prompt]) -- a passed prompt is shown as a line in the RESPONSE box
-- (it's part of the conversation); the caret is drawn in the input box. The
-- default "> " command prompt is treated as a plain caret, not response text.
local function w_input(prompt)
   if prompt and prompt ~= "" and prompt ~= "> " then
      append(tostring(prompt))
   end
   render()
   raw_at(PROMPT_X, PROMPT_Y)
   raw_write("> ")
   local line = raw_input()              -- read at the caret (device echoes here)
   fresh = true                          -- next print opens a fresh response
   return line
end

-- pc.flush() -- redraw the current buffer (for end-of-game messages that are
-- printed but never followed by another input). Returns true if it drew text.
local function w_flush()
   if #buffer == 0 then return false end
   render()
   return true
end

-- M.install() -- shadow the public pc functions with the boxed versions.
function M.install()
   pc.print = w_print
   pc.write = w_write
   pc.cls   = w_cls
   pc.input = w_input
   pc.flush = w_flush
end

return M
