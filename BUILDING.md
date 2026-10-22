# Build instructions

The first target is the Raspberry Pi Zero 2 W with an ARMv6-compatible
32-bit userspace. Buildroot 2026.05.3 is kept in `buildroot/`; generated files
and downloaded package sources are kept outside version control.
The board setup follows Buildroot's `raspberrypizero2w_defconfig` kernel and
firmware choices, while retaining the ARMv6 external toolchain so the same
userspace can later run on a Raspberry Pi Zero W.

The PICO-8 `0.2.7` Raspberry Pi archive has separate runtime variants.
The `pico8` ARMv6 binary expects legacy `libbcm_host.so`, which is not present
in this image. `pico8_gpio` additionally requires `libwiringPi.so`.
The 64-bit `pico8_64` is not appropriate for this 32-bit userspace.
`pico8_dyn` is the matching ARM hard-float variant but needs `libSDL2-2.0.so.0`.
Buildroot now includes SDL2 for that runtime. The live framebuffer is
`/dev/fb0`. BlueZ, its `bluetoothctl` client, Bluetooth HID/HOG profiles, and
the Linux joystick test utilities are included for Bluetooth keyboards, mice,
and controllers. The kernel loads its Bluetooth UART and HID/input modules at
boot. The internal Bluetooth controller (BCM43436, firmware
`brcm/BCM43430A1.raspberrypi,model-zero-2-w.hcd`) stays on the PL011 UART with
the in-kernel serdev driver, as on Raspberry Pi OS; the Linux console is
therefore only on `tty1`, not on `ttyAMA0`. Attaching it through the mini-UART
(`miniuart-bt`, `btattach`, `core_freq`) never got a response from the chip on
this hardware and is not used. Persistent runtime state (currently BlueZ pairings, `/var/lib/bluetooth`) lives
in a 16 MiB ext4 image, `/data/picoos-state.img`, which `/etc/init.d/S35picoos-state`
(`picoos-state prepare`) creates on first boot and loop-mounts at `/persist`. FAT32
itself cannot store Unix modes or names like `B8:27:EB:58:92:2E`. New persistent
settings only need an entry in `LINKS` in `picoos-state`. Paired devices survive A/B slot updates. A Stadia
controller (Bluetooth firmware mode) has been paired and read via
`/dev/input/js0` on hardware; no ALSA audio device has been verified.
The local PICO-8 binary remains user-supplied data and is never copied into
public images. Launching the emulator, validating rendered HDMI output/audio,
checking SDL2 gamepad input and Bluetooth pairing/audio, and checking
performance remain separate hardware tasks.

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

An optional third argument accepts a backed-up mode-0600 Dropbear Ed25519 host
key. It replaces only the fresh image's standard `/etc/dropbear` symlink, never
an existing host-key directory. This keeps the known SSH identity during a
locally provisioned test reflash; the private key must never enter Git/CI.

For an explicitly approved A/B hardware-test reflash,
`scripts/prepare-ab-test-card.sh IMAGE WHOLE_SD_DEVICE VERIFIED_BACKUP_DIR`
combines the normal confirmed flash with diagnostic setup on **both** slots.
The backup directory must contain `data.tar`, `diagnostics-private.tar`,
`archives.sha256`, matching `before.sha256` / `after.sha256`, and the verified
`verify-data` tree. It checks archives and files before flashing, preserves the
backed-up Ed25519 host key in both roots, then copies the full data tree to p4
and verifies every saved file hash. All host scratch storage is under ignored
`provisioning/local/tmp`. This is temporary test provisioning, not persistent
SSH account/host-key handling for future SWUpdate root replacements.

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

### Opt-in persistent bring-up diagnostics

The regular non-root `pico` account remains separate work. For bring-up only,
`picoos-diagnostics` provides explicitly enabled **key-only root SSH** and
Ethernet DHCP across root-slot replacements. It does not import arbitrary
`/etc` files or execute configuration from the data partition.
Public images contain neither diagnostic keys nor an activation marker;
the base public key is **not automatically granted root access**.
Without an opt-in, the diagnostic Dropbear listener stays off.

From a local root console, explicitly grant access to the chosen plain
Ed25519 public key:

```sh
picoos-diagnostics enable /data/ssh/base-key.pub
reboot
```

