#!/bin/bash
set -euo pipefail
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
export PICOOS_LAUNCH_TEST="$work"
cat > "$work/pico8_dyn" <<'EOF'
#!/bin/sh
set -eu
test "$SDL_VIDEODRIVER" = kmsdrm
test "$SDL_AUDIODRIVER" = alsa
test "$AUDIODEV" = default
test "$SDL_RENDER_SCALE_QUALITY" = 0
test "$SDL_RENDER_VSYNC" = 1
printf '%s\n' "$@" > "$PICOOS_LAUNCH_TEST/arguments"
exit "${PICOOS_TEST_EXIT:-0}"
EOF
chmod +x "$work/pico8_dyn"
sed "s|^cd /data/pico8$|cd '$work'|" \
    "$project_dir/br2-external/board/zero2w/overlay/usr/sbin/picoos-pico8" > "$work/launcher"
SDL_AUDIODRIVER=dummy SDL_RENDER_SCALE_QUALITY=linear SDL_RENDER_VSYNC=0 \
    sh "$work/launcher" -splore "cart with spaces.p8"
printf '%s\n' -splore "cart with spaces.p8" -pixel_perfect 1 -draw_rect 448,28,1024,1024 > "$work/expected"
cmp "$work/expected" "$work/arguments"
result=0
PICOOS_TEST_EXIT=7 sh "$work/launcher" || result=$?
test "$result" -eq 7
grep -Fq 'slave.pcm "hw:CARD=vc4hdmi,DEV=0"' \
    "$project_dir/br2-external/board/zero2w/overlay/etc/asound.conf"
echo "PICO-8 launcher tests passed (HDMI ALSA, integer scaling, arguments and failure propagation)."
