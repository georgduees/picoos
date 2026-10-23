#!/bin/bash
set -euo pipefail
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
overlay="$project_dir/br2-external/board/zero2w/overlay"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work"/{bin,proc,sys/class/thermal/thermal_zone0,run,data/pico8,log}
export PICOOS_TEST_STATE="$work"
printf 'root=/dev/mmcblk0p3 picoos.slot=B quiet\n' > "$work/proc/cmdline"
printf '90061.00 0.00\n' > "$work/proc/uptime"
printf '0.10 0.20 0.30 1/100 1\n' > "$work/proc/loadavg"
printf 'MemTotal: 524288 kB\nMemAvailable: 393216 kB\n' > "$work/proc/meminfo"
printf '42500\n' > "$work/sys/class/thermal/thermal_zone0/temp"
cat > "$work/bin/ip" <<'EOF'
#!/bin/sh
printf '    inet 192.0.2.8/24 scope global wlan0\n'
EOF
chmod +x "$work/bin/ip"
sed -e "s|/proc/|$work/proc/|g" -e "s|/sys/|$work/sys/|g" \
    "$overlay/usr/sbin/picoos-motd" > "$work/motd"
PATH="$work/bin:$PATH" NO_COLOR=1 sh "$work/motd" > "$work/greeting"
for line in 'P I C O O S' 'Boot slot  : B' 'Uptime     : 1d 01h 01m' \
    'Load       : 0.10 / 0.20 / 0.30' 'Memory     : 128 / 512 MiB used' \
    'CPU temp   : 42.5 C' 'WLAN IPv4  : 192.0.2.8/24'; do
    grep -Fq "$line" "$work/greeting"
done
if grep -q $'\033' "$work/greeting"; then
    echo "MOTD emitted terminal escapes into nonterminal output." >&2
    exit 1
fi
# Sourcing a login profile must never add output to noninteractive SSH.
sh -c '. "$1"; printf sentinel' sh "$overlay/etc/profile.d/picoos-motd.sh" \
    > "$work/noninteractive"
test "$(cat "$work/noninteractive")" = sentinel

cat > "$work/bin/start-stop-daemon" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$@" > "$PICOOS_TEST_STATE/daemon-arguments"
case "$1" in
    -S)
        printf '4242\n' > "$PICOOS_TEST_STATE/run/pico8.pid"
        if [ "${PICOOS_TEST_FAIL_START:-0}" = 0 ]; then
            touch "$PICOOS_TEST_STATE/running"
        fi
        ;;
    -K) rm "$PICOOS_TEST_STATE/running" ;;
    *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\nexit 0\n' > "$work/bin/sleep"
chmod +x "$work/bin/start-stop-daemon" "$work/bin/sleep"
export PATH="$work/bin:$PATH"
{
    cat <<'EOF'
kill() {
    test "$1" = -0 && test "$2" = 4242 &&
        test -e "$PICOOS_TEST_STATE/running"
}
EOF
    sed -e "s|/run/|$work/run/|g" -e "s|/data/|$work/data/|g" \
        -e "s|/var/log/|$work/log/|g" -e 's|/dev/tty1|/dev/null|g' \
        "$overlay/etc/init.d/S99start-pico8"
} > "$work/service"
sh "$work/service" start 2> "$work/missing"
grep -Fq 'automatic start skipped' "$work/missing"
test ! -f "$work/run/pico8.pid"
touch "$work/data/pico8/pico8_dyn"
chmod +x "$work/data/pico8/pico8_dyn"
sh "$work/service" start
grep -Fxq -- -splore "$work/daemon-arguments"
test -e "$work/running"
if sh "$work/service" start 2> "$work/duplicate"; then
    echo "Duplicate PICO-8 start unexpectedly succeeded." >&2
    exit 1
fi
grep -Fq 'PID file exists' "$work/duplicate"
sh "$work/service" stop
grep -Fxq -- "$work/data/pico8/pico8_dyn" "$work/daemon-arguments"
test ! -e "$work/run/pico8.pid"
if PICOOS_TEST_FAIL_START=1 sh "$work/service" start 2> "$work/failed"; then
    echo "Failed PICO-8 startup unexpectedly succeeded." >&2
    exit 1
fi
grep -Fq 'failed to start' "$work/failed"
test ! -e "$work/run/pico8.pid"
printf '1\n' > "$work/run/pico8.pid"
if sh "$work/service" stop 2> "$work/invalid"; then
    echo "Invalid PICO-8 PID unexpectedly accepted." >&2
    exit 1
fi
grep -Fq 'Invalid PICO-8 PID' "$work/invalid"
grep -Fq 'console=tty3 quiet loglevel=3 logo.nologo vt.global_cursor_default=0' \
    "$project_dir/br2-external/board/zero2w/u-boot.env"
grep -Fxq stdout=serial "$project_dir/br2-external/board/zero2w/u-boot.env"
grep -Fxq stderr=serial "$project_dir/br2-external/board/zero2w/u-boot.env"
mkdir -p "$work/target/etc" "$work/images/rpi-firmware/overlays"
printf '::sysinit:/etc/init.d/rcS\ntty3::respawn:/sbin/getty -L tty3 0 vt100 # GENERIC_SERIAL\n' \
    > "$work/target/etc/inittab"
for file in zImage bcm2710-rpi-zero-2-w.dtb rpi-firmware/overlays/vc4-kms-v3d.dtbo; do
    printf fixture > "$work/images/$file"
done
export TARGET_DIR="$work/target" BINARIES_DIR="$work/images"
export BR2_EXTERNAL_PICOOS_PATH="$project_dir/br2-external"
sh "$project_dir/buildroot/board/raspberrypizero2w/post-build.sh"
test "$(grep -c ':respawn:.*getty' "$work/target/etc/inittab")" -eq 2
for iteration in 1 2; do
    sh "$project_dir/br2-external/board/zero2w/post-build.sh"
    test "$(grep -c ':respawn:.*getty' "$work/target/etc/inittab")" -eq 1
    grep -q '^tty3::respawn:.*getty.*tty3' "$work/target/etc/inittab"
    grep -Fxq '::sysinit:/etc/init.d/rcS >/var/log/boot.log 2>&1' "$work/target/etc/inittab"
    test ! -s "$work/target/etc/motd"
done
echo "Console tests passed (dashboard values, noninteractive silence, quiet boot, service start/stop and explicit failures)."
