#!/bin/bash
# Diagnose signatures and safely restart the installed daemons. This script
# never changes code signatures; signature problems require reinstalling a package.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/install_helpers.sh
source "$SCRIPT_DIR/scripts/install_helpers.sh"

if [[ "$(id -u)" -ne 0 ]]; then
    echo "Run as root: sudo bash $0"
    exit 1
fi

APP_MACOS="/Applications/osxrdp/OSXRDP.app/Contents/MacOS"
XRDP="$APP_MACOS/xrdp"
SESSION_MANAGER="$APP_MACOS/osxrdp_sessionmanager"
RUNTIME_DIR="/var/run/osxrdp"

identifier() {
    codesign -dv "$1" 2>&1 | awk -F= '/^Identifier=/{print $2; exit}'
}

[[ -x "$XRDP" && -x "$SESSION_MANAGER" ]] || {
    echo "ERROR: OSXRDP install is incomplete" >&2
    exit 1
}
[[ "$(identifier "$XRDP")" == "xrdp" ]] || {
    echo "ERROR: xrdp has the wrong signing identifier; reinstall the package" >&2
    exit 1
}
[[ "$(identifier "$SESSION_MANAGER")" == "com.byungho.osxrdp.sessionmanager" ]] || {
    echo "ERROR: sessionmanager has the wrong signing identifier; reinstall the package" >&2
    exit 1
}
codesign --verify --strict "$XRDP"
codesign --verify --strict "$SESSION_MANAGER"
codesign -dv --verbose=2 "$XRDP" 2>&1 | grep -E 'Identifier|TeamIdentifier|Signature' || true
codesign -dv --verbose=2 "$SESSION_MANAGER" 2>&1 | grep -E 'Identifier|TeamIdentifier|Signature' || true

if [[ -L "$RUNTIME_DIR" ]]; then
    echo "ERROR: $RUNTIME_DIR is a symbolic link" >&2
    exit 1
fi
mkdir -p "$RUNTIME_DIR"
chown root:wheel "$RUNTIME_DIR"
chmod 700 "$RUNTIME_DIR"

osxrdp_restart_daemon com.byungho.osxrdp /Library/LaunchDaemons/com.byungho.osxrdp.plist
osxrdp_restart_daemon com.byungho.osxrdp.sessionmanager /Library/LaunchDaemons/com.byungho.osxrdp.sessionmanager.plist

echo "Sessionmanager socket:"
ls -la "$RUNTIME_DIR/sessionmanager.sock"
echo "OK: installed signatures and launchd jobs are valid"
