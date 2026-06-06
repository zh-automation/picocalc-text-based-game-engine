# play.ps1 -- rebuild the game from src/ and play it in this terminal.
#
# Usage:
#   .\play.ps1                       # build, then play games/escapethetower.lua
#   .\play.ps1 games\ett_proto.lua   # build, then play a specific game
#   .\play.ps1 -NoBuild              # skip the build, just play

param(
   [string]$Game = 'games/escapethetower.lua',
   [switch]$NoBuild
)

$ErrorActionPreference = 'Stop'

# find a Lua interpreter: PATH first, then the usual winget install location
$lua = (Get-Command lua -ErrorAction SilentlyContinue).Source
if (-not $lua) {
   $fallback = Join-Path $env:LOCALAPPDATA 'Programs\Lua\bin\lua.exe'
   if (Test-Path $fallback) {
      $lua = $fallback
   } else {
      Write-Error "Lua not found. Install it (winget install DEVCOM.Lua) or add lua.exe to PATH."
      exit 1
   }
}

# rebuild the single-file game unless told not to
if (-not $NoBuild) {
   & (Join-Path $PSScriptRoot 'build.ps1')
}

# launch the game (stdin stays interactive, so you can type commands)
& $lua (Join-Path $PSScriptRoot 'tools/pc_stub.lua') $Game
