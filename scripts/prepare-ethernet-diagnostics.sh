#!/bin/bash
set -euo pipefail
umask 077

fail() { echo "Error: $*" >&2; exit 1; }

[ "$#" -eq 2 ] || fail "Usage: sudo bash $0 ROOTFS_PARTITION PUBLIC_KEY"
[ "$EUID" -eq 0 ] || fail "Run with sudo."
partition=$(readlink -e -- "$1")
key=$(readlink -e -- "$2")
[ -b "$partition" ] || fail "Rootfs partition is not a block device."
[ "$(lsblk -dn -o TYPE "$partition")" = part ] || fail "Expected a partition."
[ "$(blkid -s TYPE -o value "$partition")" = ext4 ] || fail "Expected ext4."
[ "$(blkid -s LABEL -o value "$partition")" = rootfs ] || fail "Expected rootfs label."
[ -f "$key" ] || fail "Public key is not a regular file."
ssh-keygen -lf "$key"
if findmnt -rn -S "$partition" >/dev/null; then
    fail "Partition is already mounted; unmount it first."
fi
work=$(mktemp -d)
mounted=no
cleanup() {
    if [ "$mounted" = yes ]; then
        if ! umount "$work"; then
            echo "ERROR: Unmount failed at $work; do not remove the card." >&2
            return 1
        fi
    fi
    rmdir "$work"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mount -o nosuid,nodev,noexec "$partition" "$work"
mounted=yes
[ -f "$work/etc/network/pico8-wifi" ] || fail "Not the expected PicoOS rootfs."
[ -f "$work/usr/sbin/dropbear" ] && [ -s "$work/usr/sbin/dropbear" ] ||
    fail "Dropbear is missing or empty."
dropbear_mode=$(stat -c %a "$work/usr/sbin/dropbear")
(( (8#$dropbear_mode & 0111) != 0 )) || fail "Dropbear has no executable permission bits."
[ -d "$work/root" ] && [ ! -L "$work/root" ] || fail "Unexpected root home."
if grep -Eq '^[[:space:]]*iface[[:space:]]+eth0[[:space:]]' "$work/etc/network/interfaces"; then
    fail "eth0 is already configured; inspect before changing it."
fi
for path in root/.ssh etc/default/dropbear etc/modules-load.d/ethernet.conf; do
    [ ! -L "$work/$path" ] || fail "Unexpected symlink: $path"
done
[ ! -e "$work/root/.ssh/authorized_keys" ] ||
    fail "Existing authorized_keys; inspect before replacing it."
backup="$work/root/ethernet-diagnostics-backup-$(date +%Y%m%d-%H%M%S).tar"
paths=(etc/network/interfaces etc/avahi/avahi-daemon.conf)
for path in etc/default/dropbear etc/modules-load.d/ethernet.conf; do
    if [ -e "$work/$path" ]; then paths+=("$path"); fi
done
tar -C "$work" -cf "$backup" "${paths[@]}"
chmod 600 "$backup"
printf '\nauto eth0\niface eth0 inet dhcp\n    hostname pico8\n' >> "$work/etc/network/interfaces"
install -d -m 755 "$work/etc/modules-load.d" "$work/etc/default"
printf 'asix\nax88179_178a\n' > "$work/etc/modules-load.d/ethernet.conf"
printf 'DROPBEAR_ARGS="-s"\n' > "$work/etc/default/dropbear"
chmod 644 "$work/etc/modules-load.d/ethernet.conf" "$work/etc/default/dropbear"
install -d -m 700 "$work/root/.ssh"
install -m 600 "$key" "$work/root/.ssh/authorized_keys"
sed -i 's/^allow-interfaces=wlan0$/allow-interfaces=wlan0,eth0/' "$work/etc/avahi/avahi-daemon.conf"
cmp "$key" "$work/root/.ssh/authorized_keys"
sync
umount "$work"
mounted=no
echo "Ethernet DHCP and temporary root key-only SSH configured; partition unmounted."
echo "Original configuration archived under /root/$(basename "$backup")."
echo "No image was flashed and /data was not changed."
echo "USB host-mode compatibility and live connectivity still need hardware verification."
