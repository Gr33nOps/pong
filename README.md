<div align="center">

<img src="logo.png" alt="Ink paddles and ball on a paper court" width="180">

# Paddle Polygon

**Pong for 2 to 7 players: one paddle per side, a court that shrinks as players are knocked out, and a one-dimensional finale.**

[![Play in browser](https://img.shields.io/badge/PLAY_IN_BROWSER-111111?style=for-the-badge)](https://gr33nops.github.io/pong/)
[![Latest release](https://img.shields.io/github/v/release/Gr33nOps/pong?style=for-the-badge&color=111111)](https://github.com/Gr33nOps/pong/releases/latest)
[![Godot 4.7](https://img.shields.io/badge/GODOT-4.7-111111?style=for-the-badge)](https://godotengine.org/)

[Play now](https://gr33nops.github.io/pong/) · [Download](https://github.com/Gr33nOps/pong/releases/latest) · [Report a problem](https://github.com/Gr33nOps/pong/issues)

</div>

## The game

Every player defends one side of a regular polygon: three players play on a triangle, seven on a heptagon. Everyone starts with three lives, and letting the ball past your side costs one. When a player is knocked out, their side folds away and the court shrinks to the next shape down.

When only two players are left, the court collapses into a single line for a **1D Pong** finale. The ball runs back and forth along it, and you press Space while it is inside your hatched hit zone. The later you hit, the faster it flies back; swing too early and you are locked out for a moment. The zones shrink after every point. The last player standing wins.

Your own side is always drawn at the bottom of the screen.

## Play your way

| Mode | Players | How it works |
|---|---:|---|
| Play vs AI | 2–7 | You against 1–6 AI paddles, in your browser with no server involved. Easy, Normal or Hard AI. |
| Play online | 2–7 | Create a room, pick how many players (the shape), and share the code. The host starts whenever ready; empty sides play as AI, and anyone who drops out is replaced by AI. |

The hosted online server may need a short wake-up after being idle.

## Controls

| Action | Keyboard | Controller |
|---|---|---|
| Move your paddle | ← / → or A / D | Left stick or D-pad |
| Swing (line finale) | Space, ↑ or W | A |
| Change a value in menus | ← / → | D-pad left / right |
| Select | Space or Enter | A |
| Pause / back | Esc | Start / Back |
| Mute | M | — |

## How online stays smooth

The server runs every match. Each browser draws the ball one round trip ahead of the latest update, which is when its own paddle input reaches the server. It replays your own recent paddle movement when predicting returns, and corrections glide rather than jump. In the line finale, a swing is judged against where the ball was when you pressed, so a little network delay doesn't cost you the hit.

## Download

The [latest release](https://github.com/Gr33nOps/pong/releases/latest) includes:

- Windows x64 archive
- Browser-ready Web archive for hosts such as itch.io
- Android arm64 sideload APK
- SHA-256 checksums for every download

Windows builds are currently unsigned, so SmartScreen may show an unknown-publisher warning. The Android download is debug-signed for direct testing and sideloading.

## Run from source

Requires Godot 4.7.1.

1. Clone the repository.
2. Open the directory containing `project.godot` in Godot.
3. Press **F5**.

Run the deterministic client checks:

```bash
godot --headless --path . --script tests/arena_smoke.gd
godot --headless --path server --script res://arena_room_smoke.gd
```

The online check needs a local server running on port 9081 (`PORT=9081 godot --headless --path server --scene server_main.tscn`):

```bash
godot --headless --path . --script tests/arena_online_smoke.gd
```

## Build

Export presets are committed for Windows, Web, and Android:

```bash
godot --headless --path . --export-release "Windows Desktop" ../pong-build/pong.exe
godot --headless --path . --export-release "Web" ../pong-build/web/index.html
godot --headless --path . --export-release "Android" ../pong-build/android/Pong.apk
```

Every push to `main` validates the simulation, the scene, room flow, and a real online match (including a swing in the line finale) before deploying GitHub Pages. A `v*` tag builds and publishes the downloadable release artifacts.

## Project map

- `arena_simulation.gd` — the rules: polygon court, paddles, corner bumpers, lives, shrinking, the line finale and the AI. `server/arena_simulation.gd` must stay identical to it (a test checks this)
- `arena.gd`, `arena_court.gd` — menus, drawing, solo play and online prediction
- `network_manager.gd` — WebSocket client, rooms, input, swings, heartbeats and snapshots
- `server/` — authoritative headless server (`arena_room.gd`, `room_manager.gd`)
- `tests/` — simulation, scene and online checks

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md).
