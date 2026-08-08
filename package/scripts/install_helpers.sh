#!/bin/bash

# Shared, testable installer helpers. The package runs these with the defaults;
# tests override command paths and ownership only inside a temporary directory.

osxrdp_atomic_install() {
    local source="$1"
    local destination="$2"
    local mode="$3"
    local owner="${OSXRDP_INSTALL_OWNER:-root}"
    local group="${OSXRDP_INSTALL_GROUP:-wheel}"
    local install_bin="${OSXRDP_INSTALL_BIN:-/usr/bin/install}"
    local mv_bin="${OSXRDP_MV_BIN:-/bin/mv}"
    local temporary

    temporary="$(dirname "$destination")/.$(basename "$destination").new.$$"
    "$install_bin" -o "$owner" -g "$group" -m "$mode" "$source" "$temporary"
    "$mv_bin" -f "$temporary" "$destination"
}

osxrdp_ensure_rdp_identity() {
    local app_macos="$1"
    local config_dir="$2"
    local temp_dir="$3"
    local destination="$config_dir/rsakeys.ini"
    local keygen="${OSXRDP_KEYGEN_BIN:-$app_macos/xrdp-keygen}"

    if [[ -L "$destination" || ( -e "$destination" && ! -f "$destination" ) ]]; then
        echo "ERROR: $destination must be a regular file or absent." >&2
        return 1
    fi
    if [[ -f "$destination" ]]; then
        return 0
    fi

    "$keygen" xrdp "$temp_dir/rsakeys.ini" 2048
    if [[ ! -s "$temp_dir/rsakeys.ini" ]]; then
        echo "ERROR: xrdp-keygen did not produce rsakeys.ini." >&2
        return 1
    fi
    osxrdp_atomic_install "$temp_dir/rsakeys.ini" "$destination" 600
}

osxrdp_ensure_tls_identity() {
    local config_dir="$1"
    local temp_dir="$2"
    local key="$config_dir/key.pem"
    local cert="$config_dir/cert.pem"
    local openssl_bin="${OSXRDP_OPENSSL_BIN:-/usr/bin/openssl}"

    if [[ -L "$key" || -L "$cert" || ( -e "$key" && ! -f "$key" ) ||
          ( -e "$cert" && ! -f "$cert" ) ]]; then
        echo "ERROR: TLS identity paths must be regular files or absent." >&2
        return 1
    fi
    if [[ -f "$key" && -f "$cert" ]]; then
        return 0
    fi
    if [[ -e "$key" || -e "$cert" ]]; then
        echo "ERROR: TLS identity is incomplete; key.pem and cert.pem must both exist or both be absent." >&2
        return 1
    fi

    "$openssl_bin" req -x509 -newkey rsa:2048 -nodes \
        -keyout "$temp_dir/key.pem" \
        -out "$temp_dir/cert.pem" \
        -days 3650 -subj "/CN=osxrdp"
    if [[ ! -s "$temp_dir/key.pem" || ! -s "$temp_dir/cert.pem" ]]; then
        echo "ERROR: openssl did not produce a complete TLS identity." >&2
        return 1
    fi

    osxrdp_atomic_install "$temp_dir/key.pem" "$key" 600
    osxrdp_atomic_install "$temp_dir/cert.pem" "$cert" 644
}

osxrdp_restart_daemon() {
    local label="$1"
    local plist="$2"
    local launchctl_bin="${OSXRDP_LAUNCHCTL_BIN:-/bin/launchctl}"
    local sleep_bin="${OSXRDP_SLEEP_BIN:-/bin/sleep}"
    local attempt

    "$launchctl_bin" bootout "system/$label" 2>/dev/null || true
    for attempt in 1 2 3; do
        if "$launchctl_bin" bootstrap system "$plist"; then
            break
        fi
        if [[ "$attempt" -eq 3 ]]; then
            echo "ERROR: could not bootstrap $label after 3 attempts" >&2
            return 1
        fi
        "$sleep_bin" 1
    done

    "$launchctl_bin" enable "system/$label"
    "$launchctl_bin" kickstart -k "system/$label"
    "$launchctl_bin" print "system/$label" >/dev/null
}
