#!/bin/sh

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
NOTIFY="${NOTIFY_BIN:-$SCRIPT_DIR/claude-notify.app/Contents/MacOS/claude-notify}"
# Default to self-branded spoofing so notification icon consistently comes from claude-notify.app.
SENDER_MODE="${NOTIFY_SENDER_MODE:-auto}"
SENDER_BUNDLE_ID="${NOTIFY_SENDER_BUNDLE_ID:-com.gwk.claude-notify}"
SENDER_APP_PATH="${NOTIFY_SENDER_APP_PATH:-$SCRIPT_DIR/claude-notify.app}"
NOTIFY_TIMEOUT="${NOTIFY_TIMEOUT:-90}"
TMUX_BIN="${NOTIFY_TMUX_BIN:-$(command -v tmux 2>/dev/null || printf '%s' /opt/homebrew/bin/tmux)}"
TMUX_REDIRECT_SCRIPT="${NOTIFY_TMUX_REDIRECT_SCRIPT:-$SCRIPT_DIR/tmux-redirect.sh}"
NOTIFY_TMUX_DISPLAY_MESSAGE_FORMAT='#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_id}|#{client_name}|#{client_tty}|#{client_pid}'
TMUX_ACTIVATE_FALLBACK="${NOTIFY_TMUX_ACTIVATE_FALLBACK:-none}"
NOTIFY_ISOLATE_HELPER_BUNDLE_ID="${NOTIFY_ISOLATE_HELPER_BUNDLE_ID:-1}"
NOTIFY_ALLOW_NONISOLATED_RETRY="${NOTIFY_ALLOW_NONISOLATED_RETRY:-0}"
ACTIVATE_BUNDLE_ID="${NOTIFY_ACTIVATE_BUNDLE_ID:-}"
ACTIVATE_OSASCRIPT_BIN="${NOTIFY_ACTIVATE_OSASCRIPT_BIN:-/usr/bin/osascript}"
DEBUG_LOG="${NOTIFY_DEBUG_LOG:-}"
TMUX_REDIRECT_LOG="${NOTIFY_TMUX_REDIRECT_LOG:-$DEBUG_LOG}"
PS_BIN="${NOTIFY_PS_BIN:-ps}"

log_debug() {
  [ -n "$DEBUG_LOG" ] || return
  printf '%s [%d] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$$" "$1" >> "$DEBUG_LOG"
}

normalize_timeout_ms() {
  timeout_value="$1"
  timeout_default="$2"
  timeout_name="$3"
  case "$timeout_value" in
    '')
      printf '%s\n' "$timeout_default"
      ;;
    *[!0-9]*)
      log_debug "invalid timeout value for ${timeout_name}='${timeout_value}'; using default ${timeout_default}ms"
      printf '%s\n' "$timeout_default"
      ;;
    *)
      printf '%s\n' "$timeout_value"
      ;;
  esac
}

normalize_tmux_activate_fallback() {
  fallback_value="$1"
  case "$fallback_value" in
    frontmost|none)
      printf '%s\n' "$fallback_value"
      ;;
    *)
      log_debug "invalid tmux activate fallback '${fallback_value}'; using default none"
      printf '%s\n' "none"
      ;;
  esac
}

STDIN_TIMEOUT_MS="$(normalize_timeout_ms "${NOTIFY_STDIN_TIMEOUT_MS:-}" "150" "NOTIFY_STDIN_TIMEOUT_MS")"
TMUX_CMD_TIMEOUT_MS="$(normalize_timeout_ms "${NOTIFY_TMUX_CMD_TIMEOUT_MS:-}" "200" "NOTIFY_TMUX_CMD_TIMEOUT_MS")"
ACTIVATE_PROBE_TIMEOUT_MS="$(normalize_timeout_ms "${NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS:-}" "150" "NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS")"
TMUX_ACTIVATE_FALLBACK="$(normalize_tmux_activate_fallback "$TMUX_ACTIVATE_FALLBACK")"

