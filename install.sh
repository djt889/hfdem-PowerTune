SKIPUNZIP=0

ui_print " "
ui_print "|=================================="
ui_print "| hfdem PowerTune $(unzip -p "$ZIPFILE" module.prop 2>/dev/null | grep "^version=" | cut -d'=' -f2)"
ui_print "| 作者：温柔浩"
ui_print "|=================================="
ui_print " "

# [#5] 旧模块清理改用 rm -rf 彻底清理
OLD_MOD="/data/adb/modules/hfdem_savemode"
if [ -d "$OLD_MOD" ]; then
    ui_print "- 清除旧模块残留..."
    rm -rf "$OLD_MOD"
    ui_print "- 旧模块已清理"
else
    ui_print "- 首次安装，跳过清理"
fi

unzip -o "$ZIPFILE" -d "$MODPATH" >&2

# Joyose 云控反杀：只在小米设备上执行
if [ -d "/mi_ext" ] || [ -d "/dev/mi_display" ]; then
    ui_print "- 小米设备检测到，生成 Joyose 云控配置..."
    . "$MODPATH/gen_cloud_config.sh"
else
    # 非小米设备删除 Joyose 相关文件
    rm -rf "$MODPATH/config/" "$MODPATH/bin/" "$MODPATH/gen_cloud_config.sh"
    ui_print "- 非小米设备，跳过 Joyose 云控"
fi

# 合并 miui.prop（小米设备）
if [ -d "/mi_ext" ] || [ -d "/dev/mi_display" ]; then
    ui_print "- 合并 miui.prop..."
    cat "$MODPATH/miui.prop" >> "$MODPATH/system.prop"
fi

# 清理安装期临时文件
rm -rf "$MODPATH/gen_cloud_config.sh" "$MODPATH/bin/cloudconfig_gen"

getVolumeKey() {
  sleep 1
  while true; do
    keyInfo=$(getevent -qlc 1 | grep KEY_VOLUME)
    [ -n "$keyInfo" ] && { echo "$keyInfo" | grep -q KEY_VOLUMEUP && return 0 || return 1; }
  done
}

ui_print " "
ui_print "- 是否开启 GPU 动态调频？"
ui_print "  音量+ 开启 / 音量- 关闭"

if getVolumeKey; then
    echo "GPU_BOOST_ENABLED=1" > "$MODPATH/gpu_boost.conf"
    ui_print "  [OK] GPU 动态调频已开启"
else
    echo "GPU_BOOST_ENABLED=0" > "$MODPATH/gpu_boost.conf"
    ui_print "  [--] GPU 动态调频已关闭"
fi

# 设置权限
set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/utils.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/boost_monitor.sh" 0 0 0755
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755

ui_print " "
ui_print "- 安装完成，重启生效"
ui_print " "
