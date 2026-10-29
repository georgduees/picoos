#!/bin/bash
set -euo pipefail

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/test-wifi.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/data/network" "$work/run"
export TEST_ROOT="$work"
export REAL_STAT
REAL_STAT=$(command -v stat)
export PATH="$work/bin:$PATH"

cat > "$work/bin/mountpoint" <<'EOF'
#!/bin/sh
exit "${TEST_MOUNT_FAILURE:-0}"
EOF
cat > "$work/bin/stat" <<'EOF'
#!/bin/sh
if [ "$1" = -c ] && [ "$2" = '%u:%a' ]; then
    printf '%s:%s\n' "${TEST_OWNER:-0}" "$("$REAL_STAT" -c %a "$3")"
else
    exec "$REAL_STAT" "$@"
fi
EOF
cat > "$work/bin/wait_iface" <<'EOF'
#!/bin/sh
test "$IFACE" = wlan0
test "$IF_WAIT_DELAY" = 10
exit "${TEST_WAIT_FAILURE:-0}"
EOF
cat > "$work/bin/wpa_supplicant" <<'EOF'
#!/bin/sh
set -eu
while [ "$#" -gt 0 ]; do
    case "$1" in
        -c) config=$2; shift ;;
        -P) pidfile=$2; shift ;;
    esac
    shift
done
test "$config" = "$TEST_ROOT/run/picoos-wifi/wpa_supplicant.conf"
test "$("$REAL_STAT" -c %a "$config")" = 600
test "$("$REAL_STAT" -c %a "$(dirname "$config")")" = 700
cmp "$TEST_ROOT/data/network/wpa_supplicant.conf" "$config"
test "${TEST_WPA_FAILURE:-0}" = 0 || exit 1
echo 123 > "$pidfile"
EOF
cat > "$work/bin/start-stop-daemon" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$work/bin/"*
sed -e "s|/data/|$work/data/|g" \
    -e "s|mountpoint -q /data|mountpoint -q $work/data|g" \
    -e "s|/run/|$work/run/|g" \
    -e "s|/usr/sbin/wpa_supplicant|$work/bin/wpa_supplicant|g" \
    -e "s|/etc/network/if-pre-up.d/wait_iface|$work/bin/wait_iface|g" \
    "$project_dir/br2-external/board/zero2w/overlay/etc/network/pico8-wifi" > "$work/wifi"

config="$work/data/network/wpa_supplicant.conf"
runtime="$work/run/picoos-wifi/wpa_supplicant.conf"
printf 'country=DE\nnetwork={\n ssid="test-only"\n psk="test-only-password"\n}\n' > "$config"
for mode in 600 700; do
    chmod "$mode" "$config"
    sh "$work/wifi" start
    test -f "$runtime"
    sh "$work/wifi" stop
    test ! -e "$runtime"
done

expect_failure() {
    if "$@" > "$work/failure.log" 2>&1; then
        echo "Expected rejection: $*" >&2
        exit 1
    fi
    test ! -e "$runtime"
}
chmod 644 "$config"
expect_failure sh "$work/wifi" start
chmod 600 "$config"
expect_failure env TEST_OWNER=1000 sh "$work/wifi" start
expect_failure env TEST_MOUNT_FAILURE=1 sh "$work/wifi" start
expect_failure env TEST_WAIT_FAILURE=1 sh "$work/wifi" start
expect_failure env TEST_WPA_FAILURE=1 sh "$work/wifi" start
mv "$config" "$config.real"
ln -s "$config.real" "$config"
expect_failure sh "$work/wifi" start
rm "$config"
expect_failure sh "$work/wifi" start
mkdir "$config"
expect_failure sh "$work/wifi" start
rmdir "$config"
touch "$config"
expect_failure sh "$work/wifi" start
echo "WLAN runtime-copy tests passed (0600/ext4, 0700/FAT32, cleanup and rejection paths)."
