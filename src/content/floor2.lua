-- ===========================================================================
-- content/floor2.lua -- the upper floor: landing -> study -> roof
-- ===========================================================================
-- Multi-step puzzle showcase:
--   read the book      -> learn the combination (a flag)
--   unlock the strongbox (gated by that flag, NOT by a key item)
--   open it, take the roof key
--   unlock + open the trapdoor with the roof key
--   go up -> the roof -> win
local g = require("engine")

g.room {
   id = "landing",
   desc = "A drafty landing at the top of the stair. A trapdoor is set in the ceiling.",
   exits = { down = "hall", west = "study" },   -- "up" appears when the trapdoor opens
}
g.room {
   id = "study",
   desc = "A cramped study, every shelf stripped bare but one. A strongbox sits in the corner.",
   exits = { east = "landing" },
}
g.room {
   id = "roof",
   desc = "You haul yourself onto the windswept roof. The drawbridge is far below -- but you are OUT.",
   win = true,
}

g.item {
   id = "book", name = "book", location = "study",
   desc = "A warden's ledger. One page is dog-eared.",
   verbs = {
      read = function(e)
         g.flags().knows_code = true
         pc.print('The dog-eared page reads: "Strongbox latch -- press 3, 1, 7."')
      end,
   },
}

-- a container locked by KNOWLEDGE, not a key: its custom unlock checks a flag
g.container {
   id = "strongbox", name = "strongbox", location = "study", locked = true,
   desc = function(e)
      if e.is_open then return "An open strongbox."
      elseif e.locked then return "A strongbox with a 3-digit latch."
      else return "A strongbox, latch released but lid shut." end
   end,
   verbs = {
      unlock = function(e)
         if not e.locked then
            pc.print("The latch is already released.")
         elseif g.flags().knows_code then
            e.locked = false
            pc.print("You press 3, 1, 7. The latch springs open.")
         else
            pc.print("There's a 3-digit latch. You don't know the combination.")
         end
      end,
   },
}

g.item {
   id = "roofkey", name = "roofkey", location = "strongbox",
   desc = "A heavy brass key stamped with a sun -- the roof key.",
}

g.door {
   id = "trapdoor", name = "trapdoor", location = "landing",
   key = "roofkey",                                  -- opened by the roof key, not the iron key
   leads = { dir = "up", to = "roof", from = "landing" },
}

return true
