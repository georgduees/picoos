#!/bin/sh
set -eu
[ "$#" -eq 1 ] || { echo "Usage: $0 p8-rom-mono.fon" >&2; exit 1; }
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
cc -std=c99 -O2 -Wall -Wextra -Werror "$script_dir/convert-console-font.c" -o "$work/convert"
"$work/convert" "$1"