require_perl_timeout_runtime() {
  if ! command -v perl >/dev/null 2>&1; then
    printf '%s\n' "notify.sh: perl is required for timeout handling (run_with_timeout_ms)." >&2
    exit 1
  fi
  if ! perl -MTime::HiRes -e '1' >/dev/null 2>&1; then
    printf '%s\n' "notify.sh: perl module Time::HiRes is required for timeout handling." >&2
    exit 1
  fi
}

# Perl timeout runtime is required only when at least one timeout wrapper is enabled.
if [ "$STDIN_TIMEOUT_MS" -gt 0 ] || [ "$TMUX_CMD_TIMEOUT_MS" -gt 0 ] || [ "$ACTIVATE_PROBE_TIMEOUT_MS" -gt 0 ]; then
  require_perl_timeout_runtime
fi

run_with_timeout_ms() {
  timeout_ms="$1"
  shift
  perl -e '
use strict;
use warnings;
use Time::HiRes qw(time usleep);
use POSIX qw(WNOHANG setpgid);

my ($timeout_ms, @cmd) = @ARGV;
if (!@cmd) {
  exit 2;
}

if (!defined $timeout_ms || $timeout_ms !~ /^\d+$/ || $timeout_ms <= 0) {
  exec @cmd;
  exit 127;
}

my $timeout = $timeout_ms / 1000.0;
my $pid = fork();
if (!defined $pid) {
  exit 2;
}

if ($pid == 0) {
  # Isolate the timed command in its own process group so timeout signals
  # can terminate helper descendants that inherited command-substitution pipes.
  setpgid(0, 0);
  exec @cmd;
  exit 127;
}

# The child always attempts setpgid(0, 0) before exec, so timeout signals
# should target the child process group unconditionally.
my $kill_target = -$pid;

my $deadline = time() + $timeout;
while (1) {
    my $result = waitpid($pid, WNOHANG);
    if ($result == $pid) {
        my $status = $?;
        if (($status & 127) != 0) {
            exit(128 + ($status & 127));
        }
        exit($status >> 8);
    }
    if ($result == -1) {
        exit 1;
    }
    if (time() >= $deadline) {
        kill "TERM", $kill_target;
        for (1 .. 5) {
            my $term_result = waitpid($pid, WNOHANG);
            if ($term_result == $pid || $term_result == -1) {
                exit 124;
            }
            usleep(5_000);
        }
        kill "KILL", $kill_target;
        waitpid($pid, 0);
        exit 124;
    }
    usleep(10_000);
}
  ' "$timeout_ms" "$@"
}

read_hook_payload_with_timeout() {
  if [ "$STDIN_TIMEOUT_MS" -le 0 ]; then
    cat
    return $?
  fi
  # NOTE: Timeout-wrapped reads still run `cat`, so unexpectedly large stdin can be fully buffered.
  # This is acceptable for expected hook payload sizes; switch to streaming/limits if that changes.
  run_with_timeout_ms "$STDIN_TIMEOUT_MS" cat
}

message_from_payload() {
  payload="$1"
  if ! command -v jq >/dev/null 2>&1; then
    log_debug "jq not found; cannot parse stdin payload"
    return 1
  fi
  printf '%s' "$payload" | jq -r '(.message | select(type == "string" and length > 0)) // (.last_assistant_message | select(type == "string" and length > 0)) // "Waiting for input"' 2>/dev/null
}

# Quote a single shell argument for execute payload passed via sh -c.
shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Best-effort send-time inference; click-time foreground app may differ.
infer_frontmost_activate_bundle_id() {
  [ -x "$ACTIVATE_OSASCRIPT_BIN" ] || return
  if [ "$ACTIVATE_PROBE_TIMEOUT_MS" -le 0 ]; then
    "$ACTIVATE_OSASCRIPT_BIN" -e 'id of app (path to frontmost application as text)' 2>/dev/null | tr -d '\r'
    return
  fi
  inferred_bundle_id=$(run_with_timeout_ms "$ACTIVATE_PROBE_TIMEOUT_MS" "$ACTIVATE_OSASCRIPT_BIN" \
    -e 'id of app (path to frontmost application as text)' 2>/dev/null)
  infer_rc=$?
  if [ "$infer_rc" -eq 124 ]; then
    log_debug "activate bundle inference timed out after ${ACTIVATE_PROBE_TIMEOUT_MS}ms"
    return
  fi
  if [ "$infer_rc" -ne 0 ]; then
    log_debug "activate bundle inference failed rc=$infer_rc"
    return
  fi
  printf '%s' "$inferred_bundle_id" | tr -d '\r'
}