The first command generates a persistent Ed25519 host key. To preserve the
identity of an already provisioned diagnostic system, supply its existing key:

```sh
picoos-diagnostics enable /root/.ssh/authorized_keys \
  /etc/dropbear/dropbear_ed25519_host_key
```

Only `authorized_keys`, `dropbear_ed25519_host_key` and the versioned `enabled`
marker are stored in `/data/diagnostics`. This directory is root-only on Linux,
but FAT32 is **not encrypted**: physical card access exposes the private host
key, just as it exposes WLAN credentials. Keep all data backups private.
The marker is published only after the keys have been validated and flushed.
An existing store is not overwritten by another key-provisioning command.

Before networking, `S30picoos-diagnostics` validates the mounted FAT32 p4,
ownership, synthetic/private modes, file types, format and Ed25519 keys.
It copies keys into a mode-0700 RAM directory with mode-0600 key files, points
root's `authorized_keys` there and prepares an ifup source for Ethernet DHCP.
The ASIX drivers load only when diagnostics are enabled; Avahi permits WLAN
and Ethernet. `S50dropbear` uses fixed key-only arguments and the explicit RAM
host key, never automatic fallback host-key generation or shell-sourced
persistent options. The local boot health check requires the opted-in
listener to be prepared and running before confirming a trial slot.

`picoos-diagnostics disable` removes the activation marker and stops the
listener, retaining the stored keys. Existing SSH sessions and Ethernet
configuration may remain until reboot. Re-enable a retained store with
`picoos-diagnostics enable` without arguments. Key-file edits require
preparation again (normally a reboot); malformed enabled configuration fails
closed and prevents trial confirmation.

The offline Ethernet helper requests a one-time import only when the new
helper is installed in the root image. On first boot the explicit local
diagnostic keys are imported if no store exists; an existing persistent store
remains authoritative. Older images retain the legacy root-local setup.
Run `bash scripts/test-diagnostics-runtime.sh` for lifecycle and failure tests;
the image tests verify installed scripts/modes and absence of private
diagnostic material or activation in public artifacts.

#### Persistence hardware verification (2026-10-22)

On confirmed A, the helper was explicitly enabled with the existing working
authorization and Ed25519 host key. The original 12 data files were unchanged;
only the three documented persistence files were added. A private backup of
all 15 files was extracted and verified against before/after SHA-256 manifests
on the host before the slot update.

For hardware coverage, a **locally assembled public root image**, not a CI
artifact, was derived from the untouched `0afcfac` CI root by installing the
changed overlay files with `debugfs`. Ownership/modes, filesystem checks,
exact installed-file comparisons, image/layout tests and native SWUpdate
checks passed. The local test packages contain no private configuration or
root activation. The full Buildroot CI run remains separate.

The first package (`9ac6e25`) was installed to B. Check-only inspection and a
full signed 512 MiB readback succeeded; then B autonomously loaded the
persistent keys and confirmed itself, without root-slot provisioning. This
first-boot check caught that Dropbear 2026.93 also leaves a generated `.pub`
sidecar. The helper was corrected and verified with actual FAT32 host-key
generation to leave exactly the intended three persistent files.

The corrected final package (`9347660`) was then installed to A through the
real CLI. An independent 512 MiB readback matched its signed root hash.
A subsequent **read-only, no-journal-replay** inspection verified the exact
new scripts, root ownership/modes, absent root `authorized_keys` and offline
import marker, and the fresh Dropbear symlink. No private diagnostics were
written into A after installation. After reboot, the prior host-key SSH
identity worked; A confirmed itself and remained in the same boot beyond
90 seconds with the watchdog active. The persistent and RAM directories were
root:0700, RAM keys root:0600, and root authorization linked into RAM. Dropbear
used `-s` and the explicit RAM host key without `-R`. A no-key login was
rejected and the server advertised only `publickey`, not
password/keyboard-interactive. WLAN authenticated, ten WLAN-bound router pings
had no loss, all 15 stored data-file hashes matched the private pre-update
backup, and shared p1 was unchanged. **Current test-card state is confirmed A**
using persistent diagnostics; B is the preceding persistent-configuration
root fallback.

#### Text-only U-Boot hardware installation (2026-10-22)

