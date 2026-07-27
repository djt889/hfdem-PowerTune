#!/system/bin/sh
# Legacy 安装兼容入口；发布 ZIP 使用 customize.sh，且不会打包本文件。
SKIPUNZIP=0
unzip -o "$ZIPFILE" -d "$MODPATH" >&2

ui_print "| hfdem附加模块 v1.0.0｜作者：Jiuxia"
ui_print "| 感谢 @温柔浩（原模块基础）、@Amktiao（5.15 内核优化模块）"

OLD_MOD="/data/adb/modules/hfdem_savemode"
if [ "$OLD_MOD" != "$MODPATH" ] && [ -d "$OLD_MOD" ]; then rm -rf "$OLD_MOD"; fi

if [ -d /mi_ext ] || [ -d /dev/mi_display ]; then
    ui_print "- 小米设备：合并 MIUI 属性并生成无调频 Joyose 云控..."
    cat "$MODPATH/miui.prop" >> "$MODPATH/system.prop"
    . "$MODPATH/gen_cloud_config.sh"
else
    ui_print "- 非小米设备：跳过 Joyose/MIUI 云控"
    rm -rf "$MODPATH/config" "$MODPATH/bin" "$MODPATH/gen_cloud_config.sh"
fi
rm -f "$MODPATH/gen_cloud_config.sh" "$MODPATH/bin/cloudconfig_gen"
rmdir "$MODPATH/bin" 2>/dev/null

case "$(uname -r)" in
  5.15*) ui_print "- 保留来自 @Amktiao 的第三方 5.15 KO" ;;
  *) rm -rf "$MODPATH/ko"; ui_print "- 非 5.15 内核，跳过第三方 KO" ;;
esac
rm -f "$MODPATH/gpu_boost.conf"
set_perm_recursive "$MODPATH" 0 0 0755 0644
for f in service.sh utils.sh post-fs-data.sh uninstall.sh no_oc_check.sh; do
    [ -f "$MODPATH/$f" ] && set_perm "$MODPATH/$f" 0 0 0755
done
ui_print "- 安装完成，重启生效"
