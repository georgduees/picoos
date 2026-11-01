#!/bin/bash
set -euo pipefail
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
cleanup() {
    for file in "$work/run/pico8-display-wait.pid" "$work/run/pico8.pid"; do
        if [ -f "$file" ]; then
            pid=$(cat "$file")
            kill "$pid" 2>/dev/null || true
        fi
    done
    rm -rf -- "$work"
}
trap cleanup EXIT
mkdir -p "$work"/{bin,run,data/pico8,sys/class/drm/card0-HDMI-A-1,log}
export PICOOS_TEST_WORK="$work"
export PATH="$work/bin:$PATH"
touch "$work/data/pico8/pico8_dyn"
chmod +x "$work/data/pico8/pico8_dyn"
printf 'disconnected\n' > "$work/sys/class/drm/card0-HDMI-A-1/status"
: > "$work/sys/class/drm/card0-HDMI-A-1/modes"
sed -e "s|/run/|$work/run/|g" -e "s|/data/|$work/data/|g" \
    -e "s|/sys/|$work/sys/|g" -e "s|/var/log/|$work/log/|g" \
    -e 's|/dev/tty1|/dev/null|g' \
    -e "s|/etc/init.d/S99start-pico8|$work/service|g" \
    -e 's|/etc/init.d/S13console-font|/bin/true|g' \
    "$project_dir/br2-external/board/zero2w/overlay/etc/init.d/S99start-pico8" > "$work/service"
chmod +x "$work/service"
cat > "$work/bin/start-stop-daemon" <<'EOF'
#!/bin/sh
set -eu
action=$1
shift
pidfile=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -p) pidfile=$2; shift 2 ;;
        *) shift ;;
    esac
done
[ -n "$pidfile" ]
case "$action:$pidfile" in
    -S:*display-wait.pid)
        "$PICOOS_TEST_WORK/service" wait-display &
        echo "$!" > "$pidfile"
        ;;
    -S:*)
        echo start >> "$PICOOS_TEST_WORK/launches"
        sleep 60 &
        echo "$!" > "$pidfile"
        ;;
    -K:*) kill -TERM "$(cat "$pidfile")" ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$work/bin/start-stop-daemon"
# Wait without blocking init; stop must cancel it even before HDMI appears.
"$work/service" start
test -s "$work/run/pico8-display-wait.pid"
test ! -e "$work/launches"
"$work/service" stop
test ! -e "$work/run/pico8-display-wait.pid"
printf 'connected\n' > "$work/sys/class/drm/card0-HDMI-A-1/status"
printf '1920x1080\n' > "$work/sys/class/drm/card0-HDMI-A-1/modes"
sleep 1.2
test ! -e "$work/launches"
# With HDMI still disconnected, a later transition must launch exactly once.
printf 'disconnected\n' > "$work/sys/class/drm/card0-HDMI-A-1/status"
"$work/service" start
printf 'connected\n' > "$work/sys/class/drm/card0-HDMI-A-1/status"
for attempt in 1 2 3 4 5 6; do
    [ -f "$work/run/pico8.pid" ] &&
        [ ! -f "$work/run/pico8-display-wait.pid" ] && break
    sleep 0.5
done
test -s "$work/run/pico8.pid"
test ! -f "$work/run/pico8-display-wait.pid"
test "$(wc -l < "$work/launches")" -eq 1
# No persistent watcher restarts an exited game or responds to later toggles.
pid=$(cat "$work/run/pico8.pid")
kill "$pid"
rm "$work/run/pico8.pid"
printf 'disconnected\n' > "$work/sys/class/drm/card0-HDMI-A-1/status"
sleep 0.5
printf 'connected\n' > "$work/sys/class/drm/card0-HDMI-A-1/status"
sleep 1.2
test "$(wc -l < "$work/launches")" -eq 1
echo "Display wait integration passed: deferred one-shot launch, cancellation and no respawn."