Actions run `39805575018` completed successfully: full Buildroot build,
diagnostic/WLAN/A/B tests, FAT32/layout tests and artifact upload. Its
`u-boot.bin` SHA-256 is
`66d8908050385f9f0d8c9d49c9825bc16b3c71eac944a193c4683488d408e5cd`.
The resolved U-Boot configuration has `CONFIG_VIDEO_LOGO` and
`CONFIG_SPLASH_SCREEN` disabled, while `CONFIG_VIDEO`,
`CONFIG_VIDEO_BCM2835`, and the serial console remain enabled. Thus the U-Boot
logo/splash are removed without disabling the text console. The Linux/PicoOS
splash remains enabled and unchanged.

Before changing the shared firmware partition, the live 64 MiB p1 was saved
as a raw image on `/data` at
`/data/bootloader-maintenance-20261022/p1-before.img`, SHA-256 verified and
byte-compared against the unmounted p1. A second copy and its checksum manifest
are stored privately under ignored
`provisioning/local/backups/bootloader-20261022.*` on the workstation. This
backup is independent of both A/B roots and remains available even if U-Boot
cannot start. The helper
`scripts/restore-picoos-boot-partition.sh IMAGE MANIFEST WHOLE_SD_DEVICE`
restores only the exact 64 MiB p1 after validating the four-partition layout,
manifest, filesystem and unmounted target; it demands typing the exact disk
path and read-back-verifies the restored partition. Copy the backup image and
manifest off the SD card before using the helper, so restoration does not read
its source from the disk being written.

Only `u-boot.bin` was atomically replaced on p1; the existing firmware,
`config.txt`, stored U-Boot environment, both roots and `/data` were not
written. The config hash stayed
`38b5e3d4d5aa4087efd1e26f7572ba36c98a8c83a86d857ca38ae75812d5d2e6`, and
the known firmware UART setting remained unchanged. After reboot, the new
U-Boot successfully started confirmed A with the original persisted
key-only SSH identity. A remained confirmed with watchdog active at 15 seconds
and nowayout enabled; persistent diagnostics, WLAN and the original 15
`/data` files worked, all ten WLAN-bound router pings succeeded, and p1 passed
`fsck.vfat`. The binary hash was verified from p1 after boot. This proves the
new bootloader boots; no HDMI capture was available to independently inspect
the physical display. **Current test-card state is confirmed A.**

### A/B development implementation

This is a new layout with **A/B boots, three-attempt watchdog rollback and
signed SWUpdate installations in both directions verified**.
Arbitrary kernel-hang and power-loss tests remain pending.
It is not an in-place upgrade of a three-partition card. Back up `/data`
before an explicitly approved reflash. Do not treat this as fully qualified
update recovery until the hardware test matrix below passes.

| Region | Offset | Size |
| --- | --- | --- |
| Primary / redundant U-Boot environment | 0x40000 / 0x60000 | 64 KiB each |
| p1 shared FAT32 boot | 1 MiB | 64 MiB |
| p2 system A / p3 system B | 65 / 577 MiB | 512 MiB each |
| p4 FAT32 data | 1089 MiB | 1024 MiB |

U-Boot 2026.04 uses `rpi_3_32b` with a custom redundant MMC environment and
boots `/boot/zImage` and the DTB from the selected ext4 slot.
U-Boot keeps its HDMI/serial text console but disables its own video logo
and splash screen. This does not disable the Linux/PicoOS splash.
The firmware's shared DTB is needed to bring up U-Boot. Keep the firmware UART
in its default mini-UART configuration with `enable_uart=1`: do **not** apply
`miniuart-bt` in the shared `config.txt` for this `rpi_3_32b` build; the slot
DTB is used unmodified so Bluetooth stays on the PL011. Root filesystems remain **read/write** for this bring-up.
The explicit diagnostic opt-in above persists its keys and Ethernet policy;
read-only roots, the regular `pico` account and general system-configuration
persistence are not implemented. Other changes confined to the old root do
not follow a slot update.
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
kernel open grace period, then fed by BusyBox every five seconds. Automatic
resets without a userspace feeder were observed in the controlled test below;
this does not establish behavior under arbitrary kernel hangs.
Required tests before relying on recovery: first boot, A-to-B and B-to-A update,
tampered/wrong-board package rejection, deliberate failed health check, kernel
hang/watchdog reset, three-attempt rollback, and power cuts during image writes
and environment saves. Confirm `/data` hashes and network access after each.
Redundant environments alone do not prove SD-controller power-loss safety.

