#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/utils.sh"

MIUI_DISABLE=1
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
zram_log() {
    ZRAM_LOG="${HFD_TEST_ZRAM_LOG:-$MODDIR/zram.log}"
    printf '[%s] %s\n' "$(_get_time)" "$*" >> "$ZRAM_LOG"
}

zram_algorithm_supported() {
    ZRAM_ALG_FILE="$1"
    ZRAM_WANTED="$2"
    [ -r "$ZRAM_ALG_FILE" ] || return 1
    for ZRAM_ITEM in $(tr '[]' '  ' < "$ZRAM_ALG_FILE" 2>/dev/null); do
        [ "$ZRAM_ITEM" = "$ZRAM_WANTED" ] && return 0
    done
    return 1
}

zram_active_algorithm() {
    sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$1" 2>/dev/null
}

zram_is_active() {
    grep -q "zram$ZRAM_ID" "$ZRAM_SWAPS" 2>/dev/null
}

# 写入后必须按 sysfs 实际回读确认；调用者负责按 lz4 -> zstd -> 原算法顺序尝试。
zram_try_algorithm() {
    ZRAM_TRY="$1"
    [ -n "$ZRAM_TRY" ] || return 1
    zram_algorithm_supported "$ZRAM_ALG_FILE" "$ZRAM_TRY" || {
        zram_log "zram$ZRAM_ID 算法候选不受支持: $ZRAM_TRY"
        return 1
    }
    lock_val "$ZRAM_TRY" "$ZRAM_ALG_FILE"
    ZRAM_READBACK="$(zram_active_algorithm "$ZRAM_ALG_FILE")"
    if [ "$ZRAM_READBACK" = "$ZRAM_TRY" ]; then
        ZRAM_SELECTED="$ZRAM_TRY"
        zram_log "zram$ZRAM_ID 算法写入验证成功: $ZRAM_TRY"
        return 0
    fi
    zram_log "zram$ZRAM_ID 算法写入验证失败: 目标=$ZRAM_TRY 回读=${ZRAM_READBACK:-未知}"
    return 1
}

# reset 后的有界恢复：最多遍历一次“已验证/主选/zstd/原算法”去重候选。
# reset 已经销毁旧压缩数据，因此这里只承诺尽力重建可用 swap，不宣称恢复旧数据。
zram_recover_swap() {
    ZRAM_REASON="$1"
    ZRAM_SEEN=" "
    zram_log "zram$ZRAM_ID 开始恢复可用 swap: reason=$ZRAM_REASON"
    for ZRAM_CANDIDATE in "$ZRAM_SELECTED" "$ZRAM_REQUESTED" "zstd" "$ZRAM_CURRENT"; do
        [ -n "$ZRAM_CANDIDATE" ] || continue
        case "$ZRAM_SEEN" in *" $ZRAM_CANDIDATE "*) continue ;; esac
        ZRAM_SEEN="$ZRAM_SEEN$ZRAM_CANDIDATE "
        lock_val "1" "$ZRAM_SYS/reset"
        lock_val "0" "$ZRAM_SYS/mem_limit"
        zram_try_algorithm "$ZRAM_CANDIDATE" || continue
        if ! echo "$ZRAM_RECOVERY_SIZE" > "$ZRAM_SYS/disksize" 2>/dev/null; then
            zram_log "zram$ZRAM_ID 恢复 disksize 失败: algorithm=$ZRAM_CANDIDATE"
            continue
        fi
        if ! "$ZRAM_MKSWAP" "$ZRAM_DEV" >/dev/null 2>&1; then
            zram_log "zram$ZRAM_ID 恢复 mkswap 失败: algorithm=$ZRAM_CANDIDATE"
            continue
        fi
        if ! "$ZRAM_SWAPON" "$ZRAM_DEV" >/dev/null 2>&1; then
            zram_log "zram$ZRAM_ID 恢复 swapon 失败: algorithm=$ZRAM_CANDIDATE"
            continue
        fi
        if zram_is_active; then
            zram_log "zram$ZRAM_ID 恢复成功: algorithm=$ZRAM_CANDIDATE disksize=$ZRAM_RECOVERY_SIZE"
            return 0
        fi
        zram_log "zram$ZRAM_ID swapon 返回成功但 active 校验失败: algorithm=$ZRAM_CANDIDATE"
    done
    return 1
}

