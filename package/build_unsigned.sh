#!/bin/bash
# Local/CI package build.
#
# Default: ad-hoc sign with stable identifiers (no Apple Developer cert required).
# Optional real signing when you have a cert in Keychain:
#   CODE_SIGN_IDENTITY="Apple Development: You (TEAMID)" \
#   DEVELOPMENT_TEAM=TEAMID \
#   ./package/build_unsigned.sh
#
# IPC trust accepts:
#   - official Team ID 33X7M69J4B + identifier "xrdp"
#   - same Team ID as sessionmanager/OSXRDP (your DEVELOPMENT_TEAM)
#   - ad-hoc identifier "xrdp" installed under /Applications/osxrdp/
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BUILD_ROOT="${BUILD_ROOT:-/tmp/osxrdp-ci}"
SYMROOT="$BUILD_ROOT/Build/Products"
OBJROOT="$BUILD_ROOT/Build/Intermediates"
CONFIGURATION="${CONFIGURATION:-Release}"
# Universal by default (matches package/build_once.sh intent).
ARCHS="${ARCHS:-arm64 x86_64}"
VERSION="${VERSION:-2.0.6}"
PKG_ID="com.byungho.osxrdp.setup"
COMPONENT_PKG="osxrdp_component.pkg"

# Signing: "-" = ad-hoc. Override with a real identity if available.
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"
DEVELOPMENT_TEAM="${DEVELOPMENT_TEAM:-}"
USE_REAL_IDENTITY=0
if [[ "$CODE_SIGN_IDENTITY" != "-" ]]; then
  USE_REAL_IDENTITY=1
  OUTPUT_PKG="osxrdp_installer_v${VERSION}_signed.pkg"
  ENABLE_HARDENED_RUNTIME="${ENABLE_HARDENED_RUNTIME:-YES}"
else
  OUTPUT_PKG="osxrdp_installer_v${VERSION}_unsigned.pkg"
  ENABLE_HARDENED_RUNTIME="${ENABLE_HARDENED_RUNTIME:-NO}"
fi

echo "=== osxrdp package build ==="
echo "ROOT=$ROOT"
echo "SYMROOT=$SYMROOT"
echo "ARCHS=$ARCHS"
echo "VERSION=$VERSION"
echo "CODE_SIGN_IDENTITY=$CODE_SIGN_IDENTITY"
echo "DEVELOPMENT_TEAM=${DEVELOPMENT_TEAM:-(none)}"
echo "Xcode: $(xcodebuild -version | tr '\n' ' ')"

# Shared settings so libScreenMirrorLib.a / sessionmanager land in the same products dir.
COMMON=(
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

# Deep re-sign OSXRDP.app: nested tools first, then the bundle.
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

  # Bundle seal last.
  do_codesign --deep -i "com.byungho.osxrdp.mainapp" "$app"

  echo "--- codesign verify ---"
  codesign -dv --verbose=2 "$macos/xrdp" 2>&1 | egrep 'Identifier|TeamIdentifier|Signature' || true
  codesign --verify --verbose=2 "$app" 2>&1 || true
}

mkdir -p "$SYMROOT" "$OBJROOT" osxup/Log package/source/module

echo "=== [1/6] ScreenMirrorLib ==="
xcodebuild -project ScreenMirrorLib/ScreenMirrorLib.xcodeproj \
  -scheme ScreenMirrorLib \
  "${COMMON[@]}" \
  build

echo "=== [2/6] osxrdp_sessionmanager ==="
xcodebuild -project osxrdp_sessionmanager/osxrdp_sessionmanager.xcodeproj \
  -target osxrdp_sessionmanager \
  "${COMMON[@]}" \
  build

echo "=== [3/6] osxup (libosxup.dylib) ==="
xcodebuild -project osxup/osxup.xcodeproj \
  -scheme osxup \
  "${COMMON[@]}" \
  build

echo "=== [4/6] OSXRDP.app ==="
xcodebuild -project ServerApp/OSXRDP.xcodeproj \
  -scheme OSXRDP \
  "${COMMON[@]}" \
  build

echo "=== [5/6] OSXRDPUninstaller.app ==="
xcodebuild -project OSXRDPUninstaller/OSXRDPUninstaller.xcodeproj \
  -target OSXRDPUninstaller \
  "${COMMON[@]}" \
  build

PRODUCTS="$SYMROOT/$CONFIGURATION"
echo "Products dir: $PRODUCTS"
ls -la "$PRODUCTS"

test -d "$PRODUCTS/OSXRDP.app"
test -d "$PRODUCTS/OSXRDPUninstaller.app"
test -f "$PRODUCTS/libosxup.dylib"
test -f "$PRODUCTS/osxrdp_sessionmanager"

# Stage package inputs (gitignore ignores *.app / *.dylib; fine for local/CI staging only).
rm -rf package/source/OSXRDP.app package/source/OSXRDPUninstaller.app package/source/module/libosxup.dylib
cp -R "$PRODUCTS/OSXRDP.app" package/source/
cp -R "$PRODUCTS/OSXRDPUninstaller.app" package/source/
cp "$PRODUCTS/libosxup.dylib" package/source/module/libosxup.dylib

