#!/bin/sh
set -eu

fail() { echo "SWUpdate slot guard: $*" >&2; exit 1; }
[ "$#" -eq 3 ] || fail "expected phase, target slot and image SHA256."
phase=$1
target=$2
expected=$3
. /usr/lib/picoos/slots.sh
current=$(picoos_current_slot) || fail "cannot identify mounted root."
case "$current:$target" in
    A:B) device=/dev/mmcblk0p3 ;;
    B:A) device=/dev/mmcblk0p2 ;;
    *) fail "refusing to write the active or an unknown slot." ;;
esac
case "$phase" in
    preinst)
        [ "$(fw_printenv -n stable_slot)" = "$current" ] &&
            [ "$(fw_printenv -n boot_slot)" = "$current" ] &&
            [ "$(fw_printenv -n upgrade_available)" = 0 ] ||
            fail "running system is not a confirmed stable slot."
        target_dev=$(cat "/sys/class/block/${device##*/}/dev") ||
            fail "cannot identify target block device."
        if awk -v dev="$target_dev" '$3 == dev { found=1 } END { exit !found }' /proc/self/mountinfo ||
            awk -v dev="$device" '$1 == dev { found=1 } END { exit !found }' /proc/swaps; then
            fail "target slot is mounted or used as swap."
        fi
        ;;
    postinst)
        sync
        actual=$(head -c 536870912 "$device" | sha256sum)
        [ "${actual%% *}" = "$expected" ] || fail "target read-back SHA256 mismatch."
        ;;
    postfailure)
        echo "SWUpdate installation failed; stable slot remains $current." >&2
        ;;
    *) fail "unknown script phase." ;;
esac
