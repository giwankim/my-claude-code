#!/bin/sh

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=hooks/claude-notify/Tests/shell/lib/testlib.sh
. "$PROJECT_DIR/Tests/shell/lib/testlib.sh"
# shellcheck source=hooks/claude-notify/Tests/shell/lib/notify-test-helpers.sh
. "$PROJECT_DIR/Tests/shell/lib/notify-test-helpers.sh"

SCRIPT="$PROJECT_DIR/notify.sh"
TEST_TMP_DIRS=""
export NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS="${NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS:-2000}"
export NOTIFY_TMUX_CMD_TIMEOUT_MS="${NOTIFY_TMUX_CMD_TIMEOUT_MS:-2000}"

cleanup() {
  cleanup_registered_tmp_dirs
}
trap cleanup EXIT

case_start "U017" "notify.sh infers frontmost activate bundle outside tmux"
TMP_DIR=$(make_case_tmp_dir "U017")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_ACTIVATE_OSASCRIPT="$TMP_DIR/fake-activate-osascript.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
ACTIVATE_OSASCRIPT_ARGS_LOG="$TMP_DIR/activate-osascript-args.log"
write_fake_notify "$FAKE_NOTIFY"
write_fake_frontmost_osascript "$FAKE_ACTIVATE_OSASCRIPT"
TMUX="" NOTIFY_ACTIVATE_BUNDLE_ID="" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_ACTIVATE_OSASCRIPT" ACTIVATE_OSASCRIPT_ARGS_LOG="$ACTIVATE_OSASCRIPT_ARGS_LOG" \
  "$SCRIPT" "unit outside infer test" 2>/dev/null
rc=$?
wait_for_file "$ACTIVATE_OSASCRIPT_ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U017" "$rc" 0 \
  "notify.sh outside-tmux inference probe exits 0" \
  "notify.sh outside-tmux inference probe exited $rc"
assert_file_contains "U017" "$ACTIVATE_OSASCRIPT_ARGS_LOG" "id of app (path to frontmost application as text)" \
  "notify.sh probes frontmost app bundle outside tmux" \
  "notify.sh did not probe frontmost app bundle outside tmux"

case_start "U018" "notify.sh forwards inferred activate bundle outside tmux"
TMP_DIR=$(make_case_tmp_dir "U018")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_ACTIVATE_OSASCRIPT="$TMP_DIR/fake-activate-osascript.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
ACTIVATE_OSASCRIPT_ARGS_LOG="$TMP_DIR/activate-osascript-args.log"
write_fake_notify "$FAKE_NOTIFY"
write_fake_frontmost_osascript "$FAKE_ACTIVATE_OSASCRIPT"
TMUX="" NOTIFY_ACTIVATE_BUNDLE_ID="" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_ACTIVATE_OSASCRIPT" ACTIVATE_OSASCRIPT_ARGS_LOG="$ACTIVATE_OSASCRIPT_ARGS_LOG" \
  "$SCRIPT" "unit outside activate test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U018" "$rc" 0 \
  "notify.sh outside-tmux activate forwarding probe exits 0" \
  "notify.sh outside-tmux activate forwarding probe exited $rc"
if awk '/\]=-activate$/{getline; if ($0 ~ /\]=com.jetbrains.intellij$/) found=1} END{exit found?0:1}' "$ARGS_LOG"; then
  pass "U018" "notify.sh forwards inferred activate bundle as native -activate outside tmux"
else
  fail "U018" "notify.sh did not forward inferred activate bundle outside tmux"
fi

case_start "U019" "notify.sh tmux mode omits native -activate and emits execute payload"
TMP_DIR=$(make_case_tmp_dir "U019")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
FAKE_PS="$TMP_DIR/fake-ps.sh"
FAKE_ACTIVATE_OSASCRIPT="$TMP_DIR/fake-activate-osascript.sh"
FAKE_GHOSTTY_APP="$TMP_DIR/Ghostty.app"
FAKE_GHOSTTY_CLIENT_PID="420019"
ARGS_LOG="$TMP_DIR/notify-args.log"
ACTIVATE_OSASCRIPT_ARGS_LOG="$TMP_DIR/activate-osascript-args.log"
write_fake_notify "$FAKE_NOTIFY"
write_fake_frontmost_osascript "$FAKE_ACTIVATE_OSASCRIPT"
write_fake_app_bundle_runner "$FAKE_GHOSTTY_APP" "com.mitchellh.ghostty" "ghostty" >/dev/null
cat > "$FAKE_PS" <<FAKE_PS_U019
#!/bin/sh
pid=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -p)
      pid="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
case "\$pid" in
  420019)
    printf '%s\n' "420018 /usr/bin/tmux -L unit"
    ;;
  420018)
    printf '%s\n' "420017 $FAKE_GHOSTTY_APP/Contents/MacOS/ghostty --single-instance"
    ;;
  420017)
    printf '%s\n' "1 /sbin/launchd"
    ;;
esac
exit 0
FAKE_PS_U019
chmod +x "$FAKE_PS"
cat > "$FAKE_TMUX" <<FAKE_TMUX_U019
#!/bin/sh
if [ "\$1" = "display-message" ]; then
  printf '%s\n' "sess|9|win|1|%42|client-u|/dev/ttys042|$FAKE_GHOSTTY_CLIENT_PID"
  exit 0