# Ensure sessionmanager is embedded (build phase may no-op without shared products).
if [[ ! -x package/source/OSXRDP.app/Contents/MacOS/osxrdp_sessionmanager ]]; then
  echo "Embedding osxrdp_sessionmanager into OSXRDP.app"
  cp "$PRODUCTS/osxrdp_sessionmanager" package/source/OSXRDP.app/Contents/MacOS/
  chmod +x package/source/OSXRDP.app/Contents/MacOS/osxrdp_sessionmanager
fi

# xrdp binaries should already be copied into the app by the Xcode Copy Files phase.
if [[ ! -x package/source/OSXRDP.app/Contents/MacOS/xrdp ]]; then
  echo "WARNING: xrdp missing inside OSXRDP.app; copying from ServerApp/"
  cp ServerApp/xrdp ServerApp/xrdp-keygen package/source/OSXRDP.app/Contents/MacOS/
  chmod +x package/source/OSXRDP.app/Contents/MacOS/xrdp \
           package/source/OSXRDP.app/Contents/MacOS/xrdp-keygen
fi

# Force stable signing identifiers. Xcode CodeSignOnCopy on ad-hoc often produces
# Identifier=xrdp-<hash>, which fails IPC trust (expects exact "xrdp").
resign_osxrdp_app "package/source/OSXRDP.app"
resign_binary "package/source/module/libosxup.dylib" "libosxup.dylib"
if [[ -d package/source/OSXRDPUninstaller.app ]]; then
  do_codesign --deep -i "com.byungho.osxrdp.uninstaller" "package/source/OSXRDPUninstaller.app"
fi

echo "=== [6/6] Build pkg ($OUTPUT_PKG) ==="
PAYLOAD_DIR="$ROOT/package/payload"
SCRIPTS_DIR="$ROOT/package/scripts"
SOURCE_DIR="$ROOT/package/source"
DIST_XML="$ROOT/package/distribution.xml"

rm -rf "$PAYLOAD_DIR"
rm -f "$ROOT/package/$COMPONENT_PKG" "$ROOT/package/$OUTPUT_PKG"

mkdir -p "$PAYLOAD_DIR/Applications/osxrdp"
mkdir -p "$PAYLOAD_DIR/Library/LaunchDaemons"
mkdir -p "$PAYLOAD_DIR/Library/LaunchAgents"
mkdir -p "$PAYLOAD_DIR/etc/xrdp"
mkdir -p "$PAYLOAD_DIR/etc/osxrdp"
mkdir -p "$PAYLOAD_DIR/usr/local/lib/xrdp"
mkdir -p "$PAYLOAD_DIR/usr/local/share/xrdp"

cp -R "$SOURCE_DIR/OSXRDP.app" "$PAYLOAD_DIR/Applications/osxrdp/"
cp -R "$SOURCE_DIR/OSXRDPUninstaller.app" "$PAYLOAD_DIR/Applications/osxrdp/"
cp "$SOURCE_DIR/com.byungho.osxrdp.plist" "$PAYLOAD_DIR/Library/LaunchDaemons/"
cp "$SOURCE_DIR/com.byungho.osxrdp.sessionmanager.plist" "$PAYLOAD_DIR/Library/LaunchDaemons/"
cp "$SOURCE_DIR/com.byungho.osxrdp.lockscreen.plist" "$PAYLOAD_DIR/Library/LaunchAgents/"
cp -R "$SOURCE_DIR/config/"* "$PAYLOAD_DIR/etc/xrdp/"
cp -R "$SOURCE_DIR/log/"* "$PAYLOAD_DIR/etc/osxrdp/"
cp "$SOURCE_DIR/module/libosxup.dylib" "$PAYLOAD_DIR/usr/local/lib/xrdp/"
cp "$SOURCE_DIR/resources/"* "$PAYLOAD_DIR/usr/local/share/xrdp/"

# Match packaging.sh permissions as closely as possible without requiring a real root tree.
chmod -R a+rX "$PAYLOAD_DIR"
chmod 755 "$SCRIPTS_DIR/postinstall"

# If we chown to root for correct pkg ownership, cleanup must also use sudo
# (otherwise `rm -rf` fails with Permission denied under set -e).
USE_SUDO=0
if command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  USE_SUDO=1
  sudo chown -R root:wheel "$PAYLOAD_DIR"
fi

(
  cd "$ROOT/package"
  pkgbuild --root "$PAYLOAD_DIR" \
           --install-location "/" \
           --scripts "$SCRIPTS_DIR" \
           --identifier "$PKG_ID" \
           --version "$VERSION" \
           "$COMPONENT_PKG"

  # Unsigned product archive (no --sign, no notarytool).
  productbuild --distribution "$DIST_XML" \
               --package-path . \
               "$OUTPUT_PKG"
)

# Cleanup staging tree (keep the .pkg).
if [[ "$USE_SUDO" -eq 1 ]]; then
  sudo rm -f "$ROOT/package/$COMPONENT_PKG"
  sudo rm -rf "$PAYLOAD_DIR"
else
  rm -f "$ROOT/package/$COMPONENT_PKG"
  rm -rf "$PAYLOAD_DIR"
fi

echo "=== Done ==="
echo "Package: $ROOT/package/$OUTPUT_PKG"
ls -lh "$ROOT/package/$OUTPUT_PKG"