resolve_bundle_id_from_app_path() {
  app_path="$1"
  plist_path="$app_path/Contents/Info.plist"
  [ -r "$plist_path" ] || return 1
  bundle_id_raw=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist_path" 2>/dev/null)
  plist_rc=$?
  [ "$plist_rc" -eq 0 ] || return "$plist_rc"
  printf '%s' "$bundle_id_raw" | tr -d '\r'
}

extract_app_exec_from_args() {
  proc_args="$1"
  case "$proc_args" in
    *".app/Contents/MacOS/"*)
      app_prefix_raw="${proc_args%".app/Contents/MacOS/"*}"
      exec_tail="${proc_args##*.app/Contents/MacOS/}"
      exec_name="${exec_tail%% *}"
      exec_name="${exec_name#\"}"
      exec_name="${exec_name#\'}"
      exec_name="${exec_name%\"}"
      exec_name="${exec_name%\'}"
      [ -n "$exec_name" ] || return 0

      fallback_prefix="$(printf '%s' "$app_prefix_raw" | sed "s/^[\"']//; s/[\"']$//; s/\\\\ / /g")"
      fallback_exec="${fallback_prefix}.app/Contents/MacOS/$exec_name"

      while IFS= read -r app_prefix_candidate; do
        [ -n "$app_prefix_candidate" ] || continue
        candidate_prefix="$(printf '%s' "$app_prefix_candidate" | sed "s/^[\"']//; s/[\"']$//; s/\\\\ / /g")"
        candidate_app_path="${candidate_prefix}.app"
        candidate_exec="$candidate_app_path/Contents/MacOS/$exec_name"
        if [ -r "$candidate_app_path/Contents/Info.plist" ]; then
          printf '%s\n' "$candidate_exec"
          return 0
        fi
      done <<EOF
$(printf '%s\n' "$app_prefix_raw" | awk '
{
  input = $0
  length_input = length(input)
  for (i = 1; i <= length_input; i++) {
    if (substr(input, i, 1) == "/") {
      print substr(input, i)
    }
  }
}')
EOF

      if [ -n "$fallback_exec" ]; then
        printf '%s\n' "$fallback_exec"
      fi
      ;;
  esac
}

