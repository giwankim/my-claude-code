#!/bin/sh

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=hooks/claude-notify/Tests/shell/lib/testlib.sh
. "$PROJECT_DIR/Tests/shell/lib/testlib.sh"
# shellcheck source=hooks/claude-notify/Tests/shell/lib/notify-test-helpers.sh
. "$PROJECT_DIR/Tests/shell/lib/notify-test-helpers.sh"

NOTIFY="$PROJECT_DIR/claude-notify.app/Contents/MacOS/claude-notify"
SCRIPT="$PROJECT_DIR/notify.sh"
PID_FILE="/tmp/claude-notify.pid.$$"
RELAUNCH_MARKER="/tmp/claude-notify-relaunch-marker.$$"
TEST_TMP_DIRS=""
EXPECTED_NOTIFY_NAME=$(basename "$NOTIFY")
export CLAUDE_NOTIFY_PID_FILE="$PID_FILE"

drain_notify_pid_file() {
  max_tries="${1:-20}"
  drain_pid_file_if_present "$PID_FILE" "$max_tries" "$EXPECTED_NOTIFY_NAME"
}

cleanup() {
  kill_pid_from_file "$PID_FILE" "$EXPECTED_NOTIFY_NAME" >/dev/null 2>&1 || true
  rm -f "$PID_FILE" "$RELAUNCH_MARKER"
  cleanup_registered_tmp_dirs
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
err=$(CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$NOTIFY" -message "sender-auto-fallback" -sender-mode auto -sender-bundle-id "com.example.__missing_sender__" -timeout 1 2>&1 >/dev/null)
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
CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$NOTIFY" -message "sender-off" -sender-mode off -sender-bundle-id "com.example.__missing_sender__" -timeout 1 2>/dev/null
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
  drain_notify_pid_file 20
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
CLAUDE_NOTIFY_TEST_SKIP_DELIVERY=1 "$NOTIFY" -message "sender-off-bad-path" -sender-mode off -sender-app-path "/tmp/does-not-exist-sender.app" -timeout 1 2>/dev/null
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
TMP_DIR=$(make_case_tmp_dir "I115")
FAKE_ORIGIN="$TMP_DIR/fake-origin.sh"
ORIGIN_ARGS_LOG="$TMP_DIR/origin-args.log"
ORIGIN_ISOLATE_LOG="$TMP_DIR/origin-isolate.log"
ORIGIN_ALLOW_RETRY_LOG="$TMP_DIR/origin-allow-retry.log"
write_fake_origin_exec "$FAKE_ORIGIN"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID=1 \
  ORIGIN_ARGS_LOG="$ORIGIN_ARGS_LOG" ORIGIN_ISOLATE_LOG="$ORIGIN_ISOLATE_LOG" ORIGIN_ALLOW_RETRY_LOG="$ORIGIN_ALLOW_RETRY_LOG" \
  "$NOTIFY" -message "sender-auto-isolated-strict" -sender-mode auto -spoofed-run -origin-exec "$FAKE_ORIGIN" -timeout 2 2>&1 >/dev/null)
rc=$?
drain_notify_pid_file 20
if [ "$rc" -eq 0 ]; then
  pass "I115" "auto isolated spoof strict fallback exits 0"
else
  fail "I115" "auto isolated spoof strict fallback exited $rc (expected 0)"
fi
if wait_for_file "$ORIGIN_ARGS_LOG" 20 >/dev/null 2>&1; then
  if awk '/\]=-sender-mode$/{getline; if ($0 ~ /\]=off$/) found=1} END{exit found?0:1}' "$ORIGIN_ARGS_LOG"; then
    pass "I115" "auto isolated spoof strict fallback launches non-spoof fallback"
  else
    fail "I115" "auto isolated spoof strict fallback did not force sender-mode off"
  fi
else
  fail "I115" "auto isolated spoof strict fallback did not execute origin command"
fi
if grep -q -- '\]=-fallback-run$' "$ORIGIN_ARGS_LOG"; then
  pass "I115" "auto isolated spoof strict fallback marks fallback-run"
else
  fail "I115" "auto isolated spoof strict fallback missing fallback-run marker"
fi
if [ -f "$ORIGIN_ISOLATE_LOG" ] && grep -qx "0" "$ORIGIN_ISOLATE_LOG"; then
  fail "I115" "auto isolated spoof strict fallback unexpectedly retried non-isolated helper"
else
  pass "I115" "auto isolated spoof strict fallback avoids non-isolated retry by default"
fi
if ! echo "$err" | grep -q "launched fallback notification without spoof"; then
  printf '%s\n' "I115 diagnostic: fallback warning text missing (non-fatal)" >&2
fi

case_start "I116" "Auto isolated spoof opt-in retry enables non-isolated retry"
TMP_DIR=$(make_case_tmp_dir "I116")
FAKE_ORIGIN="$TMP_DIR/fake-origin.sh"
ORIGIN_ARGS_LOG="$TMP_DIR/origin-args.log"
ORIGIN_ISOLATE_LOG="$TMP_DIR/origin-isolate.log"
ORIGIN_ALLOW_RETRY_LOG="$TMP_DIR/origin-allow-retry.log"
write_fake_origin_exec "$FAKE_ORIGIN"
err=$(CLAUDE_NOTIFY_TEST_FORCE_POST_ERROR=1 CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID=1 CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY=1 NOTIFY_ALLOW_NONISOLATED_RETRY=1 \
  ORIGIN_ARGS_LOG="$ORIGIN_ARGS_LOG" ORIGIN_ISOLATE_LOG="$ORIGIN_ISOLATE_LOG" ORIGIN_ALLOW_RETRY_LOG="$ORIGIN_ALLOW_RETRY_LOG" \
  "$NOTIFY" -message "sender-auto-isolated-retry" -sender-mode auto -spoofed-run -origin-exec "$FAKE_ORIGIN" -timeout 2 2>&1 >/dev/null)
rc=$?
drain_notify_pid_file 20
if [ "$rc" -eq 0 ]; then
  pass "I116" "auto isolated spoof opt-in retry exits 0"
else
  fail "I116" "auto isolated spoof opt-in retry exited $rc (expected 0)"
fi
if wait_for_file "$ORIGIN_ARGS_LOG" 20 >/dev/null 2>&1; then
  pass "I116" "auto isolated spoof opt-in retry executed origin command"
else
  fail "I116" "auto isolated spoof opt-in retry did not execute origin command"
fi
if grep -q -- '\]=-fallback-run$' "$ORIGIN_ARGS_LOG"; then
  fail "I116" "auto isolated spoof opt-in retry unexpectedly launched fallback-run"
else
  pass "I116" "auto isolated spoof opt-in retry avoids fallback-run path"
fi
if awk '/\]=-sender-mode$/{getline; if ($0 ~ /\]=off$/) found=1} END{exit found?0:1}' "$ORIGIN_ARGS_LOG"; then
  fail "I116" "auto isolated spoof opt-in retry unexpectedly forced sender-mode off"
else
  pass "I116" "auto isolated spoof opt-in retry preserves spoof sender mode"
fi
if grep -q -- '\]=-origin-exec$' "$ORIGIN_ARGS_LOG"; then
  fail "I116" "auto isolated spoof opt-in retry unexpectedly retained origin-exec argument"
else
  pass "I116" "auto isolated spoof opt-in retry strips origin-exec argument"
fi
if [ -f "$ORIGIN_ISOLATE_LOG" ] && grep -qx "0" "$ORIGIN_ISOLATE_LOG"; then
  pass "I116" "auto isolated spoof opt-in retry uses non-isolated helper retry"
else
  fail "I116" "auto isolated spoof opt-in retry did not disable helper isolation on retry"
fi
if [ -f "$ORIGIN_ALLOW_RETRY_LOG" ] && grep -qx "1" "$ORIGIN_ALLOW_RETRY_LOG"; then
  pass "I116" "auto isolated spoof opt-in retry forwards allow-retry env"
else
  fail "I116" "auto isolated spoof opt-in retry did not forward allow-retry env"
fi
if ! echo "$err" | grep -q "retrying without isolated helper bundle id"; then
  printf '%s\n' "I116 diagnostic: retry warning text missing (non-fatal)" >&2
fi

case_start "I117" "notify.sh tmux binary override"
TMP_DIR=$(make_case_tmp_dir "I117")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
FAKE_REDIRECT="$TMP_DIR/fake-tmux-redirect.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
TMUX_LOG="$TMP_DIR/tmux-calls.log"
REDIRECT_ARGS_LOG="$TMP_DIR/redirect-args.log"
write_fake_notify "$FAKE_NOTIFY"
cat > "$FAKE_TMUX" <<'CASE_I117_TMUX'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_CALL_LOG"
if [ "$1" = "display-message" ]; then
  printf '%s\n' "sess'one|1|win|3|%9|client'name|/dev/tty's001"
  exit 0
fi
exit 0
CASE_I117_TMUX
cat > "$FAKE_REDIRECT" <<'CASE_I117_REDIRECT'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$REDIRECT_ARGS_LOG"
  i=$((i + 1))
done
exit 0
CASE_I117_REDIRECT
chmod +x "$FAKE_TMUX" "$FAKE_REDIRECT"
TMUX="/tmp/fake-socket,123,0" TMUX_PANE="%9" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" NOTIFY_TMUX_REDIRECT_SCRIPT="$FAKE_REDIRECT" TMUX_CALL_LOG="$TMUX_LOG" \
  NOTIFY_SENDER_MODE=off NOTIFY_ACTIVATE_BUNDLE_ID="com.example.term" "$SCRIPT" "tmux override test" 2>/dev/null
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
EXECUTE_PAYLOAD=$(extract_execute_payload "$ARGS_LOG")
if [ -n "$EXECUTE_PAYLOAD" ]; then
  pass "I117" "notify.sh captured execute payload"
else
  fail "I117" "notify.sh did not include execute payload"
fi
if printf '%s\n' "$EXECUTE_PAYLOAD" | grep -Fq "$FAKE_REDIRECT" \
  && printf '%s\n' "$EXECUTE_PAYLOAD" | grep -Fq "$FAKE_TMUX" \
  && printf '%s\n' "$EXECUTE_PAYLOAD" | grep -Fq "/tmp/fake-socket" \
  && printf '%s\n' "$EXECUTE_PAYLOAD" | grep -Fq "%9"; then
  pass "I117" "notify.sh execute payload includes redirect command components"
else
  fail "I117" "notify.sh execute payload missing expected redirect command components"
fi
REDIRECT_ARGS_LOG="$REDIRECT_ARGS_LOG" /bin/sh -c "$EXECUTE_PAYLOAD"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I117" "execute payload runs successfully with embedded single quotes"
else
  fail "I117" "execute payload failed with embedded single quotes (rc=$rc)"
fi
if grep -Fq "[0]=$FAKE_TMUX" "$REDIRECT_ARGS_LOG" \
  && grep -Fq "[1]=/tmp/fake-socket" "$REDIRECT_ARGS_LOG" \
  && grep -Fq "[2]=%9" "$REDIRECT_ARGS_LOG" \
  && grep -Fq "[3]=sess'one:1.3" "$REDIRECT_ARGS_LOG" \
  && grep -Fq "[4]=client'name" "$REDIRECT_ARGS_LOG" \
  && grep -Fq "[5]=/dev/tty's001" "$REDIRECT_ARGS_LOG" \
  && grep -Fq "[6]=com.example.term" "$REDIRECT_ARGS_LOG"; then
  pass "I117" "quoted execute payload preserves tmux metadata values"
else
  fail "I117" "quoted execute payload did not preserve expected tmux metadata values"
fi

case_start "I118" "notify.sh tmux metadata failure omits execute action"
TMP_DIR=$(make_case_tmp_dir "I118")
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

case_start "I119" "notify.sh default sender mode is auto"
TMP_DIR=$(make_case_tmp_dir "I119")
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
if awk '/\]=-sender-mode$/{getline; if ($0 ~ /\]=auto$/) found=1} END{exit found?0:1}' "$ARGS_LOG"; then
  pass "I119" "notify.sh forwards -sender-mode auto by default"
else
  fail "I119" "notify.sh did not forward default -sender-mode auto"
fi

case_start "I120" "notify.sh sender mode env override auto"
TMP_DIR=$(make_case_tmp_dir "I120")
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

case_start "I121" "notify.sh default non-isolated retry env is 0"
TMP_DIR=$(make_case_tmp_dir "I121")
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

case_start "I122" "Authorization failure falls back to AppleScript delivery"
TMP_DIR=$(make_case_tmp_dir "I122")
FAKE_OSASCRIPT="$TMP_DIR/fake-osascript.sh"
OSASCRIPT_LOG="$TMP_DIR/osascript-args.log"
write_fake_osascript_success "$FAKE_OSASCRIPT"
err=$(CLAUDE_NOTIFY_TEST_FORCE_AUTH_DENIED=1 CLAUDE_NOTIFY_OSASCRIPT_BIN="$FAKE_OSASCRIPT" OSASCRIPT_ARGS_LOG="$OSASCRIPT_LOG" \
  "$NOTIFY" -title "fallback-title" -subtitle "fallback-subtitle" -message "fallback-message" -timeout 5 2>&1 >/dev/null)
rc=$?
drain_notify_pid_file 20
if [ "$rc" -eq 0 ]; then
  pass "I122" "authorization failure fallback exits 0"
else
  fail "I122" "authorization failure fallback exited $rc"
fi
if wait_for_file "$OSASCRIPT_LOG" 20 >/dev/null 2>&1; then
  pass "I122" "authorization failure fallback invoked osascript"
else
  fail "I122" "authorization failure fallback did not invoke osascript"
fi
if grep -q '\[3\]=fallback-message' "$OSASCRIPT_LOG" && grep -q '\[4\]=fallback-title' "$OSASCRIPT_LOG"; then
  pass "I122" "authorization failure fallback forwarded notification payload"
else
  fail "I122" "authorization failure fallback missing forwarded payload"
fi
if echo "$err" | grep -q "posted notification via AppleScript fallback"; then
  pass "I122" "authorization failure fallback emits fallback warning"
else
  fail "I122" "authorization failure fallback missing fallback warning"
fi
FAILING_OSASCRIPT="$TMP_DIR/failing-osascript.sh"
OSASCRIPT_FAIL_LOG="$TMP_DIR/osascript-fail-args.log"
write_failing_osascript "$FAILING_OSASCRIPT"
err_fail=$(CLAUDE_NOTIFY_TEST_FORCE_AUTH_DENIED=1 CLAUDE_NOTIFY_OSASCRIPT_BIN="$FAILING_OSASCRIPT" OSASCRIPT_ARGS_LOG="$OSASCRIPT_FAIL_LOG" \
  "$NOTIFY" -title "fallback-fail-title" -subtitle "fallback-fail-subtitle" -message "fallback-fail-message" -timeout 10 2>&1 >/dev/null)
rc_fail=$?
drain_notify_pid_file 20
if [ "$rc_fail" -eq 1 ]; then
  pass "I122" "authorization failure exits 1 when AppleScript fallback fails"
else
  fail "I122" "authorization failure fallback-fail path exited $rc_fail (expected 1)"
fi
if wait_for_file "$OSASCRIPT_FAIL_LOG" 20 >/dev/null 2>&1; then
  pass "I122" "fallback-fail path invoked osascript"
else
  fail "I122" "fallback-fail path did not invoke osascript"
fi
if echo "$err_fail" | grep -q "AppleScript fallback exited 1"; then
  pass "I122" "fallback-fail path surfaces AppleScript failure warning"
else
  fail "I122" "fallback-fail path missing AppleScript failure warning"
fi

case_start "I123" "notify.sh forwards explicit activate bundle override"
TMP_DIR=$(make_case_tmp_dir "I123")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
write_fake_notify "$FAKE_NOTIFY"
TMUX="" TERM_PROGRAM="" NOTIFY_ACTIVATE_BUNDLE_ID="com.googlecode.iterm2" \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" "$SCRIPT" "activate explicit test" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I123" "notify.sh explicit activate probe exits 0"
else
  fail "I123" "notify.sh explicit activate probe exited $rc"
fi
_i=0
while [ "$_i" -lt 20 ] && ! awk '/\]=-activate$/{ if (getline nextline > 0 && nextline ~ /\]=com.googlecode.iterm2$/) found=1 } END{exit found?0:1}' "$ARGS_LOG" 2>/dev/null; do
  sleep 0.1
  _i=$((_i + 1))
done
if awk '/\]=-activate$/{ if (getline nextline > 0 && nextline ~ /\]=com.googlecode.iterm2$/) found=1 } END{exit found?0:1}' "$ARGS_LOG" 2>/dev/null; then
  pass "I123" "notify.sh forwards explicit activate bundle id"
else
  fail "I123" "notify.sh did not forward explicit activate bundle id"
fi

case_start "I124" "notify.sh infers activate bundle outside tmux when explicit override is unavailable"
TMP_DIR=$(make_case_tmp_dir "I124")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_ACTIVATE_OSASCRIPT="$TMP_DIR/fake-activate-osascript.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
ACTIVATE_OSASCRIPT_ARGS_LOG="$TMP_DIR/activate-osascript-args.log"
write_fake_notify "$FAKE_NOTIFY"
write_fake_frontmost_osascript "$FAKE_ACTIVATE_OSASCRIPT"
TMUX="" TERM_PROGRAM="JetBrains-JediTerm" NOTIFY_ACTIVATE_BUNDLE_ID="" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_ACTIVATE_OSASCRIPT" ACTIVATE_OSASCRIPT_ARGS_LOG="$ACTIVATE_OSASCRIPT_ARGS_LOG" \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" "$SCRIPT" "activate inference outside tmux test" 2>/dev/null
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I124" "notify.sh activate inference probe exits 0"
else
  fail "I124" "notify.sh activate inference probe exited $rc"
fi
_i=0
while [ "$_i" -lt 20 ] && ! awk '/\]=-activate$/{ if (getline nextline > 0 && nextline ~ /\]=com.jetbrains.intellij$/) found=1 } END{exit found?0:1}' "$ARGS_LOG" 2>/dev/null; do
  sleep 0.1
  _i=$((_i + 1))
done
if awk '/\]=-activate$/{ if (getline nextline > 0 && nextline ~ /\]=com.jetbrains.intellij$/) found=1 } END{exit found?0:1}' "$ARGS_LOG" 2>/dev/null; then
  pass "I124" "notify.sh forwards inferred activate bundle id outside tmux"
else
  fail "I124" "notify.sh did not forward inferred activate bundle id outside tmux"
fi
if grep -q "id of app (path to frontmost application as text)" "$ACTIVATE_OSASCRIPT_ARGS_LOG"; then
  pass "I124" "notify.sh invokes frontmost-app osascript probe outside tmux"
else
  fail "I124" "notify.sh did not invoke frontmost-app osascript probe outside tmux"
fi

case_start "I125" "notify.sh click execute payload redirects to expected tmux pane"
TMP_DIR=$(make_case_tmp_dir "I125")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
TMUX_LOG="$TMP_DIR/tmux-calls.log"
CLICK_TMUX_LOG="$TMP_DIR/tmux-click-calls.log"
write_fake_notify "$FAKE_NOTIFY"
cat > "$FAKE_TMUX" <<'CASE_I125_TMUX'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_CALL_LOG"
if [ "$1" = "display-message" ]; then
  printf '%s\n' "sess|7|win|4|%11|client-redir|/dev/ttys777"
  exit 0
fi
exit 0
CASE_I125_TMUX
chmod +x "$FAKE_TMUX"
TMUX="/tmp/fake-socket,777,0" TMUX_PANE="%11" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" TMUX_CALL_LOG="$TMUX_LOG" NOTIFY_SENDER_MODE=off "$SCRIPT" "tmux click redirect test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
if [ "$rc" -eq 0 ]; then
  pass "I125" "notify.sh tmux click payload probe exits 0"
else
  fail "I125" "notify.sh tmux click payload probe exited $rc"
fi
EXECUTE_PAYLOAD=$(extract_execute_payload "$ARGS_LOG")
if [ -n "$EXECUTE_PAYLOAD" ]; then
  pass "I125" "notify.sh captured execute payload for click redirect"
else
  fail "I125" "notify.sh did not include execute payload for click redirect"
fi
TMUX_CALL_LOG="$CLICK_TMUX_LOG" /bin/sh -c "$EXECUTE_PAYLOAD"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I125" "click execute payload runs successfully"
else
  fail "I125" "click execute payload exited $rc"
fi
if grep -q "switch-client -c client-redir -t %11" "$CLICK_TMUX_LOG" \
  && grep -q "select-pane -t %11" "$CLICK_TMUX_LOG"; then
  pass "I125" "click execute payload redirects via client switch + pane select"
else
  fail "I125" "click execute payload missing expected redirect command sequence"
fi
if grep -q "list-clients" "$CLICK_TMUX_LOG"; then
  fail "I125" "click execute payload unexpectedly fell back to list-clients when primary client target succeeded"
else
  pass "I125" "click execute payload uses primary client metadata before list-clients fallback"
fi
if grep -q "switch-client -c  -t" "$CLICK_TMUX_LOG"; then
  fail "I125" "click execute payload generated empty client target"
else
  pass "I125" "click execute payload uses non-empty client targets"
fi

case_start "I126" "Built app bundle includes configured Claude icon asset"
APP_INFO="$PROJECT_DIR/claude-notify.app/Contents/Info.plist"
APP_ICON="$PROJECT_DIR/claude-notify.app/Contents/Resources/claude-code.icns"
SOURCE_ICON="/Applications/Claude.app/Contents/Resources/electron.icns"
ICON_NAME=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIconFile" "$APP_INFO" 2>/dev/null)
if [ "$ICON_NAME" = "claude-code.icns" ]; then
  pass "I126" "app Info.plist advertises claude-code.icns as bundle icon"
else
  fail "I126" "app Info.plist bundle icon is '${ICON_NAME}' (expected claude-code.icns)"
fi
if [ -s "$APP_ICON" ]; then
  pass "I126" "app bundle includes non-empty claude-code.icns"
else
  fail "I126" "app bundle missing claude-code.icns icon asset"
fi
if [ -f "$SOURCE_ICON" ]; then
  if cmp -s "$SOURCE_ICON" "$APP_ICON"; then
    pass "I126" "bundle icon bytes match source Claude icon"
  else
    fail "I126" "bundle icon differs from source Claude icon"
  fi
else
  pass "I126" "source Claude icon missing; skipped byte-for-byte comparison"
fi

case_start "I127" "notify.sh click execute payload falls back when client-targeted switch fails"
TMP_DIR=$(make_case_tmp_dir "I127")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
TMUX_LOG="$TMP_DIR/tmux-calls.log"
CLICK_TMUX_LOG="$TMP_DIR/tmux-click-calls.log"
write_fake_notify "$FAKE_NOTIFY"
cat > "$FAKE_TMUX" <<'CASE_I127_TMUX'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_CALL_LOG"
if [ "$1" = "display-message" ]; then
  printf '%s\n' "sess|8|win|5|%12|client-primary|/dev/ttys998"
  exit 0
fi
if [ "$1" = "list-clients" ] || { [ "$1" = "-S" ] && [ "$3" = "list-clients" ]; }; then
  printf '%s\n' "client-fallback"
  exit 0
fi
case " $* " in
  *" switch-client -c client-primary -t %12 "*)
    exit 1
    ;;
  *" switch-client -c client-primary -t sess:8.5 "*)
    exit 1
    ;;
  *" switch-client -c /dev/ttys998 -t %12 "*)
    exit 1
    ;;
  *" switch-client -c /dev/ttys998 -t sess:8.5 "*)
    exit 1
    ;;
  *" switch-client -c client-fallback -t %12 "*)
    exit 1
    ;;
