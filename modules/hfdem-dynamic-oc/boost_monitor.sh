#!/system/bin/sh
SCENE=/data/cur_powermode.txt
CTS=/data/media/0/Android/CTS/mode.txt

is_event() { case "$1" in w|c|y|D|d|update) return 0;; *) return 1;; esac; }

if is_event "$1"; then
    MODDIR="${0%/*}"; [ "$MODDIR" = . ] && MODDIR=/data/adb/modules/hfdem_dynamic_oc
    . "$MODDIR/utils.sh"
    LAST_EVENT_TIME_FILE=/dev/hfdem_dynamic_oc_last_event_time
    now="$(date +%s 2>/dev/null || echo 0)"; last="$(cat "$LAST_EVENT_TIME_FILE" 2>/dev/null || echo 0)"
    if [ "$1" != update ] && [ "$now" -gt 0 ] && [ "$last" -gt 0 ] && [ $((now-last)) -lt 1 ]; then exit 0; fi
    echo "$now" > "$LAST_EVENT_TIME_FILE"
    scene_mode="$(cat "$SCENE" 2>/dev/null)"; cts_mode="$(cat "$CTS" 2>/dev/null)"
    scene_time="$(stat -c%Y "$SCENE" 2>/dev/null || echo 0)"; cts_time="$(stat -c%Y "$CTS" 2>/dev/null || echo 0)"
    if [ "$2" = "$CTS" ] && [ -n "$(normalize_mode "$cts_mode")" ]; then raw="$cts_mode"
    elif [ "$cts_time" -gt "$scene_time" ] 2>/dev/null && [ -n "$(normalize_mode "$cts_mode")" ]; then raw="$cts_mode"
    else raw="$scene_mode"; fi
    mode="$(normalize_mode "$raw")"; old="$(cat "$LAST_STATE_FILE" 2>/dev/null)"
    if [ -n "$mode" ] && { [ "$mode" != "$old" ] || [ "$1" = update ]; }; then
        rm -f "$MANUAL"
        apply_mode "$mode"
    fi
    exit 0
fi

MODDIR="${1:-/data/adb/modules/hfdem_dynamic_oc}"
. "$MODDIR/utils.sh"
CONF="$MODDIR/dynamic_oc.conf"; THERMAL_GUARD_TEMP=95000; THERMAL_RECOVER_TEMP=85000
[ -f "$CONF" ] && . "$CONF"
mkdir -p /data/media/0/Android/CTS 2>/dev/null
[ -f "$SCENE" ] || touch "$SCENE"
[ -f "$CTS" ] || touch "$CTS"
rm -f "$LAST_STATE_FILE"
"$0" update "$SCENE"

read_gpu_temp() {
    best=0
    for node in /sys/class/kgsl/kgsl-3d0/temp /sys/class/thermal/thermal_zone*/temp; do
        [ -f "$node" ] || continue
        if [ "$node" != /sys/class/kgsl/kgsl-3d0/temp ]; then
            zone="${node%/temp}"; grep -Eqi 'gpu|soc' "$zone/type" 2>/dev/null || continue
        fi
        val="$(cat "$node" 2>/dev/null)"; [ "$val" -gt "$best" ] 2>/dev/null && best="$val"
    done
    echo "$best"
}

thermal_guard() {
    guard=/dev/hfdem_dynamic_oc_thermal_guard
    while true; do
        sleep 30; temp="$(read_gpu_temp)"
        if [ "$temp" -ge "$THERMAL_GUARD_TEMP" ] 2>/dev/null && [ ! -f "$guard" ]; then
            touch "$guard"; boost_off; set_cpu_freq_pct 80; log_msg "Thermal guard ON temp=$temp"
        elif [ "$temp" -le "$THERMAL_RECOVER_TEMP" ] 2>/dev/null && [ -f "$guard" ]; then
            rm -f "$guard"; mode="$(cat "$LAST_STATE_FILE" 2>/dev/null)"; [ -n "$mode" ] && apply_mode "$mode"
            log_msg "Thermal guard OFF temp=$temp"
        fi
    done
}
thermal_guard & GUARD_PID=$!
trap 'kill "$GUARD_PID" 2>/dev/null' EXIT INT TERM

while true; do
    inotifyd "$0" "$SCENE":wcD "$CTS":wcD
    # 原子替换会令监听 inode 失效；短重试后重建缺失文件并重新应用最新状态。
    retry=0
    while { [ ! -f "$SCENE" ] || [ ! -f "$CTS" ]; } && [ "$retry" -lt 20 ]; do sleep 0.2; retry=$((retry+1)); done
    [ -f "$SCENE" ] || touch "$SCENE"
    [ -f "$CTS" ] || touch "$CTS"
    "$0" update "$SCENE"
done
