-- ===========================================================================
-- engine.lua -- the Escape the Tower engine + authoring helpers
-- ===========================================================================
-- This module is `require`d once. It returns an api table `M` that content
-- modules use to register rooms/items/etc., and that main.lua uses to run().
--
-- LUA REMINDER: a "module" here is just a chunk that builds a table `M` and
-- ends with `return M`. The build wraps each file's body in a function, so
-- everything below is local to THIS module -- no globals leak out.
-- ===========================================================================

local M = {}                      -- the api we hand back at the bottom

-- ---------------------------------------------------------------------------
-- 1. WORD TABLES (typed word -> canonical word; membership is an O(1) lookup)
-- ---------------------------------------------------------------------------
local move_verbs = {
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
local filler = {                  -- little words ignored in commands
   the = true, a = true, an = true, to = true, at = true,
   on = true, into = true, ["in"] = true,    -- "in" is a keyword, so quote it
}

-- ---------------------------------------------------------------------------
-- 2. LOW-LEVEL HELPERS
-- ---------------------------------------------------------------------------
local function inputsplit(s, sep)
   sep = sep or "%s"
   local t = {}
   for word in string.gmatch(s, "([^" .. sep .. "]+)") do
      t[#t + 1] = word                       -- append idiom
   end
   return t
end

local function deepcopy(t)
   if type(t) ~= "table" then return t end
   local c = {}
   for k, v in pairs(t) do c[k] = deepcopy(v) end
   return c
end

local function merge(base, extra)            -- base overlaid with extra
   local out = {}
   for k, v in pairs(base) do out[k] = v end
   if extra then for k, v in pairs(extra) do out[k] = v end end
   return out
end

-- serialize pure DATA (strings/numbers/booleans/tables) to loadable Lua source.
-- never sees a function, because functions live in protos, not in state.
local function serialize(v)
   local t = type(v)
   if t == "string" then return string.format("%q", v)
   elseif t == "number" or t == "boolean" then return tostring(v)
   elseif t == "table" then
      local parts = {}
      for k, val in pairs(v) do
         parts[#parts + 1] = "[" .. serialize(k) .. "]=" .. serialize(val)
      end
      return "{" .. table.concat(parts, ",") .. "}"
   end
   error("cannot serialize a " .. t)
end

-- typed line -> { verb, noun, tool } or nil
local function cmd_parse(input)
   local words = inputsplit(input:lower())
   if #words == 0 then return nil end
   local first = words[1]

   if dir_canon[first] then
      return { verb = "go", noun = dir_canon[first] }
   end
   if move_verbs[first] then
      for i = 2, #words do
         if dir_canon[words[i]] then return { verb = "go", noun = dir_canon[words[i]] } end
      end
      return { verb = "go" }
   end

   local v = verb_canon[first]
   if v then
      local cmd = { verb = v }
      local i = 2
      while i <= #words do
         local w = words[i]
         if w == "with" or w == "using" then
            i = i + 1
            while i <= #words and filler[words[i]] do i = i + 1 end
            cmd.tool = words[i]; i = i + 1
         elseif filler[w] then
            i = i + 1
         else
            if not cmd.noun then cmd.noun = w end
            i = i + 1
         end
      end
      return cmd
   end

   return nil
end

-- ---------------------------------------------------------------------------
-- 3. WORLD MODEL
-- ---------------------------------------------------------------------------
-- NOTE: `world` is never reassigned -- only its FIELDS are (world.entities, etc).
-- That is why the accessors below, which close over `world`, always see the
-- current game even after new_game()/load_game() swap the contents.
local protos = {}
local placements = {}
local world = {}
local running = true
local SLOT = "ett.slot1"

local function E(id)  return world.entities[id] end     -- entity row by id
local function P(e)   return protos[e.proto] end        -- its prototype
local function here() return E("player").location end   -- current room id

local function text_of(e)
   local d = P(e).desc
   if type(d) == "function" then return d(e) else return d end
end

local function contents(cid)
   local out = {}
   for id, e in pairs(world.entities) do
      if e.location == cid then out[#out + 1] = id end
   end
   return out
end

local function reachable(id)
   local e = E(id)
   if not e then return false end
   local loc = e.location
   if loc == here() or loc == "player" then return true end
   local c = E(loc)
   if c and c.is_open and reachable(loc) then return true end
   return false
end

local function find(noun)
   if not noun then return nil end
   for id, e in pairs(world.entities) do
      if (P(e).name == noun or id == noun) and reachable(id) then return id end
   end
   return nil
end

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
         if opt.effect then opt.effect(npc) end
         -- NOTE: the field is `next`, NOT `goto` -- `goto` is a reserved Lua keyword.
         if opt.next then nodeid = opt.next; npc.dialog_node = nodeid else break end
      end
   end
end

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

local function go(dir)
   if not dir then pc.print("Go where?"); return end
   local room = E(here())
   local dest = room.exits[dir]
   if not dest then pc.print("You can't go " .. dir .. "."); return end
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
   handler(e, tool_id and E(tool_id) or nil)        -- handler(self, tool)
end

local function tick_all()
   for _, e in pairs(world.entities) do
      local t = P(e).tick
      if t then t(e) end
   end
end

local function new_game()
   world.entities = {}
   world.flags = {}
   for _, p in ipairs(placements) do
      local row = deepcopy(p.state)
      row.id = p.id
      row.proto = p.proto
      row.location = p.location
      world.entities[p.id] = row
   end
end

local function save_game()
   local data = "return {entities=" .. serialize(world.entities) ..
                ",flags=" .. serialize(world.flags) .. "}"
   return pc.save(SLOT, data)
end

local function load_game()
   local s = pc.load(SLOT)
   if not s then return false end
   local chunk = load(s)
   if not chunk then return false end
   local data = chunk()
   world.entities = data.entities
   world.flags = data.flags
   return true
end

-- ---------------------------------------------------------------------------
-- 4. AUTHORING HELPERS
-- ---------------------------------------------------------------------------
-- register() stores a prototype and records its single starting instance.
-- (Many-of-a-kind: register the proto once, then place several ids that set
--  proto = that id. Most narrative objects are unique, so 1:1 is simplest.)
local function register(id, proto, location, state)
   protos[id] = proto
   placements[#placements + 1] =
      { id = id, proto = id, location = location, state = state or {} }
end

local item_verbs = {
   look  = function(e) pc.print(text_of(e)) end,
   take  = function(e) e.location = "player"; pc.print("You take the " .. P(e).name .. ".") end,
   drop  = function(e) e.location = here();   pc.print("You drop the " .. P(e).name .. ".") end,
   throw = function(e) e.location = "void";   pc.print("You hurl the " .. P(e).name .. " out the window. Gone for good.") end,
}

local function room(spec)
   register(spec.id,
      { name = spec.name or spec.id, desc = spec.desc, verbs = spec.verbs or {} },
      nil,
      { exits = spec.exits or {}, win = spec.win })
end

local function item(spec)
   register(spec.id,
      { name = spec.name or spec.id, desc = spec.desc, verbs = merge(item_verbs, spec.verbs) },
      spec.location, spec.state or {})
end

local function container(spec)
   local verbs = merge({
      look = function(e) pc.print(text_of(e)) end,
      open = function(e)
         if e.locked then pc.print("It's locked."); return end
         if e.is_open then pc.print("It's already open."); return end
         e.is_open = true
         pc.print("You open the " .. P(e).name .. ".")
         local inside = contents(e.id)
         if #inside == 0 then
            pc.print("  It's empty.")
         else
            for _, cid in ipairs(inside) do pc.print("  Inside is a " .. P(E(cid)).name .. ".") end
         end
      end,
      close = function(e) e.is_open = false; pc.print("You close the " .. P(e).name .. ".") end,
   }, spec.verbs)
   register(spec.id, { name = spec.name or "container", desc = spec.desc, verbs = verbs },
            spec.location, merge({ is_open = false, locked = spec.locked or false }, spec.state))
end

local function door(spec)
   local leads = spec.leads                  -- { dir =, to =, from = }
   local keyid = spec.key or "key"           -- which item proto unlocks it
   local verbs = {
      look = function(e) pc.print(text_of(e)) end,
      unlock = function(e, tool)             -- a TWO-object verb: door + key
         if not e.locked then
            pc.print("It's already unlocked.")
         elseif tool and tool.proto == keyid then
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
            E(leads.from).exits[leads.dir] = leads.to       -- the exit now exists
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
   register(spec.id, { name = spec.name, desc = spec.desc, verbs = verbs, tick = spec.tick },
            spec.location, merge({ guarding = spec.guarding }, spec.state))
end

-- ---------------------------------------------------------------------------
-- 5. RUN  (called by main.lua after all content modules have registered)
-- ---------------------------------------------------------------------------
local function run()
   pc.cls()
   pc.print("=== ESCAPE THE TOWER ===")
   pc.print("Type 'help' for commands.")

   new_game()
   if pc.load(SLOT) then
      local ans = pc.input("Continue saved game? (y/n) "):lower()
      if ans == "y" or ans == "yes" then load_game(); pc.print("Loaded.") end
   end

   look_room()

   while running do
      local line = pc.input("> ")
      local lc = line:lower()
      if lc == "" then
         -- ignore
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
         if #inv == 0 then pc.print("  nothing")
         else for _, id in ipairs(inv) do pc.print("  " .. P(E(id)).name) end end
      elseif lc == "help" then
         pc.print("Move: north/south/east/west/up/down (or 'go up').")
         pc.print("Act:  look <x>, take <x>, drop <x>, throw <x>, open <x>,")
         pc.print("      unlock <x> with <y>, read <x>, eat <x>, talk to <x>.")
         pc.print("Meta: look, inventory, save, load, quit.")
      else
         local cmd = cmd_parse(line)
         if cmd then apply(cmd); tick_all() else pc.print("I don't understand that.") end
      end
   end
end

-- ---------------------------------------------------------------------------
-- 6. EXPORTS  (what content modules and main.lua are allowed to touch)
-- ---------------------------------------------------------------------------
M.room      = room
M.item      = item
M.container = container
M.door      = door
M.npc       = npc
M.enemy     = enemy
M.register  = register
M.run       = run

-- runtime accessors used inside content closures (ticks, dialog effects):
M.E        = E
M.P        = P
M.here     = here
M.contents = contents
M.flags    = function() return world.flags end   -- live table (call it each time)

return M
