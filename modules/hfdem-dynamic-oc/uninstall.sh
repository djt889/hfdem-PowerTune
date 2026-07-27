#!/system/bin/sh
PIDFILE=/dev/hfdem_dynamic_oc_monitor_pid
PID="$(cat "$PIDFILE" 2>/dev/null)"
[ -n "$PID" ] && kill "$PID" 2>/dev/null
rm -f /dev/hfdem_dynamic_oc_boost /dev/hfdem_dynamic_oc_manual_boost \
  /dev/hfdem_dynamic_oc_last_mode /dev/hfdem_dynamic_oc_last_event_time \
  /dev/hfdem_dynamic_oc_thermal_guard /dev/hfdem_dynamic_oc_monitor_pid
