#!/usr/bin/env bash
# Smoke test: verify the symlink chain direction for make install-skills.
# Agents dir gets real copies; Claude and Codex dirs symlink to agents.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

AGENTS="$TMP/agents" CLAUDE="$TMP/claude" CODEX="$TMP/codex"

make -C "$REPO_DIR" install-skills \
  AGENTS_SKILLS_DIR="$AGENTS" CLAUDE_SKILLS_DIR="$CLAUDE" CODEX_SKILLS_DIR="$CODEX"

fail=0
for skill in "$REPO_DIR"/skills/*/; do
  s="$(basename "$skill")"
  [[ -d "$AGENTS/$s" && ! -L "$AGENTS/$s" ]] || { echo "FAIL: $AGENTS/$s not a real dir"; fail=1; }
  [[ "$(readlink "$CLAUDE/$s")" == "$AGENTS/$s" ]] || { echo "FAIL: claude/$s wrong target"; fail=1; }
  [[ "$(readlink "$CODEX/$s")" == "$AGENTS/$s" ]] || { echo "FAIL: codex/$s wrong target"; fail=1; }
done

(( fail )) && exit 1
echo "OK: symlink chain verified"