fi
exit 0
FAKE_TMUX_U019
chmod +x "$FAKE_TMUX"
TMUX="/tmp/fake-socket,999,0" TMUX_PANE="%42" NOTIFY_ACTIVATE_BUNDLE_ID="" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_PS_BIN="$FAKE_PS" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_ACTIVATE_OSASCRIPT" \
  ACTIVATE_OSASCRIPT_ARGS_LOG="$ACTIVATE_OSASCRIPT_ARGS_LOG" "$SCRIPT" "unit tmux execute test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U019" "$rc" 0 \
  "notify.sh tmux execute probe exits 0" \
  "notify.sh tmux execute probe exited $rc"
assert_file_not_contains "U019" "$ARGS_LOG" '\]=-activate$' \
  "notify.sh omits native -activate in tmux mode" \
  "notify.sh unexpectedly forwarded native -activate in tmux mode"
assert_file_contains "U019" "$ARGS_LOG" '\]=-execute$' \
  "notify.sh emits execute payload in tmux mode" \
  "notify.sh did not emit execute payload in tmux mode"

case_start "U020" "notify.sh tmux execute payload carries resolved client host app bundle from tmux client pid ancestry"
# Uses ARGS_LOG generated by the U019 setup above.
if ! wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1; then
  fail "U020" "notify.sh did not produce tmux args log for U020 dependency check"
fi
assert_file_contains "U020" "$ARGS_LOG" "tmux-redirect.sh'.*'com.mitchellh.ghostty'" \
  "notify.sh resolves Ghostty activate bundle from tmux client pid ancestry" \
  "notify.sh did not resolve Ghostty activate bundle from tmux client pid ancestry"
assert_file_not_contains "U020" "$ACTIVATE_OSASCRIPT_ARGS_LOG" "id of app (path to frontmost application as text)" \
  "notify.sh skips frontmost-app inference when tmux client pid ancestry resolves host app" \
  "notify.sh unexpectedly probed frontmost app despite resolved tmux client pid ancestry"

case_start "U021" "notify.sh times out stdin read and falls back to default message"
TMP_DIR=$(make_case_tmp_dir "U021")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
FIFO="$TMP_DIR/hook-input.fifo"
write_fake_notify "$FAKE_NOTIFY"
mkfifo "$FIFO"
(sleep 300) > "$FIFO" &
stdin_writer_pid=$!
start_epoch=$(date +%s)
TMUX="" NOTIFY_SENDER_MODE=off NOTIFY_STDIN_TIMEOUT_MS=80 NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  "$SCRIPT" < "$FIFO" 2>/dev/null
rc=$?
end_epoch=$(date +%s)
elapsed=$((end_epoch - start_epoch))
kill "$stdin_writer_pid" >/dev/null 2>&1 || true
wait "$stdin_writer_pid" >/dev/null 2>&1 || true
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U021" "$rc" 0 \
  "notify.sh stdin-timeout probe exits 0" \
  "notify.sh stdin-timeout probe exited $rc"
if [ "$elapsed" -le 1 ]; then
  pass "U021" "notify.sh stdin-timeout probe exits quickly"
else
  fail "U021" "notify.sh stdin-timeout probe took ${elapsed}s (expected <=1s)"
fi
assert_file_contains "U021" "$ARGS_LOG" "Waiting for input" \
  "notify.sh stdin-timeout probe falls back to default message" \
  "notify.sh stdin-timeout probe missing fallback message"

case_start "U022" "notify.sh explicit message bypasses stdin read timeout path"
TMP_DIR=$(make_case_tmp_dir "U022")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
FIFO="$TMP_DIR/hook-input.fifo"
write_fake_notify "$FAKE_NOTIFY"
mkfifo "$FIFO"
(sleep 300) > "$FIFO" &
stdin_writer_pid=$!
start_epoch=$(date +%s)
TMUX="" NOTIFY_SENDER_MODE=off NOTIFY_STDIN_TIMEOUT_MS=5000 NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  "$SCRIPT" "explicit stop message" < "$FIFO" 2>/dev/null
rc=$?
end_epoch=$(date +%s)
elapsed=$((end_epoch - start_epoch))
kill "$stdin_writer_pid" >/dev/null 2>&1 || true
wait "$stdin_writer_pid" >/dev/null 2>&1 || true
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
wait_for_file_contains "$ARGS_LOG" "explicit stop message" 200 >/dev/null 2>&1 || true
assert_rc_eq "U022" "$rc" 0 \
  "notify.sh explicit-message probe exits 0" \
  "notify.sh explicit-message probe exited $rc"
if [ "$elapsed" -le 1 ]; then
  pass "U022" "notify.sh explicit-message probe returns quickly"
else
  fail "U022" "notify.sh explicit-message probe took ${elapsed}s (expected <=1s)"
fi
assert_file_contains "U022" "$ARGS_LOG" "explicit stop message" \
  "notify.sh explicit-message probe forwards argument payload" \
  "notify.sh explicit-message probe missing argument payload"
if ! grep -q -- "explicit stop message" "$ARGS_LOG" 2>/dev/null; then
  printf 'U022 diagnostic: ARGS_LOG content: %s\n' "$(cat "$ARGS_LOG" 2>/dev/null || echo '<missing>')" >&2
fi

case_start "U023" "notify.sh invalid stdin JSON falls back without blocking"
TMP_DIR=$(make_case_tmp_dir "U023")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
write_fake_notify "$FAKE_NOTIFY"
printf '%s' '{invalid-json' | TMUX="" NOTIFY_SENDER_MODE=off NOTIFY_STDIN_TIMEOUT_MS=200 NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  "$SCRIPT" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U023" "$rc" 0 \
  "notify.sh invalid-json probe exits 0" \
  "notify.sh invalid-json probe exited $rc"
