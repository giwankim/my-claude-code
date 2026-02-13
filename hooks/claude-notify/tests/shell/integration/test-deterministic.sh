#!/bin/sh

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=hooks/claude-notify/tests/shell/lib/testlib.sh
. "$PROJECT_DIR/tests/shell/lib/testlib.sh"

NOTIFY="$PROJECT_DIR/claude-notify.app/Contents/MacOS/claude-notify"
SCRIPT="$PROJECT_DIR/notify.sh"
PID_FILE="/tmp/claude-notify.pid.$$"
RELAUNCH_MARKER="/tmp/claude-notify-relaunch-marker.$$"
TEST_TMP_DIRS=""
EXPECTED_NOTIFY_NAME=$(basename "$NOTIFY")
export CLAUDE_NOTIFY_PID_FILE="$PID_FILE"

register_tmp_dir() {
  dir="$1"
  TEST_TMP_DIRS="$TEST_TMP_DIRS $dir"
}

write_fake_notify() {
  script_path="$1"
  cat > "$script_path" <<'FAKE_NOTIFY_SCRIPT'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$NOTIFY_ARGS_LOG"
  i=$((i + 1))
done
if [ -n "${NOTIFY_ENV_LOG:-}" ]; then
  printf '%s\n' "${CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY:-}" > "$NOTIFY_ENV_LOG"
fi
exit 0
FAKE_NOTIFY_SCRIPT
  chmod +x "$script_path"
}

is_expected_notify_pid() {
  pid="$1"
  case "$pid" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  [ "$pid" -gt 0 ] 2>/dev/null || return 1
  kill -0 "$pid" 2>/dev/null || return 1
  proc=$(ps -p "$pid" -o comm= 2>/dev/null | awk 'NR==1 {print $1}')
  [ "$proc" = "$EXPECTED_NOTIFY_NAME" ]
}

kill_pid_from_file() {
  pid_file="$1"
  [ -f "$pid_file" ] || return 1
  pid=$(cat "$pid_file" 2>/dev/null)
  is_expected_notify_pid "$pid" || return 1
  kill "$pid" 2>/dev/null
}

drain_pid_file_if_present() {
  pid_file="$1"
  max_tries="${2:-20}"
  if wait_for_pid_file "$pid_file" "$max_tries"; then
    kill_pid_from_file "$pid_file" >/dev/null 2>&1 || true
    wait_for_pid_removed "$pid_file" "$max_tries" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  kill_pid_from_file "$PID_FILE" >/dev/null 2>&1 || true
  rm -f "$PID_FILE" "$RELAUNCH_MARKER"
  for dir in $TEST_TMP_DIRS; do
    rm -rf "$dir"
  done
}
trap cleanup EXIT

case_start "I101" "Binary exists"
if [ -x "$NOTIFY" ]; then
  pass "I101" "binary is executable"
else
  fail "I101" "binary not found or not executable at $NOTIFY"
fi

