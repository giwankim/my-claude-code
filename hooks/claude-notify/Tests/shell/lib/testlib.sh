#!/bin/sh

PASS=0
FAIL=0

pass() {
  PASS=$((PASS + 1))
  printf '  PASS [%s]: %s\n' "$1" "$2"
}

fail() {
  FAIL=$((FAIL + 1))
  printf '  FAIL [%s]: %s\n' "$1" "$2"
}

case_start() {
  printf 'Case %s: %s\n' "$1" "$2"
}

now_ms() {
  perl -MTime::HiRes=time -e 'printf "%.0f\n", time() * 1000'
}

wait_for_pid_file() {
  pid_file="$1"
  max_tries="${2:-50}"
  i=0
  while [ "$i" -lt "$max_tries" ]; do
    [ -s "$pid_file" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

wait_for_pid_removed() {
  pid_file="$1"
  max_tries="${2:-50}"
  i=0
  while [ "$i" -lt "$max_tries" ]; do
    [ ! -e "$pid_file" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

wait_for_process_exit() {
  pid="$1"
  max_tries="${2:-50}"
  i=0
  while [ "$i" -lt "$max_tries" ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

wait_for_file() {
  file="$1"
  max_tries="${2:-30}"
  i=0
  while [ "$i" -lt "$max_tries" ]; do
    [ -f "$file" ] && return 0
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

wait_for_file_contains() {
  # NOTE: `pattern` is interpreted by grep as a BRE regex (same as assert_file_contains).
  # For literal matching, use fixed-string semantics (for example, grep -qF).
  file="$1"
  pattern="$2"
  max_tries="${3:-30}"
  i=0
  while [ "$i" -lt "$max_tries" ]; do
    if [ -f "$file" ] && grep -q -- "$pattern" "$file" 2>/dev/null; then
      return 0
    fi
    sleep 0.1
    i=$((i + 1))
  done
  return 1
}

finish() {
  printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}

assert_rc_eq() {
  case_id="$1"
  rc="$2"
  expected="$3"
  pass_message="$4"
  fail_message="$5"
  if [ "$rc" -eq "$expected" ]; then
    pass "$case_id" "$pass_message"
  else
    fail "$case_id" "$fail_message"
  fi
}

assert_file_contains() {
  case_id="$1"
  file="$2"
  pattern="$3"
  pass_message="$4"
  fail_message="$5"
  if grep -q -- "$pattern" "$file"; then
    pass "$case_id" "$pass_message"
  else
    fail "$case_id" "$fail_message"
  fi
}

assert_file_not_contains() {
  case_id="$1"
  file="$2"
  pattern="$3"
  pass_message="$4"
  fail_message="$5"
  if grep -q -- "$pattern" "$file" 2>/dev/null; then
    fail "$case_id" "$fail_message"
  else
    pass "$case_id" "$pass_message"
  fi
}