#### First A/B hardware boot (2026-10-22)

The original image from Actions run 39772416660 (`c5887b6`) remained at the
firmware rainbow screen with no Ethernet SSH. A controlled test removed only
`dtoverlay=miniuart-bt` from p1 `config.txt`, retaining the original file as
`config-before-uart-test.txt`. U-Boot/Linux output and Ethernet SSH then worked.
The fix is now part of the board configuration; the downloaded original image
is still the pre-fix artifact and must not be represented as a corrected image.
The reversible `scripts/prepare-uboot-uart-test.sh BOOT_PARTITION test|restore`
helper changes only this p1 setting, not root slots, data or boot environment.

The running Zero 2 W booted kernel `6.12.61-v7` from p2 with `picoos.slot=A`,
mounted FAT32 `/data` from p4, and confirmed `boot_slot=stable_slot=A`,
`upgrade_available=0`, `bootcount=0`, `ustate=0`. BusyBox watchdog was running;
sysfs reported the BCM2835 watchdog active, timeout 15 seconds and nowayout 1.
WLAN authenticated automatically and Ethernet key-only SSH retained the
backed-up host identity. All 12 data files matched the pre-A/B SHA-256 manifest.
This verifies the normal first boot, **not** a forced watchdog reset, Slot B,
SWUpdate switching, three-attempt rollback or power-loss behavior.

#### Slot-selection interpreter regression

The first B trial returned to A although both slots' kernel, DTB, overlay,
health service and diagnostic SSH files matched. The `rpi_3_32b` build uses
U-Boot's **old Hush parser**, not the laptop's Bash or Linux BusyBox shell.
In that parser, `if false; then ...; fi` returns 1. The original `select_slot`
ended with such a false condition for every valid slot, so
`run select_slot && run load_slot` skipped the primary boot and entered the
stable-slot fallback. Initial successful A boots therefore did not prove
that selection worked.

The selector now has an explicit successful branch for valid A/B identities,
while invalid identities still return the rollback result. A native U-Boot
2026.04 sandbox with the same old Hush parser reproduces the old failure and
passes the corrected A/B, interrupted/failed transaction and invalid-slot
cases. The fix was installed on the test device as one read-back-verified
`select_slot` change through libubootenv before re-arming B; no root image or
data was rewritten. B then booted p3, automatically confirmed
`boot_slot=stable_slot=B`, cleared `upgrade_available` / `bootcount`, and had
active watchdog, authenticated WLAN and the original SSH host identity.
Fresh images include the corrected default environment. Existing development
cards require this explicit environment maintenance; a root-only SWUpdate
package does not automatically replace arbitrary shared bootloader scripts.

#### Three-attempt watchdog rollback (2026-10-22)

With explicit permission for fault injection, confirmed B remained the stable
slot while only the inactive A health script's executable mode was changed
from 0755 to 0644. Kernel, boot assets and data were not modified. A was armed
with `upgrade_available=1` and `bootcount=0` using `fw_setenv -s`.

SSH observations captured A booting with persistent counters **1, 2 and 3**,
each time retaining `stable_slot=B` and no userspace watchdog feeder or slot
confirmation. Automatic resets occurred without further reboot commands;
U-Boot then returned to B, which confirmed itself with
`upgrade_available=0`, `bootcount=0` and an active 15-second watchdog.
The driver reported `bootstatus=0` throughout, so this is an observed
watchdog/fallback test, not a claim that the reset-cause register was decoded.

The inactive A health script was compared with its original and restored to
0755. A subsequent normal B-to-A trial boot confirmed A successfully with
working WLAN/SSH and active watchdog. All 12 `/data` file hashes after the
rollback matched the verified pre-A/B backup. This verifies the configured
attempt limit, automatic fallback and repaired slot; it does **not** test
power loss or an actual SWUpdate raw-image installation.

#### Signed SWUpdate hardware installation (2026-10-22)

The existing development package `picoos-0.1.0-c5887b6.swu` was used to test
the actual update engine independently of the newer shared U-Boot binary.
Its SHA-256 is
`f7ea50db29da60d4f2d6fe3c0941dd399c949ba062a4680237b7f2ce7c541f64`.
This is the root version already used for bring-up; its original shared
firmware/U-Boot files were **not** installed. The live shared environment
retained the separately corrected `select_slot`.

