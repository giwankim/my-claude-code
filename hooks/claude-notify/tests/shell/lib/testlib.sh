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

finish() {
  printf '\nResults: %d passed, %d failed\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ]
}
