#!/bin/sh
set -eu

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
helper="$project_dir/br2-external/board/zero2w/overlay/usr/sbin/picoos-state"
mkdir -p "$project_dir/provisioning/local"
work="$project_dir/provisioning/local/test-state.$$"
(umask 077; mkdir "$work")
trap 'rm -rf -- "$work"' EXIT HUP INT TERM
mkdir -p "$work/data" "$work/persist" "$work/root/var/lib" "$work/proc"
printf 'rootfs / ext4 rw 0 0\n/dev/mmcblk0p4 %s vfat rw 0 0\n' \
    "$work/data" > "$work/proc/mounts"

export PICOOS_STATE_DATA_DIR="$work/data"
export PICOOS_STATE_MOUNT_DIR="$work/persist"
export PICOOS_STATE_MOUNTS_FILE="$work/proc/mounts"
export PICOOS_STATE_ROOT_PREFIX="$work/root"
unset PICOOS_STATE_IMAGE_MIB
export PICOOS_STATE_SKIP_MOUNT=1
link="$work/root/var/lib/bluetooth"
home="$work/root/root/.lexaloffle"
target="$work/persist/pico8-home"

expect_failure() {
    if sh "$helper" "$1" > "$work/$2.log" 2>&1; then
        echo "State setup unexpectedly accepted $2." >&2
        exit 1
    fi
}

sh "$helper" prepare
image="$work/data/picoos-state.img"
test -f "$image"
test ! -e "$image.new"
test "$(wc -c < "$image")" -eq $((128 * 1024 * 1024))
dumpe2fs -h "$image" 2>/dev/null | grep -q 'Filesystem volume name:.*PICOOS-STATE'
dumpe2fs -h "$image" 2>/dev/null | grep -q 'has_journal'
e2fsck -fn "$image" > /dev/null
test "$(readlink "$link")" = "$work/persist/bluetooth"
test -d "$work/persist/bluetooth"
test "$(readlink "$home")" = "$target"
test "$(stat -c %a "$target")" = 700
sum_before=$(sha256sum "$image")
PICOOS_STATE_IMAGE_MIB=8 sh "$helper" prepare
test "$(sha256sum "$image")" = "$sum_before"

# Explicit sizes still work; an existing legacy image is never resized.
PICOOS_STATE_IMAGE="$work/data/legacy.img" PICOOS_STATE_IMAGE_MIB=16 sh "$helper" create
legacy_sum=$(sha256sum "$work/data/legacy.img")
PICOOS_STATE_IMAGE="$work/data/legacy.img" sh "$helper" create
test "$(wc -c < "$work/data/legacy.img")" -eq $((16 * 1024 * 1024))
test "$(sha256sum "$work/data/legacy.img")" = "$legacy_sum"

# BlueZ names its directories after the controller address, which FAT32 rejects.
debugfs -w -R "mkdir B8:27:EB:58:92:2E" "$image" > /dev/null 2>&1
debugfs -R "ls" "$image" 2>/dev/null | grep -q 'B8:27:EB:58:92:2E'

# A new root slot reuses both homes and leaves existing Bluetooth pairings intact.
mkdir -p "$link/B8:27:EB:58:92:2E" "$home/pico-8/bbs" "$home/pico-8/carts"
printf 'pairing-key\n' > "$link/B8:27:EB:58:92:2E/info"
pairing_sum=$(sha256sum "$link/B8:27:EB:58:92:2E/info")
printf 'volume=64\n' > "$home/pico-8/config.txt"
printf 'download\n' > "$home/pico-8/bbs/cart.p8"
printf 'save\n' > "$home/pico-8/carts/progress.p8d.txt"
PICOOS_STATE_ROOT_PREFIX="$work/slot-b" sh "$helper" prepare
test "$(readlink "$work/slot-b/root/.lexaloffle")" = "$target"
cmp "$home/pico-8/config.txt" "$work/slot-b/root/.lexaloffle/pico-8/config.txt"
test "$(cat "$work/slot-b/root/.lexaloffle/pico-8/bbs/cart.p8")" = download
test "$(cat "$work/slot-b/root/.lexaloffle/pico-8/carts/progress.p8d.txt")" = save
test "$(sha256sum "$link/B8:27:EB:58:92:2E/info")" = "$pairing_sum"

