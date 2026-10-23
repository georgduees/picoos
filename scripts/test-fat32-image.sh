#!/bin/bash
set -euo pipefail

if [ "$#" -ne 1 ]; then
    echo "Usage: bash $0 DIRECTORY_WITH_EXISTING_IMAGE_FILES" >&2
    exit 1
fi
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fixture=$(readlink -e -- "$1")
for tool in genimage mkfs.fat fsck.fat mcopy mdir sfdisk blkid debugfs; do
    command -v "$tool" >/dev/null
done
# Load the same pre-write image validation used by the flash helper.
source "$project_dir/scripts/flash-and-provision.sh"
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/test-image.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/images" "$work/build" "$work/host/sbin" "$work/host/bin"
for file in u-boot.bin uboot-env.bin bcm2710-rpi-zero-2-w.dtb rootfs.ext4; do
    cp --reflink=auto "$fixture/$file" "$work/images/"
done
cp -a "$fixture/rpi-firmware" "$work/images/"
ln -s "$(command -v mkfs.fat)" "$work/host/sbin/mkfs.fat"
ln -s "$(command -v mcopy)" "$work/host/bin/mcopy"
BUILD_DIR="$work/build" HOST_DIR="$work/host" BINARIES_DIR="$work/images" \
    BR2_EXTERNAL_PICOOS_PATH="$project_dir/br2-external" \
    sh "$project_dir/br2-external/board/zero2w/post-image.sh"

test "$(stat -c %s "$work/images/data.vfat")" -eq 1073741824
test "$(blkid -p -s VERSION -o value "$work/images/data.vfat")" = FAT32
test "$(blkid -p -s LABEL -o value "$work/images/data.vfat")" = PICOOS-DATA
fsck.fat -n "$work/images/data.vfat"
validate_data_image "$work/images/sdcard.img"
mcopy -i "$work/images/boot.vfat" ::config.txt "$work/boot-config.txt"
cmp "$project_dir/br2-external/board/zero2w/config.txt" "$work/boot-config.txt"
grep -Fxq 'kernel=u-boot.bin' "$work/boot-config.txt"
grep -Fxq 'enable_uart=1' "$work/boot-config.txt"
grep -Fxq 'gpu_mem_512=64' "$work/boot-config.txt"
if grep -Eq '^dtoverlay=(pi3-)?miniuart-bt([,[:space:]]|$)' "$work/boot-config.txt"; then
    echo "Shared firmware must retain the mini-UART for rpi_3_32b U-Boot." >&2
    exit 1
fi
if grep -Eq 'miniuart-bt|btattach|ttyAMA0' "$project_dir/br2-external/board/zero2w/u-boot.env"; then
    echo "Bluetooth must stay on the PL011 UART (no miniuart overlay, btattach or ttyAMA0 console)." >&2
    exit 1
fi
grep -Fq "/boot/overlays/vc4-kms-v3d.dtbo" "$project_dir/br2-external/board/zero2w/u-boot.env"
grep -Fq "else true; fi" "$project_dir/br2-external/board/zero2w/u-boot.env"
debugfs -R "dump /boot/overlays/vc4-kms-v3d.dtbo $work/slot-vc4-kms-v3d.dtbo" "$work/images/rootfs.ext4"
cmp "$work/slot-vc4-kms-v3d.dtbo" "$work/images/rpi-firmware/overlays/vc4-kms-v3d.dtbo"
# Mesa 26 installs the Gallium drivers in a shared library, not dri/vc4_dri.so.
mesa_version=$(sed -n 's/^MESA3D_VERSION = //p' "$project_dir/buildroot/package/mesa3d/mesa3d.mk")
test -n "$mesa_version"
debugfs -R "stat /usr/lib/libgallium-$mesa_version.so" "$work/images/rootfs.ext4" \
    > "$work/gallium-stat" 2>&1
if ! grep -Eq 'Type:[[:space:]]*regular' "$work/gallium-stat"; then
    cat "$work/gallium-stat" >&2
    echo "Mesa Gallium runtime library missing from rootfs." >&2
    exit 1
fi

debugfs -R 'stat /usr/lib/libSDL2-2.0.so.0' "$work/images/rootfs.ext4" \
    > "$work/sdl2-runtime-link" 2>&1
grep -q 'Type:[[:space:]]*symlink' "$work/sdl2-runtime-link"
grep -q 'Fast link dest:' "$work/sdl2-runtime-link"
for path in usr/bin/bluetoothctl usr/libexec/bluetooth/bluetoothd usr/bin/jstest; do
    debugfs -R "stat /$path" "$work/images/rootfs.ext4" 2>/dev/null |
        grep -Eq 'Mode:[[:space:]]+0755'
