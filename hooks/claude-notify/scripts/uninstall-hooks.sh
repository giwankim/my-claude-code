#!/bin/sh
# uninstall-hooks.sh — Remove claude-notify hook entries from Claude Code
# settings and optionally delete the installed hook directory.
#
# Usage:
#   uninstall-hooks.sh [--settings <path>] [--install-dir <path>]
#                      [--dry-run] [--hook <event>]... [--all]
#                      [--remove-files]

set -eu

SETTINGS_FILE="${HOME}/.claude/settings.json"
INSTALL_DIR="${HOME}/.claude/hooks/claude-notify"
DRY_RUN=0
REMOVE_FILES=0
HOOK_EVENTS=""   # space-separated list; empty means --all
ALL_MODE=0

usage() {
  printf 'Usage: %s [--settings <path>] [--install-dir <path>] [--dry-run] [--hook <event>]... [--all] [--remove-files]\n' "$(basename "$0")"
  exit "${1:-1}"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --settings)
      [ "$#" -ge 2 ] || usage
      SETTINGS_FILE="$2"; shift 2 ;;
    --install-dir)
      [ "$#" -ge 2 ] || usage
      case "$2" in
        ""|"/"|".")
          printf 'Error: refusing unsafe install directory: %s\n' "$2" >&2
          exit 1
          ;;
      esac
      INSTALL_DIR="$2"; shift 2 ;;
    --dry-run)
      DRY_RUN=1; shift ;;
    --remove-files)
      REMOVE_FILES=1; shift ;;
    --hook)
      [ "$#" -ge 2 ] || usage
      case "$2" in
        ''|*[!A-Za-z0-9_-]*)
          printf 'Invalid hook event name: %s\n' "$2" >&2
          exit 1
          ;;
      esac
      HOOK_EVENTS="${HOOK_EVENTS:+$HOOK_EVENTS }$2"; shift 2 ;;
    --all)
      ALL_MODE=1; shift ;;
    -h|--help)
      usage 0 ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2; usage ;;
  esac
done

# Default to --all when no --hook flags given.
if [ -z "$HOOK_EVENTS" ]; then
  ALL_MODE=1
fi

# Resolve symlinks so we modify the real file, not replace the link.
if [ -L "$SETTINGS_FILE" ]; then
  SETTINGS_FILE=$(perl -MCwd -e 'print Cwd::abs_path(shift)' "$SETTINGS_FILE")
fi

# --- Helper: conditionally remove installed directory ----------------------

maybe_remove_install_dir() {
  # INSTALL_DIR safety is validated at argument-parse time so this helper
  # never encounters an unsafe value and cannot exit(1) mid-operation.
  if [ "$REMOVE_FILES" -eq 1 ] && [ "$ALL_MODE" -eq 1 ]; then
    if [ "$DRY_RUN" -eq 1 ]; then
      if [ -d "$INSTALL_DIR" ]; then printf 'Dry run: would remove install directory: %s\n' "$INSTALL_DIR"; fi
    elif [ -d "$INSTALL_DIR" ]; then
      rm -rf "$INSTALL_DIR"
      printf 'Removed install directory: %s\n' "$INSTALL_DIR"
    fi
  fi
}

# --- Pre-flight checks ----------------------------------------------------

if ! command -v jq >/dev/null 2>&1; then
  printf 'Error: jq is required but not found on PATH.\n' >&2
  exit 1
fi

if [ ! -f "$SETTINGS_FILE" ]; then
  printf 'Settings file not found: %s — nothing to uninstall.\n' "$SETTINGS_FILE"
  maybe_remove_install_dir
  exit 0
fi

if ! jq empty "$SETTINGS_FILE" 2>/dev/null; then
  printf 'Error: %s is not valid JSON.\n' "$SETTINGS_FILE" >&2
  exit 1
fi

# Check whether .hooks exists and is non-empty.
# Note: jq -e '.hooks' is truthy for {}, so we check key count explicitly.
if ! jq -e '.hooks | keys | length > 0' "$SETTINGS_FILE" >/dev/null 2>&1; then
  printf 'No hooks configured in %s — nothing to uninstall.\n' "$SETTINGS_FILE"
  maybe_remove_install_dir
  exit 0
fi

# --- Build jq filter -------------------------------------------------------

