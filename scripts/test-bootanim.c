#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "psplash-bootanim.h"

static unsigned char pixels[128][128];

static void
rectangle(void *context, int x, int y, int width, int height, unsigned color)
{
    unsigned char (*canvas)[128] = context;
    assert(x >= 0 && y >= 0 && x + width <= 128 && y + height <= 128);
    assert(width > 0 && height > 0 && color < 16);
    /* The initialized framebuffer must not flash black between frames. */
    if (context == pixels)
        assert(color != 0);
    for (int row = y; row < y + height; row++)
        for (int column = x; column < x + width; column++)
            canvas[row][column] = color;
}

int main(int argc, char **argv)
{
    const unsigned char star[8][4] = {
        {2, 0, 8, 2}, {3, 1, 15, 4}, {4, 2, 14, 2}, {3, 3, 13, 1},
        {2, 4, 12, 1}, {1, 3, 11, 3}, {0, 2, 10, 9}, {1, 1, 9, 4}
    };
    const unsigned colors[16] = {
        0x000000, 0x1d2b53, 0x7e2553, 0x008751,
        0xab5236, 0x5f574f, 0xc2c3c7, 0xfff1e8,
        0xff004d, 0xffa300, 0xffec27, 0x00e436,
        0x29adff, 0x83769c, 0xff77a8, 0xffccaa
    };
    assert(memcmp(star, picoos_star, sizeof star) == 0);
    for (unsigned i = 0; i < 16; i++)
        assert(((unsigned)picoos_palette[i][0] << 16 |
                (unsigned)picoos_palette[i][1] << 8 |
                picoos_palette[i][2]) == colors[i]);

    for (unsigned frame = 0; frame < 108; frame++) {
        unsigned char expected[128][128] = {{0}};
        unsigned columns = frame < 36 ? frame * 35 / 36 : 35;
        for (unsigned y = 0; y < 5; y++)
            for (unsigned x = 0; x < columns; x++)
                rectangle(expected, 36 + x * 2, 59 + y * 2, 2, 2,
                          picoos_logo[y][x]);
        if (frame >= 40) {
            for (unsigned y = 0; y < 5; y++)
                for (unsigned x = 0; x < 5; x++) {
                    unsigned color = 0;
                    if ((x == 2 && y >= 1 && y <= 3) ||
                        (y == 2 && x >= 1 && x <= 3))
                        color = 7;
                    for (unsigned i = 0; i < 8; i++)
                        if (star[i][0] == x && star[i][1] == y) {
                            unsigned phase = ((frame - 40) / 4) % 8;
                            color = star[i][i == phase || i == (phase + 1) % 8 ? 3 : 2];
                        }
                    rectangle(expected, 96 + x * 2, 51 + y * 2, 2, 2, color);
                }
        }
        picoos_bootanim(pixels, rectangle, frame);
        assert(memcmp(pixels, expected, sizeof pixels) == 0);
    }
    /* The static kernel star must use the same bright palette and geometry. */
    assert(argc == 3);
    FILE *file = fopen(argv[1], "r");
    assert(file);
    for (unsigned y = 0; y < 5; y++)
        for (unsigned x = 0; x < 5; x++) {
            unsigned color = (x == 2 || y == 2) ? 7 : 0;
            for (unsigned i = 0; i < 8; i++)
                if (star[i][0] == x && star[i][1] == y)
                    color = star[i][2];
            for (unsigned channel = 0; channel < 3; channel++) {
                unsigned value;
                assert(fscanf(file, "%u", &value) == 1);
                assert(value == picoos_palette[color][channel]);
            }
        }
    fclose(file);
    file = fopen(argv[2], "r");
    assert(file);
    for (unsigned y = 0; y < 80; y++)
        for (unsigned x = 0; x < 80; x++) {
            unsigned sx = x / 16, sy = y / 16;
            unsigned color = (sx == 2 || sy == 2) ? 7 : 0;
            for (unsigned i = 0; i < 8; i++)
                if (star[i][0] == sx && star[i][1] == sy)
                    color = star[i][2];
            for (unsigned channel = 0; channel < 3; channel++) {
                unsigned value;
                assert(fscanf(file, "%u", &value) == 1);
                assert(value == picoos_palette[color][channel]);
            }
        }
    fclose(file);
    puts("Boot animation passed: 108 frames, two clockwise dimmed points, palette and kernel star.");
}
