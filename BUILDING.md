# Build instructions

The first target is the Raspberry Pi Zero 2 W with an ARMv6-compatible
32-bit userspace. Buildroot 2026.05.3 is kept in `buildroot/`; generated files
and downloaded package sources are kept outside version control.

Configure and build from this project directory:

```sh
make bootstrap
make configure
make build
```

`make bootstrap` downloads Buildroot 2026.05.3 and verifies its pinned SHA-256
checksum before extraction. The first build downloads the selected external
toolchain and package sources.
The bootable SD-card image is produced at `output/images/sdcard.img`.

The current configuration is the bring-up baseline. It builds the Zero 2 W
kernel and firmware, a framebuffer splash, an HDMI console, and the network
packages needed for the setup access point. The setup portal, data partition,
A/B slots, U-Boot rollback and SWUpdate integration are subsequent
implementation steps; the baseline image is not yet the complete planned
release.
