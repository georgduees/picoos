#!/bin/sh

picoos_current_slot() {
    slot=
    for arg in $(cat /proc/cmdline); do
        case "$arg" in
            picoos.slot=*)
                [ -z "$slot" ] || { echo "Duplicate PicoOS slot argument." >&2; return 1; }
                slot=${arg#picoos.slot=}
                ;;
        esac
    done
    case "$slot" in
        A) part=2 ;;
        B) part=3 ;;
        *) echo "Missing or invalid PicoOS A/B boot identity." >&2; return 1 ;;
    esac
    IFS=: read -r major minor < "/sys/class/block/mmcblk0p$part/dev" || return 1
    # This board uses Linux MMC block minors below 256.
    [ "$(stat -c %d /)" = "$((major * 256 + minor))" ] &&
        [ -b "/dev/mmcblk0p$part" ] ||
        { echo "Boot identity does not match the mounted root device." >&2; return 1; }
    printf '%s\n' "$slot"
}
