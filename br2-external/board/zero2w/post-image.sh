#!/bin/sh
set -eu

board_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(mktemp -d "$BUILD_DIR/picoos-image.XXXXXX")
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/empty" "$root/data/network" "$root/data/pico8" "$root/data/carts" "$root/data/ssh"
cp "$board_dir/data/wpa_supplicant.conf.example" "$root/data/network/"
cp "$BR2_EXTERNAL_PICOOS_PATH/../provisioning/data/ssh/base-key.pub" "$root/data/ssh/"
rm -f "$BINARIES_DIR/data.vfat"
"$HOST_DIR/sbin/mkfs.fat" -F 32 -n PICOOS-DATA -C "$BINARIES_DIR/data.vfat" 262144
"$HOST_DIR/bin/mcopy" -s -i "$BINARIES_DIR/data.vfat" "$root/data/"* ::
rm -f "$BINARIES_DIR/data.ext4"

genimage --rootpath "$root/empty" --tmppath "$root/genimage" \
	--inputpath "$BINARIES_DIR" --outputpath "$BINARIES_DIR" \
	--config "$board_dir/genimage.cfg"
