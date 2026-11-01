#!/bin/bash
set -euo pipefail
umask 077

command -v wpa_passphrase >/dev/null || {
    echo "Required host tool not found: wpa_passphrase" >&2
    exit 1
}

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
destination="$project_dir/provisioning/local"
read -r -p "2.4 GHz WLAN SSID: " ssid
read -r -s -p "WLAN password (8-63 characters): " password
printf '\n'
if [ -z "$ssid" ] || [ "${#ssid}" -gt 32 ]; then
    echo "SSID must contain 1-32 characters." >&2
    exit 1
fi
if [ "${#password}" -lt 8 ] || [ "${#password}" -gt 63 ]; then
    echo "Password must contain 8-63 characters." >&2
    exit 1
fi

mkdir -p "$destination"
temporary=$(mktemp "$destination/.wifi.XXXXXX")
trap 'rm -f "$temporary"' EXIT
{
    printf 'ctrl_interface=/var/run/wpa_supplicant\ncountry=DE\n'
    printf '%s\n' "$password" | wpa_passphrase "$ssid" | sed '/^[[:space:]]*#psk=/d'
} > "$temporary"
unset password
chmod 600 "$temporary"
mv "$temporary" "$destination/wpa_supplicant.conf"
printf 'Saved private WLAN configuration to %s/wpa_supplicant.conf\n' "$destination"
printf 'This file contains a WLAN credential. Do not publish it.\n'
