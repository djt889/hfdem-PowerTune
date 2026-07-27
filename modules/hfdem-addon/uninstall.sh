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

# 无超频版不创建也不清理 Boost/Scene 标记，避免影响独立调频模块。
