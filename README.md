# PONG

A classic Pong remake built with **Godot 4.7** — two modes, gamepad + keyboard support, and a glowing motion trail.

## Play

- **Web (browser):** <https://gr33nops.github.io/pong/> — built and deployed automatically by GitHub Actions on every push to `main`.
- **Windows:** grab `pong-windows.zip` from the [Releases](https://github.com/Gr33nOps/pong/releases) page, unzip, and run `pong.exe`.

## Features

- Player vs AI and Player vs Player modes (pick on the start screen)
- Keyboard controls (W/S for P1, Arrows for P2) plus auto-detecting gamepads (first pad = P1, second = P2)
- Serve, pause (ESC / START), first to 5 wins
- Ball stays white; the fading trail shifts blue/red with whoever touched it last
- AI paddle with a forgiving reaction delay

## Controls

| Action    | P1        | P2           | Gamepad          |
|-----------|-----------|--------------|------------------|
| Move      | W / S     | ↑ / ↓        | Left stick, D-pad |
| Confirm   | Space / A | (pad A)      | A / START        |
| Mode pick | 1 / 2     | (pad d-pad)  | D-pad + A        |
| Pause     | ESC       | START / BACK | START / BACK     |

## Running from source

1. Open `pong/` (the project root, where `project.godot` lives) in the Godot 4.7 editor.
2. Press **F5**.

## Building

Both presets are in `export_presets.cfg`. From the project root:

```bash
godot --headless --path . --export-release "Windows Desktop"
godot --headless --path . --export-release "Web"
```

## Project layout

- `game_state.gd` — scores, serve/pause/game-over flow, mode selection
- `main.gd` — scoring logic and rally flow
- `ball.gd`, `paddle.gd`, `ai.gd`, `trail.gd` — gameplay
- `players.gd` — gamepad auto-assignment + input latches
- `serve.gd`, `pause.gd`, `game_over.gd` — UI overlays
- `sfx.gd` — procedural sound effects
