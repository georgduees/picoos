#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
helper="$project_dir/br2-external/board/zero2w/overlay/usr/sbin/picoos-state"
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/test-state.XXXXXX")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
mkdir -p "$work/data" "$work/persist" "$work/root/var/lib" "$work/proc"
printf 'rootfs / ext4 rw 0 0\n/dev/mmcblk0p4 %s vfat rw 0 0\n' \
    "$work/data" > "$work/proc/mounts"

export PICOOS_STATE_DATA_DIR="$work/data"
export PICOOS_STATE_MOUNT_DIR="$work/persist"
export PICOOS_STATE_MOUNTS_FILE="$work/proc/mounts"
export PICOOS_STATE_ROOT_PREFIX="$work/root"
export PICOOS_STATE_IMAGE_MIB=8
export PICOOS_STATE_SKIP_MOUNT=1
link="$work/root/var/lib/bluetooth"

sh "$helper" prepare
image="$work/data/picoos-state.img"
test -f "$image"
test ! -e "$image.new"
test "$(wc -c < "$image")" -eq $((8 * 1024 * 1024))
dumpe2fs -h "$image" 2>/dev/null | grep -q 'Filesystem volume name:.*PICOOS-STATE'
dumpe2fs -h "$image" 2>/dev/null | grep -q 'has_journal'
e2fsck -fn "$image" > /dev/null
test "$(readlink "$link")" = "$work/persist/bluetooth"
test -d "$work/persist/bluetooth"
sum_before=$(sha256sum "$image")
sh "$helper" prepare
test "$(sha256sum "$image")" = "$sum_before"

# BlueZ names its directories after the controller address, which FAT32 rejects.
debugfs -w -R "mkdir B8:27:EB:58:92:2E" "$image" > /dev/null 2>&1
debugfs -R "ls" "$image" 2>/dev/null | grep -q 'B8:27:EB:58:92:2E'

printf 'rootfs / ext4 rw 0 0\n' > "$PICOOS_STATE_MOUNTS_FILE"
mkdir "$work/data2"
if PICOOS_STATE_DATA_DIR="$work/data2" PICOOS_STATE_IMAGE="$work/data2/picoos-state.img" \
    sh "$helper" prepare > "$work/unmounted.log" 2>&1; then
    echo "State setup accepted an unmounted data partition." >&2
    exit 1
fi
test -z "$(ls -A "$work/data2")"
printf '/dev/mmcblk0p4 %s vfat rw 0 0\n' "$work/data" > "$PICOOS_STATE_MOUNTS_FILE"

rm "$link"
ln -s "$work/elsewhere" "$link"
if sh "$helper" prepare > "$work/conflict.log" 2>&1; then
    echo "State setup replaced an unexpected symlink." >&2
    exit 1
fi
test "$(readlink "$link")" = "$work/elsewhere"

rm "$link"
mkdir "$link"
touch "$link/unexpected"
if sh "$helper" prepare > "$work/nonempty.log" 2>&1; then
    echo "State setup discarded unexpected pairing data." >&2
    exit 1
fi
test -f "$link/unexpected"
echo "Persistent state runtime tests passed."