assert_file_contains "U023" "$ARGS_LOG" "Waiting for input" \
  "notify.sh invalid-json probe falls back to default message" \
  "notify.sh invalid-json probe missing fallback message"

case_start "U024" "notify.sh uses last_assistant_message when message field is missing"
TMP_DIR=$(make_case_tmp_dir "U024")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
write_fake_notify "$FAKE_NOTIFY"
printf '%s' '{"last_assistant_message":"Final response from stop hook"}' | TMUX="" NOTIFY_SENDER_MODE=off NOTIFY_STDIN_TIMEOUT_MS=200 \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" "$SCRIPT" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U024" "$rc" 0 \
  "notify.sh last_assistant_message probe exits 0" \
  "notify.sh last_assistant_message probe exited $rc"
assert_file_contains "U024" "$ARGS_LOG" "Final response from stop hook" \
  "notify.sh parses last_assistant_message fallback field" \
  "notify.sh did not parse last_assistant_message fallback field"

case_start "U025" "notify.sh treats empty message as missing and falls back to last_assistant_message"
TMP_DIR=$(make_case_tmp_dir "U025")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
write_fake_notify "$FAKE_NOTIFY"
printf '%s' '{"message":"","last_assistant_message":"Assistant fallback message"}' | TMUX="" NOTIFY_SENDER_MODE=off NOTIFY_STDIN_TIMEOUT_MS=200 \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" "$SCRIPT" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U025" "$rc" 0 \
  "notify.sh empty-message fallback probe exits 0" \
  "notify.sh empty-message fallback probe exited $rc"
assert_file_contains "U025" "$ARGS_LOG" "Assistant fallback message" \
  "notify.sh falls back to last_assistant_message when message is empty" \
  "notify.sh did not fall back to last_assistant_message for empty message"

case_start "U026" "notify.sh logs activate probe failure when helper exits by signal"
TMP_DIR=$(make_case_tmp_dir "U026")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_SIGNAL_OSASCRIPT="$TMP_DIR/fake-signal-osascript.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
DEBUG_LOG="$TMP_DIR/notify-debug.log"
write_fake_notify "$FAKE_NOTIFY"
cat > "$FAKE_SIGNAL_OSASCRIPT" <<'FAKE_SIGNAL_OSASCRIPT_U026'
#!/bin/sh
kill -TERM "$$"
FAKE_SIGNAL_OSASCRIPT_U026
chmod +x "$FAKE_SIGNAL_OSASCRIPT"
TMUX="" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" NOTIFY_DEBUG_LOG="$DEBUG_LOG" \
  NOTIFY_ACTIVATE_BUNDLE_ID="" NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_SIGNAL_OSASCRIPT" "$SCRIPT" "signal probe test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U026" "$rc" 0 \
  "notify.sh signal-failure probe exits 0" \
  "notify.sh signal-failure probe exited $rc"
assert_file_contains "U026" "$DEBUG_LOG" "activate bundle inference failed rc=143" \
  "notify.sh preserves signal exit when activate probe child is terminated" \
  "notify.sh did not preserve signal exit code for activate probe child"

case_start "U027" "notify.sh skips perl runtime guard when all timeout wrappers are disabled"
TMP_DIR=$(make_case_tmp_dir "U027")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
EMPTY_PATH="$TMP_DIR/empty-path"
mkdir -p "$EMPTY_PATH"
write_fake_notify "$FAKE_NOTIFY"
PATH="$EMPTY_PATH" TMUX="" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_ACTIVATE_BUNDLE_ID="com.jetbrains.intellij" NOTIFY_STDIN_TIMEOUT_MS=0 \
  NOTIFY_TMUX_CMD_TIMEOUT_MS=0 NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS=0 \
  "$SCRIPT" "timeouts disabled perl test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U027" "$rc" 0 \
  "notify.sh all-timeouts-disabled probe exits 0 without perl on PATH" \
  "notify.sh all-timeouts-disabled probe exited $rc"
assert_file_contains "U027" "$ARGS_LOG" "timeouts disabled perl test" \
  "notify.sh all-timeouts-disabled probe still dispatches notification" \
  "notify.sh all-timeouts-disabled probe did not dispatch notification"

case_start "U028" "notify.sh requires perl runtime when any timeout wrapper is enabled"
TMP_DIR=$(make_case_tmp_dir "U028")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
EMPTY_PATH="$TMP_DIR/empty-path"
ERR_LOG="$TMP_DIR/notify.err"
mkdir -p "$EMPTY_PATH"
write_fake_notify "$FAKE_NOTIFY"
PATH="$EMPTY_PATH" TMUX="" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_ACTIVATE_BUNDLE_ID="com.jetbrains.intellij" NOTIFY_STDIN_TIMEOUT_MS=1 \
  NOTIFY_TMUX_CMD_TIMEOUT_MS=0 NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS=0 \
  "$SCRIPT" "timeouts enabled perl test" 2>"$ERR_LOG"
rc=$?
if [ "$rc" -ne 0 ]; then
  pass "U028" "notify.sh timeout-enabled probe fails fast without perl on PATH"
else
  fail "U028" "notify.sh timeout-enabled probe unexpectedly succeeded without perl on PATH"
