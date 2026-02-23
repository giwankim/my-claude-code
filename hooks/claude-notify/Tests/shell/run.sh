#!/bin/sh

set -e

PROJECT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)"

"$PROJECT_DIR/Tests/shell/integration/run.sh"
"$PROJECT_DIR/Tests/shell/e2e/run.sh"
