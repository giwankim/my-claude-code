#!/bin/sh

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=hooks/claude-notify/Tests/shell/lib/testlib.sh
. "$PROJECT_DIR/Tests/shell/lib/testlib.sh"
# shellcheck source=hooks/claude-notify/Tests/shell/lib/notify-test-helpers.sh
. "$PROJECT_DIR/Tests/shell/lib/notify-test-helpers.sh"

NOTIFY="$PROJECT_DIR/claude-notify.app/Contents/MacOS/claude-notify"
SCRIPT="$PROJECT_DIR/notify.sh"
PID_FILE="/tmp/claude-notify.pid.$$"
TEST_TMP_DIRS=""
EXPECTED_NOTIFY_NAME=$(basename "$NOTIFY")
export CLAUDE_NOTIFY_PID_FILE="$PID_FILE"

cleanup() {
  kill_pid_from_file "$PID_FILE" "$EXPECTED_NOTIFY_NAME" >/dev/null 2>&1 || true
  rm -f "$PID_FILE"
  cleanup_registered_tmp_dirs
}
trap cleanup EXIT

# PID/signal lifecycle checks are decoupled from OS notification authorization.
# Delivery/fallback semantics remain covered by E007, E010, and E011.
case_start "E001" "PID file written on launch"
rm -f "$PID_FILE"
CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$NOTIFY" -message "pid-test" -group "test-pid" -timeout 5 &
bg_pid=$!
file_pid=""
if wait_for_pid_file "$PID_FILE" 50; then
  file_pid=$(cat "$PID_FILE")
  if kill -0 "$file_pid" 2>/dev/null; then
    pass "E001" "PID file contains running PID ($file_pid)"
  else
    fail "E001" "PID file contains $file_pid but process is not running"
  fi
else
  fail "E001" "PID file not created"
fi
if [ -n "$file_pid" ] && [ "$file_pid" -gt 0 ] 2>/dev/null; then
  kill "$file_pid" 2>/dev/null
  kill "$bg_pid" 2>/dev/null
  wait "$bg_pid" 2>/dev/null
fi
sleep 0.2

case_start "E002" "New instance kills previous instance"
rm -f "$PID_FILE"
CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$NOTIFY" -message "instance-A" -group "test-kill" -timeout 10 &
shell_a=$!
if wait_for_pid_file "$PID_FILE" 50; then
  pid_a=$(cat "$PID_FILE" 2>/dev/null)
else
  pid_a=""
fi
CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$NOTIFY" -message "instance-B" -group "test-kill" -timeout 5 &
shell_b=$!
if [ -n "$pid_a" ] && wait_for_process_exit "$pid_a" 50; then
  pass "E002" "instance A ($pid_a) was killed"
elif [ -n "$pid_a" ] && kill -0 "$pid_a" 2>/dev/null; then
  fail "E002" "instance A ($pid_a) is still running"
  kill "$pid_a" 2>/dev/null
else
  fail "E002" "could not read PID for instance A"
fi
wait_for_pid_file "$PID_FILE" 50 >/dev/null 2>&1
pid_b=$(cat "$PID_FILE" 2>/dev/null)
[ -n "$pid_b" ] && kill "$pid_b" 2>/dev/null
kill "$shell_a" "$shell_b" 2>/dev/null
wait "$shell_a" 2>/dev/null
wait "$shell_b" 2>/dev/null
sleep 0.2

case_start "E003" "Timeout causes exit"
rm -f "$PID_FILE"
CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$NOTIFY" -message "timeout-test" -group "test-timeout" -timeout 2 &
timeout_pid=$!
if wait_for_process_exit "$timeout_pid" 60; then
  pass "E003" "process exited after timeout"
else
  fail "E003" "process still running after timeout"
  kill "$timeout_pid" 2>/dev/null
fi
wait "$timeout_pid" 2>/dev/null

case_start "E004" "PID file removed after timeout"
rm -f "$PID_FILE"
CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$NOTIFY" -message "timeout-cleanup-test" -group "test-timeout-cleanup" -timeout 2 &
cleanup_pid=$!
if ! wait_for_pid_file "$PID_FILE" 50; then
  fail "E004" "PID file not created for timeout cleanup test"
  kill "$cleanup_pid" 2>/dev/null
  wait "$cleanup_pid" 2>/dev/null