NOTIFY_PATTERN='claude-notify/notify\\.sh'

if [ "$ALL_MODE" -eq 1 ]; then
  jq_filter='
    .hooks |= with_entries(
      .value |= [
        .[]
        | .hooks |= [ .[] | select(((.command? // "") | tostring | test("'"$NOTIFY_PATTERN"'")) | not) ]
        | select(.hooks | length > 0)
      ]
      | select(.value | length > 0)
    )
    | if (.hooks | length) == 0 then del(.hooks) else . end
  '
else
  # Build a per-key filter for each --hook event.
  # Start with identity and chain per-key removals.
  # NOTE: The jq filter below is intentionally a single line. Multi-line
  # construction via string concatenation causes shell tools (sed, etc.) to
  # strip jq pipe operators from intermediate lines; keeping it on one line
  # avoids that class of bug entirely.
  jq_filter="."
  for event_key in $HOOK_EVENTS; do
    jq_filter="${jq_filter}"' | if .hooks["'"${event_key}"'"] then .hooks["'"${event_key}"'"] |= [.[] | .hooks |= [.[] | select(((.command? // "") | tostring | test("'"${NOTIFY_PATTERN}"'")) | not)] | select(.hooks | length > 0)] | if (.hooks["'"${event_key}"'"] | length) == 0 then del(.hooks["'"${event_key}"'"]) else . end else . end'
  done
  # Clean up empty .hooks object.
  jq_filter="${jq_filter}"' | if (.hooks | length) == 0 then del(.hooks) else . end'
fi

# --- Apply filter and check for changes ------------------------------------

new_content=$(jq "$jq_filter" "$SETTINGS_FILE")

# Validate output.
if ! printf '%s\n' "$new_content" | jq empty 2>/dev/null; then
  printf 'Error: jq produced invalid JSON output. Aborting.\n' >&2
  exit 1
fi

# Normalize for comparison (compact both).
old_compact=$(jq -cS '.' "$SETTINGS_FILE")
new_compact=$(printf '%s\n' "$new_content" | jq -cS '.')

if [ "$old_compact" = "$new_compact" ]; then
  printf 'No claude-notify hooks found in %s — nothing to uninstall.\n' "$SETTINGS_FILE"
  maybe_remove_install_dir
  exit 0
fi

# --- Identify what will be removed (for reporting) -------------------------

if [ "$ALL_MODE" -eq 1 ]; then
  removed_events=$(jq -r '
    .hooks | to_entries[]
    | select(.value | any(.[].hooks[]; ((.command? // "") | tostring | test("'"$NOTIFY_PATTERN"'"))))
    | .key
  ' "$SETTINGS_FILE" | tr '\n' ' ')
else
  removed_events=""
  for _ev in $HOOK_EVENTS; do
    if jq -e --arg k "$_ev" '.hooks[$k] // [] | any(.[].hooks[]; ((.command? // "") | tostring | test("'"$NOTIFY_PATTERN"'")))' "$SETTINGS_FILE" >/dev/null 2>&1; then
      removed_events="${removed_events:+$removed_events }$_ev"
    fi
  done
fi

# --- Dry-run mode -----------------------------------------------------------

if [ "$DRY_RUN" -eq 1 ]; then
  printf 'Dry run: would remove claude-notify hooks from event(s): %s\n' "$removed_events"
  maybe_remove_install_dir
  exit 0
fi

# --- Write changes atomically -----------------------------------------------

# Backup.
timestamp=$(date +%Y%m%dT%H%M%S)
backup_file="${SETTINGS_FILE}.backup-${timestamp}"
cp "$SETTINGS_FILE" "$backup_file"

# Write to temp file then atomic move.
settings_dir=$(dirname "$SETTINGS_FILE")
tmp_file=$(mktemp "${settings_dir}/settings.json.tmp.XXXXXX")
trap 'rm -f "$tmp_file"' EXIT HUP INT TERM
printf '%s\n' "$new_content" > "$tmp_file"
mv "$tmp_file" "$SETTINGS_FILE"
trap - EXIT HUP INT TERM

printf 'Removed claude-notify hooks from event(s): %s\n' "$removed_events"
printf 'Backup saved to: %s\n' "$backup_file"

# --- Optionally remove installed files --------------------------------------

maybe_remove_install_dir
