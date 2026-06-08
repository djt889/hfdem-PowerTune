#!/system/bin/sh
# 温控Boost + GPU调频器监听 - inotifyd 零耗电 + 防原子替换版

# ==========================================
# 1. inotifyd 事件响应区
# 兼容: w(直接写入), c(修改), y(移动), update(原子替换后的重载)
# ==========================================
if [ "$1" = "w" ] || [ "$1" = "c" ] || [ "$1" = "y" ] || [ "$1" = "update" ] || [ "$2" = "/data/cur_powermode.txt" ]; then
    BOOST="/dev/hfdem_boost"
    MANUAL="/dev/hfdem_manual_boost"
    LOG="$MDIR/boost.log"
    PROP="$MDIR/module.prop"
    CONF="$MDIR/gpu_boost.conf"
    LAST_STATE_FILE="/dev/hfdem_last_mode"
    
    GPU_BOOST_ENABLED=0
    [ -f "$CONF" ] && . "$CONF"
    [ "$GPU_BOOST_ENABLED" != "1" ] && exit 0

    _get_time() { date "+%Y-%m-%d %H:%M:%S"; }
    _wval() { chmod 0644 "$2" 2>/dev/null; echo "$1" > "$2" 2>/dev/null; }
    _lock_val() { chmod 0644 "$2" 2>/dev/null; echo "$1" > "$2" 2>/dev/null; chmod 0444 "$2" 2>/dev/null; }
    _get_ver() { grep "^version=" "$PROP" 2>/dev/null | cut -d= -f2; }
    _status() {
        local ver=$(_get_ver)
        sed -i "s/^description=.*/description=hfdem PowerTune $ver | GPU: $1 | 温控: $2 | $3/" "$PROP" 2>/dev/null
    }
    
    _set_gpu_governor() {
        local mod_pct="$1"
        for df in /sys/class/devfreq/*kgsl-3d0; do
            [ -d "$df" ] && _lock_val "$mod_pct" "$df/mod_percent"
        done
    }

    _boost_on() {
        [ -f "$BOOST" ] && return
        for i in /sys/class/thermal/t*; do
            grep -Eq "cpu|gpu" "$i/type" 2>/dev/null && _wval "105000" "$i/trip_point_2_temp"
        done
        _wval "10" /sys/class/thermal/thermal_message/sconfig
        touch "$BOOST"
        local t=$(_get_time)
        echo "[$t] Boost ON" >> "$LOG"
    }

    _boost_off() {
        [ -f "$BOOST" ] || return
        for i in /sys/class/thermal/t*; do
            grep -Eq "cpu|gpu" "$i/type" 2>/dev/null && _wval "100000" "$i/trip_point_2_temp"
        done
        _wval "0" /sys/class/thermal/thermal_message/sconfig
        rm -f "$BOOST"
        local t=$(_get_time)
        echo "[$t] Boost OFF" >> "$LOG"
    }

    _set_mode() {
        local mode="$1"
        local gpu_label=""
        local thermal_label=""

        case "$mode" in
            powersave|balance)
                _set_gpu_governor "100"
                gpu_label="调频100%"
                if [ ! -f "$MANUAL" ]; then
                    [ -f "$BOOST" ] && _boost_off
                    thermal_label="🔴 OFF"
                else
                    [ -f "$BOOST" ] && thermal_label="🟢 ON(手动)" || thermal_label="🔴 OFF(手动)"
                fi
                ;;
            performance|fast)
                _set_gpu_governor "120"
                gpu_label="调频120%"
                if [ ! -f "$MANUAL" ]; then
                    [ "$mode" = "fast" ] && { [ -f "$BOOST" ] || _boost_on; thermal_label="🟢 ON"; }
                    [ "$mode" = "performance" ] && { [ -f "$BOOST" ] && _boost_off; thermal_label="🔴 OFF"; }
                else
                    [ -f "$BOOST" ] && thermal_label="🟢 ON(手动)" || thermal_label="🔴 OFF(手动)"
                fi
                ;;
        esac

        local t=$(_get_time)
        echo "[$t] Mode: $mode | GPU: $gpu_label" >> "$LOG"
        _status "$gpu_label" "$thermal_label" "$t"
    }

    # 执行状态更新逻辑
    CUR=$(cat /data/cur_powermode.txt 2>/dev/null)
    LAST=$(cat "$LAST_STATE_FILE" 2>/dev/null)
    
    if [ -n "$CUR" ] && [ "$CUR" != "$LAST" ]; then
        rm -f "$MANUAL"
        echo "$CUR" > "$LAST_STATE_FILE"
        _set_mode "$CUR"
    fi
    exit 0
fi

# ==========================================
# 2. 守护进程主入口
# ==========================================
if [ -n "$1" ] && [ -d "$1" ]; then
    export MDIR="$1"
else
    export MDIR="/data/adb/modules/hfdem" 
fi

CONF="$MDIR/gpu_boost.conf"
LAST_STATE_FILE="/dev/hfdem_last_mode"
KGSL="/sys/class/kgsl/kgsl-3d0"

GPU_BOOST_ENABLED=0
[ -f "$CONF" ] && . "$CONF"
[ "$GPU_BOOST_ENABLED" != "1" ] && exit 0

_wval() { chmod 0644 "$2" 2>/dev/null; echo "$1" > "$2" 2>/dev/null; }
_lock_val() { chmod 0644 "$2" 2>/dev/null; echo "$1" > "$2" 2>/dev/null; chmod 0444 "$2" 2>/dev/null; }

_set_gpu_unlock() {
    NUM_PWRLVL="$(cat $KGSL/num_pwrlevels 2>/dev/null)"
    MIN_PWRLVL="$((NUM_PWRLVL - 1))"
    _lock_val "0" "$KGSL/max_pwrlevel"
    _lock_val "$MIN_PWRLVL" "$KGSL/min_pwrlevel"
    _lock_val "$MIN_PWRLVL" "$KGSL/default_pwrlevel"
    _lock_val "0" "$KGSL/thermal_pwrlevel"
    _lock_val "0" "$KGSL/throttling"
    [ -f "$KGSL/force_clk_on" ] && _wval "0" "$KGSL/force_clk_on"
    [ -f "$KGSL/force_no_nap" ] && _wval "0" "$KGSL/force_no_nap"
    [ -f "$KGSL/force_rail_on" ] && _wval "0" "$KGSL/force_rail_on"
    [ -f "$KGSL/bcl" ] && _wval "0" "$KGSL/bcl"
    [ -f "$KGSL/max_gpu_clk" ] && _lock_val "2147483647" "$KGSL/max_gpu_clk"
    [ -f "$KGSL/max_clock_mhz" ] && _lock_val "2147483647" "$KGSL/max_clock_mhz"
    [ -f "$KGSL/min_clock_mhz" ] && _lock_val "0" "$KGSL/min_clock_mhz"
    [ -f /sys/kernel/gpu/gpu_max_clock ] && _lock_val "2147483647" /sys/kernel/gpu/gpu_max_clock
    [ -f /sys/kernel/gpu/gpu_min_clock ] && _lock_val "0" /sys/kernel/gpu/gpu_min_clock
    for df in /sys/class/devfreq/*kgsl-3d0; do
        [ -d "$df" ] && {
            _lock_val "0" "$df/min_freq"
            _lock_val "2147483647" "$df/max_freq"
        }
    done
}

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 5; done
sleep 5

_set_gpu_unlock

[ ! -f /data/cur_powermode.txt ] && touch /data/cur_powermode.txt

# ==========================================
# 3. 核心监听循环 (防原子替换机制)
# ==========================================
while true; do
    # 增加监听 'D' (Delete Self)。当发生原子替换时，原文件 inode 被销毁，触发此事件
    inotifyd "$0" /data/cur_powermode.txt:wcD
    
    # 运行到这里说明 inotifyd 退出了（大概率是遇到了原子替换 mv 操作）
    # 给文件系统 0.5 秒时间完成文件的替换写入
    sleep 0.5 
    
    if [ ! -f /data/cur_powermode.txt ]; then
        # 如果是真的被删了，建一个空文件，等待下次被写入
        touch /data/cur_powermode.txt
    else
        # 文件存在，说明是原子替换！
        # 我们主动伪造一个 "update" 事件传给本脚本的上半部分，立即应用新的模式
        "$0" "update" "/data/cur_powermode.txt"
    fi
    
    # 循环自动回到开头，inotifyd 此时会重新绑定到新文件的 inode 上！
done