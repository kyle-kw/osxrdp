#!/bin/bash
# Authoritative Release package builder.
# SIGNING_MODE=adhoc creates a CI/smoke-test package.
# SIGNING_MODE=release requires APPLICATION_SIGNING_IDENTITY,
# INSTALLER_SIGNING_IDENTITY, and NOTARY_PROFILE.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SIGNING_MODE="${SIGNING_MODE:-adhoc}"
CONFIGURATION="${CONFIGURATION:-Release}"
if [[ "$CONFIGURATION" != "Release" ]]; then
  echo "ERROR: package builds must use Release (got $CONFIGURATION)"
  exit 1
fi
if [[ "$SIGNING_MODE" != "adhoc" && "$SIGNING_MODE" != "release" ]]; then
  echo "ERROR: SIGNING_MODE must be adhoc or release"
  exit 1
fi

# Do not allow environment overrides to turn the installer build back into a
# development build. Authentication is identical in every configuration, but
# packages must still be optimized, non-testable Release artifacts.
UNSAFE_FLAGS="${GCC_PREPROCESSOR_DEFINITIONS:-} ${OTHER_CFLAGS:-} ${OTHER_CPLUSPLUSFLAGS:-} ${CFLAGS:-} ${CXXFLAGS:-}"
if [[ "${DEBUG:-0}" != "0" || "${ENABLE_TESTABILITY:-NO}" == "YES" ||
      "$UNSAFE_FLAGS" =~ (^|[[:space:]])-?D?DEBUG([=[:space:]]|$) ]]; then
  echo "ERROR: unsafe Debug/testability override detected in package build environment"
  exit 1
fi

BUILD_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/osxrdp-package.XXXXXX")"
trap 'status=$?; rm -rf "$BUILD_ROOT"; exit "$status"' EXIT
SYMROOT="$BUILD_ROOT/Build/Products"
OBJROOT="$BUILD_ROOT/Build/Intermediates"
# osxrdp packages target Apple Silicon only.
ARCHS="${ARCHS:-arm64}"
VERSION="${VERSION:-3.2.1}"
if [[ "$ARCHS" != "arm64" ]]; then
  echo "ERROR: only arm64 package builds are supported (got $ARCHS)"
  exit 1
fi
PKG_ID="com.byungho.osxrdp.setup"
COMPONENT_PKG="osxrdp_component.pkg"

DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
USE_REAL_IDENTITY=0
if [[ "$SIGNING_MODE" == "release" ]]; then
  : "${APPLICATION_SIGNING_IDENTITY:?APPLICATION_SIGNING_IDENTITY is required for release signing}"
  : "${INSTALLER_SIGNING_IDENTITY:?INSTALLER_SIGNING_IDENTITY is required for release signing}"
  : "${NOTARY_PROFILE:?NOTARY_PROFILE is required for release signing}"
  : "${DEVELOPMENT_TEAM:?DEVELOPMENT_TEAM is required for release signing}"
  CODE_SIGN_IDENTITY="$APPLICATION_SIGNING_IDENTITY"
  USE_REAL_IDENTITY=1
  OUTPUT_PKG="osxrdp_installer_v${VERSION}_signed.pkg"
  ENABLE_HARDENED_RUNTIME=YES
else
  CODE_SIGN_IDENTITY="-"
  OUTPUT_PKG="osxrdp_installer_v${VERSION}_unsigned.pkg"
  ENABLE_HARDENED_RUNTIME=NO
fi

echo "=== osxrdp package build ==="
echo "ROOT=$ROOT"
echo "SYMROOT=$SYMROOT"
echo "ARCHS=$ARCHS"
echo "VERSION=$VERSION"
echo "SIGNING_MODE=$SIGNING_MODE"
echo "CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY"
echo "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-(none)}"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"

# Shared settings so libScreenMirrorLib.a / sessionmanager land in the same products dir.
COMMON=(
  -quiet
  -configuration "$CONFIGURATION"
  -destination "generic/platform=macOS"
  ARCHS="$ARCHS"
  ONLY_ACTIVE_ARCH=NO
  SYMROOT="$SYMROOT"
  OBJROOT="$OBJROOT"
  MACOSX_DEPLOYMENT_TARGET=12.4
  CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY"
  CODE_SIGNING_ALLOWED=YES
  CODE_SIGNING_REQUIRED=YES
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"
  PROVISIONING_PROFILE_SPECIFIER=
  ENABLE_HARDENED_RUNTIME="$ENABLE_HARDENED_RUNTIME"
)

