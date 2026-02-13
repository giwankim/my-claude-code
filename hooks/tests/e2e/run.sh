#!/bin/sh

set -e

ROOT_DIR="$(CDPATH= cd -- "$(dirname "$0")/../../.." && pwd)"

"$ROOT_DIR/hooks/tests/e2e/test-runtime.sh"
