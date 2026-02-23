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

# Quote a single shell argument for execute payload passed via sh -c.
shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

# Best-effort send-time inference; click-time foreground app may differ.
infer_frontmost_activate_bundle_id() {
  [ -x "$ACTIVATE_OSASCRIPT_BIN" ] || return
  "$ACTIVATE_OSASCRIPT_BIN" -e 'id of app (path to frontmost application as text)' 2>/dev/null | tr -d '\r'
}

# Read message from $1 (manual) or stdin JSON (Claude Code hook)
if [ -n "$1" ]; then
  MESSAGE="$1"
else
  MESSAGE=$(jq -r '.message // "Waiting for input"')
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
    TARGET_PANE=$("$TMUX_BIN" display-message -p '#{pane_id}' 2>/dev/null)
  fi

  TMUX_FORMAT="$NOTIFY_TMUX_DISPLAY_MESSAGE_FORMAT"
  if [ -n "$TARGET_PANE" ]; then
    TMUX_INFO=$("$TMUX_BIN" display-message -t "$TARGET_PANE" -p "$TMUX_FORMAT" 2>/dev/null)
  else
    TMUX_INFO=$("$TMUX_BIN" display-message -p "$TMUX_FORMAT" 2>/dev/null)
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
          CLIENT_INFO=$("$TMUX_BIN" display-message -p '#{client_name}|#{client_tty}' 2>/dev/null)
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
