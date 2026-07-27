#!/system/bin/sh
# 安装期生成经过净化的 Joyose 云控镜像；JSON 中不含任何调频/提频命令。

CONF_DIR="$MODPATH/config/joyose"
TEMP_DIR="$MODPATH/pandora_temp"
CONF_ROOT="$TEMP_DIR/mnt"
CONF_PATH="$CONF_ROOT/etc"
COMMON_VERSION="2047123101"
BOOSTER_VERSION="2047123101"
DEVICE="$(getprop ro.product.device)"
COMMON_JSON="$CONF_DIR/common_config.json"
BOOSTER_JSON="$CONF_DIR/booster_config.json"
TEG_COMMON_JSON="$TEMP_DIR/teg_common_config.json"
TEG_BOOSTER_JSON="$TEMP_DIR/teg_booster_config.json"

print_output() {
    IFS=$(printf '\n')
    eval "$1" | while read -r line; do ui_print "- ${line}"; done
}

gen_teg_config_json() {
    {
        printf '{"config_name":"%s","group_name":"%s","with_model":false,"enable":true,"version":%s,"params":' "$1" "$1" "$2"
        cat "$3"
        printf '}'
    } > "$4"
}

[ -f "$COMMON_JSON" ] || { ui_print "- Joyose common_config 缺失，跳过生成"; return 1; }
if [ -f "$CONF_DIR/booster_config_$DEVICE.json" ]; then
    BOOSTER_JSON="$CONF_DIR/booster_config_$DEVICE.json"
else
    case "$(getprop ro.hardware)" in
        qcom) BOOSTER_JSON="$CONF_DIR/booster_config_qti.json" ;;
        mt*) BOOSTER_JSON="$CONF_DIR/booster_config_mtk.json" ;;
        *) ui_print "- 当前平台未适配 Joyose 云控，跳过生成"; return 0 ;;
    esac
fi
[ -f "$BOOSTER_JSON" ] || { ui_print "- Joyose 净化配置缺失，跳过生成"; return 1; }
[ -x "$MODPATH/bin/cloudconfig_gen" ] || chmod 0755 "$MODPATH/bin/cloudconfig_gen" 2>/dev/null
command -v mkfs.erofs >/dev/null 2>&1 || { ui_print "- mkfs.erofs 不可用，降级为清理 Joyose 数据"; pm clear com.xiaomi.joyose >/dev/null 2>&1; return 0; }

rm -rf "$TEMP_DIR"
mkdir -p "$CONF_PATH"
gen_teg_config_json "common_config" "$COMMON_VERSION" "$COMMON_JSON" "$TEG_COMMON_JSON" || return 1
gen_teg_config_json "booster_config" "$BOOSTER_VERSION" "$BOOSTER_JSON" "$TEG_BOOSTER_JSON" || return 1
"$MODPATH/bin/cloudconfig_gen" "$TEG_BOOSTER_JSON" "$TEG_COMMON_JSON" "$CONF_PATH/default_cloud.json" >/dev/null 2>&1 || {
    ui_print "- cloudconfig_gen 执行失败，降级为清理 Joyose 数据"
    rm -rf "$TEMP_DIR"
    pm clear com.xiaomi.joyose >/dev/null 2>&1
    return 0
}

rm -rf "$CONF_DIR"
mkdir -p "$CONF_DIR"
chmod 0755 "$CONF_ROOT"
chown -R root:root "$CONF_ROOT"
find "$CONF_ROOT" -type d -exec chmod 0755 {} \;
find "$CONF_ROOT" -type f -exec chmod 0644 {} \;
printf "/ u:object_r:vendor_file:s0\n/etc u:object_r:vendor_configs_file:s0\n/etc/default_cloud\\.json u:object_r:vendor_configs_file:s0\n" > "$TEMP_DIR/context"
touch -a -m -c -h -d "2009-01-01 08:00:00.000000000 +0800" "$CONF_PATH"
if mkfs.erofs -T1230768000 --ignore-mtime --quiet --file-contexts="$TEMP_DIR/context" "$CONF_DIR/config.img" "$CONF_ROOT"; then
    ui_print "- Joyose 无调频云控镜像已生成"
else
    ui_print "- Joyose 镜像生成失败，降级为清理 Joyose 数据"
    rm -f "$CONF_DIR/config.img"
    pm clear com.xiaomi.joyose >/dev/null 2>&1
fi
rm -rf "$TEMP_DIR"
pm clear com.xiaomi.joyose >/dev/null 2>&1
pm enable com.xiaomi.joyose/com.xiaomi.joyose.cloud.CloudServerReceiver >/dev/null 2>&1
am broadcast -a android.intent.action.BOOT_COMPLETED -n com.xiaomi.joyose/com.xiaomi.joyose.JoyoseBroadCastReceiver >/dev/null 2>&1
return 0