resolve_tmux_client_host_bundle_id() {
  resolver_client_pid="$1"
  resolver_client_tty="$2"
  resolver_client_name="$3"
  resolver_socket="$4"
  TMUX_RESOLVED_APP_PATH=""
  TMUX_RESOLVED_BUNDLE_ID=""

  if [ -z "$resolver_client_pid" ]; then
    log_debug "tmux client host resolver failure reason=no-client-pid client_name=${resolver_client_name:-<empty>} client_tty=${resolver_client_tty:-<empty>} socket=${resolver_socket:-<empty>}"
    return 1
  fi
  case "$resolver_client_pid" in
    ''|*[!0-9]*)
      log_debug "tmux client host resolver failure reason=invalid-client-pid client_pid=${resolver_client_pid:-<empty>} client_name=${resolver_client_name:-<empty>} client_tty=${resolver_client_tty:-<empty>} socket=${resolver_socket:-<empty>}"
      return 1
      ;;
  esac

  current_pid="$resolver_client_pid"
  depth=0
  while [ "$depth" -lt 40 ]; do
    proc_line="$("$PS_BIN" -p "$current_pid" -o ppid= -o args= 2>/dev/null | awk 'NR==1{sub(/^[[:space:]]+/, "", $0); print; exit}')"
    if [ -z "$proc_line" ]; then
      log_debug "tmux client host resolver failure reason=ancestry-scan-miss start_pid=$resolver_client_pid missing_pid=$current_pid"
      return 1
    fi

    parent_pid="$(printf '%s\n' "$proc_line" | awk '{print $1}')"
    proc_args="$(printf '%s\n' "$proc_line" | sed -E 's/^[[:space:]]*[0-9]+[[:space:]]*//')"
    app_exec="$(extract_app_exec_from_args "$proc_args")"
    if [ -n "$app_exec" ]; then
      app_path="${app_exec%/Contents/MacOS/*}"
      resolved_bundle_id="$(resolve_bundle_id_from_app_path "$app_path")"
      resolve_bundle_rc=$?
      if [ "$resolve_bundle_rc" -eq 0 ] && [ -n "$resolved_bundle_id" ]; then
        TMUX_RESOLVED_APP_PATH="$app_path"
        TMUX_RESOLVED_BUNDLE_ID="$resolved_bundle_id"
        log_debug "tmux client host resolver resolved app_path=$TMUX_RESOLVED_APP_PATH bundle_id=$resolved_bundle_id source_pid=$current_pid depth=$depth"
        return 0
      fi
      log_debug "tmux client host resolver failure reason=plist-read-miss app_path=$app_path source_pid=$current_pid plist_rc=$resolve_bundle_rc"
      return 1
    fi

    case "$parent_pid" in
      ''|*[!0-9]*)
        break
        ;;
    esac
    if [ "$parent_pid" -le 1 ] || [ "$parent_pid" -eq "$current_pid" ]; then
      break
    fi
    current_pid="$parent_pid"
    depth=$((depth + 1))
  done

  log_debug "tmux client host resolver failure reason=ancestry-scan-miss start_pid=$resolver_client_pid client_name=${resolver_client_name:-<empty>} client_tty=${resolver_client_tty:-<empty>} socket=${resolver_socket:-<empty>}"
  return 1
}

# Read message from $1 (manual) or stdin JSON (Claude Code hook)
if [ -n "$1" ]; then
  MESSAGE="$1"
else
  MESSAGE="Waiting for input"
  PAYLOAD="$(read_hook_payload_with_timeout)"
  payload_rc=$?
  if [ "$payload_rc" -eq 0 ]; then
    if [ -n "$PAYLOAD" ]; then
      parsed_message="$(message_from_payload "$PAYLOAD")"
      parsed_rc=$?
      if [ "$parsed_rc" -eq 0 ]; then
        MESSAGE="$parsed_message"
      else
        log_debug "stdin payload parse failed; using fallback message"
      fi
    else
      log_debug "stdin payload empty; using fallback message"
    fi
  elif [ "$payload_rc" -eq 124 ]; then
    log_debug "stdin payload read timed out after ${STDIN_TIMEOUT_MS}ms; using fallback message"
  else
    log_debug "stdin payload read failed rc=$payload_rc; using fallback message"
  fi
fi
# Generate a unique generation token for supersession detection across spoof relaunches.
CLAUDE_NOTIFY_GENERATION="${CLAUDE_NOTIFY_GENERATION:-$$_$(date +%s)}"
export CLAUDE_NOTIFY_GENERATION

log_debug "notify.sh start tmux=${TMUX:-<empty>} pane=${TMUX_PANE:-<empty>} term_program=${TERM_PROGRAM:-<empty>} sender_mode=$SENDER_MODE generation=$CLAUDE_NOTIFY_GENERATION"

