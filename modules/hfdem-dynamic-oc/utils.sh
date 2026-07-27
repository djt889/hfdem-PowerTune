#!/system/bin/sh
MODDIR=${MODDIR:-${0%/*}}
STATE_PREFIX=/dev/hfdem_dynamic_oc
BOOST="${STATE_PREFIX}_boost"
MANUAL="${STATE_PREFIX}_manual_boost"
LAST_STATE_FILE="${STATE_PREFIX}_last_mode"
LOG="${MODDIR}/dynamic_oc.log"

write_val() {
    [ -f "$2" ] || return 0
    chmod 0644 "$2" 2>/dev/null
    echo "$1" > "$2" 2>/dev/null
}

unlock_val() {
    chmod 0644 "$1" 2>/dev/null
    chattr -i "$1" 2>/dev/null
}

rotate_log() {
    [ -f "$1" ] || return 0
    size="$(stat -c%s "$1" 2>/dev/null || echo 0)"
    [ "$size" -gt "${2:-524288}" ] 2>/dev/null && mv -f "$1" "$1.old"
}

log_msg() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"
    rotate_log "$LOG"
}

normalize_mode() {
    case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '\r\n ')" in
        powersave|power_save|0|省电) echo powersave ;;
        balance|balanced|1|均衡|default) echo balance ;;
        performance|perf|2|性能|sport) echo performance ;;
        fast|turbo|gaming|3|极速|极限) echo fast ;;
        *) echo "" ;;
    esac
}

freq_list() {
    table=""
    [ -f "$1/available_frequencies" ] && table="$1/available_frequencies"
    [ -z "$table" ] && [ -f "$1/freq_table" ] && table="$1/freq_table"
    [ -n "$table" ] || return 0
    tr ' ' '\n' < "$table" 2>/dev/null | grep '^[0-9][0-9]*$' | sort -n -u
}

freq_target_pct() {
    list="$(freq_list "$1")"; pct="$2"
    [ -n "$list" ] || return 0
    count="$(printf '%s\n' "$list" | wc -l | tr -d ' ')"
    index=$(( (count * pct + 99) / 100 ))
    [ "$index" -lt 1 ] && index=1
    [ "$index" -gt "$count" ] && index="$count"
    printf '%s\n' "$list" | sed -n "${index}p"
}

is_gpu_core_devfreq() {
    [ -d "$1" ] || return 1
    base="${1##*/}"
    driver="$(readlink "$1/device/driver" 2>/dev/null)"; driver="${driver##*/}"
    names="$(cat "$1/name" "$1/device/name" "$1/device/of_node/name" 2>/dev/null | tr '\n' ' ')"
    ident="$(printf '%s %s %s' "$base" "$driver" "$names" | tr '[:upper:]' '[:lower:]')"
    case "$ident" in *interconnect*|*memory*|*memlat*|*membw*|*gpu-bus*|*gpu_bus*|*bus-gpu*|*bus_gpu*|*icc*|*ddr*|*llcc*|*noc*) return 1;; esac
    case "$ident" in *mali*|*panfrost*|*gpu*|*kgsl-3d0*|*adreno*) return 0;; esac
    return 1
}

set_cpu_freq_pct() {
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$policy" ] || continue
        max="$(cat "$policy/cpuinfo_max_freq" 2>/dev/null)"
        [ -n "$max" ] && write_val "$((max * $1 / 100))" "$policy/scaling_max_freq"
    done
}

