#!/bin/sh

set -e

HOOKS_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
exec "$HOOKS_DIR/tests/shell/run.sh" "$@"
