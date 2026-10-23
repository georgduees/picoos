#ifndef PICOOS_BOOTANIM_H
#define PICOOS_BOOTANIM_H

#include <stdint.h>
#include "picoos-bootanim-data.h"

static const unsigned char picoos_palette[16][3] = {
    {0, 0, 0}, {29, 43, 83}, {126, 37, 83}, {0, 135, 81},
    {171, 82, 54}, {95, 87, 79}, {194, 195, 199}, {255, 241, 232},
    {255, 0, 77}, {255, 163, 0}, {255, 236, 39}, {0, 228, 54},
    {41, 173, 255}, {131, 118, 156}, {255, 119, 168}, {255, 204, 170}
};

typedef void (*PicoosRect)(void *, int, int, int, int, unsigned);

/* Coordinates and timing follow the cartridge's 128x128, 30 Hz canvas. */
static void
picoos_bootanim(void *context, PicoosRect rect, uint64_t frame)
{
    unsigned x, y, i;
    unsigned columns = frame >= 36 ? 35 : frame * 35 / 36;

    rect(context, 36, 51, 70, 18, 0);
    for (y = 0; y < 5; y++)
        for (x = 0; x < columns; x++)
            rect(context, 36 + x * 2, 59 + y * 2, 2, 2,
                 picoos_logo[y][x]);

    if (frame < 40)
        return;

    rect(context, 100, 53, 2, 6, 7);
    rect(context, 98, 55, 6, 2, 7);
    for (i = 0; i < 8; i++) {
        unsigned step = ((frame - 40) / 4) % 8;
        unsigned color = picoos_star[i][2];
        if (i == step || i == (step + 1) % 8)
            color = picoos_star[i][3];
        rect(context, 96 + picoos_star[i][0] * 2,
             51 + picoos_star[i][1] * 2, 2, 2, color);
    }
}

#endif
