#!/bin/bash
set -euo pipefail
umask 077

fail() { echo "Error: $*" >&2; exit 1; }
[ "$#" -eq 3 ] || fail "Usage: sudo bash $0 IMAGE WHOLE_SD_DEVICE VERIFIED_BACKUP_DIR"
[ "$EUID" -eq 0 ] || fail "Run with sudo."
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image=$(readlink -e -- "$1")
device=$(readlink -e -- "$2")
backup=$(readlink -e -- "$3")
key="$project_dir/provisioning/data/ssh/base-key.pub"
[ -d "$backup/verify-data" ] && [ ! -L "$backup/verify-data" ] &&
    [ -s "$backup/before.sha256" ] || fail "Missing verified data tree or manifest."
[ -z "$(find "$backup/verify-data" ! -type f ! -type d -print -quit)" ] ||
    fail "Data backup must contain only regular files and directories."
(cd "$backup" && sha256sum --strict -c archives.sha256)
(cd "$backup/verify-data" && sha256sum --strict --quiet -c ../before.sha256)
cmp "$backup/before.sha256" "$backup/after.sha256"
[ "$(find "$backup/verify-data" -type f | wc -l)" -eq "$(wc -l < "$backup/before.sha256")" ] ||
    fail "Data backup file count does not match its manifest."
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/ab-test-card.XXXXXX")
export TMPDIR="$work"
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
tar -xOf "$backup/diagnostics-private.tar" etc/dropbear/dropbear_ed25519_host_key > "$work/host-key"
[ -s "$work/host-key" ] || fail "Missing backed-up Ed25519 host key."
chmod 600 "$work/host-key"

bash "$project_dir/scripts/flash-and-provision.sh" "$image" "$device"
partition() {
    lsblk -nrpo NAME,PARTN "$device" | awk -v n="$1" '$2 == n { print $1 }'
}
for slot in 2 3; do
    root_partition=$(partition "$slot")
    [ -b "$root_partition" ] || fail "System partition $slot not found."
    bash "$project_dir/scripts/prepare-ethernet-diagnostics.sh" \
        "$root_partition" "$key" "$work/host-key"
done
data_partition=$(partition 4)
[ -b "$data_partition" ] &&
    [ "$(blkid -p -s TYPE -o value "$data_partition")" = vfat ] &&
    [ "$(blkid -p -s VERSION -o value "$data_partition")" = FAT32 ] &&
    [ "$(blkid -p -s LABEL -o value "$data_partition")" = PICOOS-DATA ] ||
    fail "Expected FAT32 data partition p4."
if lsblk -nr -o MOUNTPOINTS "$device" | grep -q '[^[:space:]]'; then
    fail "A target partition was automounted; unmount before continuing."
fi
mkdir "$work/data"
mount -t vfat -o nosuid,nodev,noexec,uid=0,gid=0,fmask=0177,dmask=0077,utf8=1 \
    "$data_partition" "$work/data"
mounted=yes
cp -R -- "$backup/verify-data/." "$work/data/"
(cd "$work/data" && sha256sum --strict --quiet -c "$backup/before.sha256")
sync
umount "$work/data"
mounted=no
echo "A/B test card prepared: both slots have key-only Ethernet SSH and the original host key."
echo "All backed-up data files restored and SHA256-verified on FAT32 p4; partitions unmounted."
echo "Hardware boot, watchdog and rollback remain unverified."