case_start "I102" "-help exits 0 and prints usage"
err=$("$NOTIFY" -help 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I102" "-help exits 0"
else
  fail "I102" "-help exited $rc (expected 0)"
fi
if echo "$err" | grep -q "Usage:"; then
  pass "I102" "-help prints usage"
else
  fail "I102" "-help did not print usage"
fi

case_start "I103" "Missing -message exits 1"
"$NOTIFY" -title "test" 2>/dev/null
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "I103" "missing -message exits 1"
else
  fail "I103" "missing -message exited $rc (expected 1)"
fi

case_start "I104" "Missing flag value exits 1"
"$NOTIFY" -title 2>/dev/null
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "I104" "missing flag value exits 1"
else
  fail "I104" "missing flag value exited $rc (expected 1)"
fi

case_start "I105" "Unknown flag exits 1"
"$NOTIFY" -bogus 2>/dev/null
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "I105" "unknown flag exits 1"
else
  fail "I105" "unknown flag exited $rc (expected 1)"
fi

case_start "I106" "Invalid sender mode exits 1"
"$NOTIFY" -message "sender-mode-invalid" -sender-mode "bogus" 2>/dev/null
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "I106" "invalid sender mode exits 1"
else
  fail "I106" "invalid sender mode exited $rc (expected 1)"
fi

case_start "I107" "Required sender with missing bundle fails"
err=$("$NOTIFY" -message "sender-required-invalid" -sender-mode required -sender-bundle-id "com.example.__missing_sender__" -timeout 1 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "I107" "required sender mode fails when sender app missing"
else
  fail "I107" "required sender mode exited $rc (expected 1)"
fi
if echo "$err" | grep -q "sender spoof unavailable"; then
  pass "I107" "required sender mode prints spoof failure"
else
  fail "I107" "required sender mode did not print spoof failure"
fi

case_start "I108" "Auto sender missing bundle falls back"
err=$("$NOTIFY" -message "sender-auto-fallback" -sender-mode auto -sender-bundle-id "com.example.__missing_sender__" -timeout 1 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I108" "auto sender mode falls back and exits 0"
else
  fail "I108" "auto sender mode exited $rc (expected 0)"
fi
if echo "$err" | grep -q "sender spoof unavailable"; then
  pass "I108" "auto sender mode warns on spoof failure"
else
  fail "I108" "auto sender mode did not warn on spoof failure"
fi

case_start "I109" "Off sender mode ignores missing bundle"
"$NOTIFY" -message "sender-off" -sender-mode off -sender-bundle-id "com.example.__missing_sender__" -timeout 1 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I109" "sender mode off ignores spoof settings"
else
  fail "I109" "sender mode off exited $rc (expected 0)"
fi

case_start "I110" "notify.sh sender env override"
if [ -x "$SCRIPT" ] || [ -f "$SCRIPT" ]; then
  NOTIFY_SENDER_MODE=off NOTIFY_SENDER_BUNDLE_ID="com.example.__missing_sender__" "$SCRIPT" "notify.sh sender override test" 2>/dev/null
  rc=$?
  drain_pid_file_if_present "$PID_FILE" 20
  if [ "$rc" -eq 0 ]; then
    pass "I110" "notify.sh accepts sender env overrides"
  else
    fail "I110" "notify.sh sender override exited $rc"
  fi
else
  fail "I110" "notify.sh not found for sender override test"
fi

case_start "I111" "Required invalid sender app path fails"
err=$("$NOTIFY" -message "sender-required-bad-path" -sender-mode required -sender-app-path "/tmp/does-not-exist-sender.app" -timeout 1 2>&1 >/dev/null)
rc=$?
if [ "$rc" -eq 1 ]; then
  pass "I111" "required invalid sender app path exits 1"
else
  fail "I111" "required invalid sender app path exited $rc (expected 1)"
fi
if echo "$err" | grep -q "sender app path is not a valid app bundle"; then
  pass "I111" "required invalid sender app path prints validation error"
else
  fail "I111" "required invalid sender app path missing validation error"
fi

case_start "I112" "Off mode ignores invalid sender app path"
"$NOTIFY" -message "sender-off-bad-path" -sender-mode off -sender-app-path "/tmp/does-not-exist-sender.app" -timeout 1 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I112" "off mode ignores invalid sender app path"
else
  fail "I112" "off mode invalid sender app path exited $rc (expected 0)"
fi

case_start "I113" "Spoof relaunch path uses app launch"
MARKER="$RELAUNCH_MARKER"
rm -f "$MARKER"
SELF_APP="$PROJECT_DIR/claude-notify.app"
CLAUDE_NOTIFY_TEST_SKIP_RELAUNCH=1 CLAUDE_NOTIFY_TEST_RELAUNCH_MARKER="$MARKER" \
  "$NOTIFY" -message "sender-relaunch-marker" -sender-mode auto -sender-app-path "$SELF_APP" -timeout 1 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I113" "spoof relaunch probe exits 0"
else
  fail "I113" "spoof relaunch probe exited $rc"
fi
if [ -f "$MARKER" ] && grep -q '^open .*\.app$' "$MARKER"; then
  pass "I113" "spoof relaunch uses app open path"
else
  fail "I113" "spoof relaunch did not record app open path"
fi
rm -f "$MARKER"

case_start "I114" "Spoof helper uses isolated signing identifier"
SPOOF_ID="com.example.notifyspoof.test"
SELF_APP="$PROJECT_DIR/claude-notify.app"
CLAUDE_NOTIFY_TEST_SKIP_RELAUNCH=1 \
  CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID=1 \
  "$NOTIFY" -message "sender-signing-id" -sender-mode auto -sender-bundle-id "$SPOOF_ID" -sender-app-path "$SELF_APP" -timeout 1 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I114" "spoof helper prep for signing probe exits 0"
else
  fail "I114" "spoof helper prep for signing probe exited $rc"
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
BASE_BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PROJECT_DIR/claude-notify.app/Contents/Info.plist" 2>/dev/null)
EXPECTED_PREFIX="${BASE_BUNDLE_ID:-com.gwk.claude-notify}.spoof."
if [ -n "$HELPER_APP" ]; then
  HELPER_IDENTIFIER=$(codesign -dv "$HELPER_APP" 2>&1 | sed -n 's/^Identifier=//p' | head -n 1)
else
  HELPER_IDENTIFIER=""
fi
case "$HELPER_IDENTIFIER" in
  "$EXPECTED_PREFIX"*)
    if [ "$HELPER_IDENTIFIER" = "$SPOOF_ID" ]; then
      fail "I114" "spoof helper identifier unexpectedly reuses sender bundle id"
    else
      pass "I114" "spoof helper code signing identifier is isolated from sender bundle id"
    fi
    ;;
  *)
    if [ -z "$HELPER_APP" ]; then
      fail "I114" "spoof helper app not found at $HELPER_HOME or $HELPER_TMP"
    else
      fail "I114" "spoof helper code signing identifier '${HELPER_IDENTIFIER}' does not match expected prefix '${EXPECTED_PREFIX}'"
    fi
    ;;
esac

case_start "I115" "Auto isolated spoof strict fallback avoids non-isolated retry"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID=1 \
  "$NOTIFY" -message "sender-auto-isolated-strict" -sender-mode auto -spoofed-run -origin-exec "$NOTIFY" -timeout 2 2>&1 >/dev/null)
