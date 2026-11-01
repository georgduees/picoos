#!/bin/bash
set -euo pipefail
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/bin" "$work/modules"
export PICOOS_MODULES_DIR="$work/modules" MODULE_TEST_LOG="$work/log"
export PATH="$work/bin:$PATH"
cat > "$work/bin/modprobe" <<'EOF'
#!/bin/sh
printf '%s\n' "$*" >> "$MODULE_TEST_LOG"
[ "$2" != broken ]
EOF
cat > "$work/bin/rmmod" <<'EOF'
#!/bin/sh
echo "Unexpected module unload" >> "$MODULE_TEST_LOG"
exit 1
EOF
chmod +x "$work/bin/"*
printf '# comment\n\nbrcmfmac\nvc4\nexample option=1\n' > "$work/modules/test.conf"
tool="$project_dir/br2-external/board/zero2w/overlay/etc/init.d/S11modules"
sh "$tool" start
printf '%s\n' '-q brcmfmac' '-q vc4' '-q example option=1' > "$work/expected"
cmp "$work/expected" "$work/log"
sh "$tool" stop
cmp "$work/expected" "$work/log"
sh "$tool" restart
test "$(wc -l < "$work/log")" -eq 6
printf 'broken\n' > "$work/modules/test.conf"
if sh "$tool" start > "$work/error" 2>&1; then
    echo "Module load failure was ignored" >&2
    exit 1
fi
grep -q 'failed to load module broken' "$work/error"
rm "$work/modules/test.conf"
sh "$tool" start
sh "$tool" stop
echo "Module runtime tests passed (load arguments, failure reporting, no shutdown unload)."
