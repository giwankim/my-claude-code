#!/bin/sh
# Automated tests for claude-notify

NOTIFY="$(dirname "$0")/claude-notify.app/Contents/MacOS/claude-notify"
PID_FILE="/tmp/claude-notify.pid"
PASS=0
FAIL=0

pass() { PASS=$((PASS+1)); printf "  PASS: %s\n" "$1"; }
fail() { FAIL=$((FAIL+1)); printf "  FAIL: %s\n" "$1"; }

wait_for_pid_file() {
  max_tries="${1:-50}"
  i=0
  while [ "$i" -lt "$max_tries" ]; do
    [ -s "$PID_FILE" ] && return 0
    sleep 0.1
    i=$((i+1))
  done
  return 1
}

wait_for_pid_removed() {
  max_tries="${1:-50}"
  i=0
  while [ "$i" -lt "$max_tries" ]; do
    [ ! -e "$PID_FILE" ] && return 0
    sleep 0.1
    i=$((i+1))
  done
  return 1
}

wait_for_process_exit() {
  pid="$1"
  max_tries="${2:-50}"
  i=0
  while [ "$i" -lt "$max_tries" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
    i=$((i+1))
  done
  return 1
}

cleanup() {
  # Kill any leftover test processes.
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    rm -f "$PID_FILE"
  fi
}
trap cleanup EXIT

# ---- Test 1: Binary exists ----
printf "Test 1: Binary exists\n"
if [ -x "$NOTIFY" ]; then
  pass "binary is executable"
else
  fail "binary not found or not executable at $NOTIFY"
fi

# ---- Test 2: -help exits 1 and prints usage to stderr ----
printf "Test 2: -help flag\n"
err=$("$NOTIFY" -help 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "-help exits 1"
else
  fail "-help exited $rc (expected 1)"
fi
if echo "$err" | grep -q "Usage:"; then
  pass "-help prints usage"
else
  fail "-help did not print usage"
fi

# ---- Test 3: Missing -message exits 1 ----
printf "Test 3: Missing -message\n"
"$NOTIFY" -title "test" 2>/dev/null
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "missing -message exits 1"
else
  fail "missing -message exited $rc (expected 1)"
fi

# ---- Test 4: Missing flag value exits 1 ----
printf "Test 4: Missing flag value\n"
"$NOTIFY" -title 2>/dev/null
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "missing flag value exits 1"
else
  fail "missing flag value exited $rc (expected 1)"
fi

# ---- Test 5: Unknown flag exits 1 ----
printf "Test 5: Unknown flag\n"
"$NOTIFY" -bogus 2>/dev/null
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "unknown flag exits 1"
else
  fail "unknown flag exited $rc (expected 1)"
fi

# ---- Test 6: PID file is written on launch and contains a running PID ----
printf "Test 6: PID file written\n"
rm -f "$PID_FILE"
"$NOTIFY" -message "pid-test" -group "test-pid" -timeout 5 &
bg_pid=$!
if wait_for_pid_file 50; then
  file_pid=$(cat "$PID_FILE")
  if kill -0 "$file_pid" 2>/dev/null; then
    pass "PID file contains running PID ($file_pid)"
  else
    fail "PID file contains $file_pid but process is not running"
  fi
else
  fail "PID file not created"
fi
kill "$file_pid" 2>/dev/null
kill "$bg_pid" 2>/dev/null
wait "$bg_pid" 2>/dev/null
sleep 0.2

# ---- Test 7: New instance kills previous instance ----
printf "Test 7: New instance kills previous\n"
rm -f "$PID_FILE"
"$NOTIFY" -message "instance-A" -group "test-kill" -timeout 10 &
shell_a=$!
if wait_for_pid_file 50; then
  pid_a=$(cat "$PID_FILE" 2>/dev/null)
else
  pid_a=""
fi
"$NOTIFY" -message "instance-B" -group "test-kill" -timeout 5 &
shell_b=$!
if [ -n "$pid_a" ] && wait_for_process_exit "$pid_a" 50; then
  pass "instance A ($pid_a) was killed"
elif [ -n "$pid_a" ] && kill -0 "$pid_a" 2>/dev/null; then
  fail "instance A ($pid_a) is still running"
  kill "$pid_a" 2>/dev/null
else
  fail "could not read PID for instance A"
fi
wait_for_pid_file 50 >/dev/null 2>&1
pid_b=$(cat "$PID_FILE" 2>/dev/null)
[ -n "$pid_b" ] && kill "$pid_b" 2>/dev/null
kill "$shell_a" "$shell_b" 2>/dev/null
wait "$shell_a" 2>/dev/null
wait "$shell_b" 2>/dev/null
sleep 0.2

# ---- Test 8: Timeout causes exit ----
printf "Test 8: Timeout exit\n"
rm -f "$PID_FILE"
"$NOTIFY" -message "timeout-test" -group "test-timeout" -timeout 2 &
timeout_pid=$!
if wait_for_process_exit "$timeout_pid" 60; then
  pass "process exited after timeout"
else
  fail "process still running after timeout"
  kill "$timeout_pid" 2>/dev/null
fi
wait "$timeout_pid" 2>/dev/null

# ---- Test 9: PID file removed after timeout ----
printf "Test 9: PID file removed after timeout\n"
if wait_for_pid_removed 30; then
  pass "PID file removed after timeout"
else
  fail "PID file still exists after timeout"
fi

# ---- Test 10: -remove exits quickly ----
printf "Test 10: -remove flag\n"
"$NOTIFY" -remove "test-remove" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "-remove exits 0"
else
  fail "-remove exited $rc (expected 0)"
fi

# ---- Test 11: SIGTERM causes clean exit and PID removal ----
printf "Test 11: SIGTERM cleanup\n"
rm -f "$PID_FILE"
"$NOTIFY" -message "sigterm-test" -group "test-sigterm" -timeout 30 &
sigterm_pid=$!
if wait_for_pid_file 50; then
  kill -TERM "$sigterm_pid"
  wait_for_process_exit "$sigterm_pid" 50 >/dev/null 2>&1
  wait "$sigterm_pid" 2>/dev/null
  if wait_for_pid_removed 30; then
    pass "SIGTERM: PID file cleaned up"
  else
    fail "PID file not removed after SIGTERM"
  fi
  if kill -0 "$sigterm_pid" 2>/dev/null; then
    fail "process still running after SIGTERM"
    kill -9 "$sigterm_pid" 2>/dev/null
  else
    pass "SIGTERM: process exited"
  fi
else
  fail "PID file was not written (cannot test SIGTERM)"
fi

# ---- Test 12: Notification posts successfully ----
printf "Test 12: Notification posts (via timeout exit)\n"
rm -f "$PID_FILE"
"$NOTIFY" -message "post-test" -group "test-post" -timeout 2 &
post_pid=$!
wait "$post_pid" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "notification posted (exit 0)"
else
  fail "notification post exited $rc (expected 0)"
fi

# ---- Test 13: notify.sh runs without error ----
printf "Test 13: notify.sh integration\n"
SCRIPT="$(dirname "$0")/notify.sh"
if [ -x "$SCRIPT" ] || [ -f "$SCRIPT" ]; then
  "$SCRIPT" "test from test-claude-notify.sh" 2>/dev/null
  rc=$?
  sleep 1
  # Kill the background notify process it spawned.
  if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    sleep 0.5
  fi
  if [ "$rc" -eq 0 ]; then
    pass "notify.sh exits 0"
  else
    fail "notify.sh exited $rc"
  fi
else
  fail "notify.sh not found"
fi

# ---- Test 14: Invalid sender mode exits 1 ----
printf "Test 14: Invalid sender mode\n"
"$NOTIFY" -message "sender-mode-invalid" -sender-mode "bogus" 2>/dev/null
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "invalid sender mode exits 1"
else
  fail "invalid sender mode exited $rc (expected 1)"
fi

# ---- Test 15: Required sender with missing bundle fails ----
printf "Test 15: Required sender missing bundle\n"
err=$("$NOTIFY" -message "sender-required-invalid" -sender-mode required -sender-bundle-id "com.example.__missing_sender__" -timeout 1 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "required sender mode fails when sender app missing"
else
  fail "required sender mode exited $rc (expected 1)"
fi
if echo "$err" | grep -q "sender spoof unavailable"; then
  pass "required sender mode prints spoof failure"
else
  fail "required sender mode did not print spoof failure"
fi

# ---- Test 16: Auto sender missing bundle falls back ----
printf "Test 16: Auto sender fallback\n"
err=$("$NOTIFY" -message "sender-auto-fallback" -sender-mode auto -sender-bundle-id "com.example.__missing_sender__" -timeout 1 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "auto sender mode falls back and exits 0"
else
  fail "auto sender mode exited $rc (expected 0)"
fi
if echo "$err" | grep -q "sender spoof unavailable"; then
  pass "auto sender mode warns on spoof failure"
else
  fail "auto sender mode did not warn on spoof failure"
fi

# ---- Test 17: Off sender mode ignores missing bundle ----
printf "Test 17: Sender mode off\n"
"$NOTIFY" -message "sender-off" -sender-mode off -sender-bundle-id "com.example.__missing_sender__" -timeout 1 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "sender mode off ignores spoof settings"
else
  fail "sender mode off exited $rc (expected 0)"
fi

# ---- Test 18: notify.sh sender env override ----
printf "Test 18: notify.sh sender env override\n"
if [ -x "$SCRIPT" ] || [ -f "$SCRIPT" ]; then
  NOTIFY_SENDER_MODE=off NOTIFY_SENDER_BUNDLE_ID="com.example.__missing_sender__" "$SCRIPT" "notify.sh sender override test" 2>/dev/null
  rc=$?
  sleep 1
  if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    sleep 0.5
  fi
  if [ "$rc" -eq 0 ]; then
    pass "notify.sh accepts sender env overrides"
  else
    fail "notify.sh sender override exited $rc"
  fi
else
  fail "notify.sh not found for sender override test"
fi

# ---- Test 19: Auto mode spoofed post failure triggers fallback ----
printf "Test 19: Auto spoofed post failure fallback\n"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 "$NOTIFY" -message "sender-auto-forced-failure" -sender-mode auto -spoofed-run -origin-exec "$NOTIFY" -timeout 2 2>&1 >/dev/null)
rc=$?
sleep 1
if [ -f "$PID_FILE" ]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null
  sleep 0.5
fi
if [ "$rc" -eq 0 ]; then
  pass "auto spoofed post failure exits 0"
else
  fail "auto spoofed post failure exited $rc (expected 0)"
fi
if echo "$err" | grep -q "launched fallback notification without spoof"; then
  pass "auto spoofed post failure launches fallback"
else
  fail "auto spoofed post failure did not launch fallback"
fi

# ---- Test 20: Required mode spoofed post failure does not fallback ----
printf "Test 20: Required spoofed post failure no fallback\n"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 "$NOTIFY" -message "sender-required-forced-failure" -sender-mode required -spoofed-run -origin-exec "$NOTIFY" -timeout 1 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "required spoofed post failure exits 0"
else
  fail "required spoofed post failure exited $rc (expected 0)"
fi
if echo "$err" | grep -q "launched fallback notification without spoof"; then
  fail "required spoofed post failure unexpectedly launched fallback"
else
  pass "required spoofed post failure does not fallback"
fi

# ---- Test 21: Required mode invalid sender app path fails ----
printf "Test 21: Required invalid sender app path\n"
err=$("$NOTIFY" -message "sender-required-bad-path" -sender-mode required -sender-app-path "/tmp/does-not-exist-sender.app" -timeout 1 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "required invalid sender app path exits 1"
else
  fail "required invalid sender app path exited $rc (expected 1)"
fi
if echo "$err" | grep -q "sender app path is not a valid app bundle"; then
  pass "required invalid sender app path prints validation error"
else
  fail "required invalid sender app path missing validation error"
fi

# ---- Test 22: Off mode ignores invalid sender app path ----
printf "Test 22: Off mode ignores invalid sender app path\n"
"$NOTIFY" -message "sender-off-bad-path" -sender-mode off -sender-app-path "/tmp/does-not-exist-sender.app" -timeout 1 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "off mode ignores invalid sender app path"
else
  fail "off mode invalid sender app path exited $rc (expected 0)"
fi

# ---- Test 23: Spoof relaunch path uses app launch ----
printf "Test 23: Spoof relaunch path\n"
MARKER="/tmp/claude-notify-relaunch-marker.$$"
rm -f "$MARKER"
SELF_APP="$(dirname "$0")/claude-notify.app"
CLAUDE_NOTIFY_TEST_SKIP_RELAUNCH=1 CLAUDE_NOTIFY_TEST_RELAUNCH_MARKER="$MARKER" \
  "$NOTIFY" -message "sender-relaunch-marker" -sender-mode auto -sender-app-path "$SELF_APP" -timeout 1 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "spoof relaunch probe exits 0"
else
  fail "spoof relaunch probe exited $rc"
fi
if [ -f "$MARKER" ] && grep -q '^open .*\.app$' "$MARKER"; then
  pass "spoof relaunch uses app open path"
else
  fail "spoof relaunch did not record app open path"
fi
rm -f "$MARKER"

# ---- Test 24: Spoof helper uses isolated signing identifier ----
printf "Test 24: Spoof helper signing identifier\n"
SPOOF_ID="com.example.notifyspoof.test"
SELF_APP="$(dirname "$0")/claude-notify.app"
CLAUDE_NOTIFY_TEST_SKIP_RELAUNCH=1 \
  CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID=1 \
  "$NOTIFY" -message "sender-signing-id" -sender-mode auto -sender-bundle-id "$SPOOF_ID" -sender-app-path "$SELF_APP" -timeout 1 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "spoof helper prep for signing probe exits 0"
else
  fail "spoof helper prep for signing probe exited $rc"
fi
HELPER_HOME="$HOME/Library/Caches/claude-notify/sender/$SPOOF_ID/claude-notify.app"
HELPER_TMP="/tmp/claude-notify/sender/$SPOOF_ID/claude-notify.app"
if [ -d "$HELPER_HOME" ]; then
  HELPER_APP="$HELPER_HOME"
elif [ -d "$HELPER_TMP" ]; then
  HELPER_APP="$HELPER_TMP"
else
  HELPER_APP=""
fi
BASE_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$(dirname "$0")/claude-notify.app/Contents/Info.plist" 2>/dev/null)
EXPECTED_PREFIX="${BASE_BUNDLE_ID:-com.gwk.claude-notify}.spoof."
if [ -n "$HELPER_APP" ]; then
  HELPER_IDENTIFIER=$(codesign -dv "$HELPER_APP" 2>&1 | sed -n 's/^Identifier=//p' | head -n 1)
else
  HELPER_IDENTIFIER=""
fi
case "$HELPER_IDENTIFIER" in
  "$EXPECTED_PREFIX"*)
    if [ "$HELPER_IDENTIFIER" = "$SPOOF_ID" ]; then
      fail "spoof helper identifier unexpectedly reuses sender bundle id"
    else
      pass "spoof helper code signing identifier is isolated from sender bundle id"
    fi
    ;;
  *)
    fail "spoof helper code signing identifier mismatch"
    ;;
esac

# ---- Test 25: stale pid file does not kill unrelated process ----
printf "Test 25: Stale PID safety guard\n"
sleep 20 &
SLEEP_PID=$!
echo "$SLEEP_PID" > "$PID_FILE"
"$NOTIFY" -message "stale-pid-guard" -timeout 1 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "stale pid guard probe exits 0"
else
  fail "stale pid guard probe exited $rc"
fi
if kill -0 "$SLEEP_PID" 2>/dev/null; then
  pass "stale pid guard preserved unrelated process"
  kill "$SLEEP_PID" 2>/dev/null
  wait "$SLEEP_PID" 2>/dev/null
else
  fail "stale pid guard killed unrelated process"
fi

# ---- Test 26: Auto isolated spoof failure falls back without non-isolated retry by default ----
printf "Test 26: Auto isolated spoof strict fallback\n"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID=1 \
  "$NOTIFY" -message "sender-auto-isolated-strict" -sender-mode auto -spoofed-run -origin-exec "$NOTIFY" -timeout 2 2>&1 >/dev/null)
rc=$?
sleep 1
if [ -f "$PID_FILE" ]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null
  sleep 0.5
fi
if [ "$rc" -eq 0 ]; then
  pass "auto isolated spoof strict fallback exits 0"
else
  fail "auto isolated spoof strict fallback exited $rc (expected 0)"
fi
if echo "$err" | grep -q "launched fallback notification without spoof"; then
  pass "auto isolated spoof strict fallback launches non-spoof fallback"
else
  fail "auto isolated spoof strict fallback did not launch non-spoof fallback"
fi
if echo "$err" | grep -q "retrying without isolated helper bundle id"; then
  fail "auto isolated spoof strict fallback unexpectedly retried non-isolated helper"
else
  pass "auto isolated spoof strict fallback avoids non-isolated retry by default"
fi

# ---- Test 27: Auto isolated spoof failure can opt-in to non-isolated retry ----
printf "Test 27: Auto isolated spoof opt-in retry\n"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID=1 CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY=1 \
  "$NOTIFY" -message "sender-auto-isolated-retry" -sender-mode auto -spoofed-run -origin-exec "$NOTIFY" -timeout 2 2>&1 >/dev/null)
