#pragma once

#include "lua.h"

// Registers the "pc" table (PicoCalc game API) as a global in the given
// Lua state. Exposes screen, keyboard, audio, and timing functions plus
// key-code and colour constants for use by game scripts.
void register_game_api(lua_State *L);