esac
case " $* " in
  *" switch-client "*)
    exit 0
    ;;
esac
exit 0
CASE_I127_TMUX
chmod +x "$FAKE_TMUX"
TMUX="/tmp/fake-socket,888,0" TMUX_PANE="%12" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  NOTIFY_TMUX_BIN="$FAKE_TMUX" TMUX_CALL_LOG="$TMUX_LOG" NOTIFY_SENDER_MODE=off "$SCRIPT" "tmux click fallback test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
if [ "$rc" -eq 0 ]; then
  pass "I127" "notify.sh tmux fallback payload probe exits 0"
else
  fail "I127" "notify.sh tmux fallback payload probe exited $rc"
fi
EXECUTE_PAYLOAD=$(extract_execute_payload "$ARGS_LOG")
if [ -n "$EXECUTE_PAYLOAD" ]; then
  pass "I127" "notify.sh captured execute payload with fallback"
else
  fail "I127" "notify.sh did not include execute payload with fallback"
fi
TMUX_CALL_LOG="$CLICK_TMUX_LOG" /bin/sh -c "$EXECUTE_PAYLOAD"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I127" "fallback execute payload runs successfully"
else
  fail "I127" "fallback execute payload exited $rc"
fi
if grep -q "switch-client -c client-primary -t %12" "$CLICK_TMUX_LOG" \
  && grep -q "switch-client -c client-primary -t sess:8.5" "$CLICK_TMUX_LOG" \
  && grep -q "switch-client -c /dev/ttys998 -t %12" "$CLICK_TMUX_LOG" \
  && grep -q "switch-client -c /dev/ttys998 -t sess:8.5" "$CLICK_TMUX_LOG" \
  && grep -q "switch-client -c client-fallback -t %12" "$CLICK_TMUX_LOG" \
  && grep -q "switch-client -c client-fallback -t sess:8.5" "$CLICK_TMUX_LOG"; then
  pass "I127" "fallback execute payload attempted primary client metadata before list-clients fallback"
