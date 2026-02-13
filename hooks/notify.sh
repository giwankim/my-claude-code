#!/bin/sh

NOTIFY="${NOTIFY_BIN:-$(dirname "$0")/claude-notify.app/Contents/MacOS/claude-notify}"
# Default sender spoofing off so click actions reliably focus tmux instead of spoofed apps.
SENDER_MODE="${NOTIFY_SENDER_MODE:-off}"
SENDER_BUNDLE_ID="${NOTIFY_SENDER_BUNDLE_ID:-com.anthropic.claudefordesktop}"
SENDER_APP_PATH="${NOTIFY_SENDER_APP_PATH:-}"
NOTIFY_TIMEOUT="${NOTIFY_TIMEOUT:-90}"
ACTIVATE_BUNDLE_ID="${NOTIFY_ACTIVATE_BUNDLE_ID:-com.mitchellh.ghostty}"
TMUX_BIN="${NOTIFY_TMUX_BIN:-$(command -v tmux 2>/dev/null || printf '%s' /opt/homebrew/bin/tmux)}"
NOTIFY_ISOLATE_HELPER_BUNDLE_ID="${NOTIFY_ISOLATE_HELPER_BUNDLE_ID:-1}"
NOTIFY_ALLOW_NONISOLATED_RETRY="${NOTIFY_ALLOW_NONISOLATED_RETRY:-0}"

# Read message from $1 (manual) or stdin JSON (Claude Code hook)
if [ -n "$1" ]; then
  MESSAGE="$1"
else
  MESSAGE=$(jq -r '.message // "Waiting for input"')
fi

notify_run() {
  if [ -n "$SENDER_APP_PATH" ]; then
    CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID="$NOTIFY_ISOLATE_HELPER_BUNDLE_ID" \
      CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY="$NOTIFY_ALLOW_NONISOLATED_RETRY" "$NOTIFY" "$@" \
      -timeout "$NOTIFY_TIMEOUT" \
      -sender-mode "$SENDER_MODE" \
      -sender-bundle-id "$SENDER_BUNDLE_ID" \
      -sender-app-path "$SENDER_APP_PATH"
  else
    CLAUDE_NOTIFY_ISOLATE_HELPER_BUNDLE_ID="$NOTIFY_ISOLATE_HELPER_BUNDLE_ID" \
      CLAUDE_NOTIFY_ALLOW_NONISOLATED_RETRY="$NOTIFY_ALLOW_NONISOLATED_RETRY" "$NOTIFY" "$@" \
      -timeout "$NOTIFY_TIMEOUT" \
      -sender-mode "$SENDER_MODE" \
      -sender-bundle-id "$SENDER_BUNDLE_ID"
  fi
}

if [ -n "$TMUX" ]; then
  # Get all tmux context in a single subprocess, then parse with parameter expansion
  SOCKET=${TMUX%%,*}
  if TMUX_INFO=$("$TMUX_BIN" display-message -t "$TMUX_PANE" -p '#{session_name}|#{window_index}|#{window_name}|#{client_tty}' 2>/dev/null); then
    case "$TMUX_INFO" in
      *"|"*"|"*"|"*)
        SESSION=${TMUX_INFO%%|*}; TMUX_INFO=${TMUX_INFO#*|}
        WINDOW=${TMUX_INFO%%|*}; TMUX_INFO=${TMUX_INFO#*|}
        WINDOW_NAME=${TMUX_INFO%%|*}
        CLIENT=${TMUX_INFO#*|}
        if [ -n "$CLIENT" ] && [ -n "$TMUX_PANE" ] && [ -n "$SOCKET" ]; then
          notify_run \
            -title "Claude Code" \
            -subtitle "$SESSION:$WINDOW_NAME" \
            -message "$MESSAGE" \
            -sound default \
            -group "claude-code" \
            -activate "$ACTIVATE_BUNDLE_ID" \
            -execute "'$TMUX_BIN' -S $SOCKET switch-client -c '$CLIENT' -t '$TMUX_PANE'" &
        else
          printf '%s\n' "Warning: tmux context incomplete; sending notification without execute action" >&2
          notify_run \
            -title "Claude Code" \
            -message "$MESSAGE" \
            -sound default \
            -group "claude-code" \
            -activate "$ACTIVATE_BUNDLE_ID" &
        fi
        ;;
      *)
        printf '%s\n' "Warning: unable to read tmux context; sending notification without execute action" >&2
        notify_run \
          -title "Claude Code" \
          -message "$MESSAGE" \
          -sound default \
          -group "claude-code" \
          -activate "$ACTIVATE_BUNDLE_ID" &
        ;;
    esac
  else
    printf '%s\n' "Warning: unable to read tmux context; sending notification without execute action" >&2
    notify_run \
      -title "Claude Code" \
      -message "$MESSAGE" \
      -sound default \
      -group "claude-code" \
      -activate "$ACTIVATE_BUNDLE_ID" &
  fi
else
  notify_run \
    -title "Claude Code" \
    -message "$MESSAGE" \
    -sound default \
    -group "claude-code" \
    -activate "$ACTIVATE_BUNDLE_ID" &
fi
