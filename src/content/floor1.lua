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
   desc = "A damp stone cell. A heavy door is set in the north wall.",
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
   id = "door", name = "door", location = "cell",
   leads = { dir = "north", to = "hall", from = "cell" },
   -- key defaults to the item proto "key"
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
            pc.print("You continue to tear into the bread. Alas, there is nothing left to find")
         end
      end,
      eat = function(self)
         if #g.contents(self.id) > 0 then
            pc.print("You bite the hard loaf, but something even harder is inside")
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