else
  fail "I127" "fallback execute payload missing expected client-targeted fallback attempts"
fi
if grep -q "list-clients -F #{client_name}" "$CLICK_TMUX_LOG" \
  && grep -q "select-pane -t %12" "$CLICK_TMUX_LOG"; then
  pass "I127" "fallback execute payload uses list-clients recovery and final pane select"
else
  fail "I127" "fallback execute payload missing expected recovery steps"
fi

case_start "I128" "notify.sh carries inferred IntelliJ tmux activate bundle in redirect payload without native -activate"
TMP_DIR=$(make_case_tmp_dir "I128")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
FAKE_TMUX="$TMP_DIR/fake-tmux.sh"
FAKE_ACTIVATE_OSASCRIPT="$TMP_DIR/fake-activate-osascript.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
TMUX_LOG="$TMP_DIR/tmux-calls.log"
ACTIVATE_OSASCRIPT_ARGS_LOG="$TMP_DIR/activate-osascript-args.log"
write_fake_notify "$FAKE_NOTIFY"
cat > "$FAKE_TMUX" <<'CASE_I128_TMUX'
#!/bin/sh
printf '%s\n' "$*" >> "$TMUX_CALL_LOG"
if [ "$1" = "display-message" ]; then
  printf '%s\n' "sess|3|win|2|%8|client-8|/dev/ttys008"
  exit 0
