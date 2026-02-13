#!/bin/sh

set -eu

usage() {
  cat <<'USAGE'
Usage: check-docstring-coverage.sh [--min <percent>] [<path> ...]

Checks Swift docstring coverage for declarations in the provided paths.
Defaults to: Sources Tests
USAGE
}

min=80

while [ "$#" -gt 0 ]; do
  case "$1" in
    --min)
      shift
      if [ "$#" -eq 0 ]; then
        echo "Missing value for --min" >&2
        usage >&2
        exit 1
      fi
      min="$1"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
    *)
      break
      ;;
  esac
  shift
done

if ! awk -v value="$min" 'BEGIN { exit(value ~ /^[0-9]+([.][0-9]+)?$/ ? 0 : 1) }'; then
  echo "Invalid --min value: $min" >&2
  exit 1
fi

if [ "$#" -eq 0 ]; then
  set -- Sources Tests
fi

tmp_files=$(mktemp)
trap 'rm -f "$tmp_files"' EXIT INT TERM HUP

for path in "$@"; do
  if [ -d "$path" ]; then
    if command -v rg >/dev/null 2>&1; then
      rg --files "$path" -g '*.swift' >> "$tmp_files"
    else
      find "$path" -type f -name '*.swift' >> "$tmp_files"
    fi
  elif [ -f "$path" ]; then
    case "$path" in
      *.swift)
        printf '%s\n' "$path" >> "$tmp_files"
        ;;
    esac
  fi
done

sort -u "$tmp_files" -o "$tmp_files"

if [ ! -s "$tmp_files" ]; then
  echo "No Swift files found in paths: $*" >&2
  exit 1
fi

# shellcheck disable=SC2046
set +e
awk -v min="$min" '
  BEGIN {
    declarationPattern = "^((public|internal|private|fileprivate|open|final|static|class|override|required|convenience|mutating|nonmutating|@preconcurrency)[[:space:]]+)*(enum|struct|class|protocol|func|init)([[:space:](]|$)"
    total = 0
    documented = 0
    missingCount = 0
  }

  function trim(value) {
    sub(/^[[:space:]]+/, "", value)
    sub(/[[:space:]]+$/, "", value)
    return value
  }

  FNR == 1 {
    previousNonEmpty = ""
  }

  {
    rawLine = $0
    trimmedLine = trim($0)

    if (rawLine ~ /^[ ]{0,2}/ && trimmedLine ~ declarationPattern) {
      total += 1
      if (previousNonEmpty ~ /^[[:space:]]*\/\/\//) {
        documented += 1
      } else {
        missingCount += 1
        missing[missingCount] = FILENAME ":" FNR ":" trimmedLine
      }
    }

    if ($0 !~ /^[[:space:]]*$/) {
      previousNonEmpty = $0
    }
  }

  END {
    coverage = (total == 0) ? 0 : (documented * 100.0 / total)

    print "Docstring coverage report"
    print "Total declarations: " total
    print "Documented declarations: " documented
    printf "Coverage: %.2f%%\n", coverage
    print "Undocumented declarations:"

    if (missingCount == 0) {
      print "(none)"
    } else {
      for (i = 1; i <= missingCount; i += 1) {
        print missing[i]
      }
    }

    if (coverage + 1e-9 < min + 0) {
      exit 2
    }
  }
' $(cat "$tmp_files")
status=$?
set -e
if [ "$status" -eq 2 ]; then
  echo "Docstring coverage check failed: coverage is below $min%." >&2
fi
exit "$status"
