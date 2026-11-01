#!/bin/bash
set -euo pipefail
umask 077

project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/test-ab.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/proc/self" "$work/sys/class/block/mmcblk0p2" \
    "$work/sys/class/block/mmcblk0p3" "$work/dev"
export TEST_ROOT="$work"
export PATH="$work/bin:$PATH"
printf '179:2\n' > "$work/sys/class/block/mmcblk0p2/dev"
printf '179:3\n' > "$work/sys/class/block/mmcblk0p3/dev"
touch "$work/dev/mmcblk0p2" "$work/dev/mmcblk0p3"
cat > "$work/bin/stat" <<'EOF'
#!/bin/sh
printf '%s\n' "${TEST_ROOT_DEVICE:-45826}"
EOF
cat > "$work/bin/fw_printenv" <<'EOF'
#!/bin/sh
case "$2" in
    boot_slot|stable_slot) echo "${TEST_ENV_SLOT:-A}" ;;
    upgrade_available) echo "${TEST_UPGRADE:-0}" ;;
    *) exit 1 ;;
esac
EOF
cat > "$work/bin/head" <<'EOF'
#!/bin/sh
test "$1" = -c && test "$2" = 536870912
printf 'read-back-test'
EOF
cat > "$work/bin/sync" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod 755 "$work/bin/"*
sed -e "s|/proc/|$work/proc/|g" -e "s|/sys/|$work/sys/|g" \
    -e "s|/dev/|$work/dev/|g" -e 's/\[ -b /[ -f /g' \
    "$project_dir/br2-external/board/zero2w/overlay/usr/lib/picoos/slots.sh" > "$work/slots.sh"
sed -e "s|/usr/lib/picoos/slots.sh|$work/slots.sh|" \
    -e "s|/proc/|$work/proc/|g" -e "s|/dev/|$work/dev/|g" \
    -e "s|/sys/|$work/sys/|g" \
    "$project_dir/br2-external/board/zero2w/update-guard.sh" > "$work/guard.sh"
printf 'root=/dev/mmcblk0p2 picoos.slot=A\n' > "$work/proc/cmdline"
: > "$work/proc/self/mountinfo"
: > "$work/proc/swaps"
slot() { sh -c '. "$1"; picoos_current_slot' sh "$work/slots.sh"; }
reject() {
    if "$@" > "$work/rejection.log" 2>&1; then
        echo "Expected failure: $*" >&2
        exit 1
    fi
}
[ "$(slot)" = A ]
reject env TEST_ROOT_DEVICE=45827 sh -c '. "$1"; picoos_current_slot' sh "$work/slots.sh"
for args in '' 'picoos.slot=C' 'picoos.slot=A picoos.slot=B'; do
    printf '%s\n' "$args" > "$work/proc/cmdline"
    reject slot
done
printf 'picoos.slot=A\n' > "$work/proc/cmdline"
hash=$(printf 'read-back-test' | sha256sum | cut -d ' ' -f 1)
sh "$work/guard.sh" preinst B "$hash"
reject sh "$work/guard.sh" preinst A "$hash"
reject env TEST_UPGRADE=1 sh "$work/guard.sh" preinst B "$hash"
reject env TEST_ENV_SLOT=B sh "$work/guard.sh" preinst B "$hash"
printf '42 1 179:3 / /mnt rw - ext4 /dev/disk/by-label/system rw\n' > "$work/proc/self/mountinfo"
reject sh "$work/guard.sh" preinst B "$hash"
: > "$work/proc/self/mountinfo"
printf '%s partition 1024 0 -1\n' "$work/dev/mmcblk0p3" > "$work/proc/swaps"
reject sh "$work/guard.sh" preinst B "$hash"
: > "$work/proc/swaps"
sh "$work/guard.sh" postinst B "$hash"
reject sh "$work/guard.sh" postinst B wrong-hash
printf 'picoos.slot=B\n' > "$work/proc/cmdline"
TEST_ROOT_DEVICE=45827 TEST_ENV_SLOT=B sh "$work/guard.sh" preinst A "$hash"
echo "A/B runtime tests passed (root identity, both directions, pending/active/mounted/swap guards, read-back hash)."
