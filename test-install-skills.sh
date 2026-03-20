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
skill_count=0
for skill in "$REPO_DIR"/skills/*/; do
  ((++skill_count))
  s="$(basename "$skill")"
  [[ -d "$AGENTS/$s" && ! -L "$AGENTS/$s" ]] || { echo "FAIL: $AGENTS/$s not a real dir"; fail=1; }
  expected="$(cd "$AGENTS/$s" && pwd -P)"
  [[ "$(readlink "$CLAUDE/$s")" == "$expected" ]] || { echo "FAIL: claude/$s wrong target"; fail=1; }
  [[ "$(readlink "$CODEX/$s")" == "$expected" ]] || { echo "FAIL: codex/$s wrong target"; fail=1; }
done

[[ $skill_count -gt 0 ]] || { echo "FAIL: no skills found in skills/"; exit 1; }
if (( fail )); then exit 1; fi
echo "OK: symlink chain verified ($skill_count skills)"
