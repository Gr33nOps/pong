<p align="center">
</p>

# PONG

A classic Pong remake built with **Godot 4.7** — aimed serves, rally heat, and a glowing motion trail.

## Play

- **Web (browser):** <https://greenops.itch.io/pong/> — upload builds manually when ready.
- **Web mirror:** <https://gr33nops.github.io/pong/> — a GitHub Pages mirror built from `main`.
- **Windows:** grab `pong-windows.zip` from the [Releases](https://github.com/Gr33nOps/pong/releases) page, unzip, and run `pong.exe`.
- **Android:** export an APK locally and install it for testing (enable "Install unknown apps" for your browser/file manager first).

## Features

- Player vs AI and Player vs Player (pick on the start screen)
- Keyboard (W/S for P1, arrows for P2) plus auto-detecting gamepads
- Loser serves: ball sits on the paddle; aim with movement or a touch drag, then Space / A / tap to launch
- Center hits are faster and flatter; edge hits are sharper and a bit slower
- Paddle english, rally speed ramp, and paddles that shrink after a long volley
- Rally-based gameplay balancing, speed-scaled SFX pitch and screen shake
- Pause menu (ESC / START) with volume and AI difficulty controls in a monochrome ink UI
- Touch play supports speed-limited paddle movement, aimed serves, two-player side ownership, and draggable volume controls
- First to 5 wins

## Controls

| Action    | P1        | P2           | Gamepad           |
|-----------|-----------|--------------|-------------------|
| Move      | W / S     | ↑ / ↓        | Left stick, D-pad |
| Confirm   | Space / A | (pad A)      | A / START         |
| Mode pick | 1 / 2     | (pad d-pad)  | D-pad + A         |
| Pause     | ESC       | START / BACK | START / BACK      |

Aim the serve by moving the paddle before you launch. In vs AI, the computer auto-serves after a short delay. Touch players must use the serving side of the court.

## Running from source

1. Open `pong/` (the project root, where `project.godot` lives) in the Godot 4.7 editor.
2. Press **F5**.

## Building

All presets are in `export_presets.cfg`. From the project root:

```bash
godot --headless --path . --script tests/smoke.gd
godot --headless --path . --export-release "Windows Desktop" ../pong-build/pong.exe
godot --headless --path . --export-release "Web" ../pong-build/web/index.html
godot --headless --path . --export-release "Android" ../pong-build/android/Pong.apk
```

Pushing a `v*` tag (e.g. `v1.1.4`) triggers [`release.yml`](.github/workflows/release.yml), which validates and packages the Windows and Web builds as GitHub Release artifacts. Itch.io uploads are intentionally manual for now; no Butler token or Android signing secret is required.

Windows builds are x64 and currently unsigned, so Windows SmartScreen may show an “unknown publisher” prompt. An Authenticode certificate can be added later without changing the game package.

### Android testing setup

For local Android testing, install JDK 17, Android SDK Platform 36, Build Tools, Platform Tools, and the Godot 4.7.1 Android build template. Set the SDK/JDK paths in Godot’s Editor Settings; machine-specific paths are intentionally not stored in this repository. A debug-signed APK is sufficient for sideloading and manual Itch testing. A permanent release key is only needed later for Google Play or upgrade-safe public releases.

## Project layout

- `constants.gd` — shared gameplay numbers
- `game_state.gd` — scores, serve/pause/game-over flow, mode selection
- `main.gd` — scoring, aimed serve placement, rally UI
- `ball.gd`, `paddle.gd`, `ai.gd`, `trail.gd` — gameplay
- `players.gd` — gamepad auto-assignment + input latches
- `serve.gd`, `pause.gd`, `game_over.gd` — UI overlays
- `sfx.gd`, `screen_shake.gd`, `particle_effects.gd` — juice