rc=$?
drain_pid_file_if_present "$PID_FILE" 20
if [ "$rc" -eq 0 ]; then
  pass "I115" "auto isolated spoof strict fallback exits 0"
else
  fail "I115" "auto isolated spoof strict fallback exited $rc (expected 0)"
fi
if echo "$err" | grep -q "launched fallback notification without spoof"; then
  pass "I115" "auto isolated spoof strict fallback launches non-spoof fallback"
else
  fail "I115" "auto isolated spoof strict fallback did not launch non-spoof fallback"
fi
if echo "$err" | grep -q "retrying without isolated helper bundle id"; then
  fail "I115" "auto isolated spoof strict fallback unexpectedly retried non-isolated helper"
else
  pass "I115" "auto isolated spoof strict fallback avoids non-isolated retry by default"
fi

case_start "I116" "Auto isolated spoof opt-in retry enables non-isolated retry"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID=1 CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY=1 \
  "$NOTIFY" -message "sender-auto-isolated-retry" -sender-mode auto -spoofed-run -origin-exec "$NOTIFY" -timeout 2 2>&1 >/dev/null)
rc=$?
drain_pid_file_if_present "$PID_FILE" 20
if [ "$rc" -eq 0 ]; then
  pass "I116" "auto isolated spoof opt-in retry exits 0"
else
  fail "I116" "auto isolated spoof opt-in retry exited $rc (expected 0)"
fi
if echo "$err" | grep -q "retrying without isolated helper bundle id"; then
  pass "I116" "auto isolated spoof opt-in retry uses non-isolated helper retry"
else
  fail "I116" "auto isolated spoof opt-in retry did not use non-isolated helper retry"
fi

case_start "I117" "notify.sh tmux binary override"
TMP_DIR="/tmp/claude-notify-test.$$"
register_tmp_dir "$TMP_DIR"
mkdir -p "$TMP_DIR"
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
TMUX_LOG="$TMP_DIR/tmux-calls.log"
write_fake_notify "$FAKE_NOTIFY"
cat > "$FAKE_TMUX" <<'CASE_I117_TMUX'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_CALL_LOG"
if [ "$1" = "display-message" ]; then
  printf '%s\n' "sess|1|win|/dev/pts/fake"
  exit 0
fi
exit 0
CASE_I117_TMUX
chmod +x "$FAKE_TMUX"
TMUX="/tmp/fake-socket,123,0" TMUX_PANE="%9" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" TMUX_CALL_LOG="$TMUX_LOG" NOTIFY_SENDER_MODE=off "$SCRIPT" "tmux override test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
if [ "$rc" -eq 0 ]; then
  pass "I117" "notify.sh tmux override exits 0"
else
  fail "I117" "notify.sh tmux override exited $rc"
fi
if grep -q "^display-message -t %9 -p " "$TMUX_LOG"; then
  pass "I117" "notify.sh used NOTIFY_TMUX_BIN for tmux metadata lookup"
else
  fail "I117" "notify.sh did not use NOTIFY_TMUX_BIN for tmux metadata lookup"
fi
if grep -q "switch-client -c '/dev/pts/fake' -t '%9'" "$ARGS_LOG"; then
  pass "I117" "notify.sh execute payload references overridden tmux binary context"
else
  fail "I117" "notify.sh execute payload missing overridden tmux context"
fi
rm -rf "$TMP_DIR"

