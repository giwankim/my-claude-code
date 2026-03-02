# Delayed Notification After Stop Hook — Progress Report

**Date:** 2026-03-02
**Branch:** giwankim/delayed-notif-after-stop
**Status:** Ready for Review

## Task Overview
- Investigate and fix: after pressing Stop, a delayed notification sometimes appears seconds later
- Root cause: race condition between the Notification hook (sender spoofing ON, slow relaunch) and Stop hook (spoofing OFF, fast)
- The spoofed helper app from the Notification hook launches after the Stop hook's notification, kills it, and replaces it

## Current Context
- `notify.sh` is the shell hook entrypoint; launches `claude-notify` Swift binary in background (`&`)
- The binary supports sender spoofing via a helper app relaunch (`open -n -W`)
- PID file at `$TMPDIR/claude-notify/claude-notify.pid` tracks single-instance lifecycle
- User config: Notification hook uses `NOTIFY_SENDER_MODE=auto` (default), Stop hook uses `NOTIFY_SENDER_MODE=off`

## Completed Tasks
- [x] ~~Cycle 1: PID file generation token format~~ (U040-U044)
  - Files: `Sources/NotifyCore/NotifyCore.swift`
  - Added `PidFileContent` struct, `formatPidFileContent()`, `parsePidFileContent()`
  - Tested: 5 Swift unit tests passing

- [x] ~~Cycle 2: Argument parsing for `-generation`~~ (U045-U048)
  - Files: `Sources/NotifyCore/NotifyCore.swift`
  - Added `generation` field to `NotifyArgs`, parser support, forwarding in `buildRelaunchArguments()`
  - Tested: 4 Swift unit tests passing

- [x] ~~Cycle 3: Staleness check~~ (U049-U052)
  - Files: `Sources/NotifyCore/NotifyCore.swift`
  - Added `isSuperseded(ownGeneration:fileGeneration:)` function
  - Tested: 4 Swift unit tests passing

- [x] ~~Cycle 4: PID ownership only in posting process~~ (I135-I136)
  - Files: `Sources/ClaudeNotify/main.swift`
  - Ensured only the process that will post the notification runs `killPrevious()`/`writePid()`/`installSignalHandlers()`
  - `writePid()` now writes generation token to second line of PID file
  - Generation read from `-generation` arg or `CLAUDE_NOTIFY_GENERATION` env var
  - Tested: 2 shell integration tests passing

- [x] ~~Cycle 5: Generation check before posting~~ (I137)
  - Files: `Sources/ClaudeNotify/main.swift`
  - Added supersession check: if PID file has a different generation, exit without posting
  - Added `readPidFileContentFromFile()` and `readPidFileRaw()` helpers
  - Tested: 1 shell integration test passing

- [x] ~~Cycle 6: Shell notify.sh generation export~~ (U053)
  - Files: `hooks/claude-notify/notify.sh`
  - Exports `CLAUDE_NOTIFY_GENERATION="$$_$(date +%s)"` before all binary launch paths
  - Tested: 1 shell unit test passing

## Testing Summary
- **New test coverage added**: U040-U053 (unit), I135-I140 (integration)
- **Full test suite**: `make test-fast` → 175 passed, 0 failed; `make test-e2e` → 23 passed, 0 failed
- **Total**: 198 tests, 0 failures
- **Manual testing**: not yet performed (requires real Claude session with Notification + Stop hooks)

## Key Decisions Made
- **Generation token format**: `$$_$(date +%s)` (shell PID + epoch seconds) — unique per `notify.sh` invocation
- **PID file format**: backward-compatible two-line format (`PID\nGENERATION\n`), legacy single-line still parses
- **Supersession check placement**: before `killPrevious()` — avoids destroying PID file state before comparing
- **Generation propagation**: env var `CLAUDE_NOTIFY_GENERATION` for shell→binary, `-generation` CLI arg for binary→helper relaunch
- **Fallback behavior**: `isSuperseded()` returns false when either generation is nil (safe for legacy/no-generation callers)

## Files Changed
- `hooks/claude-notify/Sources/NotifyCore/NotifyCore.swift` — `PidFileContent`, `formatPidFileContent`, `parsePidFileContent`, `isSuperseded`, `generation` on `NotifyArgs`, parser, `buildRelaunchArguments` generation param, `buildFallbackArguments` preserves generation
- `hooks/claude-notify/Sources/ClaudeNotify/main.swift` — generation env/arg reading, supersession check before posting, spoof relaunch propagation, and PID mgmt in the posting process path (`killPrevious`/`writePid(generation:)`), plus `readPidFileRaw` and `readPidFileContentFromFile`
- `hooks/claude-notify/notify.sh` — exports `CLAUDE_NOTIFY_GENERATION` before binary launch
- `hooks/claude-notify/Tests/NotifyCoreTests/UnitArgParserTests.swift` — U045-U046
- `hooks/claude-notify/Tests/NotifyCoreTests/UnitUtilityTests.swift` — U040-U044, U047-U052
- `hooks/claude-notify/Tests/shell/unit/test-notify-activate.sh` — U053
- `hooks/claude-notify/Tests/shell/integration/test-deterministic.sh` — I135-I140
- `hooks/claude-notify/Tests/required-cases.txt` — registered all new case IDs

## Next Steps
1. Manual test: run a Claude session, let it respond, press Stop immediately, verify no delayed notification
2. Check debug logs at `/tmp/claude-notify-notify.log` for generation mismatch exits
3. ~~Consider adding a warning log line in the binary when supersession is detected~~ — done (main.swift:682)
4. Address review feedback on PR #12
