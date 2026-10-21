# Build instructions

The first target is the Raspberry Pi Zero 2 W with an ARMv6-compatible
32-bit userspace. Buildroot 2026.05.3 is kept in `buildroot/`; generated files
and downloaded package sources are kept outside version control.
The board setup follows Buildroot's `raspberrypizero2w_defconfig` kernel and
firmware choices, while retaining the ARMv6 external toolchain so the same
userspace can later run on a Raspberry Pi Zero W.

Configure and build from this project directory:

```sh
make bootstrap
make configure OUTPUT_DIR=/path/to/ssd/picoos/output DOWNLOAD_DIR=/path/to/ssd/picoos/dl
make build OUTPUT_DIR=/path/to/ssd/picoos/output DOWNLOAD_DIR=/path/to/ssd/picoos/dl -j8
```

`make bootstrap` downloads Buildroot 2026.05.3 and verifies its pinned SHA-256
checksum before extraction. The first build downloads the selected external
toolchain and package sources.

`OUTPUT_DIR` and `DOWNLOAD_DIR` may be placed on a larger mounted drive to
keep generated build products and package downloads off the source workspace.
Compiler cache is enabled and stored under `$(OUTPUT_DIR)/ccache` by default;
set `CCACHE_DIR` to override that location. The cache mainly speeds up later
rebuilds when the compiler and toolchain configuration remain unchanged.
The bootable SD-card image is produced at `output/images/sdcard.img`.

## GitHub Actions

`.github/workflows/build.yml` builds the image on pushes to `main`, `develop`,
and feature branches, on pull requests to `main` or `develop`, and on manual
dispatch. The hosted runner uses two parallel jobs to limit memory pressure.
Buildroot downloads and the compiler cache are cached between runs; generated
host/build output is not reused. A successful run publishes the files from
`output/images/` as the `picoos-zero2w-image` artifact for 14 days.

To run this build in GitHub Actions, push the branch to a GitHub repository
with Actions enabled. The workflow does not flash a storage device.

The current configuration is the bring-up baseline. It builds the Zero 2 W
kernel and firmware, a framebuffer splash, an HDMI console, and the network
packages needed for the setup access point. The setup portal, data partition,
A/B slots, U-Boot rollback and SWUpdate integration are subsequent
implementation steps; the baseline image is not yet the complete planned
release.

The kernel starts from Buildroot's Raspberry Pi board defaults, then applies
`br2-external/board/zero2w/linux.fragment` to remove hardware and filesystem
families not used by this console. The fragment deliberately retains the
Broadcom Wi-Fi/Bluetooth paths, VC4 display, sound, SD-card/ext4, USB host and
mass storage, and generic/common gamepad input support.

## Hardware bring-up

The first GitHub Actions image (run 39629727082) booted on a Zero 2 W
to the HDMI login console with a working USB keyboard when psplash was
disabled. The original splash remained visible after startup. The init
scripts now let psplash manage its own virtual console (without `-n`) so
that quitting restores the text console; this change still needs hardware
verification. Splash control failures are reported rather than ignored.

For diagnostic boots using `init=/bin/sh`, `/proc` must be mounted manually.
Restore the normal kernel command line before testing the normal login
sequence. Keep the splash script executable for normal operation; to disable
it during diagnosis, rename it outside the `S??*` init-script pattern.

## Kernel boot logo

The small per-CPU kernel logos use the PICO-8 Education favicon from
<https://www.pico-8-edu.com/favicon.ico>, used with permission confirmed by the
project owner. The 16x16 icon was scaled to 80x80 with nearest-neighbor
sampling, flattened onto black, and saved as an ASCII PPM in
`br2-external/board/zero2w/kernel-logo.ppm`. The artwork remains third-party
PICO-8 branding; permission does not imply endorsement.

The external tree copies this image over `logo_linux_clut224.ppm` before
kernel configuration. The kernel fragment enables the corresponding logo.
The kernel's per-CPU logo count is unchanged (four on the Zero 2 W); the
psplash image is independent and is not changed. An existing build needs
`linux-reconfigure` followed by the normal image build to replace the compiled
logo. The new logo still needs verification on hardware.

## Console font work in progress

The selected font is PICO-8 ROM Mono from
<https://github.com/juanitogan/p8-programming-fonts>, revision
`b7725f671958237fe5cf5fae8c6017e4a5cb171c`,
`bitmap-fonts/p8-rom-mono.fon` (Git blob
`d48d45ae2b9f05153e91cef47ac9e67a5e53e192`).
It is included as `assets/fonts/p8-rom-mono.fon`. The project owner confirmed
on 2026-10-21 that permission for use and redistribution has been cleared.
This records the owner's confirmation, not an independently verified
upstream license or a change of the font's license.
The font is not yet wired into the console or the image build.
