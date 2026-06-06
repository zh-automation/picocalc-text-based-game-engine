#include <stdio.h>
#include <string.h>

#include "pico/stdlib.h"

#include "drivers/picocalc.h"
#include "drivers/display.h"
#include "drivers/keyboard.h"
#include "drivers/onboard_led.h"

#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

bool power_off_requested = false;

void set_onboard_led(uint8_t led)
{
    led_set(led & 0x01);
}

#include <ctype.h>

void str_to_lower(char *s) {
    while (*s) {
        *s = tolower((unsigned char)*s);
        s++;
    }
}

void readline(char *buffer, size_t size)
{
    size_t index = 0;
    while (true)
    {
        char ch = getchar();
        if (ch == 0x04) // Ctrl+D to debug
        {
            printf("Entering debug mode...\n");
            __breakpoint();
        }
        else if (ch == '\n' || ch == '\r')
        {
            printf("\n");
            break; // End of line
        }
        else if ((ch == 0x08 || ch == 0x7F) && index > 0) // Backspace or Delete
        {
            index--;
            buffer[index] = '\0'; // Remove last character
            printf("\b \b"); // Erase the last character
        }
        else if (ch >= 0x20 && ch < 0x7F && index < size - 1) // Printable characters
        {
            buffer[index++] = ch;
            putchar(ch);
        }
    }
    buffer[index] = '\0'; // Null-terminate the string
}

int main()
{
    char buffer[256];

    // Initialize the LED driver and set the LED callback
    // If the LED driver fails to initialize, we can still run the text starter
    // without LED support, so we pass NULL to picocalc_init.
    int led_init_result = led_init();

    stdio_init_all();
    picocalc_init();
    if (led_init_result == 0) {
        display_set_led_callback(set_onboard_led);
    }

    // Create the Lua interpreter and load the standard libraries.
    lua_State *L = luaL_newstate();
    if (L == NULL) {
        printf("\033cFATAL: could not allocate Lua state (out of memory).\n");
        while (true) { tight_loop_contents(); }
    }
    luaL_openlibs(L);

    printf("\033c\033[1m\n PicoCalc Lua Game Engine\033[0m\n\n");
    printf("Lua %s.%s.%s\n\n", LUA_VERSION_MAJOR, LUA_VERSION_MINOR, LUA_VERSION_RELEASE);
    printf("Type Lua at the prompt, e.g. \033[4mprint(\"hello\")\033[0m\n\n");

    // A very simple Lua REPL: read a line, execute it as a Lua chunk,
    // and report any compile/runtime error to the display.
    printf("\033[q> ");
    while (true)
    {
        readline(buffer, sizeof(buffer));
        if (strlen(buffer) == 0)
        {
            printf("> ");
            continue; // Skip empty input
        }

        printf("\033[1q"); // Turn on the LED so the user knows input is being processed

        // Load and run the line as a Lua chunk. luaL_dostring returns
        // non-zero on error, leaving the error message on the stack.
        if (luaL_dostring(L, buffer) != LUA_OK)
        {
            const char *msg = lua_tostring(L, -1);
            printf("\033[31m%s\033[0m\n", msg ? msg : "(unknown error)");
            lua_pop(L, 1); // remove the error message from the stack
        }

        printf("\033[q> "); // Turn off the LED and prompt for input again
    }
}
