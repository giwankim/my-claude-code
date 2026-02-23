#!/bin/sh

set -e

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"

"$PROJECT_DIR/Tests/shell/unit/test-notify-activate.sh"