fi
assert_file_contains "U028" "$ERR_LOG" "perl is required for timeout handling" \
  "notify.sh timeout-enabled probe reports missing perl runtime requirement" \
  "notify.sh timeout-enabled probe did not report missing perl runtime requirement"

case_start "U029" "notify.sh tmux timeout path remains fast when stderr is captured"
TMP_DIR=$(make_case_tmp_dir "U029")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
write_fake_notify "$FAKE_NOTIFY"
cat > "$FAKE_TMUX" <<'FAKE_TMUX_U029'
#!/bin/sh
if [ "$1" = "display-message" ]; then
  sleep 30
  printf '%s\n' "sess|1|win|1|%1|client-slow|/dev/ttys001"
  exit 0
fi
exit 0
FAKE_TMUX_U029
chmod +x "$FAKE_TMUX"
start_ms=$(now_ms)
err=$(TMUX="/tmp/fake-socket,111,0" TMUX_PANE="%1" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" NOTIFY_TMUX_CMD_TIMEOUT_MS=100 NOTIFY_SENDER_MODE=off \
  "$SCRIPT" "tmux timeout capture test" 2>&1 >/dev/null)
rc=$?
end_ms=$(now_ms)
elapsed_ms=$((end_ms - start_ms))
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U029" "$rc" 0 \
  "notify.sh tmux timeout capture probe exits 0" \
  "notify.sh tmux timeout capture probe exited $rc"
# U029 is intentionally load-sensitive: with NOTIFY_TMUX_CMD_TIMEOUT_MS=100,
# elapsed_ms can overshoot under CI contention due to process-group kill + waitpid.
# I130/I131 (same pattern) have shown CI peaks above 2100ms, so we use a 35x
# ceiling for stability. The fake sleep is 30s, so a broken timeout that lets the
# sleep complete would far exceed this ceiling.
if [ "$elapsed_ms" -le 3500 ]; then
  pass "U029" "notify.sh tmux timeout capture probe exits quickly"
else
  fail "U029" "notify.sh tmux timeout capture probe took ${elapsed_ms}ms (expected <=3500ms)"
fi
if echo "$err" | grep -q "unable to read tmux context"; then
  pass "U029" "notify.sh tmux timeout capture probe emits fail-open warning"
else
  fail "U029" "notify.sh tmux timeout capture probe missing fail-open warning"
fi

case_start "U030" "notify.sh logs invalid timeout env values at debug level"
TMP_DIR=$(make_case_tmp_dir "U030")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
DEBUG_LOG="$TMP_DIR/notify-debug.log"
write_fake_notify "$FAKE_NOTIFY"
TMUX="" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" NOTIFY_DEBUG_LOG="$DEBUG_LOG" \
  NOTIFY_ACTIVATE_BUNDLE_ID="com.jetbrains.intellij" NOTIFY_SENDER_MODE=off \
  NOTIFY_STDIN_TIMEOUT_MS="15O" "$SCRIPT" "invalid timeout debug test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U030" "$rc" 0 \
  "notify.sh invalid-timeout debug probe exits 0" \
  "notify.sh invalid-timeout debug probe exited $rc"
assert_file_contains "U030" "$DEBUG_LOG" "invalid timeout value for NOTIFY_STDIN_TIMEOUT_MS='15O'; using default 150ms" \
  "notify.sh logs invalid timeout env fallback at debug level" \
  "notify.sh did not log invalid timeout env fallback at debug level"

case_start "U031" "notify.sh uses explicit tmux query branches instead of shared dedup helpers"
if grep -Eq 'run_tmux_query_with_logging[[:space:]]*\(\)[[:space:]]*\{' "$SCRIPT"; then
  fail "U031" "notify.sh still defines shared tmux query logging helper"
else
  pass "U031" "notify.sh removed shared tmux query logging helper"
fi
if grep -Eq 'tmux_query[[:space:]]*\(\)[[:space:]]*\{' "$SCRIPT"; then
  fail "U031" "notify.sh still defines shared tmux query wrapper"
else
  pass "U031" "notify.sh removed shared tmux query wrapper"
fi
if grep -Eq 'TARGET_PANE="\$\(run_with_timeout_ms[[:space:]]+"\$TMUX_CMD_TIMEOUT_MS"[[:space:]]+"\$TMUX_BIN"[[:space:]]+display-message[[:space:]]+-p[[:space:]]+'\''#\{pane_id\}'\''' "$SCRIPT"; then
  pass "U031" "notify.sh target pane lookup has explicit timeout branch"
else
  fail "U031" "notify.sh target pane lookup missing explicit timeout branch"
fi
if grep -Eq 'TARGET_PANE="\$\("\$TMUX_BIN"[[:space:]]+display-message[[:space:]]+-p[[:space:]]+'\''#\{pane_id\}'\''' "$SCRIPT"; then
  pass "U031" "notify.sh target pane lookup has explicit non-timeout branch"
else
  fail "U031" "notify.sh target pane lookup missing explicit non-timeout branch"
fi
if grep -Eq 'CLIENT_INFO="\$\(run_with_timeout_ms[[:space:]]+"\$TMUX_CMD_TIMEOUT_MS"[[:space:]]+"\$TMUX_BIN"[[:space:]]+display-message[[:space:]]+-p[[:space:]]+'\''#\{client_name\}\|#\{client_tty\}\|#\{client_pid\}'\''' "$SCRIPT"; then
  pass "U031" "notify.sh client metadata lookup has explicit timeout branch"
else
  fail "U031" "notify.sh client metadata lookup missing explicit timeout branch"
fi
if grep -Eq 'CLIENT_INFO="\$\("\$TMUX_BIN"[[:space:]]+display-message[[:space:]]+-p[[:space:]]+'\''#\{client_name\}\|#\{client_tty\}\|#\{client_pid\}'\''' "$SCRIPT"; then
  pass "U031" "notify.sh client metadata lookup has explicit non-timeout branch"
else
  fail "U031" "notify.sh client metadata lookup missing explicit non-timeout branch"
fi

case_start "U032" "notify.sh timeout kill target always uses child process group"
assert_file_contains "U032" "$SCRIPT" 'my $kill_target = -$pid;' \
  "notify.sh sets timeout kill target to child process group unconditionally" \
  "notify.sh does not set unconditional process-group kill target"
assert_file_not_contains "U032" "$SCRIPT" 'my $use_process_group_kill = 0;' \
  "notify.sh removes conditional process-group kill flag logic" \
  "notify.sh still has conditional process-group kill flag logic"
assert_file_not_contains "U032" "$SCRIPT" 'if (setpgid($pid, $pid) == 0)' \
  "notify.sh removes parent-side setpgid race path" \
  "notify.sh still has parent-side setpgid race path"

case_start "U033" "notify.sh logs missing jq dependency when stdin payload parsing is unavailable"
TMP_DIR=$(make_case_tmp_dir "U033")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
DEBUG_LOG="$TMP_DIR/notify-debug.log"
NO_JQ_PATH="$TMP_DIR/no-jq-path"
mkdir -p "$NO_JQ_PATH"
ln -s /bin/cat "$NO_JQ_PATH/cat"
ln -s /bin/date "$NO_JQ_PATH/date"
write_fake_notify "$FAKE_NOTIFY"
printf '%s' '{"message":"payload message without jq"}' | \
  PATH="$NO_JQ_PATH" TMUX="" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" NOTIFY_DEBUG_LOG="$DEBUG_LOG" \
  NOTIFY_ACTIVATE_BUNDLE_ID="com.jetbrains.intellij" NOTIFY_SENDER_MODE=off \
  NOTIFY_STDIN_TIMEOUT_MS=0 NOTIFY_TMUX_CMD_TIMEOUT_MS=0 NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS=0 \
  "$SCRIPT" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U033" "$rc" 0 \
  "notify.sh missing-jq payload probe exits 0" \
  "notify.sh missing-jq payload probe exited $rc"
assert_file_contains "U033" "$ARGS_LOG" "Waiting for input" \
  "notify.sh missing-jq payload probe falls back to default message" \
  "notify.sh missing-jq payload probe did not fall back to default message"
assert_file_contains "U033" "$DEBUG_LOG" "jq not found; cannot parse stdin payload" \
  "notify.sh logs missing jq dependency at debug level" \
  "notify.sh missing-jq payload probe did not log missing jq dependency"

case_start "U034" "notify.sh tmux mode explicit activate bundle override wins over client-pid resolver"
TMP_DIR=$(make_case_tmp_dir "U034")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
write_fake_notify "$FAKE_NOTIFY"
cat > "$FAKE_TMUX" <<FAKE_TMUX_U034
#!/bin/sh
if [ "\$1" = "display-message" ]; then
  printf '%s\n' "sess|4|win|2|%34|client-34|/dev/ttys034|420034"
  exit 0
fi
exit 0
FAKE_TMUX_U034
chmod +x "$FAKE_TMUX"
TMUX="/tmp/fake-socket,434,0" TMUX_PANE="%34" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" NOTIFY_ACTIVATE_BUNDLE_ID="com.example.explicit" "$SCRIPT" "tmux explicit override test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U034" "$rc" 0 \
  "notify.sh tmux explicit override probe exits 0" \
  "notify.sh tmux explicit override probe exited $rc"
assert_file_contains "U034" "$ARGS_LOG" "tmux-redirect.sh'.*'com.example.explicit'" \
  "notify.sh tmux explicit activate bundle override wins over resolver output" \
  "notify.sh tmux explicit activate bundle override did not win over resolver output"

case_start "U035" "notify.sh tmux mode unresolved client-pid ancestry keeps activate bundle empty by default fallback"
TMP_DIR=$(make_case_tmp_dir "U035")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
FAKE_REDIRECT="$TMP_DIR/fake-tmux-redirect.sh"
FAKE_ACTIVATE_OSASCRIPT="$TMP_DIR/fake-activate-osascript.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
REDIRECT_ARGS_LOG="$TMP_DIR/redirect-args.log"
ACTIVATE_OSASCRIPT_ARGS_LOG="$TMP_DIR/activate-osascript-args.log"
write_fake_notify "$FAKE_NOTIFY"
write_fake_frontmost_osascript "$FAKE_ACTIVATE_OSASCRIPT"
cat > "$FAKE_TMUX" <<'FAKE_TMUX_U035'
#!/bin/sh
if [ "$1" = "display-message" ]; then
  printf '%s\n' "sess|5|win|3|%35|client-35|/dev/ttys035|1"
  exit 0
fi
exit 0
FAKE_TMUX_U035
cat > "$FAKE_REDIRECT" <<'FAKE_REDIRECT_U035'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$REDIRECT_ARGS_LOG"
  i=$((i + 1))
done
exit 0
FAKE_REDIRECT_U035
chmod +x "$FAKE_TMUX" "$FAKE_REDIRECT"
TMUX="/tmp/fake-socket,535,0" TMUX_PANE="%35" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" NOTIFY_TMUX_REDIRECT_SCRIPT="$FAKE_REDIRECT" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_ACTIVATE_OSASCRIPT" ACTIVATE_OSASCRIPT_ARGS_LOG="$ACTIVATE_OSASCRIPT_ARGS_LOG" \
  "$SCRIPT" "tmux fallback none test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U035" "$rc" 0 \
  "notify.sh tmux fallback-none probe exits 0" \
  "notify.sh tmux fallback-none probe exited $rc"
if EXECUTE_PAYLOAD=$(wait_for_execute_payload "$ARGS_LOG" 20); then
  REDIRECT_ARGS_LOG="$REDIRECT_ARGS_LOG" /bin/sh -c "$EXECUTE_PAYLOAD" >/dev/null 2>&1
else
  fail "U035" "notify.sh tmux fallback-none probe did not emit execute payload"
fi
assert_file_contains "U035" "$REDIRECT_ARGS_LOG" '^\[6\]=$' \
  "notify.sh tmux fallback-none keeps activate bundle argument empty" \
  "notify.sh tmux fallback-none did not keep activate bundle argument empty"
assert_file_not_contains "U035" "$ACTIVATE_OSASCRIPT_ARGS_LOG" "id of app (path to frontmost application as text)" \
  "notify.sh tmux fallback-none does not invoke frontmost-app probe" \
  "notify.sh tmux fallback-none unexpectedly invoked frontmost-app probe"

case_start "U036" "notify.sh tmux mode fallback frontmost preserves legacy activate inference when enabled"
TMP_DIR=$(make_case_tmp_dir "U036")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
FAKE_REDIRECT="$TMP_DIR/fake-tmux-redirect.sh"
FAKE_ACTIVATE_OSASCRIPT="$TMP_DIR/fake-activate-osascript.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
REDIRECT_ARGS_LOG="$TMP_DIR/redirect-args.log"
ACTIVATE_OSASCRIPT_ARGS_LOG="$TMP_DIR/activate-osascript-args.log"
write_fake_notify "$FAKE_NOTIFY"
write_fake_frontmost_osascript "$FAKE_ACTIVATE_OSASCRIPT"
cat > "$FAKE_TMUX" <<'FAKE_TMUX_U036'
#!/bin/sh
if [ "$1" = "display-message" ]; then
  printf '%s\n' "sess|6|win|3|%36|client-36|/dev/ttys036|1"
  exit 0
fi
exit 0
FAKE_TMUX_U036
cat > "$FAKE_REDIRECT" <<'FAKE_REDIRECT_U036'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$REDIRECT_ARGS_LOG"
  i=$((i + 1))
done
exit 0
FAKE_REDIRECT_U036
chmod +x "$FAKE_TMUX" "$FAKE_REDIRECT"
TMUX="/tmp/fake-socket,636,0" TMUX_PANE="%36" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" NOTIFY_TMUX_REDIRECT_SCRIPT="$FAKE_REDIRECT" NOTIFY_TMUX_ACTIVATE_FALLBACK="frontmost" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_ACTIVATE_OSASCRIPT" ACTIVATE_OSASCRIPT_ARGS_LOG="$ACTIVATE_OSASCRIPT_ARGS_LOG" \
  "$SCRIPT" "tmux fallback frontmost test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U036" "$rc" 0 \
  "notify.sh tmux fallback-frontmost probe exits 0" \
  "notify.sh tmux fallback-frontmost probe exited $rc"
if EXECUTE_PAYLOAD=$(wait_for_execute_payload "$ARGS_LOG" 20); then
  REDIRECT_ARGS_LOG="$REDIRECT_ARGS_LOG" /bin/sh -c "$EXECUTE_PAYLOAD" >/dev/null 2>&1
else
  fail "U036" "notify.sh tmux fallback-frontmost probe did not emit execute payload"
fi
assert_file_contains "U036" "$REDIRECT_ARGS_LOG" '^\[6\]=com.jetbrains.intellij$' \
  "notify.sh tmux fallback-frontmost preserves legacy inferred activate bundle" \
  "notify.sh tmux fallback-frontmost did not preserve legacy inferred activate bundle"
assert_file_contains "U036" "$ACTIVATE_OSASCRIPT_ARGS_LOG" "id of app (path to frontmost application as text)" \
  "notify.sh tmux fallback-frontmost invokes frontmost-app probe" \
  "notify.sh tmux fallback-frontmost did not invoke frontmost-app probe"

case_start "U037" "notify.sh tmux mode resolves IntelliJ host app bundle from client pid ancestry"
TMP_DIR=$(make_case_tmp_dir "U037")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
FAKE_REDIRECT="$TMP_DIR/fake-tmux-redirect.sh"
FAKE_PS="$TMP_DIR/fake-ps.sh"
FAKE_ACTIVATE_OSASCRIPT="$TMP_DIR/fake-activate-osascript.sh"
FAKE_IDEA_APP="$TMP_DIR/IntelliJ IDEA.app"
FAKE_IDEA_CLIENT_PID="420037"
ARGS_LOG="$TMP_DIR/notify-args.log"
REDIRECT_ARGS_LOG="$TMP_DIR/redirect-args.log"
ACTIVATE_OSASCRIPT_ARGS_LOG="$TMP_DIR/activate-osascript-args.log"
write_fake_notify "$FAKE_NOTIFY"
write_fake_frontmost_osascript "$FAKE_ACTIVATE_OSASCRIPT"
write_fake_app_bundle_runner "$FAKE_IDEA_APP" "com.jetbrains.intellij" "idea" >/dev/null
cat > "$FAKE_PS" <<FAKE_PS_U037
#!/bin/sh
pid=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -p)
      pid="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
