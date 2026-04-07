#!/bin/sh

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"
# shellcheck source=hooks/claude-notify/Tests/shell/lib/testlib.sh
. "$PROJECT_DIR/Tests/shell/lib/testlib.sh"
# shellcheck source=hooks/claude-notify/Tests/shell/lib/notify-test-helpers.sh
. "$PROJECT_DIR/Tests/shell/lib/notify-test-helpers.sh"

SCRIPT="$PROJECT_DIR/scripts/uninstall-hooks.sh"
TEST_TMP_DIRS=""

cleanup() {
  cleanup_registered_tmp_dirs
}
trap cleanup EXIT

# --- Helper: write a synthetic settings.json with both claude-notify hooks ---
write_both_hooks_settings() {
  cat > "$1" <<'SETTINGS_JSON'
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  },
  "permissions": {
    "defaultMode": "plan"
  },
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/test/.claude/hooks/claude-notify/notify.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "NOTIFY_SENDER_MODE=off /Users/test/.claude/hooks/claude-notify/notify.sh \"Claude finished\"",
            "timeout": 5,
            "async": true
          }
        ]
      }
    ]
  },
  "statusLine": {
    "type": "command",
    "command": "echo status"
  }
}
SETTINGS_JSON
}

# --- Helper: write settings with mixed claude-notify and non-claude-notify hooks ---
write_mixed_hooks_settings() {
  cat > "$1" <<'SETTINGS_JSON'
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/test/.claude/hooks/claude-notify/notify.sh",
            "timeout": 5
          }
        ]
      },
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "/some/other/hook.sh",
            "timeout": 10
          }
        ]
      }
    ],
    "Stop": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "NOTIFY_SENDER_MODE=off /Users/test/.claude/hooks/claude-notify/notify.sh \"Claude finished\"",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
SETTINGS_JSON
}

