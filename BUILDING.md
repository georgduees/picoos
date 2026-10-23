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
Buildroot builds SDL2 with KMS/DRM and Mesa Gallium VC4 for the Zero 2 W's
VideoCore IV. U-Boot applies the slot-local KMS overlay and falls back to the
original DTB on older slots without the overlay. New slots expose
`/dev/dri/card0` without an X11/Wayland session. The firmware GPU
reservation is 64 MiB; KMS uses CMA from system memory rather than requiring a
large legacy GPU split. The active image before this change had only a firmware
framebuffer and PICO-8 failed with `SDL Error: No available video device`.
On 2026-10-23, image commit `4b5acbe` booted and confirmed slot A. Loading
`i2c_bcm2835` and `vc4` exposed DRM card0/renderD128 and the HDMI sound card.
Both modules are now listed in `graphics.conf` for boot-time loading. PICO-8
started with `SDL_VIDEODRIVER=kmsdrm SDL_AUDIODRIVER=dummy`, loaded Mesa
Gallium/EGL/GLES, and its prompt was confirmed visible on HDMI by the user.
Splore navigation with the Stadia controller was also confirmed. The local
PICO-8 config uses `boot_to_splore 1` and, for testing only, `show_fps 1`.
Launch with `picoos-pico8 -splore`. This wrapper explicitly forces
`-pixel_perfect 1`, SDL nearest-neighbour scaling and
`-draw_rect 448,28,1024,1024`: the 128x128 game image is centered at exactly
8x on the 1920x1080 output. New images enable SDL2's ALSA backend by including
alsa-lib. The launcher selects ALSA's default PCM; `/etc/asound.conf` routes it
through `plug` to `hw:CARD=vc4hdmi,DEV=0`, using the stable HDMI card name
rather than its numeric index. ALSA converts PICO-8's mono/22050 Hz output
to hardware-supported parameters. No silent dummy fallback is configured.
Use the television's 1:1/Just Scan mode; panel scaling can still soften
the HDMI image if the panel is not native 1920x1080.
After a restart, DRM devices and Bluetooth pairing were present without
manual module loading. PICO-8 now starts automatically through the service
described under "Quiet console boot and PICO-8 startup".
Shutdown tracing on 2026-10-23 showed a reboot hanging in `S11modules`,
after network and Bluetooth services had stopped. The board's module service
therefore loads configured modules at startup but does not unload them at
shutdown. The kernel handles device shutdown; restart/reload only ensures
modules are loaded. Cold boots connected to WLAN automatically, whereas the
hung shutdown never reached a new boot. WLAN boot/reconnect validation must
be distinguished from this shutdown failure.
The login getty now runs only on `tty3`, separate from the game display.
Previously it ran on `tty1`. A generic `/dev/console` getty would
compete with an explicit getty on the same kernel console, causing
`tcsetpgrp: Inappropriate ioctl for device` during startup.
With the no-unload module service installed, two consecutive software reboots
on the test Pi returned automatically to WLAN at `192.168.0.98`; Internet
pings bound to `wlan0` succeeded without packet loss. The second reboot used
the original, uninstrumented shutdown script and the single `tty1` getty;
no `tcsetpgrp` error was logged. Slot A remained confirmed and KMS used
1280x720 with no margins. This does not yet certify offline-to-online or
access-point-loss recovery.
The HDMI baseline is 1920x1080 at 60 Hz: firmware uses CEA group 1, mode 16,
and the KMS kernel command line uses `video=HDMI-A-1:1920x1080@60`.
Existing cards need both shared firmware configuration and persistent U-Boot
`load_slot` maintenance; a root-only update does not change these settings.
No software overscan/underscan controls are installed. Disable overscan on the
television if necessary.
The existing card still reserves 100 MiB of firmware GPU RAM; the new 64 MiB
setting applies to fresh images, not root-only updates. U-Boot environment
maintenance was backed up on `/data/kms-maintenance-4b5acbe` and read-back
verified; older slots without the overlay retain their original DTB boot.
BlueZ, its `bluetoothctl` client, Bluetooth HID/HOG profiles, and
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
`/dev/input/js0` on hardware; the VC4 HDMI ALSA device is present.
The local PICO-8 binary remains user-supplied data and is never copied into
public images. Audible HDMI confirmation, Bluetooth audio and performance
measurements remain separate hardware tasks.

