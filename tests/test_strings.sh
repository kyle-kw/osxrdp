#!/bin/bash
# Smoke-check that required UI keys exist in the English catalog.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EN="$ROOT/ServerApp/OSXRDP/en.lproj/Localizable.strings"

fail=0
if ! command -v rg >/dev/null 2>&1; then
  echo "FAIL test_strings requires ripgrep (rg)"
  exit 1
fi
keys=(
  "main.state.permissions.title"
  "main.state.ready.title"
  "main.state.connected.metrics"
  "main.action.permissions"
  "main.action.stop"
  "main.files.count"
  "permission.button.grant"
  "permission.button.open_settings"
  "diag.error.missing_permissions"
  "diag.error.agent_start_failed"
  "settings.startup.requires_approval"
  "settings.startup.unsupported"
  "settings.diag.session_title"
  "filecopy.alert.success"
  "filecopy.alert.show_in_finder"
  "filecopy.alert.disconnected"
  "filecopy.alert.create_failed"
  "filecopy.status.item"
  "filecopy.notify.body"
  "statusbar.menu.save_to_downloads"
  "statusbar.menu.dashboard"
  "statusbar.menu.status_summary"
  "statusbar.menu.quit"
)

echo "== test_strings =="
for f in "$EN"; do
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

if rg -n -P --glob '!extern_lib/**' --glob '!package/source/resources/**' '[\x{AC00}-\x{D7A3}]' "$ROOT"; then
  echo "  FAIL Korean text remains in the repository"
  fail=1
fi

if [[ "$fail" -eq 0 ]]; then
  echo "OK  test_strings (${#keys[@]} English keys; no Korean text)"
  exit 0
fi
echo "FAIL test_strings"
exit 1