# --- Helper: write settings with no claude-notify hooks ---
write_no_notify_settings() {
  cat > "$1" <<'SETTINGS_JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write",
        "hooks": [
          {
            "type": "command",
            "command": "/some/other/hook.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS_JSON
}

# ===========================================================================

case_start "U057" "--all removes all claude-notify entries"
TMP_DIR=$(make_case_tmp_dir "U057")
write_both_hooks_settings "$TMP_DIR/settings.json"
"$SCRIPT" --all --settings "$TMP_DIR/settings.json" >/dev/null 2>&1
rc=$?
assert_rc_eq "U057" "$rc" 0 \
  "uninstall --all exits 0" \
  "uninstall --all exited $rc"
if jq -e '.hooks.Notification' "$TMP_DIR/settings.json" >/dev/null 2>&1; then
  fail "U057" "Notification hook still present after --all"
else
  pass "U057" "Notification hook removed"
fi
if jq -e '.hooks.Stop' "$TMP_DIR/settings.json" >/dev/null 2>&1; then
  fail "U057" "Stop hook still present after --all"
else
  pass "U057" "Stop hook removed"
fi

# ===========================================================================

case_start "U058" "--all preserves non-claude-notify hook entries in the same event"
TMP_DIR=$(make_case_tmp_dir "U058")
write_mixed_hooks_settings "$TMP_DIR/settings.json"
"$SCRIPT" --all --settings "$TMP_DIR/settings.json" >/dev/null 2>&1
rc=$?
assert_rc_eq "U058" "$rc" 0 \
  "uninstall --all mixed exits 0" \
  "uninstall --all mixed exited $rc"
# The non-claude-notify Notification entry (matcher "Write") should survive.
other_cmd=$(jq -r '.hooks.Notification[0].hooks[0].command // empty' "$TMP_DIR/settings.json" 2>/dev/null)
if [ "$other_cmd" = "/some/other/hook.sh" ]; then
  pass "U058" "non-claude-notify Notification entry preserved"
else
  fail "U058" "non-claude-notify Notification entry missing (got: $other_cmd)"
fi
# Stop should be gone entirely (only had claude-notify).
if jq -e '.hooks.Stop' "$TMP_DIR/settings.json" >/dev/null 2>&1; then
  fail "U058" "Stop hook still present after --all"
else
  pass "U058" "Stop hook removed"
fi

# ===========================================================================

case_start "U059" "--all preserves other top-level settings keys"
TMP_DIR=$(make_case_tmp_dir "U059")
write_both_hooks_settings "$TMP_DIR/settings.json"
"$SCRIPT" --all --settings "$TMP_DIR/settings.json" >/dev/null 2>&1
rc=$?
assert_rc_eq "U059" "$rc" 0 \
  "uninstall --all exits 0" \
  "uninstall --all exited $rc"
env_val=$(jq -r '.env.CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS // empty' "$TMP_DIR/settings.json" 2>/dev/null)
if [ "$env_val" = "1" ]; then
  pass "U059" "env key preserved"
else
  fail "U059" "env key missing or changed (got: $env_val)"
fi
status_type=$(jq -r '.statusLine.type // empty' "$TMP_DIR/settings.json" 2>/dev/null)
if [ "$status_type" = "command" ]; then
  pass "U059" "statusLine key preserved"
else
  fail "U059" "statusLine key missing or changed (got: $status_type)"
fi

# ===========================================================================

case_start "U060" "--hook Notification removes only Notification, leaves Stop"
TMP_DIR=$(make_case_tmp_dir "U060")
write_both_hooks_settings "$TMP_DIR/settings.json"
"$SCRIPT" --hook Notification --settings "$TMP_DIR/settings.json" >/dev/null 2>&1
rc=$?
assert_rc_eq "U060" "$rc" 0 \
  "uninstall --hook Notification exits 0" \
  "uninstall --hook Notification exited $rc"
if jq -e '.hooks.Notification' "$TMP_DIR/settings.json" >/dev/null 2>&1; then
  fail "U060" "Notification hook still present"
else
  pass "U060" "Notification hook removed"
fi
if jq -e '.hooks.Stop' "$TMP_DIR/settings.json" >/dev/null 2>&1; then
  pass "U060" "Stop hook preserved"
else
  fail "U060" "Stop hook was incorrectly removed"
fi

# ===========================================================================

case_start "U061" "--hook Stop removes only Stop, leaves Notification"
TMP_DIR=$(make_case_tmp_dir "U061")
write_both_hooks_settings "$TMP_DIR/settings.json"
"$SCRIPT" --hook Stop --settings "$TMP_DIR/settings.json" >/dev/null 2>&1
rc=$?
assert_rc_eq "U061" "$rc" 0 \
  "uninstall --hook Stop exits 0" \
  "uninstall --hook Stop exited $rc"
if jq -e '.hooks.Stop' "$TMP_DIR/settings.json" >/dev/null 2>&1; then
  fail "U061" "Stop hook still present"
else
  pass "U061" "Stop hook removed"
fi
if jq -e '.hooks.Notification' "$TMP_DIR/settings.json" >/dev/null 2>&1; then
  pass "U061" "Notification hook preserved"
else
  fail "U061" "Notification hook was incorrectly removed"
fi

# ===========================================================================

case_start "U062" "settings file does not exist -- exits 0"
TMP_DIR=$(make_case_tmp_dir "U062")
output=$("$SCRIPT" --all --settings "$TMP_DIR/nonexistent.json" 2>&1)
rc=$?
assert_rc_eq "U062" "$rc" 0 \
  "uninstall exits 0 for missing settings" \
  "uninstall exited $rc for missing settings"
case "$output" in
  *"not found"*|*"does not exist"*|*"No settings"*)
    pass "U062" "informational message printed"
    ;;
  *)
    fail "U062" "no informational message about missing file (got: $output)"
    ;;
esac

# ===========================================================================

case_start "U063" "no claude-notify hooks found -- exits 0"
TMP_DIR=$(make_case_tmp_dir "U063")
write_no_notify_settings "$TMP_DIR/settings.json"
cp "$TMP_DIR/settings.json" "$TMP_DIR/settings-before.json"
output=$("$SCRIPT" --all --settings "$TMP_DIR/settings.json" 2>&1)
rc=$?
assert_rc_eq "U063" "$rc" 0 \
  "uninstall exits 0 when no notify hooks" \
  "uninstall exited $rc when no notify hooks"
