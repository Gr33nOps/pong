# PONG Online Server

This directory contains the authoritative WebSocket server for online matches. It stores rooms in memory, uses six-character room codes, accepts input-only client messages, simulates the ball and paddles on the server, and broadcasts compact JSON snapshots at 30 Hz. There are no accounts, database tables, or paid runtime dependencies.

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

Clients send JSON messages containing `create_room`, `join_room`, `leave_room`, `input`, `serve`, or `rematch`. Clients never send authoritative positions or scores. The server returns room events, connection events, and snapshots containing ball position and velocity, paddle positions, score, serve state, and match state.
