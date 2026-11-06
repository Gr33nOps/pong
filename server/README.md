# Paddle Polygon Online Server

This directory contains the authoritative WebSocket server for online matches. It stores rooms in memory, uses six-character room codes, accepts input-only client messages, simulates the ball and paddles on the server at a fixed 120 Hz step, and broadcasts compact JSON snapshots at 40 Hz with Nagle's algorithm disabled. There are no accounts, database tables, or paid runtime dependencies.

## Local run

From the `server/` directory, run:

```text
godot --headless --path . --scene server_main.tscn
```

The listener uses `PORT` when it is present and otherwise defaults to `9080`.

## Render deployment

Create a free Render Web Service from the repository and set its Dockerfile path to `server/Dockerfile`. Render supplies the `PORT` environment variable automatically. The client should use the resulting secure WebSocket URL, for example `wss://your-service.onrender.com`, through `PONG_SERVER_URL` or the in-game online-server setting.

The free service may sleep when idle. The client therefore keeps the explicit wake-up message in the lobby and shows a retry path when the first connection takes longer than the client timeout.

## Protocol

Every room is a polygon match for 2 to 10 players. The rules live in `arena_simulation.gd`, a verbatim copy of the client's file (a client test checks they match).

Clients send:
- `create_room` with `size` (2–10), and `join_room` with `code`
- `set_size` and `start` (host only, before the match), `rematch` after it ends, and `leave_room`
- `input` with `target_y`: the client's predicted paddle position along its wall. The server moves its paddle toward it under a speed cap, so clients never set positions, the ball, or lives directly.
- `hit` with `tick`: a swing in the line finale, stamped with the server tick the player saw. A swing that arrives late is judged against the ball's recorded position at that tick; one that arrives early is held until that tick.
- `ping` with an optional timestamp `t`, echoed in `pong` so the client can measure round-trip time.

The server answers with `arena_room` (your seat), keeps everyone updated with `arena_lobby` (size, filled seats, host), sends `arena_started` when the host starts, with AI in every empty seat, and then streams `arena_snapshot` messages at 40 Hz. A player who drops out mid-match is replaced by AI.

Clients draw the ball one round trip ahead of the latest snapshot, which is when their own input reaches the server, and replay their own recent paddle positions when predicting returns. Corrections from new snapshots glide out instead of snapping.
