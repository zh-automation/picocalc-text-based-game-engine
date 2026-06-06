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
   exits = { down = "cell", up = "landing" },
}

g.container {
   id = "chest", name = "chest", location = "cell",
   desc = function(e) return e.is_open and "A wooden chest, lid thrown open." or "A wooden chest, lid shut." end,
}

g.item {
   id = "key", name = "key", location = "chest",   -- starts INSIDE the chest
   desc = "A small iron key, cold to the touch.",
}

g.door {
   id = "door", name = "door", location = "cell",
   leads = { dir = "north", to = "hall", from = "cell" },
   -- key defaults to the item proto "key"
}

g.item {
   id = "bread", name = "bread", location = "cell",
   desc = "A stale crust of bread.",
   verbs = {
      eat = function(e)
         e.location = nil                  -- consumed -> in no container -> gone
         pc.print("You wolf down the bread. Gone now -- hope you didn't need it.")
      end,
   },
}

g.npc {
   id = "prisoner", name = "prisoner", location = "hall",
   desc = "A gaunt fellow prisoner slumped against the wall.",
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
