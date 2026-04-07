#!/bin/sh

set -e

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"

"$SCRIPT_DIR/test-notify-activate.sh"
"$SCRIPT_DIR/test-uninstall-hooks.sh"
