#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
helper="$project_dir/br2-external/board/zero2w/overlay/usr/sbin/picoos-bluetooth"
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/test-bluetooth.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
mkdir -p "$work/data" "$work/root/var/lib" "$work/proc"
printf 'rootfs / ext4 rw 0 0\n/dev/mmcblk0p4 %s vfat rw 0 0\n' \
    "$work/data" > "$work/proc/mounts"

export PICOOS_BLUETOOTH_DATA_DIR="$work/data"
export PICOOS_BLUETOOTH_STATE_DIR="$work/root/var/lib/bluetooth"
export PICOOS_BLUETOOTH_MOUNTS_FILE="$work/proc/mounts"

sh "$helper" prepare
test -d "$PICOOS_BLUETOOTH_DATA_DIR/bluetooth"
test "$(readlink "$PICOOS_BLUETOOTH_STATE_DIR")" = "$PICOOS_BLUETOOTH_DATA_DIR/bluetooth"
sh "$helper" prepare

printf 'rootfs / ext4 rw 0 0\n' > "$PICOOS_BLUETOOTH_MOUNTS_FILE"
mkdir -p "$work/unmounted-data" "$work/unmounted-root/var/lib"
PICOOS_BLUETOOTH_DATA_DIR="$work/unmounted-data"
PICOOS_BLUETOOTH_STATE_DIR="$work/unmounted-root/var/lib/bluetooth"
export PICOOS_BLUETOOTH_DATA_DIR PICOOS_BLUETOOTH_STATE_DIR
if sh "$helper" prepare > "$work/unmounted.log" 2>&1; then
    echo "Bluetooth state setup accepted an unmounted data partition." >&2
    exit 1
fi
test ! -e "$PICOOS_BLUETOOTH_DATA_DIR/bluetooth"

PICOOS_BLUETOOTH_DATA_DIR="$work/data"
PICOOS_BLUETOOTH_STATE_DIR="$work/root/var/lib/bluetooth"
export PICOOS_BLUETOOTH_DATA_DIR PICOOS_BLUETOOTH_STATE_DIR
rm "$PICOOS_BLUETOOTH_STATE_DIR"
ln -s "$work/elsewhere" "$PICOOS_BLUETOOTH_STATE_DIR"
printf '/dev/mmcblk0p4 %s vfat rw 0 0\n' "$PICOOS_BLUETOOTH_DATA_DIR" > "$PICOOS_BLUETOOTH_MOUNTS_FILE"
if sh "$helper" prepare > "$work/conflict.log" 2>&1; then
    echo "Bluetooth state setup replaced an unexpected symlink." >&2
    exit 1
fi
test "$(readlink "$PICOOS_BLUETOOTH_STATE_DIR")" = "$work/elsewhere"

rm "$PICOOS_BLUETOOTH_STATE_DIR"
mkdir "$PICOOS_BLUETOOTH_STATE_DIR"
touch "$PICOOS_BLUETOOTH_STATE_DIR/unexpected"
if sh "$helper" prepare > "$work/nonempty.log" 2>&1; then
    echo "Bluetooth state setup discarded unexpected pairing data." >&2
    exit 1
fi
test -f "$PICOOS_BLUETOOTH_STATE_DIR/unexpected"
echo "Bluetooth runtime persistence tests passed."