zram_log_final_state() {
    if zram_is_active; then
        zram_log "zram$ZRAM_ID 最终状态: swap active algorithm=$(zram_active_algorithm "$ZRAM_ALG_FILE")"
    else
        zram_log "zram$ZRAM_ID 最终状态: swap inactive（恢复尝试已穷尽）"
    fi
}

init_zram_per() {
    ZRAM_ID="$1"
    ZRAM_REQUESTED="$2"
    ZRAM_SYS_ROOT="${HFD_TEST_ZRAM_SYS_ROOT:-/sys/block}"
    ZRAM_DEV_ROOT="${HFD_TEST_ZRAM_DEV_ROOT:-/dev/block}"
    ZRAM_MEMINFO="${HFD_TEST_MEMINFO:-/proc/meminfo}"
    ZRAM_SWAPS="${HFD_TEST_SWAPS:-/proc/swaps}"
    ZRAM_SWAPON="${HFD_TEST_SWAPON_BIN:-/system/bin/swapon}"
    ZRAM_SWAPOFF="${HFD_TEST_SWAPOFF_BIN:-swapoff}"
    ZRAM_MKSWAP="${HFD_TEST_MKSWAP_BIN:-mkswap}"
    ZRAM_SYS="$ZRAM_SYS_ROOT/zram$ZRAM_ID"
    ZRAM_DEV="$ZRAM_DEV_ROOT/zram$ZRAM_ID"
    ZRAM_ALG_FILE="$ZRAM_SYS/comp_algorithm"
    [ -r "$ZRAM_ALG_FILE" ] && [ -e "$ZRAM_DEV" ] || {
        zram_log "zram$ZRAM_ID 不可用，保留系统当前配置"
        return 0
    }

    # 在任何破坏性操作前记录算法、启用状态和旧大小，仅用于恢复决策与日志。
    ZRAM_CURRENT="$(zram_active_algorithm "$ZRAM_ALG_FILE")"
    ZRAM_WAS_ACTIVE=0
    zram_is_active && ZRAM_WAS_ACTIVE=1
    ZRAM_OLD_SIZE="$(cat "$ZRAM_SYS/disksize" 2>/dev/null)"
    zram_log "zram$ZRAM_ID 重建前状态: active=$ZRAM_WAS_ACTIVE algorithm=${ZRAM_CURRENT:-未知} disksize=${ZRAM_OLD_SIZE:-未知}"

    ZRAM_SIZE="$(awk 'NR==1{print int($2*2*1024)}' "$ZRAM_MEMINFO")"
    if [ -n "$ZRAM_SIZE" ] && [ "$ZRAM_SIZE" -gt 0 ] 2>/dev/null; then
        ZRAM_RECOVERY_SIZE="$ZRAM_SIZE"
    elif [ -n "$ZRAM_OLD_SIZE" ] && [ "$ZRAM_OLD_SIZE" -gt 0 ] 2>/dev/null; then
        ZRAM_RECOVERY_SIZE="$ZRAM_OLD_SIZE"
        zram_log "zram$ZRAM_ID 2x 大小计算失败，恢复阶段使用旧 disksize=$ZRAM_OLD_SIZE"
    else
        zram_log "zram$ZRAM_ID 无有效 disksize，无法安全重建；保留当前状态"
        zram_log_final_state
        return 0
    fi

    if [ "$ZRAM_WAS_ACTIVE" = "1" ] && ! "$ZRAM_SWAPOFF" "$ZRAM_DEV" >/dev/null 2>&1; then
        zram_log "zram$ZRAM_ID swapoff 失败，未执行 reset，保留当前 swap"
        zram_log_final_state
        return 0
    fi

    lock_val "1" "$ZRAM_SYS/reset"
    lock_val "0" "$ZRAM_SYS/mem_limit"
    ZRAM_SELECTED=""
    ZRAM_SEEN=" "
    for ZRAM_CANDIDATE in "$ZRAM_REQUESTED" "zstd" "$ZRAM_CURRENT"; do
        [ -n "$ZRAM_CANDIDATE" ] || continue
        case "$ZRAM_SEEN" in *" $ZRAM_CANDIDATE "*) continue ;; esac
        ZRAM_SEEN="$ZRAM_SEEN$ZRAM_CANDIDATE "
        zram_try_algorithm "$ZRAM_CANDIDATE" && break
    done

    if [ -z "$ZRAM_SELECTED" ]; then
        zram_log "zram$ZRAM_ID reset 后所有算法候选均验证失败"
        zram_recover_swap "algorithm-selection-failed" || :
        zram_log_final_state
        return 0
    fi

    if ! echo "$ZRAM_SIZE" > "$ZRAM_SYS/disksize" 2>/dev/null; then
        zram_log "zram$ZRAM_ID 主流程 disksize 写入失败: algorithm=$ZRAM_SELECTED"
        zram_recover_swap "disksize-failed" || :
        zram_log_final_state
        return 0
    fi
    if ! "$ZRAM_MKSWAP" "$ZRAM_DEV" >/dev/null 2>&1; then
        zram_log "zram$ZRAM_ID 主流程 mkswap 失败: algorithm=$ZRAM_SELECTED"
        zram_recover_swap "mkswap-failed" || :
        zram_log_final_state
        return 0
    fi
    if ! "$ZRAM_SWAPON" "$ZRAM_DEV" >/dev/null 2>&1 || ! zram_is_active; then
        zram_log "zram$ZRAM_ID 主流程 swapon/active 校验失败: algorithm=$ZRAM_SELECTED"
        zram_recover_swap "swapon-or-active-check-failed" || :
        zram_log_final_state
        return 0
    fi

    zram_log "zram$ZRAM_ID 已启用: algorithm=$ZRAM_SELECTED disksize=$ZRAM_SIZE"
    zram_log_final_state
}

