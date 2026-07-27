#!/system/bin/sh
# Magisk / KernelSU / APatch modern installer customization.
SKIPUNZIP=0

ui_print " "
ui_print "| hfdem动态超频模块 v1.0.1"
ui_print "| 作者：Jiuxia"
ui_print "| 感谢 @温柔浩：原项目基础"
ui_print "| 独立动态超频模块，仅承担超频职责"
ui_print " "

# 只初始化本模块配置；绝不删除或修改其他模块目录。
[ -f "$MODPATH/dynamic_oc.conf" ] || {
    echo 'DYNAMIC_OC_ENABLED=1' > "$MODPATH/dynamic_oc.conf"
    echo 'THERMAL_GUARD_TEMP=95000' >> "$MODPATH/dynamic_oc.conf"
    echo 'THERMAL_RECOVER_TEMP=85000' >> "$MODPATH/dynamic_oc.conf"
}

set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in service.sh utils.sh boost_monitor.sh action.sh uninstall.sh; do
    [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done

ui_print "- 已启用四模式动态调配与 Scene/CTS 双监听"
ui_print "- 安装完成，重启生效"
