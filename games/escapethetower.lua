-- Escape the Tower -- prototype slice: one cell, a locked door, a key.
-- Demonstrates: a parser that returns {verb, noun, tool}, object tables that
-- each carry the verbs they understand, and a dispatch that lets every object
-- handle its own verbs (with a sensible default when it doesn't).

-- setup
pc.cls()
local running = true

-- command lookup tables: word -> meaning (membership is just an index)
local move_verbs = {
   go = true, move = true, walk = true, run = true, jog = true, mosey = true,
}
local action_verbs = {
   get = true, take = true, drop = true, open = true, close = true,
   unlock = true, lock = true, use = true, look = true, read = true,
}
-- direction synonym -> canonical direction name
local dir_canon = {
   north = "north", n = "north",
   south = "south", s = "south",
   west  = "west",  w = "west",
   east  = "east",  e = "east",
   up = "up", u = "up", rise = "up", ascend = "up",
   down = "down", d = "down", descend = "down",
}

-- split an input string on whitespace (or a given separator class)
local function inputsplit(inputstr, sep)
   sep = sep or "%s"
   local t = {}
   for str in string.gmatch(inputstr, "([^" .. sep .. "]+)") do
      table.insert(t, str)
   end
   return t
end

-- parse a typed line into a command table {verb, noun, tool}, or nil if the
-- leading word isn't a verb we know.
local function cmd_parse(input)
   local words = inputsplit(input:lower())
   if #words == 0 then return nil end

   local first = words[1]

   -- a bare direction ("north") or a movement verb ("go north") -> "go"
   if dir_canon[first] then
      return { verb = "go", noun = dir_canon[first] }
   end
   if move_verbs[first] then
      return { verb = "go", noun = dir_canon[words[2]] }
   end

   -- an action verb: "take key", or "unlock door with key"
   if action_verbs[first] then
      local cmd = { verb = first, noun = words[2] }
      for i = 3, #words - 1 do            -- scan for "with <tool>"
         if words[i] == "with" then
            cmd.tool = words[i + 1]
            break
         end
      end
      return cmd
   end

   return nil   -- unrecognized verb
end

-- ---------------------------------------------------------------------------
-- World model
-- ---------------------------------------------------------------------------
local rooms                  -- forward-declared: the objects below close over it
local player = { room = "cell", inventory = {} }

-- An "object" is just a table: some state, plus a `verbs` table of the verbs
-- it understands. Each handler is called as handler(self, tool).
local key = {
   name = "key",
   verbs = {
      take = function(self)
         rooms[player.room].objects[self.name] = nil   -- leave the room
         player.inventory[self.name] = self            -- enter the pack
         pc.print("You pocket the iron key.")
      end,
      look = function(self)
         pc.print("A small iron key, worn smooth with age.")
      end,
   },
}

local door = {
   name = "door",
   locked = true,
   is_open = false,
   verbs = {
      look = function(self)
         if self.is_open then
            pc.print("The heavy door stands open.")
         elseif self.locked then
            pc.print("A heavy wooden door, firmly locked.")
         else
            pc.print("A heavy wooden door, unlocked but shut.")
         end
      end,
      -- a two-object verb: the door owns it and inspects the tool
      unlock = function(self, tool)
         if not self.locked then
            pc.print("It's already unlocked.")
         elseif tool and tool.name == "key" then
            self.locked = false
            pc.print("The key turns. The lock clicks open.")
         else
            pc.print("You need the right key to unlock it.")
         end
      end,
      open = function(self)
         if self.locked then
            pc.print("It won't budge -- it's locked.")
         elseif self.is_open then
            pc.print("It's already open.")
         else
            self.is_open = true
            rooms.cell.exits.north = "stairs"   -- opening it reveals the way out
            pc.print("The door swings open onto a dark stairwell.")
         end
      end,
   },
}

rooms = {
   cell = {
      desc = "A cold stone cell. A heavy door is set in the north wall.",
      objects = { key = key, door = door },
      exits = {},                          -- "north" appears once the door opens
   },
   stairs = {
      desc = "A spiral stair climbs into darkness. Fresh air drifts from above.",
      objects = {},
      exits = { down = "cell", up = "freedom" },
   },
   freedom = {
      desc = "You burst onto the battlements under open sky. You've escaped!",
      objects = {},
      exits = {},
      win = true,
   },
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
local function describe(room)
   pc.print("")
   pc.print(room.desc)
   for name in pairs(room.objects) do
      pc.print("  There is a " .. name .. " here.")
   end
end

-- resolve a noun word to an object: check the pack first, then the room
local function find(name)
   if not name then return nil end
   return player.inventory[name] or rooms[player.room].objects[name]
end

local function go(dir)
   local dest = rooms[player.room].exits[dir]
   if dest then
      player.room = dest
      describe(rooms[player.room])
      if rooms[player.room].win then
         running = false                   -- reaching the win room ends the game
      end
   else
      pc.print("You can't go " .. (dir or "that way") .. ".")
   end
end

-- route a parsed command to whichever object owns the verb
local function apply(cmd)
   if cmd.verb == "go" then
      go(cmd.noun)
      return
   end

   local obj = find(cmd.noun)
   if not obj then
      pc.print("You don't see any " .. (cmd.noun or "such thing") .. ".")
      return
   end

   local handler = obj.verbs[cmd.verb]
   if handler then
      handler(obj, find(cmd.tool))         -- self, plus the tool object (may be nil)
   else
      pc.print("You can't " .. cmd.verb .. " the " .. obj.name .. ".")
   end
end

local function show_inventory()
   pc.print("You are carrying:")
   local empty = true
   for name in pairs(player.inventory) do
      pc.print("  " .. name)
      empty = false
   end
   if empty then pc.print("  nothing") end
end

-- ---------------------------------------------------------------------------
-- Main loop
-- ---------------------------------------------------------------------------
describe(rooms[player.room])

while running do
   local line = pc.input("> ")

   if line == "quit" or line == "q" then
      running = false
   elseif line == "look" or line == "l" then
      describe(rooms[player.room])          -- bare "look" = look at the room
   elseif line == "inventory" or line == "inv" or line == "i" then
      show_inventory()
   else
      local cmd = cmd_parse(line)
      if cmd then
         apply(cmd)
      else
         pc.print("I don't understand that.")
      end
   end
end