rc=$?
sleep 1
if [ -f "$PID_FILE" ]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null
  sleep 0.5
fi
if [ "$rc" -eq 0 ]; then
  pass "auto isolated spoof opt-in retry exits 0"
else
  fail "auto isolated spoof opt-in retry exited $rc (expected 0)"
fi
if echo "$err" | grep -q "retrying without isolated helper bundle id"; then
  pass "auto isolated spoof opt-in retry uses non-isolated helper retry"
else
  fail "auto isolated spoof opt-in retry did not use non-isolated helper retry"
fi

# ---- Test 28: notify.sh uses NOTIFY_TMUX_BIN for tmux lookup and execute ----
printf "Test 28: notify.sh tmux binary override\n"
TMP_DIR="/tmp/claude-notify-test.$$"
mkdir -p "$TMP_DIR"
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
TMUX_LOG="$TMP_DIR/tmux-calls.log"
cat > "$FAKE_NOTIFY" <<'EOF'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$NOTIFY_ARGS_LOG"
  i=$((i+1))
done
exit 0
EOF
cat > "$FAKE_TMUX" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_CALL_LOG"
if [ "$1" = "display-message" ]; then
  printf '%s\n' "sess|1|win|/dev/pts/fake"
  exit 0
fi
exit 0
EOF
chmod +x "$FAKE_NOTIFY" "$FAKE_TMUX"
TMUX="/tmp/fake-socket,123,0" TMUX_PANE="%9" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" TMUX_CALL_LOG="$TMUX_LOG" NOTIFY_SENDER_MODE=off "$SCRIPT" "tmux override test" 2>/dev/null
rc=$?
i=0
while [ "$i" -lt 20 ] && [ ! -f "$ARGS_LOG" ]; do
  sleep 0.1
  i=$((i+1))