case "\$pid" in
  420037)
    printf '%s\n' "420036 /usr/bin/tmux -L unit"
    ;;
  420036)
    printf '%s\n' "420035 $FAKE_IDEA_APP/Contents/MacOS/idea --nosplash"
    ;;
  420035)
    printf '%s\n' "1 /sbin/launchd"
    ;;
esac
exit 0
FAKE_PS_U037
chmod +x "$FAKE_PS"
cat > "$FAKE_TMUX" <<FAKE_TMUX_U037
#!/bin/sh
if [ "\$1" = "display-message" ]; then
  printf '%s\n' "sess|7|win|3|%37|client-37|/dev/ttys037|$FAKE_IDEA_CLIENT_PID"
  exit 0
fi
exit 0
FAKE_TMUX_U037
cat > "$FAKE_REDIRECT" <<'FAKE_REDIRECT_U037'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$REDIRECT_ARGS_LOG"
  i=$((i + 1))
done
exit 0
FAKE_REDIRECT_U037
chmod +x "$FAKE_TMUX" "$FAKE_REDIRECT"
TMUX="/tmp/fake-socket,737,0" TMUX_PANE="%37" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" NOTIFY_TMUX_REDIRECT_SCRIPT="$FAKE_REDIRECT" \
  NOTIFY_PS_BIN="$FAKE_PS" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_ACTIVATE_OSASCRIPT" ACTIVATE_OSASCRIPT_ARGS_LOG="$ACTIVATE_OSASCRIPT_ARGS_LOG" \
  "$SCRIPT" "tmux intellij pid ancestry test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U037" "$rc" 0 \
  "notify.sh tmux IntelliJ ancestry probe exits 0" \
  "notify.sh tmux IntelliJ ancestry probe exited $rc"
