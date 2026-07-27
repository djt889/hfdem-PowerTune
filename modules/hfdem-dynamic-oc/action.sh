#!/system/bin/sh
MODDIR=${0%/*}
[ "$MODDIR" = . ] && MODDIR=/data/adb/modules/hfdem_dynamic_oc
. "$MODDIR/utils.sh"
# 该 Action 只使用 hfdem_dynamic_oc 前缀状态；不读取或清理模块 A 状态。
if [ -f "$BOOST" ]; then
    boost_off
    echo off > "$MANUAL"
else
    boost_on
    echo on > "$MANUAL"
fi
mode="$(cat "$LAST_STATE_FILE" 2>/dev/null)"
printf 'mode=%s\nboost=%s\nmanual=1\nupdated=%s\n' "${mode:-unknown}" "$([ -f "$BOOST" ] && echo on || echo off)" "$(date +%s)" > "$MODDIR/status.conf.tmp"
mv -f "$MODDIR/status.conf.tmp" "$MODDIR/status.conf"
