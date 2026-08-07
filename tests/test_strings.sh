#!/bin/bash
# Smoke-check that localization keys used by UI code exist in en/ko catalogs.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EN="$ROOT/ServerApp/OSXRDP/en.lproj/Localizable.strings"
KO="$ROOT/ServerApp/OSXRDP/ko.lproj/Localizable.strings"

fail=0
keys=(
  "diag.button.check_status"
  "diag.alert.title"
  "diag.error.missing_permissions"
  "diag.error.agent_start_failed"
  "filecopy.alert.success"
  "filecopy.alert.show_in_finder"
  "filecopy.alert.disconnected"
  "filecopy.alert.create_failed"
  "filecopy.status.item"
  "filecopy.notify.body"
  "statusbar.menu.save_to_downloads"
  "statusbar.menu.status"
)

echo "== test_strings =="
for f in "$EN" "$KO"; do
  if [[ ! -f "$f" ]]; then
    echo "  FAIL missing file: $f"
    fail=1
    continue
  fi
  for k in "${keys[@]}"; do
    if ! grep -Fq "\"$k\"" "$f"; then
      echo "  FAIL missing key \"$k\" in $f"
      fail=1
    fi
  done
done

if [[ "$fail" -eq 0 ]]; then
  echo "OK  test_strings (${#keys[@]} keys x 2 locales)"
  exit 0
fi
echo "FAIL test_strings"
exit 1
