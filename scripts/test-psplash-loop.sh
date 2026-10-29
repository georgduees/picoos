#!/bin/bash
set -euo pipefail
[ "$#" -eq 1 ] || { echo "Usage: $0 CONFIGURED_PSPLASH_SOURCE" >&2; exit 1; }
source_dir=$(readlink -e "$1")
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cat > "$work/loop.c" <<'EOF'
#include "psplash.h"
#include <sys/wait.h>
#include <time.h>

extern void psplash_main(PSplashFB *, int, int);

int main(void)
{
    int descriptors[2], status;
    PSplashFB fb = {0};
    struct timespec before, after;
    assert(pipe(descriptors) == 0);
    fb.width = fb.real_width = 1920;
    fb.height = fb.real_height = 1080;
    fb.bpp = 32;
    fb.stride = fb.width * 4;
    fb.rgbmode = RGB888;
    fb.bdata = calloc(fb.height, fb.stride);
    assert(fb.bdata);
    pid_t writer = fork();
    assert(writer >= 0);
    if (!writer) {
        close(descriptors[0]);
        usleep(1600000);
        assert(write(descriptors[1], "QUIT\n", 5) == 5);
        close(descriptors[1]);
        _exit(0);
    }
    close(descriptors[1]);
    clock_gettime(CLOCK_MONOTONIC, &before);
    psplash_main(&fb, descriptors[0], 0);
    clock_gettime(CLOCK_MONOTONIC, &after);
    assert(waitpid(writer, &status, 0) == writer);
    assert(WIFEXITED(status) && WEXITSTATUS(status) == 0);
    double elapsed = after.tv_sec - before.tv_sec +
                     (after.tv_nsec - before.tv_nsec) / 1e9;
    assert(elapsed >= 1.5 && elapsed < 2.5);
    /* The loop must draw frames, not just exit promptly on QUIT. */
    unsigned nonzero = 0;
    for (int i = 0; i < fb.height * fb.stride; i++)
        nonzero += fb.bdata[i] != 0;
    assert(nonzero > 10000);
    free(fb.bdata);
    close(descriptors[0]);
    puts("psplash event loop passed: timed animation, framebuffer rendering and prompt QUIT.");
}
EOF
flags=(-std=gnu99 -O2 -Wall -Wextra -I"$source_dir" -DHAVE_CONFIG_H
       -DPSPLASH_DISABLE_STARTUP_MSG -DPSPLASH_DISABLE_PROGRESS_BAR
       '-DFONT_HEADER="radeon-font.h"' -DFONT_DEF=radeon_font)
cc "${flags[@]}" -Dmain=picoos_psplash_program -c "$source_dir/psplash.c" -o "$work/main.o"
cc "${flags[@]}" "$work/loop.c" "$work/main.o" \
    "$source_dir/psplash-fb.c" "$source_dir/psplash-console.c" -o "$work/loop"
timeout 5 "$work/loop"
