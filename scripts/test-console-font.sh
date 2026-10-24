#!/bin/bash
set -euo pipefail
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
sh "$project_dir/scripts/generate-console-font.sh" "$project_dir/assets/fonts/p8-rom-mono.fon" \
    > "$work/font.psf"
cat > "$work/check.c" <<'EOF'
#include <assert.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv)
{
    assert(argc == 3);
    unsigned char fon[18352], psf[12671];
    FILE *f = fopen(argv[1], "rb");
    assert(f && fread(fon, 1, sizeof fon, f) == sizeof fon);
    fclose(f);
    f = fopen(argv[2], "rb");
    assert(f && fread(psf, 1, sizeof psf, f) == sizeof psf);
    assert(fgetc(f) == EOF);
    fclose(f);
    const unsigned char header[32] = {
        0x72,0xb5,0x4a,0x86, 0,0,0,0, 32,0,0,0, 1,0,0,0,
        0,1,0,0, 48,0,0,0, 24,0,0,0, 16,0,0,0
    };
    assert(!memcmp(psf, header, sizeof header));
    unsigned map = 32 + 256*48;
    for (unsigned glyph = 0; glyph < 256; glyph++) {
        unsigned entry = 4848 + 118 + glyph*4;
        unsigned bitmap = 4848 + fon[entry+2] + 256*fon[entry+3];
        for (unsigned row = 0; row < 24; row++) {
            assert(psf[32 + glyph*48 + row*2] == fon[bitmap + row]);
            assert(psf[32 + glyph*48 + row*2+1] == fon[bitmap + 24 + row]);
        }
        if (glyph >= 32 && glyph <= 126)
            assert(psf[map++] == glyph);
        assert(psf[map++] == 255);
    }
    assert(map == sizeof psf);
    puts("Console font passed: all 256 glyphs, exact 16x24 bitmap, ASCII-only Unicode map.");
}
EOF
cc -std=c99 -Wall -Wextra -Werror "$work/check.c" -o "$work/check"
"$work/check" "$project_dir/assets/fonts/p8-rom-mono.fon" "$work/font.psf"
head -c 512 "$project_dir/assets/fonts/p8-rom-mono.fon" > "$work/invalid.fon"
if sh "$project_dir/scripts/generate-console-font.sh" "$work/invalid.fon" \
    > "$work/invalid.psf" 2> "$work/error"; then
    echo "Truncated font unexpectedly accepted." >&2
    exit 1
fi
grep -q 'Unsupported PICO-8 FON layout' "$work/error"
test ! -s "$work/invalid.psf"

overlay="$project_dir/br2-external/board/zero2w/overlay"
mkdir -p "$work/bin" "$work/dev" "$work/fonts"
printf fixture > "$work/fonts/picoos.psf"
cat > "$work/bin/setfont" <<'EOF'
#!/bin/sh
set -eu
test "$#" -eq 3
test "$1" = -C
test "$2" = "$PICOOS_FONT_TEST/dev/tty3"
test "$3" = "$PICOOS_FONT_TEST/fonts/picoos.psf"
printf invoked > "$PICOOS_FONT_TEST/setfont-called"
exit "${PICOOS_FONT_TEST_FAIL:-0}"
EOF
chmod +x "$work/bin/setfont"
export PICOOS_FONT_TEST="$work"
sed -e "s|/usr/sbin/setfont|$work/bin/setfont|g" \
    -e "s|/dev/tty3|$work/dev/tty3|g" \
    -e "s|/usr/share/consolefonts|$work/fonts|g" \
    -e "s|-c /dev/fb0|-c /dev/null|g" \
    "$overlay/etc/init.d/S13console-font" > "$work/font-service"
sh "$work/font-service" start
test -f "$work/setfont-called"
if PICOOS_FONT_TEST_FAIL=1 sh "$work/font-service" start 2> "$work/load-error"; then
    echo "Font loader failure unexpectedly accepted." >&2
    exit 1
fi
grep -Fq 'Failed to load PicoOS console font on tty3.' "$work/load-error"
rm "$work/setfont-called"
sed 's|-c /dev/null|-c /nonexistent/picoos-fb0|' \
    "$work/font-service" > "$work/font-deferred"
sh "$work/font-deferred" start 2> "$work/deferred"
grep -Fq 'Console font deferred' "$work/deferred"
test ! -e "$work/setfont-called"
grep -Fxq CONFIG_SETFONT=y "$project_dir/br2-external/board/zero2w/busybox.fragment"
grep -Fxq CONFIG_FEATURE_LOADFONT_PSF2=y "$project_dir/br2-external/board/zero2w/busybox.fragment"
echo "Console font service passed: explicit tty3, loader failure and no-framebuffer deferral."
