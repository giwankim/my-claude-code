# Code Review: hooks/claude-notify — 2026-03-07

Review of the full `hooks/claude-notify` codebase for reuse, quality, and efficiency.

## Recommended Fixes

### 1. notify.sh: Extract `launch_notify` helper (HIGH — copy-paste x4)

The notification launch block (build args with `set --`, conditionally add `-sender-app-path`, launch with env vars) is repeated 4 times:
- Lines 454–484: tmux with full context (subtitle + execute)
- Lines 489–501: tmux parse failure fallback
- Lines 507–519: tmux info empty fallback
- Lines 529–544: non-tmux (activate instead of execute)

All share identical base args (`-title`, `-message`, `-sound`, `-group`, `-timeout`, `-sender-mode`, `-sender-bundle-id`), identical conditional `-sender-app-path`, and identical env-var launch invocation. Extract a helper that accepts optional subtitle, execute, and activate parameters.

### 2. notify.sh: Extract `run_tmux_cmd` helper (HIGH — copy-paste x4)

Every tmux command follows the same pattern:
```sh
if [ "$TMUX_CMD_TIMEOUT_MS" -le 0 ]; then
  RESULT="$(command ...)"
  rc=$?
else
  RESULT="$(run_with_timeout_ms "$TMUX_CMD_TIMEOUT_MS" command ...)"
  rc=$?
fi
if [ "$rc" -eq 124 ]; then
  log_debug "... timed out after ${TMUX_CMD_TIMEOUT_MS}ms"
  RESULT=""
elif [ "$rc" -ne 0 ]; then
  log_debug "... failed rc=$rc"
  RESULT=""
fi
```

This appears at lines 344–357, 362–376, 370–376, and 402–415. Extract a helper that encapsulates the conditional timeout wrapping and rc-based log_debug.

### 3. main.swift: Delegate readPidFromFile to readPidFileContentFromFile (LOW)

`readPidFromFile()` (line 171) and `readPidFileContentFromFile()` (line 177) both independently call `readPidFileRaw()` then `parsePidFileContent()`. The former should delegate to the latter:
```swift
func readPidFromFile() -> pid_t? {
  readPidFileContentFromFile()?.pid
}
```

### 4. NotifyCore.swift: Fix TOCTOU in prepareSpoofHelper (MEDIUM)

Lines 721–724 check `fileExists` before `removeItem` for the helper executable. Lines 742–744 do the same for the icon copy. Remove the existence checks and attempt removal directly:
```swift
try? fm.removeItem(at: helperExecutable)
try fm.copyItem(atPath: sourceExecutablePath, toPath: helperExecutable.path)
```

### 5. NotifyCore.swift: Optimize icon fallback scan (LOW)

Line 527 sorts the entire Resources directory listing then filters for `.icns`. Filter first, then sort:
```swift
return files.filter { $0.lowercased().hasSuffix(".icns") }.sorted().first
```

## Reviewed and Skipped

These were flagged during review but determined to be false positives or not worth the added complexity:

- **flagsWithValues/internalMarkerFlags duplication with parse() switch**: Valid maintenance concern, but a flag registry abstraction would add complexity disproportionate to the risk.
- **warn() vs warning() naming**: Intentionally distinct prefixes ("Error:" vs "Warning:"). Slightly confusing names, but renaming `warn` to `error` would shadow Swift's built-in.
- **Inconsistent env var naming (NOTIFY_ vs CLAUDE_NOTIFY_)**: Convention difference, not a defect. Dual-prefix fallbacks in main.swift are intentional for backward compatibility.
- **Double PID file read (killPrevious then writePid)**: The read in `writePid` is a defensive safety check against races. Correct behavior.
- **Perl subprocess per timeout**: No better POSIX-portable alternative for millisecond-precision timeouts. Overhead is acceptable for the few calls per notification.
- **Sequential tmux commands / N+2 client iteration**: tmux has no compound-command API. Client iteration is bounded with early exit.
- **HelperPreparationOptions parameter count**: 5 fields with good defaults is not excessive.
- **Broad app scanning in resolveSenderAppURL**: Fallback path only, triggered when NSWorkspace lookup fails. Acceptable for rare cases.
- **Stringly-typed env var booleans**: Standard practice for shell↔process communication. Documented values are clear.
