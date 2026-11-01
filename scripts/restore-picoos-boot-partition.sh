#!/bin/bash
set -euo pipefail
umask 077

fail() { echo "Error: $*" >&2; exit 1; }
[ "$#" -eq 3 ] ||
    fail "Usage: sudo bash $0 P1_BACKUP_IMAGE SHA256_MANIFEST WHOLE_SD_DEVICE"
[ "$EUID" -eq 0 ] || fail "Run this script with sudo."
for tool in readlink stat lsblk blockdev sfdisk blkid findmnt sha256sum dd cmp fsck.vfat; do
    command -v "$tool" >/dev/null || fail "Required tool not found: $tool"
done

image=$(readlink -e -- "$1") || fail "Backup image does not exist."
manifest=$(readlink -e -- "$2") || fail "SHA-256 manifest does not exist."
device=$(readlink -e -- "$3") || fail "Target device does not exist."
[ -f "$image" ] && [ ! -L "$image" ] && [ "$(stat -c %s "$image")" -eq 67108864 ] ||
    fail "Expected a regular, exact 64 MiB p1 image."
[ -f "$manifest" ] && [ ! -L "$manifest" ] || fail "Invalid SHA-256 manifest."
[ -b "$device" ] && [ "$(lsblk -dn -o TYPE "$device")" = disk ] ||
    fail "Select the whole SD disk, not a partition."
[ "$(blockdev --getro "$device")" = 0 ] || fail "Target disk is read-only."
[ "$(stat -c %a "$image")" = 600 ] || fail "Keep the raw backup private (mode 0600)."

read -r expected_image expected_name extra < "$manifest" ||
    fail "Malformed SHA-256 manifest."
[[ "$expected_image" =~ ^[0-9a-f]{64}$ ]] &&
    [ "$expected_name" = p1-before.img ] &&
    [ -z "${extra:-}" ] &&
    [ "$(wc -l < "$manifest")" -eq 1 ] ||
    fail "Manifest must contain one SHA-256 entry for p1-before.img."
[ "$(sha256sum "$image" | cut -d ' ' -f 1)" = "$expected_image" ] ||
    fail "Backup image does not match its manifest."

if lsblk -nr -o MOUNTPOINTS "$device" | grep -q '[^[:space:]]'; then
    fail "Target disk or a child partition is mounted; unmount it first."
fi
image_major_minor=$(findmnt -n -o MAJ:MIN -T "$image") ||
    fail "Cannot identify the backup image's filesystem."
while IFS= read -r target_major_minor; do
    [ "$image_major_minor" != "$target_major_minor" ] ||
        fail "Copy the backup image off the target SD before restoring it."
done < <(lsblk -nr -o MAJ:MIN "$device")

partitions=$(sfdisk --dump "$device") || fail "Cannot read target partition table."
[ "$(printf '%s\n' "$partitions" | awk '/^label:/ { print $2 }')" = dos ] &&
    [ "$(printf '%s\n' "$partitions" | awk '/^sector-size:/ { print $2 }')" = 512 ] ||
    fail "Expected the PicoOS DOS/MBR layout."
mapfile -t entries < <(printf '%s\n' "$partitions" | awk '/ : start=/')
starts=(2048 133120 1181696 2230272)
sizes=(131072 1048576 1048576 2097152)
[ "${#entries[@]}" -eq 4 ] || fail "Expected four PicoOS partitions."
for i in 0 1 2 3; do
    entry=${entries[$i]}
    start=$(printf '%s\n' "$entry" | awk -F 'start=' '{ split($2, a, ","); gsub(/[[:space:]]/, "", a[1]); print a[1] }')
    size=$(printf '%s\n' "$entry" | awk -F 'size=' '{ split($2, a, ","); gsub(/[[:space:]]/, "", a[1]); print a[1] }')
    [ "$start" = "${starts[$i]}" ] && [ "$size" = "${sizes[$i]}" ] ||
        fail "Unexpected PicoOS partition $((i + 1)); refusing to write."
done
p1=$(lsblk -nrpo NAME,PARTN "$device" | awk '$2 == 1 { print $1 }')
[ -b "$p1" ] &&
    [ "$(blockdev --getsize64 "$p1")" -eq 67108864 ] &&
    [ "$(blkid -p -s TYPE -o value "$p1")" = vfat ] ||
    fail "Partition 1 is not the expected 64 MiB FAT boot partition."

lsblk -o NAME,PATH,SIZE,MODEL,SERIAL,TYPE,MOUNTPOINTS "$device"
echo "ONLY p1 (64 MiB shared boot partition) will be restored from $image."
read -r -p "Type the exact target disk path ($device) to confirm: " confirmation
[ "$confirmation" = "$device" ] || fail "Confirmation did not match; nothing written."

dd if="$image" of="$p1" bs=4M conv=fsync status=progress
cmp "$image" "$p1"
fsck.vfat -n "$p1"
echo "Original boot partition restored and read-back verified. p2/p3/p4 were not written."