# 主策略固定标准 lz4；先做能力枚举，只有支持时才选择。
# 不支持时保守回退 zstd 或当前受支持算法，且回读验证通过后才 mkswap/swapon。
init_zram() {
    init_zram_per "0" "lz4hc"
}

# ============================================================
# 3. 内存参数
# ============================================================
init_mem() {
    local TOTAL_KB=$(awk 'NR==1{print $2}' /proc/meminfo)

    lmkd --reinit 2>/dev/null || reinit_lmkd

    write_val "20" /proc/sys/vm/compaction_proactiveness
    write_val "0" /proc/sys/vm/page-cluster

    # watermark_scale_factor=150（约 1.5% 间距）— 保活场景
    write_val "150" /proc/sys/vm/watermark_scale_factor
    # [#1] watermark_boost_factor=1：保留微量抗 OOM 暴增
    # 参考Yuni：完全禁用(0)在极端内存压力下可能导致水位线不够灵活
    write_val "1" /proc/sys/vm/watermark_boost_factor

    write_val "1" /proc/sys/vm/overcommit_memory
    write_val "60" /proc/sys/vm/swappiness

    # MGLRU 配合 swappiness=60：积极使用低延迟 lz4 ZRAM 保留后台。
    # swappiness 是回收提示，MGLRU 继续依据 refault/evict 反馈自适应。
    write_val "3" /sys/kernel/mm/lru_gen/enabled

    local mfk=$((TOTAL_KB / 128))
    [ "$mfk" -gt 131072 ] && mfk=131072
    [ "$mfk" -lt 32768 ] && mfk=32768
    write_val "$mfk" /proc/sys/vm/min_free_kbytes

    write_val "10" /proc/sys/vm/dirty_ratio
    write_val "3" /proc/sys/vm/dirty_background_ratio
    write_val "60" /proc/sys/vm/dirtytime_expire_seconds

    [ -f /sys/kernel/mm/lru_gen/enabled ] && write_val "0x0007" /sys/kernel/mm/lru_gen/enabled
    [ -f /sys/kernel/mm/lru_gen/min_ttl_ms ] && write_val "5000" /sys/kernel/mm/lru_gen/min_ttl_ms

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
        [ -f "$sd/queue/scheduler" ] || continue
        # [fix16] 5.15 CPQ 调度器优化：内核带 cpq 时选用并调参，否则保持原 none 行为
        if grep -q cpq "$sd/queue/scheduler" 2>/dev/null; then
            write_val "cpq" "$sd/queue/scheduler"
            IOSCHED="$sd/queue/iosched"
            [ -f "$sd/queue/nr_requests" ] && [ -f "$IOSCHED/async_depth" ] && \
                write_val "$(cat "$sd/queue/nr_requests")" "$IOSCHED/async_depth"
            [ -f "$IOSCHED/read_expire" ] && write_val "4" "$IOSCHED/read_expire"
            [ -f "$IOSCHED/write_expire" ] && write_val "8" "$IOSCHED/write_expire"
            [ -f "$IOSCHED/prio_aging_expire" ] && write_val "200" "$IOSCHED/prio_aging_expire"
            [ -f "$IOSCHED/io_threshold" ] && write_val "256" "$IOSCHED/io_threshold"
        else
            write_val "none" "$sd/queue/scheduler"
        fi
        [ -f "$sd/queue/iostats" ] && write_val "0" "$sd/queue/iostats"
        [ -f "$sd/queue/nomerges" ] && write_val "2" "$sd/queue/nomerges"
        [ -f "$sd/queue/read_ahead_kb" ] && write_val "128" "$sd/queue/read_ahead_kb"
        [ -f "$sd/bdi/read_ahead_kb" ] && write_val "128" "$sd/bdi/read_ahead_kb"
    done
}

