#!/bin/sh

# This file assumes testlib.sh is sourced first for wait_for_pid_file and
# wait_for_pid_removed used by drain_pid_file_if_present.

NOTIFY_TMUX_DISPLAY_MESSAGE_FORMAT='#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_id}|#{client_name}|#{client_tty}|#{client_pid}'

register_tmp_dir() {
  dir="$1"
  TEST_TMP_DIRS="$TEST_TMP_DIRS $dir"
}

make_case_tmp_dir() {
  case_id="$1"
  dir="/tmp/claude-notify-test-${case_id}.$$"
  register_tmp_dir "$dir"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

cleanup_registered_tmp_dirs() {
  for dir in $TEST_TMP_DIRS; do
    rm -rf "$dir"
  done
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

write_fake_origin_exec() {
  script_path="$1"
  cat > "$script_path" <<'FAKE_ORIGIN_SCRIPT'
#!/bin/sh
i=0
for arg in "$@"; do
  printf '[%d]=%s\n' "$i" "$arg" >> "$ORIGIN_ARGS_LOG"
  i=$((i + 1))
done
printf '%s\n' "${CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID:-}" > "$ORIGIN_ISOLATE_LOG"
printf '%s\n' "${CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY:-}" > "$ORIGIN_ALLOW_RETRY_LOG"
exit 0
FAKE_ORIGIN_SCRIPT
  chmod +x "$script_path"
}

write_fake_osascript() {
  script_path="$1"
  log_env_var="$2"
  cat > "$script_path" <<FAKE_OSASCRIPT
#!/bin/sh
log_path=\${$log_env_var:-}
if [ -n "\$log_path" ]; then
  i=0
  for arg in "\$@"; do
    printf '[%d]=%s\n' "\$i" "\$arg" >> "\$log_path"
    i=\$((i + 1))
  done
fi
case "\${2:-}" in
  *"id of app (path to frontmost application as text)"*)
    printf '%s\n' "com.jetbrains.intellij"
    ;;
esac
exit 0
FAKE_OSASCRIPT
  chmod +x "$script_path"
}

write_fake_osascript_success() {
  script_path="$1"
  write_fake_osascript "$script_path" "OSASCRIPT_ARGS_LOG"
}

write_fake_frontmost_osascript() {
  script_path="$1"
  write_fake_osascript "$script_path" "ACTIVATE_OSASCRIPT_ARGS_LOG"
}

write_failing_osascript() {
  script_path="$1"
  cat > "$script_path" <<'FAILING_OSASCRIPT_SCRIPT'
#!/bin/sh
if [ -n "${OSASCRIPT_ARGS_LOG:-}" ]; then
  i=0
  for arg in "$@"; do
    printf '[%d]=%s\n' "$i" "$arg" >> "$OSASCRIPT_ARGS_LOG"
    i=$((i + 1))
  done
fi
printf '%s\n' "simulated osascript failure" >&2
exit 1
FAILING_OSASCRIPT_SCRIPT
  chmod +x "$script_path"
}

notify_tmux_display_message_format() {
  notify_script="$1"
  format=$(awk -F"'" '/^NOTIFY_TMUX_DISPLAY_MESSAGE_FORMAT=/{print $2; exit}' "$notify_script")
  if [ -n "$format" ]; then
    printf '%s\n' "$format"
  else
    printf '%s\n' "$NOTIFY_TMUX_DISPLAY_MESSAGE_FORMAT"
  fi
}

build_tmux_display_message_payload() {
  session_name="$1"
  window_index="$2"
  window_name="$3"
  pane_index="$4"
  pane_id="$5"
  client_name="$6"
  client_tty="$7"
  client_pid="$8"
  printf '%s|%s|%s|%s|%s|%s|%s|%s\n' \
    "$session_name" "$window_index" "$window_name" "$pane_index" "$pane_id" "$client_name" "$client_tty" "$client_pid"
}

extract_execute_payload() {
  args_log="$1"
  awk '
    /\]=-execute$/ {
      if (getline > 0) {
        sub(/^\[[0-9]+\]=/, "", $0)
        print $0
        exit
      }
    }
  ' "$args_log"
}

wait_for_execute_payload() {
  args_log="$1"
  max_tries="${2:-30}"
  i=0
  while [ "$i" -lt "$max_tries" ]; do
    if [ -f "$args_log" ]; then
      execute_payload=$(extract_execute_payload "$args_log")
      if [ -n "$execute_payload" ]; then
        printf '%s\n' "$execute_payload"
        return 0
      fi
    fi
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

kill_pid_from_file() {
  pid_file="$1"
  expected_name="${2:-}"
  [ -f "$pid_file" ] || return 1
  pid=$(cat "$pid_file" 2>/dev/null)
  case "$pid" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac
  [ "$pid" -gt 0 ] 2>/dev/null || return 1
  if [ -n "$expected_name" ]; then
    kill -0 "$pid" 2>/dev/null || return 1
    proc=$(ps -p "$pid" -o comm= 2>/dev/null | awk 'NR==1 {print $1}')
    [ "$proc" = "$expected_name" ] || return 1
  fi
  kill "$pid" 2>/dev/null
}

drain_pid_file_if_present() {
  pid_file="$1"
  max_tries="${2:-20}"
  expected_name="${3:-}"
  # Depends on wait_for_pid_file and wait_for_pid_removed from testlib.sh.
  if wait_for_pid_file "$pid_file" "$max_tries"; then
    kill_pid_from_file "$pid_file" "$expected_name" >/dev/null 2>&1 || true
    wait_for_pid_removed "$pid_file" "$max_tries" >/dev/null 2>&1 || true
  fi
}

write_fake_app_bundle_runner() {
  app_root="$1"
  bundle_id="$2"
  exec_name="${3:-app-runner}"
  exec_path="$app_root/Contents/MacOS/$exec_name"
  mkdir -p "$app_root/Contents/MacOS"
  cat > "$app_root/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>$bundle_id</string>
</dict>
</plist>
EOF
  cat > "$exec_path" <<'FAKE_APP_RUNNER'
#!/bin/sh
pid_file="$1"
sleep_secs="${2:-30}"
sleep "$sleep_secs" &
child_pid=$!
if [ -n "$pid_file" ]; then
  printf '%s\n' "$child_pid" > "$pid_file"
fi
wait "$child_pid"
FAKE_APP_RUNNER
  chmod +x "$exec_path"
  printf '%s\n' "$exec_path"
}
