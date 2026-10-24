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
