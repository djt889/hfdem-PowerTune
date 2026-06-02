#!/system/bin/sh
MODDIR=${0%/*}
source $MODDIR/utils.sh

USE_THP="$(awk 'NR==1{if (int($2/1024/1024) < 10) print false; else print true;}' /proc/meminfo)"

init_thp() {
    THP_PATH=/sys/kernel/mm/transparent_hugepage
    [ -d "$THP_PATH" ] || return
    write_val "always" $THP_PATH/enabled
    if [ "$USE_THP" = "false" ]; then
        write_val "madvise" $THP_PATH/enabled
    fi
    write_val "defer+madvise" $THP_PATH/defrag
    write_val "within_size" $THP_PATH/shmem_enabled
    write_val "0" $THP_PATH/use_zero_page
    write_val "1" $THP_PATH/khugepaged/defrag
    write_val "65536" $THP_PATH/khugepaged/pages_to_scan
    write_val "0" $THP_PATH/khugepaged/scan_sleep_millisecs
    write_val "100" $THP_PATH/khugepaged/alloc_sleep_millisecs
    write_val "8" $THP_PATH/khugepaged/max_ptes_none
    write_val "64" $THP_PATH/khugepaged/max_ptes_swap
    write_val "511" $THP_PATH/khugepaged/max_ptes_shared
    sleep 30
    local count=0
    while [ "$(cat $THP_PATH/khugepaged/full_scans 2>/dev/null)" -lt 10 ] && [ $count -lt 60 ]; do
        sleep 1
        count=$((count + 1))
    done
    write_val "6000" $THP_PATH/khugepaged/scan_sleep_millisecs
}

init_zram_per() {
    swapoff "/dev/block/zram$1" 2>/dev/null
    echo "1" > "/sys/class/block/zram$1/reset"
    echo "0" > "/sys/class/block/zram$1/mem_limit"
    echo "$2" > "/sys/class/block/zram$1/comp_algorithm"
    echo "$(awk 'NR==1{print $2*2048}' /proc/meminfo)" > "/sys/block/zram$1/disksize"
    mkswap "/dev/block/zram$1"
    /system/bin/swapon "/dev/block/zram$1"
}

init_zram() {
    init_zram_per "0" "zstd"
}

init_mem() {
    lmkd --reinit 2>/dev/null || reinit_lmkd
    write_val "20" /proc/sys/vm/compaction_proactiveness
    write_val "0" /proc/sys/vm/page-cluster
    write_val "150" /proc/sys/vm/watermark_scale_factor
    write_val "15000" /proc/sys/vm/watermark_boost_factor
    write_val "1" /proc/sys/vm/overcommit_memory
    write_val "60" /proc/sys/vm/swappiness
    write_val "65536" /proc/sys/vm/min_free_kbytes
    write_val "5" /proc/sys/vm/dirty_ratio
    write_val "2" /proc/sys/vm/dirty_background_ratio
    write_val "60" /proc/sys/vm/dirtytime_expire_seconds
    [ -f /sys/kernel/mm/lru_gen/enabled ] && write_val "0x0007" /sys/kernel/mm/lru_gen/enabled
    [ -f /sys/kernel/mm/lru_gen/min_ttl_ms ] && write_val "1000" /sys/kernel/mm/lru_gen/min_ttl_ms
    [ -f /sys/module/pandora_config/parameters/enable_mm_vhs ] && write_val "Y" /sys/module/pandora_config/parameters/enable_mm_vhs
    init_thp
}

reinit_lmkd() {
    local lmkd_restart_counter_path=/sys/module/lowmemorykiller/parameters/restart
    if [ -e "$lmkd_restart_counter_path" ]; then
        echo "0" > "$lmkd_restart_counter_path"
        echo "1" > "$lmkd_restart_counter_path"
    fi
}

init_io() {
    for sd in /sys/block/*; do
        [ -f "$sd/queue/scheduler" ] && write_val "none" "$sd/queue/scheduler"
        [ -f "$sd/queue/iostats" ] && write_val "0" "$sd/queue/iostats"
        [ -f "$sd/queue/nomerges" ] && write_val "2" "$sd/queue/nomerges"
        [ -f "$sd/queue/read_ahead_kb" ] && write_val "128" "$sd/queue/read_ahead_kb"
        [ -f "$sd/bdi/read_ahead_kb" ] && write_val "128" "$sd/bdi/read_ahead_kb"
    done
}

init_network() {
    write_val "0" /proc/sys/net/ipv4/tcp_autocorking
    write_val "1" /proc/sys/net/ipv4/tcp_tw_reuse
    write_val "5" /proc/sys/net/ipv4/tcp_fin_timeout
    write_val "1" /proc/sys/net/ipv4/tcp_shrink_window
    write_val "10" /proc/sys/net/ipv4/tcp_reordering
    write_val "1000" /proc/sys/net/ipv4/tcp_max_reordering
    write_val "1" /proc/sys/net/ipv4/tcp_thin_linear_timeouts
    write_val "1048576" /proc/sys/net/ipv4/rmem_default
    write_val "16777216" /proc/sys/net/ipv4/rmem_max
    write_val "65536 1048576 16777216" /proc/sys/net/ipv4/tcp_rmem
    write_val "1048576" /proc/sys/net/ipv4/wmem_default
    write_val "16777216" /proc/sys/net/ipv4/wmem_max
    write_val "65536 1048576 16777216" /proc/sys/net/ipv4/tcp_wmem
}

init_android_config() {
    device_config set_sync_disabled_for_tests until_reboot
    device_config put activity_manager max_cached_processes 65535
    device_config put activity_manager max_phantom_processes 65535
    device_config put lmkd_native use_minfree_levels false
    device_config delete lmkd_native thrashing_limit_critical
    device_config put activity_manager use_compaction false
    device_config delete activity_manager settings_enable_monitor_phantom_procs
    settings put global settings_enable_monitor_phantom_procs false
}

init_miui_disable() {
    stop vendor.cnss_diag 2>/dev/null
    stop vendor.tcpdump 2>/dev/null
    stop cnss-daemon 2>/dev/null
    for svc in mimd-service mimd-service2_0; do stop $svc 2>/dev/null; done
    [ -f /sys/module/ged/parameters/gpu_cust_boost_freq ] && write_val "0" /sys/module/ged/parameters/gpu_cust_boost_freq
    [ -f /sys/module/ged/parameters/gpu_cust_upbound_gpu_freq ] && write_val "0" /sys/module/ged/parameters/gpu_cust_upbound_gpu_freq
    settings put system miui_app_cache_optimization 0
    am broadcast -a miui.intent.action.CLOUD_CONTROL -n com.android.htmlviewer/com.android.settings.cloud.CloudControlBootCompletedReceiver 2>/dev/null
}

init_gpu_unlock() {
    local KGSL="/sys/class/kgsl/kgsl-3d0"
    [ -d "$KGSL" ] || return

    local NUM_PWRLVL="$(cat $KGSL/num_pwrlevels 2>/dev/null)"
    local MIN_PWRLVL="$((NUM_PWRLVL - 1))"

    [ -f "$KGSL/default_pwrlevel" ] && lock_val "$MIN_PWRLVL" "$KGSL/default_pwrlevel"
    [ -f "$KGSL/min_pwrlevel" ] && lock_val "$MIN_PWRLVL" "$KGSL/min_pwrlevel"
    [ -f "$KGSL/max_pwrlevel" ] && lock_val "0" "$KGSL/max_pwrlevel"
    [ -f "$KGSL/thermal_pwrlevel" ] && lock_val "0" "$KGSL/thermal_pwrlevel"
    [ -f "$KGSL/throttling" ] && lock_val "0" "$KGSL/throttling"
    [ -f "$KGSL/force_bus_on" ] && write_val "0" "$KGSL/force_bus_on"
    [ -f "$KGSL/bus_split" ] && write_val "0" "$KGSL/bus_split"
    [ -f "$KGSL/force_clk_on" ] && write_val "0" "$KGSL/force_clk_on"
    [ -f "$KGSL/force_no_nap" ] && write_val "0" "$KGSL/force_no_nap"
    [ -f "$KGSL/force_rail_on" ] && write_val "0" "$KGSL/force_rail_on"
    [ -f "$KGSL/bcl" ] && write_val "0" "$KGSL/bcl"
    [ -f "$KGSL/max_gpu_clk" ] && lock_val "2147483647" "$KGSL/max_gpu_clk"
    [ -f "$KGSL/max_clock_mhz" ] && lock_val "2147483647" "$KGSL/max_clock_mhz"
    [ -f "$KGSL/min_clock_mhz" ] && lock_val "0" "$KGSL/min_clock_mhz"

    [ -f /sys/kernel/gpu/gpu_max_clock ] && lock_val "2147483647" /sys/kernel/gpu/gpu_max_clock
    [ -f /sys/kernel/gpu/gpu_min_clock ] && lock_val "0" /sys/kernel/gpu/gpu_min_clock

    for freq_path in /sys/class/devfreq/*kgsl-3d0; do
        [ -d "$freq_path" ] && {
            [ -f "$freq_path/min_freq" ] && lock_val "0" "$freq_path/min_freq"
            [ -f "$freq_path/max_freq" ] && lock_val "2147483647" "$freq_path/max_freq"
        }
    done
}

init_cpu_freq() {
    lock_val_in_path "2147483647" "/sys/devices/system/cpu/cpufreq" "scaling_max_freq"
}

init_bus_dcvs() {
    local BUS_DIR="/sys/devices/system/cpu/bus_dcvs"
    [ -d "$BUS_DIR" ] || return
    lock_val_in_path "10900000" "$BUS_DIR/DDR" "max_freq"
    lock_val_in_path "806000" "$BUS_DIR/LLCC" "max_freq"
    lock_val_in_path "20000000" "$BUS_DIR/L3" "max_freq"
    lock_val_in_path "0" "$BUS_DIR" "min_freq"
    lock_val_in_path "0" "$BUS_DIR" "boost_freq"
    lock_val_in_path "1" "$BUS_DIR/DDRQOS" "boost_freq"
}

init_corectl() {
    lock_val_in_path "1" "/sys/devices/system/cpu" "core_ctl" "enable"
    lock_val_in_path "99" "/sys/devices/system/cpu" "core_ctl" "min_cpus"
    lock_val_in_path "99" "/sys/devices/system/cpu" "core_ctl" "max_cpus"
    lock_val_in_path "0" "/sys/devices/system/cpu" "core_ctl" "enable"
}

init_perfhal() {
    [ -f /sys/kernel/msm_performance/parameters/cpu_min_freq ] || return
    write_val "0:100000 1:100000 2:100000 3:100000 4:100000 5:100000 6:100000 7:100000" /sys/kernel/msm_performance/parameters/cpu_min_freq
    write_val "0:9999999 1:9999999 2:9999999 3:9999999 4:9999999 5:9999999 6:9999999 7:9999999" /sys/kernel/msm_performance/parameters/cpu_max_freq
}

init_cpuset() {
    local LITTLE_LIST="$(cat /sys/devices/system/cpu/cpu0/topology/package_cpus_list 2>/dev/null)"
    local ALL_LIST="$(cat /sys/devices/system/cpu/present 2>/dev/null)"
    [ -n "$LITTLE_LIST" ] && [ -n "$ALL_LIST" ] || return
    rmdir /dev/cpuset/foreground/boost 2>/dev/null
    lock_val "$LITTLE_LIST" /dev/cpuset/background/cpus
    lock_val "$LITTLE_LIST" /dev/cpuset/system-background/cpus
    lock_val "$ALL_LIST" /dev/cpuset/foreground/cpus
    lock_val "$ALL_LIST" /dev/cpuset/top-app/cpus
    lock_val "$LITTLE_LIST" /proc/irq/default_smp_affinity
    lock_val_in_path "$LITTLE_LIST" "/proc/irq" "smp_affinity_list"
}

init_lpm() {
    for f in /sys/devices/system/cpu/qcom_lpm/*disable*; do
        [ -f "$f" ] && lock_val "0" "$f"
    done
}

init_sched() {
    [ -f /proc/sys/kernel/sched_pelt_multiplier ] && write_val "4" /proc/sys/kernel/sched_pelt_multiplier
    [ -f /sys/kernel/rcu_expedited ] && lock_val "0" /sys/kernel/rcu_expedited
}

nohup sh "$MODDIR/boost_monitor.sh" "$MODDIR" &

init_zram

wait_until_boot_complete
wait_until_login

init_network
init_android_config
init_miui_disable
init_cpu_freq
init_bus_dcvs
init_corectl
init_perfhal
init_cpuset
init_lpm
init_sched
init_gpu_unlock
init_io
init_mem
