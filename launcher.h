#pragma once

#include "lua.h"

// Runs the game launcher: scans the SD card for game scripts, presents a
// menu, and runs the selected game (or a Lua console). Never returns.
void run_launcher(lua_State *L);