HDMI audio bring-up: `aplay -l` lists hardware devices, and
`speaker-test -D default -c 2 -r 48000 -t sine -l 1` tests the configured
default output. Start with low TV volume. Confirm that PICO-8's log reports
`Current audio driver: alsa`, then verify audible game audio.
On 2026-10-23, the signed `04d99e6` image was installed and confirmed on slot A.
The existing PICO-8 home and demos were copied from B before booting.
Jelpi started with volume 64/256 and the log reported `SDL_OpenAudio ok` and
`Current audio driver: alsa`. The HDMI PCM stream was `RUNNING`, owned by the
PICO-8 process, at 44100 Hz stereo in `IEC958_SUBFRAME_LE` format. This verifies
the software playback path; audible output from the television still needs
user confirmation.

Splore downloads require GNU Wget with OpenSSL HTTPS support and the system
CA certificate bundle. The previous BusyBox Wget rejected HTTPS URLs outright.
The NTP daemon starts through Buildroot's `S49ntp`, after network startup,
and synchronizes against the configured NTP pool servers when the network
is available. Its `-g` option permits the initial correction from 1970 on
this board without an RTC. Boot does not wait for synchronization; offline
use remains possible, but HTTPS certificate validation needs a correct clock.
On 2026-10-23, the signed `d883b21` base was installed on slot B and confirmed.
Before booting, local bring-up corrections (no module unloading, WLAN-only
diagnostics, single tty1 getty and the pixel-perfect launcher) were copied into
the inactive root, together with the existing PICO-8 home and demos. This is
therefore a locally maintained root, not an unmodified CI artifact.
After boot, ntpd corrected the clock from 1970 without a manual date command.
GNU Wget downloaded `https://carts.lexaloffle.com/astfm-1.p8.png` with normal
certificate verification (HTTP 200, 33655 bytes, PNG signature verified).
Splore subsequently populated its BBS cartridge cache with new downloads.
KMS remained at 1920x1080 and PICO-8 ran with the centered 1024x1024 draw
rectangle and pixel-perfect scaling. Curl is not needed by PICO-8.

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

## Animated cartridge splash

The owner's `bootanim.p8` is the source artwork for the native psplash
animation. `scripts/generate-bootanim.sh` extracts the 35x5 sprite and the
eight bright/dark star-point colors; it rejects unsupported timing/layout
changes rather than silently building a mismatched animation. The native C
renderer ports the cartridge's 30 Hz reveal (36 frames), star appearance
(frame 40) and clockwise dimming of two adjacent points (one step per four
frames). The star cycle repeats without restarting the text reveal.

The background is PICO-8 black (`cls(0)`), not dark blue. All colors use the
original 16-color palette shared with the static kernel star. A 16-bit
RGB565 framebuffer necessarily quantizes those RGB values; it cannot display
every 24-bit palette entry exactly. The 128x128 canvas is centered and
integer-scaled without interpolation (8x on 1080p).

The package patch replaces the stock psplash logo. There is no separate
animation daemon, PICO-8 runtime, video decoder or desktop involved.
`S12psplash` starts after `S11modules` has loaded VC4, avoiding the
firmware-framebuffer-to-KMS handover. `S99psplash-stop` sends `QUIT` and
checks that the process has exited; the animation does not continue behind
PICO-8 and adds no intentional minimum boot delay. Incremental builds remove
the obsolete `S00psplash`. Existing roots need the new image to get this
animation.

Hardware validation: the `6da18c1` root image was installed on slot B and
confirmed stable after reboot. The subsequent no-clear correction was
cross-compiled with the matching Bootlin ARMv6 hard-float toolchain and
installed directly as `/usr/bin/psplash` on that root. Two locally captured
1080p framebuffer snapshots matched the expected RGB565 palette and distinct
star phases (5 and 7). Drawing only colored sprite pixels and overwriting
the star points directly avoids black intermediate frames and unnecessary
framebuffer writes. The framebuffer is cleared once at startup, not on every
animation tick. This fbdev device does not support psplash double buffering;
the normal single-buffer fallback remains in use. A subsequent normal reboot
returned over WLAN on stable slot B with no remaining splash process or
PID file. Visual confirmation of the complete boot sequence on the TV remains
a user-side check; framebuffer checks do not establish perceived smoothness.

