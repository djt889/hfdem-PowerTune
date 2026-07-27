#!/system/bin/sh
SKIPUNZIP=0

ui_print " "
ui_print "|=================================="
ui_print "| hfdem附加模块 v1.0.0"
ui_print "| 作者：Jiuxia"
ui_print "| 感谢 @温柔浩：原模块基础"
ui_print "| 感谢 @Amktiao：5.15 内核优化模块"
ui_print "|=================================="
ui_print " "

# 只清理本模块同 ID 的旧目录，不引用、不触碰 Dynamic OC。
OLD_MOD="/data/adb/modules/hfdem_savemode"
if [ "$OLD_MOD" != "$MODPATH" ] && [ -d "$OLD_MOD" ]; then
    ui_print "- 清除本模块旧版本残留..."
    rm -rf "$OLD_MOD"
fi

if [ -d /mi_ext ] || [ -d /dev/mi_display ]; then
    ui_print "- 小米设备：合并 MIUI 属性并生成无调频 Joyose 云控..."
    cat "$MODPATH/miui.prop" >> "$MODPATH/system.prop"
    . "$MODPATH/gen_cloud_config.sh"
else
    ui_print "- 非小米设备：跳过 Joyose/MIUI 云控"
    rm -rf "$MODPATH/config" "$MODPATH/bin" "$MODPATH/gen_cloud_config.sh"
fi
# 生成器与二进制只在安装期使用；config.img/净化 JSON 保留给 early boot。
rm -f "$MODPATH/gen_cloud_config.sh" "$MODPATH/bin/cloudconfig_gen"
rmdir "$MODPATH/bin" 2>/dev/null

KVER="$(uname -r)"
case "$KVER" in
    5.15*) ui_print "- 内核 $KVER，保留来自 @Amktiao 的第三方 5.15 KO" ;;
    *) rm -rf "$MODPATH/ko"; ui_print "- 内核 $KVER 非 5.15，跳过 @Amktiao 的第三方 5.15 KO" ;;
esac

ui_print "- 无超频版不含调度监听、频率写入、温控 Boost 或手动 Boost"
rm -f "$MODPATH/gpu_boost.conf"
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in service.sh utils.sh post-fs-data.sh uninstall.sh no_oc_check.sh; do
    [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
ui_print "- 安装完成，重启生效"
