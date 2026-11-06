# Contributing

Thank you for helping improve Paddle Polygon. Contributions should keep the game's paper-and-ink feel and focus on correctness, usability, performance, accessibility or documentation.

## Before opening a change

Please search existing issues and pull requests first. For a bug report, include the affected version or commit, browser and operating system, reproduction steps, expected behavior, actual behavior, and relevant logs or screenshots. For a proposed change, explain the problem it solves.

## Development checks

Before opening a pull request, run the tests and check for whitespace errors:

```text
godot --headless --path . --script tests/arena_smoke.gd
godot --headless --path server --script res://arena_room_smoke.gd
git diff --check
```

The online test needs a local server (see the README).

If you change the game rules in `scripts/arena_simulation.gd`, copy the file to `server/arena_simulation.gd` too; the tests fail if the two copies differ.

## Pull requests

Keep each pull request focused and explain the important decisions. Do not commit build output (`build/`), editor state (`.godot/`), credentials or personal data. Update documentation and tests when behavior changes. Pull requests should pass the automated checks before merging.

## Commit messages

Use a short, descriptive imperative message, such as `Fix controller pause input`. Avoid unrelated changes in the same commit.
