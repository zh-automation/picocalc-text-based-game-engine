#include <stdio.h>

#include "pico/stdlib.h"

#include "drivers/picocalc.h"
#include "drivers/display.h"
#include "drivers/onboard_led.h"

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

#include "game_api.h"
#include "launcher.h"

bool power_off_requested = false;

// Set by the keyboard/serial drivers when the user presses Break (Ctrl+C
// on serial). Drivers reference it via extern; the application owns it.
volatile bool user_interrupt = false;

void set_onboard_led(uint8_t led)
{
    led_set(led & 0x01);
}

int main()
{
    // Initialize the LED driver and set the LED callback.
    // If the LED driver fails to initialize, we can still run without LED
    // support, so we simply skip registering the callback.
    int led_init_result = led_init();

    stdio_init_all();
    picocalc_init();
    if (led_init_result == 0) {
        display_set_led_callback(set_onboard_led);
    }

    // Create the Lua interpreter, load the standard libraries, and expose
    // the "pc" hardware API to game scripts.
    lua_State *L = luaL_newstate();
    if (L == NULL) {
        printf("\033cFATAL: could not allocate Lua state (out of memory).\n");
        while (true) { tight_loop_contents(); }
    }
    luaL_openlibs(L);
    register_game_api(L);

    // Hand control to the launcher: it presents the game menu, runs the
    // selected game, and never returns.
    run_launcher(L);

    return 0;
}
