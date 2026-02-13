#!/bin/sh

set -e

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

"$PROJECT_DIR/tests/shell/integration/run.sh"
"$PROJECT_DIR/tests/shell/e2e/run.sh"
