#!/bin/bash
set -euo pipefail
umask 077

[ "$#" -eq 3 ] || { echo "Usage: bash $0 MKENVIMAGE FW_PRINTENV FW_SETENV" >&2; exit 1; }
mkenvimage=$(command -v "$1")
fw_printenv=$(command -v "$2")
fw_setenv=$(command -v "$3")
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/test-env.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
"$mkenvimage" -r -s 0x10000 -o "$work/env.bin" \
    "$project_dir/br2-external/board/zero2w/u-boot.env"
truncate -s 1M "$work/disk"
dd if="$work/env.bin" of="$work/disk" bs=65536 seek=4 conv=notrunc status=none
dd if="$work/env.bin" of="$work/disk" bs=65536 seek=6 conv=notrunc status=none
cat > "$work/config" <<EOF
uboot:
  size: 0x10000
  lockfile: $work/environment.lock
  devices:
    - path: $work/disk
      offset: 0x40000
      sectorsize: 0x10000
    - path: $work/disk
      offset: 0x60000
      sectorsize: 0x10000
EOF
[ "$("$fw_printenv" -c "$work/config" -n boot_slot)" = A ]
"$fw_setenv" -c "$work/config" boot_slot B
[ "$("$fw_printenv" -c "$work/config" -n boot_slot)" = B ]
"$fw_setenv" -c "$work/config" upgrade_available 1
"$fw_setenv" -c "$work/config" recovery_status in_progress
# Exercise the exact libubootenv input emitted by the boot health service.
awk '/cat > \/run\/picoos-confirm.env <<EOF/ { printing=1; next }
     printing && /^EOF$/ { exit }
     printing { print }' \
    "$project_dir/br2-external/board/zero2w/overlay/etc/init.d/S99picoos-health" |
    sed 's/$slot/B/' > "$work/confirm.env"
test -s "$work/confirm.env"
"$fw_setenv" -c "$work/config" -s "$work/confirm.env"
[ "$("$fw_printenv" -c "$work/config" -n stable_slot)" = B ]
[ "$("$fw_printenv" -c "$work/config" -n upgrade_available)" = 0 ]
[ "$("$fw_printenv" -c "$work/config" -n bootcount)" = 0 ]
if [ -n "$("$fw_printenv" -c "$work/config" -n recovery_status)" ]; then
    echo "Health confirmation did not remove the transaction marker." >&2
    exit 1
fi
# Each CRC-valid redundant copy must still be readable if its peer is corrupt.
cp "$work/disk" "$work/confirmed"
for offset in 262144 393216; do
    cp "$work/confirmed" "$work/disk"
    dd if=/dev/zero of="$work/disk" bs=1 seek="$offset" count=65536 conv=notrunc status=none
    "$fw_printenv" -c "$work/config" -n boot_slot > "$work/surviving-slot"
    grep -Eq '^[AB]$' "$work/surviving-slot"
done
echo "Native libubootenv tests passed (redundant CRC layout, saves, exact health confirmation and either-copy corruption)."
