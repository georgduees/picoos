#!/bin/bash
set -euo pipefail
umask 077

[ "$#" -ge 1 ] && [ "$#" -le 2 ] ||
    { echo "Usage: bash $0 NATIVE_UBOOT_SANDBOX [ENV_TEXT_FILE]" >&2; exit 1; }
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
sandbox=$(readlink -e -- "$1")
environment=${2:-"$project_dir/br2-external/board/zero2w/u-boot.env"}
dtb="$(dirname "$sandbox")/arch/sandbox/dts/sandbox.dtb"
grep -Fxq 'CONFIG_HUSH_OLD_PARSER=y' "$(dirname "$sandbox")/.config" ||
    { echo "Sandbox must use the same old Hush parser as rpi_3_32b." >&2; exit 1; }
[ -f "$dtb" ] || { echo "Missing sandbox control DTB: $dtb" >&2; exit 1; }
select_slot=$(sed -n 's/^select_slot=//p' "$environment")
rollback=$(sed -n 's/^rollback=//p' "$environment")
[ -n "$select_slot" ] && [[ "$rollback" == *'; saveenv' ]] ||
    { echo "Missing slot selector or expected rollback format." >&2; exit 1; }
[[ "$select_slot$rollback" != *"'"* ]] ||
    { echo "Unexpected single quote in boot environment script." >&2; exit 1; }
# Preserve rollback logic but never save a sandbox environment onto the host.
rollback="${rollback%; saveenv}; true"
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/test-bootflow.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
export TMPDIR="$work"
check() {
    local slot=$1 stable=$2 recovery=$3 expected=$4 state=$5 commands
    commands="setenv boot_slot '$slot'; setenv stable_slot '$stable'; setenv recovery_status '$recovery'; setenv ustate 0; setenv rollback '$rollback'; setenv select_slot '$select_slot'; if run select_slot; then echo SELECTION_OK; else echo SELECTION_FAILED; fi; echo RESULT_SLOT=\${boot_slot}; echo RESULT_STATE=\${ustate}; true"
    if ! (cd "$work"; "$sandbox" -d "$dtb" -c "$commands") > "$work/raw.log" 2>&1; then
        cat "$work/raw.log" >&2
        return 1
    fi
    tr -d '\r' < "$work/raw.log" |
        sed -E $'s/\033\\[[0-9;]*[A-Za-z]//g' > "$work/result.log"
    if ! grep -Fxq SELECTION_OK "$work/result.log" ||
        ! grep -Fxq "RESULT_SLOT=$expected" "$work/result.log" ||
        ! grep -Fxq "RESULT_STATE=$state" "$work/result.log"; then
        echo "Boot selector failed: slot=$slot stable=$stable recovery=$recovery" >&2
        cat "$work/result.log" >&2
        return 1
    fi
}
check A A '' A 0
check B A '' B 0
check B A in_progress A 3
check B A failed A 3
check invalid B '' B 3
echo "Real U-Boot parser tests passed (valid A/B return success; interrupted, failed and invalid selections roll back)."
