-- ===========================================================================
-- sound.lua -- short 2-3 tone "stingers" tied to player actions.
-- ===========================================================================
-- The device plays one blocking tone at a time via pc.tone(freq_hz, ms).
-- A stinger is just a little list of {freq, ms} notes we play back to back
-- (a freq of 0 is silence, handy for a gap). Each note BLOCKS until it ends,
-- so a stinger takes about the sum of its note durations -- keep them short.
--
-- LUA REMINDER: this file builds a table `M`, fills in a couple of functions,
-- and ends with `return M`. The build shim caches it, so every `require
-- ("sound")` hands back this same table.
-- ===========================================================================

local M = {}

-- name -> sequence of { frequency_hz, duration_ms } notes.
-- Frequencies are rough musical pitches (C5≈523, G5≈784, etc.); the exact
-- values matter less than the shape (rising = good, falling/low = bad).
local stingers = {
   move   = { { 392, 55 }, { 523, 55 } },                 -- two quick rising steps
   take   = { { 523, 40 }, { 659, 55 } },                 -- bright pickup blip
   drop   = { { 494, 40 }, { 330, 60 } },                 -- soft drop down
   open   = { { 523, 40 }, { 784, 90 } },                 -- unlock/open: bright success
   throw  = { { 784, 40 }, { 392, 70 } },                 -- whoosh downward
   talk   = { { 440, 40 }, { 554, 40 }, { 440, 45 } },    -- chatter
   attack = { { 147, 60 }, { 110, 90 } },                 -- low thud
   eat    = { { 330, 40 }, { 262, 70 } },                 -- gulp down
   error  = { { 220, 70 }, { 165, 120 } },                -- low descending buzz
   win    = { { 523, 90 }, { 659, 90 }, { 784, 200 } },   -- rising fanfare
   lose   = { { 392, 130 }, { 330, 130 }, { 196, 280 } }, -- falling dirge
   ok     = { { 523, 40 }, { 659, 50 } },                 -- generic confirm
}

-- canonical verb (from the engine's verb_canon) -> stinger name.
-- Anything not listed falls back to "ok" via M.for_verb below.
local verb_sound = {
   go = "move",
   take = "take", drop = "drop", throw = "throw",
   open = "open", close = "open", unlock = "open", lock = "open",
   talk = "talk", attack = "attack", eat = "eat",
   look = "ok", read = "ok", use = "ok",
}

-- M.play(name) -- play a stinger by name (unknown names play "ok").
function M.play(name)
   local seq = stingers[name] or stingers.ok
   for _, note in ipairs(seq) do
      pc.tone(note[1], note[2])           -- blocks until this note finishes
   end
end

-- M.for_verb(verb) -- map a canonical verb to its stinger name.
function M.for_verb(verb)
   return verb_sound[verb] or "ok"
end

return M
