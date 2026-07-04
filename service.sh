#!/system/bin/sh
MODDIR=${0%/*}
source "$MODDIR/utils.sh"

CONF="$MODDIR/gpu_boost.conf"
GPU_BOOST_ENABLED=0
MIUI_DISABLE=1
[ -f "$CONF" ] && . "$CONF"
USE_THP="$(awk 'NR==1{if (int($2/1024/1024) < 10) print false; else print true;}' /proc/meminfo)"

# ============================================================
# 1. 透明大页（参考 Yuni：开机全速扫描 6 轮后降速）
# ============================================================
init_thp() {
    THP_PATH=/sys/kernel/mm/transparent_hugepage
    [ -d "$THP_PATH" ] || return
    write_val "always" $THP_PATH/enabled
    [ "$USE_THP" = "false" ] && write_val "madvise" $THP_PATH/enabled
    write_val "defer+madvise" $THP_PATH/defrag
    write_val "within_size" $THP_PATH/shmem_enabled
    # [#2] use_zero_page=1：读全零页时用巨页映射，节省内存
    write_val "1" $THP_PATH/use_zero_page
    write_val "1" $THP_PATH/khugepaged/defrag
    # [#3] 开机全速扫描：65536 页/轮，确保快速覆盖所有内存
    write_val "65536" $THP_PATH/khugepaged/pages_to_scan
    write_val "100" $THP_PATH/khugepaged/alloc_sleep_millisecs
    write_val "8" $THP_PATH/khugepaged/max_ptes_none
    write_val "64" $THP_PATH/khugepaged/max_ptes_swap
    write_val "511" $THP_PATH/khugepaged/max_ptes_shared

    # [#3] full_scans 策略（参考 Yuni）：
    # 开机后等用户解锁，然后全速扫描直到 6 轮完成，再降到 6s 间隔
    # 这确保所有可折叠内存都被 THP 扫过一遍，比盲目 sleep 60s 更可靠
    init_khpd_scan &
}

init_khpd_scan() {
    # 先等开机完成
    wait_until_login

    # 全速扫描（scan_sleep=0）
    write_val "0" /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs

    # 等待 full_scans >= 6（6 轮全覆盖）
    while [ "$(cat /sys/kernel/mm/transparent_hugepage/khugepaged/full_scans 2>/dev/null)" -lt "6" ]; do
        sleep 1
    done

    # 扫描完成，降到 6s 间隔（6000ms）— 日常运行不占 CPU
    write_val "6000" /sys/kernel/mm/transparent_hugepage/khugepaged/scan_sleep_millisecs
}

# ============================================================
# 2. ZRAM
# ============================================================
init_zram_per() {
    swapoff "/dev/block/zram$1" 2>/dev/null
    # reset 清空旧压缩数据，lock_val 防覆盖
    lock_val "1" "/sys/block/zram$1/reset"
    lock_val "0" "/sys/block/zram$1/mem_limit"
    lock_val "$2" "/sys/block/zram$1/comp_algorithm"
    echo "$(awk 'NR==1{print int($2*2*1024)}' /proc/meminfo)" > "/sys/block/zram$1/disksize"
    mkswap "/dev/block/zram$1"
    /system/bin/swapon "/dev/block/zram$1"
}

# 先关旧的 zram swap，再用自己的参数重建
# 整个 init_zram 已在后台运行，swapoff 不会卡主流程
init_zram() {
    if grep -q zram /proc/swaps; then
        swapoff /dev/block/zram0 2>/dev/null
    fi
    init_zram_per "0" "zstd"
}

# ============================================================
# 3. 内存参数
# ============================================================
init_mem() {
    local TOTAL_KB=$(awk 'NR==1{print $2}' /proc/meminfo)
    local TOTAL_MB=$((TOTAL_KB / 1024))

    lmkd --reinit 2>/dev/null || reinit_lmkd

    write_val "20" /proc/sys/vm/compaction_proactiveness
    write_val "0" /proc/sys/vm/page-cluster

    # watermark: 50 (5% 间距) — 保活场景
    write_val "150" /proc/sys/vm/watermark_scale_factor
    # [#1] watermark_boost_factor=1：保留微量抗 OOM 暴增
    # 参考Yuni：完全禁用(0)在极端内存压力下可能导致水位线不够灵活
    write_val "1" /proc/sys/vm/watermark_boost_factor

    write_val "1" /proc/sys/vm/overcommit_memory
    write_val "35" /proc/sys/vm/swappiness

    local mfk=$((TOTAL_KB / 128))
    [ "$mfk" -gt 131072 ] && mfk=131072
    [ "$mfk" -lt 32768 ] && mfk=32768
    write_val "$mfk" /proc/sys/vm/min_free_kbytes

    write_val "5" /proc/sys/vm/dirty_ratio
    write_val "2" /proc/sys/vm/dirty_background_ratio
    write_val "60" /proc/sys/vm/dirtytime_expire_seconds

    [ -f /sys/kernel/mm/lru_gen/enabled ] && write_val "0x0007" /sys/kernel/mm/lru_gen/enabled
    [ -f /sys/kernel/mm/lru_gen/min_ttl_ms ] && write_val "1000" /sys/kernel/mm/lru_gen/min_ttl_ms

    [ -f /sys/module/pandora_config/parameters/enable_mm_vhs ] && write_val "Y" /sys/module/pandora_config/parameters/enable_mm_vhs

    init_thp
}

reinit_lmkd() {
    local p=/sys/module/lowmemorykiller/parameters/restart
    [ -e "$p" ] && { echo "0" > "$p"; echo "1" > "$p"; }
}

# ============================================================
# 4. I/O
# ============================================================
init_io() {
    for sd in /sys/block/*; do
        [ -f "$sd/queue/scheduler" ] && write_val "none" "$sd/queue/scheduler"
        [ -f "$sd/queue/iostats" ] && write_val "0" "$sd/queue/iostats"
        [ -f "$sd/queue/nomerges" ] && write_val "2" "$sd/queue/nomerges"
        [ -f "$sd/queue/read_ahead_kb" ] && write_val "128" "$sd/queue/read_ahead_kb"
        [ -f "$sd/bdi/read_ahead_kb" ] && write_val "128" "$sd/bdi/read_ahead_kb"
    done
}

# ============================================================
# 5. 网络（用 mask_val 防系统回写覆盖）
# ============================================================
init_network() {
    mask_val "0" /proc/sys/net/ipv4/tcp_autocorking
    mask_val "1" /proc/sys/net/ipv4/tcp_tw_reuse
    mask_val "5" /proc/sys/net/ipv4/tcp_fin_timeout
    mask_val "1" /proc/sys/net/ipv4/tcp_shrink_window
    mask_val "10" /proc/sys/net/ipv4/tcp_reordering
    mask_val "1000" /proc/sys/net/ipv4/tcp_max_reordering
    mask_val "1" /proc/sys/net/ipv4/tcp_thin_linear_timeouts
    mask_val "1048576" /proc/sys/net/ipv4/rmem_default
    mask_val "16777216" /proc/sys/net/ipv4/rmem_max
    mask_val "65536 1048576 16777216" /proc/sys/net/ipv4/tcp_rmem
    mask_val "1048576" /proc/sys/net/ipv4/wmem_default
    mask_val "16777216" /proc/sys/net/ipv4/wmem_max
    mask_val "65536 1048576 16777216" /proc/sys/net/ipv4/tcp_wmem
}

# ============================================================
# 6. Android Config（#9 先 override 再 put，双重保险）
# ============================================================
set_device_config() {
    local NAMESPACE="$1"
    local KEY="$2"
    local VAL="$3"
    device_config override "$NAMESPACE" "$KEY" "$VAL" 2>/dev/null
    device_config put "$NAMESPACE" "$KEY" "$VAL" 2>/dev/null
}

init_android_config() {
    device_config set_sync_disabled_for_tests until_reboot
    set_device_config "activity_manager" "max_cached_processes" "65535"
    set_device_config "activity_manager" "max_phantom_processes" "65535"
    set_device_config "lmkd_native" "use_minfree_levels" "false"
    device_config delete lmkd_native thrashing_limit_critical 2>/dev/null
    set_device_config "activity_manager" "use_compaction" "false"
    set_device_config "activity_manager" "use_freezer" "false"
    device_config delete activity_manager settings_enable_monitor_phantom_procs 2>/dev/null
    settings put global settings_enable_monitor_phantom_procs false
    settings put global cached_apps_freezer false
}

# ============================================================
# 7. MIUI 禁用
# ============================================================
init_miui_disable() {
    [ "$MIUI_DISABLE" != "1" ] && return
    stop vendor.cnss_diag 2>/dev/null
    stop vendor.tcpdump 2>/dev/null
    stop cnss-daemon 2>/dev/null
    killall -9 mi_thermald 2>/dev/null
    for svc in mimd-service mimd-service2_0; do stop $svc 2>/dev/null; done
    [ -f /sys/module/ged/parameters/gpu_cust_boost_freq ] && write_val "0" /sys/module/ged/parameters/gpu_cust_boost_freq
    [ -f /sys/module/ged/parameters/gpu_cust_upbound_gpu_freq ] && write_val "0" /sys/module/ged/parameters/gpu_cust_upbound_gpu_freq
    settings put system miui_app_cache_optimization 0
    am broadcast -a miui.intent.action.CLOUD_CONTROL -n com.android.htmlviewer/com.android.settings.cloud.CloudControlBootCompletedReceiver 2>/dev/null
}

# ============================================================
# 7.5 TikTok 硬解优化（移植自 Catalyst Kernel）
# ============================================================
tiktok_decoding() {
    local xml="/data/data/com.ss.android.ugc.aweme/shared_prefs/aweme-app.xml"
    [ -f "$xml" ] || return
    sed -i 's/enable_ijk_hardware[^\"]*\"0\"/enable_ijk_hardware=\"1\"/g' "$xml"
    chmod 0444 "$xml"
}

# ============================================================
# 8. GPU 解锁
# ============================================================
init_gpu_unlock() {
    local KGSL="/sys/class/kgsl/kgsl-3d0"
    [ -d "$KGSL" ] || return

    local NUM_PWRLVL="$(cat $KGSL/num_pwrlevels 2>/dev/null)"

    [ -f "$KGSL/max_pwrlevel" ] && lock_val "0" "$KGSL/max_pwrlevel"
    [ -f "$KGSL/thermal_pwrlevel" ] && lock_val "0" "$KGSL/thermal_pwrlevel"
    [ -f "$KGSL/throttling" ] && lock_val "0" "$KGSL/throttling"
    [ -f "$KGSL/force_bus_on" ] && lock_val "0" "$KGSL/force_bus_on"
    [ -f "$KGSL/bus_split" ] && lock_val "0" "$KGSL/bus_split"
    [ -f "$KGSL/force_clk_on" ] && lock_val "0" "$KGSL/force_clk_on"
    [ -f "$KGSL/force_no_nap" ] && lock_val "0" "$KGSL/force_no_nap"
    [ -f "$KGSL/force_rail_on" ] && lock_val "0" "$KGSL/force_rail_on"
    [ -f "$KGSL/bcl" ] && lock_val "1" "$KGSL/bcl"
    [ -f "$KGSL/cxl" ] && write_val "0" "$KGSL/cxl" 2>/dev/null
    [ -f "$KGSL/max_gpu_clk" ] && lock_val "2147483647" "$KGSL/max_gpu_clk"
    [ -f "$KGSL/max_clock_mhz" ] && lock_val "2147483647" "$KGSL/max_clock_mhz"
    [ -f "$KGSL/min_clock_mhz" ] && lock_val "0" "$KGSL/min_clock_mhz"

    [ -f /sys/kernel/gpu/gpu_max_clock ] && lock_val "2147483647" /sys/kernel/gpu/gpu_max_clock
    [ -f /sys/kernel/gpu/gpu_min_clock ] && lock_val "0" /sys/kernel/gpu/gpu_min_clock

    # devfreq: 两种路径都处理，max_freq 动态读取 available_frequencies 最大值
    local GPU_MAX_FREQ="2147483647"
    for freq_path in /sys/class/devfreq/*kgsl-3d0 /sys/class/kgsl/kgsl-3d0/devfreq; do
        [ -d "$freq_path" ] || continue
        local avail="$(cat "$freq_path/available_frequencies" 2>/dev/null)"
        [ -n "$avail" ] && {
            local dyn_max=$(echo "$avail" | tr ' ' '\n' | sort -n | tail -1)
            [ -n "$dyn_max" ] && GPU_MAX_FREQ="$dyn_max"
        }
        [ -f "$freq_path/min_freq" ] && lock_val "0" "$freq_path/min_freq"
        [ -f "$freq_path/max_freq" ] && lock_val "$GPU_MAX_FREQ" "$freq_path/max_freq"
    done
}

# 极速模式专用：min_pwrlevel = N-1（最低档）
gpu_boost_on() {
    local KGSL="/sys/class/kgsl/kgsl-3d0"
    [ -d "$KGSL" ] || return
    local N="$(cat $KGSL/num_pwrlevels 2>/dev/null)"
    [ -n "$N" ] && lock_val "$((N - 1))" "$KGSL/min_pwrlevel"
}

# 性能模式：min_pwrlevel = N-1（最低档）
gpu_boost_perf() {
    local KGSL="/sys/class/kgsl/kgsl-3d0"
    [ -d "$KGSL" ] || return
    local N="$(cat $KGSL/num_pwrlevels 2>/dev/null)"
    [ -n "$N" ] && lock_val "$((N - 1))" "$KGSL/min_pwrlevel"
}

# 退出极速/性能模式：min_pwrlevel = N-1（最低档）
gpu_boost_off() {
    local KGSL="/sys/class/kgsl/kgsl-3d0"
    [ -d "$KGSL" ] || return
    local N="$(cat $KGSL/num_pwrlevels 2>/dev/null)"
    [ -n "$N" ] && lock_val "$((N - 1))" "$KGSL/min_pwrlevel"
}

# ============================================================
# 9. CPU 总线频率（动态读取，有 fallback）
# ============================================================
init_bus_dcvs() {
    local BUS_DIR="/sys/devices/system/cpu/bus_dcvs"
    [ -d "$BUS_DIR" ] || return

    local ddr_max=$(get_max_available_freq "$BUS_DIR/DDR")
    [ -n "$ddr_max" ] && lock_val_in_path "$ddr_max" "$BUS_DIR/DDR" "max_freq" \
        || lock_val_in_path "10900000" "$BUS_DIR/DDR" "max_freq"

    local llcc_max=$(get_max_available_freq "$BUS_DIR/LLCC")
    [ -n "$llcc_max" ] && lock_val_in_path "$llcc_max" "$BUS_DIR/LLCC" "max_freq" \
        || lock_val_in_path "806000" "$BUS_DIR/LLCC" "max_freq"

    local l3_max=$(get_max_available_freq "$BUS_DIR/L3")
    [ -n "$l3_max" ] && lock_val_in_path "$l3_max" "$BUS_DIR/L3" "max_freq" \
        || lock_val_in_path "20000000" "$BUS_DIR/L3" "max_freq"

    lock_val_in_path "0" "$BUS_DIR" "min_freq"
    lock_val_in_path "0" "$BUS_DIR" "boost_freq"
    lock_val_in_path "1" "$BUS_DIR/DDRQOS" "boost_freq"
}

# ============================================================
# 10. Core Control（先写值，最后 lock）
# ============================================================
init_corectl() {
    local CTL_DIR="/sys/devices/system/cpu"
    write_val_in_path "99" "$CTL_DIR" "core_ctl" "min_cpus"
    write_val_in_path "99" "$CTL_DIR" "core_ctl" "max_cpus"
    write_val_in_path "0"  "$CTL_DIR" "core_ctl" "enable"
    lock_val_in_path "0"   "$CTL_DIR" "core_ctl" "enable"
}

# ============================================================
# 11. Perf HAL
# ============================================================
init_perfhal() {
    [ -f /sys/kernel/msm_performance/parameters/cpu_min_freq ] || return
    write_val "0:100000 1:100000 2:100000 3:100000 4:100000 5:100000 6:100000 7:100000" /sys/kernel/msm_performance/parameters/cpu_min_freq
    write_val "0:9999999 1:9999999 2:9999999 3:9999999 4:9999999 5:9999999 6:9999999 7:9999999" /sys/kernel/msm_performance/parameters/cpu_max_freq
}

# ============================================================
# 12. CPUSET + IRQ 亲和性
# ============================================================
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
    for irq_dir in /proc/irq/*/; do
        [ -f "$irq_dir/actions" ] || continue
        local act=$(cat "$irq_dir/actions" 2>/dev/null)
        case "$act" in
            *mdss*|*dsi*|*display*|*ufshcd*|*mmc*|*gic*|*arm-smmu*|*iomm*)
                lock_val "$ALL_LIST" "$irq_dir/smp_affinity_list"
                ;;
            *)
                lock_val "$LITTLE_LIST" "$irq_dir/smp_affinity_list"
                ;;
        esac
    done
}

