#!/system/bin/sh
# hfdem PowerTune 无超频版只读自检；不修改任何系统节点。
MODDIR=${0%/*}
echo "===== hfdem PowerTune noOC check ====="
grep -E '^(id|name|version|versionCode|description)=' "$MODDIR/module.prop" 2>/dev/null
echo "dynamic_tuning=DISABLED (no daemon, no mode listener)"
echo "memory:"
printf '  swappiness='; cat /proc/sys/vm/swappiness 2>/dev/null || echo --
printf '  mglru='; cat /sys/kernel/mm/lru_gen/enabled 2>/dev/null || echo --
printf '  thp='; cat /sys/kernel/mm/transparent_hugepage/enabled 2>/dev/null || echo --
printf '  zram='; cat /sys/block/zram0/comp_algorithm 2>/dev/null || echo --
echo "kernel_builtin_515:"
printf '  kernel='; uname -r
case "$(uname -r)" in
    5.15*) echo "  builtin_515_opt=yes（5.15 附加优化内建于 hfdem 内核，本模块不加载第三方 KO）" ;;
    *) echo "  builtin_515_opt=no（非 5.15 内核）" ;;
esac
echo "NOTE: 超频/动态调频已拆分，本脚本仅做读取。"
