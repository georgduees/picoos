#!/bin/bash
set -euo pipefail
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
sh "$project_dir/scripts/generate-bootanim.sh" "$project_dir/bootanim.p8" > "$work/picoos-bootanim-data.h"
awk '!/^#/ { print }' "$project_dir/br2-external/board/zero2w/kernel-star.ppm" |
    tail -n +4 > "$work/star-rgb"
awk '!/^#/ { print }' "$project_dir/br2-external/board/zero2w/kernel-logo.ppm" |
    tail -n +4 > "$work/logo-rgb"
cc -std=c99 -Wall -Wextra -Werror \
    -I"$work" -I"$project_dir/br2-external/board/zero2w" \
    "$project_dir/scripts/test-bootanim.c" -o "$work/test"
"$work/test" "$work/star-rgb" "$work/logo-rgb"
sed 's/cls(0)/cls(1)/' "$project_dir/bootanim.p8" > "$work/invalid.p8"
if sh "$project_dir/scripts/generate-bootanim.sh" "$work/invalid.p8" > "$work/invalid.h" 2> "$work/error"; then
    echo "Unsupported cartridge changes were silently accepted." >&2
    exit 1
fi
grep -q 'Unsupported boot animation logic' "$work/error"
