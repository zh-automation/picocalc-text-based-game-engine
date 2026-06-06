-- ===========================================================================
-- Escape the Tower -- ARCHITECTURE PROTOTYPE
-- ===========================================================================
-- A vertical slice of the "flat entity store" design: one floor, two rooms,
-- a chest, a locked door, a key, an NPC with branching dialog, and an enemy
-- that guards the stairs until you lure it away. Plus save/continue.
--
-- It exercises every mechanism the full game needs, at tiny scale. The
-- 80-room version is "just more data" added at the bottom.
--
-- LUA REMINDERS (you said you're new to it -- these come up constantly):
--   * `local x = ...`  declares a variable. WITHOUT `local`, you make a GLOBAL,
--     which on this engine leaks between games. Always use `local`.
--   * Tables `{}` are Lua's only data structure. Used two ways here:
--       - as an ARRAY:  {10, 20, 30}      -> keys 1,2,3   (use ipairs)
--       - as a MAP:     {locked = true}   -> string keys  (use pairs)
--   * `t.foo` and `t["foo"]` are the same thing.
--   * `function t.f(self) end`  called as `t.f(t)`  is the same as
--     `function t:f() end`      called as `t:f()`.  The `:` just hides `self`.
--   * A value that doesn't exist reads back as `nil` (which is "falsy").
--   * Functions can read variables from the scope they were DEFINED in
--     (closures). That's why all engine helpers are defined BEFORE the content.
-- ===========================================================================

-- setup --------------------------------------------------------------------
pc.cls()
local running = true
local SLOT = "ett.slot1"          -- save file name under /saves

-- ---------------------------------------------------------------------------
-- 1. WORD TABLES  (map a typed word -> a canonical word; membership is O(1))
-- ---------------------------------------------------------------------------
local move_verbs = {              -- words that mean "move"
   go = true, move = true, walk = true, run = true, climb = true, head = true,
}
local dir_canon = {               -- direction synonym -> canonical direction
   north = "north", n = "north",
   south = "south", s = "south",
   west  = "west",  w = "west",
   east  = "east",  e = "east",
   up = "up", u = "up", rise = "up", ascend = "up",
   down = "down", d = "down", descend = "down",
}
local verb_canon = {              -- action synonym -> canonical verb
   look = "look", examine = "look", inspect = "look",
   take = "take", get = "take", grab = "take", pick = "take",
   drop = "drop",
   throw = "throw", toss = "throw", chuck = "throw",
   open = "open", close = "close", shut = "close",
   unlock = "unlock", lock = "lock",
   eat = "eat", drink = "eat",
   talk = "talk", speak = "talk", ask = "talk",
   attack = "attack", hit = "attack", fight = "attack",
   use = "use", read = "read",
}
local filler = {                  -- little words to ignore in commands
   the = true, a = true, an = true, to = true, at = true,
   on = true, into = true, ["in"] = true,   -- "in" is a Lua keyword, so quote it
}

-- ---------------------------------------------------------------------------
-- 2. LOW-LEVEL HELPERS
-- ---------------------------------------------------------------------------

-- split a string into a list of words on whitespace
local function inputsplit(s, sep)
   sep = sep or "%s"
   local t = {}
   for word in string.gmatch(s, "([^" .. sep .. "]+)") do
      t[#t + 1] = word            -- t[#t + 1] = ... is the idiom for "append"
   end
   return t
end

-- copy a table (and any tables inside it) so callers don't share references
local function deepcopy(t)
   if type(t) ~= "table" then return t end
   local c = {}
   for k, v in pairs(t) do c[k] = deepcopy(v) end
   return c
end

-- make a new table = base, then overlaid with extra (extra wins)
local function merge(base, extra)
   local out = {}
   for k, v in pairs(base) do out[k] = v end
   if extra then for k, v in pairs(extra) do out[k] = v end end
   return out
end

-- turn a pure-data table into a string of Lua source we can load() back later.
-- Works ONLY on strings/numbers/booleans/tables -- never functions. That is
-- exactly why game STATE (data) is kept separate from PROTOS (functions).
local function serialize(v)
   local t = type(v)
   if t == "string" then
      return string.format("%q", v)      -- %q adds quotes and escapes specials
   elseif t == "number" or t == "boolean" then
      return tostring(v)
   elseif t == "table" then
      local parts = {}
      for k, val in pairs(v) do
         parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
   end
   error("cannot serialize a " .. t)
end

-- parse a typed line into a command table {verb, noun, tool}, or nil.
local function cmd_parse(input)
   local words = inputsplit(input:lower())
   if #words == 0 then return nil end
   local first = words[1]

   -- a bare direction ("north"), or a move verb + a direction ("go north")
   if dir_canon[first] then
      return { verb = "go", noun = dir_canon[first] }
   end
   if move_verbs[first] then
      for i = 2, #words do
         if dir_canon[words[i]] then
            return { verb = "go", noun = dir_canon[words[i]] }
         end
      end
      return { verb = "go" }              -- "go" with no direction
   end

   -- an action verb, e.g. "unlock the door with the key"
   local v = verb_canon[first]
   if v then
      local cmd = { verb = v }
      local i = 2
      while i <= #words do
         local w = words[i]
         if w == "with" or w == "using" then
            i = i + 1
            while i <= #words and filler[words[i]] do i = i + 1 end
            cmd.tool = words[i]           -- first real word after "with"
            i = i + 1
         elseif filler[w] then
            i = i + 1                      -- skip "the", "to", ...
         else
            if not cmd.noun then cmd.noun = w end   -- first real word = noun
            i = i + 1
         end
      end
      return cmd
   end

   return nil                            -- unknown leading word
end

-- ---------------------------------------------------------------------------
-- 3. THE WORLD MODEL
-- ---------------------------------------------------------------------------
-- protos      : static definitions (verbs/descriptions/dialog). NEVER saved.
-- placements  : the initial layout, used to build a fresh game.
-- world       : the mutable state. world.entities is a FLAT table keyed by id;
--               each entity stores a `location` = the id of its container.
--               This one idea handles inventories, containment, moving items,
--               destroying them, and saving -- all at once.
local protos = {}
local placements = {}
local world = {}

-- short accessors
local function E(id)  return world.entities[id] end          -- entity row by id
local function P(e)   return protos[e.proto] end             -- its prototype
local function here() return E("player").location end        -- current room id

-- the display description -- may be a plain string OR a function of state
local function text_of(e)
   local d = P(e).desc
   if type(d) == "function" then return d(e) else return d end
end

-- list the ids of everything whose container is `cid`
local function contents(cid)
   local out = {}
   for id, e in pairs(world.entities) do
      if e.location == cid then out[#out + 1] = id end
   end
   return out
end

-- can the player touch this entity right now?  (in the room, carried, or
-- inside an OPEN container that is itself reachable)
local function reachable(id)
   local e = E(id)
   if not e then return false end
   local loc = e.location
   if loc == here() or loc == "player" then return true end
   local c = E(loc)
   if c and c.is_open and reachable(loc) then return true end
   return false
end

-- resolve a typed noun to an entity id (match by display name or id)
local function find(noun)
   if not noun then return nil end
   for id, e in pairs(world.entities) do
      if (P(e).name == noun or id == noun) and reachable(id) then
         return id
      end
   end
   return nil
end

-- run an NPC conversation. The tree is static (in the proto); the only saved
-- state is which node we're on (npc.dialog_node).
local function run_dialog(npc)
   local tree = P(npc).dialog
   local nodeid = npc.dialog_node or "start"
   while true do
      local node = tree[nodeid]
      if not node then break end
      pc.print("")
      pc.print(P(npc).name .. ': "' .. node.text .. '"')
      if not node.options or #node.options == 0 then break end
      for i, opt in ipairs(node.options) do
         pc.print("  " .. i .. ") " .. opt.label)
      end
      local choice = tonumber(pc.input("> "))
      local opt = choice and node.options[choice]
      if not opt then
         pc.print("(type the number of a choice)")
      else
         if opt.effect then opt.effect(npc) end       -- side effect (set a flag, give an item)
         -- the field is `next`, NOT `goto` -- `goto` is a reserved Lua keyword
         if opt.next then
            nodeid = opt.next
            npc.dialog_node = nodeid                   -- remember where we left off
         else
            break                                      -- option with no next ends the chat
         end
      end
   end
end

-- print the current room: its description, what's here, and the exits
local function look_room()
   local room = E(here())
   pc.print("")
   pc.print(text_of(room))
   for _, id in ipairs(contents(here())) do
      if id ~= "player" then
         local e = E(id)
         pc.print("  There is a " .. P(e).name .. " here.")
         if e.is_open then
            for _, cid in ipairs(contents(id)) do
               pc.print("    Inside: a " .. P(E(cid)).name)
            end
         end
      end
   end
   local dirs = {}
   for d in pairs(room.exits) do dirs[#dirs + 1] = d end
   if #dirs > 0 then pc.print("Exits: " .. table.concat(dirs, ", ")) end
end

-- move the player in a direction (if there's an exit and nothing blocks it)
local function go(dir)
   if not dir then pc.print("Go where?"); return end
   local room = E(here())
   local dest = room.exits[dir]
   if not dest then pc.print("You can't go " .. dir .. "."); return end
   -- is an enemy in this room guarding that direction?
   for _, id in ipairs(contents(here())) do
      if E(id).guarding == dir then
         pc.print("The " .. P(E(id)).name .. " blocks the way " .. dir .. ".")
         return
      end
   end
   E("player").location = dest
   look_room()
   if E(dest).win then
      pc.print("")
      pc.print("*** YOU ESCAPED THE TOWER ***")
      running = false
   end
end

-- send a parsed command to whichever entity owns the verb
local function apply(cmd)
   if cmd.verb == "go" then go(cmd.noun); return end

   local id = find(cmd.noun)
   if not id then
      pc.print("You don't see any " .. (cmd.noun or "such thing") .. " here.")
      return
   end
   local e = E(id)
   local handler = P(e).verbs[cmd.verb]
   if not handler then
      pc.print("You can't " .. cmd.verb .. " the " .. P(e).name .. ".")
      return
   end
   local tool_id = cmd.tool and find(cmd.tool)
   handler(e, tool_id and E(tool_id) or nil)     -- call as handler(self, tool)
end

-- give every entity with a `tick` a chance to act (called once per turn)
local function tick_all()
   for _, e in pairs(world.entities) do
      local t = P(e).tick
      if t then t(e) end
   end
end

-- build a brand-new game from the placements
local function new_game()
   world.entities = {}
   world.flags = {}
   for _, p in ipairs(placements) do
      local row = deepcopy(p.state)   -- fresh copy of the starting state
      row.id = p.id
      row.proto = p.proto
      row.location = p.location
      world.entities[p.id] = row
   end
end

-- save = serialize the mutable parts; load = compile them back with load()
local function save_game()
   local data = "return {entities=" .. serialize(world.entities) ..
                ",flags=" .. serialize(world.flags) .. "}"
   return pc.save(SLOT, data)
end
local function load_game()
   local s = pc.load(SLOT)
   if not s then return false end
   local chunk = load(s)             -- compile the string into a function
   if not chunk then return false end
   local data = chunk()              -- run it -> get our table back
   world.entities = data.entities
   world.flags = data.flags
   return true
end

-- ---------------------------------------------------------------------------
-- 4. AUTHORING HELPERS  (these are how you add content without boilerplate)
-- ---------------------------------------------------------------------------
-- register() stores a prototype AND records where its single instance starts.
-- (For many-of-a-kind things like "5 goblins", you'd split these: one proto,
--  several placements with different ids that all set proto = "goblin". For a
--  narrative game most things are unique, so 1 proto : 1 instance is simplest.)
local function register(id, proto, location, state)
   protos[id] = proto
   placements[#placements + 1] =
      { id = id, proto = id, location = location, state = state or {} }
end

-- default verbs every takeable item understands
local item_verbs = {
   look  = function(e) pc.print(text_of(e)) end,
   take  = function(e) e.location = "player"; pc.print("You take the " .. P(e).name .. ".") end,
   drop  = function(e) e.location = here();   pc.print("You drop the " .. P(e).name .. ".") end,
   throw = function(e) e.location = "void";   pc.print("You hurl the " .. P(e).name .. " out the window. It's gone for good.") end,
}

local function room(spec)
   register(spec.id,
      { name = spec.name or spec.id, desc = spec.desc, verbs = spec.verbs or {} },
      nil,                                   -- rooms aren't inside anything
      { exits = spec.exits or {}, win = spec.win })
end

local function item(spec)
   register(spec.id,
      { name = spec.name or spec.id, desc = spec.desc,
        verbs = merge(item_verbs, spec.verbs) },   -- item verbs + any extras
      spec.location, spec.state or {})
end

local function container(spec)
   local verbs = merge({
      look = function(e) pc.print(text_of(e)) end,
      open = function(e)
         if e.is_open then pc.print("It's already open."); return end
         e.is_open = true
         pc.print("You open the " .. P(e).name .. ".")
         local inside = contents(e.id)
         if #inside == 0 then
            pc.print("  It's empty.")
         else
            for _, cid in ipairs(inside) do
               pc.print("  Inside is a " .. P(E(cid)).name .. ".")
            end
         end
      end,
      close = function(e) e.is_open = false; pc.print("You close the " .. P(e).name .. ".") end,
   }, spec.verbs)
   register(spec.id, { name = spec.name or "container", desc = spec.desc, verbs = verbs },
            spec.location, { is_open = false })
end

local function door(spec)
   local leads = spec.leads                  -- { dir =, to =, from = }
   local verbs = {
      look = function(e) pc.print(text_of(e)) end,
      unlock = function(e, tool)             -- a TWO-object verb: door + key
         if not e.locked then
            pc.print("It's already unlocked.")
         elseif tool and tool.proto == "key" then
            e.locked = false
            pc.print("The key turns. The lock clicks open.")
         else
            pc.print("You need the right key to unlock it.")
         end
      end,
      open = function(e)
         if e.locked then
            pc.print("It won't budge -- it's locked.")
         elseif e.is_open then
            pc.print("It's already open.")
         else
            e.is_open = true
            E(leads.from).exits[leads.dir] = leads.to   -- the exit now exists
            pc.print("The " .. P(e).name .. " swings open, revealing the way " .. leads.dir .. ".")
         end
      end,
   }
   local desc = spec.desc or function(e)
      if e.is_open then return "An open doorway leads " .. leads.dir .. "."
      elseif e.locked then return "A heavy door blocks the way " .. leads.dir .. ", firmly locked."
      else return "A heavy door, unlocked but still shut." end
   end
   register(spec.id, { name = spec.name or "door", desc = desc, verbs = verbs },
            spec.location, { locked = true, is_open = false })
end

local function npc(spec)
   local verbs = merge({
      look = function(e) pc.print(text_of(e)) end,
      talk = function(e) run_dialog(e) end,
   }, spec.verbs)
   register(spec.id, { name = spec.name, desc = spec.desc, verbs = verbs, dialog = spec.dialog },
            spec.location, { dialog_node = "start" })
end

local function enemy(spec)
   local verbs = merge({
      look   = function(e) pc.print(text_of(e)) end,
      attack = function(e) pc.print("The " .. P(e).name .. " is far too strong to fight head-on.") end,
   }, spec.verbs)
   register(spec.id,
      { name = spec.name, desc = spec.desc, verbs = verbs, tick = spec.tick },
      spec.location, merge({ guarding = spec.guarding }, spec.state))
end

-- ---------------------------------------------------------------------------
-- 5. THE CONTENT  (this is the only part you edit to build the game)
-- ---------------------------------------------------------------------------

-- the player avatar. Carried items have location = "player".
register("player", { name = "you", verbs = {} }, "cell", {})

room {
   id = "cell",
   desc = "A damp stone cell. A heavy door is set in the north wall.",
   exits = {},                  -- the north exit only appears once the door opens
}
room {
   id = "hall",
   desc = "A torchlit hall. A spiral stair winds upward; a low door leads back down.",
   exits = { down = "cell", up = "freedom" },
}
room {
   id = "freedom",
   desc = "You burst through a trapdoor onto the battlements. Open sky, cold wind -- freedom.",
   win = true,
}

container {
   id = "chest", name = "chest", location = "cell",
   desc = function(e) return e.is_open and "A wooden chest, lid thrown open." or "A wooden chest, lid shut." end,
}

item {
   id = "key", name = "key", location = "chest",     -- the key starts INSIDE the chest
   desc = "A small iron key, cold to the touch.",
}

door {
   id = "door", name = "door", location = "cell",
   leads = { dir = "north", to = "hall", from = "cell" },
}

item {
   id = "bread", name = "bread", location = "cell",
   desc = "A stale crust of bread.",
   verbs = {
      eat = function(e)
         e.location = nil          -- consumed: in no container = gone forever
         pc.print("You wolf down the bread. Gone now -- hope you didn't need it.")
      end,
   },
}

npc {
   id = "prisoner", name = "prisoner", location = "hall",
   desc = "A gaunt fellow prisoner slumped against the wall.",
   dialog = {
      start = {
         text = "You got out of your cell? That goblin on the stair won't let anyone past, though.",
         options = {
            { label = "How do I get past it?", next = "hint",
              effect = function() world.flags.knows_hint = true end },
            { label = "I'll manage." },          -- no next -> ends the chat
         },
      },
      hint = {
         text = "That brute would chase a scrap of food off a cliff. Drop it something to eat and slip by.",
         options = { { label = "Thanks." } },
      },
   },
}

enemy {
   id = "goblin", name = "goblin", location = "hall",
   desc = "A wiry goblin crouches on the bottom stair, blocking the way up.",
   guarding = "up",
   tick = function(e)
      local bread = E("bread")
      -- if the bread is loose in the goblin's room, it abandons its post
      if e.guarding and bread and bread.location == e.location then
         e.guarding = nil
         pc.print("")
         pc.print("The goblin lunges for the bread and drags it into the dark. The stair is clear!")
      end
   end,
}

-- ---------------------------------------------------------------------------
-- 6. MAIN LOOP
-- ---------------------------------------------------------------------------
pc.print("=== ESCAPE THE TOWER (prototype) ===")
pc.print("Type 'help' for commands.")

new_game()                          -- always start from a clean world...
if pc.load(SLOT) then               -- ...then offer to load a save over it
   local ans = pc.input("Continue saved game? (y/n) "):lower()
   if ans == "y" or ans == "yes" then
      load_game()
      pc.print("Loaded.")
   end
end

look_room()

while running do
   local line = pc.input("> ")
   local lc = line:lower()

   if lc == "" then
      -- ignore blank input
   elseif lc == "quit" or lc == "q" then
      running = false
   elseif lc == "save" then
      pc.print(save_game() and "Game saved." or "Save failed.")
   elseif lc == "load" then
      if load_game() then look_room() else pc.print("No save found.") end
   elseif lc == "look" or lc == "l" then
      look_room()
   elseif lc == "inventory" or lc == "inv" or lc == "i" then
      local inv = contents("player")
      pc.print("You are carrying:")
      if #inv == 0 then
         pc.print("  nothing")
      else
         for _, id in ipairs(inv) do pc.print("  " .. P(E(id)).name) end
      end
   elseif lc == "help" then
      pc.print("Move: north/south/east/west/up/down (or 'go up').")
      pc.print("Act:  look <x>, take <x>, drop <x>, throw <x>, open <x>,")
      pc.print("      unlock <x> with <y>, eat <x>, talk to <x>, attack <x>.")
      pc.print("Meta: look, inventory, save, load, quit.")
   else
      local cmd = cmd_parse(line)
      if cmd then
         apply(cmd)
         tick_all()                 -- the world reacts after each real action
      else
         pc.print("I don't understand that.")
      end
   end
end