On the Zero 2 W, SWUpdate check-only accepted both signed slot selections and
rejected a wrong board, wrong hardware revision, modified signed manifest
and modified guard payload. Inactive B and shared p1 hashes were unchanged,
as were the active boot assets, boot environment and all 12 data files.
A raw checksum of the mounted read/write active root is not an appropriate
no-write test: normal logging and filesystem metadata change it.

From confirmed A, the real `picoos-update` CLI then installed B successfully,
including its signed pre/postinstall guards and bootloader handler. An
additional full 512 MiB readback matched the original root image SHA-256:
`47e4f79271597cf554cdd2f89a4d82d58265309443a985874475c974684d4305`.
Before reboot, the environment showed `boot_slot=B`, `stable_slot=A`,
`upgrade_available=1`, `bootcount=0`; shared p1 and A boot assets remained
unchanged.

**Test-only provisioning, explicitly approved:** the public root image does
not contain local Ethernet/root-SSH configuration or private host keys.
After the raw readback, inactive B was mounted and only the previously
backed-up Ethernet, Avahi and key-only Dropbear/root-SSH diagnostics restored
from A. Every restored file was compared, key modes checked and B unmounted
before reboot. The raw image checksum is the result **before** this intentional
local modification. No private keys were embedded in the signed package or
uploaded. This is not automatic configuration persistence across updates.

B then booted p3 under a new kernel boot identity, confirmed itself, cleared
the trial counters and remained in the same boot beyond 90 seconds with the
15-second nowayout watchdog active. Original host-key SSH, authenticated WLAN
and ten router pings explicitly bound to WLAN succeeded without loss.
All 12 data file hashes matched the original pre-A/B backup.
This first installation test ended in confirmed B. Power cuts, arbitrary
kernel hangs and application readiness remain untested.

Actions run 39790580285 (`0afcfac`) had earlier built the corrected default
selector and text-only U-Boot. Run 39805575018 includes the diagnostic
persistence code and is the artifact from which the verified U-Boot binary
above was installed.

#### Reverse signed SWUpdate installation (2026-10-22)

With explicit approval, the same signed development package was then installed
through `picoos-update` from confirmed B to inactive A. The private diagnostics
were first backed up on B, and all 12 data hashes matched the original backup.
The signed guards and bootloader handler completed successfully; an independent
512 MiB readback of p2 matched the same original root image hash listed above.
Before reboot, `boot_slot=A`, `stable_slot=B`, `upgrade_available=1` and
`bootcount=0` preserved B as fallback. The shared selector, p1 and B boot assets
were unchanged.

As in the first test, only the approved local diagnostics were restored into
the newly written A **after** raw-image verification. Files were compared,
private key/directory modes and the executable health check verified, and A
unmounted. The staged package was removed from B; its private diagnostic
backup was retained. This is still test-only provisioning, not update-safe
configuration persistence.

A booted p2 under a new kernel boot identity, automatically confirmed itself
and remained in the same boot beyond 90 seconds. The watchdog was active at
15 seconds with nowayout enabled, original host-key SSH worked, WLAN
authenticated and ten WLAN-bound router pings completed without loss.
All 12 data hashes still matched the original backup and the shared p1 hash
matched its pre-test value. This reverse-update test ended in confirmed A, with
`boot_slot=stable_slot=A`, `upgrade_available=0` and `bootcount=0`.
Neither this test nor the first root update installed the new shared U-Boot.

Additional host tests:

- `bash scripts/test-ab-runtime.sh`: root/slot identity, inactive-slot guards and
  read-back failure paths.
- `bash scripts/test-uboot-env.sh /path/to/mkenvimage /path/to/fw_printenv /path/to/fw_setenv`:
  real libubootenv reads/writes on a disposable file, confirmation syntax and
  one corrupt redundant copy.
- `bash scripts/test-uboot-bootflow.sh /path/to/native/sandbox/u-boot`:
  tests the actual environment selection script in U-Boot's old Hush parser,
  checking success return values as well as slot identities. Requires the
  matching sandbox `.config` and `arch/sandbox/dts/sandbox.dtb`; unlike a
  Bash-based mock this catches the false-condition return-status regression.
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
