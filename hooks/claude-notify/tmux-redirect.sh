#!/bin/sh
# Usage: tmux-redirect.sh <tmux_bin> <socket> <pane_id> <pane_index> [client_name] [client_tty] [activate_bundle_id] [debug_log] [activation_source]

TMUX_BIN="$1"
SOCKET="$2"
PANE_TARGET_ID="$3"
PANE_TARGET_INDEX="$4"
CLIENT_NAME="$5"
CLIENT_TTY="$6"
ACTIVATE_BUNDLE_ID="$7"
DEBUG_LOG="$8"
ACTIVATION_SOURCE="$9"
ACTIVATE_OSASCRIPT_BIN="${NOTIFY_ACTIVATE_OSASCRIPT_BIN:-/usr/bin/osascript}"

log_debug() {
  [ -n "$DEBUG_LOG" ] || return
  printf '%s [%d] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$$" "$1" >> "$DEBUG_LOG"
}

log_client_pane() {
  target_client="$1"
  [ -n "$target_client" ] || return
  state=$("$TMUX_BIN" -S "$SOCKET" display-message -c "$target_client" -p '#{session_name}:#{window_index}.#{pane_index}|#{pane_id}' 2>/dev/null || true)
  log_debug "client $target_client now at ${state:-<unknown>}"
}

if [ -z "$TMUX_BIN" ] || [ -z "$SOCKET" ] || [ -z "$PANE_TARGET_ID" ] || [ -z "$PANE_TARGET_INDEX" ]; then
  log_debug "skip redirect due to missing args tmux_bin=${TMUX_BIN:-<empty>} socket=${SOCKET:-<empty>} pane_id=${PANE_TARGET_ID:-<empty>} pane_index=${PANE_TARGET_INDEX:-<empty>}"
  exit 0
fi
log_debug "start redirect socket=$SOCKET pane_id=$PANE_TARGET_ID pane_index=$PANE_TARGET_INDEX client_name=${CLIENT_NAME:-<empty>} client_tty=${CLIENT_TTY:-<empty>} activation_source=${ACTIVATION_SOURCE:-<empty>}"

activate_bundle() {
  if [ -z "$ACTIVATE_BUNDLE_ID" ]; then
    log_debug "activation skipped activation_source=${ACTIVATION_SOURCE:-<empty>} bundle_id=<empty>"
    return 0
  fi
  log_debug "activating bundle id $ACTIVATE_BUNDLE_ID activation_source=${ACTIVATION_SOURCE:-<empty>}"
  if [ -x "$ACTIVATE_OSASCRIPT_BIN" ]; then
    "$ACTIVATE_OSASCRIPT_BIN" -e 'on run argv
  tell application id (item 1 of argv) to activate
end run' -- "$ACTIVATE_BUNDLE_ID" >/dev/null 2>&1
    rc=$?
    if [ "$rc" -eq 0 ]; then
      log_debug "activate via osascript succeeded for $ACTIVATE_BUNDLE_ID"
      return 0
    fi
    log_debug "activate via osascript failed rc=$rc for $ACTIVATE_BUNDLE_ID"
  fi
  /usr/bin/open -b "$ACTIVATE_BUNDLE_ID" >/dev/null 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    log_debug "activate via open succeeded for $ACTIVATE_BUNDLE_ID"
  else
    log_debug "activate via open failed rc=$rc for $ACTIVATE_BUNDLE_ID"
  fi
  return 0
}

switch_client_target() {
  target_client="$1"
  [ -n "$target_client" ] || return 1

  log_debug "try switch-client -c $target_client -t $PANE_TARGET_ID"
  "$TMUX_BIN" -S "$SOCKET" switch-client -c "$target_client" -t "$PANE_TARGET_ID" 2>/dev/null
  rc=$?
  if [ "$rc" -eq 0 ]; then
    log_debug "switch-client success with pane id for client $target_client"
    log_client_pane "$target_client"
    return 0
  fi
  log_debug "switch-client failed rc=$rc for client $target_client pane id"

  log_debug "try switch-client -c $target_client -t $PANE_TARGET_INDEX"
  "$TMUX_BIN" -S "$SOCKET" switch-client -c "$target_client" -t "$PANE_TARGET_INDEX" 2>/dev/null
  rc=$?
  if [ "$rc" -eq 0 ]; then
    log_debug "switch-client success with pane index for client $target_client"
    log_client_pane "$target_client"
    return 0
  fi
  log_debug "switch-client failed rc=$rc for client $target_client pane index"
  return 1
}

switched=0
if switch_client_target "$CLIENT_NAME"; then
  switched=1
elif switch_client_target "$CLIENT_TTY"; then
  switched=1
else
  clients=$("$TMUX_BIN" -S "$SOCKET" list-clients -F '#{client_name}' 2>/dev/null)
  log_debug "fallback list-clients: ${clients:-<empty>}"
  for client in $clients; do
    if switch_client_target "$client"; then
      switched=1
      break
    fi
  done
fi

if [ "$switched" -eq 0 ]; then
  log_debug "client-targeted switch failed; trying non-client switch-client fallback"
  "$TMUX_BIN" -S "$SOCKET" switch-client -t "$PANE_TARGET_ID" 2>/dev/null || \
    "$TMUX_BIN" -S "$SOCKET" switch-client -t "$PANE_TARGET_INDEX" 2>/dev/null || true
fi

log_debug "selecting pane via pane id/index fallback"
"$TMUX_BIN" -S "$SOCKET" select-pane -t "$PANE_TARGET_ID" 2>/dev/null || \
  "$TMUX_BIN" -S "$SOCKET" select-pane -t "$PANE_TARGET_INDEX" 2>/dev/null || true
activate_bundle
log_debug "redirect complete"

exit 0
