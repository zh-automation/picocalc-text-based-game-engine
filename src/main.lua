-- ===========================================================================
-- main.lua -- entry point. Pull the engine, load every content module (in
-- order), then start the game. The require shim caches "engine", so all
-- content modules share the same engine instance and register into it.
-- ===========================================================================
local engine = require("engine")

require("content.floor1")
require("content.floor2")

-- wrap the raw display in the boxed view (top 2/3 = responses, bottom = input).
-- Must happen before run() so every pc.print/pc.input goes through the box.
require("screen").install()

engine.run()
