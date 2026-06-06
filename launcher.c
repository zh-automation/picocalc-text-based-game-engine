//
//  PicoCalc game launcher
//
//  Scans the SD card's /games directory for Lua scripts, presents an
//  arrow-key menu, and runs the selected game with dofile(). When a game
//  script finishes (or errors), control returns here. A "Lua console"
//  entry drops to an interactive REPL, which is handy during development.
//

#include <stdio.h>
#include <string.h>

#include "pico/stdlib.h"

#include "lua.h"
#include "lauxlib.h"

#include "drivers/keyboard.h"
#include "drivers/fat32.h"

#include "launcher.h"

#define GAMES_DIR "/games"
#define MAX_GAMES 64

static char game_names[MAX_GAMES][FAT32_MAX_FILENAME_LEN + 1];

//
//  Game discovery
//

// Case-insensitive test for a ".lua" filename suffix.
static bool ends_with_lua(const char *name)
{
    size_t len = strlen(name);
    if (len < 4)
    {
        return false;
    }
    const char *ext = name + (len - 4);
    return (ext[0] == '.') &&
           (ext[1] == 'l' || ext[1] == 'L') &&
           (ext[2] == 'u' || ext[2] == 'U') &&
           (ext[3] == 'a' || ext[3] == 'A');
}

// Scan GAMES_DIR for *.lua files, filling game_names. Returns the count.
static int scan_games(void)
{
    fat32_file_t dir;
    fat32_entry_t entry;
    int count = 0;

    if (fat32_open(&dir, GAMES_DIR) != FAT32_OK)
    {
        return 0; // directory missing or card not ready
    }

    while (count < MAX_GAMES)
    {
        if (fat32_dir_read(&dir, &entry) != FAT32_OK)
        {
            break;
        }
        if (entry.filename[0] == '\0')
        {
            break; // end of directory
        }
        if (entry.attr & (FAT32_ATTR_DIRECTORY | FAT32_ATTR_VOLUME_ID |
                          FAT32_ATTR_HIDDEN | FAT32_ATTR_SYSTEM))
        {
            continue;
        }
        if (!ends_with_lua(entry.filename))
        {
            continue;
        }

        strncpy(game_names[count], entry.filename, FAT32_MAX_FILENAME_LEN);
        game_names[count][FAT32_MAX_FILENAME_LEN] = '\0';
        count++;
    }

    fat32_close(&dir);
    return count;
}

//
//  Rendering
//

// Draw the menu. Selectable items are the games [0..count-1] followed by
// the Lua console entry at index == count.
static void draw_menu(int count, int selected)
{
    printf("\033[2J\033[H");
    printf("\033[1m  PicoCalc Lua Game Engine\033[0m\n");
    printf("  --------------------------\n\n");

    if (!fat32_is_mounted())
    {
        printf("  \033[33mNo SD card detected.\033[0m\n");
        printf("  Insert a FAT32 card with a %s folder.\n\n", GAMES_DIR);
    }
    else if (count == 0)
    {
        printf("  \033[33mNo games found in %s\033[0m\n", GAMES_DIR);
        printf("  Copy .lua games there, then press R.\n\n");
    }

    for (int i = 0; i < count; i++)
    {
        if (i == selected)
        {
            printf("  \033[7m %s \033[0m\n", game_names[i]);
        }
        else
        {
            printf("   %s\n", game_names[i]);
        }
    }

    // Lua console entry (always present, index == count)
    if (selected == count)
    {
        printf("  \033[7m [ Lua console ] \033[0m\n");
    }
    else
    {
        printf("   [ Lua console ]\n");
    }

    printf("\n  \033[2mUp/Down: select   Enter: run   R: rescan\033[0m\n");
}

//
//  Running games and the console
//

// Run a single game script. Errors are reported but do not crash the
// launcher; control always returns to the menu.
static void run_game(lua_State *L, const char *name)
{
    char path[FAT32_MAX_PATH_LEN];
    snprintf(path, sizeof(path), GAMES_DIR "/%s", name);

    printf("\033[2J\033[H");

    if (luaL_dofile(L, path) != LUA_OK)
    {
        const char *msg = lua_tostring(L, -1);
        printf("\n\033[31mError: %s\033[0m\n", msg ? msg : "(unknown error)");
        lua_pop(L, 1);
    }

    // Reset attributes in case the game left colours or styles set, then
    // wait so the final screen is readable before returning to the menu.
    printf("\033[0m\n\n  -- Press any key to return to the menu --");
    fflush(stdout);
    keyboard_get_key();
}

// Read a line from the keyboard with echo and backspace editing.
static void read_console_line(char *buf, size_t size)
{
    size_t idx = 0;
    while (true)
    {
        char c = keyboard_get_key();
        if (c == KEY_RETURN || c == '\n')
        {
            putchar('\n');
            break;
        }
        else if ((c == KEY_BACKSPACE || c == 0x7F) && idx > 0)
        {
            idx--;
            printf("\b \b");
        }
        else if ((unsigned char)c >= 0x20 && (unsigned char)c < 0x7F &&
                 idx < size - 1)
        {
            buf[idx++] = c;
            putchar(c);
        }
        fflush(stdout);
    }
    buf[idx] = '\0';
}

// A simple interactive Lua REPL. Type 'exit' to return to the menu.
static void run_console(lua_State *L)
{
    char line[256];

    printf("\033[2J\033[H");
    printf("Lua console — type \033[4mexit\033[0m to return to the menu.\n\n");

    while (true)
    {
        printf("> ");
        fflush(stdout);
        read_console_line(line, sizeof(line));

        if (strcmp(line, "exit") == 0)
        {
            break;
        }
        if (line[0] == '\0')
        {
            continue;
        }

        if (luaL_dostring(L, line) != LUA_OK)
        {
            const char *msg = lua_tostring(L, -1);
            printf("\033[31m%s\033[0m\n", msg ? msg : "(unknown error)");
            lua_pop(L, 1);
        }
    }
}

//
//  Main launcher loop
//

void run_launcher(lua_State *L)
{
    int selected = 0;
    int count = scan_games();
    int total = count + 1; // +1 for the Lua console entry

    while (true)
    {
        draw_menu(count, selected);

        int key = (unsigned char)keyboard_get_key();
        switch (key)
        {
        case KEY_UP:
            selected = (selected - 1 + total) % total;
            break;
        case KEY_DOWN:
            selected = (selected + 1) % total;
            break;
        case KEY_RETURN:
        case KEY_ENTER:
            if (selected < count)
            {
                run_game(L, game_names[selected]);
            }
            else
            {
                run_console(L);
            }
            // The card or its contents may have changed while away.
            count = scan_games();
            total = count + 1;
            if (selected >= total)
            {
                selected = total - 1;
            }
            break;
        case 'r':
        case 'R':
            count = scan_games();
            total = count + 1;
            if (selected >= total)
            {
                selected = total - 1;
            }
            break;
        default:
            break;
        }
    }
}
