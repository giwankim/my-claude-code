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
NOTIFY_TMUX_DISPLAY_MESSAGE_FORMAT='#{session_name}|#{window_index}|#{window_name}|#{pane_index}|#{pane_id}|#{client_name}|#{client_tty}'
NOTIFY_ISOLATE_HELPER_BUNDLE_ID="${NOTIFY_ISOLATE_HELPER_BUNDLE_ID:-1}"
NOTIFY_ALLOW_NONISOLATED_RETRY="${NOTIFY_ALLOW_NONISOLATED_RETRY:-0}"
ACTIVATE_BUNDLE_ID="${NOTIFY_ACTIVATE_BUNDLE_ID:-}"
ACTIVATE_OSASCRIPT_BIN="${NOTIFY_ACTIVATE_OSASCRIPT_BIN:-/usr/bin/osascript}"
DEBUG_LOG="${NOTIFY_DEBUG_LOG:-}"
TMUX_REDIRECT_LOG="${NOTIFY_TMUX_REDIRECT_LOG:-$DEBUG_LOG}"

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

STDIN_TIMEOUT_MS="$(normalize_timeout_ms "${NOTIFY_STDIN_TIMEOUT_MS:-}" "150" "NOTIFY_STDIN_TIMEOUT_MS")"
TMUX_CMD_TIMEOUT_MS="$(normalize_timeout_ms "${NOTIFY_TMUX_CMD_TIMEOUT_MS:-}" "200" "NOTIFY_TMUX_CMD_TIMEOUT_MS")"
ACTIVATE_PROBE_TIMEOUT_MS="$(normalize_timeout_ms "${NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS:-}" "150" "NOTIFY_ACTIVATE_PROBE_TIMEOUT_MS")"

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

my $use_process_group_kill = 0;
if (setpgid($pid, $pid) == 0) {
  $use_process_group_kill = 1;
}
my $kill_target = $use_process_group_kill ? -$pid : $pid;

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
  command -v jq >/dev/null 2>&1 || return 1
  printf '%s' "$payload" | jq -r '(.message | select(type == "string" and length > 0)) // (.last_assistant_message | select(type == "string" and length > 0)) // "Waiting for input"' 2>/dev/null
}

tmux_query() {
  if [ "$TMUX_CMD_TIMEOUT_MS" -le 0 ]; then
    "$TMUX_BIN" "$@" 2>/dev/null
    return $?
  fi
  run_with_timeout_ms "$TMUX_CMD_TIMEOUT_MS" "$TMUX_BIN" "$@" 2>/dev/null
}