if diff -q "$TMP_DIR/settings.json" "$TMP_DIR/settings-before.json" >/dev/null 2>&1; then
  pass "U063" "settings file unchanged"
else
  fail "U063" "settings file was modified when no notify hooks existed"
fi

# ===========================================================================

case_start "U064" "--dry-run reports changes but does not modify the file"
TMP_DIR=$(make_case_tmp_dir "U064")
write_both_hooks_settings "$TMP_DIR/settings.json"
cp "$TMP_DIR/settings.json" "$TMP_DIR/settings-before.json"
output=$("$SCRIPT" --all --dry-run --settings "$TMP_DIR/settings.json" 2>&1)
rc=$?
assert_rc_eq "U064" "$rc" 0 \
  "uninstall --dry-run exits 0" \
  "uninstall --dry-run exited $rc"
if diff -q "$TMP_DIR/settings.json" "$TMP_DIR/settings-before.json" >/dev/null 2>&1; then
  pass "U064" "settings file not modified in dry-run"
else
  fail "U064" "settings file was modified during dry-run"
fi
case "$output" in
  *"Notification"*|*"Stop"*|*"would remove"*|*"dry"*)
    pass "U064" "dry-run output mentions affected hooks"
    ;;
  *)
    fail "U064" "dry-run output missing affected hook info (got: $output)"
    ;;
esac

# ===========================================================================

case_start "U065" "backup file is created before modification"
TMP_DIR=$(make_case_tmp_dir "U065")
write_both_hooks_settings "$TMP_DIR/settings.json"
"$SCRIPT" --all --settings "$TMP_DIR/settings.json" >/dev/null 2>&1
rc=$?
assert_rc_eq "U065" "$rc" 0 \
  "uninstall exits 0" \
  "uninstall exited $rc"
backup_count=$(find "$TMP_DIR" -name 'settings.json.backup-*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$backup_count" -ge 1 ]; then
  pass "U065" "backup file created ($backup_count found)"
else
  fail "U065" "no backup file created"
fi

# ===========================================================================

case_start "U066" "empty .hooks object is removed after all entries gone"
TMP_DIR=$(make_case_tmp_dir "U066")
# Settings with only claude-notify hooks — after removal .hooks should vanish.
cat > "$TMP_DIR/settings.json" <<'SETTINGS_JSON'
{
  "env": { "FOO": "1" },
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/test/.claude/hooks/claude-notify/notify.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS_JSON
"$SCRIPT" --all --settings "$TMP_DIR/settings.json" >/dev/null 2>&1
rc=$?
assert_rc_eq "U066" "$rc" 0 \
  "uninstall exits 0" \
  "uninstall exited $rc"
if jq -e '.hooks' "$TMP_DIR/settings.json" >/dev/null 2>&1; then
  fail "U066" "empty .hooks key still present"
else
  pass "U066" "empty .hooks key removed"
fi
env_val=$(jq -r '.env.FOO // empty' "$TMP_DIR/settings.json" 2>/dev/null)
if [ "$env_val" = "1" ]; then
  pass "U066" "other keys preserved"
else
  fail "U066" "other keys lost (got: $env_val)"
fi

# ===========================================================================

case_start "U067" "mixed entries retain only non-claude-notify entries"
TMP_DIR=$(make_case_tmp_dir "U067")
# Notification has two matcher groups: one claude-notify, one other.
cat > "$TMP_DIR/settings.json" <<'SETTINGS_JSON'
{
  "hooks": {
    "Notification": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "/Users/test/.claude/hooks/claude-notify/notify.sh"
          },
          {
            "type": "command",
            "command": "/other/hook.sh"
          }
        ]
      }
    ]
  }
}
SETTINGS_JSON
"$SCRIPT" --all --settings "$TMP_DIR/settings.json" >/dev/null 2>&1
rc=$?
assert_rc_eq "U067" "$rc" 0 \
  "uninstall mixed exits 0" \
  "uninstall mixed exited $rc"