if [ -n "$TMUX" ]; then
  # Get tmux context in a single subprocess, then parse into fixed fields.
  SOCKET=${TMUX%%,*}
  TARGET_PANE="$TMUX_PANE"
  if [ -z "$TARGET_PANE" ]; then
    if [ "$TMUX_CMD_TIMEOUT_MS" -le 0 ]; then
      TARGET_PANE="$("$TMUX_BIN" display-message -p '#{pane_id}' 2>/dev/null)"
      target_pane_rc=$?
    else
      TARGET_PANE="$(run_with_timeout_ms "$TMUX_CMD_TIMEOUT_MS" "$TMUX_BIN" display-message -p '#{pane_id}' 2>/dev/null)"
      target_pane_rc=$?
    fi
    if [ "$target_pane_rc" -eq 124 ]; then
      log_debug "tmux pane lookup timed out after ${TMUX_CMD_TIMEOUT_MS}ms"
      TARGET_PANE=""
    elif [ "$target_pane_rc" -ne 0 ]; then
      log_debug "tmux pane lookup failed rc=$target_pane_rc"
      TARGET_PANE=""
    fi
  fi

  TMUX_FORMAT="$NOTIFY_TMUX_DISPLAY_MESSAGE_FORMAT"
  if [ -n "$TARGET_PANE" ]; then
    if [ "$TMUX_CMD_TIMEOUT_MS" -le 0 ]; then
      TMUX_INFO="$("$TMUX_BIN" display-message -t "$TARGET_PANE" -p "$TMUX_FORMAT" 2>/dev/null)"
      tmux_info_rc=$?
    else
      TMUX_INFO="$(run_with_timeout_ms "$TMUX_CMD_TIMEOUT_MS" "$TMUX_BIN" display-message -t "$TARGET_PANE" -p "$TMUX_FORMAT" 2>/dev/null)"
      tmux_info_rc=$?
    fi
  else
    if [ "$TMUX_CMD_TIMEOUT_MS" -le 0 ]; then
      TMUX_INFO="$("$TMUX_BIN" display-message -p "$TMUX_FORMAT" 2>/dev/null)"
      tmux_info_rc=$?
    else
      TMUX_INFO="$(run_with_timeout_ms "$TMUX_CMD_TIMEOUT_MS" "$TMUX_BIN" display-message -p "$TMUX_FORMAT" 2>/dev/null)"
      tmux_info_rc=$?
    fi
  fi
  if [ "$tmux_info_rc" -eq 124 ]; then
    log_debug "tmux metadata lookup timed out after ${TMUX_CMD_TIMEOUT_MS}ms"
    TMUX_INFO=""
  elif [ "$tmux_info_rc" -ne 0 ]; then
    log_debug "tmux metadata lookup failed rc=$tmux_info_rc"
    TMUX_INFO=""
  fi

  if [ -n "$TMUX_INFO" ]; then
    case "$TMUX_INFO" in
      *"|"*"|"*"|"*"|"*"|"*)
        SESSION=""
        WINDOW_INDEX=""
        WINDOW_NAME=""
        PANE_INDEX=""
        PANE_ID=""
        CLIENT_NAME=""
        CLIENT_TTY=""
        CLIENT_PID=""
        IFS='|' read -r SESSION WINDOW_INDEX WINDOW_NAME PANE_INDEX PANE_ID CLIENT_NAME CLIENT_TTY CLIENT_PID <<EOF
$TMUX_INFO
EOF

        if [ -z "$CLIENT_PID" ]; then
          if [ "$TMUX_CMD_TIMEOUT_MS" -le 0 ]; then
            CLIENT_INFO="$("$TMUX_BIN" display-message -p '#{client_name}|#{client_tty}|#{client_pid}' 2>/dev/null)"
            client_info_rc=$?
          else
            CLIENT_INFO="$(run_with_timeout_ms "$TMUX_CMD_TIMEOUT_MS" "$TMUX_BIN" display-message -p '#{client_name}|#{client_tty}|#{client_pid}' 2>/dev/null)"
            client_info_rc=$?
          fi
          if [ "$client_info_rc" -eq 124 ]; then
            log_debug "tmux client metadata lookup timed out after ${TMUX_CMD_TIMEOUT_MS}ms"
            CLIENT_INFO=""
          elif [ "$client_info_rc" -ne 0 ]; then
            log_debug "tmux client metadata lookup failed rc=$client_info_rc"
            CLIENT_INFO=""
          fi
          case "$CLIENT_INFO" in
            *"|"*)
              IFS='|' read -r CLIENT_NAME CLIENT_TTY CLIENT_PID <<EOF