elif ! wait_for_process_exit "$cleanup_pid" 60; then
  fail "E004" "process still running after timeout"
  kill "$cleanup_pid" 2>/dev/null
  wait "$cleanup_pid" 2>/dev/null
elif wait_for_pid_removed "$PID_FILE" 30; then
  wait "$cleanup_pid" 2>/dev/null
  pass "E004" "PID file removed after timeout"
else
  wait "$cleanup_pid" 2>/dev/null
  fail "E004" "PID file still exists after timeout"
fi

case_start "E005" "-remove exits quickly"
"$NOTIFY" -remove "test-remove" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "E005" "-remove exits 0"
else
  fail "E005" "-remove exited $rc (expected 0)"
fi

case_start "E006" "SIGTERM causes clean exit and PID removal"
rm -f "$PID_FILE"
CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$NOTIFY" -message "sigterm-test" -group "test-sigterm" -timeout 30 &
sigterm_pid=$!
if wait_for_pid_file "$PID_FILE" 50; then
  kill -TERM "$sigterm_pid"
  wait_for_process_exit "$sigterm_pid" 50 >/dev/null 2>&1
  wait "$sigterm_pid" 2>/dev/null
  if wait_for_pid_removed "$PID_FILE" 30; then
    pass "E006" "SIGTERM cleaned PID file"
  else
    fail "E006" "PID file not removed after SIGTERM"
  fi
  if kill -0 "$sigterm_pid" 2>/dev/null; then
    fail "E006" "process still running after SIGTERM"
    kill -9 "$sigterm_pid" 2>/dev/null
  else
    pass "E006" "SIGTERM process exited"
  fi
else
  fail "E006" "PID file not written (cannot test SIGTERM)"
fi

case_start "E007" "Notification post path exits cleanly"
rm -f "$PID_FILE"
TMP_DIR=$(make_case_tmp_dir "E007")
FAKE_OSASCRIPT="$TMP_DIR/fake-osascript.sh"
OSASCRIPT_LOG="$TMP_DIR/osascript-args.log"
write_fake_osascript_success "$FAKE_OSASCRIPT"
err=$(CLAUDE_NOTIFY_TEST_FORCE_AUTH_DENIED=1 CLAUDE_NOTIFY_OSASCRIPT_BIN="$FAKE_OSASCRIPT" OSASCRIPT_ARGS_LOG="$OSASCRIPT_LOG" \
  "$NOTIFY" -message "post-test" -group "test-post" -timeout 2 2>&1 >/dev/null)
rc=$?
drain_pid_file_if_present "$PID_FILE" 20 "$EXPECTED_NOTIFY_NAME"
if [ "$rc" -eq 0 ]; then
  pass "E007" "notification post path exited 0"
else
  fail "E007" "notification post path exited $rc"
fi
if wait_for_file "$OSASCRIPT_LOG" 20 >/dev/null 2>&1 \
  && grep -q '\[3\]=post-test' "$OSASCRIPT_LOG"; then
  pass "E007" "notification post path used deterministic AppleScript fallback payload"
else
  fail "E007" "notification post path missing deterministic AppleScript fallback payload"
fi
if echo "$err" | grep -q "posted notification via AppleScript fallback"; then
  pass "E007" "notification post path reports AppleScript fallback success"
else
  fail "E007" "notification post path missing AppleScript fallback success warning"
fi

case_start "E008" "notify.sh runs without error"
if [ -x "$SCRIPT" ] || [ -f "$SCRIPT" ]; then
  CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$SCRIPT" "test from test-runtime.sh" 2>/dev/null
  rc=$?
  drain_pid_file_if_present "$PID_FILE" 20 "$EXPECTED_NOTIFY_NAME"
  if [ "$rc" -eq 0 ]; then
    pass "E008" "notify.sh exits 0"
  else
    fail "E008" "notify.sh exited $rc"
  fi
else
  fail "E008" "notify.sh not found"
fi

case_start "E009" "Stale PID file does not kill unrelated process"
sleep 20 &
SLEEP_PID=$!
echo "$SLEEP_PID" > "$PID_FILE"
CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$NOTIFY" -message "stale-pid-guard" -timeout 1 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "E009" "stale PID guard probe exits 0"
else
  fail "E009" "stale PID guard probe exited $rc"
fi
if kill -0 "$SLEEP_PID" 2>/dev/null; then
  pass "E009" "stale PID guard preserved unrelated process"
  kill "$SLEEP_PID" 2>/dev/null
  wait "$SLEEP_PID" 2>/dev/null