# ============================================================
# 13. LPM / Sched
# ============================================================
init_lpm() {
    # 启用 LPM 低功耗模式：空闲核心进 C-state 深睡省电
    # core_ctl 保持关闭(8核全在线)，但闲时核心可以深睡，唤醒微秒级无感
    mask_val_in_path "1" "/sys/devices/system/cpu/qcom_lpm" "*disable*"
}

init_sched() {
    [ -f /proc/sys/kernel/sched_pelt_multiplier ] && mask_val "4" /proc/sys/kernel/sched_pelt_multiplier
    [ -f /sys/kernel/rcu_expedited ] && lock_val "0" /sys/kernel/rcu_expedited
}

# ============================================================
# 14. 等待开机完成
# ============================================================
wait_until_boot_complete
wait_until_login

# 确保 mask_val 所需目录存在
mkdir -p /dev/mount_masks

# ============================================================
# 15. 启动 boost 监控
# ============================================================
nohup sh "$MODDIR/boost_monitor.sh" "$MODDIR" &

# init_zram 放后台：swapoff 可能较慢，不阻塞其他初始化
init_zram &
init_network
init_android_config
init_miui_disable
tiktok_decoding
set_cpu_freq_pct 100
init_bus_dcvs
init_corectl
init_perfhal
init_cpuset
init_lpm
init_sched
init_gpu_unlock
init_io
init_mem

# 启动完成后主动刷新 module.prop 状态
sh "$MODDIR/boost_monitor.sh" "update" "/data/cur_powermode.txt" &
