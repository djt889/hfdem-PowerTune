#!/system/bin/sh

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

mkdir -p "$TEMP_DIR"
mkdir -p "$CONF_ROOT"

## cmd output
print_output() {
	IFS=$(printf '\n')
	eval "$1" | while read -r line; do
		ui_print "- ${line}"
	done
}

gen_teg_config_json() {
	{
		printf '{"config_name":"%s","group_name":"%s","with_model":false,"enable":true,"version":%s,"params":' "$1" "$1" "$2"
		cat "$3"
		printf '}'
	} >"$4"
}

if [ -f "$CONF_DIR/booster_config_$DEVICE.json" ]; then
	BOOSTER_JSON="$CONF_DIR/booster_config_$DEVICE.json"
else
	VENDOR="$(getprop ro.hardware)"
	case "$VENDOR" in
	qcom)
		BOOSTER_JSON="$CONF_DIR/booster_config_qti.json"
		;;
	mt*)
		BOOSTER_JSON="$CONF_DIR/booster_config_mtk.json"
		;;
	*)
		echo "- $VENDOR device is not adapted"
		return 0
		;;
	esac
fi

# Generate configs
mkdir -p "$CONF_PATH"
gen_teg_config_json "common_config" "$COMMON_VERSION" "$COMMON_JSON" "$TEG_COMMON_JSON"
gen_teg_config_json "booster_config" "$BOOSTER_VERSION" "$BOOSTER_JSON" "$TEG_BOOSTER_JSON"
print_output "$MODPATH/bin/cloudconfig_gen $TEG_BOOSTER_JSON $TEG_COMMON_JSON $CONF_PATH/default_cloud.json"
rm -rf "$CONF_DIR"

#Generate image
mkdir -p "$CONF_DIR"
## Set common permission and owner
chmod 755 "$CONF_ROOT"
chown -R root:root "$CONF_ROOT"
find "$CONF_ROOT" -type d -exec chmod 755 {} \;
find "$CONF_ROOT" -type f -exec chmod 644 {} \;
find "$CONF_ROOT/bin" -type f -exec chmod 755 {} \;
## Set custom permission and owner
chown root:root "$CONF_PATH/default_cloud.json"
chmod 644 "$CONF_PATH/default_cloud.json"
## Set secontext
printf "/ u:object_r:vendor_file:s0\n/etc u:object_r:vendor_configs_file:s0\n/etc/default_cloud\\.json u:object_r:vendor_configs_file:s0\n" >"$TEMP_DIR/context"
## Make image
touch -a -m -c -h -d "2009-01-01 08:00:00.000000000 +0800" "$CONF_PATH"

mkfs.erofs -T1230768000 --ignore-mtime --quiet \
	--file-contexts="$TEMP_DIR/context" \
	"$CONF_DIR/config.img" "$CONF_ROOT"
## Cleanup temp
rm -rf "$TEMP_DIR"

# Restart Joyose
print_output "pm clear com.xiaomi.joyose </dev/null 2>&1 | cat"
print_output "pm enable com.xiaomi.joyose/com.xiaomi.joyose.cloud.CloudServerReceiver </dev/null 2>&1 | cat"
print_output "am broadcast -a android.intent.action.BOOT_COMPLETED -n com.xiaomi.joyose/com.xiaomi.joyose.JoyoseBroadCastReceiver </dev/null 2>&1 | cat"