if EXECUTE_PAYLOAD=$(wait_for_execute_payload "$ARGS_LOG" 20); then
  REDIRECT_ARGS_LOG="$REDIRECT_ARGS_LOG" /bin/sh -c "$EXECUTE_PAYLOAD" >/dev/null 2>&1
else
  fail "U037" "notify.sh tmux IntelliJ ancestry probe did not emit execute payload"
fi
assert_file_contains "U037" "$REDIRECT_ARGS_LOG" '^\[6\]=com.jetbrains.intellij$' \
  "notify.sh tmux resolves IntelliJ bundle id from client pid ancestry" \
  "notify.sh tmux did not resolve IntelliJ bundle id from client pid ancestry"
assert_file_not_contains "U037" "$ACTIVATE_OSASCRIPT_ARGS_LOG" "id of app (path to frontmost application as text)" \
  "notify.sh tmux IntelliJ ancestry path skips frontmost-app probe" \
  "notify.sh tmux IntelliJ ancestry path unexpectedly invoked frontmost-app probe"

case_start "U038" "notify.sh tmux mode resolves quoted IntelliJ app path from wrapped client pid ancestry"
TMP_DIR=$(make_case_tmp_dir "U038")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
FAKE_REDIRECT="$TMP_DIR/fake-tmux-redirect.sh"
FAKE_PS="$TMP_DIR/fake-ps.sh"
FAKE_ACTIVATE_OSASCRIPT="$TMP_DIR/fake-activate-osascript.sh"
FAKE_IDEA_APP="$TMP_DIR/IntelliJ IDEA.app"
FAKE_IDEA_CLIENT_PID="420038"
ARGS_LOG="$TMP_DIR/notify-args.log"
REDIRECT_ARGS_LOG="$TMP_DIR/redirect-args.log"
ACTIVATE_OSASCRIPT_ARGS_LOG="$TMP_DIR/activate-osascript-args.log"
write_fake_notify "$FAKE_NOTIFY"
write_fake_frontmost_osascript "$FAKE_ACTIVATE_OSASCRIPT"
write_fake_app_bundle_runner "$FAKE_IDEA_APP" "com.jetbrains.intellij" "idea" >/dev/null
cat > "$FAKE_PS" <<FAKE_PS_U038
#!/bin/sh
pid=""
while [ "\$#" -gt 0 ]; do
  case "\$1" in
    -p)
      pid="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
