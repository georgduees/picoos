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
ones. The historical crash trigger is not established.

Direct Ethernet-assisted testing on 2026-10-22 reproduced repeated WPA
authentication timeouts with power saving disabled. With a fresh driver load,
disabling firmware WPA handshake offload completed the WPA2-PSK handshake;
a fresh load with the default feature mask reproduced the timeouts, and
disabling offload again restored the connection. With the workaround and
power saving enabled, WLAN obtained a DHCP lease and answered all 20
router pings explicitly bound to `wlan0`.

`overlay/etc/modprobe.d/brcmfmac.conf` therefore sets
`options brcmfmac feature_disable=8192` for this board profile. This disables
only FWSUP (bit 13 in the pinned kernel's `brcmfmac/feature.h`), leaving
the WPA handshake to wpa_supplicant; it does not disable WPA encryption or
power saving. Revalidate this workaround when changing kernel/firmware.
This isolates the observed authentication failure to the firmware-offload
path in the tested combination, not necessarily to a particular component's
implementation. It does not establish the cause of the earlier firmware crash.

Boot testing also exposed an interface-readiness ordering issue: BusyBox ifup
runs the inline `pre-up` supplicant command before the standard `wait_iface`
hook. The WLAN helper now calls that existing bounded wait explicitly before
starting the supplicant, so asynchronous SDIO probe/firmware loading can finish.
The configured `wait-delay` is respected (10 seconds by default), with an
explicit error if `wlan0` does not appear.

After both changes were deployed to the test card, reboot verification
confirmed automatic WPA completion and DHCP (`192.168.0.98`), with power saving
still enabled. Router pings bound to WLAN passed after boot (20/20) and after
an idle period (30/30), without a firmware-crash message in that boot's log.
A final test temporarily brought `eth0` down: laptop-to-Pi ping and public-key
SSH to the WLAN address worked, and another 5/5 WLAN router pings succeeded.
Ethernet was then restored. A separate Pi-to-laptop ping did not receive
replies; the laptop has UFW active, which was not changed or investigated.
These are bounded bring-up tests, not a long-duration stability certification.

For additional diagnosis on an image containing `iw`, compare connectivity with power saving enabled
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

### Temporary USB-Ethernet diagnosis

For an existing card, `scripts/prepare-ethernet-diagnostics.sh` accepts the
unmounted ext4 `rootfs` partition and a local SSH public key:

```sh
sudo bash scripts/prepare-ethernet-diagnostics.sh \
  /dev/disk/by-id/YOUR_SD_CARD-part2 ~/.ssh/id_ed25519.pub
```

This does not flash the card or change `/data`. It archives the original
network/Avahi/Dropbear configuration under `/root`, loads the ASIX USB-Ethernet
modules at boot, enables DHCP on `eth0`, and allows Avahi on Ethernet as well
as WLAN. It installs the supplied public key for a temporary diagnostic
`root` SSH login and disables all SSH password authentication (`dropbear -s`).
This is not the planned non-root `pico` account setup. Only use it on a trusted
LAN; remove the temporary root authorized key after diagnosis and restore the
desired SSH policy. The helper refuses to replace existing authorized keys
or an existing `eth0` interface configuration.

The shipped image contains `asix` and `ax88179_178a` modules. A Chromecast Ultra
Ethernet power adapter still needs a working USB host connection on the Pi's
USB data port; the presence of drivers alone does not prove cable/OTG
compatibility. Check the router's DHCP lease list for the Ethernet address if
`pico8.local` is unavailable.

On 2026-10-22, the owner's Chromecast Ultra Ethernet power adapter was verified
on the Zero 2 W: the kernel identified an AX88772C PHY using `asix`, Ethernet
negotiated 100 Mbps/full duplex, and DHCP, mDNS and root public-key SSH worked.
Five router pings through `eth0` completed without loss; Dropbear ran with
password authentication disabled (`-s`). WLAN was down during this check;
the intermittent WLAN fault is not resolved by this Ethernet result.

The A/B post-image script creates a fourth, 1 GiB **FAT32** partition labelled
`PICOOS-DATA`, mounted as `/data` from `/dev/mmcblk0p4` before init services.
It explicitly uses `mkfs.fat -F 32`, produces `data.vfat`, and marks the MBR
partition as FAT32 LBA (0x0C); both 512 MiB system slots use ext4.
It seeds `/data/network/wpa_supplicant.conf.example`, `/data/pico8`,
`/data/carts`, and `/data/ssh/base-key.pub`. The WLAN example is deliberately
inactive; install the real configuration as `/data/network/wpa_supplicant.conf`.
The public SSH key is staged only; account/key activation is still pending.

FAT32 supports access from Windows, macOS and Linux, but does not store Unix
owners, permissions or symbolic links, and has a maximum file size of
4 GiB minus one byte. Target mount options set `uid=0,gid=0,fmask=0077,dmask=0077`:
all data files/directories appear root-owned and mode 0700. This keeps network
credentials inaccessible to other Linux users while allowing root to execute
PICO-8 binaries from `/data`. These permissions are synthetic, not per-file
metadata; `chmod`/`chown` cannot be used to configure FAT permissions.
The future non-root `pico` runtime needs a separate access policy.
Physical access to the card bypasses these Linux mount restrictions, so treat
the WLAN configuration as a secret on every desktop OS.

Before starting wpa_supplicant, the WLAN helper copies the persistent file to
`/run/picoos-wifi/wpa_supplicant.conf` with mode 0600 in a mode-0700 directory.
The supplicant reads this RAM copy, removed on service stop or startup failure.
To change credentials, edit the persistent file and restart WLAN; editing the
RAM copy is not persistent. Old ext4 cards with root-owned mode-0600 credentials
remain supported by the helper.

PICO-8 binaries and private WLAN settings are not included in GitHub artifacts.
They must be copied locally into the data partition after flashing. Automatic
partition/filesystem expansion to the SD card's remaining space is still
pending. Reflashing a complete `sdcard.img` overwrites the data partition as
well: back up provisioned data first. Future A/B updates must preserve it.
There is no in-place ext4-to-FAT32 migration. Updating the source does not
convert an existing card; moving it to FAT32 requires an explicit backup,
reflash and restore/provisioning step.

### FAT32 validation

Run `bash scripts/test-wifi-runtime.sh` for the private RAM-copy lifecycle,
permission checks and error handling. After building, run:

```sh
PATH="$PWD/output/host/bin:$PWD/output/host/sbin:$PATH" \
  bash scripts/test-fat32-image.sh output/images
```

The image test regenerates an SD image in a temporary directory using existing
kernel/rootfs/boot files. It checks FAT32 size/version/label, partition metadata,
filesystem consistency, seeded files and absence of active WLAN credentials.
It also checks that the provisioning validator rejects ext4 and FAT16 data
filesystems even with a FAT32 MBR type. Both tests run in GitHub Actions before
image upload.

On 2026-10-22, an isolated FAT32 loop image was also tested on the Zero 2 W,
without formatting or replacing the real `/data` partition. Root-only 0700
mount permissions, execution of a test script from FAT32, a mode-0600 WLAN
RAM copy and successful WPA authentication were verified. Normal WLAN was
restored afterward; at that point the live data partition still used ext4.

The complete FAT32 image from Actions run 39758758648 (commit `de51917`) was
then flashed and booted on the Zero 2 W on 2026-10-22. `/dev/mmcblk0p3` mounted
as writable vfat with root-only masks. Automatic WLAN authentication and DHCP
worked (`192.168.0.98`) with power saving enabled; Ethernet and key-only
diagnostic SSH also worked (`192.168.0.246`). The active supplicant used
`/run/picoos-wifi/wpa_supplicant.conf` (root:0600), byte-identical to the FAT32
source (synthetic root:0700). All 11 provisioned user files matched the verified
pre-migration backup by SHA-256; only the intentionally updated inactive WLAN
example was excluded from that comparison. Twenty router pings bound to WLAN
completed without loss, with no FAT corruption or firmware-crash message in
the checked boot log. PICO-8 runtime execution and full-card expansion remain
separate, unverified work.

### Flash and provision locally

Prepare private credentials once with `bash scripts/prepare-wifi.sh`. Then run:

```sh
sudo bash scripts/flash-and-provision.sh \
  /absolute/path/to/sdcard.img \
  /dev/disk/by-id/YOUR_SD_CARD
```

The helper requires the exact four-partition A/B layout and a whole, unmounted target disk.
It prints device identity and requires the resolved device path as confirmation
before overwriting it. Back up existing data first. Before writing, it validates
the image's slot boundaries, ext4 slot filesystems, and fourth partition's
actual FAT32 filesystem/version and label.
After read-back verification it checks the card's FAT32 filesystem and
`PICOOS-DATA` label, then installs:

- The local `pico8/pico-8_0.2.7_raspi.zip` contents in `/data/pico8/`.
- Private WLAN settings in `/data/network/wpa_supplicant.conf`.
- The public base key in `/data/ssh/base-key.pub`.

The host mounts FAT32 with root-only masks and `noexec`, copies files without
attempting Unix ownership/mode changes, and compares their contents.
Writes are flushed, and the data partition
unmounted before reporting success. PICO-8 is copied, not executed. This does
not yet verify runtime libraries or activate the `pico` SSH account. The helper
never uploads private files to GitHub and refuses older two-/three-partition
images as well as ext4/FAT12/FAT16 data filesystems in the data partition.

### A/B development implementation

This is a new, **hardware-unverified** layout, not an in-place upgrade of the
currently tested three-partition card. Back up `/data` before an explicitly
approved reflash. Do not use it as a proven recovery system until the hardware
test matrix below passes.

| Region | Offset | Size |
| --- | --- | --- |
| Primary / redundant U-Boot environment | 0x40000 / 0x60000 | 64 KiB each |
| p1 shared FAT32 boot | 1 MiB | 64 MiB |
| p2 system A / p3 system B | 65 / 577 MiB | 512 MiB each |
| p4 FAT32 data | 1089 MiB | 1024 MiB |

U-Boot 2026.04 uses `rpi_3_32b` with a custom redundant MMC environment and
boots `/boot/zImage`, DTB and `miniuart-bt.dtbo` from the selected ext4 slot.
The firmware's shared DTB/overlay copies are needed to bring up U-Boot; the
Linux slot's DTB receives the slot overlay and U-Boot's Raspberry Pi firmware
fixups. This path, including framebuffer, UART, WLAN and Ethernet, still needs
testing on the Zero 2 W. Root filesystems remain **read/write** for this bring-up;
read-only roots and persistent SSH host keys/account configuration are not yet
implemented. Manual changes confined to the old root do not follow a slot update.
The shared Pi firmware and U-Boot are not A/B-protected or replaced by SWUpdate.

Only a root CLI starts SWUpdate; there is no auto-started web upload or IPC
daemon. The development signing key is kept under ignored
`provisioning/local/update-signing/dev.key` (0600). Only
`assets/keys/swupdate-dev.pub` is committed and installed in the image.
GitHub builds unsigned images and never receives the private key.
Keep a separate secure backup of that key. It is a development trust root,
not secure boot or a finalized production signing/rotation policy.

Create a signed update locally from the new build's exact 512 MiB root image:

```sh
bash scripts/make-swu.sh output/images/rootfs.ext4 0.1.0-dev \
  provisioning/local/update-signing/dev.key /absolute/path/picoos-0.1.0-dev.swu
```

Copy the package to `/data` on an A/B-booted device, then run as root:

```sh
picoos-update /data/picoos-0.1.0-dev.swu
reboot
```

The CLI derives the running slot from the kernel boot identity **and mounted
root device**, refuses pending trial boots and serializes installs. SWUpdate
verifies the RSA/SHA-256 manifest signature, board/revision and payload hashes.
A signed preinstall guard independently refuses active or mounted target slots.
The non-streaming raw handler writes only the inactive root, then a postinstall
guard flushes and reads back all 512 MiB for comparison with the signed hash.
Only afterward does SWUpdate commit slot selection via libubootenv. Temporary
extraction uses a private directory on `/data` rather than RAM; leave room for
the package and extracted compressed payload. Updates never format `/data`.

U-Boot uses SWUpdate's `recovery_status` to fall back after interrupted/failed
transactions. `upgrade_available=1` enables its persistent boot counter:
three unconfirmed boots are allowed, then the stable slot is restored.
The late local health service checks root identity, writable FAT32 data,
boot assets, verification key and a running watchdog process before atomically
confirming the slot with `fw_setenv -s`. It deliberately does not require
Internet, router access or WLAN credentials. This is a **bring-up health check**,
not yet a PICO-8/application readiness check.

The BCM2835 watchdog is configured for a 15-second timeout and a 60-second
kernel open grace period, then fed by BusyBox every five seconds. Its actual
handoff across U-Boot, kernel and userspace must be measured on hardware.
Required tests before relying on recovery: first boot, A-to-B and B-to-A update,
tampered/wrong-board package rejection, deliberate failed health check, kernel
hang/watchdog reset, three-attempt rollback, and power cuts during image writes
and environment saves. Confirm `/data` hashes and network access after each.
Redundant environments alone do not prove SD-controller power-loss safety.

Additional host tests:

- `bash scripts/test-ab-runtime.sh`: root/slot identity, inactive-slot guards and
  read-back failure paths.
- `bash scripts/test-uboot-env.sh /path/to/mkenvimage /path/to/fw_printenv /path/to/fw_setenv`:
  real libubootenv reads/writes on a disposable file, confirmation syntax and
  one corrupt redundant copy.
- `bash scripts/test-swu.sh /path/to/rootfs.ext4 provisioning/local/update-signing/dev.key /path/to/native/swupdate`:
  genuine SWUpdate check-only verification of both slot manifests and negative
  signature/payload/board tests. Use a native SWUpdate build with socket paths
  in a private home-directory workspace (Unix socket paths must be below
  108 bytes), not target `/run` paths.

Host image/signing/provisioning tests keep scratch files under ignored
`provisioning/local/tmp`, not `/tmp`. Configure compiler/build `TMPDIR` to a
home-directory workspace as well.

The target hostname is `pico8`. The WLAN interface uses DHCP and sends that
hostname to the DHCP server. Before requesting a lease, ifup starts
the WLAN helper using `/data/network/wpa_supplicant.conf`; this must reside on
a mounted data partition, be root-owned and have mode 0600 or 0700. The helper
starts wpa_supplicant with the private mode-0600 RAM copy. Missing credentials
are reported explicitly and do not start an unconfigured supplicant.
The data partition is prepared by the project post-image script; private
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