# codesign with optional hardened-runtime flags (real identity only).
do_codesign() {
  # usage: do_codesign [extra codesign args...] <path>
  local path="${*: -1}"
  local args=("${@:1:$#-1}")
  if [[ "$USE_REAL_IDENTITY" -eq 1 ]]; then
    codesign --force --sign "$CODE_SIGN_IDENTITY" --timestamp --options runtime "${args[@]}" "$path"
  else
    codesign --force --sign "$CODE_SIGN_IDENTITY" "${args[@]}" "$path"
  fi
}

# Re-sign a single Mach-O with a stable identifier so IPC can trust it.
# Usage: resign_binary <path> <identifier>
resign_binary() {
  local path="$1"
  local identifier="$2"
  if [[ ! -f "$path" && ! -d "$path" ]]; then
    echo "WARNING: resign skip missing path: $path"
    return 0
  fi
  echo "  codesign -i $identifier  $path"
  do_codesign -i "$identifier" "$path"
}

# Re-sign OSXRDP.app in dependency order: nested tools first, then the bundle.
resign_osxrdp_app() {
  local app="$1"
  local macos="$app/Contents/MacOS"

  echo "=== Re-signing $app (identity=$CODE_SIGN_IDENTITY) ==="

  # xrdp identifier MUST be exactly "xrdp" — sessionmanager/MirrorAppServer trust it.
  if [[ -x "$macos/xrdp" ]]; then
    resign_binary "$macos/xrdp" "xrdp"
  else
    echo "ERROR: xrdp missing in app bundle: $macos/xrdp"
    return 1
  fi

  if [[ -x "$macos/xrdp-keygen" ]]; then
    resign_binary "$macos/xrdp-keygen" "xrdp-keygen"
  fi

  if [[ -x "$macos/osxrdp_sessionmanager" ]]; then
    resign_binary "$macos/osxrdp_sessionmanager" "com.byungho.osxrdp.sessionmanager"
  fi

  if [[ -x "$macos/OSXRDP" ]]; then
    resign_binary "$macos/OSXRDP" "com.byungho.osxrdp.mainapp"
  fi

  # Seal the .app last WITHOUT --deep.
  # --deep -i <id> re-signs nested Mach-Os with the same identifier and overwrites
  # xrdp / sessionmanager ids (breaks IPC trust and can trigger Launch Constraint
  # Violation when a LaunchDaemon binary claims the GUI app's identity).
  do_codesign -i "com.byungho.osxrdp.mainapp" "$app"

  echo "--- codesign verify ---"
  codesign -dv --verbose=2 "$macos/xrdp" 2>&1 | grep -E 'Identifier|TeamIdentifier|Signature' || true
  codesign -dv --verbose=2 "$macos/osxrdp_sessionmanager" 2>&1 | grep -E 'Identifier|TeamIdentifier|Signature' || true
  codesign --verify --strict --verbose=2 "$app"

  require_identifier "$macos/xrdp" "xrdp"
  require_identifier "$macos/osxrdp_sessionmanager" "com.byungho.osxrdp.sessionmanager"
  require_identifier "$macos/OSXRDP" "com.byungho.osxrdp.mainapp"
}

require_identifier() {
  local path="$1"
  local expected="$2"
  local actual
  actual="$(codesign -dv "$path" 2>&1 | awk -F= '/^Identifier=/{print $2; exit}')"
  if [[ "$actual" != "$expected" ]]; then
    echo "ERROR: $path Identifier is '$actual' (expected '$expected')"
    return 1
  fi
}

thin_to_arm64() {
  local path="$1"
  local binary_archs
  binary_archs="$(lipo -archs "$path")"
  if [[ "$binary_archs" == "arm64" ]]; then
    return 0
  fi
  if [[ " $binary_archs " != *" arm64 "* ]]; then
    echo "ERROR: $path has no arm64 slice (architectures: $binary_archs)"
    return 1
  fi

  local temporary="$path.arm64"
  lipo "$path" -thin arm64 -output "$temporary"
  chmod 755 "$temporary"
  mv -f "$temporary" "$path"
  if [[ "$(lipo -archs "$path")" != "arm64" ]]; then
    echo "ERROR: failed to produce arm64-only binary: $path"
    return 1
  fi
}

