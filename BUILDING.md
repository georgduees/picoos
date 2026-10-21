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
dispatch. The Ubuntu 24.04 hosted runner uses two parallel jobs to limit memory pressure.
Buildroot downloads and the compiler cache are cached between runs.
A compatible full `output/` is also cached for incremental builds. Its key
includes the runner image version, workspace path, host compiler/libc versions,
project Makefile, scripts and external-tree build inputs. Only the Zero 2 W
rootfs overlay content is excluded from the build-input hash: changing it reruns
rootfs finalization and image generation without rebuilding the kernel.
Overlay paths, types, permissions and symlink destinations remain in the key
so that removals/renames cannot leave stale files in the cached target tree.
Changing the kernel configuration/artwork, toolchain, package definitions or
build hooks deliberately starts a clean build, with compiler/download caches
still available. Arbitrary Buildroot package changes are not assumed safe for
incremental reuse.

Each successful run saves a new output snapshot. These snapshots can be large
and are subject to GitHub cache quotas/eviction; a missing cache falls back to
a clean build. Absolute host paths must match, which is why this cache must
not be copied into the laptop output directory. Existing runs are no longer
cancelled by a newer push; pending runs may still be superseded by GitHub
concurrency handling. Compiler-cache statistics are printed in the job log.
A successful run publishes the files from
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

Kernel modules are XZ-compressed (`.ko.xz`), so target XZ support must be
enabled for kmod, not only for host depmod. The first hardware images lacked
this target support and `modprobe brcmfmac` returned "Function not implemented".
`/etc/modules-load.d/wifi.conf` explicitly loads brcmfmac through S11modules;
the current devtmpfs-only setup does not automatically load device drivers.
WLAN interface creation and firmware loading still need hardware verification
after this correction.

The target includes `wireless-regdb` for the kernel's regulatory database
and `iw` for WLAN diagnostics. Keep `country=DE` in the provisioned supplicant
configuration; the database supplies regulatory rules, not the country selection.
Older hardware images reported a missing `regulatory.db`.

During WLAN bring-up, the hardware log also reported
`brcmf_sdio_checkdied: firmware trap in dongle` and
`Firmware has halted or crashed`, followed by SDIO device reinitialization.
Connectivity was intermittent, including failed pings after earlier successful
ones. The crash trigger is not established; power saving is a hypothesis,
not a confirmed cause.

On an image containing `iw`, compare connectivity with power saving enabled
and disabled, including after an idle period:

```sh
iw dev wlan0 link
iw dev wlan0 get power_save
iw dev wlan0 set power_save off
iw dev wlan0 get power_save
ping -c 20 192.168.0.1
dmesg | tail -n 40
```

Use the actual router address if different. Check command errors and repeat
the same connectivity/idle test before and after the change. Restore the
original setting afterward (`iw dev wlan0 set power_save on` if it was on).
This is a runtime diagnostic change, not a persistent power-saving policy.
Package selection alone does not establish that the firmware crash is fixed.

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

The small per-CPU kernel logos use the bright, static star from the owner's
`bootanim.p8` cart, with its white cross and eight PICO-8 palette colors.
The 5x5 source is `br2-external/board/zero2w/kernel-star.ppm`.
Each source pixel becomes a uniform 16x16 block in the 80x80
`kernel-logo.ppm`; no interpolation or antialiasing is used. This replaces
the favicon-derived image, whose source already contained softened edges.
Regenerate the build asset with ImageMagick:

```sh
magick br2-external/board/zero2w/kernel-star.ppm \
  -filter point -resize 1600% -depth 8 -compress none \
  br2-external/board/zero2w/kernel-logo.ppm
```

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

## Private WLAN provisioning (bring-up)

Run `bash scripts/prepare-wifi.sh` locally to prepare a German (`DE`)
WPA2-Personal configuration for a 2.4 GHz network. The password is read
without echo and passed to `wpa_passphrase` on stdin, not as a process
argument. The plaintext-password comment is removed. The generated
`provisioning/local/wpa_supplicant.conf` has mode 0600 and is Git-ignored.
Its derived PSK is still a network credential and must not be published,
cached by CI, or uploaded as an Actions artifact.

This step only prepares a local file; it does not change the public image,
connect the Pi, or write to an SD card. Install it on the test card only
after the WLAN driver correction has been verified. Pure WPA3/SAE and
enterprise networks are not covered by this provisioning helper.

The target enables `wpa_cli` and its control-interface support, matching the
`ctrl_interface` directive in both generated and example configurations.
Older images without this support must omit that directive for diagnosis.

## Data partition

The project post-image script creates a third, 256 MiB ext4 partition labelled
`picoos-data`, mounted as `/data` from `/dev/mmcblk0p3` before init services.
It seeds `/data/network/wpa_supplicant.conf.example`, `/data/pico8`,
`/data/carts`, and `/data/ssh/base-key.pub`. Private directories are root-owned
with mode 0700. The WLAN example is deliberately inactive; install the real
configuration as `/data/network/wpa_supplicant.conf`, root-owned, mode 0600.
The public SSH key is staged only; account/key activation is still pending.

PICO-8 binaries and private WLAN settings are not included in GitHub artifacts.
They must be copied locally into the data partition after flashing. Automatic
partition/filesystem expansion to the SD card's remaining space is still
pending. Reflashing a complete `sdcard.img` overwrites the data partition as
well: back up provisioned data first. Future A/B updates must preserve it.

### Flash and provision locally

Prepare private credentials once with `bash scripts/prepare-wifi.sh`. Then run:

```sh
sudo bash scripts/flash-and-provision.sh \
  /absolute/path/to/sdcard.img \
  /dev/disk/by-id/YOUR_SD_CARD
```

The helper requires a three-partition image and a whole, unmounted target disk.
It prints device identity and requires the resolved device path as confirmation
before overwriting it. Back up existing data first. It verifies the flashed image,
checks the data partition's ext4 type and `picoos-data` label, then installs:

- The local `pico8/pico-8_0.2.7_raspi.zip` contents in `/data/pico8/`.
- Private WLAN settings in `/data/network/wpa_supplicant.conf` (0600).
- The public base key in `/data/ssh/base-key.pub`.

Copied file contents are compared, writes flushed, and the data partition
unmounted before reporting success. PICO-8 is copied, not executed. This does
not yet verify runtime libraries or activate the `pico` SSH account. The helper
never uploads private files to GitHub and refuses the older two-partition images.

The target hostname is `pico8`. The WLAN interface uses DHCP and sends that
hostname to the DHCP server. Before requesting a lease, ifup starts
wpa_supplicant using `/data/network/wpa_supplicant.conf`; this must reside on
a mounted data partition, be root-owned and have mode 0600. Missing credentials
are reported explicitly and do not start an unconfigured supplicant. The data partition is prepared by the project post-image script; private
credential installation remains a local provisioning step.

Avahi advertises the host addresses and workstation on WLAN using mDNS/DNS-SD,
normally as `pico8.local`, without D-Bus.
Buildroot builds Avahi with `--disable-dbus` when the D-Bus
package is absent; in that build even `enable-dbus=no` is an invalid config
key and must be omitted. D-Bus is not required for address publication or
static DNS-SD services.
No IPv4 link-local fallback is enabled: the IP address
comes from the router's DHCP server. A conflicting hostname can cause Avahi to
choose a suffixed name. Clients must support mDNS and the network must allow
multicast; `.local` does not normally cross routed networks. No SSH service
advertisement is added until the planned non-root SSH provisioning is ready.
