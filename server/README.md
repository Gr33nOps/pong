# PONG Online Server

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

Clients send JSON messages containing `create_room`, `join_room`, `leave_room`, `input`, `serve`, `rematch`, or the `ping` keepalive. An `input` carries the client's locally predicted paddle position as `target_y`; the server moves its own paddle toward it under a speed cap, so clients never set positions, ball state, or scores directly. A `ping` may include a client timestamp `t`, which the `pong` reply echoes so the client can measure round-trip time. The server returns room events, connection events, and snapshots containing ball position and velocity, paddle positions and velocities, score, serve state, and match state.

Four-player rooms use the same connection. A client sends `create_room` or `join_room` with `"mode": "quad"`; codes only work for their own room type. The server answers with `quad_room` (the player's seat), keeps everyone updated with `quad_lobby`, starts on the host's `start` with CPU paddles in empty seats, and then streams `quad_snapshot` messages at 40 Hz. `server/quad_simulation.gd` is a verbatim copy of the client's `quad_simulation.gd`.

Clients draw the ball one round trip ahead of the latest snapshot, which is when their paddle input reaches the server, and replay their own recent paddle positions when predicting returns. Corrections from new snapshots fade out instead of snapping.