mkdir -p "$SYMROOT" "$OBJROOT" osxup/Log

echo "=== [1/6] ScreenMirrorLib ==="
xcodebuild -project ScreenMirrorLib/ScreenMirrorLib.xcodeproj \
  -scheme ScreenMirrorLib \
  -derivedDataPath "$BUILD_ROOT/DerivedData/ScreenMirrorLib" \
  "${COMMON[@]}" \
  build

echo "=== [2/6] osxrdp_sessionmanager ==="
xcodebuild -project osxrdp_sessionmanager/osxrdp_sessionmanager.xcodeproj \
  -scheme osxrdp_sessionmanager \
  -derivedDataPath "$BUILD_ROOT/DerivedData/sessionmanager" \
  "${COMMON[@]}" \
  build

echo "=== [3/6] osxup (libosxup.dylib) ==="
xcodebuild -project osxup/osxup.xcodeproj \
  -scheme osxup \
  -derivedDataPath "$BUILD_ROOT/DerivedData/osxup" \
  "${COMMON[@]}" \
  build

echo "=== [4/6] OSXRDP.app ==="
xcodebuild -project ServerApp/OSXRDP.xcodeproj \
  -scheme OSXRDP \
  -derivedDataPath "$BUILD_ROOT/DerivedData/OSXRDP" \
  "${COMMON[@]}" \
  build

echo "=== [5/6] OSXRDPUninstaller.app ==="
xcodebuild -project OSXRDPUninstaller/OSXRDPUninstaller.xcodeproj \
  -scheme OSXRDPUninstaller \
  -derivedDataPath "$BUILD_ROOT/DerivedData/Uninstaller" \
  "${COMMON[@]}" \
  build

PRODUCTS="$SYMROOT/$CONFIGURATION"
echo "Products dir: $PRODUCTS"
ls -la "$PRODUCTS"

test -d "$PRODUCTS/OSXRDP.app"
test -d "$PRODUCTS/OSXRDPUninstaller.app"
test -f "$PRODUCTS/libosxup.dylib"
test -f "$PRODUCTS/osxrdp_sessionmanager"

STAGE_DIR="$BUILD_ROOT/Stage"
mkdir -p "$STAGE_DIR/module"
cp -R "$PRODUCTS/OSXRDP.app" "$STAGE_DIR/"
cp -R "$PRODUCTS/OSXRDPUninstaller.app" "$STAGE_DIR/"
cp "$PRODUCTS/libosxup.dylib" "$STAGE_DIR/module/libosxup.dylib"

# Ensure sessionmanager is embedded (build phase may no-op without shared products).
if [[ ! -x "$STAGE_DIR/OSXRDP.app/Contents/MacOS/osxrdp_sessionmanager" ]]; then
  echo "Embedding osxrdp_sessionmanager into OSXRDP.app"
  cp "$PRODUCTS/osxrdp_sessionmanager" "$STAGE_DIR/OSXRDP.app/Contents/MacOS/"
  chmod +x "$STAGE_DIR/OSXRDP.app/Contents/MacOS/osxrdp_sessionmanager"
fi

# xrdp binaries should already be copied into the app by the Xcode Copy Files phase.
if [[ ! -x "$STAGE_DIR/OSXRDP.app/Contents/MacOS/xrdp" ]]; then
  echo "WARNING: xrdp missing inside OSXRDP.app; copying from ServerApp/"
  cp ServerApp/xrdp ServerApp/xrdp-keygen "$STAGE_DIR/OSXRDP.app/Contents/MacOS/"
  chmod +x "$STAGE_DIR/OSXRDP.app/Contents/MacOS/xrdp" \
           "$STAGE_DIR/OSXRDP.app/Contents/MacOS/xrdp-keygen"
fi