else
  fail "E009" "stale PID guard killed unrelated process"
fi

case_start "E010" "Auto spoofed post failure triggers fallback"
TMP_DIR=$(make_case_tmp_dir "E010")
FAKE_ORIGIN="$TMP_DIR/fake-origin.sh"
ORIGIN_ARGS_LOG="$TMP_DIR/origin-args.log"
ORIGIN_ISOLATE_LOG="$TMP_DIR/origin-isolate.log"
ORIGIN_ALLOW_RETRY_LOG="$TMP_DIR/origin-allow-retry.log"
write_fake_origin_exec "$FAKE_ORIGIN"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 \
  ORIGIN_ARGS_LOG="$ORIGIN_ARGS_LOG" ORIGIN_ISOLATE_LOG="$ORIGIN_ISOLATE_LOG" ORIGIN_ALLOW_RETRY_LOG="$ORIGIN_ALLOW_RETRY_LOG" \
  "$NOTIFY" -message "sender-auto-forced-failure" -sender-mode auto -spoofed-run -origin-exec "$FAKE_ORIGIN" -timeout 2 2>&1 >/dev/null)
rc=$?
drain_pid_file_if_present "$PID_FILE" 20 "$EXPECTED_NOTIFY_NAME"
if [ "$rc" -eq 0 ]; then
  pass "E010" "auto spoofed post failure exits 0"
else
  fail "E010" "auto spoofed post failure exited $rc (expected 0)"
fi
if wait_for_file "$ORIGIN_ARGS_LOG" 20 >/dev/null 2>&1 \
  && awk '/\]=-sender-mode$/{ if (getline nextline > 0 && nextline ~ /\]=off$/) found=1 } END{exit found?0:1}' "$ORIGIN_ARGS_LOG" \
  && grep -q -- '\]=-fallback-run$' "$ORIGIN_ARGS_LOG"; then
  pass "E010" "auto spoofed post failure launched fallback run without spoof"
else
  fail "E010" "auto spoofed post failure did not launch expected fallback run"
fi
if ! echo "$err" | grep -q "launched fallback notification without spoof"; then
  printf '%s\n' "E010 diagnostic: fallback warning text missing (non-fatal)" >&2
fi

case_start "E011" "Required spoofed post failure does not fallback"
TMP_DIR=$(make_case_tmp_dir "E011")
FAKE_OSASCRIPT="$TMP_DIR/fake-osascript.sh"
OSASCRIPT_LOG="$TMP_DIR/osascript-args.log"
write_fake_osascript_success "$FAKE_OSASCRIPT"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 CLAUDE_NOTIFY_OSASCRIPT_BIN="$FAKE_OSASCRIPT" OSASCRIPT_ARGS_LOG="$OSASCRIPT_LOG" \
  "$NOTIFY" -message "sender-required-forced-failure" -sender-mode required -spoofed-run -origin-exec "$NOTIFY" -timeout 1 2>&1 >/dev/null)
rc=$?
drain_pid_file_if_present "$PID_FILE" 20 "$EXPECTED_NOTIFY_NAME"
if [ "$rc" -eq 0 ]; then
  pass "E011" "required spoofed post failure exits 0"
else
  fail "E011" "required spoofed post failure exited $rc (expected 0)"
fi
if wait_for_file "$OSASCRIPT_LOG" 20 >/dev/null 2>&1 \
  && grep -q '\[3\]=sender-required-forced-failure' "$OSASCRIPT_LOG"; then
  pass "E011" "required spoofed post failure uses deterministic AppleScript fallback payload"
else
  fail "E011" "required spoofed post failure missing deterministic AppleScript fallback payload"
fi
if echo "$err" | grep -q "launched fallback notification without spoof"; then
  fail "E011" "required spoofed post failure unexpectedly launched fallback"
else
  pass "E011" "required spoofed post failure does not fallback"
fi

case_start "E012" "notify.sh outside tmux logs activate inference path"
TMP_DIR=$(make_case_tmp_dir "E012")
FAKE_OSASCRIPT="$TMP_DIR/fake-osascript.sh"
OSASCRIPT_LOG="$TMP_DIR/osascript-args.log"
DEBUG_LOG="$TMP_DIR/notify-debug.log"
write_fake_osascript_success "$FAKE_OSASCRIPT"
TMUX="" NOTIFY_DEBUG_LOG="$DEBUG_LOG" NOTIFY_ACTIVATE_BUNDLE_ID="" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_OSASCRIPT" OSASCRIPT_ARGS_LOG="$OSASCRIPT_LOG" CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 NOTIFY_TIMEOUT=1 \
  "$SCRIPT" "e2e outside tmux inference test" 2>/dev/null
