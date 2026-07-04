#!/system/bin/sh
# post-fs-data.sh: Joyose 云控反杀 + 模块 early-boot 初始化
# 参考 Yuni Kernel 附加模块的云控覆盖方案

MODDIR=${0%/*}
CLOUDCONFIG_DIR="$MODDIR/config/joyose"
MOUNT_BASE="/dev/mount_lib"
ODM_OVL_DIR="$MOUNT_BASE/odm"

# Joyose 云控反杀：只在小米设备且有 config.img 时执行
if { [ -d "/mi_ext" ] || [ -d "/dev/mi_display" ]; } && \
   [ -f "$CLOUDCONFIG_DIR/config.img" ]; then
    mkdir -p "$MOUNT_BASE" "$ODM_OVL_DIR"
    mount "$CLOUDCONFIG_DIR/config.img" "$ODM_OVL_DIR"
    mount -t overlay -o lowerdir="$ODM_OVL_DIR:/odm" overlay /odm
fi
