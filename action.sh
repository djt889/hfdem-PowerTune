#!/system/bin/sh
# Boost/Deboost 温控开关（手动）
# 手动切换会覆盖自动控制，直到下次Scene切换模式

MODDIR=${0%/*}
BOOST="/dev/hfdem_boost"
MANUAL="/dev/hfdem_manual_boost"
LOG="$MODDIR/boost.log"
PROP="$MODDIR/module.prop"

_get_time() { date "+%Y-%m-%d %H:%M:%S"; }
_wval() { chmod 0644 "$2" 2>/dev/null; echo "$1" > "$2" 2>/dev/null; }
_get_ver() { grep "^version=" "$PROP" 2>/dev/null | cut -d= -f2; }
_status() {
    local ver=$(_get_ver)
    sed -i "s/^description=.*/description=hfdem PowerTune $ver | 温控: $1 | 手动 | $2/" "$PROP" 2>/dev/null
}

_boost_on() {
    [ -f "$BOOST" ] && return
    for i in /sys/class/thermal/t*; do
        grep -Eq "cpu|gpu" "$i/type" 2>/dev/null && _wval "105000" "$i/trip_point_2_temp"
    done
    _wval "10" /sys/class/thermal/thermal_message/sconfig
    touch "$BOOST"
    echo "on" > "$MANUAL"
    local t=$(_get_time)
    echo "[$t] Boost ON (手动)" >> "$LOG"
    _status "🟢 ON" "$t"
}

_boost_off() {
    [ -f "$BOOST" ] || return
    for i in /sys/class/thermal/t*; do
        grep -Eq "cpu|gpu" "$i/type" 2>/dev/null && _wval "100000" "$i/trip_point_2_temp"
    done
    _wval "0" /sys/class/thermal/thermal_message/sconfig
    rm -f "$BOOST"
    echo "off" > "$MANUAL"
    local t=$(_get_time)
    echo "[$t] Boost OFF (手动)" >> "$LOG"
    _status "🔴 OFF" "$t"
}

if [ -f "$BOOST" ]; then
    _boost_off
else
    _boost_on
fi
