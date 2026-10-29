#!/bin/sh
set -eu

seconds=${1:-10}
case "$seconds" in
    ''|*[!0-9]*) echo "Usage: $0 [sample-seconds: 1..60]" >&2; exit 1 ;;
esac
[ "$seconds" -ge 1 ] && [ "$seconds" -le 60 ] ||
    { echo "Sample duration must be 1..60 seconds." >&2; exit 1; }
echo "PicoOS software timing baseline (not physical input-to-photon latency)"
printf 'uptime_seconds='
awk '{print $1}' /proc/uptime
if [ -r /run/pico8-start-timing ]; then
    cat /run/pico8-start-timing
    echo "Startup verification includes the service's one-second health-check delay, not first-frame timing."
else
    echo "startup_timing=unavailable (start with the updated service first)"
fi
if [ -r /sys/class/graphics/fb0/virtual_size ]; then
    printf 'framebuffer_size='
    cat /sys/class/graphics/fb0/virtual_size
fi
if [ -r /sys/class/thermal/thermal_zone0/temp ]; then
    awk '{printf "cpu_temperature_c=%.1f\n", $1/1000}' /sys/class/thermal/thermal_zone0/temp
fi
[ -r /run/pico8.pid ] || { echo "PICO-8 is not running." >&2; exit 1; }
pid=$(cat /run/pico8.pid)
case "$pid" in
    ''|*[!0-9]*|0|1) echo "Invalid PICO-8 PID." >&2; exit 1 ;;
esac
kill -0 "$pid" || { echo "PICO-8 PID is stale." >&2; exit 1; }
printf 'pico8_pid=%s\n' "$pid"
tr '\000' '\n' < "/proc/$pid/environ" |
    grep -E '^(SDL_RENDER_VSYNC|SDL_RENDER_SCALE_QUALITY|SDL_VIDEODRIVER|SDL_AUDIODRIVER)='
params=/proc/asound/card0/pcm0p/sub0/hw_params
if [ -r "$params" ]; then
    cat "$params"
    awk '/^rate:/ {rate=$2} /^period_size:/ {period=$2} /^buffer_size:/ {buffer=$2}
        END {if (rate && period && buffer)
            printf "alsa_hardware_period_ms=%.2f\nalsa_hardware_buffer_ms=%.2f\n",
                1000*period/rate, 1000*buffer/rate}' "$params"
    echo "ALSA buffer duration is capacity, not measured end-to-end audio latency."
fi
if [ ! -r "/proc/$pid/schedstat" ]; then
    echo "scheduler_timing=unavailable (kernel schedstat not exposed)"
    exit 0
fi
read -r cpu_before wait_before slices_before < "/proc/$pid/schedstat"
read -r uptime_before idle < /proc/uptime
sleep "$seconds"
read -r cpu_after wait_after slices_after < "/proc/$pid/schedstat"
read -r uptime_after idle < /proc/uptime
awk -v cpu0="$cpu_before" -v cpu1="$cpu_after" \
    -v wait0="$wait_before" -v wait1="$wait_after" \
    -v slices0="$slices_before" -v slices1="$slices_after" \
    -v t0="$uptime_before" -v t1="$uptime_after" 'BEGIN {
        duration=t1-t0;
        if (duration <= 0 || cpu1 < cpu0 || wait1 < wait0 || slices1 < slices0) {
            print "Invalid scheduler sample." > "/dev/stderr"; exit 1
        }
        printf "sample_seconds=%.2f\nmain_thread_cpu_percent=%.2f\nmain_thread_runqueue_wait_ms=%.3f\nmain_thread_timeslices=%.0f\n",
            duration, (cpu1-cpu0)/1e7/duration, (wait1-wait0)/1e6, slices1-slices0
    }'
echo "Scheduler counters cover the main thread only; runqueue wait is not controller/display latency."
echo "A 60 Hz output has a nominal 16.67 ms refresh interval; physical latency needs external measurement."
