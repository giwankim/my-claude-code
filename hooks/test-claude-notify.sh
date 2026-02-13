#!/bin/sh

set -e

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"

"$ROOT_DIR/hooks/tests/integration/run.sh"
"$ROOT_DIR/hooks/tests/e2e/run.sh"
