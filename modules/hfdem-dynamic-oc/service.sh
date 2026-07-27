#!/system/bin/sh
MODDIR=${0%/*}
. "$MODDIR/utils.sh"
CONF="$MODDIR/dynamic_oc.conf"
DYNAMIC_OC_ENABLED=1
[ -f "$CONF" ] && . "$CONF"
[ "$DYNAMIC_OC_ENABLED" = 1 ] || exit 0
while [ "$(getprop sys.boot_completed)" != 1 ]; do sleep 3; done
mkdir -p /data/media/0/Android/CTS 2>/dev/null
[ -f /data/cur_powermode.txt ] || touch /data/cur_powermode.txt
[ -f /data/media/0/Android/CTS/mode.txt ] || touch /data/media/0/Android/CTS/mode.txt

# 防止 service 重入产生重复监听器；PID 状态使用本模块独立前缀。
PIDFILE=/dev/hfdem_dynamic_oc_monitor_pid
OLDPID="$(cat "$PIDFILE" 2>/dev/null)"
[ -n "$OLDPID" ] && kill -0 "$OLDPID" 2>/dev/null && exit 0
nohup sh "$MODDIR/boost_monitor.sh" "$MODDIR" >/dev/null 2>&1 &
echo "$!" > "$PIDFILE"
