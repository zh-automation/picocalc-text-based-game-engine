//
//  PicoCalc game API — the "pc" table exposed to Lua game scripts.
//
//  This is the bridge between game scripts on the SD card and the
//  PicoCalc hardware drivers. Screen output is done through the display
//  driver's ANSI terminal emulation (via stdout); keyboard and audio
//  call their drivers directly.
//

#include <stdio.h>

#include "pico/stdlib.h"

#include "lua.h"
#include "lauxlib.h"

#include "drivers/keyboard.h"
#include "drivers/audio.h"

#include "game_api.h"

//
//  Helpers
//

// Map a 0-15 colour index to its ANSI SGR foreground code.
// 0-7 -> 30-37 (normal), 8-15 -> 90-97 (bright).
static int ansi_fg(int idx)
{
    if (idx < 0) idx = 0;
    if (idx > 15) idx = 15;
    return (idx >= 8) ? (90 + (idx - 8)) : (30 + idx);
}

// Map a 0-15 colour index to its ANSI SGR background code.
// 0-7 -> 40-47 (normal), 8-15 -> 100-107 (bright).
static int ansi_bg(int idx)
{
    if (idx < 0) idx = 0;
    if (idx > 15) idx = 15;
    return (idx >= 8) ? (100 + (idx - 8)) : (40 + idx);
}

//
//  Screen
//

// pc.cls() — clear the screen and move the cursor to the top-left.
static int l_cls(lua_State *L)
{
    (void)L;
    printf("\033[2J\033[H");
    fflush(stdout);
    return 0;
}

// pc.write(...) — write the arguments to the screen with no separator
// and no trailing newline. Useful for prompts and partial-line output.
static int l_write(lua_State *L)
{
    int n = lua_gettop(L);
    for (int i = 1; i <= n; i++)
    {
        size_t len;
        const char *s = luaL_tolstring(L, i, &len); // converts numbers too
        fwrite(s, 1, len, stdout);
        lua_pop(L, 1); // remove the string pushed by luaL_tolstring
    }
    fflush(stdout);
    return 0;
}

// pc.print(...) — like pc.write but appends a newline.
static int l_print(lua_State *L)
{
    l_write(L);
    putchar('\n');
    fflush(stdout);
    return 0;
}

// pc.at(x, y) — move the cursor to column x, row y (both 1-based).
static int l_at(lua_State *L)
{
    int x = (int)luaL_checkinteger(L, 1);
    int y = (int)luaL_checkinteger(L, 2);
    printf("\033[%d;%dH", y, x); // ANSI CUP is row;column
    fflush(stdout);
    return 0;
}

// pc.color(fg [, bg]) — set foreground (and optionally background) colour
// using 0-15 palette indices. See the pc.* colour constants.
static int l_color(lua_State *L)
{
    int fg = (int)luaL_checkinteger(L, 1);
    printf("\033[%dm", ansi_fg(fg));
    if (!lua_isnoneornil(L, 2))
    {
        int bg = (int)luaL_checkinteger(L, 2);
        printf("\033[%dm", ansi_bg(bg));
    }
    fflush(stdout);
    return 0;
}

// pc.fg(r, g, b) — set a 24-bit truecolor foreground.
static int l_fg(lua_State *L)
{
    int r = (int)luaL_checkinteger(L, 1);
    int g = (int)luaL_checkinteger(L, 2);
    int b = (int)luaL_checkinteger(L, 3);
    printf("\033[38;2;%d;%d;%dm", r, g, b);
    fflush(stdout);
    return 0;
}

// pc.bg(r, g, b) — set a 24-bit truecolor background.
static int l_bg(lua_State *L)
{
    int r = (int)luaL_checkinteger(L, 1);
    int g = (int)luaL_checkinteger(L, 2);
    int b = (int)luaL_checkinteger(L, 3);
    printf("\033[48;2;%d;%d;%dm", r, g, b);
    fflush(stdout);
    return 0;
}

// pc.reset() — reset all text attributes to their defaults.
static int l_reset(lua_State *L)
{
    (void)L;
    printf("\033[0m");
    fflush(stdout);
    return 0;
}

//
//  Keyboard
//

// pc.getkey() — block until a key is pressed and return its code as an
// integer (compare against pc.KEY_* constants, or string.char() for ASCII).
static int l_getkey(lua_State *L)
{
    char ch = keyboard_get_key(); // blocks until a key is available
    lua_pushinteger(L, (unsigned char)ch);
    return 1;
}

