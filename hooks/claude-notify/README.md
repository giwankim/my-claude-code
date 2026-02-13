# claude-notify

`claude-notify` is a macOS notification hook module for Claude Code. It provides:

- A Swift binary (`claude-notify`) that posts notifications and manages sender spoofing behavior.
- A shell hook entrypoint (`notify.sh`) for Claude hook execution.
- Test and quality gates for unit, integration, and shell e2e behavior.

## Directory layout

- `Makefile`: module-local build/test/check entrypoints.
- `Package.swift`: Swift package definition.
- `Sources/`: production Swift sources.
- `Tests/`: Swift tests and shell integration/e2e tests.
- `scripts/`: required check scripts used by `make` targets.
- `notify.sh`: canonical hook script entrypoint.
- `test-claude-notify.sh`: module-local shell test runner.
- `claude-notify.app/`: app bundle containing the built binary (`Contents/MacOS/claude-notify`).

## Prerequisites

- macOS (this module targets macOS notification behavior).
- Swift toolchain (`swift build`, `swift test`).
- `jq` available on `PATH` (used by `notify.sh` stdin JSON parsing).
- `tmux` optional (used for richer context and execute actions when running inside tmux).

## Build and test

From repository root:

```bash
make build
make test-unit
make test-integration
make test-e2e
make test
```

From module directory (`hooks/claude-notify`):

```bash
make build
make test-unit
make test-integration
make test-e2e
make test
```

## Install and usage

Install via root Makefile:

```bash
make install
```

Installed canonical hook path:

- `~/.claude/hooks/claude-notify/notify.sh`

This script accepts:

- First argument as message text, or
- JSON on stdin with `.message` field (Claude hook payload format).

## Environment variables (`notify.sh`)

- `NOTIFY_BIN`: override binary path.
- `NOTIFY_TIMEOUT`: notification timeout seconds (default `90`).
- `NOTIFY_SENDER_MODE`: `off|auto|required` (default `off`).
- `NOTIFY_SENDER_BUNDLE_ID`: spoof sender bundle ID override.
- `NOTIFY_SENDER_APP_PATH`: spoof sender app bundle path override.
- `NOTIFY_ACTIVATE_BUNDLE_ID`: app bundle activated on click.
- `NOTIFY_TMUX_BIN`: override tmux binary path.
- `NOTIFY_ISOLATE_HELPER_BUNDLE_ID`: helper isolation toggle (default `1`).
- `NOTIFY_ALLOW_NONISOLATED_RETRY`: fallback behavior toggle (default `0`).

## Troubleshooting

- Binary missing:
  - Run `make build`.
  - Confirm `hooks/claude-notify/claude-notify.app/Contents/MacOS/claude-notify` exists.
- tmux warning (`unable to read tmux context`):
  - Notification still posts, but execute action is skipped.
  - Ensure `$TMUX`, `$TMUX_PANE`, and tmux client context are available.
- Sender spoof errors:
  - Use `NOTIFY_SENDER_MODE=off` to disable spoofing.
  - Use `NOTIFY_SENDER_MODE=auto` for fallback behavior.
  - Use `NOTIFY_SENDER_MODE=required` to fail hard when spoofing cannot be performed.

## Maintenance notes

- Required-case gate:
  - `scripts/check-required-cases.sh` validates IDs listed in `Tests/required-cases.txt`.
- Docstring coverage gate:
  - `scripts/check-docstring-coverage.sh --min 80 Sources Tests`.
- These gates run from Makefile targets and are part of the expected CI quality checks.