run_tmux_query_with_logging() {
  timeout_log_message="$1"
  failure_log_prefix="$2"
  shift 2

  tmux_output="$(tmux_query "$@")"
  tmux_query_rc=$?
  if [ "$tmux_query_rc" -eq 124 ]; then
    log_debug "$timeout_log_message"
    return 124
  fi
  if [ "$tmux_query_rc" -ne 0 ]; then
    log_debug "$failure_log_prefix rc=$tmux_query_rc"
    return "$tmux_query_rc"
  fi
  printf '%s' "$tmux_output"
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
log_debug "notify.sh start tmux=${TMUX:-<empty>} pane=${TMUX_PANE:-<empty>} term_program=${TERM_PROGRAM:-<empty>} sender_mode=$SENDER_MODE"

notify_run() {
  ACTIVATE_OVERRIDE="${NOTIFY_ACTIVATE_OVERRIDE-$ACTIVATE_BUNDLE_ID}"
  log_debug "notify_run activate_override=${ACTIVATE_OVERRIDE:-<empty>} activate_bundle=${ACTIVATE_BUNDLE_ID:-<empty>}"
  set -- "$@" \
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
    CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY="$NOTIFY_ALLOW_NONISOLATED_RETRY" "$NOTIFY" "$@"
}

tmux_notify() {
  subtitle="$1"
  execute_cmd="$2"

  set -- -title "Claude Code"
  if [ -n "$subtitle" ]; then
    set -- "$@" -subtitle "$subtitle"
  fi
  set -- "$@" \
    -message "$MESSAGE" \
    -sound default \
    -group "claude-code"
  if [ -n "$execute_cmd" ]; then
    set -- "$@" -execute "$execute_cmd"
  fi

  NOTIFY_ACTIVATE_OVERRIDE="" notify_run "$@" &
}

if [ -n "$TMUX" ]; then
  # Get tmux context in a single subprocess, then parse with parameter expansion.
  SOCKET=${TMUX%%,*}
  TARGET_PANE="$TMUX_PANE"
  if [ -z "$TARGET_PANE" ]; then
    TARGET_PANE="$(run_tmux_query_with_logging \
      "tmux pane lookup timed out after ${TMUX_CMD_TIMEOUT_MS}ms" \
      "tmux pane lookup failed" \
      display-message -p '#{pane_id}')"
    target_pane_rc=$?
    if [ "$target_pane_rc" -ne 0 ]; then
      TARGET_PANE=""
    fi
  fi

  TMUX_FORMAT="$NOTIFY_TMUX_DISPLAY_MESSAGE_FORMAT"
  if [ -n "$TARGET_PANE" ]; then
    TMUX_INFO="$(run_tmux_query_with_logging \
      "tmux metadata lookup timed out after ${TMUX_CMD_TIMEOUT_MS}ms" \
      "tmux metadata lookup failed" \
      display-message -t "$TARGET_PANE" -p "$TMUX_FORMAT")"
    tmux_info_rc=$?
  else
    TMUX_INFO="$(run_tmux_query_with_logging \
      "tmux metadata lookup timed out after ${TMUX_CMD_TIMEOUT_MS}ms" \
      "tmux metadata lookup failed" \
      display-message -p "$TMUX_FORMAT")"
    tmux_info_rc=$?
  fi
  if [ "$tmux_info_rc" -ne 0 ]; then
    TMUX_INFO=""
  fi

  if [ -n "$TMUX_INFO" ]; then
    case "$TMUX_INFO" in
      *"|"*"|"*"|"*"|"*"|"*)
        SESSION=${TMUX_INFO%%|*}; TMUX_INFO=${TMUX_INFO#*|}
        WINDOW_INDEX=${TMUX_INFO%%|*}; TMUX_INFO=${TMUX_INFO#*|}
        WINDOW_NAME=${TMUX_INFO%%|*}; TMUX_INFO=${TMUX_INFO#*|}
        PANE_INDEX=${TMUX_INFO%%|*}; TMUX_INFO=${TMUX_INFO#*|}
        PANE_ID=${TMUX_INFO%%|*}; TMUX_INFO=${TMUX_INFO#*|}
        CLIENT_NAME=${TMUX_INFO%%|*}
        CLIENT_TTY=${TMUX_INFO#*|}

        if [ -z "$CLIENT_NAME" ] && [ -z "$CLIENT_TTY" ]; then
          CLIENT_INFO="$(run_tmux_query_with_logging \
            "tmux client metadata lookup timed out after ${TMUX_CMD_TIMEOUT_MS}ms" \
            "tmux client metadata lookup failed" \
            display-message -p '#{client_name}|#{client_tty}')"
          client_info_rc=$?
          if [ "$client_info_rc" -ne 0 ]; then
            CLIENT_INFO=""
          fi
          case "$CLIENT_INFO" in
            *"|"*)
              CLIENT_NAME=${CLIENT_INFO%%|*}
              CLIENT_TTY=${CLIENT_INFO#*|}
              ;;
          esac
        fi

        if [ -n "$PANE_ID" ]; then
          PANE_TARGET_ID="$PANE_ID"
        else
          PANE_TARGET_ID="$TARGET_PANE"
        fi
        if [ -z "$ACTIVATE_BUNDLE_ID" ]; then
          ACTIVATE_BUNDLE_ID="$(infer_frontmost_activate_bundle_id)"
          log_debug "inferred activate bundle id in tmux mode: ${ACTIVATE_BUNDLE_ID:-<empty>}"
        fi
        if [ -n "$PANE_TARGET_ID" ] && [ -n "$SOCKET" ] && [ -x "$TMUX_REDIRECT_SCRIPT" ]; then
          if [ -n "$SESSION" ] && [ -n "$WINDOW_INDEX" ] && [ -n "$PANE_INDEX" ]; then
            PANE_TARGET_INDEX="$SESSION:$WINDOW_INDEX.$PANE_INDEX"
          else
            PANE_TARGET_INDEX="$PANE_TARGET_ID"
          fi

          EXECUTE_CMD="$(shell_quote "$TMUX_REDIRECT_SCRIPT") $(shell_quote "$TMUX_BIN") $(shell_quote "$SOCKET") $(shell_quote "$PANE_TARGET_ID") $(shell_quote "$PANE_TARGET_INDEX") $(shell_quote "$CLIENT_NAME") $(shell_quote "$CLIENT_TTY") $(shell_quote "${ACTIVATE_BUNDLE_ID:-}") $(shell_quote "${TMUX_REDIRECT_LOG:-}")"
          log_debug "execute payload prepared socket=$SOCKET pane_id=$PANE_TARGET_ID pane_index=$PANE_TARGET_INDEX client_name=${CLIENT_NAME:-<empty>} client_tty=${CLIENT_TTY:-<empty>} activate_bundle=${ACTIVATE_BUNDLE_ID:-<empty>}"

          tmux_notify "$SESSION:$WINDOW_INDEX.$WINDOW_NAME" "$EXECUTE_CMD"
        else
          printf '%s\n' "Warning: tmux redirect helper unavailable or tmux context incomplete; sending notification without execute action" >&2
          log_debug "tmux execute omitted: helper unavailable or incomplete context socket=${SOCKET:-<empty>} pane=${PANE_TARGET_ID:-<empty>}"
          tmux_notify "" ""
        fi
        ;;
      *)
        printf '%s\n' "Warning: unable to read tmux context; sending notification without execute action" >&2
        log_debug "tmux execute omitted: unable to parse tmux info"
        tmux_notify "" ""
        ;;
    esac
  else
    printf '%s\n' "Warning: unable to read tmux context; sending notification without execute action" >&2
    log_debug "tmux execute omitted: tmux info empty"
    tmux_notify "" ""
  fi
else
  if [ -z "$ACTIVATE_BUNDLE_ID" ]; then
    ACTIVATE_BUNDLE_ID="$(infer_frontmost_activate_bundle_id)"
    log_debug "inferred activate bundle id outside tmux: ${ACTIVATE_BUNDLE_ID:-<empty>}"
  fi
  log_debug "running outside tmux; execute action omitted"
  notify_run \
    -title "Claude Code" \
    -message "$MESSAGE" \
    -sound default \
    -group "claude-code" &
fi
