#!/system/bin/sh
MODDIR=${0%/*}

# 公共工具函数（供 service.sh / boost_monitor.sh / action.sh source）

write_val() {
    if [ -f "$2" ]; then
        chmod 0644 "$2" 2>/dev/null
        echo "$1" > "$2" 2>/dev/null
    else
        find $2 -type f 2>/dev/null | while read -r file; do
            chmod 0644 "$file" 2>/dev/null
            echo "$1" > "$file" 2>/dev/null
        done
    fi
}

lock_val() {
    if [ -f "$2" ]; then
        chmod 0644 "$2" 2>/dev/null
        echo "$1" > "$2" 2>/dev/null
        chmod 0444 "$2" 2>/dev/null
    else
        find $2 -type f 2>/dev/null | while read -r file; do
            chmod 0644 "$file" 2>/dev/null
            echo "$1" > "$file" 2>/dev/null
            chmod 0444 "$file" 2>/dev/null
        done
    fi
}

lock_val_in_path() {
    if [ "$#" = "4" ]; then
        find "$2/" -path "*$3*" -name "$4" -type f 2>/dev/null | while read -r file; do
            lock_val "$1" "$file"
        done
    else
        find "$2/" -name "$3" -type f 2>/dev/null | while read -r file; do
            lock_val "$1" "$file"
        done
    fi
}

write_val_in_path() {
    if [ "$#" = "4" ]; then
        find "$2/" -path "*$3*" -name "$4" -type f 2>/dev/null | while read -r file; do
            write_val "$1" "$file"
        done
    else
        find "$2/" -name "$3" -type f 2>/dev/null | while read -r file; do
            write_val "$1" "$file"
        done
    fi
}

# [#7] mask_val: bind mount 防覆盖（参考 Yuni）
# 写入后 mount --bind 一个只读文件覆盖原路径，系统回写也无法改变值
# 比 lock_val (chmod 0444) 更可靠，某些内核 sysfs 不支持 chmod 降权
mask_val() {
    local val="$1"
    local path="$2"
    find $path -type f 2>/dev/null | while read -r file; do
        file="$(realpath "$file")"
        umount "$file" 2>/dev/null
        chown root:root "$file" 2>/dev/null
        chmod 0644 "$file" 2>/dev/null
        echo "$val" > "$file" 2>/dev/null
        chmod 0444 "$file" 2>/dev/null

        local TIME="$(date "+%s%N" 2>/dev/null || echo "$$")"
        local mask_file="/dev/mount_masks/mount_mask_$TIME"
        echo "$val" > "$mask_file" 2>/dev/null
        mount --bind "$mask_file" "$file" 2>/dev/null
        restorecon -R -F "$file" >/dev/null 2>&1
    done
}

mask_val_in_path() {
    if [ "$#" = "4" ]; then
        find "$2/" -path "*$3*" -name "$4" -type f 2>/dev/null | while read -r file; do
            mask_val "$1" "$file"
        done
    else
        find "$2/" -name "$3" -type f 2>/dev/null | while read -r file; do
            mask_val "$1" "$file"
        done
    fi
}

get_max_available_freq() {
    local dir="$1"
    [ -d "$dir" ] || return
    local max_file=$(find "$dir" -maxdepth 1 -name "available_frequencies" -o -name "freq_table" 2>/dev/null | head -n1)
    if [ -f "$max_file" ]; then
        local max=$(tr ' ' '\n' < "$max_file" | sort -n | tail -n1)
        [ -n "$max" ] && echo "$max"
    fi
}

set_cpu_freq_pct() {
    local pct="$1"
    for policy in /sys/devices/system/cpu/cpufreq/policy*; do
        [ -d "$policy" ] || continue
        local hw_max=$(cat "$policy/cpuinfo_max_freq" 2>/dev/null)
        [ -z "$hw_max" ] && continue
        local target=$((hw_max * pct / 100))
        chmod 0644 "$policy/scaling_max_freq" 2>/dev/null
        echo "$target" > "$policy/scaling_max_freq" 2>/dev/null
    done
}

rotate_log() {
    local logf="$1"
    local max_bytes="${2:-1048576}"
    [ -f "$logf" ] || return
    local size
    size=$(stat -c%s "$logf" 2>/dev/null || echo 0)
    [ "$size" -gt "$max_bytes" ] && mv "$logf" "${logf}.old"
}

normalize_mode() {
    case "$1" in
        powersave|power_save|0|省电)       echo "powersave" ;;
        balance|balanced|1|均衡|default)     echo "balance" ;;
        performance|perf|2|性能|sport)      echo "performance" ;;
        fast|turbo|gaming|3|极速|极限)      echo "fast" ;;
        *)                                  echo "" ;;
    esac
}

_get_time() { date "+%Y-%m-%d %H:%M:%S"; }

wait_until_boot_complete() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 3
    done
    sleep 5
}

wait_until_login() {
    while [ "$(getprop sys.boot_completed)" != "1" ]; do
        sleep 3
    done
    local i=0
    while [ ! -d /data/data/android ] && [ $i -lt 30 ]; do
        sleep 3
        i=$((i + 1))
    done
}

# 公共 Boost 逻辑（boost_monitor.sh 和 action.sh 共用）
boost_on() {
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

    for df in /sys/class/devfreq/*ufs*; do
        [ -d "$df" ] && {
            [ -f "$df/max_freq" ] && write_val "2147483646" "$df/max_freq"
            [ -f "$df/min_freq" ] && write_val "2147483646" "$df/min_freq"
        }
    done

    touch "$BOOST"
    local t=$(_get_time)
    echo "[$t] Boost ON" >> "$LOG"
    rotate_log "$LOG"
}

boost_off() {
    [ -f "$BOOST" ] || return
    for i in /sys/class/thermal/t*; do
        grep -Eq "cpu|gpu" "$i/type" 2>/dev/null && write_val "100000" "$i/trip_point_2_temp"
    done
    write_val "0" /sys/class/thermal/thermal_message/sconfig

    local BUS_DIR="/sys/devices/system/cpu/bus_dcvs"
    [ -d "$BUS_DIR/DDRQOS" ] && write_val "0" "$BUS_DIR/DDRQOS/min_freq"

    for df in /sys/class/devfreq/*ufs*; do
        [ -d "$df" ] && [ -f "$df/min_freq" ] && write_val "0" "$df/min_freq"
    done

    rm -f "$BOOST"
    local t=$(_get_time)
    echo "[$t] Boost OFF" >> "$LOG"
    rotate_log "$LOG"
}