# The matcher group should remain because /other/hook.sh survives.
remaining_cmd=$(jq -r '.hooks.Notification[0].hooks[0].command // empty' "$TMP_DIR/settings.json" 2>/dev/null)
if [ "$remaining_cmd" = "/other/hook.sh" ]; then
  pass "U067" "non-claude-notify entry preserved in mixed matcher group"
else
  fail "U067" "unexpected remaining command (got: $remaining_cmd)"
fi
# The claude-notify entry should be gone.
notify_count=$(jq '[.hooks.Notification[0].hooks[] | select(.command | test("claude-notify/notify\\.sh"))] | length' "$TMP_DIR/settings.json" 2>/dev/null)
if [ "$notify_count" = "0" ]; then
  pass "U067" "claude-notify entry removed from mixed group"
else
  fail "U067" "claude-notify entry still present ($notify_count remaining)"
fi

# ===========================================================================

case_start "U068" "--remove-files removes installed directory"
TMP_DIR=$(make_case_tmp_dir "U068")
write_both_hooks_settings "$TMP_DIR/settings.json"
FAKE_INSTALL_DIR="$TMP_DIR/fake-install"
mkdir -p "$FAKE_INSTALL_DIR"
printf 'placeholder\n' > "$FAKE_INSTALL_DIR/notify.sh"
"$SCRIPT" --all --remove-files --settings "$TMP_DIR/settings.json" --install-dir "$FAKE_INSTALL_DIR" >/dev/null 2>&1
rc=$?
assert_rc_eq "U068" "$rc" 0 \
  "uninstall --remove-files exits 0" \
  "uninstall --remove-files exited $rc"
if [ -d "$FAKE_INSTALL_DIR" ]; then
  fail "U068" "install directory still exists"
else
  pass "U068" "install directory removed"
fi

# ===========================================================================

case_start "U069" "multiple --hook flags remove multiple specific events"
TMP_DIR=$(make_case_tmp_dir "U069")
write_both_hooks_settings "$TMP_DIR/settings.json"
"$SCRIPT" --hook Notification --hook Stop --settings "$TMP_DIR/settings.json" >/dev/null 2>&1
rc=$?
assert_rc_eq "U069" "$rc" 0 \
  "uninstall --hook Notification --hook Stop exits 0" \
  "uninstall --hook Notification --hook Stop exited $rc"
if jq -e '.hooks.Notification' "$TMP_DIR/settings.json" >/dev/null 2>&1; then
  fail "U069" "Notification hook still present"
else
  pass "U069" "Notification hook removed"
fi
if jq -e '.hooks.Stop' "$TMP_DIR/settings.json" >/dev/null 2>&1; then
  fail "U069" "Stop hook still present"
else
  pass "U069" "Stop hook removed"
fi

# ===========================================================================

case_start "U070" "--remove-files removes install dir even when settings file is missing"
TMP_DIR=$(make_case_tmp_dir "U070")
FAKE_INSTALL_DIR="$TMP_DIR/fake-install"
mkdir -p "$FAKE_INSTALL_DIR"
printf 'placeholder\n' > "$FAKE_INSTALL_DIR/notify.sh"
"$SCRIPT" --all --remove-files --settings "$TMP_DIR/nonexistent.json" --install-dir "$FAKE_INSTALL_DIR" >/dev/null 2>&1
rc=$?
assert_rc_eq "U070" "$rc" 0 \
  "uninstall exits 0 for missing settings with --remove-files" \
  "uninstall exited $rc for missing settings with --remove-files"
if [ -d "$FAKE_INSTALL_DIR" ]; then
  fail "U070" "install directory still exists after --remove-files with missing settings"
else
  pass "U070" "install directory removed despite missing settings"
fi

# ===========================================================================