case "\$pid" in
  420038)
    printf '%s\n' "420137 /usr/bin/tmux -L unit"
    ;;
  420137)
    printf '%s\n' "420136 /bin/sh -lc '$FAKE_IDEA_APP/Contents/MacOS/idea --nosplash'"
    ;;
  420136)
    printf '%s\n' "1 /sbin/launchd"
    ;;
esac
exit 0
FAKE_PS_U038
chmod +x "$FAKE_PS"
cat > "$FAKE_TMUX" <<FAKE_TMUX_U038
#!/bin/sh
if [ "\$1" = "display-message" ]; then
  printf '%s\n' "sess|8|win|3|%38|client-38|/dev/ttys038|$FAKE_IDEA_CLIENT_PID"
  exit 0
fi
exit 0
FAKE_TMUX_U038
cat > "$FAKE_REDIRECT" <<'FAKE_REDIRECT_U038'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$REDIRECT_ARGS_LOG"
  i=$((i + 1))
done
exit 0
FAKE_REDIRECT_U038
chmod +x "$FAKE_TMUX" "$FAKE_REDIRECT"
TMUX="/tmp/fake-socket,838,0" TMUX_PANE="%38" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" NOTIFY_TMUX_REDIRECT_SCRIPT="$FAKE_REDIRECT" \
  NOTIFY_PS_BIN="$FAKE_PS" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_ACTIVATE_OSASCRIPT" ACTIVATE_OSASCRIPT_ARGS_LOG="$ACTIVATE_OSASCRIPT_ARGS_LOG" \
  "$SCRIPT" "tmux wrapped intellij pid ancestry test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