fi
exit 0
CASE_I128_TMUX
write_fake_frontmost_osascript "$FAKE_ACTIVATE_OSASCRIPT"
chmod +x "$FAKE_TMUX"
TMUX="/tmp/fake-socket,333,0" TMUX_PANE="%8" TERM_PROGRAM="tmux" NOTIFY_ACTIVATE_BUNDLE_ID="" \
  NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" NOTIFY_TMUX_BIN="$FAKE_TMUX" TMUX_CALL_LOG="$TMUX_LOG" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_ACTIVATE_OSASCRIPT" "$SCRIPT" "activate frontmost inference test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
if [ "$rc" -eq 0 ]; then
  pass "I128" "notify.sh tmux frontmost activate probe exits 0"
else
  fail "I128" "notify.sh tmux frontmost activate probe exited $rc"
fi
if grep -q -- '\]=-activate$' "$ARGS_LOG"; then
  fail "I128" "notify.sh unexpectedly forwarded native -activate in tmux mode"
else
  pass "I128" "notify.sh omits native -activate in tmux mode"
fi
if grep -q "tmux-redirect.sh'.*'com.jetbrains.intellij'" "$ARGS_LOG"; then
  pass "I128" "notify.sh passes inferred IntelliJ activate bundle to tmux redirect helper"