$CLIENT_INFO
EOF
              ;;
          esac
        fi

        if [ -n "$PANE_ID" ]; then
          PANE_TARGET_ID="$PANE_ID"
        else
          PANE_TARGET_ID="$TARGET_PANE"
        fi

        ACTIVATE_SOURCE=""
        TMUX_RESOLVED_APP_PATH=""
        if [ -n "$ACTIVATE_BUNDLE_ID" ]; then
          ACTIVATE_SOURCE="explicit"
        else
          if resolve_tmux_client_host_bundle_id "$CLIENT_PID" "$CLIENT_TTY" "$CLIENT_NAME" "$SOCKET"; then
            ACTIVATE_BUNDLE_ID="$TMUX_RESOLVED_BUNDLE_ID"
            ACTIVATE_SOURCE="tmux-client-pid"
          else
            case "$TMUX_ACTIVATE_FALLBACK" in
              frontmost)
                ACTIVATE_BUNDLE_ID="$(infer_frontmost_activate_bundle_id)"
                ACTIVATE_SOURCE="fallback-frontmost"
                ;;
              *)
                ACTIVATE_BUNDLE_ID=""
                ACTIVATE_SOURCE="fallback-none"
                ;;
            esac
          fi
        fi
        log_debug "tmux activation source=${ACTIVATE_SOURCE:-<empty>} client_pid=${CLIENT_PID:-<empty>} resolved app path=${TMUX_RESOLVED_APP_PATH:-<empty>} activate_bundle=${ACTIVATE_BUNDLE_ID:-<empty>} fallback_policy=$TMUX_ACTIVATE_FALLBACK"

        set -- -title "Claude Code"
        if [ -n "$SESSION" ] && [ -n "$WINDOW_INDEX" ] && [ -n "$WINDOW_NAME" ]; then
          set -- "$@" -subtitle "$SESSION:$WINDOW_INDEX.$WINDOW_NAME"
        fi
        set -- "$@" \
          -message "$MESSAGE" \
          -sound default \
          -group "claude-code"
        if [ -n "$PANE_TARGET_ID" ] && [ -n "$SOCKET" ] && [ -x "$TMUX_REDIRECT_SCRIPT" ]; then
          if [ -n "$SESSION" ] && [ -n "$WINDOW_INDEX" ] && [ -n "$PANE_INDEX" ]; then
            PANE_TARGET_INDEX="$SESSION:$WINDOW_INDEX.$PANE_INDEX"
          else
            PANE_TARGET_INDEX="$PANE_TARGET_ID"
          fi

          EXECUTE_CMD="$(shell_quote "$TMUX_REDIRECT_SCRIPT") $(shell_quote "$TMUX_BIN") $(shell_quote "$SOCKET") $(shell_quote "$PANE_TARGET_ID") $(shell_quote "$PANE_TARGET_INDEX") $(shell_quote "$CLIENT_NAME") $(shell_quote "$CLIENT_TTY") $(shell_quote "${ACTIVATE_BUNDLE_ID:-}") $(shell_quote "${TMUX_REDIRECT_LOG:-}") $(shell_quote "${ACTIVATE_SOURCE:-}")"
          log_debug "execute payload prepared socket=$SOCKET pane_id=$PANE_TARGET_ID pane_index=$PANE_TARGET_INDEX client_name=${CLIENT_NAME:-<empty>} client_tty=${CLIENT_TTY:-<empty>} client_pid=${CLIENT_PID:-<empty>} activate_bundle=${ACTIVATE_BUNDLE_ID:-<empty>} activation_source=${ACTIVATE_SOURCE:-<empty>}"
          set -- "$@" -execute "$EXECUTE_CMD"
        else
          printf '%s\n' "Warning: tmux redirect helper unavailable or tmux context incomplete; sending notification without execute action" >&2
          log_debug "tmux execute omitted: helper unavailable or incomplete context socket=${SOCKET:-<empty>} pane=${PANE_TARGET_ID:-<empty>}"
        fi
        set -- "$@" \
          -timeout "$NOTIFY_TIMEOUT" \
          -sender-mode "$SENDER_MODE" \
          -sender-bundle-id "$SENDER_BUNDLE_ID"
        if [ -n "$SENDER_APP_PATH" ]; then
          set -- "$@" -sender-app-path "$SENDER_APP_PATH"
        fi
        CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID="$NOTIFY_ISOLATE_HELPER_BUNDLE_ID" \
          CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY="$NOTIFY_ALLOW_NONISOLATED_RETRY" "$NOTIFY" "$@" &
        ;;
      *)
        printf '%s\n' "Warning: unable to read tmux context; sending notification without execute action" >&2
        log_debug "tmux execute omitted: unable to parse tmux info"
        set -- \
          -title "Claude Code" \
          -message "$MESSAGE" \
          -sound default \
          -group "claude-code" \
          -timeout "$NOTIFY_TIMEOUT" \
          -sender-mode "$SENDER_MODE" \
          -sender-bundle-id "$SENDER_BUNDLE_ID"
        if [ -n "$SENDER_APP_PATH" ]; then
          set -- "$@" -sender-app-path "$SENDER_APP_PATH"
        fi
        CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID="$NOTIFY_ISOLATE_HELPER_BUNDLE_ID" \
          CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY="$NOTIFY_ALLOW_NONISOLATED_RETRY" "$NOTIFY" "$@" &
        ;;
    esac
  else
    printf '%s\n' "Warning: unable to read tmux context; sending notification without execute action" >&2
    log_debug "tmux execute omitted: tmux info empty"
    set -- \
      -title "Claude Code" \
      -message "$MESSAGE" \
      -sound default \
      -group "claude-code" \
      -timeout "$NOTIFY_TIMEOUT" \
      -sender-mode "$SENDER_MODE" \
      -sender-bundle-id "$SENDER_BUNDLE_ID"
    if [ -n "$SENDER_APP_PATH" ]; then
      set -- "$@" -sender-app-path "$SENDER_APP_PATH"
    fi
    CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID="$NOTIFY_ISOLATE_HELPER_BUNDLE_ID" \
      CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY="$NOTIFY_ALLOW_NONISOLATED_RETRY" "$NOTIFY" "$@" &
  fi
