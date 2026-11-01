#!/bin/bash
set -euo pipefail
umask 077

[ "$#" -eq 3 ] || { echo "Usage: bash $0 ROOTFS_EXT4 PRIVATE_KEY NATIVE_SWUPDATE" >&2; exit 1; }
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image=$(readlink -e -- "$1")
key=$(readlink -e -- "$2")
swupdate=$(readlink -e -- "$3")
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/test-swu.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
export TMPDIR="$work"
bash "$project_dir/scripts/make-swu.sh" "$image" 0.1.0-test "$key" "$work/valid.swu"
check() {
    "$swupdate" -c -i "$1" -e "stable,$2" -H "${3:-picoos_zero2w:1.0}" \
        -k "$project_dir/assets/keys/swupdate-dev.pub" > "$work/check.log" 2>&1
}
for slot in A B; do
    check "$work/valid.swu" "$slot" || { cat "$work/check.log" >&2; exit 1; }
done
reject() {
    if check "$@"; then
        echo "Invalid SWU unexpectedly accepted: $*" >&2
        exit 1
    fi
}
reject "$work/valid.swu" A picoos_zero2w:9.9
reject "$work/valid.swu" A unrelated_board:1.0
mkdir "$work/extracted"
(
    cd "$work/extracted"
    cpio --quiet -id < "$work/valid.swu"
    cp sw-description sw-description.original
    sed 's/0.1.0-test/0.1.1-test/' sw-description.original > sw-description
    printf '%s\n' sw-description sw-description.sig update-guard.sh rootfs.ext4.gz |
        cpio --quiet -o -H crc > "$work/bad-signature.swu"
    mv sw-description.original sw-description
    printf '\n# altered guard\n' >> update-guard.sh
    printf '%s\n' sw-description sw-description.sig update-guard.sh rootfs.ext4.gz |
        cpio --quiet -o -H crc > "$work/bad-payload.swu"
)
reject "$work/bad-signature.swu" A
reject "$work/bad-payload.swu" B
echo "Real SWUpdate validation passed (A/B selectors, board/revision, manifest signature and payload tampering)."
