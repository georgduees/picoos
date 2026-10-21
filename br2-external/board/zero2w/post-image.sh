#!/bin/sh
set -eu

board_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
root=$(mktemp -d "$BUILD_DIR/picoos-image.XXXXXX")
trap 'rm -rf "$root"' EXIT

mkdir -p "$root/empty" "$root/data/network" "$root/data/pico8" "$root/data/carts" "$root/data/ssh"
cp "$board_dir/data/wpa_supplicant.conf.example" "$root/data/network/"
cp "$BR2_EXTERNAL_PICOOS_PATH/../provisioning/data/ssh/base-key.pub" "$root/data/ssh/"
chmod 700 "$root/data/network" "$root/data/ssh"

"$HOST_DIR/sbin/mke2fs" -t ext4 -L picoos-data -m 0 -F \
	-O ^orphan_file -E root_owner=0:0,lazy_itable_init=0,lazy_journal_init=0 \
	-d "$root/data" "$BINARIES_DIR/data.ext4" 256M
for path in /network /network/wpa_supplicant.conf.example /ssh /ssh/base-key.pub /pico8 /carts; do
	for field in uid gid; do
		"$HOST_DIR/sbin/debugfs" -w -R "set_inode_field $path $field 0" "$BINARIES_DIR/data.ext4"
	done
done

genimage --rootpath "$root/empty" --tmppath "$root/genimage" \
	--inputpath "$BINARIES_DIR" --outputpath "$BINARIES_DIR" \
	--config "$board_dir/genimage.cfg"