case_start "I118" "notify.sh tmux metadata failure omits execute action"
TMP_DIR="/tmp/claude-notify-test-fail.$$"
register_tmp_dir "$TMP_DIR"
mkdir -p "$TMP_DIR"
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
TMUX_LOG="$TMP_DIR/tmux-calls.log"
write_fake_notify "$FAKE_NOTIFY"
cat > "$FAKE_TMUX" <<'CASE_I118_TMUX'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_CALL_LOG"
exit 1
CASE_I118_TMUX
chmod +x "$FAKE_TMUX"
err=$(TMUX="/tmp/fake-socket,999,0" TMUX_PANE="%7" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" TMUX_CALL_LOG="$TMUX_LOG" NOTIFY_SENDER_MODE=off "$SCRIPT" "tmux failure test" 2>&1 >/dev/null)
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
if [ "$rc" -eq 0 ]; then
  pass "I118" "notify.sh tmux metadata failure exits 0"
else
  fail "I118" "notify.sh tmux metadata failure exited $rc"
fi
if echo "$err" | grep -q "unable to read tmux context"; then
  pass "I118" "notify.sh tmux metadata failure emits warning"
else
  fail "I118" "notify.sh tmux metadata failure did not emit warning"
fi
if grep -q -- "-execute" "$ARGS_LOG"; then
  fail "I118" "notify.sh tmux metadata failure unexpectedly included execute action"
else
  pass "I118" "notify.sh tmux metadata failure omits execute action"
fi
rm -rf "$TMP_DIR"

case_start "I119" "notify.sh default sender mode is off"
TMP_DIR="/tmp/claude-notify-test-default-mode.$$"
register_tmp_dir "$TMP_DIR"
mkdir -p "$TMP_DIR"
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
write_fake_notify "$FAKE_NOTIFY"
TMUX="" NOTIFY_SENDER_MODE="" NOTIFY_ALLOW_NONISOLATED_RETRY="" \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" "$SCRIPT" "default sender mode test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
if [ "$rc" -eq 0 ]; then
  pass "I119" "notify.sh default sender mode probe exits 0"
else
  fail "I119" "notify.sh default sender mode probe exited $rc"
fi
if awk '/\]=-sender-mode$/{getline; if ($0 ~ /\]=off$/) found=1} END{exit found?0:1}' "$ARGS_LOG"; then
  pass "I119" "notify.sh forwards -sender-mode off by default"
else
  fail "I119" "notify.sh did not forward default -sender-mode off"
fi
rm -rf "$TMP_DIR"

case_start "I120" "notify.sh sender mode env override auto"
TMP_DIR="/tmp/claude-notify-test-auto-mode.$$"
register_tmp_dir "$TMP_DIR"
mkdir -p "$TMP_DIR"
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
write_fake_notify "$FAKE_NOTIFY"
TMUX="" NOTIFY_SENDER_MODE=auto NOTIFY_ALLOW_NONISOLATED_RETRY="" \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" "$SCRIPT" "sender mode auto override test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
if [ "$rc" -eq 0 ]; then
  pass "I120" "notify.sh sender mode auto override probe exits 0"
else
  fail "I120" "notify.sh sender mode auto override probe exited $rc"
fi
if awk '/\]=-sender-mode$/{getline; if ($0 ~ /\]=auto$/) found=1} END{exit found?0:1}' "$ARGS_LOG"; then
  pass "I120" "notify.sh forwards -sender-mode auto when overridden"
else
  fail "I120" "notify.sh did not forward overridden -sender-mode auto"
fi
rm -rf "$TMP_DIR"

case_start "I121" "notify.sh default non-isolated retry env is 0"
TMP_DIR="/tmp/claude-notify-test-default-retry.$$"
register_tmp_dir "$TMP_DIR"
mkdir -p "$TMP_DIR"
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
ENV_LOG="$TMP_DIR/notify-env.log"
write_fake_notify "$FAKE_NOTIFY"
TMUX="" NOTIFY_SENDER_MODE="" NOTIFY_ALLOW_NONISOLATED_RETRY="" \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" NOTIFY_ENV_LOG="$ENV_LOG" "$SCRIPT" "default retry env test" 2>/dev/null
rc=$?
wait_for_file "$ENV_LOG" 20 >/dev/null 2>&1
if [ "$rc" -eq 0 ]; then
  pass "I121" "notify.sh default retry env probe exits 0"
else
  fail "I121" "notify.sh default retry env probe exited $rc"
fi
if [ -f "$ENV_LOG" ] && grep -qx "0" "$ENV_LOG"; then
  pass "I121" "notify.sh exports CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY=0 by default"
else
  fail "I121" "notify.sh did not export default CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY=0"
fi
rm -rf "$TMP_DIR"

finish
