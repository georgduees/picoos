#!/bin/sh
set -eu

board_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
install -d "$TARGET_DIR/boot/overlays" "$TARGET_DIR/etc/swupdate"
install -m 0644 "$BINARIES_DIR/zImage" "$TARGET_DIR/boot/"
install -m 0644 "$BINARIES_DIR/bcm2710-rpi-zero-2-w.dtb" "$TARGET_DIR/boot/"
install -m 0644 "$board_dir/u-boot.env" "$TARGET_DIR/etc/u-boot-initial-env"
install -m 0644 "$BR2_EXTERNAL_PICOOS_PATH/../assets/keys/swupdate-dev.pub" \
    "$TARGET_DIR/etc/swupdate/public-key.pub"
# Only the root-only slot-selecting CLI starts SWUpdate; no network/IPC daemon at boot.
rm -f "$TARGET_DIR/etc/init.d/S80swupdate"