else
  fail "I128" "notify.sh did not pass inferred IntelliJ activate bundle to tmux redirect helper"
fi
EXECUTE_PAYLOAD=$(extract_execute_payload "$ARGS_LOG")
if [ -n "$EXECUTE_PAYLOAD" ]; then
  pass "I128" "notify.sh captured execute payload for tmux activate path"
else
  fail "I128" "notify.sh did not include execute payload for tmux activate path"
fi
TMUX_CALL_LOG="$TMUX_LOG" NOTIFY_ACTIVATE_OSASCRIPT_BIN="$FAKE_ACTIVATE_OSASCRIPT" ACTIVATE_OSASCRIPT_ARGS_LOG="$ACTIVATE_OSASCRIPT_ARGS_LOG" \
  /bin/sh -c "$EXECUTE_PAYLOAD"
rc=$?
if [ "$rc" -eq 0 ]; then
  pass "I128" "tmux redirect execute payload runs successfully"
else
  fail "I128" "tmux redirect execute payload failed (rc=$rc)"
fi
if grep -q '\[1\]=on run argv' "$ACTIVATE_OSASCRIPT_ARGS_LOG" \
  && grep -q '\[2\]=--' "$ACTIVATE_OSASCRIPT_ARGS_LOG" \
  && grep -q '\[3\]=com.jetbrains.intellij' "$ACTIVATE_OSASCRIPT_ARGS_LOG"; then
  pass "I128" "tmux redirect passes activate bundle via osascript argv"
