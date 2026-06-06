# PicoCalc Lua Game Engine

A text-based game engine for the [PicoCalc](https://www.clockworkpi.com/picocalc).
Games are plain [Lua](https://www.lua.org) scripts on a FAT32 SD card — drop
them in `/games`, boot the device, and pick one from the on-screen launcher.
The firmware is flashed once; new games are just files you copy to the card.

Built on the [picocalc-text-starter](https://github.com/) drivers by Blair
Leduc, which provide the display (ANSI terminal emulation), keyboard, audio,
and SD-card/FAT32 access.

> [!NOTE]
> Targets the **Pico 2 / RP2350** PicoCalc. The full Lua 5.4 interpreter is
> embedded in the firmware; on this board it uses ~260 KB of flash and leaves
> hundreds of KB of RAM for games.

## How it works

- A Lua 5.4 interpreter is embedded in the firmware (see [`lua/`](lua/)).
- On boot, the launcher ([`launcher.c`](launcher.c)) scans `/games/*.lua` on
  the SD card and shows a menu.
- Selecting a game runs its script with `dofile()`. When the script finishes,
  control returns to the menu. Script errors are reported, not fatal.
- Games talk to the hardware through the `pc` table ([`game_api.c`](game_api.c)).

## Hardware

- A PicoCalc fitted with a **Raspberry Pi Pico 2** (RP2350).
- A FAT32-formatted SD card.

## Building

This is a standard [Pico SDK](https://www.raspberrypi.com/documentation/microcontrollers/c_sdk.html)
project. The easiest path is [VS Code](https://code.visualstudio.com) with the
[Raspberry Pi Pico extension](https://marketplace.visualstudio.com/items?itemName=raspberry-pi.raspberry-pi-pico):
open the folder, let it configure, and press **Compile**. The board is set to
`pico2` in [`CMakeLists.txt`](CMakeLists.txt).

From the command line (using the SDK tools the extension installs):

```sh
cmake -S . -B build -G Ninja
cmake --build build
```

The build produces `build/picocalc-text-starter.uf2`.

## Flashing

Hold **BOOTSEL**, connect the Pico over USB, and copy the `.uf2` to the
`RPI-RP2` drive that appears. The device reboots into the launcher.

## Playing games

Copy `.lua` files into a `/games` folder at the root of the SD card:

```text
SD card root/
└── games/
    ├── hello.lua
    └── guess.lua
```

Example games are in [`games/`](games/). Insert the card and boot:

- **Up/Down** — move the selection
- **Enter** — run the highlighted game
- **R** — rescan the card (after adding files)
- **[ Lua console ]** — an interactive Lua REPL, handy for development

## Writing a game

A game is a Lua script that uses the global `pc` table. When the script
returns, the launcher takes over again — so a game's main loop should exit on
a quit key.

```lua
-- mygame.lua
pc.cls()
pc.color(pc.BRIGHT_GREEN)
pc.print("Press Q to quit.")
pc.reset()

while true do
  local k = pc.getkey()
  if k == string.byte("q") then break end
  pc.print("key code: " .. k)
end
```

### The `pc` API

| Category | Functions |
|---|---|
| Screen   | `pc.cls()`, `pc.print(...)`, `pc.write(...)`, `pc.at(x,y)`, `pc.color(fg[,bg])`, `pc.fg(r,g,b)`, `pc.bg(r,g,b)`, `pc.reset()` |
| Keyboard | `pc.getkey()` (blocks, returns a key code), `pc.keyhit()`, `pc.input([prompt])` (reads a line) |
| Audio    | `pc.beep()`, `pc.tone(freq[,ms])`, `pc.sound(freq)`, `pc.stop()` |
| Timing   | `pc.sleep(ms)`, `pc.time()` (ms since boot) |
| Random   | `pc.random()` / `pc.random(m)` / `pc.random(m,n)` (hardware RNG, no seeding) |

Constants on `pc`: keys `KEY_UP/DOWN/LEFT/RIGHT/ENTER/ESC/SPACE/BACKSPACE/TAB`
and `KEY_F1`–`KEY_F10`; colours `BLACK`, `RED`, `GREEN`, `YELLOW`, `BLUE`,
`MAGENTA`, `CYAN`, `WHITE`, plus `GREY` and the `BRIGHT_*` variants.

The full Lua 5.4 standard library is available **except** `io`, `os`, and
`package` — these are omitted because they need operating-system facilities
(dynamic loading, `system()`, real file streams) the PicoCalc doesn't have.
Use the `pc` API for I/O instead. See [`games/README.md`](games/README.md) for
more detail.

## Project structure

```text
main.c          Boot: init hardware + Lua, hand off to the launcher
launcher.c/.h   SD game discovery, menu, game runner, dev console
game_api.c/.h   The "pc" table bridging Lua to the drivers
lua/            Vendored Lua 5.4 interpreter (built as a static library)
drivers/        PicoCalc hardware drivers (display, keyboard, audio, SD, ...)
games/          Example games and SD-card install instructions
docs/           Driver documentation
```

## Credits & license

MIT licensed (see [LICENSE](LICENSE)). The hardware drivers and original
text-starter are © 2025 Blair Leduc. [Lua](https://www.lua.org) is © 1994–2025
Lua.org, PUC-Rio, MIT licensed.
