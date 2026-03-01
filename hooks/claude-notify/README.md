# claude-notify

`claude-notify` is a macOS notification hook module for Claude Code. It provides:

- A Swift binary (`claude-notify`) that posts notifications and manages sender spoofing behavior.
- A shell hook entrypoint (`notify.sh`) for Claude hook execution.
- Test and quality gates for unit, integration, and e2e behavior (Swift + shell).

## Directory layout

- `Makefile`: module-local build/test/check entrypoints.
- `Package.swift`: Swift package definition.
- `Sources/`: production Swift sources.
- `Tests/`: Swift unit/integration tests, required case manifest, and shell unit/integration/e2e suites.
- `scripts/`: required check scripts used by `make` targets.
- `notify.sh`: canonical hook script entrypoint.
- `test-claude-notify.sh`: module-local shell test runner.
- `claude-notify.app/`: app bundle containing the built binary (`Contents/MacOS/claude-notify`).

## Prerequisites

- macOS (this module targets macOS notification behavior).
- Swift toolchain (`swift build`, `swift test`).
- `perl` with `Time::HiRes` (used by `notify.sh` timeout wrappers; bundled by default on standard macOS Perl builds).
- `jq` available on `PATH` (used by `notify.sh` stdin JSON parsing).
- `tmux` optional (used for richer context and execute actions when running inside tmux).

## Build and test

`make test-unit` runs both Swift unit tests and shell unit tests (`Tests/shell/unit/run.sh`) from both repository-root and module-directory invocations.

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
- JSON on stdin with non-empty `.message`, then non-empty `.last_assistant_message`, else default `"Waiting for input"`.

## Environment variables (`notify.sh`)

- `NOTIFY_BIN`: override binary path.
- `NOTIFY_TIMEOUT`: notification timeout seconds (default `90`).
- `NOTIFY_SENDER_MODE`: `off|auto|required` (default `auto`).
- `NOTIFY_SENDER_BUNDLE_ID`: spoof sender bundle ID override (default `com.gwk.claude-notify`).
- `NOTIFY_SENDER_APP_PATH`: spoof sender app bundle path override (default `claude-notify.app` next to `notify.sh`).
- `NOTIFY_ACTIVATE_BUNDLE_ID`: optional app bundle activated on click (default auto-infers frontmost app at send time).
- `NOTIFY_ACTIVATE_OVERRIDE`: override non-tmux activate behavior; set to an app bundle ID to force activation or to an empty value to disable `-activate`.
- `NOTIFY_ACTIVATE_OSASCRIPT_BIN`: override `osascript` path used for frontmost-app activate inference (default `/usr/bin/osascript`).
- `NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS`: timeout for activate-bundle inference probe calls (default `150`).
- `NOTIFY_TMUX_BIN`: override tmux binary path.
- `NOTIFY_TMUX_ACTIVATE_FALLBACK`: tmux activation fallback policy when client-host resolution fails: `frontmost|none` (default `none`).
- `NOTIFY_TMUX_CMD_TIMEOUT_MS`: timeout for tmux metadata probe calls (default `200`).
- `NOTIFY_TMUX_REDIRECT_SCRIPT`: override tmux click redirect helper path (default `tmux-redirect.sh` next to `notify.sh`).
- `NOTIFY_STDIN_TIMEOUT_MS`: timeout for stdin hook payload reads when no `$1` message is provided (default `150`).
- `NOTIFY_DEBUG_LOG`: enable debug logging to a file path.
- `NOTIFY_TMUX_REDIRECT_LOG`: override tmux-redirect helper debug log path (defaults to `NOTIFY_DEBUG_LOG` when set).
- `NOTIFY_ISOLATE_HELPER_BUNDLE_ID`: helper isolation toggle (default `1`).
- `NOTIFY_ALLOW_NONISOLATED_RETRY`: fallback behavior toggle (default `0`).
- `NOTIFY_OSASCRIPT_BIN`: override `osascript` path for delivery fallback when `UNUserNotificationCenter` is unavailable.

## Stop hook recommendations (IDE terminals)

For JetBrains terminals (IntelliJ/IDEA/WebStorm), use a fast-fail Stop hook config:

- Pass an explicit stop message arg so Stop does not depend on stdin JSON timing.
- Set per-hook `timeout` in Claude hook config.
- Use `NOTIFY_SENDER_MODE=off` for lowest-friction Stop notifications.

Example:

```json
{
  "hooks": {
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "NOTIFY_SENDER_MODE=off NOTIFY_TIMEOUT=15 $HOME/.claude/hooks/claude-notify/notify.sh \"Claude finished\"",
            "timeout": 3
          }
        ]
      }
    ]
  }
}
```

## Troubleshooting

- Binary missing:
  - Run `make build`.
  - Confirm `hooks/claude-notify/claude-notify.app/Contents/MacOS/claude-notify` exists.
- tmux warning (`unable to read tmux context`):
  - Notification still posts, but execute action is skipped.
  - Ensure `$TMUX`, `$TMUX_PANE`, and tmux client context are available.
- Click does not foreground terminal app:
  - `notify.sh` infers the frontmost app bundle at send time and uses it for click activation.
  - In tmux mode, activation is applied by `tmux-redirect.sh` after pane switching.
  - Outside tmux, activation is forwarded as native `-activate`.
  - Override explicitly with `NOTIFY_ACTIVATE_BUNDLE_ID` if needed.
- Sender spoof errors:
  - Use `NOTIFY_SENDER_MODE=off` to disable spoofing.
  - Use `NOTIFY_SENDER_MODE=auto` for default self-branded icon behavior with fallback.
  - Use `NOTIFY_SENDER_MODE=required` to fail hard when spoofing cannot be performed.
- Static Claude icon setup:
  - The build copies `/Applications/Claude.app/Contents/Resources/electron.icns` into `claude-notify.app` as `claude-code.icns` when available.
  - Notifications can use this icon even with spoofing disabled (`NOTIFY_SENDER_MODE=off`).
- Notification authorization denied:
  - The binary now attempts an AppleScript fallback (`display notification`) when native notification authorization or posting fails.
  - You can override the fallback binary path with `NOTIFY_OSASCRIPT_BIN` (or `CLAUDE_NOTIFY_OSASCRIPT_BIN`).

## Maintenance notes

- Required-case gate:
  - `scripts/check-required-cases.sh` validates IDs listed in `Tests/required-cases.txt`.
- Docstring coverage gate:
  - `scripts/check-docstring-coverage.sh --min 80 Sources Tests`.
- These gates run from Makefile targets and are part of the expected CI quality checks.
- Shared shell test helpers:
  - `Tests/shell/lib/testlib.sh` contains shared assertions and wait helpers.
  - `Tests/shell/lib/notify-test-helpers.sh` contains shared fake writers, temp-dir helpers, and execute payload extraction.
