#!/bin/bash
set -euo pipefail
umask 077

fail() { echo "Error: $*" >&2; exit 1; }
[ "$#" -eq 2 ] || fail "Usage: sudo bash $0 BOOT_PARTITION {test|restore}"
[ "$EUID" -eq 0 ] || fail "Run with sudo."
partition=$(readlink -e -- "$1")
mode=$2
case "$mode" in test|restore) ;; *) fail "Expected test or restore." ;; esac
[ -b "$partition" ] &&
    [ "$(lsblk -dn -o TYPE "$partition")" = part ] &&
    [ "$(lsblk -dn -o PARTN "$partition")" = 1 ] &&
    [ "$(lsblk -dnb -o SIZE "$partition")" = 67108864 ] &&
    [ "$(blkid -p -s TYPE -o value "$partition")" = vfat ] &&
    [ "$(blkid -p -s VERSION -o value "$partition")" = FAT32 ] ||
    fail "Expected the 64 MiB FAT32 A/B boot partition p1."
if findmnt -rn -S "$partition" >/dev/null; then
    fail "Boot partition is already mounted."
fi
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/uboot-uart.XXXXXX")
export TMPDIR="$work"
mounted=no
cleanup() {
    if [ "$mounted" = yes ]; then
        if ! umount "$work/boot"; then
            echo "ERROR: Unmount failed; leave the card inserted." >&2
            return 1
        fi
    fi
    rm -rf -- "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir "$work/boot"
mount -t vfat -o nosuid,nodev,noexec,uid=0,gid=0,fmask=0177,dmask=0077 "$partition" "$work/boot"
mounted=yes
config="$work/boot/config.txt"
saved="$work/boot/config-before-uart-test.txt"
[ -s "$work/boot/u-boot.bin" ] && [ -s "$config" ] ||
    fail "Missing U-Boot or firmware configuration."
grep -Fxq 'kernel=u-boot.bin' "$config" &&
    grep -Fxq 'arm_64bit=0' "$config" &&
    grep -Fxq 'enable_uart=1' "$config" ||
    fail "Unexpected U-Boot firmware settings."
if [ "$mode" = test ]; then
    [ ! -e "$saved" ] || fail "UART test backup already exists; inspect or restore it first."
    [ "$(grep -Fxc 'dtoverlay=miniuart-bt' "$config")" -eq 1 ] ||
        fail "Expected exactly one miniuart-bt overlay."
    sed '/^dtoverlay=miniuart-bt$/d' "$config" > "$work/candidate.txt"
    cp "$config" "$saved"
    cmp "$config" "$saved"
    sync
    cp "$work/candidate.txt" "$config"
    cmp "$work/candidate.txt" "$config"
else
    [ -s "$saved" ] || fail "Original boot configuration backup not found."
    sed '/^dtoverlay=miniuart-bt$/d' "$saved" > "$work/candidate.txt"
    cmp "$work/candidate.txt" "$config" ||
        fail "Configuration changed since UART test; refusing to overwrite it."
    cp "$saved" "$config"
    cmp "$saved" "$config"
fi
sync
umount "$work/boot"
mounted=no
echo "U-Boot UART test action '$mode' completed; boot partition unmounted."
echo "Only p1 firmware configuration was changed. No image, system slot, data or boot environment was written."
