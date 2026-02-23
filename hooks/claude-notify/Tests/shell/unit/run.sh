#!/bin/sh

set -e

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"

"$PROJECT_DIR/tests/shell/unit/test-notify-activate.sh"
