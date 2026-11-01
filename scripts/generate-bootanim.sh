#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { echo "Usage: $0 bootanim.p8" >&2; exit 1; }
for expected in 'cls(0)' 'local spr_w = 35' 'local scale = 2' \
    'local dx = 36' 'local dy = 59' 't / 36' 'if t >= 40 then' \
    'flr((t - 40) / 4)' 'i == step or i == (step % #star_pixels + 1)'; do
    grep -Fq "$expected" "$1" ||
        { echo "Unsupported boot animation logic: missing $expected" >&2; exit 1; }
done
awk '
BEGIN { print "/* Generated from bootanim.p8; do not edit. */"
        print "static const unsigned char picoos_star[8][4] = {" }
/\{dx=/ {
    line=$0
    gsub(/[^0-9,]/, "", line)
    sub(/,$/, "", line)
    n=split(line, value, ",")
    if (n != 4) exit 1
    printf "    {%d, %d, %d, %d},\n", value[1], value[2], value[3], value[4]
    stars++
}
/^__gfx__$/ {
    print "};"
    print "static const unsigned char picoos_logo[5][35] = {"
    gfx=1
    next
}
gfx && rows < 5 {
    if (length($0) != 128 || $0 ~ /[^0-9a-f]/) exit 1
    printf "    {"
    for (x=9; x<=43; x++) {
        printf "%s%d", x==9 ? "" : ", ", index("0123456789abcdef", substr($0,x,1))-1
    }
    print "},"
    rows++
}
END {
    print "};"
    if (stars != 8 || rows != 5) exit 1
}' "$1"
