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
trap 'status=$?; rm -rf "$OUT"; exit "$status"' EXIT

CFLAGS=(
  -std=c11
  -Wall
  -Wextra
  -Wno-unused-parameter
  -I"$ROOT/tests"
  -I"$ROOT/ScreenMirrorLib"
  -I"$ROOT/ScreenMirrorLib/osxrdp"
)

CXX="${CXX:-clang++}"
CXXFLAGS=(
  -std=gnu++20
  -Wall
  -Wextra
  -Wno-unused-parameter
  -I"$ROOT/tests"
  -I"$ROOT/ScreenMirrorLib"
  -I"$ROOT/ScreenMirrorLib/osxrdp"
  -I"$ROOT/osxup"
  -I"$ROOT/osxup/xrdp"
)

OBJCFLAGS=(
  -x objective-c++
  -fobjc-arc
  -std=gnu++20
  -Wall
  -Wextra
  -Wno-unused-parameter
  -I"$ROOT/tests"
  -I"$ROOT/ScreenMirrorLib"
  -I"$ROOT/ScreenMirrorLib/osxrdp"
  -I"$ROOT/osxup"
  -I"$ROOT/osxup/xrdp"
  -I"$ROOT/ServerApp/OSXRDP"
  -framework Foundation
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

build_and_run_cxx() {
  local name="$1"
  shift
  echo ""
  echo "-- building $name (C++) --"
  # Compile .c sources as C (void* arithmetic is invalid in C++ mode).
  local cxx_srcs=()
  local c_objs=()
  local arg
  for arg in "$@"; do
    case "$arg" in
      *.c)
        local base
        base="$(basename "$arg" .c)"
        if ! "$CC" "${CFLAGS[@]}" -c "$arg" -o "$OUT/${name}_${base}.o"; then
          echo "FAIL compile $name ($arg as C)"
          failures=$((failures + 1))
          return
        fi
        c_objs+=("$OUT/${name}_${base}.o")
        ;;
      *)
        cxx_srcs+=("$arg")
        ;;
    esac
  done
  if [[ "${#c_objs[@]}" -gt 0 ]]; then
    "$CXX" "${CXXFLAGS[@]}" "${cxx_srcs[@]}" "${c_objs[@]}" -o "$OUT/$name" || {
      echo "FAIL compile $name"
      failures=$((failures + 1))
      return
    }
  elif ! "$CXX" "${CXXFLAGS[@]}" "${cxx_srcs[@]}" -o "$OUT/$name"; then
    echo "FAIL compile $name"
    failures=$((failures + 1))
    return
  fi
  if ! "$OUT/$name"; then
    failures=$((failures + 1))
  fi
}

build_and_run_objc() {
  local name="$1"
  shift
  echo ""
  echo "-- building $name (ObjC++) --"
  if ! "$CXX" "${OBJCFLAGS[@]}" "$@" -o "$OUT/$name"; then
    echo "FAIL compile $name"
    failures=$((failures + 1))
    return
  fi
  if ! "$OUT/$name"; then
    failures=$((failures + 1))
  fi
}

build_and_run_ipc_bundle() {
  local name="test_ipc_bundle_identity"
  local app="$OUT/IPCBundlePeer.app"
  local executable="$app/Contents/MacOS/ipc_bundle_peer"
  local info_plist="$app/Contents/Info.plist"

  echo ""
  echo "-- building $name (ad-hoc app bundle) --"
  mkdir -p "$app/Contents/MacOS"
  plutil -create xml1 "$info_plist"
  plutil -insert CFBundleExecutable -string ipc_bundle_peer "$info_plist"
  plutil -insert CFBundleIdentifier -string com.byungho.osxrdp.testpeer "$info_plist"
  plutil -insert CFBundleName -string IPCBundlePeer "$info_plist"
  plutil -insert CFBundlePackageType -string APPL "$info_plist"
  plutil -insert CFBundleVersion -string 1 "$info_plist"

  if ! "$CC" "${CFLAGS[@]}" \
    "$ROOT/tests/test_ipc_bundle_identity.c" \
    "$ROOT/ScreenMirrorLib/ipc.c" \
    -framework Security -framework CoreFoundation -lpthread \
    -o "$executable"; then
    echo "FAIL compile $name"
    failures=$((failures + 1))
    return
  fi

  if ! codesign --force --sign - "$app"; then
    echo "FAIL sign $name"
    failures=$((failures + 1))
    return
  fi

  if ! "$executable"; then
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

build_and_run test_ipc \
  "$ROOT/tests/test_ipc.c" \
  "$ROOT/ScreenMirrorLib/ipc.c" \
  -framework Security \
  -framework CoreFoundation \
  -lpthread

build_and_run_ipc_bundle

build_and_run test_session_protocol \
  "$ROOT/tests/test_session_protocol.c" \
  "$ROOT/ScreenMirrorLib/xstream.c" \
  "$ROOT/ScreenMirrorLib/utils.c" \
  -framework CoreFoundation \
  -framework CoreGraphics

if [[ "${RUN_TSAN:-0}" == "1" ]]; then
  echo ""
  echo "-- building test_ipc (Thread Sanitizer) --"
  "$CC" "${CFLAGS[@]}" -fsanitize=thread \
    "$ROOT/tests/test_ipc.c" "$ROOT/ScreenMirrorLib/ipc.c" \
    -framework Security -framework CoreFoundation -lpthread \
    -o "$OUT/test_ipc_tsan"
  TSAN_OPTIONS="halt_on_error=1" "$OUT/test_ipc_tsan"
fi

build_and_run_cxx test_status_manager \
  "$ROOT/tests/test_status_manager.cpp" \
  "$ROOT/osxup/Status/StatusManager.cpp"

build_and_run_cxx test_inflight_tracker \
  "$ROOT/tests/test_inflight_tracker.cpp" \
  "$ROOT/osxup/Paint/InFlightTracker.cpp"

build_and_run_cxx test_command_packing \
  "$ROOT/tests/test_command_packing.cpp" \
  "$ROOT/osxup/Command/Command.cpp" \
  "$ROOT/ScreenMirrorLib/xstream.c"

build_and_run_cxx test_connection_state \
  "$ROOT/tests/test_connection_state.cpp" \
  "$ROOT/ServerApp/OSXRDP/Utils/ConnectionState.cpp"

build_and_run_objc test_inset_card_view \
  "$ROOT/tests/test_inset_card_view.mm" \
  "$ROOT/ServerApp/OSXRDP/UI/InsetCardView.m" \
  -framework AppKit

build_and_run_objc test_clip_protocol \
  "$ROOT/tests/test_clip_protocol.mm" \
  "$ROOT/ServerApp/OSXRDP/Clipboard/ClipProtocol.mm"

echo ""
echo "-- test_strings.sh --"
if ! bash "$ROOT/tests/test_strings.sh"; then
  failures=$((failures + 1))
fi

echo ""
echo "-- test_install_helpers.sh --"
if ! bash "$ROOT/tests/test_install_helpers.sh"; then
  failures=$((failures + 1))
fi

echo ""
if [[ "$failures" -eq 0 ]]; then
  echo "=== ALL UNIT TESTS PASSED ==="
  exit 0
fi
echo "=== UNIT TESTS FAILED ($failures) ==="
exit 1