case_start "U071" "--remove-files removes install dir when no claude-notify hooks exist"
TMP_DIR=$(make_case_tmp_dir "U071")
write_no_notify_settings "$TMP_DIR/settings.json"
FAKE_INSTALL_DIR="$TMP_DIR/fake-install"
mkdir -p "$FAKE_INSTALL_DIR"
printf 'placeholder\n' > "$FAKE_INSTALL_DIR/notify.sh"
"$SCRIPT" --all --remove-files --settings "$TMP_DIR/settings.json" --install-dir "$FAKE_INSTALL_DIR" >/dev/null 2>&1
rc=$?
assert_rc_eq "U071" "$rc" 0 \
  "uninstall exits 0 with no matching hooks and --remove-files" \
  "uninstall exited $rc with no matching hooks and --remove-files"
if [ -d "$FAKE_INSTALL_DIR" ]; then
  fail "U071" "install directory still exists after --remove-files with no matching hooks"
else
  pass "U071" "install directory removed despite no matching hooks"
fi

# ===========================================================================

case_start "U072" "symlinked settings.json: real target is modified, symlink preserved"
TMP_DIR=$(make_case_tmp_dir "U072")
REAL_DIR="$TMP_DIR/real"
LINK_DIR="$TMP_DIR/link"
mkdir -p "$REAL_DIR" "$LINK_DIR"
write_both_hooks_settings "$REAL_DIR/settings.json"
ln -s "$REAL_DIR/settings.json" "$LINK_DIR/settings.json"
"$SCRIPT" --all --settings "$LINK_DIR/settings.json" >/dev/null 2>&1
rc=$?
assert_rc_eq "U072" "$rc" 0 \
  "uninstall through symlink exits 0" \
  "uninstall through symlink exited $rc"
if [ -L "$LINK_DIR/settings.json" ]; then
  pass "U072" "symlink preserved"
else
  fail "U072" "symlink was replaced with a regular file"
fi
if jq -e '.hooks.Notification' "$REAL_DIR/settings.json" >/dev/null 2>&1; then
  fail "U072" "real target still has Notification hook"
else
  pass "U072" "real target had Notification hook removed"
fi

# ===========================================================================

case_start "U073" "--all reporting does not emit jq errors to stderr"
TMP_DIR=$(make_case_tmp_dir "U073")
write_both_hooks_settings "$TMP_DIR/settings.json"
stderr_output=$("$SCRIPT" --all --settings "$TMP_DIR/settings.json" 2>&1 1>/dev/null)
rc=$?
assert_rc_eq "U073" "$rc" 0 \
  "uninstall --all exits 0" \
  "uninstall --all exited $rc"
case "$stderr_output" in
  *"Cannot index"*|*"error"*|*"jq:"*)
    fail "U073" "jq error in stderr: $stderr_output"
    ;;
  *)
    pass "U073" "no jq errors in stderr"
    ;;
esac

# ===========================================================================

case_start "U074" "empty hooks object is treated as no-op"
TMP_DIR=$(make_case_tmp_dir "U074")
cat > "$TMP_DIR/settings.json" <<'SETTINGS_JSON'
{
  "env": { "FOO": "1" },
  "hooks": {}
}
SETTINGS_JSON
cp "$TMP_DIR/settings.json" "$TMP_DIR/settings-before.json"
output=$("$SCRIPT" --all --settings "$TMP_DIR/settings.json" 2>&1)
rc=$?
assert_rc_eq "U074" "$rc" 0 \
  "uninstall exits 0 for empty hooks object" \
  "uninstall exited $rc for empty hooks object"
if diff -q "$TMP_DIR/settings.json" "$TMP_DIR/settings-before.json" >/dev/null 2>&1; then
  pass "U074" "settings file unchanged for empty hooks object"
else
  fail "U074" "settings file was modified for empty hooks object"
fi
backup_count=$(find "$TMP_DIR" -name 'settings.json.backup-*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$backup_count" -eq 0 ]; then
  pass "U074" "no backup created for empty hooks object"
else
  fail "U074" "backup was created for empty hooks object ($backup_count found)"
fi
case "$output" in
  *"Removed"*)
    fail "U074" "output falsely claims hooks were removed"
    ;;
  *)
    pass "U074" "no false removal claim"
    ;;
esac

# ===========================================================================

finish