set_kgsl_mode() {
    mode="$1"; KGSL=/sys/class/kgsl/kgsl-3d0
    case "$mode" in powersave) pct=70; mod=90; thermal=1; bcl=1;; balance) pct=85; mod=100; thermal=1; bcl=1;; performance) pct=95; mod=110; thermal=0; bcl=0;; fast) pct=100; mod=120; thermal=0; bcl=0;; *) return;; esac
    [ -d "$KGSL" ] && {
        write_val 0 "$KGSL/max_pwrlevel"
        n="$(cat "$KGSL/num_pwrlevels" 2>/dev/null)"
        [ -n "$n" ] && write_val "$((n - 1))" "$KGSL/min_pwrlevel"
        unlock_val "$KGSL/thermal_pwrlevel"; write_val "$thermal" "$KGSL/thermal_pwrlevel"
        unlock_val "$KGSL/bcl"; write_val "$bcl" "$KGSL/bcl"
        write_val 0 "$KGSL/force_clk_on"; write_val 0 "$KGSL/force_no_nap"; write_val 0 "$KGSL/force_rail_on"
    }
    for df in /sys/class/devfreq/*kgsl-3d0 /sys/class/kgsl/kgsl-3d0/devfreq; do
        [ -d "$df" ] || continue
        min="$(freq_list "$df" | head -n1)"; max="$(freq_list "$df" | tail -n1)"
        [ -n "$min" ] && write_val "$min" "$df/min_freq"
        [ -n "$max" ] && write_val "$max" "$df/max_freq"
        write_val "$mod" "$df/mod_percent"
    done
    set_cpu_freq_pct "$pct"
}

set_mali_mode() {
    case "$1" in powersave) pct=50;; balance) pct=70;; performance) pct=90;; fast) pct=100;; *) return;; esac
    ged_target=""
    for df in /sys/class/devfreq/*; do
        is_gpu_core_devfreq "$df" || continue
        case "$df" in *kgsl-3d0*) continue;; esac
        min="$(freq_list "$df" | head -n1)"; target="$(freq_target_pct "$df" "$pct")"
        [ -n "$min" ] && [ -n "$target" ] || continue
        write_val "$min" "$df/min_freq"; write_val "$target" "$df/max_freq"
        [ -n "$ged_target" ] || ged_target="$target"
    done
    [ -n "$ged_target" ] && write_val "$ged_target" /sys/module/ged/parameters/gpu_cust_upbound_gpu_freq
}

set_bus_mode() {
    case "$1" in powersave) pct=50;; balance) pct=70;; performance) pct=90;; fast) pct=100;; *) return;; esac
    BUS=/sys/devices/system/cpu/bus_dcvs
    for df in "$BUS"/DDR "$BUS"/LLCC "$BUS"/L3; do
        [ -d "$df" ] || continue
        target="$(freq_target_pct "$df" "$pct")"
        [ -n "$target" ] || continue
        find "$df" -type f -name '*max_freq' 2>/dev/null | while read -r node; do write_val "$target" "$node"; done
        find "$df" -type f -name '*min_freq' 2>/dev/null | while read -r node; do write_val 0 "$node"; done
    done
    # UFS 是动态性能链的一部分：四模式限制上限，最低档仍允许空闲降频。
    for df in /sys/class/devfreq/*ufs*; do
        [ -d "$df" ] || continue
        min="$(freq_list "$df" | head -n1)"; target="$(freq_target_pct "$df" "$pct")"
        [ -n "$min" ] && write_val "$min" "$df/min_freq"
        [ -n "$target" ] && write_val "$target" "$df/max_freq"
    done
}

set_ged_mode() {
    case "$1" in powersave|balance) level=0;; performance|fast) level=1;; *) return;; esac
    # 仅写 GED GPU 动态调频/Boost 节点，不触碰通用 I/O、后台或内存策略。
    write_val "$level" /sys/module/ged/parameters/ged_boost_enable
    write_val 1 /sys/module/ged/parameters/gpu_dvfs_enable
}

boost_on() {
    [ -f "$BOOST" ] && return 0
    for zone in /sys/class/thermal/thermal_zone* /sys/class/thermal/t*; do
        [ -f "$zone/type" ] || continue
        grep -Eqi 'cpu|gpu|soc' "$zone/type" 2>/dev/null && write_val 105000 "$zone/trip_point_2_temp"
    done
    write_val 10 /sys/class/thermal/thermal_message/sconfig
    BUS=/sys/devices/system/cpu/bus_dcvs
    if [ -d "$BUS/DDRQOS" ]; then
        write_val 1 "$BUS/DDRQOS/hw_max_freq"
        write_val 1 "$BUS/DDRQOS/boost_freq"
        write_val 1 "$BUS/DDRQOS/hw_min_freq"
    fi
    for df in /sys/class/devfreq/*ufs*; do
        [ -d "$df" ] || continue
        max="$(freq_list "$df" | tail -n1)"
        [ -n "$max" ] && { write_val "$max" "$df/max_freq"; write_val "$max" "$df/min_freq"; }
    done
    touch "$BOOST"; log_msg 'Boost ON'
}

boost_off() {
    [ -f "$BOOST" ] || return 0
    for zone in /sys/class/thermal/thermal_zone* /sys/class/thermal/t*; do
        [ -f "$zone/type" ] || continue
        grep -Eqi 'cpu|gpu|soc' "$zone/type" 2>/dev/null && write_val 100000 "$zone/trip_point_2_temp"
    done
    write_val 0 /sys/class/thermal/thermal_message/sconfig
    BUS=/sys/devices/system/cpu/bus_dcvs
    write_val 0 "$BUS/DDRQOS/min_freq"
    for df in /sys/class/devfreq/*ufs*; do
        [ -d "$df" ] || continue
        min="$(freq_list "$df" | head -n1)"
        [ -n "$min" ] && write_val "$min" "$df/min_freq"
    done
    rm -f "$BOOST"; log_msg 'Boost OFF'
}

apply_mode() {
    mode="$(normalize_mode "$1")"; [ -n "$mode" ] || return 1
    set_kgsl_mode "$mode"; set_mali_mode "$mode"; set_ged_mode "$mode"; set_bus_mode "$mode"
    if [ ! -f "$MANUAL" ]; then [ "$mode" = fast ] && boost_on || boost_off; fi
    echo "$mode" > "$LAST_STATE_FILE"
    printf 'mode=%s\nboost=%s\nupdated=%s\n' "$mode" "$([ -f "$BOOST" ] && echo on || echo off)" "$(date +%s)" > "$MODDIR/status.conf.tmp"
    mv -f "$MODDIR/status.conf.tmp" "$MODDIR/status.conf"
    log_msg "Mode $mode applied"
}
