#!/system/bin/sh
# 温控Boost + GPU动态调频监听 — 双文件监听（Scene + CTS）
# [#1] 补充 y 事件码
# [#7] source utils.sh 复用公共函数，去重代码
# [#6] 加 rotate_log 日志轮转
# [#B] 事件条件拆分：先判断 $1 是合法事件码/内部命令，再看 $2 文件路径

# ============================================================
# 1. inotifyd 事件响应区
# ============================================================
# [#B] 先判断 $1 是否为合法事件码或内部命令
# 旧代码把 $2 文件路径判断也放进 || 条件，
# 导致 $1 不是事件码但 $2 恰好匹配时也误进事件区
_is_event() {
    case "$1" in
        w|c|y|D|d|update) return 0 ;;
        *) return 1 ;;
    esac
}

if _is_event "$1"; then
    # 对于 "update" 内部命令，需匹配指定文件才处理
    if [ "$1" = "update" ] && \
       [ "$2" != "/data/cur_powermode.txt" ] && \
       [ "$2" != "/data/media/0/Android/CTS/mode.txt" ]; then
        exit 0
    fi

    # [#5.3b] MDIR fallback（inotifyd 子进程不继承 export 变量）
    if [ -z "$MDIR" ]; then
        MDIR="${0%/*}"
        [ "$MDIR" = "." ] && MDIR="/data/adb/modules/hfdem_savemode"
    fi

    BOOST="/dev/hfdem_boost"
    MANUAL="/dev/hfdem_manual_boost"
    LOG="$MDIR/boost.log"
    PROP="$MDIR/module.prop"
    LAST_STATE_FILE="/dev/hfdem_last_mode"

    # source utils.sh（事件区内也需要公共函数）
    MODDIR="$MDIR"
    source "$MODDIR/utils.sh"

    _get_ver() { grep "^version=" "$PROP" 2>/dev/null | cut -d= -f2; }
    _status() {
        local ver=$(_get_ver)
        sed -i "s/^description=.*/description=hfdem PowerTune $ver | GPU: $1 | 温控: $2 | $3/" "$PROP" 2>/dev/null
    }

    _set_gpu_governor() {
        local mod_pct="$1"
        for df in /sys/class/devfreq/*kgsl-3d0; do
            [ -d "$df" ] && lock_val "$mod_pct" "$df/mod_percent"
        done
    }

    _set_mode() {
        local mode="$1"
        local gpu_label=""
        local thermal_label=""
        local KGSL="/sys/class/kgsl/kgsl-3d0"

        case "$mode" in
            powersave|balance)
                _set_gpu_governor "100"
                gpu_label="调频100%"

                lock_val "0" "$KGSL/force_clk_on"
                lock_val "0" "$KGSL/force_no_nap"
                lock_val "0" "$KGSL/force_rail_on"
                write_val "1" "$KGSL/thermal_pwrlevel"
                lock_val "1" "$KGSL/bcl"
                gpu_boost_off

                case "$mode" in
                    powersave)  set_cpu_freq_pct 70  ;;
                    balance)    set_cpu_freq_pct 85  ;;
                esac

                if [ ! -f "$MANUAL" ]; then
                    [ -f "$BOOST" ] && boost_off
                    thermal_label="🔴 OFF"
                else
                    [ -f "$BOOST" ] && thermal_label="🟢 ON(手动)" || thermal_label="🔴 OFF(手动)"
                fi
                ;;
            performance|fast)
                _set_gpu_governor "120"
                gpu_label="调频120%"

                lock_val "0" "$KGSL/thermal_pwrlevel"
                lock_val "0" "$KGSL/force_rail_on"
                lock_val "0" "$KGSL/force_clk_on"
                lock_val "0" "$KGSL/force_no_nap"
                lock_val "0" "$KGSL/bcl"

                case "$mode" in
                    performance)  set_cpu_freq_pct 95; gpu_boost_perf ;;
                    fast)         set_cpu_freq_pct 100; gpu_boost_on ;;
                esac

                if [ ! -f "$MANUAL" ]; then
                    [ "$mode" = "fast" ] && { [ -f "$BOOST" ] || boost_on; thermal_label="🟢 ON"; }
                    [ "$mode" = "performance" ] && { [ -f "$BOOST" ] && boost_off; thermal_label="🔴 OFF"; }
                else
                    [ -f "$BOOST" ] && thermal_label="🟢 ON(手动)" || thermal_label="🔴 OFF(手动)"
                fi
                ;;
        esac

        local t=$(_get_time)
        echo "[$t] Mode: $mode | GPU: $gpu_label" >> "$LOG"
        rotate_log "$LOG"
        _status "$gpu_label" "$thermal_label" "$t"
    }

    # ---- 确定当前生效模式 ----
    CUR=""
    SCENE_MODE="$(cat /data/cur_powermode.txt 2>/dev/null)"
    CTS_MODE="$(cat /data/media/0/Android/CTS/mode.txt 2>/dev/null)"

    SCENE_MTIME="$(stat -c%Y /data/cur_powermode.txt 2>/dev/null || echo 0)"
    CTS_MTIME="$(stat -c%Y /data/media/0/Android/CTS/mode.txt 2>/dev/null || echo 0)"

    if [ "$2" = "/data/media/0/Android/CTS/mode.txt" ]; then
        CUR="$CTS_MODE"
    else
        if [ "$CTS_MTIME" -gt "$SCENE_MTIME" ] 2>/dev/null; then
            CUR="$CTS_MODE"
        else
            CUR="$SCENE_MODE"
        fi
    fi

    CUR="$(normalize_mode "$CUR")"
    LAST="$(cat "$LAST_STATE_FILE" 2>/dev/null)"

    if [ -n "$CUR" ] && [ "$CUR" != "$LAST" ]; then
        rm -f "$MANUAL"
        echo "$CUR" > "$LAST_STATE_FILE"
        _set_mode "$CUR"
    fi
    exit 0
fi

# ============================================================
# 2. 守护进程主入口
# ============================================================
if [ -n "$1" ] && [ -d "$1" ]; then
    export MDIR="$1"
else
    export MDIR="/data/adb/modules/hfdem_savemode"
fi

# [#7] source utils.sh
MODDIR="$MDIR"
source "$MODDIR/utils.sh"

CONF="$MDIR/gpu_boost.conf"
LAST_STATE_FILE="/dev/hfdem_last_mode"
LOG="$MDIR/boost.log"
KGSL="/sys/class/kgsl/kgsl-3d0"

GPU_BOOST_ENABLED=0
[ -f "$CONF" ] && . "$CONF"
[ "$GPU_BOOST_ENABLED" != "1" ] && exit 0

_set_gpu_unlock() {
    NUM_PWRLVL="$(cat $KGSL/num_pwrlevels 2>/dev/null)"
    lock_val "0" "$KGSL/max_pwrlevel"
    lock_val "0" "$KGSL/thermal_pwrlevel"
    lock_val "0" "$KGSL/throttling"
    [ -f "$KGSL/force_clk_on" ] && lock_val "0" "$KGSL/force_clk_on"
    [ -f "$KGSL/force_no_nap" ] && lock_val "0" "$KGSL/force_no_nap"
    [ -f "$KGSL/force_rail_on" ] && lock_val "0" "$KGSL/force_rail_on"
    [ -f "$KGSL/bcl" ] && lock_val "0" "$KGSL/bcl"
    [ -f "$KGSL/max_gpu_clk" ] && lock_val "2147483647" "$KGSL/max_gpu_clk"
    [ -f "$KGSL/max_clock_mhz" ] && lock_val "2147483647" "$KGSL/max_clock_mhz"
    [ -f "$KGSL/min_clock_mhz" ] && lock_val "0" "$KGSL/min_clock_mhz"
    [ -f /sys/kernel/gpu/gpu_max_clock ] && lock_val "2147483647" /sys/kernel/gpu/gpu_max_clock
    [ -f /sys/kernel/gpu/gpu_min_clock ] && lock_val "0" /sys/kernel/gpu/gpu_min_clock

    GPU_MAX_FREQ="2147483647"
    for df in /sys/class/devfreq/*kgsl-3d0 /sys/class/kgsl/kgsl-3d0/devfreq; do
        [ -d "$df" ] || continue
        avail="$(cat "$df/available_frequencies" 2>/dev/null)"
        [ -n "$avail" ] && {
            dyn_max=$(echo "$avail" | tr ' ' '\n' | sort -n | tail -1)
            [ -n "$dyn_max" ] && GPU_MAX_FREQ="$dyn_max"
        }
        lock_val "0" "$df/min_freq"
        lock_val "$GPU_MAX_FREQ" "$df/max_freq"
    done
}

while [ "$(getprop sys.boot_completed)" != "1" ]; do sleep 3; done
sleep 5

_set_gpu_unlock

[ ! -f /data/cur_powermode.txt ] && touch /data/cur_powermode.txt
mkdir -p /data/media/0/Android/CTS 2>/dev/null
[ ! -f /data/media/0/Android/CTS/mode.txt ] && touch /data/media/0/Android/CTS/mode.txt

# 启动时应用当前模式
CUR_SCENE="$(cat /data/cur_powermode.txt 2>/dev/null)"
CUR_CTS="$(cat /data/media/0/Android/CTS/mode.txt 2>/dev/null)"
INIT_MODE=""
SCENE_MTIME="$(stat -c%Y /data/cur_powermode.txt 2>/dev/null || echo 0)"
CTS_MTIME="$(stat -c%Y /data/media/0/Android/CTS/mode.txt 2>/dev/null || echo 0)"
if [ "$CTS_MTIME" -gt "$SCENE_MTIME" ] 2>/dev/null && [ -n "$CUR_CTS" ]; then
    INIT_MODE="$CUR_CTS"
elif [ -n "$CUR_SCENE" ]; then
    INIT_MODE="$CUR_SCENE"
fi
INIT_MODE="$(normalize_mode "$INIT_MODE")"
if [ -n "$INIT_MODE" ]; then
    echo "$INIT_MODE" > "$LAST_STATE_FILE"
    "$0" "update" "/data/cur_powermode.txt"
fi

# ============================================================
# 3. 核心监听循环（双文件 inotifyd，底层真实路径）
# ============================================================
while true; do
    inotifyd "$0" \
        /data/cur_powermode.txt:wcD \
        /data/media/0/Android/CTS/mode.txt:wcD

    # inotifyd 退出 → 原子替换，重试
    sleep 0.5

    if [ ! -f /data/cur_powermode.txt ]; then
        touch /data/cur_powermode.txt
    else
        "$0" "update" "/data/cur_powermode.txt"
    fi

    if [ ! -f /data/media/0/Android/CTS/mode.txt ]; then
        touch /data/media/0/Android/CTS/mode.txt
    else
        "$0" "update" "/data/media/0/Android/CTS/mode.txt"
    fi

    rotate_log "$LOG"
done