assert_rc_eq "U038" "$rc" 0 \
  "notify.sh tmux wrapped IntelliJ ancestry probe exits 0" \
  "notify.sh tmux wrapped IntelliJ ancestry probe exited $rc"
if EXECUTE_PAYLOAD=$(wait_for_execute_payload "$ARGS_LOG" 20); then
  REDIRECT_ARGS_LOG="$REDIRECT_ARGS_LOG" /bin/sh -c "$EXECUTE_PAYLOAD" >/dev/null 2>&1
else
  fail "U038" "notify.sh tmux wrapped IntelliJ ancestry probe did not emit execute payload"
fi
assert_file_contains "U038" "$REDIRECT_ARGS_LOG" '^\[6\]=com.jetbrains.intellij$' \
  "notify.sh tmux resolves quoted IntelliJ bundle id from wrapped client pid ancestry" \
  "notify.sh tmux did not resolve quoted IntelliJ bundle id from wrapped client pid ancestry"
assert_file_not_contains "U038" "$ACTIVATE_OSASCRIPT_ARGS_LOG" "id of app (path to frontmost application as text)" \
  "notify.sh tmux wrapped IntelliJ ancestry path skips frontmost-app probe" \
  "notify.sh tmux wrapped IntelliJ ancestry path unexpectedly invoked frontmost-app probe"

case_start "U039" "notify.sh resolve_bundle_id_from_app_path returns non-zero when CFBundleIdentifier is missing"
TMP_DIR=$(make_case_tmp_dir "U039")
FAKE_FUNC_SCRIPT="$TMP_DIR/notify-resolver-func.sh"
FAKE_APP="$TMP_DIR/Missing Bundle ID.app"
mkdir -p "$FAKE_APP/Contents"
cat > "$FAKE_APP/Contents/Info.plist" <<'U039_INFO_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>Missing Bundle ID</string>
</dict>
</plist>
U039_INFO_PLIST
awk '
  /^resolve_bundle_id_from_app_path\(\)/ {capture=1}
  capture {print}
  capture && /^}$/ {exit}
' "$SCRIPT" > "$FAKE_FUNC_SCRIPT"
# shellcheck source=/dev/null
. "$FAKE_FUNC_SCRIPT"
resolve_bundle_id_from_app_path "$FAKE_APP" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then
  pass "U039" "notify.sh resolver returns non-zero when CFBundleIdentifier is missing"
else
  fail "U039" "notify.sh resolver returned zero when CFBundleIdentifier is missing"
fi

case_start "U053" "notify.sh exports CLAUDE_NOTIFY_GENERATION env var to the binary"
TMP_DIR=$(make_case_tmp_dir "U053")
ENV_LOG="$TMP_DIR/env.log"
FAKE_BIN="$TMP_DIR/fake-notify"
# The fake binary captures CLAUDE_NOTIFY_GENERATION to ENV_LOG.
# ENV_LOG path is embedded at write time (unquoted heredoc).
cat > "$FAKE_BIN" <<FAKE_BIN_U053
#!/bin/sh
env | grep '^CLAUDE_NOTIFY_GENERATION=' > "$ENV_LOG"
FAKE_BIN_U053
chmod +x "$FAKE_BIN"
NOTIFY_BIN="$FAKE_BIN" \
  NOTIFY_SENDER_MODE=off NOTIFY_STDIN_TIMEOUT_MS=0 \
  NOTIFY_TMUX_CMD_TIMEOUT_MS=0 NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS=0 \
  "$SCRIPT" "generation env test" </dev/null 2>/dev/null
rc=$?
assert_rc_eq "U053" "$rc" 0 \
  "notify.sh generation env probe exits 0" \
  "notify.sh generation env probe exited $rc"
# Wait briefly for background binary to write the env log.
U053_FOUND=0
for _i in $(seq 1 20); do
  if [ -s "$ENV_LOG" ]; then
    U053_FOUND=1
    break
  fi
  sleep 0.1
done
if [ "$U053_FOUND" -eq 1 ] && grep -q '^CLAUDE_NOTIFY_GENERATION=' "$ENV_LOG"; then
  GEN_VALUE=$(sed 's/^CLAUDE_NOTIFY_GENERATION=//' "$ENV_LOG")
  if [ -n "$GEN_VALUE" ]; then
    pass "U053" "notify.sh exports non-empty CLAUDE_NOTIFY_GENERATION=$GEN_VALUE"
  else
    fail "U053" "notify.sh exports empty CLAUDE_NOTIFY_GENERATION"
  fi
else
  fail "U053" "notify.sh did not export CLAUDE_NOTIFY_GENERATION to binary"
fi

case_start "U054" "notify.sh defines launch_notify helper function"
assert_file_contains "U054" "$SCRIPT" 'launch_notify()' \
  "notify.sh defines launch_notify function" \
  "notify.sh missing launch_notify function"

finish