# The vendored xrdp tools may still be universal. Remove their legacy x86_64
# slices before signing so the final package is entirely arm64-only.
thin_to_arm64 "$STAGE_DIR/OSXRDP.app/Contents/MacOS/xrdp"
thin_to_arm64 "$STAGE_DIR/OSXRDP.app/Contents/MacOS/xrdp-keygen"

# Force stable signing identifiers. Xcode CodeSignOnCopy on ad-hoc often produces
# Identifier=xrdp-<hash>, which fails IPC trust (expects exact "xrdp").
resign_osxrdp_app "$STAGE_DIR/OSXRDP.app"
resign_binary "$STAGE_DIR/module/libosxup.dylib" "libosxup.dylib"
if [[ -d "$STAGE_DIR/OSXRDPUninstaller.app" ]]; then
  do_codesign -i "com.byungho.osxrdp.uninstaller" "$STAGE_DIR/OSXRDPUninstaller.app"
fi

echo "=== [6/6] Build pkg ($OUTPUT_PKG) ==="
PAYLOAD_DIR="$BUILD_ROOT/Payload"
SCRIPTS_DIR="$ROOT/package/scripts"
SOURCE_DIR="$ROOT/package/source"
DIST_XML="$ROOT/package/distribution.xml"
COMPONENT_PATH="$BUILD_ROOT/$COMPONENT_PKG"
OUTPUT_PATH="$ROOT/package/$OUTPUT_PKG"

rm -f "$OUTPUT_PATH"

mkdir -p "$PAYLOAD_DIR/Applications/osxrdp"
mkdir -p "$PAYLOAD_DIR/Library/LaunchDaemons"
mkdir -p "$PAYLOAD_DIR/Library/LaunchAgents"
mkdir -p "$PAYLOAD_DIR/etc/xrdp"
mkdir -p "$PAYLOAD_DIR/etc/osxrdp"
mkdir -p "$PAYLOAD_DIR/usr/local/lib/xrdp"
mkdir -p "$PAYLOAD_DIR/usr/local/share/xrdp"

cp -R "$STAGE_DIR/OSXRDP.app" "$PAYLOAD_DIR/Applications/osxrdp/"
cp -R "$STAGE_DIR/OSXRDPUninstaller.app" "$PAYLOAD_DIR/Applications/osxrdp/"
cp "$SOURCE_DIR/com.byungho.osxrdp.plist" "$PAYLOAD_DIR/Library/LaunchDaemons/"
cp "$SOURCE_DIR/com.byungho.osxrdp.sessionmanager.plist" "$PAYLOAD_DIR/Library/LaunchDaemons/"
cp "$SOURCE_DIR/com.byungho.osxrdp.lockscreen.plist" "$PAYLOAD_DIR/Library/LaunchAgents/"
cp -R "$SOURCE_DIR/config/"* "$PAYLOAD_DIR/etc/xrdp/"
cp -R "$SOURCE_DIR/log/"* "$PAYLOAD_DIR/etc/osxrdp/"
cp "$STAGE_DIR/module/libosxup.dylib" "$PAYLOAD_DIR/usr/local/lib/xrdp/"
cp "$SOURCE_DIR/resources/"* "$PAYLOAD_DIR/usr/local/share/xrdp/"

# Match packaging.sh permissions as closely as possible without requiring a real root tree.
chmod -R a+rX "$PAYLOAD_DIR"
chmod 755 "$SCRIPTS_DIR/postinstall"

pkgbuild --root "$PAYLOAD_DIR" \
         --install-location "/" \
         --ownership recommended \
         --scripts "$SCRIPTS_DIR" \
         --identifier "$PKG_ID" \
         --version "$VERSION" \
         "$COMPONENT_PATH"

if [[ "$SIGNING_MODE" == "release" ]]; then
  productbuild --distribution "$DIST_XML" \
               --package-path "$BUILD_ROOT" \
               --sign "$INSTALLER_SIGNING_IDENTITY" \
               "$OUTPUT_PATH"
  xcrun notarytool submit "$OUTPUT_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$OUTPUT_PATH"
else
  productbuild --distribution "$DIST_XML" \
               --package-path "$BUILD_ROOT" \
               "$OUTPUT_PATH"
fi

echo "=== Done ==="
echo "Package: $OUTPUT_PATH"
ls -lh "$OUTPUT_PATH"
