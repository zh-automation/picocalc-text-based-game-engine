-- ===========================================================================
-- content/floor1.lua -- the dungeon floor: cell -> hall
-- ===========================================================================
-- A content module is just data + a few closures. It pulls the engine api and
-- calls the authoring helpers. Registration mutates the engine's tables, so
-- this module has nothing useful to return -- we `return true` so the require
-- shim caches it.
local g = require("engine")

-- the player avatar; carried items have location = "player"
g.register("player", { name = "you", verbs = {} }, "cell", {})

g.room {
   id = "cell",
   desc = "A damp stone cell. A heavy door is set in the north wall. A small, barred window allows a meager bit of light to shine into the cell.",
   exits = {},                  -- north appears only once the door is opened
}
g.room {
   id = "hall",
   desc = "A torchlit hall. A spiral stair winds upward; a low door leads back down.",
   exits = { south = "cell", up = "landing" },
}

g.item {
   id = "key", name = "key", location = "bread",   -- baked in the bread
   desc = "A small iron key, cold to the touch.",
}

g.door {
   id = "celldoor", name = "door", location = "cell",
   leads = { dir = "north", to = "hall", from = "cell" },
   -- key defaults to the item proto "key"
}

g.window {
   id = "cellwindow", name = "window", location = "cell",
   barred = true,                            -- permanent scenery: no key opens it, it never opens
   overlooks = "void",                       -- you can still SEE through the bars (see void's glimpse)
   -- The window is barred. react[verb] fires when the window is the TARGET of a
   -- verb -- e.g. "push key through window" or "throw key at window" (push/shove
   -- are parsed as throw). self = the window, projectile = the thing pushed.
   -- Small items slip between the bars and fall into the void, unrecoverable.
   react = {
      throw = function(self, projectile)
         projectile.location = "void"          -- the void is a fatal drop; nothing comes back
         pc.print("You slip the " .. g.P(projectile).name ..
                  " between the bars. It tumbles away into the dark below, gone for good.")
      end,
   },
}

g.room {
   id = "void",
   desc = "Beyond the bars is only open air -- a sheer drop down the tower's outer wall to the courtyard stones far, far below.",
   -- the short version shown when peering through the cell window (see g.window overlooks)
   glimpse = "open air, and a sheer drop down the tower wall to the courtyard far below.",
   -- entering this room ends the game (see the `lose` handling in engine go()).
   lose = "*** You squeeze past the bars and plummet from the tower. YOU DIED ***",
   exits = {},
}

g.item {
   id = "bread", name = "bread", location = "cell",
   state = { is_open = false},
   desc = function(e)
      if e.is_open then return "A hard crust of stale bread, torn open." end
      return "A hard and oddly heavy crust of stale bread." end,
   verbs = {
      open = function(self)
         self.is_open = true
         if #g.contents(self.id) > 0 then
            pc.print("You tear the bread open revealing a key! Weird.")
         else
            pc.print("You continue to tear into the bread. Alas, there is nothing left to find.")
         end
      end,
      eat = function(self)
         if #g.contents(self.id) > 0 then
            pc.print("You bite the hard loaf, but something even harder is inside.")
            return
         end
         self.location = nil                  -- consumed -> in no container -> gone
         pc.print("You choke down the bread. It was less than satisfying.")
      end,
   },
}

g.npc {
   id = "prisoner", name = "prisoner", location = "hall",
   desc = "A gaunt fellow prisoner slumped against the wall.",
   -- react[verb] fires when the prisoner is the TARGET of a verb ("... at/to prisoner").
   -- self = the prisoner, projectile = the thing thrown.
   react = {
      throw = function(self, projectile)
         projectile.location = g.here()      -- it bounces off and lands at your feet
         pc.print('The prisoner flinches and swats it away. "Oi! Throw that at the goblin, not me!"')
      end,
   },
   dialog = {
      start = {
         text = "You got out of your cell? That goblin on the stair won't let anyone past, though.",
         options = {
            { label = "How do I get past it?", next = "hint",
              effect = function() g.flags().knows_hint = true end },
            { label = "I'll manage." },        -- no goto -> ends the chat
         },
      },
      hint = {
         text = "That brute would chase a scrap of food off a cliff. Drop it something to eat and slip by.",
         options = { { label = "Thanks." } },
      },
   },
}

g.enemy {
   id = "goblin", name = "goblin", location = "hall",
   desc = "A wiry goblin crouches on the bottom stair, blocking the way up.",
   guarding = "up",
   tick = function(e)
      local bread = g.E("bread")
      if e.guarding and bread and bread.location == e.location then
         e.guarding = nil
         pc.print("")
         pc.print("The goblin lunges for the bread and drags it into the dark. The stair is clear!")
      end
   end,
}

return true
