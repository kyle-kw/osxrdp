#!/bin/bash
# Repair a broken local install where sessionmanager is killed by Launch Constraint
# (usually after ad-hoc re-sign overwrote nested code-signing identifiers with the GUI app id).
#
# Usage:
#   sudo bash package/fix_sessionmanager.sh
set -euo pipefail

if [[ "$(id -u)" -ne 0 ]]; then
  echo "Run as root: sudo bash $0"
  exit 1
fi

APP_BUNDLE="/Applications/osxrdp/OSXRDP.app"
APP_MACOS="$APP_BUNDLE/Contents/MacOS"
SM="$APP_MACOS/osxrdp_sessionmanager"
XRDP="$APP_MACOS/xrdp"

if [[ ! -x "$SM" || ! -x "$XRDP" ]]; then
  echo "ERROR: OSXRDP install not found under /Applications/osxrdp"
  exit 1
fi

echo "=== Stopping daemons ==="
launchctl bootout system/com.byungho.osxrdp.sessionmanager 2>/dev/null || true
launchctl bootout system/com.byungho.osxrdp 2>/dev/null || true
rm -f /tmp/osxrdpsessionmanager

echo "=== Re-signing nested helpers with distinct identifiers ==="
codesign --force --sign - -i xrdp "$XRDP"
codesign --force --sign - -i xrdp-keygen "$APP_MACOS/xrdp-keygen" 2>/dev/null || true
codesign --force --sign - -i com.byungho.osxrdp.sessionmanager "$SM"
codesign --force --sign - -i com.byungho.osxrdp.mainapp "$APP_MACOS/OSXRDP"
# Seal app without --deep (must not overwrite nested ids).
codesign --force --sign - -i com.byungho.osxrdp.mainapp "$APP_BUNDLE"

echo "=== Identifiers ==="
codesign -dv "$XRDP" 2>&1 | egrep 'Identifier|Team'
codesign -dv "$SM" 2>&1 | egrep 'Identifier|Team'

# Refresh LaunchDaemon plist ProcessType if missing.
PLIST="/Library/LaunchDaemons/com.byungho.osxrdp.sessionmanager.plist"
if [[ -f "$PLIST" ]] && ! grep -q ProcessType "$PLIST"; then
  echo "=== Adding ProcessType=Interactive to sessionmanager plist ==="
  /usr/libexec/PlistBuddy -c 'Add :ProcessType string Interactive' "$PLIST" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c 'Set :ProcessType Interactive' "$PLIST"
fi

xattr -dr com.apple.quarantine /Applications/osxrdp 2>/dev/null || true
xattr -d com.apple.quarantine /Library/LaunchDaemons/com.byungho.osxrdp.plist 2>/dev/null || true
xattr -d com.apple.quarantine "$PLIST" 2>/dev/null || true

mkdir -p /Library/Logs/osxrdp
chmod 755 /Library/Logs/osxrdp

echo "=== Starting daemons ==="
launchctl bootstrap system /Library/LaunchDaemons/com.byungho.osxrdp.plist 2>/dev/null || true
launchctl enable system/com.byungho.osxrdp
launchctl kickstart -k system/com.byungho.osxrdp

launchctl bootstrap system "$PLIST" 2>/dev/null || true
launchctl enable system/com.byungho.osxrdp.sessionmanager
launchctl kickstart -k system/com.byungho.osxrdp.sessionmanager

sleep 1
echo "=== Status ==="
ps aux | grep -E 'osxrdp_sessionmanager|/MacOS/xrdp ' | grep -v grep || true
echo "socket:"
ls -la /tmp/osxrdpsessionmanager 2>/dev/null || echo "(no socket yet)"
echo "sessionmanager log (tail):"
tail -5 /Library/Logs/osxrdp/osxrdp_sessionmanager.log 2>/dev/null || echo "(no log yet)"

if pgrep -x osxrdp_sessionmanager >/dev/null; then
  echo "OK: osxrdp_sessionmanager is running"
  exit 0
fi

echo "FAILED: sessionmanager still not running. Check:"
echo "  launchctl print system/com.byungho.osxrdp.sessionmanager"
echo "  log show --last 5m --predicate 'eventMessage CONTAINS \"sessionmanager\"'"
exit 1
