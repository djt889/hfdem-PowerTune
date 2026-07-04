#!/system/bin/sh
# Boost/Deboost 温控开关（手动）
# 手动切换会覆盖自动控制，直到下次Scene切换模式
# [#2] source utils.sh 复用公共函数

MODDIR=${0%/*}
source "$MODDIR/utils.sh"

BOOST="/dev/hfdem_boost"
MANUAL="/dev/hfdem_manual_boost"
LOG="$MODDIR/boost.log"
PROP="$MODDIR/module.prop"

_get_ver() { grep "^version=" "$PROP" 2>/dev/null | cut -d= -f2; }
_status() {
    local ver=$(_get_ver)
    sed -i "s/^description=.*/description=hfdem PowerTune $ver | 温控: $1 | 手动 | $2/" "$PROP" 2>/dev/null
}

_boost_on() {
    [ -f "$BOOST" ] && return
    for i in /sys/class/thermal/t*; do
        grep -Eq "cpu|gpu" "$i/type" 2>/dev/null && write_val "105000" "$i/trip_point_2_temp"
    done
    write_val "10" /sys/class/thermal/thermal_message/sconfig

    local BUS_DIR="/sys/devices/system/cpu/bus_dcvs"
    [ -d "$BUS_DIR/DDRQOS" ] && {
        lock_val "1" "$BUS_DIR/DDRQOS/hw_max_freq"
        lock_val "1" "$BUS_DIR/DDRQOS/boost_freq"
        lock_val "1" "$BUS_DIR/DDRQOS/hw_min_freq"
    }

    for df in /sys/class/devfreq/*kgsl-3d0; do
        [ -d "$df" ] && [ -f "$df/mod_percent" ] && write_val "120" "$df/mod_percent"
    done
    for df in /sys/class/devfreq/*ufs*; do
        [ -d "$df" ] && {
            [ -f "$df/max_freq" ] && write_val "2147483646" "$df/max_freq"
            [ -f "$df/min_freq" ] && write_val "2147483646" "$df/min_freq"
        }
    done

    touch "$BOOST"
    echo "on" > "$MANUAL"
    local t=$(_get_time)
    echo "[$t] Boost ON (手动)" >> "$LOG"
    rotate_log "$LOG"
    _status "🟢 ON" "$t"
}

_boost_off() {
    [ -f "$BOOST" ] || return
    for i in /sys/class/thermal/t*; do
        grep -Eq "cpu|gpu" "$i/type" 2>/dev/null && write_val "100000" "$i/trip_point_2_temp"
    done
    write_val "0" /sys/class/thermal/thermal_message/sconfig

    local BUS_DIR="/sys/devices/system/cpu/bus_dcvs"
    [ -d "$BUS_DIR/DDRQOS" ] && write_val "0" "$BUS_DIR/DDRQOS/min_freq"

    for df in /sys/class/devfreq/*kgsl-3d0; do
        [ -d "$df" ] && [ -f "$df/mod_percent" ] && write_val "100" "$df/mod_percent"
    done
    for df in /sys/class/devfreq/*ufs*; do
        [ -d "$df" ] && [ -f "$df/min_freq" ] && write_val "0" "$df/min_freq"
    done

    rm -f "$BOOST"
    echo "off" > "$MANUAL"
    local t=$(_get_time)
    echo "[$t] Boost OFF (手动)" >> "$LOG"
    rotate_log "$LOG"
    _status "🔴 OFF" "$t"
}

if [ -f "$BOOST" ]; then
    _boost_off
else
    _boost_on
fi
