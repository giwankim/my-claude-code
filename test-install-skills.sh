#!/usr/bin/env bash
# Test that `make install-skills` creates correct symlinks.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
TEST_AGENTS_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_AGENTS_DIR"' EXIT

echo "=== test-install-skills ==="

# Run install-skills with overridden AGENTS_SKILLS_DIR.
make -C "$REPO_DIR" install-skills AGENTS_SKILLS_DIR="$TEST_AGENTS_DIR"

# Collect expected skills from the skills/ directory.
failures=0
for skill_dir in "$REPO_DIR"/skills/*/; do
  skill="$(basename "$skill_dir")"
  link="$TEST_AGENTS_DIR/$skill"

  # Check symlink exists.
  if [[ ! -L "$link" ]]; then
    echo "FAIL: $link is not a symlink"
    failures=$((failures + 1))
    continue
  fi

  # Check symlink target points to the repo skill directory.
  target="$(readlink "$link")"
  expected="$REPO_DIR/skills/$skill"
  if [[ "$target" != "$expected" ]]; then
    echo "FAIL: $link -> $target (expected $expected)"
    failures=$((failures + 1))
    continue
  fi

  echo "OK: $skill -> $target"
done

# Check that at least one skill was found (sanity check).
skill_count=$(find "$REPO_DIR/skills" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
if [[ "$skill_count" -eq 0 ]]; then
  echo "FAIL: no skill directories found in skills/"
  failures=$((failures + 1))
fi

# Check that install-skills overwrites an existing real directory with a symlink.
first_skill="$(basename "$(find "$REPO_DIR/skills" -mindepth 1 -maxdepth 1 -type d | head -1)")"
rm -f "$TEST_AGENTS_DIR/$first_skill"
mkdir -p "$TEST_AGENTS_DIR/$first_skill/nested"
make -C "$REPO_DIR" install-skills AGENTS_SKILLS_DIR="$TEST_AGENTS_DIR" 2>&1
if [[ -L "$TEST_AGENTS_DIR/$first_skill" ]]; then
  echo "OK: real directory replaced with symlink ($first_skill)"
else
  echo "FAIL: $TEST_AGENTS_DIR/$first_skill was not replaced with a symlink"
  failures=$((failures + 1))
fi

# Check idempotency: running install-skills again should succeed.
make -C "$REPO_DIR" install-skills AGENTS_SKILLS_DIR="$TEST_AGENTS_DIR" 2>&1
echo "OK: idempotent re-run succeeded"

if [[ "$failures" -gt 0 ]]; then
  echo "FAILED: $failures test(s) failed"
  exit 1
fi

echo "PASSED: all tests passed"