# Existing root data must never be silently moved, merged or overwritten.
rm "$home"
mkdir -p "$home/pico-8/bbs" "$home/pico-8/carts"
chmod 700 "$home"
printf 'volume=32\n' > "$home/pico-8/config.txt"
printf 'original download\n' > "$home/pico-8/bbs/cart.p8"
printf 'original save\n' > "$home/pico-8/carts/save with spaces.p8d.txt"
printf 'hidden\n' > "$home/.hidden"
chmod 600 "$home/pico-8/config.txt"
ln -s config.txt "$home/pico-8/config-link"
expect_failure prepare nonempty-pico8-home
test -d "$home" && test ! -L "$home"
test "$(cat "$home/pico-8/config.txt")" = volume=32
expect_failure migrate-pico8 conflicting-pico8-target
test "$(cat "$target/pico-8/config.txt")" = volume=64
test ! -e "$home.picoos-backup"

# Isolated fixture reset: a fresh persistent home permits explicit migration.
rm -rf "$target"
mkdir "$target"
mkdir "$home.picoos-backup"
expect_failure migrate-pico8 existing-backup
rmdir "$home.picoos-backup"
rmdir "$target"
ln -s "$work/elsewhere" "$target"
expect_failure migrate-pico8 symlink-target
expect_failure prepare symlink-prepare-target
test "$(readlink "$target")" = "$work/elsewhere"
rm "$target"

# Reject insufficient reserve before staging or copying, including just below the boundary.
mkdir "$work/bin"
cat > "$work/bin/df" <<'EOF'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'state 131072 0 %s 0%% %s\n' "$PICOOS_TEST_AVAILABLE_KIB" "$PICOOS_STATE_MOUNT_DIR"
EOF
chmod 755 "$work/bin/df"
source_kib=$(du -sk "$home" | awk '{print $1}')
required_kib=$((source_kib + 16 * 1024))
PICOOS_TEST_AVAILABLE_KIB=$((required_kib - 1)) PATH="$work/bin:$PATH" \
    expect_failure migrate-pico8 insufficient-reserve
grep -q 'enlarge the state image offline' "$work/insufficient-reserve.log"
test ! -e "$work/persist/.pico8-home.migrating"
test ! -e "$target"
test ! -e "$home.picoos-backup"
test "$(cat "$home/pico-8/config.txt")" = volume=32
test "$(sha256sum "$link/B8:27:EB:58:92:2E/info")" = "$pairing_sum"

# At the exact reserve boundary, copying starts; a failed copy retains the original.
cat > "$work/bin/cp" <<'EOF'
#!/bin/sh
printf 'incomplete\n' > "$PICOOS_STATE_MOUNT_DIR/.pico8-home.migrating/partial"
exit 1
EOF
chmod 755 "$work/bin/cp"
PICOOS_TEST_AVAILABLE_KIB="$required_kib" PATH="$work/bin:$PATH" \
    expect_failure migrate-pico8 failed-copy
test "$(cat "$home/pico-8/config.txt")" = volume=32
test ! -e "$home.picoos-backup"
test ! -e "$target"
test -f "$work/persist/.pico8-home.migrating/partial"
expect_failure migrate-pico8 incomplete-stage
rm "$work/persist/.pico8-home.migrating/partial"
rmdir "$work/persist/.pico8-home.migrating"

sh "$helper" migrate-pico8
test "$(readlink "$home")" = "$target"
test -d "$home.picoos-backup" && test ! -L "$home.picoos-backup"
diff -r "$home.picoos-backup" "$target"
test "$(stat -c %a "$target/pico-8/config.txt")" = 600
test "$(readlink "$target/pico-8/config-link")" = config.txt
test "$(cat "$target/.hidden")" = hidden
sh "$helper" prepare
expect_failure migrate-pico8 already-linked-home
test "$(sha256sum "$link/B8:27:EB:58:92:2E/info")" = "$pairing_sum"

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