# ============================================================
# 4b. 5.15 附加优化说明
# hfdem 内核已内建原 @Amktiao 5.15 附加优化（binder / kshrink /
# sw_sync 等），本模块自 v1.0.2 起不再携带或加载任何第三方 KO。
# ============================================================

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
# 7. MIUI / Joyose 非超频优化
# ============================================================
init_miui_disable() {
    [ "$MIUI_DISABLE" != "1" ] && return
    stop vendor.cnss_diag 2>/dev/null
    stop vendor.tcpdump 2>/dev/null
    stop cnss-daemon 2>/dev/null
    for svc in mimd-service mimd-service2_0; do stop $svc 2>/dev/null; done
    settings put system miui_app_cache_optimization 0
    # 触发 MIUI 普通云控重载；不停止温控服务、不写 GPU/CPU/DDR 节点。
    am broadcast -a miui.intent.action.CLOUD_CONTROL -n com.android.htmlviewer/com.android.settings.cloud.CloudControlBootCompletedReceiver 2>/dev/null
    # Joyose overlay 是安装期生成、post-fs-data 挂载；这里仅确保服务使用本地净化配置。
    if [ -d /mi_ext ] || [ -d /dev/mi_display ]; then
        pm enable com.xiaomi.joyose/com.xiaomi.joyose.cloud.CloudServerReceiver 2>/dev/null
    fi
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
            *mdss*|*dsi*|*display*|*disp*|*mtk-drm*|*drm*|*mali*|*ged*|*gpu*|*kgsl*|*touch*|*touchscreen*|*goodix*|*fts*|*synaptics*|*ufshcd*|*ufs*|*mmc*|*emmc*|*msdc*|*gic*|*arm-smmu*|*iomm*|*iommu*)
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

# init_zram 放后台：swapoff 可能较慢，不阻塞其他初始化
init_zram &
init_network
init_android_config
init_miui_disable
tiktok_decoding
init_corectl
init_cpuset
init_lpm
init_sched

init_io
init_mem
