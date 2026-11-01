#!/bin/bash
set -euo pipefail
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work"/{proc/4242,proc/asound/card0/pcm0p/sub0,run,bin,sys}
printf '4242\n' > "$work/run/pico8.pid"
printf '100.0 200.0\n' > "$work/proc/uptime"
printf '1000000000 2000000 10\n' > "$work/proc/4242/schedstat"
printf 'SDL_RENDER_VSYNC=1\0SDL_RENDER_SCALE_QUALITY=0\0SDL_AUDIODRIVER=alsa\0SDL_VIDEODRIVER=kmsdrm\0' \
    > "$work/proc/4242/environ"
printf 'rate: 44100 (44100/1)\nperiod_size: 2048\nbuffer_size: 4096\n' \
    > "$work/proc/asound/card0/pcm0p/sub0/hw_params"
cat > "$work/bin/sleep" <<EOF
#!/bin/sh
printf '102.0 200.0\\n' > '$work/proc/uptime'
printf '1500000000 5000000 30\\n' > '$work/proc/4242/schedstat'
EOF
chmod +x "$work/bin/sleep"
{
    printf 'kill() { test "$1" = -0 && test "$2" = 4242; }\n'
    sed -e "s|/proc/|$work/proc/|g" -e "s|/run/|$work/run/|g" \
        -e "s|/sys/|$work/sys/|g" "$project_dir/scripts/measure-pico8.sh"
} > "$work/measure"
PATH="$work/bin:$PATH" sh "$work/measure" 2 > "$work/result"
for line in 'sample_seconds=2.00' 'main_thread_cpu_percent=25.00' \
    'main_thread_runqueue_wait_ms=3.000' 'main_thread_timeslices=20' \
    'alsa_hardware_period_ms=46.44' 'alsa_hardware_buffer_ms=92.88'; do
    grep -Fxq "$line" "$work/result"
done
for invalid in 0 61 bad; do
    if sh "$work/measure" "$invalid" > /dev/null 2>&1; then
        echo "Invalid measurement duration accepted: $invalid" >&2
        exit 1
    fi
done
echo "Performance baseline tests passed (CPU/wait deltas, ALSA durations and duration bounds)."
