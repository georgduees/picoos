#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: bash $0 DIRECTORY_WITH_EXISTING_IMAGE_FILES" >&2
    exit 1
fi
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(readlink -e -- "$1")
for tool in genimage mkfs.fat fsck.fat mcopy mdir sfdisk blkid; do
    command -v "$tool" >/dev/null
done
# Load the same pre-write image validation used by the flash helper.
source "$project_dir/scripts/flash-and-provision.sh"
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/images" "$work/build" "$work/host/sbin" "$work/host/bin"
for file in zImage bcm2710-rpi-zero-2-w.dtb rootfs.ext4; do
    cp --reflink=auto "$fixture/$file" "$work/images/"
done
cp -a "$fixture/rpi-firmware" "$work/images/"
ln -s "$(command -v mkfs.fat)" "$work/host/sbin/mkfs.fat"
ln -s "$(command -v mcopy)" "$work/host/bin/mcopy"
BUILD_DIR="$work/build" HOST_DIR="$work/host" BINARIES_DIR="$work/images" \
    BR2_EXTERNAL_PICOOS_PATH="$project_dir/br2-external" \
    sh "$project_dir/br2-external/board/zero2w/post-image.sh"

test "$(stat -c %s "$work/images/data.vfat")" -eq 268435456
test "$(blkid -p -s VERSION -o value "$work/images/data.vfat")" = FAT32
test "$(blkid -p -s LABEL -o value "$work/images/data.vfat")" = PICOOS-DATA
fsck.fat -n "$work/images/data.vfat"
validate_data_image "$work/images/sdcard.img"
mcopy -i "$work/images/data.vfat" ::/network/wpa_supplicant.conf.example "$work/example"
cmp "$work/example" "$project_dir/br2-external/board/zero2w/data/wpa_supplicant.conf.example"
mcopy -i "$work/images/data.vfat" ::/ssh/base-key.pub "$work/public-key"
cmp "$work/public-key" "$project_dir/provisioning/data/ssh/base-key.pub"
mdir -i "$work/images/data.vfat" ::/carts ::/pico8
if mdir -i "$work/images/data.vfat" ::/network/wpa_supplicant.conf >/dev/null 2>&1; then
    echo "Private WLAN configuration unexpectedly included in image." >&2
    exit 1
fi

expect_rejection() {
    if (validate_data_image "$1") > "$work/rejection.log" 2>&1; then
        echo "Invalid image unexpectedly accepted: $1" >&2
        exit 1
    fi
}
offset=$(sfdisk --dump "$work/images/sdcard.img" | awk '/ : start=/ { n++; if (n == 3) { split($0, parts, "start="); split(parts[2], fields, ","); gsub(/[[:space:]]/, "", fields[1]); print fields[1] } }')
cp --reflink=auto "$work/images/sdcard.img" "$work/ext4.img"
dd if="$work/images/rootfs.ext4" of="$work/ext4.img" bs=512 seek="$offset" conv=notrunc status=none
expect_rejection "$work/ext4.img"
# Keep the valid FAT32 MBR type but replace its filesystem with FAT16.
cp --reflink=auto "$work/images/sdcard.img" "$work/fat16.img"
mkfs.fat -F 16 -n PICOOS-DATA -C "$work/fat16.vfat" 262144
dd if="$work/fat16.vfat" of="$work/fat16.img" bs=512 seek="$offset" conv=notrunc status=none
expect_rejection "$work/fat16.img"
echo "FAT32 image tests passed (size, filesystem, MBR, seed and ext4/FAT16 rejection)."
