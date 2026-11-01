#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static unsigned char source[18352];

static unsigned u16(const unsigned char *p)
{
    return p[0] | (unsigned)p[1] << 8;
}

static unsigned u32(const unsigned char *p)
{
    return u16(p) | u16(p + 2) << 16;
}

static void word(unsigned value)
{
    for (unsigned i = 0; i < 4; i++)
        putchar((value >> (i * 8)) & 255);
}

int main(int argc, char **argv)
{
    if (argc != 2) {
        fprintf(stderr, "Usage: convert-console-font p8-rom-mono.fon\n");
        return 1;
    }
    FILE *file = fopen(argv[1], "rb");
    if (!file) {
        perror(argv[1]);
        return 1;
    }
    size_t length = fread(source, 1, sizeof source, file);
    int extra = fgetc(file);
    int failed = ferror(file);
    fclose(file);
    const unsigned char *font = source + 4848;
    if (failed || length != sizeof source || extra != EOF ||
        memcmp(source, "MZ", 2) || u16(font) != 0x200 ||
        u32(font + 2) != 13498 || u16(font + 86) != 16 ||
        u16(font + 88) != 24 || font[95] != 0 || font[96] != 255) {
        fprintf(stderr, "Unsupported PICO-8 FON layout; refusing an incorrect conversion.\n");
        return 1;
    }
    for (unsigned glyph = 0; glyph < 256; glyph++) {
        const unsigned char *entry = font + 118 + glyph * 4;
        if (u16(entry) != 16 || u16(entry + 2) + 48 > 13498) {
            fprintf(stderr, "Invalid FNT glyph %u.\n", glyph);
            return 1;
        }
    }
    /* PSF2: 256 glyphs, 16x24, ASCII-only Unicode map. */
    const unsigned header[] = {0x864ab572, 0, 32, 1, 256, 48, 24, 16};
    for (unsigned i = 0; i < sizeof header / sizeof *header; i++)
        word(header[i]);
    for (unsigned glyph = 0; glyph < 256; glyph++) {
        unsigned offset = u16(font + 118 + glyph * 4 + 2);
        for (unsigned row = 0; row < 24; row++) {
            putchar(font[offset + row]);
            putchar(font[offset + 24 + row]);
        }
    }
    for (unsigned glyph = 0; glyph < 256; glyph++) {
        if (glyph >= 32 && glyph <= 126)
            putchar(glyph);
        putchar(255);
    }
    if (fflush(stdout) || ferror(stdout)) {
        perror("Writing PSF2 font");
        return 1;
    }
    return 0;
}
