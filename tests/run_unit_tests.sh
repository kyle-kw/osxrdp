#!/bin/bash
# Build and run lightweight unit tests (macOS / clang).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "Unit tests require macOS (clang + system frameworks). Skipping on $(uname -s)."
  exit 0
fi

CC="${CC:-clang}"
OUT="${TMPDIR:-/tmp}/osxrdp-unit-tests-$$"
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' EXIT

CFLAGS=(
  -std=c11
  -Wall
  -Wextra
  -Wno-unused-parameter
  -I"$ROOT/tests"
  -I"$ROOT/ScreenMirrorLib"
  -I"$ROOT/ScreenMirrorLib/osxrdp"
)

echo "=== osxrdp unit tests ==="
echo "CC=$CC"
echo "OUT=$OUT"

failures=0

build_and_run() {
  local name="$1"
  shift
  echo ""
  echo "-- building $name --"
  if ! "$CC" "${CFLAGS[@]}" "$@" -o "$OUT/$name"; then
    echo "FAIL compile $name"
    failures=$((failures + 1))
    return
  fi
  if ! "$OUT/$name"; then
    failures=$((failures + 1))
  fi
}

build_and_run test_xstream \
  "$ROOT/tests/test_xstream.c" \
  "$ROOT/ScreenMirrorLib/xstream.c"

build_and_run test_utils_name \
  "$ROOT/tests/test_utils_name.c" \
  "$ROOT/ScreenMirrorLib/utils.c" \
  -framework CoreFoundation \
  -framework CoreGraphics

build_and_run test_xshm_name \
  "$ROOT/tests/test_xshm_name.c" \
  "$ROOT/ScreenMirrorLib/xshm.c"

echo ""
echo "-- test_strings.sh --"
if ! bash "$ROOT/tests/test_strings.sh"; then
  failures=$((failures + 1))
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
  echo "=== ALL UNIT TESTS PASSED ==="
  exit 0
fi
echo "=== UNIT TESTS FAILED ($failures) ==="
exit 1
