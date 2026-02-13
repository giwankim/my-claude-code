#!/bin/sh

set -eu

if [ "$#" -lt 2 ]; then
  echo "Usage: $0 <suite> <path> [<path> ...]" >&2
  exit 1
fi

SUITE="$1"
shift
MANIFEST="Tests/required-cases.txt"

if [ ! -f "$MANIFEST" ]; then
  echo "Manifest not found: $MANIFEST" >&2
  exit 1
fi

has_case_id() {
  pattern="$1"
  path="$2"
  if command -v rg >/dev/null 2>&1; then
    rg -q --fixed-strings "$pattern" "$path"
  else
    grep -R -q --fixed-strings "$pattern" "$path"
  fi
}

current_suite=""
required=0
missing=0

while IFS= read -r line || [ -n "$line" ]; do
  trimmed=$(printf '%s' "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  case "$trimmed" in
    ''|'#'*)
      continue
      ;;
    '['*']')
      current_suite=${trimmed#'['}
      current_suite=${current_suite%']'}
      continue
      ;;
  esac

  [ "$current_suite" = "$SUITE" ] || continue

  required=$((required + 1))
  found=0
  for path in "$@"; do
    if [ -e "$path" ] && has_case_id "$trimmed" "$path" >/dev/null 2>&1; then
      found=1
      break
    fi
  done

  if [ "$found" -eq 0 ]; then
    echo "Missing required case ID '$trimmed' for suite '$SUITE'" >&2
    missing=1
  fi
done < "$MANIFEST"

if [ "$required" -eq 0 ]; then
  echo "No required cases defined for suite '$SUITE' in $MANIFEST" >&2
  exit 1
fi

if [ "$missing" -ne 0 ]; then
  exit 1
fi

echo "Required case check passed for suite '$SUITE' ($required IDs)."
