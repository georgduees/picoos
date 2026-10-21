#!/bin/bash
set -euo pipefail
umask 077

fail() {
    echo "Error: $*" >&2
    exit 1
}

if [ "$#" -ne 2 ]; then
    echo "Usage: sudo bash $0 IMAGE WHOLE_SD_DEVICE" >&2
    exit 1
fi
[ "$EUID" -eq 0 ] || fail "Run this script with sudo."
for tool in lsblk readlink stat dd cmp blockdev udevadm mount umount mountpoint \
    unzip install find sync sfdisk blkid awk grep; do
    command -v "$tool" >/dev/null || fail "Required tool not found: $tool"
done

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image=$(readlink -e -- "$1") || fail "Image does not exist."
device=$(readlink -e -- "$2") || fail "Target does not exist."
archive="$project_dir/pico8/pico-8_0.2.7_raspi.zip"
wifi="$project_dir/provisioning/local/wpa_supplicant.conf"
key="$project_dir/provisioning/data/ssh/base-key.pub"

[ -f "$image" ] && [ -s "$image" ] || fail "Image must be a nonempty regular file."
[ -b "$device" ] || fail "Target is not a block device."
[ "$(lsblk -dn -o TYPE "$device")" = disk ] || fail "Select the whole SD disk, not a partition."
[ "$(blockdev --getro "$device")" = 0 ] || fail "Target is read-only."
[ "$(stat -c %s "$image")" -le "$(blockdev --getsize64 "$device")" ] ||
    fail "Image is larger than the target."
if lsblk -nr -o MOUNTPOINTS "$device" | grep -q '[^[:space:]]'; then
    fail "Target or a child partition is mounted/in use. Unmount it first."
fi
[ -s "$archive" ] || fail "Missing local PICO-8 archive: $archive"
[ -s "$wifi" ] || fail "Run bash scripts/prepare-wifi.sh first."
[ -s "$key" ] || fail "Missing public SSH key: $key"

# Refuse old two-partition images before overwriting the card.
partitions=$(sfdisk --dump "$image")
[ "$(printf '%s\n' "$partitions" | grep -c ' : start=')" -eq 3 ] ||
    fail "Expected an image with exactly three partitions (boot, rootfs, data)."

work=$(mktemp -d)
mounted=no
cleanup() {
    if [ "$mounted" = yes ]; then
        if ! umount "$work/data"; then
            echo "ERROR: Could not unmount $work/data; do not remove the card." >&2
            return 1
        fi
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# The supplied distribution is flat; reject traversal and unexpected paths.
unzip -Z1 "$archive" > "$work/archive-files"
while IFS= read -r entry; do
    [[ "$entry" =~ ^pico-8/([[:alnum:]_.-]+)?$ ]] ||
        fail "Unexpected archive entry: $entry"
    [ "$entry" != pico-8/.. ] && [ "$entry" != pico-8/. ] ||
        fail "Unsafe archive entry."
done < "$work/archive-files"
unzip -q "$archive" -d "$work/extracted"
[ -z "$(find "$work/extracted" -type l -print -quit)" ] ||
    fail "Archive contains symbolic links."
[ -s "$work/extracted/pico-8/pico8" ] &&
    [ -s "$work/extracted/pico-8/pico8.dat" ] || fail "Incomplete PICO-8 distribution."

lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,TYPE,MOUNTPOINTS "$device"
echo "ALL DATA on $device will be overwritten, including existing /data contents."
read -r -p "Type the exact target path ($device) to confirm: " confirmation
[ "$confirmation" = "$device" ] || fail "Confirmation did not match; nothing written."

dd if="$image" of="$device" bs=4M conv=fsync status=progress
cmp -n "$(stat -c %s "$image")" "$image" "$device"
echo "Image read-back verified."
blockdev --rereadpt "$device"
udevadm settle
data_partition=$(lsblk -nrpo NAME,PARTN "$device" | awk '$2 == 3 { print $1 }')
[ -b "$data_partition" ] || fail "Third partition was not found."
[ "$(blkid -s TYPE -o value "$data_partition")" = ext4 ] ||
    fail "Third partition is not ext4."
[ "$(blkid -s LABEL -o value "$data_partition")" = picoos-data ] ||
    fail "Third partition does not have the expected picoos-data label."
if lsblk -nr -o MOUNTPOINTS "$device" | grep -q '[^[:space:]]'; then
    fail "A partition was automounted after flashing. Unmount it before provisioning."
fi

mkdir "$work/data"
mount -o nosuid,nodev,noexec "$data_partition" "$work/data"
mounted=yes
install -d -o root -g root -m 700 "$work/data/network" "$work/data/ssh"
install -d -o root -g root -m 755 "$work/data/pico8" "$work/data/carts"
install -o root -g root -m 600 "$wifi" "$work/data/network/wpa_supplicant.conf"
install -o root -g root -m 644 "$key" "$work/data/ssh/base-key.pub"
for source in "$work/extracted/pico-8/"*; do
    [ -f "$source" ] || fail "Unexpected distribution entry: $source"
    mode=644
    case "$(basename "$source")" in
        pico8|pico8_dyn|pico8_gpio|pico8_64) mode=755 ;;
    esac
    install -o root -g root -m "$mode" "$source" "$work/data/pico8/"
    cmp "$source" "$work/data/pico8/$(basename "$source")"
done
cmp "$wifi" "$work/data/network/wpa_supplicant.conf"
cmp "$key" "$work/data/ssh/base-key.pub"
sync
umount "$work/data"
mounted=no
echo "Image and local data written and verified. The SD card can now be safely removed."
echo "PICO-8 runtime dependencies and SSH account activation still need separate verification."