done
for path in usr/sbin/picoos-diagnostics usr/sbin/picoos-state \
    etc/init.d/S30picoos-diagnostics etc/init.d/S35picoos-state \
    etc/init.d/S50dropbear \
    etc/init.d/S99picoos-health \
    etc/network/interfaces etc/avahi/avahi-daemon.conf; do
    debugfs -R "dump /$path $work/installed-file" "$work/images/rootfs.ext4"
    test -s "$work/installed-file"
    cmp "$work/installed-file" "$project_dir/br2-external/board/zero2w/overlay/$path"
    rm "$work/installed-file"
    case "$path" in
        usr/sbin/*|etc/init.d/*)
            debugfs -R "stat /$path" "$work/images/rootfs.ext4" 2>/dev/null |
                grep -Eq 'Mode:[[:space:]]+0755'
            ;;
    esac
done
debugfs -R "dump /etc/modules-load.d/bluetooth.conf $work/bluetooth-modules" \
    "$work/images/rootfs.ext4"
cmp "$work/bluetooth-modules" \
    "$project_dir/br2-external/board/zero2w/overlay/etc/modules-load.d/bluetooth.conf"
debugfs -R "dump /etc/modules-load.d/graphics.conf $work/graphics-modules" \
    "$work/images/rootfs.ext4"
cmp "$work/graphics-modules" \
    "$project_dir/br2-external/board/zero2w/overlay/etc/modules-load.d/graphics.conf"

for path in /etc/picoos-diagnostics-import /root/.ssh/authorized_keys \
    /etc/dropbear/dropbear_ed25519_host_key; do
    debugfs -R "dump $path $work/forbidden-file" "$work/images/rootfs.ext4" 2>/dev/null
    if [ -e "$work/forbidden-file" ]; then
        echo "Local diagnostic credentials or activation unexpectedly included: $path" >&2
        exit 1
    fi
done
dd if="$work/images/sdcard.img" of="$work/environment-a" bs=65536 skip=4 count=1 status=none
dd if="$work/images/sdcard.img" of="$work/environment-b" bs=65536 skip=6 count=1 status=none
cmp "$work/images/uboot-env.bin" "$work/environment-a"
cmp "$work/images/uboot-env.bin" "$work/environment-b"
mcopy -i "$work/images/data.vfat" ::/network/wpa_supplicant.conf.example "$work/example"
cmp "$work/example" "$project_dir/br2-external/board/zero2w/data/wpa_supplicant.conf.example"
mcopy -i "$work/images/data.vfat" ::/ssh/base-key.pub "$work/public-key"
cmp "$work/public-key" "$project_dir/provisioning/data/ssh/base-key.pub"
mdir -i "$work/images/data.vfat" ::/carts ::/pico8
if mdir -i "$work/images/data.vfat" ::/network/wpa_supplicant.conf >/dev/null 2>&1; then
    echo "Private WLAN configuration unexpectedly included in image." >&2
    exit 1
fi
if mdir -i "$work/images/data.vfat" ::/diagnostics >/dev/null 2>&1; then
    echo "Private diagnostic persistence unexpectedly included in public data image." >&2
    exit 1
fi

expect_rejection() {
    if (validate_data_image "$1") > "$work/rejection.log" 2>&1; then
        echo "Invalid image unexpectedly accepted: $1" >&2
        exit 1
    fi
}
offset=$(sfdisk --dump "$work/images/sdcard.img" | awk '/ : start=/ { n++; if (n == 4) { split($0, parts, "start="); split(parts[2], fields, ","); gsub(/[[:space:]]/, "", fields[1]); print fields[1] } }')
cp --reflink=auto "$work/images/sdcard.img" "$work/ext4.img"
dd if="$work/images/rootfs.ext4" of="$work/ext4.img" bs=512 seek="$offset" conv=notrunc status=none
expect_rejection "$work/ext4.img"
# Keep the valid FAT32 MBR type but replace its filesystem with FAT16.
cp --reflink=auto "$work/images/sdcard.img" "$work/fat16.img"
mkfs.fat -F 16 -n PICOOS-DATA -C "$work/fat16.vfat" 262144
dd if="$work/fat16.vfat" of="$work/fat16.img" bs=512 seek="$offset" conv=notrunc status=none
expect_rejection "$work/fat16.img"
echo "A/B FAT32 image tests passed (UART boot settings, slot overlay, layout, redundant environments, 1 GiB data, seed and ext4/FAT16 rejection)."