else
  fail "I128" "tmux redirect did not use argv-based osascript activate call"
fi

case_start "I129" "notify.sh outside tmux omits activate when inference probe is unavailable"
TMP_DIR=$(make_case_tmp_dir "I129")
FAKE_NOTIFY="$TMP_DIR/fake-notify.sh"
ARGS_LOG="$TMP_DIR/notify-args.log"
MISSING_ACTIVATE_OSASCRIPT="$TMP_DIR/missing-activate-osascript.sh"
write_fake_notify "$FAKE_NOTIFY"
TMUX="" TERM_PROGRAM="JetBrains-JediTerm" NOTIFY_ACTIVATE_BUNDLE_ID="" \
  NOTIFY_ACTIVATE_OSASCRIPT_BIN="$MISSING_ACTIVATE_OSASCRIPT" NOTIFY_BIN="$FAKE_NOTIFY" NOTIFY_ARGS_LOG="$ARGS_LOG" \
  "$SCRIPT" "activate probe unavailable test" 2>/dev/null
rc=$?
wait_for_file "$ARGS_LOG" 20 >/dev/null 2>&1
if [ "$rc" -eq 0 ]; then
  pass "I129" "notify.sh outside-tmux unavailable probe exits 0"
else
  fail "I129" "notify.sh outside-tmux unavailable probe exited $rc"
fi
if grep -q -- '\]=-activate$' "$ARGS_LOG"; then
  fail "I129" "notify.sh unexpectedly forwarded -activate when probe was unavailable"
else
  pass "I129" "notify.sh omits -activate when outside-tmux probe is unavailable"
fi
if grep -q "activate probe unavailable test" "$ARGS_LOG"; then
  pass "I129" "notify.sh still forwards notification payload when probe is unavailable"
else
  fail "I129" "notify.sh did not forward notification payload when probe is unavailable"
fi

finish