else
  if [ -z "$ACTIVATE_BUNDLE_ID" ]; then
    ACTIVATE_BUNDLE_ID="$(infer_frontmost_activate_bundle_id)"
    log_debug "inferred activate bundle id outside tmux: ${ACTIVATE_BUNDLE_ID:-<empty>}"
  fi
  ACTIVATE_OVERRIDE="${NOTIFY_ACTIVATE_OVERRIDE-$ACTIVATE_BUNDLE_ID}"
  log_debug "notify_run activate_override=${ACTIVATE_OVERRIDE:-<empty>} activate_bundle=${ACTIVATE_BUNDLE_ID:-<empty>}"
  log_debug "running outside tmux; execute action omitted"
  set -- \
    -title "Claude Code" \
    -message "$MESSAGE" \
    -sound default \
    -group "claude-code" \
    -timeout "$NOTIFY_TIMEOUT" \
    -sender-mode "$SENDER_MODE" \
    -sender-bundle-id "$SENDER_BUNDLE_ID"
  if [ -n "$ACTIVATE_OVERRIDE" ]; then
    set -- "$@" -activate "$ACTIVATE_OVERRIDE"
  fi
  if [ -n "$SENDER_APP_PATH" ]; then
    set -- "$@" -sender-app-path "$SENDER_APP_PATH"
  fi
  CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID="$NOTIFY_ISOLATE_HELPER_BUNDLE_ID" \
    CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY="$NOTIFY_ALLOW_NONISOLATED_RETRY" "$NOTIFY" "$@" &
fi
