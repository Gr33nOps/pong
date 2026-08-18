# Contributing

Thank you for helping improve PONG. Contributions should preserve the existing arcade experience and should focus on correctness, usability, performance, accessibility, documentation, or platform compatibility.

## Before opening a change

Please search existing issues and pull requests first. For a bug report, include the affected version or commit, operating system, device type, reproduction steps, expected behavior, actual behavior, and relevant logs or screenshots. For a proposed change, explain the user problem it solves and why the change fits the current scope of the project.

## Development checks

Before opening a pull request, run the existing Godot smoke test and check the working tree for whitespace errors:

```text
godot --headless --path . --script tests/smoke.gd
git diff --check
```

If you modify export settings or platform-specific behavior, also validate the relevant export preset when the required Godot export templates are installed.

## Pull requests

Keep each pull request focused and explain the important implementation decisions. Do not commit generated build artifacts, editor state, credentials, signing keys, or personal data. Update documentation and tests when behavior changes. Pull requests should pass the repository's automated checks before merging.

## Commit messages

Use a short, descriptive imperative message, such as `Fix controller pause input` or `Harden web export workflow`. Avoid unrelated changes in the same commit.
