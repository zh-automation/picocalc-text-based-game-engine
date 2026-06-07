# Building *Escape the Tower*

A developer guide to the game's architecture, authoring workflow, and tooling.
For the underlying hardware/engine API (`pc.*`, screen, audio, saves), see
[`game-development.md`](game-development.md). This document is about the *game*
built on top of it.

## Contents

- [Quick start](#quick-start)
- [Project layout](#project-layout)
- [The big idea: a flat entity store](#the-big-idea-a-flat-entity-store)
- [Prototypes vs. state](#prototypes-vs-state)
- [Authoring content](#authoring-content)
- [Verbs and parsing](#verbs-and-parsing)
- [Two-object verbs and reactions](#two-object-verbs-and-reactions)
- [Dialog trees](#dialog-trees)
- [Behavior over time: ticks and flags](#behavior-over-time-ticks-and-flags)
- [Saving and soft-locks](#saving-and-soft-locks)
- [Adding a new floor](#adding-a-new-floor)
- [Lua gotchas worth remembering](#lua-gotchas-worth-remembering)

## Quick start

From the repo root, in a terminal:

```powershell
.\play.ps1                       # rebuild from src/ and play in the terminal
.\play.ps1 games\ett_proto.lua   # play a specific game file
.\play.ps1 -NoBuild              # skip the build, just play
```

`play.ps1` runs the build and launches the game under desktop Lua via the
[`tools/pc_stub.lua`](../tools/pc_stub.lua) shim, so you never need the hardware
to test. Type commands at the `>` prompt; `help` lists them; `quit` exits.

To only build the shippable single file (without playing):

```powershell
.\build.ps1                      # writes games/escapethetower.lua
```

Then copy `games\escapethetower.lua` to `/games` on the SD card.

> Lua 5.4 is required on the PC. Install once with `winget install DEVCOM.Lua`.
> `play.ps1` finds it on PATH, or falls back to the default install location.

## Project layout

```
src/
  engine.lua            the engine + authoring helpers; returns an api table
  main.lua              entry point: require engine, load floors, run()
  content/
    floor1.lua          cell -> hall
    floor2.lua          landing -> study -> roof
build.ps1               bundles src/**/*.lua -> games/escapethetower.lua
play.ps1                build + play in one step
tools/pc_stub.lua       implements pc.* over the terminal for desktop play
games/
  escapethetower.lua    GENERATED -- do not hand-edit; edit src/ and rebuild
  ett_proto.lua         frozen single-file floor-1 reference (readable example)
```

**Why a build step?** The device runs one `.lua` file via `dofile()` and has no
`require` (`io`/`os`/`package` are removed). So we author in modules and
`build.ps1` concatenates them into one file, prepending a tiny `require` shim.
Each module becomes its own function, which also keeps every file under Lua's
limit of 200 locals per scope as the game grows.

The normal loop is: **edit `src/` → `.\play.ps1` → repeat.** Never edit
`games/escapethetower.lua` directly; it's overwritten on every build.

## The big idea: a flat entity store

Everything in the world — rooms, items, doors, NPCs, enemies, and the player —
is an **entity**: a row in one flat table `world.entities`, keyed by a unique
string id. Each entity stores a `location`, which is the **id of its
container**.

```lua
world.entities = {
  player = { location = "cell" },                 -- you are in the cell
  key    = { location = "chest" },                -- key is inside the chest
  chest  = { location = "cell", is_open = false },
  door   = { location = "cell", locked = true },
}
```

That one `location` field does a remarkable amount of work:

| Question | Answer |
|---|---|
| What's in the cell? | every entity whose `location == "cell"` |
| Your inventory? | every entity whose `location == "player"` |
| Pick something up | set its `location = "player"` |
| Put the key in the chest | `location = "chest"` (containment nests for free) |
| Throw it out the window | `location = "void"` (a place nothing leaves) |
| Eat it / destroy it | `location = nil` (it's in no container = gone) |

Containers nest naturally (`key` in `chest` in `cell`), and "can I touch this?"
is answered by `reachable()`: an entity is reachable if it's in the current
room, carried, or inside an **open** container that is itself reachable.

## Prototypes vs. state

Each entity is split into two halves:

- **Prototype** (`protos[id]`) — the *static* parts: its verbs, description,
  dialog tree, `tick`. This is code/authored data. **It is never saved.**
- **State** (the row in `world.entities`) — the *mutable* parts: `location`,
  `locked`, `is_open`, `hp`, `dialog_node`, etc. This is pure data, so it
  serializes cleanly.

An entity row carries `proto` (a string id), and the engine looks up its
prototype on demand. This split is the whole reason save/load is trivial: no
functions ever end up in a save file, only strings/numbers/booleans/tables.

## Authoring content

A content module pulls the engine api and calls helpers. Each helper takes a
single table (a "spec"). Registration has side effects on the engine, so the
module just ends with `return true`:

```lua
local g = require("engine")

g.room { id = "cell", desc = "A damp stone cell.", exits = { north = "hall" } }
g.item { id = "key", location = "chest", desc = "A small iron key." }

return true
```

### The helpers

**`g.room{ id, desc, exits?, name?, win?, verbs? }`**
A place. `desc` is a string or a `function(self)` returning a string. `exits` is
a map of direction → destination room id (it's mutable state, so a door can add
to it later). Set `win = true` to make entering it end the game.

**`g.item{ id, location, desc, name?, state?, verbs? }`**
A takeable object. Comes with `look`, `take`, `drop`, `throw` for free. Add or
override with `verbs = { ... }` (e.g. give food an `eat`).

**`g.container{ id, location, desc, locked?, name?, state?, verbs? }`**
Holds other entities (put their `location` = this id). Comes with `look`,
`open`, `close`. If `locked = true`, `open` refuses until something clears it —
supply a custom `unlock` verb (by key item, or by a flag — see the strongbox in
[`floor2.lua`](../src/content/floor2.lua)).

**`g.door{ id, location, leads, key?, name?, desc? }`**
A gate between rooms. `leads = { dir = "north", to = "hall", from = "cell" }`.
Comes with `look`, `unlock`, `open`. Opening it adds the exit
`from.exits[dir] = to`. `key` is the item proto id that unlocks it (default
`"key"`); set it for special keys (the roof key, etc.).

**`g.npc{ id, location, name, desc, dialog, verbs? }`**
A character. Comes with `look` and `talk` (which runs its `dialog` tree).

**`g.enemy{ id, location, name, desc, guarding?, tick?, state?, verbs? }`**
A creature. Comes with `look` and `attack`. `guarding = "up"` blocks that
direction out of its room until cleared. `tick` runs every turn (see below).

**`g.register(id, proto, location, state)`** — the low-level primitive the
others build on. Use it directly for one-off entities (the player is registered
this way).

### Verb handlers

A verb is a function stored under its canonical name in the entity's `verbs`
table. It is called as `handler(self, tool, cmd)`:

- `self` — the entity row the verb acts on (read and mutate its state here).
- `tool` — the resolved indirect-object entity (`"unlock door with key"` → the
  key); `nil` if there wasn't one.
- `cmd` — the full parsed command, for the rare verb that needs more than
  `tool`. Notably `cmd.dir` holds a direction target (`"throw bread north"` →
  `cmd.dir == "north"`); also `cmd.verb` / `cmd.noun`. Most verbs ignore it.

```lua
g.item {
  id = "bread", location = "cell", desc = "A stale crust.",
  verbs = {
    eat = function(self)
      self.location = nil                      -- consumed, gone forever
      pc.print("You wolf down the bread.")
    end,
  },
}
```

Inside content closures, reach engine state through the api: `g.E(id)` for
another entity, `g.flags()` for the world flags table, `g.here()` for the
current room id, `g.contents(id)` to list a container's contents.

## Verbs and parsing

Typed input becomes a `{ verb, noun, tool }` command. Synonyms are folded to a
**canonical verb** so handlers only deal with one spelling:

- `take`/`get`/`grab`/`pick` → `take`
- `look`/`examine`/`inspect` → `look`
- `throw`/`toss`/`chuck` → `throw`
- `talk`/`speak`/`ask` → `talk`, etc.

Directions fold too (`n`/`north`, `u`/`up`/`ascend`...), and movement verbs work
both bare (`north`) and with a verb (`go north`).

Only `the`/`a`/`an` are true filler (ignored). Everything else is significant:

- The first plain word after the verb is the **direct object** (`noun`).
- A **preposition** (`with`, `using`, `at`, `to`, `on`, `into`, `in`) introduces
  the **indirect object** — stored in `tool`. So `unlock door with key` →
  `noun=door, tool=key`, and `throw bread at prisoner` → `noun=bread,
  tool=prisoner`.
- A *leading* preposition means its object is the thing acted on: `talk to
  prisoner` → `noun=prisoner` (no separate target). `look at door` →
  `noun=door`.

So all of these parse correctly:

```
unlock the door with the key
throw bread at prisoner
talk to prisoner
go up
```

To add a new verb, add its spelling(s) to `verb_canon` in
[`engine.lua`](../src/engine.lua), then give entities a handler under the
canonical name. Nouns are matched to entities by display `name` or by `id`,
restricted to what's reachable.

## Two-object verbs and reactions

Many verbs involve two things — a direct object and an indirect object (the
`tool`): `unlock door with key`, `throw bread at prisoner`, `give coin to
guard`. There are two ways those resolve, in this order:

1. **The target reacts.** If the indirect object has a `react` entry for the
   verb, it runs and *fully handles* the action — the direct object's verb is
   skipped. `react` is a map of verb → `function(self, other, cmd)`, where
   `self` is the target, `other` is the direct object (the thing
   thrown/given/used), and `cmd` is the full command.

   ```lua
   g.npc {
     id = "prisoner", location = "hall", name = "prisoner",
     react = {
       throw = function(self, projectile)
         projectile.location = g.here()        -- it bounces off and lands here
         pc.print('The prisoner swats it away. "Oi! Not me!"')
       end,
     },
     dialog = { ... },
   }
   ```

   Now `throw bread at prisoner` triggers this instead of the bread's normal
   throw. Any entity can carry a `react` table; it's how you handle "weird
   interactions" without special-casing the engine.

2. **The direct object's verb runs**, receiving the indirect object and command:
   `handler(self, tool, cmd)`. This is how `door.unlock(self, key)` reads the
   key. If the target had no matching `react`, this is what happens.

So with no target (`throw bread`) you get the item's own `throw`; with a target
that doesn't care (`unlock door with key` — keys have no `react`) you get the
direct object's verb and the tool; with a target that *does* care (`throw bread
at prisoner`) the target's reaction wins.

### How the built-in `throw` uses this

The default item `throw` lands the item at the **target's location**:

- `throw bread north` — a direction target (`cmd.dir`); the bread goes to the
  room that exit leads to, or bounces back to your feet if there's no exit that
  way. It never assumes a window.
- `throw bread at goblin` — an entity target with no `react`; the bread lands
  wherever that entity is.
- `throw bread` — no target; it drops at your feet (your current room).

To make something destroy a thrown item ("out the window"), give that feature a
`react.throw` that sets the projectile's `location = "void"` — e.g. a `window`
entity in rooms that have one. That keeps the soft-lock available where it makes
narrative sense, instead of everywhere.

> Reactions are for being the **target** of an action involving another object.
> Single-object oddities (`push statue`) are just ordinary verbs on that object.

## Dialog trees

An NPC's `dialog` is a table of nodes. The conversation starts at `"start"`;
each node has `text` and a list of `options`. An option may carry an `effect`
(a side-effecting function) and a `next` (the node id to continue to). An option
with no `next` ends the chat.

```lua
g.npc {
  id = "prisoner", location = "hall", name = "prisoner",
  desc = "A gaunt fellow prisoner.",
  dialog = {
    start = {
      text = "That goblin won't let anyone past.",
      options = {
        { label = "How do I get past it?", next = "hint",
          effect = function() g.flags().knows_hint = true end },
        { label = "I'll manage." },          -- no `next` -> ends
      },
    },
    hint = {
      text = "It'd chase food off a cliff. Lure it away.",
      options = { { label = "Thanks." } },
    },
  },
}
```

> The field is **`next`**, not `goto`. `goto` is a reserved keyword in Lua 5.4
> and can't be used as a bare table key.

Only the NPC's current node (`dialog_node`) is saved, so a conversation resumes
where it left off after a load.

## Behavior over time: ticks and flags

After every successful command, `tick_all()` gives each entity with a `tick`
function a chance to act. This is how enemies react to the world:

```lua
g.enemy {
  id = "goblin", location = "hall", name = "goblin",
  desc = "A goblin blocks the stairs.", guarding = "up",
  tick = function(self)
    local bread = g.E("bread")
    if self.guarding and bread and bread.location == self.location then
      self.guarding = nil                    -- distracted; stairs now clear
      pc.print("The goblin lunges for the bread. The way up is clear!")
    end
  end,
}
```

**Puzzles are mostly flags.** `g.flags()` returns a live table of booleans you
set in one place and check in another. Reading a book sets `knows_code`; the
strongbox's `unlock` checks it. You rarely need a dedicated "puzzle" entity.

## Saving and soft-locks

`save` serializes `world.entities` + `world.flags` to a Lua literal under
`/saves` (or `./saves` on desktop); `load` compiles it back. Because state is
pure data, this just works — including opened doors, moved items, dialog
progress, and flags.

**Soft-locks are allowed on purpose.** There are deliberately no guard rails
preventing an unwinnable state: eat the bait you needed (`eat` sets
`location = nil`), or toss a needed item into a `"void"` via something like a
`window` entity's `react.throw`, and the game lets you. This is a narrative
choice — verbs freely orphan an item's `location`, and nothing stops them.
(Note the built-in `throw` itself is non-destructive — it relocates to an
adjacent room or your feet; destruction is opt-in per feature.)

## Adding a new floor

1. Create `src/content/floor3.lua`:

   ```lua
   local g = require("engine")

   g.room { id = "attic", desc = "Cobwebs everywhere.", exits = { down = "roof" } }
   -- ...items, doors, npcs, enemies...

   return true
   ```

2. Wire it in [`src/main.lua`](../src/main.lua):

   ```lua
   require("content.floor1")
   require("content.floor2")
   require("content.floor3")     -- add this line
   ```

3. Connect the floors by an exit (e.g. have an existing room's exit, or a door,
   lead to a room id on the new floor).

4. `.\play.ps1` to rebuild and test. `build.ps1` auto-discovers any `.lua` under
   `src/`, so the only manual step is the `require` line.

## Lua gotchas worth remembering

- **`local` or it's global.** A bare assignment makes a global, which *leaks
  between games* on the shared interpreter. Everything in `src/` is `local`.
- **Definition order matters.** A function can only close over `local`s declared
  *above* it. That's why all engine helpers are defined before the content uses
  them.
- **`goto` is reserved** — use `next` for dialog links (above).
- **`pairs` vs `ipairs`.** Use `ipairs` for array-style tables (1,2,3...),
  `pairs` for maps with string keys. Maps have no defined order and `#map` is 0.
- **`:` is sugar.** `obj:verb(x)` means `obj.verb(obj, x)` — `self` is hidden.
- **200 locals per scope.** Modules keep each file under this; if one file ever
  trips it, split it.
- **Scripted playtests need BOM-free input.** Piping commands with PowerShell's
  `|` prepends a BOM that corrupts the first command. For automated solves,
  write commands to an ASCII file and redirect:
  `cmd /c "lua tools\pc_stub.lua < solve.txt"`. Interactive typing is unaffected.
