#!/system/bin/sh
MODPATH=/data/adb/modules/hfdem_savemode

# 清理 system.prop 中的 persist 属性
for prop in $(grep "^persist\." $MODPATH/system.prop 2>/dev/null | cut -d= -f1); do
    resetprop -p --delete "$prop" 2>/dev/null
done

# 清理 miui.prop 中的 persist 属性（卸载前可能已合并到 system.prop）
for prop in $(grep "^persist\." $MODPATH/miui.prop 2>/dev/null | cut -d= -f1); do
    resetprop -p --delete "$prop" 2>/dev/null
done

# [#11] 清理运行时标记文件
rm -f /dev/hfdem_boost
rm -f /dev/hfdem_manual_boost
rm -f /dev/hfdem_last_mode
