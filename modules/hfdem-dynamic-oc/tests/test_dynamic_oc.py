from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
# Runtime boundary scan excludes documentation: README may explicitly document forbidden duties.
ALL = "\n".join(
    p.read_text(encoding="utf-8", errors="ignore")
    for p in ROOT.rglob("*")
    if p.is_file() and "tests" not in p.parts and p.name.lower() != "readme.md"
)
SHELL = [ROOT/n for n in ("service.sh","utils.sh","boost_monitor.sh","action.sh","customize.sh","uninstall.sh")]

def text(name): return (ROOT/name).read_text(encoding="utf-8")

def test_identity_version_and_isolation():
    prop=text("module.prop")
    assert "id=hfdem_dynamic_oc" in prop and "name=hfdem动态超频模块" in prop
    assert "version=v1.0.1" in prop and "versionCode=2" in prop
    assert "author=Jiuxia" in prop and "感谢 @温柔浩" in prop
    assert "/data/adb/modules/hfdem_savemode" not in ALL
    assert "/dev/hfdem_boost" not in ALL and "/dev/hfdem_last_mode" not in ALL
    assert "/data/adb/modules/hfdem_dynamic_oc" in ALL

def test_dual_listener_debounce_atomic_restore():
    mon=text("boost_monitor.sh")
    assert "/data/cur_powermode.txt" in mon
    assert "/data/media/0/Android/CTS/mode.txt" in mon
    assert '"$SCENE":wcD' in mon and '"$CTS":wcD' in mon
    assert "LAST_EVENT_TIME_FILE=/dev/hfdem_dynamic_oc_last_event_time" in mon
    assert "stat -c%Y" in mon and "while true" in mon and "touch \"$SCENE\"" in mon

def test_four_modes_cpu_gpu_bus():
    u=text("utils.sh")
    for mode,pct in (("powersave","70"),("balance","85"),("performance","95"),("fast","100")):
        assert mode in u and f"pct={pct}" in u
    assert "set_cpu_freq_pct" in u and "set_kgsl_mode" in u and "set_bus_mode" in u
    assert "DDR" in u and "LLCC" in u and "L3" in u and "/sys/class/devfreq/*ufs*" in u

def test_kgsl_mali_ged_conservative_detection():
    u=text("utils.sh")
    assert "/sys/class/kgsl/kgsl-3d0/devfreq" in u
    assert "available_frequencies" in u and "max_pwrlevel" in u
    assert "is_gpu_core_devfreq" in u and "*mali*|*panfrost*|*gpu*" in u
    assert "*interconnect*|*memory*|*memlat*|*membw*" in u
    assert "/sys/module/ged/parameters/gpu_cust_upbound_gpu_freq" in u
    assert "/sys/module/ged/parameters/ged_boost_enable" in u
    assert "/sys/module/ged/parameters/gpu_dvfs_enable" in u

def test_only_oc_boundary_no_ko():
    assert not (ROOT/"ko").exists()
    forbidden=["zram","transparent_hugepage","mglru","lru_gen","lmkd","tcp_","binder","cpq","/sys/block/","cpuset","/proc/irq","joyose","cloud_control","max_cached_processes","swappiness"]
    low=ALL.lower()
    for word in forbidden: assert word not in low, word
    assert not (ROOT/"system.prop").exists() and not (ROOT/"miui.prop").exists()

def test_webui_modes_state_manual_control():
    web=text("webroot/index.html")
    for mode in ("powersave","balance","performance","fast"): assert mode in web
    assert "/dev/hfdem_dynamic_oc_last_mode" in web and "action.sh" in web
    assert "/dev/hfdem_dynamic_oc_manual_boost" in web
    assert "window.ksu" in web and ".exec" in web
    assert "printf '%s\\\\n'" in web and "/data/cur_powermode.txt" in web
    assert "sh '\"+MOD+\"/action.sh'" in web
    assert "hfdem_savemode" not in web

def test_action_is_independent_and_prefixed():
    action=text("action.sh")
    assert "MODDIR=/data/adb/modules/hfdem_dynamic_oc" in action
    assert "hfdem_dynamic_oc" in text("utils.sh")
    assert "hfdem_savemode" not in action
    assert "/dev/hfdem_boost" not in action
    assert "boost_on" in action and "boost_off" in action

def test_thermal_boost_carries_bus_and_ufs_duties():
    u=text("utils.sh")
    assert "trip_point_2_temp" in u and "thermal_message/sconfig" in u
    assert "DDRQOS" in u and "boost_freq" in u
    assert "/sys/class/devfreq/*ufs*" in u

def test_runtime_entries_and_minimal_assets():
    for p in SHELL: assert p.exists() and p.read_text(encoding="utf-8").startswith("#!")
    allowed={"META-INF","tests","webroot"}
    assert not any(p.name in {"bin","config","ko"} for p in ROOT.iterdir())


def test_modern_installer_permissions_and_single_daemon_guard():
    custom = text("customize.sh")
    service = text("service.sh")
    uninstall = text("uninstall.sh")
    assert "SKIPUNZIP=0" in custom
    for name in ("service.sh", "utils.sh", "boost_monitor.sh", "action.sh", "uninstall.sh"):
        assert name in custom
    assert "set_perm_recursive" in custom and "set_perm" in custom
    assert "/data/adb/modules/hfdem_savemode" not in custom
    assert "PIDFILE=/dev/hfdem_dynamic_oc_monitor_pid" in service
    assert 'kill -0 "$OLDPID"' in service
    assert "hfdem_dynamic_oc_monitor_pid" in uninstall and 'kill "$PID"' in uninstall
