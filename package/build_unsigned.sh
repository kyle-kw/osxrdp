#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SIGNING_MODE=adhoc exec "$ROOT/package/build_package.sh" "$@"
