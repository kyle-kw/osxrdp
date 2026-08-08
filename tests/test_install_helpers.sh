#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=../package/scripts/install_helpers.sh
source "$ROOT/package/scripts/install_helpers.sh"

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/osxrdp-install-test.XXXXXX")"
trap 'status=$?; rm -rf "$TEST_ROOT"; exit "$status"' EXIT
CONFIG_DIR="$TEST_ROOT/etc/xrdp"
TEMP_DIR="$TEST_ROOT/temp"
BIN_DIR="$TEST_ROOT/bin"
mkdir -p "$CONFIG_DIR" "$TEMP_DIR" "$BIN_DIR"

OSXRDP_INSTALL_OWNER="$(id -un)"
OSXRDP_INSTALL_GROUP="$(id -gn)"
export OSXRDP_INSTALL_OWNER OSXRDP_INSTALL_GROUP

printf '%s\n' '#!/bin/bash' 'printf "rdp-identity\\n" > "$2"' > "$BIN_DIR/keygen"
printf '%s\n' '#!/bin/bash' \
    'while [[ "$#" -gt 0 ]]; do' \
    '  case "$1" in -keyout) key="$2"; shift 2;; -out) cert="$2"; shift 2;; *) shift;; esac' \
    'done' \
    'printf "tls-key\\n" > "$key"' \
    'printf "tls-cert\\n" > "$cert"' > "$BIN_DIR/openssl"
chmod 755 "$BIN_DIR/keygen" "$BIN_DIR/openssl"
OSXRDP_KEYGEN_BIN="$BIN_DIR/keygen"
OSXRDP_OPENSSL_BIN="$BIN_DIR/openssl"
export OSXRDP_KEYGEN_BIN OSXRDP_OPENSSL_BIN

# First install creates all identities.
osxrdp_ensure_rdp_identity "$TEST_ROOT/app" "$CONFIG_DIR" "$TEMP_DIR"
osxrdp_ensure_tls_identity "$CONFIG_DIR" "$TEMP_DIR"
test -s "$CONFIG_DIR/rsakeys.ini"
test -s "$CONFIG_DIR/key.pem"
test -s "$CONFIG_DIR/cert.pem"

# A complete upgrade must preserve exact bytes.
before="$(shasum "$CONFIG_DIR/rsakeys.ini" "$CONFIG_DIR/key.pem" "$CONFIG_DIR/cert.pem")"
printf 'replacement\n' > "$TEMP_DIR/rsakeys.ini"
printf 'replacement\n' > "$TEMP_DIR/key.pem"
printf 'replacement\n' > "$TEMP_DIR/cert.pem"
osxrdp_ensure_rdp_identity "$TEST_ROOT/app" "$CONFIG_DIR" "$TEMP_DIR"
osxrdp_ensure_tls_identity "$CONFIG_DIR" "$TEMP_DIR"
after="$(shasum "$CONFIG_DIR/rsakeys.ini" "$CONFIG_DIR/key.pem" "$CONFIG_DIR/cert.pem")"
test "$before" = "$after"

# A partial TLS identity is a hard failure and the remaining file is preserved.
rm "$CONFIG_DIR/cert.pem"
key_before="$(shasum "$CONFIG_DIR/key.pem")"
if osxrdp_ensure_tls_identity "$CONFIG_DIR" "$TEMP_DIR"; then
    echo "FAIL: partial TLS identity was accepted" >&2
    exit 1
fi
test "$key_before" = "$(shasum "$CONFIG_DIR/key.pem")"

# launchctl bootstrap is retried, then enable/kickstart/print are verified.
printf '%s\n' '#!/bin/bash' \
    'printf "%s\\n" "$*" >> "$OSXRDP_LAUNCH_LOG"' \
    'if [[ "$1" == bootstrap ]]; then' \
    '  count=0; [[ -f "$OSXRDP_LAUNCH_COUNT" ]] && count="$(cat "$OSXRDP_LAUNCH_COUNT")"' \
    '  count=$((count + 1)); printf "%s" "$count" > "$OSXRDP_LAUNCH_COUNT"' \
    '  if [[ "$count" -ge "${OSXRDP_BOOTSTRAP_SUCCEEDS_AT:-99}" ]]; then exit 0; else exit 1; fi' \
    'fi' \
    'exit 0' > "$BIN_DIR/launchctl"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$BIN_DIR/sleep"
chmod 755 "$BIN_DIR/launchctl" "$BIN_DIR/sleep"
OSXRDP_LAUNCHCTL_BIN="$BIN_DIR/launchctl"
OSXRDP_SLEEP_BIN="$BIN_DIR/sleep"
OSXRDP_LAUNCH_LOG="$TEST_ROOT/launch.log"
OSXRDP_LAUNCH_COUNT="$TEST_ROOT/launch.count"
OSXRDP_BOOTSTRAP_SUCCEEDS_AT=3
export OSXRDP_LAUNCHCTL_BIN OSXRDP_SLEEP_BIN OSXRDP_LAUNCH_LOG
export OSXRDP_LAUNCH_COUNT OSXRDP_BOOTSTRAP_SUCCEEDS_AT
osxrdp_restart_daemon "com.example.service" "/Library/LaunchDaemons/example.plist"
test "$(cat "$OSXRDP_LAUNCH_COUNT")" = 3
grep -q '^enable system/com.example.service$' "$OSXRDP_LAUNCH_LOG"
grep -q '^kickstart -k system/com.example.service$' "$OSXRDP_LAUNCH_LOG"
grep -q '^print system/com.example.service$' "$OSXRDP_LAUNCH_LOG"

rm "$OSXRDP_LAUNCH_COUNT"
OSXRDP_BOOTSTRAP_SUCCEEDS_AT=99
export OSXRDP_BOOTSTRAP_SUCCEEDS_AT
if osxrdp_restart_daemon "com.example.fail" "/Library/LaunchDaemons/fail.plist"; then
    echo "FAIL: permanently failing bootstrap was accepted" >&2
    exit 1
fi
test "$(cat "$OSXRDP_LAUNCH_COUNT")" = 3

echo "OK  test_install_helpers"
