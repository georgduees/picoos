#!/bin/bash
set -euo pipefail
umask 077

fail() { echo "Error: $*" >&2; exit 1; }
[ "$#" -eq 4 ] || fail "usage: bash $0 ROOTFS_EXT4 VERSION PRIVATE_KEY OUTPUT_SWU"
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
image=$(readlink -e -- "$1")
version=$2
key=$(readlink -e -- "$3")
output=$(realpath -m -- "$4")
[[ "$version" =~ ^[0-9A-Za-z][0-9A-Za-z._+-]{0,63}$ ]] || fail "invalid version."
[ "$(stat -c %s "$image")" -eq 536870912 ] || fail "expected a 512 MiB slot image."
[ "$(blkid -p -s TYPE -o value "$image")" = ext4 ] || fail "slot image must be ext4."
[ -f "$key" ] && [ "$(stat -c %a "$key")" = 600 ] || fail "private key must be a mode-0600 regular file."
[ ! -e "$output" ] || fail "output already exists."
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/sign-swu.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
openssl pkey -in "$key" -pubout -out "$work/public-key.pub" 2>/dev/null
cmp "$work/public-key.pub" "$project_dir/assets/keys/swupdate-dev.pub" ||
    fail "private key does not match the image development trust key."
gzip -n -c "$image" > "$work/rootfs.ext4.gz"
cp "$project_dir/br2-external/board/zero2w/update-guard.sh" "$work/update-guard.sh"
raw_hash=$(sha256sum "$image" | cut -d ' ' -f 1)
image_hash=$(sha256sum "$work/rootfs.ext4.gz" | cut -d ' ' -f 1)
guard_hash=$(sha256sum "$work/update-guard.sh" | cut -d ' ' -f 1)
{
    printf 'software = {\n version = "%s";\n hardware-compatibility = [ "1.0" ];\n picoos_zero2w = { stable = {\n' "$version"
    for slot in A B; do
        case "$slot" in A) part=2 ;; B) part=3 ;; esac
        cat <<EOF
  $slot = {
   images = ({ filename = "rootfs.ext4.gz"; type = "raw";
    device = "/dev/mmcblk0p$part"; compressed = "zlib";
    sha256 = "$image_hash"; });
   scripts = ({ filename = "update-guard.sh"; type = "shellscript";
    data = "$slot $raw_hash"; sha256 = "$guard_hash"; });
   bootenv = (
    { name = "boot_slot"; value = "$slot"; },
    { name = "upgrade_available"; value = "1"; },
    { name = "bootcount"; value = "0"; }
   );
  };
EOF
    done
    printf ' }; };\n};\n'
} > "$work/sw-description"
openssl dgst -sha256 -sign "$key" -out "$work/sw-description.sig" "$work/sw-description"
openssl dgst -sha256 -verify "$work/public-key.pub" -signature "$work/sw-description.sig" "$work/sw-description"
(
    cd "$work"
    printf '%s\n' sw-description sw-description.sig update-guard.sh rootfs.ext4.gz |
        cpio --quiet -o -H crc > "$work/update.swu"
)
# Publish only a completely generated archive.
cp --no-clobber "$work/update.swu" "$output"
echo "Signed development update created: $output"