Validation: `bash scripts/test-bootanim.sh` compares 108 complete frames,
the bright/dark mapping, palette and both static kernel-star assets.
`bash scripts/test-psplash-loop.sh CONFIGURED_PSPLASH_SOURCE` runs the
patched production event loop against an in-memory 1080p framebuffer and
checks timed drawing plus prompt FIFO-command exit, without touching a
desktop framebuffer. Both tests also run in CI.

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
later psplash animation uses the same palette and star geometry. An existing build needs
`linux-reconfigure` followed by the normal image build to replace the compiled
logo.

The early firmware framebuffer is separate from VC4/KMS. U-Boot 2026.04
requests RGB byte order but describes it to Linux as `a8r8g8b8`, swapping
red and blue in early console artwork. The board's U-Boot patch requests
BGR byte order instead, matching the existing simplefb description. Artwork
stays in the original PICO-8 palette; no compensating channel swap is applied
to the PPM or to the later psplash renderer. A rootfs-only update does not
replace U-Boot on the shared firmware partition.

Hardware mailbox queries confirmed the mismatch before the fix
(`pixel_order=1`, RGB; 32-bit depth) and the matching BGR order after it
(`pixel_order=0`, 32-bit depth; simplefb still `a8r8g8b8`). The test card
keeps the original `/u-boot.bin`; its firmware configuration selects the
locally cross-built `/u-boot-rgb.bin` (SHA256
`832846873a0ea3c9329b544d34d3c0938526cd20dfca1653b4e54f9463807135`).
The previous shared configuration and bootloader were backed up under
`/data` before rollout. Existing local GPU-memory/core-clock settings were
preserved, not replaced with the image defaults.

## Quiet console boot and PICO-8 startup

Normal boots send U-Boot output to serial, disable the firmware rainbow
splash and put the kernel console on tty3 with `quiet loglevel=3
logo.nologo vt.global_cursor_default=0`. CPU-count logos remain compiled in
for diagnostic boots but are hidden in normal console operation. Service
output goes to `/var/log/boot.log`; kernel messages remain available through
`dmesg`, and syslog in `/var/log/messages`. These logs are in RAM, avoiding ongoing
SD-card writes. The single local getty is on tty3 (Ctrl+Alt+F3 with a keyboard);
the board post-build removes Buildroot's automatically appended tty1 getty
so it cannot overwrite the game display.

After the health checks and splash shutdown, `S99start-pico8` starts the
existing `/data/pico8/pico8_dyn` via the pixel-perfect ALSA launcher in
Splore. Standard output/error go to `/var/log/pico8.log`, with tty1 used for
input. The launcher explicitly requests `SDL_RENDER_VSYNC=1`, in addition
to the previously observed SDL renderer `PRESENTVSYNC` flag (`0x4` in
`0x0000000E`). Nearest-neighbor integer scaling remains enabled. This avoids
tearing; it is not a claim of measured minimum input latency.
There is no desktop or respawning launcher loop. Startup failures are
reported in the boot log; an uninstalled proprietary runtime is explicitly
reported and skipped rather than making the public image unbootable.
Stopping the service sends SIGTERM and waits for exit so PICO-8 can save its
configuration. Use `/etc/init.d/S99start-pico8 start|stop|restart`; do not
start a second manual PICO-8 while the service is running.

On the test Pi, a normal reboot with these shared boot settings returned
over WLAN to stable slot B (`upgrade_available=0`), automatically started
PICO-8 on active tty1, and left no splash process/PID file. The ALSA playback
status was `RUNNING` with the PICO-8 PID as owner. A later service
stop/start was also verified. The running process has
`SDL_RENDER_VSYNC=1`, `SDL_RENDER_SCALE_QUALITY=0` and the ALSA/KMSDRM
drivers. This initial test used `6da18c1` with the corrected splash,
launcher and console files installed directly. After a manual BlueZ reconnect, the persistent Stadia pairing was
connected/trusted and exposed both `event2` and `js0`; automatic
controller-initiated reconnect after power-on is not certified by that test.

