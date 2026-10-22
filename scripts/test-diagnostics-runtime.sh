#!/bin/bash
set -euo pipefail
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$project_dir/provisioning/local/tmp"
work=$(mktemp -d "$project_dir/provisioning/local/tmp/test-diagnostics.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
export TEST_ROOT="$work" TEST_LISTENER_PID=$$
export REAL_STAT REAL_READLINK
REAL_STAT=$(command -v stat)
REAL_READLINK=$(command -v readlink)
export PATH="$work/bin:$PATH"
mkdir -p "$work/bin" "$work/run" "$work/data" "$work/root/.ssh" "$work/etc/dropbear"
chmod 700 "$work/data" "$work/root/.ssh"
ssh-keygen -q -t ed25519 -N '' -f "$work/client"
cp "$work/client.pub" "$work/authorized_keys"
chmod 600 "$work/authorized_keys"
printf 'test-only-dropbear-key\n' > "$work/host-key"
chmod 600 "$work/host-key"
printf '/dev/mmcblk0p4 %s/data vfat rw,nosuid,nodev 0 0\n' "$work" > "$work/mounts"
cat > "$work/bin/id" <<'EOF'
#!/bin/sh
echo "${TEST_UID:-0}"
EOF
cat > "$work/bin/stat" <<'EOF'
#!/bin/sh
if [ "$1" = -c ] && [ "$2" = '%u:%a' ]; then
    printf '%s:%s\n' "${TEST_OWNER:-0}" "$("$REAL_STAT" -c %a "$3")"
else
    exec "$REAL_STAT" "$@"
fi
EOF
cat > "$work/bin/readlink" <<'EOF'
#!/bin/sh
if [ "$1" = -f ] && [ "$2" = "/proc/$TEST_LISTENER_PID/exe" ]; then
    echo "$TEST_ROOT/bin/dropbear"
else
    exec "$REAL_READLINK" "$@"
fi
EOF
cat > "$work/bin/dropbearkey" <<'EOF'
#!/bin/sh
set -eu
if [ "$1" = -t ]; then
    test "$2" = ed25519
    test "$3" = -f
    printf 'test-only-dropbear-key\n' > "$4"
    cp "$TEST_ROOT/client.pub" "$4.pub"
else
    test "$1" = -y
    test "$2" = -f
    grep -qx 'test-only-dropbear-key' "$3"
fi
test "${TEST_KEY_FAILURE:-0}" = 0
cat "$TEST_ROOT/client.pub"
EOF
cat > "$work/bin/modprobe" <<'EOF'
#!/bin/sh
echo "$*" >> "$TEST_ROOT/modules.log"
test "${TEST_MODULE_FAILURE:-0}" = 0
EOF
cat > "$work/bin/start-stop-daemon" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$*" >> "$TEST_ROOT/daemon.log"
if [ "$1" = -S ]; then
    test "$*" = "-S -q -p $TEST_ROOT/run/dropbear.pid -x $TEST_ROOT/bin/dropbear -- -s -r $TEST_ROOT/run/picoos-diagnostics/dropbear_ed25519_host_key -P $TEST_ROOT/run/dropbear.pid"
    test "${TEST_START_FAILURE:-0}" = 0
    printf '%s\n' "$TEST_LISTENER_PID" > "$TEST_ROOT/run/dropbear.pid"
fi
EOF
cat > "$work/bin/sync" <<'EOF'
#!/bin/sh
exit 0
EOF
touch "$work/bin/dropbear"
chmod 755 "$work/bin/"*
sed -e "s|/data|$work/data|g" \
    -e "s|/run/|$work/run/|g" \
    -e "s|/root/|$work/root/|g" \
    -e "s|/etc/|$work/etc/|g" \
    -e "s|/proc/mounts|$work/mounts|g" \
    -e "s|/usr/sbin/dropbear|$work/bin/dropbear|g" \
    "$project_dir/br2-external/board/zero2w/overlay/usr/sbin/picoos-diagnostics" > "$work/helper"
run() { sh "$work/helper" "$@"; }
reject() {
    if "$@" > "$work/rejection.log" 2>&1; then
        echo "Diagnostics unexpectedly accepted: $*" >&2
        exit 1
    fi
}
store="$work/data/diagnostics"
runtime="$work/run/picoos-diagnostics"
run prepare
run start
run check
test ! -e "$work/daemon.log"
test ! -e "$runtime/ready"
test ! -e "$store"
reject env TEST_UID=1000 sh "$work/helper" enable "$work/authorized_keys" "$work/host-key"
reject env TEST_OWNER=1000 sh "$work/helper" enable "$work/authorized_keys" "$work/host-key"
reject run enable
printf 'invalid\n' > "$work/invalid.pub"
chmod 600 "$work/invalid.pub"
reject run enable "$work/invalid.pub" "$work/host-key"
run enable "$work/authorized_keys" "$work/host-key"
test "$(find "$store" -type f | wc -l)" -eq 3
cmp "$work/host-key" "$store/dropbear_ed25519_host_key"
reject run enable "$work/authorized_keys"
run prepare
cmp "$work/authorized_keys" "$runtime/authorized_keys"
cmp "$work/host-key" "$runtime/dropbear_ed25519_host_key"
test "$("$REAL_STAT" -c %a "$runtime/authorized_keys")" = 600
test "$("$REAL_STAT" -c %a "$runtime/dropbear_ed25519_host_key")" = 600
test "$("$REAL_STAT" -c %a "$runtime")" = 700
test "$("$REAL_READLINK" "$work/root/.ssh/authorized_keys")" = "$runtime/authorized_keys"
grep -qx 'auto eth0' "$runtime/interfaces"
grep -qx asix "$work/modules.log"
grep -qx ax88179_178a "$work/modules.log"
run start
run check
printf '0\n' > "$work/run/dropbear.pid"
reject run check
printf '%s\n' "$TEST_LISTENER_PID" > "$work/run/dropbear.pid"
run disable
test ! -e "$store/enabled"
test ! -e "$runtime/ready"
test ! -e "$runtime/authorized_keys"
test ! -e "$work/run/dropbear.pid"
test -s "$store/dropbear_ed25519_host_key"
before=$(wc -l < "$work/daemon.log")
run start
test "$(wc -l < "$work/daemon.log")" = "$before"
run enable
for name in enabled authorized_keys dropbear_ed25519_host_key; do
    mv "$store/$name" "$store/$name.saved"
    ln -s "$store/$name.saved" "$store/$name"
    reject run prepare
    test ! -e "$runtime/ready"
    reject run start
    rm "$store/$name"
    mv "$store/$name.saved" "$store/$name"
done
for name in enabled authorized_keys dropbear_ed25519_host_key; do
    chmod 644 "$store/$name"
    reject run prepare
    test ! -e "$runtime/ready"
    chmod 600 "$store/$name"
done
printf 'unsupported-format\n' > "$store/enabled"
reject run prepare
reject run enable
printf 'picoos-diagnostics-v1\n' > "$store/enabled"
reject env TEST_KEY_FAILURE=1 sh "$work/helper" prepare
reject env TEST_MODULE_FAILURE=1 sh "$work/helper" prepare
test ! -e "$runtime/ready"
run prepare
reject env TEST_START_FAILURE=1 sh "$work/helper" start
cp "$store/authorized_keys" "$store/key.saved"
printf '\n# pending key-file edit\n' >> "$store/authorized_keys"
reject run start
cp "$store/key.saved" "$store/authorized_keys"
printf 'bad key\n' > "$store/authorized_keys"
reject run start
mv "$store/key.saved" "$store/authorized_keys"
mv "$work/mounts" "$work/mounts.saved"
touch "$work/mounts"
reject run prepare
test ! -e "$runtime/ready"
mv "$work/mounts.saved" "$work/mounts"
mv "$store" "$store.saved"
ln -s "$store.saved" "$store"
reject run prepare
rm "$store"
mv "$store.saved" "$store"
mv "$runtime" "$runtime.saved"
ln -s "$runtime.saved" "$runtime"
reject run prepare
rm "$runtime"
mv "$runtime.saved" "$runtime"
run disable
test ! -e "$store/enabled"
rm "$store/authorized_keys" "$store/dropbear_ed25519_host_key"
rmdir "$store"
rm "$work/root/.ssh/authorized_keys"
cp "$work/authorized_keys" "$work/root/.ssh/authorized_keys"
cp "$work/host-key" "$work/etc/dropbear/dropbear_ed25519_host_key"
printf 'picoos-diagnostics-v1\n' > "$work/etc/picoos-diagnostics-import"
chmod 600 "$work/etc/picoos-diagnostics-import"
run prepare
test ! -e "$work/etc/picoos-diagnostics-import"
cmp "$work/host-key" "$store/dropbear_ed25519_host_key"
run start
run check
run disable
rm "$store/authorized_keys" "$store/dropbear_ed25519_host_key"
rmdir "$store"
run enable "$work/authorized_keys"
test "$(find "$store" -type f | wc -l)" -eq 3
test ! -e "$store/dropbear_ed25519_host_key.pub"
run prepare
run start
run check
test ! -e "$work/run/picoos-diagnostics.lock"
grep -q 'picoos-diagnostics check' "$project_dir/br2-external/board/zero2w/overlay/etc/init.d/S99picoos-health"
echo "Diagnostic persistence tests passed (opt-in, RAM keys, key-only SSH, health, disable/import, key generation and fail-closed validation)."