done
if [ "$rc" -eq 0 ]; then
  pass "notify.sh tmux override exits 0"
else
  fail "notify.sh tmux override exited $rc"
fi
if grep -q "^display-message -t %9 -p " "$TMUX_LOG"; then
  pass "notify.sh used NOTIFY_TMUX_BIN for tmux metadata lookup"
else
  fail "notify.sh did not use NOTIFY_TMUX_BIN for tmux metadata lookup"
fi
if grep -q "switch-client -c '/dev/pts/fake' -t '%9'" "$ARGS_LOG"; then
  pass "notify.sh execute payload references overridden tmux binary context"
else
  fail "notify.sh execute payload missing overridden tmux context"
fi
rm -rf "$TMP_DIR"

# ---- Test 29: notify.sh tmux metadata failure omits execute action ----
printf "Test 29: notify.sh tmux metadata failure fallback\n"
TMP_DIR="/tmp/claude-notify-test-fail.$$"
mkdir -p "$TMP_DIR"
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
TMUX_LOG="$TMP_DIR/tmux-calls.log"
cat > "$FAKE_NOTIFY" <<'EOF'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$NOTIFY_ARGS_LOG"
  i=$((i+1))
done
exit 0
EOF
cat > "$FAKE_TMUX" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_CALL_LOG"
exit 1
EOF
chmod +x "$FAKE_NOTIFY" "$FAKE_TMUX"
err=$(TMUX="/tmp/fake-socket,999,0" TMUX_PANE="%7" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" TMUX_CALL_LOG="$TMUX_LOG" NOTIFY_SENDER_MODE=off "$SCRIPT" "tmux failure test" 2>&1 >/dev/null)
rc=$?
i=0
while [ "$i" -lt 20 ] && [ ! -f "$ARGS_LOG" ]; do
  sleep 0.1
  i=$((i+1))
done
if [ "$rc" -eq 0 ]; then
  pass "notify.sh tmux metadata failure exits 0"
else
  fail "notify.sh tmux metadata failure exited $rc"
fi
if echo "$err" | grep -q "unable to read tmux context"; then
  pass "notify.sh tmux metadata failure emits warning"
else
  fail "notify.sh tmux metadata failure did not emit warning"
fi
if grep -q -- "-execute" "$ARGS_LOG"; then
  fail "notify.sh tmux metadata failure unexpectedly included execute action"
else
  pass "notify.sh tmux metadata failure omits execute action"
fi
rm -rf "$TMP_DIR"

# ---- Test 30: notify.sh default sender mode is off ----
printf "Test 30: notify.sh default sender mode is off\n"
TMP_DIR="/tmp/claude-notify-test-default-mode.$$"
mkdir -p "$TMP_DIR"
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
cat > "$FAKE_NOTIFY" <<'EOF'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$NOTIFY_ARGS_LOG"
  i=$((i+1))
done
exit 0
EOF
chmod +x "$FAKE_NOTIFY"
TMUX="" NOTIFY_SENDER_MODE= NOTIFY_ALLOW_NONISOLATED_RETRY= \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" "$SCRIPT" "default sender mode test" 2>/dev/null
rc=$?
i=0
while [ "$i" -lt 20 ] && [ ! -f "$ARGS_LOG" ]; do
  sleep 0.1
  i=$((i+1))
done
if [ "$rc" -eq 0 ]; then
  pass "notify.sh default sender mode probe exits 0"
else
  fail "notify.sh default sender mode probe exited $rc"
fi
if awk '/\]=-sender-mode$/{getline; if ($0 ~ /\]=off$/) found=1} END{exit found?0:1}' "$ARGS_LOG"; then
  pass "notify.sh forwards -sender-mode off by default"
else
  fail "notify.sh did not forward default -sender-mode off"
fi
rm -rf "$TMP_DIR"

# ---- Test 31: notify.sh sender mode env override auto ----
printf "Test 31: notify.sh sender mode env override auto\n"
TMP_DIR="/tmp/claude-notify-test-auto-mode.$$"
mkdir -p "$TMP_DIR"
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
cat > "$FAKE_NOTIFY" <<'EOF'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$NOTIFY_ARGS_LOG"
  i=$((i+1))
done
exit 0
EOF
chmod +x "$FAKE_NOTIFY"
TMUX="" NOTIFY_SENDER_MODE=auto NOTIFY_ALLOW_NONISOLATED_RETRY= \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" "$SCRIPT" "sender mode auto override test" 2>/dev/null
rc=$?
i=0
while [ "$i" -lt 20 ] && [ ! -f "$ARGS_LOG" ]; do
  sleep 0.1
  i=$((i+1))
done
if [ "$rc" -eq 0 ]; then
  pass "notify.sh sender mode auto override probe exits 0"
else
  fail "notify.sh sender mode auto override probe exited $rc"
fi
if awk '/\]=-sender-mode$/{getline; if ($0 ~ /\]=auto$/) found=1} END{exit found?0:1}' "$ARGS_LOG"; then
  pass "notify.sh forwards -sender-mode auto when overridden"
else
  fail "notify.sh did not forward overridden -sender-mode auto"
fi
rm -rf "$TMP_DIR"

# ---- Test 32: notify.sh default non-isolated retry env is 0 ----
printf "Test 32: notify.sh default non-isolated retry env\n"
TMP_DIR="/tmp/claude-notify-test-default-retry.$$"
mkdir -p "$TMP_DIR"
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
ENV_LOG="$TMP_DIR/notify-env.log"
cat > "$FAKE_NOTIFY" <<'EOF'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$NOTIFY_ARGS_LOG"
  i=$((i+1))
done
printf '%s\n' "$CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY" > "$NOTIFY_ENV_LOG"
exit 0
EOF
chmod +x "$FAKE_NOTIFY"
TMUX="" NOTIFY_SENDER_MODE= NOTIFY_ALLOW_NONISOLATED_RETRY= \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" NOTIFY_ENV_LOG="$ENV_LOG" "$SCRIPT" "default retry env test" 2>/dev/null
rc=$?
i=0
while [ "$i" -lt 20 ] && [ ! -f "$ENV_LOG" ]; do
  sleep 0.1
  i=$((i+1))
done
if [ "$rc" -eq 0 ]; then
  pass "notify.sh default retry env probe exits 0"
else
  fail "notify.sh default retry env probe exited $rc"
fi
if [ -f "$ENV_LOG" ] && grep -qx "0" "$ENV_LOG"; then
  pass "notify.sh exports CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY=0 by default"
else
  fail "notify.sh did not export default CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY=0"
fi
rm -rf "$TMP_DIR"

# ---- Summary ----
printf "\nResults: %d passed, %d failed\n" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