rc=$?
drain_pid_file_if_present "$PID_FILE" 30 "$EXPECTED_NOTIFY_NAME"
if [ "$rc" -eq 0 ]; then
  pass "E012" "notify.sh outside-tmux inference probe exits 0"
else
  fail "E012" "notify.sh outside-tmux inference probe exited $rc"
fi
if wait_for_file "$OSASCRIPT_LOG" 20 >/dev/null 2>&1 \
  && grep -q 'id of app (path to frontmost application as text)' "$OSASCRIPT_LOG"; then
  pass "E012" "notify.sh outside-tmux inference probe invoked deterministic frontmost-app osascript"
else
  fail "E012" "notify.sh outside-tmux inference probe missing deterministic frontmost-app osascript invocation"
fi
if grep -q "inferred activate bundle id outside tmux: com.jetbrains.intellij" "$DEBUG_LOG" \
  && grep -q "notify_run activate_override=com.jetbrains.intellij activate_bundle=com.jetbrains.intellij" "$DEBUG_LOG"; then
  pass "E012" "notify.sh outside-tmux debug log records inferred native activate path"
else
  fail "E012" "notify.sh outside-tmux debug log missing inferred native activate path"
fi

case_start "E013" "notify.sh tmux mode logs execute payload inference path"
TMP_DIR=$(make_case_tmp_dir "E013")
FAKE_OSASCRIPT="$TMP_DIR/fake-osascript.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
DEBUG_LOG="$TMP_DIR/notify-debug.log"
write_fake_osascript_success "$FAKE_OSASCRIPT"
TMUX_DISPLAY_MESSAGE_FORMAT=$(notify_tmux_display_message_format "$SCRIPT")
TMUX_DISPLAY_PAYLOAD=$(build_tmux_display_message_payload "sess" "6" "win" "3" "%61" "client-e2e" "/dev/ttys061")
if [ "$TMUX_DISPLAY_MESSAGE_FORMAT" != "$NOTIFY_TMUX_DISPLAY_MESSAGE_FORMAT" ]; then
  fail "E013" "notify.sh tmux display-message format drifted from expected parser contract"
fi
# Keep this fake wired to notify.sh's NOTIFY_TMUX_DISPLAY_MESSAGE_FORMAT parser template.
cat > "$FAKE_TMUX" <<FAKE_TMUX_E013
#!/bin/sh
if [ "\$1" = "display-message" ]; then
  printf '%s\n' "\$*" | grep -F -- " -p $TMUX_DISPLAY_MESSAGE_FORMAT" >/dev/null 2>&1 || exit 1
  printf '%s\n' "$TMUX_DISPLAY_PAYLOAD"
  exit 0
fi
exit 0
FAKE_TMUX_E013
chmod +x "$FAKE_TMUX"
TMUX="/tmp/fake-socket,661,0" TMUX_PANE="%61" NOTIFY_DEBUG_LOG="$DEBUG_LOG" NOTIFY_ACTIVATE_BUNDLE_ID="" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_OSASCRIPT" NOTIFY_TMUX_BIN="$FAKE_TMUX" CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 NOTIFY_TIMEOUT=1 \
  "$SCRIPT" "e2e tmux inference test" 2>/dev/null
rc=$?
drain_pid_file_if_present "$PID_FILE" 30 "$EXPECTED_NOTIFY_NAME"
if [ "$rc" -eq 0 ]; then
  pass "E013" "notify.sh tmux inference probe exits 0"
else
  fail "E013" "notify.sh tmux inference probe exited $rc"
fi
if grep -q "inferred activate bundle id in tmux mode: com.jetbrains.intellij" "$DEBUG_LOG" \
  && grep -q "notify_run activate_override=<empty> activate_bundle=com.jetbrains.intellij" "$DEBUG_LOG" \
  && grep -q "execute payload prepared .*activate_bundle=com.jetbrains.intellij" "$DEBUG_LOG"; then
  pass "E013" "notify.sh tmux debug log records execute payload inference path"
else
  fail "E013" "notify.sh tmux debug log missing execute payload inference path"
fi

finish