Final rollout: both push and PR builds for `b006f49` passed, including the
complete image, console, animation and Bluetooth persistence tests. The
signed update (SHA256
`2484527ba02d7878d10acc8bf4aa5aa01c7a78881dad227930745e30e42ad097`)
was installed from B to inactive A and read-back verified. Only the existing
user PICO-8 home was copied to the new root before reboot. Slot A then
confirmed itself (`stable_slot=A`, `upgrade_available=0`), returned over
WLAN, automatically started Splore on tty1 with the expected SDL environment
and owned a running HDMI-ALSA stream. The dashboard reports the new A slot.
The saved Stadia pairing reconnected on an explicit BlueZ connect and
exposed `js0`. The shared bootloader/configuration remain the separately
installed, color-corrected versions described above.

### Controller reconnect and display-unavailable checks

Follow-up testing on the saved, trusted Stadia pairing confirmed native
BlueZ reconnect without another `connect` call in three cases: an explicit
`bluetoothctl disconnect`, a full `S40bluetoothd restart`, and a normal Pi
reboot. Each restored `Connected: yes` and `/dev/input/js0`. BlueZ 5.79's
HOG profile already has `auto_connect = true`; probing that profile restores
the LE auto-connect list from the saved device services. No polling daemon,
repeated discovery scans, hard-coded controller address or audio-oriented
`ReconnectUUIDs` override is needed. This does not certify physical
controller power-off/power-on or out-of-range recovery; those cases still
need a separate hardware test.

During that reboot test HDMI was disconnected. KMS consequently exposed
no `/dev/fb0`, so neither the animation nor PICO-8 could run. Splash startup
now explicitly rejects a missing framebuffer and checks for immediate
process exit before writing its PID file. A stale PID is reported and
removed on stop, rather than sending `QUIT` to a nonexistent reader. PICO-8
reports a disconnected HDMI connector before launching, avoiding an empty
game log as the only clue. These paths are covered by the console tests and
were also checked on the Pi without a display. No forced HDMI mode or
automatic retry loop has been added; after connecting the display, start
`/etc/init.d/S99start-pico8 start` explicitly. Successful display-connected
startup was verified in the earlier rollout; this follow-up does not claim
a new visual or audio check.

## Interactive login dashboard

The original PicoOS welcome screen is inspired by DietPi's compact system
overview, not copied from it. The interactive login profile invokes
`picoos-motd` after authentication, for SSH and local shell logins. It shows
host/kernel, running A/B slot, uptime, load averages, available-memory-based
usage, CPU temperature and WLAN IPv4, followed by local service/log/update
commands. Reads are local, with no Internet lookups or privileged changes.
Color is used only on a suitable terminal, and `NO_COLOR` disables it.
The stock `/etc/motd` is empty to avoid duplicate greetings. Noninteractive
SSH commands and file transfers do not invoke the dashboard.

`bash scripts/test-console-runtime.sh` checks deterministic dashboard values,
noninteractive silence, start/stop failures and duplicate-start protection,
quiet boot settings and the idempotent post-build getty/log configuration.

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
`picoos-diagnostics` provides explicitly enabled **key-only root SSH** over
WLAN across root-slot replacements. USB-OTG Ethernet is no longer enabled by
this service and is not required for boot health. It does not import arbitrary
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
root's `authorized_keys` there. It does not load USB-Ethernet drivers or
configure Ethernet DHCP. `S50dropbear` uses fixed key-only arguments and the explicit RAM
host key, never automatic fallback host-key generation or shell-sourced
persistent options. The local boot health check requires the opted-in
listener to be prepared and running before confirming a trial slot.

`picoos-diagnostics disable` removes the activation marker and stops the
listener, retaining the stored keys. Existing SSH sessions
may remain until reboot. Re-enable a retained store with
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
The explicit diagnostic opt-in above persists its SSH keys;
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
