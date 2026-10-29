#!/bin/bash
set -euo pipefail
umask 077

fail() {
    echo "Error: $*" >&2
    exit 1
}

validate_data_image() {
    local image=$1 partitions data_entry data_start data_offset i entry start size
    local -a entries starts=(2048 133120 1181696 2230272)
    local -a sizes=(131072 1048576 1048576 2097152)
    partitions=$(sfdisk --dump "$image") || fail "Could not read image partition table."
    [ "$(printf '%s\n' "$partitions" | awk '/^label:/ { print $2 }')" = dos ] &&
        [ "$(printf '%s\n' "$partitions" | awk '/^sector-size:/ { print $2 }')" = 512 ] ||
        fail "Expected a DOS partition table with 512-byte sectors."
    mapfile -t entries < <(printf '%s\n' "$partitions" | awk '/ : start=/')
    [ "${#entries[@]}" -eq 4 ] ||
        fail "Expected exactly four partitions (boot, system A, system B, data)."
    for i in 0 1 2 3; do
        entry=${entries[$i]}
        start=$(printf '%s\n' "$entry" | awk -F 'start=' '{ split($2, a, ","); gsub(/[[:space:]]/, "", a[1]); print a[1] }')
        size=$(printf '%s\n' "$entry" | awk -F 'size=' '{ split($2, a, ","); gsub(/[[:space:]]/, "", a[1]); print a[1] }')
        [ "$start" = "${starts[$i]}" ] && [ "$size" = "${sizes[$i]}" ] ||
            fail "Unexpected A/B layout at partition $((i + 1))."
        if [ "$i" -eq 1 ] || [ "$i" -eq 2 ]; then
            printf '%s\n' "$entry" | grep -Eq 'type=83([,[:space:]]|$)' &&
                [ "$(blkid -p -O "$((start * 512))" -s TYPE -o value "$image")" = ext4 ] ||
                fail "System slot must be Linux/ext4."
        fi
    done
    data_entry=${entries[3]}
    printf '%s\n' "$data_entry" | grep -Eq 'type=(0?[cC])([,[:space:]]|$)' ||
        fail "Expected a FAT32 LBA data partition (type 0x0C)."
    data_start=$(printf '%s\n' "$data_entry" | awk -F 'start=' '{ split($2, fields, ","); gsub(/[[:space:]]/, "", fields[1]); print fields[1] }')
    [[ "$data_start" =~ ^[0-9]+$ ]] || fail "Invalid data partition offset."
    data_offset=$((data_start * 512))
    [ "$(blkid -p -O "$data_offset" -s TYPE -o value "$image")" = vfat ] &&
        [ "$(blkid -p -O "$data_offset" -s VERSION -o value "$image")" = FAT32 ] &&
        [ "$(blkid -p -O "$data_offset" -s LABEL -o value "$image")" = PICOOS-DATA ] ||
        fail "Image data filesystem must be FAT32 with label PICOOS-DATA."
}

if [[ "${BASH_SOURCE[0]}" != "$0" ]]; then
    return
fi

if [ "$#" -ne 2 ]; then
    echo "Usage: sudo bash $0 IMAGE WHOLE_SD_DEVICE" >&2
    exit 1
fi
[ "$EUID" -eq 0 ] || fail "Run this script with sudo."
for tool in lsblk readlink stat dd cmp blockdev udevadm mount umount mountpoint \
    unzip cp find sync sfdisk blkid awk grep; do
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

validate_data_image "$image"

mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/provision.XXXXXX")
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
data_partition=$(lsblk -nrpo NAME,PARTN "$device" | awk '$2 == 4 { print $1 }')
[ -b "$data_partition" ] || fail "Fourth partition was not found."
[ "$(blkid -p -s TYPE -o value "$data_partition")" = vfat ] &&
    [ "$(blkid -p -s VERSION -o value "$data_partition")" = FAT32 ] ||
    fail "Fourth partition is not FAT32."
[ "$(blkid -p -s LABEL -o value "$data_partition")" = PICOOS-DATA ] ||
    fail "Fourth partition does not have the expected PICOOS-DATA label."
if lsblk -nr -o MOUNTPOINTS "$device" | grep -q '[^[:space:]]'; then
    fail "A partition was automounted after flashing. Unmount it before provisioning."
fi

mkdir "$work/data"
mount -t vfat -o nosuid,nodev,noexec,uid=0,gid=0,fmask=0177,dmask=0077,utf8=1 \
    "$data_partition" "$work/data"
mounted=yes
mkdir -p "$work/data/network" "$work/data/ssh" "$work/data/pico8" "$work/data/carts"
cp "$wifi" "$work/data/network/wpa_supplicant.conf"
cp "$key" "$work/data/ssh/base-key.pub"
for source in "$work/extracted/pico-8/"*; do
    [ -f "$source" ] || fail "Unexpected distribution entry: $source"
    cp "$source" "$work/data/pico8/"
    cmp "$source" "$work/data/pico8/$(basename "$source")"
done
cmp "$wifi" "$work/data/network/wpa_supplicant.conf"
cmp "$key" "$work/data/ssh/base-key.pub"
sync
umount "$work/data"
mounted=no
echo "Image and local data written and verified. The SD card can now be safely removed."
echo "PICO-8 runtime dependencies and SSH account activation still need separate verification."
