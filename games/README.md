# Games

Lua game scripts for the PicoCalc Lua Game Engine.

## Installing on the SD card

Copy the `.lua` files in this folder to a `/games` directory in the root of
a FAT32-formatted SD card:

```
SD card root/
└── games/
    ├── hello.lua
    └── guess.lua
```

Insert the card, power on the PicoCalc, and the launcher lists every
`*.lua` file in `/games`. Use **Up/Down** to select, **Enter** to run, and
**R** to rescan after adding files. A game returns to the menu when its
script finishes.

## The `pc` game API

Scripts get a global `pc` table:

| Category | Functions |
|---|---|
| Screen   | `pc.cls()`, `pc.print(...)`, `pc.write(...)`, `pc.at(x,y)`, `pc.color(fg[,bg])`, `pc.fg(r,g,b)`, `pc.bg(r,g,b)`, `pc.reset()` |
| Keyboard | `pc.getkey()` (blocks, returns a key code), `pc.keyhit()`, `pc.input([prompt])` (reads a line) |
| Audio    | `pc.beep()`, `pc.tone(freq[,ms])`, `pc.sound(freq)`, `pc.stop()` |
| Timing   | `pc.sleep(ms)`, `pc.time()` (ms since boot) |
| Random   | `pc.random()` / `pc.random(m)` / `pc.random(m,n)` (hardware RNG) |

Constants: `pc.KEY_UP/DOWN/LEFT/RIGHT/ENTER/ESC/SPACE/BACKSPACE/TAB`,
`pc.KEY_F1`–`pc.KEY_F10`, and colours `pc.BLACK`, `pc.RED`, `pc.GREEN`,
`pc.YELLOW`, `pc.BLUE`, `pc.MAGENTA`, `pc.CYAN`, `pc.WHITE`, plus the
`pc.GREY` / `pc.BRIGHT_*` variants.

The full Lua 5.4 standard library is available except `io`, `os`, and
`package` (omitted because they need OS facilities the PicoCalc lacks).
