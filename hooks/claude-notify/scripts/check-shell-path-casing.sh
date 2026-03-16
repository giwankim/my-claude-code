#!/bin/sh

set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)"
PATTERN='tests/shell/'

if command -v rg >/dev/null 2>&1; then
  matches=$(rg --line-number --fixed-strings "$PATTERN" \
    "$PROJECT_DIR/Makefile" \
    "$PROJECT_DIR/README.md" \
    "$PROJECT_DIR/AGENTS.md" \
    "$PROJECT_DIR/Tests/shell" \
    "$PROJECT_DIR/scripts" | grep -v '/scripts/check-shell-path-casing.sh:' || true)
else
  matches=$(grep -R -n --fixed-strings "$PATTERN" \
    "$PROJECT_DIR/Makefile" \
    "$PROJECT_DIR/README.md" \
    "$PROJECT_DIR/AGENTS.md" \
    "$PROJECT_DIR/Tests/shell" \
    "$PROJECT_DIR/scripts" | grep -v 'scripts/check-shell-path-casing.sh' || true)
fi

if [ -n "$matches" ]; then
  printf '%s\n' "$matches" >&2
  echo "Found lowercase shell-test path references. Use 'Tests/shell/' in module scripts/docs/Makefile." >&2
  exit 1
fi

echo "Shell path casing check passed."
