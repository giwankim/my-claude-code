#!/bin/sh

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=hooks/tests/lib/testlib.sh
. "$ROOT_DIR/hooks/tests/lib/testlib.sh"

NOTIFY="$ROOT_DIR/hooks/claude-notify.app/Contents/MacOS/claude-notify"
SCRIPT="$ROOT_DIR/hooks/notify.sh"
PID_FILE="/tmp/claude-notify.pid.$$"
export CLAUDE_NOTIFY_PID_FILE="$PID_FILE"

cleanup() {
  if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null)
    [ -n "$pid" ] && kill "$pid" 2>/dev/null
    rm -f "$PID_FILE"
  fi
}
trap cleanup EXIT

case_start "E001" "PID file written on launch"
rm -f "$PID_FILE"
"$NOTIFY" -message "pid-test" -group "test-pid" -timeout 5 &
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
"$NOTIFY" -message "instance-A" -group "test-kill" -timeout 10 &
shell_a=$!
if wait_for_pid_file "$PID_FILE" 50; then
  pid_a=$(cat "$PID_FILE" 2>/dev/null)
else
  pid_a=""
fi
"$NOTIFY" -message "instance-B" -group "test-kill" -timeout 5 &
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
"$NOTIFY" -message "timeout-test" -group "test-timeout" -timeout 2 &
timeout_pid=$!
if wait_for_process_exit "$timeout_pid" 60; then
  pass "E003" "process exited after timeout"
else
  fail "E003" "process still running after timeout"
  kill "$timeout_pid" 2>/dev/null
fi
wait "$timeout_pid" 2>/dev/null

case_start "E004" "PID file removed after timeout"
if wait_for_pid_removed "$PID_FILE" 30; then
  pass "E004" "PID file removed after timeout"
else
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
"$NOTIFY" -message "sigterm-test" -group "test-sigterm" -timeout 30 &
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
"$NOTIFY" -message "post-test" -group "test-post" -timeout 2 &
post_pid=$!
wait "$post_pid" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "E007" "notification post path exited 0"
else
  fail "E007" "notification post path exited $rc"
fi

case_start "E008" "notify.sh runs without error"
if [ -x "$SCRIPT" ] || [ -f "$SCRIPT" ]; then
  "$SCRIPT" "test from test-runtime.sh" 2>/dev/null
  rc=$?
  sleep 1
  if [ -f "$PID_FILE" ]; then
    kill "$(cat "$PID_FILE")" 2>/dev/null
    sleep 0.5
  fi
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
"$NOTIFY" -message "stale-pid-guard" -timeout 1 2>/dev/null
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
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 "$NOTIFY" -message "sender-auto-forced-failure" -sender-mode auto -spoofed-run -origin-exec "$NOTIFY" -timeout 2 2>&1 >/dev/null)
rc=$?
sleep 1
if [ -f "$PID_FILE" ]; then
  kill "$(cat "$PID_FILE")" 2>/dev/null
  sleep 0.5
fi
if [ "$rc" -eq 0 ]; then
  pass "E010" "auto spoofed post failure exits 0"
else
  fail "E010" "auto spoofed post failure exited $rc (expected 0)"
fi
if echo "$err" | grep -q "launched fallback notification without spoof"; then
  pass "E010" "auto spoofed post failure launched fallback"
else
  fail "E010" "auto spoofed post failure did not launch fallback"
fi

case_start "E011" "Required spoofed post failure does not fallback"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 "$NOTIFY" -message "sender-required-forced-failure" -sender-mode required -spoofed-run -origin-exec "$NOTIFY" -timeout 1 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "E011" "required spoofed post failure exits 0"
else
  fail "E011" "required spoofed post failure exited $rc (expected 0)"
fi
if echo "$err" | grep -q "launched fallback notification without spoof"; then
  fail "E011" "required spoofed post failure unexpectedly launched fallback"
else
  pass "E011" "required spoofed post failure does not fallback"
fi

finish