// pc.keyhit() — return true if a key is waiting to be read (non-blocking).
static int l_keyhit(lua_State *L)
{
    lua_pushboolean(L, keyboard_key_available());
    return 1;
}

//
//  Audio
//

// pc.beep() — play a short high beep.
static int l_beep(lua_State *L)
{
    (void)L;
    audio_play_sound_blocking(HIGH_BEEP, HIGH_BEEP, 80);
    return 0;
}

// pc.tone(freq [, ms]) — play a tone on both channels for ms milliseconds
// (default 200). Blocks until the tone finishes.
static int l_tone(lua_State *L)
{
    int freq = (int)luaL_checkinteger(L, 1);
    int ms = (int)luaL_optinteger(L, 2, 200);
    audio_play_sound_blocking(freq, freq, ms);
    return 0;
}

// pc.sound(freq) — start a continuous tone on both channels without
// blocking. Call pc.sound(0) (or pc.stop()) to silence it.
static int l_sound(lua_State *L)
{
    int freq = (int)luaL_checkinteger(L, 1);
    if (freq <= 0)
    {
        audio_stop();
    }
    else
    {
        audio_play_sound(freq, freq);
    }
    return 0;
}

// pc.stop() — stop any non-blocking sound started with pc.sound().
static int l_stop(lua_State *L)
{
    (void)L;
    audio_stop();
    return 0;
}

//
//  Timing
//

// pc.sleep(ms) — pause execution for ms milliseconds.
static int l_sleep(lua_State *L)
{
    int ms = (int)luaL_checkinteger(L, 1);
    if (ms > 0)
    {
        sleep_ms((uint32_t)ms);
    }
    return 0;
}

//
//  Registration
//

static const luaL_Reg pc_funcs[] = {
    {"cls", l_cls},
    {"write", l_write},
    {"print", l_print},
    {"at", l_at},
    {"color", l_color},
    {"fg", l_fg},
    {"bg", l_bg},
    {"reset", l_reset},
    {"getkey", l_getkey},
    {"keyhit", l_keyhit},
    {"beep", l_beep},
    {"tone", l_tone},
    {"sound", l_sound},
    {"stop", l_stop},
    {"sleep", l_sleep},
    {NULL, NULL}};

// A named integer constant to set on the pc table.
typedef struct
{
    const char *name;
    lua_Integer value;
} pc_const_t;

static const pc_const_t pc_consts[] = {
    // Special keys (see drivers/keyboard.h)
    {"KEY_UP", KEY_UP},
    {"KEY_DOWN", KEY_DOWN},
    {"KEY_LEFT", KEY_LEFT},
    {"KEY_RIGHT", KEY_RIGHT},
    {"KEY_ENTER", KEY_RETURN},
    {"KEY_ESC", KEY_ESC},
    {"KEY_SPACE", KEY_SPACE},
    {"KEY_BACKSPACE", KEY_BACKSPACE},
    {"KEY_TAB", KEY_TAB},
    {"KEY_F1", KEY_F1},
    {"KEY_F2", KEY_F2},
    {"KEY_F3", KEY_F3},
    {"KEY_F4", KEY_F4},
    {"KEY_F5", KEY_F5},
    {"KEY_F6", KEY_F6},
    {"KEY_F7", KEY_F7},
    {"KEY_F8", KEY_F8},
    {"KEY_F9", KEY_F9},
    {"KEY_F10", KEY_F10},
    // Colour palette indices (for pc.color)
    {"BLACK", 0},
    {"RED", 1},
    {"GREEN", 2},
    {"YELLOW", 3},
    {"BLUE", 4},
    {"MAGENTA", 5},
    {"CYAN", 6},
    {"WHITE", 7},
    {"GREY", 8},
    {"BRIGHT_RED", 9},
    {"BRIGHT_GREEN", 10},
    {"BRIGHT_YELLOW", 11},
    {"BRIGHT_BLUE", 12},
    {"BRIGHT_MAGENTA", 13},
    {"BRIGHT_CYAN", 14},
    {"BRIGHT_WHITE", 15},
    {NULL, 0}};

void register_game_api(lua_State *L)
{
    luaL_newlib(L, pc_funcs); // new table with the functions

    for (const pc_const_t *c = pc_consts; c->name != NULL; c++)
    {
        lua_pushinteger(L, c->value);
        lua_setfield(L, -2, c->name);
    }

    lua_setglobal(L, "pc"); // pc = { ... }
}
