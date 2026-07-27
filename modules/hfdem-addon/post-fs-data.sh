#!/system/bin/sh
# post-fs-data.sh: 小米设备挂载安装期生成的无调频 Joyose 云控镜像。
MODDIR=${0%/*}
CLOUDCONFIG_DIR="$MODDIR/config/joyose"
MOUNT_BASE="/dev/hfdem_savemode_cloud"
ODM_OVL_DIR="$MOUNT_BASE/odm"

if { [ -d /mi_ext ] || [ -d /dev/mi_display ]; } && [ -f "$CLOUDCONFIG_DIR/config.img" ]; then
    mkdir -p "$MOUNT_BASE" "$ODM_OVL_DIR"
    if mount "$CLOUDCONFIG_DIR/config.img" "$ODM_OVL_DIR" 2>/dev/null; then
        mount -t overlay -o lowerdir="$ODM_OVL_DIR:/odm" overlay /odm 2>/dev/null
    fi
fi
