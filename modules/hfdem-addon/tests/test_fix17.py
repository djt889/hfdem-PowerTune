#!/usr/bin/env python3
"""hfdem PowerTune noOC precise static/sandbox regressions."""
from pathlib import Path
import json, os, re, subprocess, tempfile

ROOT = Path(__file__).resolve().parents[1]
def text(name): return (ROOT / name).read_text(encoding="utf-8")
SERVICE=text("service.sh"); UTILS=text("utils.sh"); INSTALL=text("install.sh"); CUSTOM=text("customize.sh")
GEN=text("gen_cloud_config.sh"); POSTFS=text("post-fs-data.sh"); PROP=text("module.prop"); WEBUI=text("webroot/index.html")

def extract_function(src,name):
    start=src.index(f"{name}() {{"); depth=0
    for pos in range(start,len(src)):
        if src[pos]=="{": depth+=1
        elif src[pos]=="}":
            depth-=1
            if depth==0:return src[start:pos+1]
    raise AssertionError(name)

def test_metadata():
    for x in ("id=hfdem_savemode","name=hfdem附加模块","version=v1.0.2","versionCode=33","author=Jiuxia","@温柔浩","@Amktiao"): assert x in PROP
    assert "不再携带或加载第三方 KO" in PROP and "已内建于 hfdem 内核" in PROP

def test_cloud_resources_and_safe_install_branches():
    assert (ROOT/"bin/cloudconfig_gen").is_file()
    for n in ("common_config.json","booster_config_qti.json","booster_config_mtk.json","booster_config_fuxi.json","booster_config_sheng.json"):
        assert (ROOT/"config/joyose"/n).is_file(),n
    for installer in (INSTALL,CUSTOM):
        assert "gen_cloud_config.sh" in installer
        assert 'cat "$MODPATH/miui.prop" >> "$MODPATH/system.prop"' in installer
        assert "非小米设备" in installer
        assert 'rm -rf "$MODPATH/config" "$MODPATH/bin" "$MODPATH/gen_cloud_config.sh"' in installer
        assert "action.sh" not in installer
        assert "getVolumeKey" not in installer and "GPU_BOOST_ENABLED" not in installer
    assert "cloudconfig_gen" in GEN and "mkfs.erofs" in GEN
    assert "config.img" in POSTFS and "overlay" in POSTFS and "/odm" in POSTFS
    assert "pm enable com.xiaomi.joyose" in SERVICE and "miui.intent.action.CLOUD_CONTROL" in SERVICE

def test_sanitized_booster_has_no_tuning_commands():
    bad=re.compile(r"cpufreq|scaling_|target_loads|governor|/kgsl|/mali|/ged/|ddr|llcc|bus_dcvs|thermal|freq|\"cmd\"",re.I)
    for p in (ROOT/"config/joyose").glob("booster_config_*.json"):
        raw=p.read_text(encoding="utf-8"); obj=json.loads(raw); assert not bad.search(raw),p.name
        gb=obj["game_booster"]
        assert gb["booster_enable"] is False and gb["tuner_enable"] is False
        assert gb["booster_config"]=={"default_config":[],"scene_config":[]}

def test_no_action_and_readonly_webui():
    assert not (ROOT/"action.sh").exists()
    assert "action.sh" not in INSTALL+CUSTOM+WEBUI
    assert "手动Boost" not in WEBUI and "手动 Boost" not in WEBUI
    assert "只读基础模块" in WEBUI and "不读取外部模式文件" in WEBUI
    assert "onclick=\"refresh()\"" in WEBUI and "write_val" not in WEBUI
    assert "动态调频监听','由独立超频模块负责" in WEBUI
    assert "CPU/GPU/总线频率写入','本模块不执行" in WEBUI

def run_webui_probe(expression):
    node=subprocess.run(["node","--version"],capture_output=True)
    if node.returncode: return None
    functions=[]
    for name in ("formatBatteryTemp","builtin515Status"):
        marker=f"function {name}("; start=WEBUI.index(marker); depth=0
        brace=WEBUI.index("{",start)
        for pos in range(brace,len(WEBUI)):
            if WEBUI[pos]=="{": depth+=1
            elif WEBUI[pos]=="}":
                depth-=1
                if depth==0: functions.append(WEBUI[start:pos+1]); break
    return subprocess.run(["node","-e","\n".join(functions)+f"\nconsole.log(JSON.stringify({expression}))"],text=True,capture_output=True,check=True).stdout.strip()

def test_webui_temperature_formatter_contract_and_probe():
    assert "function formatBatteryTemp(raw)" in WEBUI and "Number.isFinite" in WEBUI
    result=run_webui_probe("[formatBatteryTemp(377),formatBatteryTemp(37),formatBatteryTemp(37.5),formatBatteryTemp(37700),formatBatteryTemp('')]")
    if result is not None: assert json.loads(result)==["37.7°C","37°C","37.5°C","37.7°C","--"]

def test_webui_builtin_515_status_card():
    for x in ("内核内建优化状态","内核已内建","不再携带或加载任何第三方 KO","本模块不加载（内核已内建）","function builtin515Status(kernel)","@Amktiao","@温柔浩"): assert x in WEBUI,x
    for x in ("koStatus","ko_load.log","moon_binder","moon_kshrink","mi_sw_sync","加载成功","加载失败","已跳过","未加载/尚未执行","/sys/module/moon","/sys/module/mi_sw"): assert x not in WEBUI,x
    result=run_webui_probe("[builtin515Status('5.15.202-android13-8'),builtin515Status(' 5.15.1 '),builtin515Status('6.1.0'),builtin515Status('')]")
    if result is not None: assert json.loads(result)==["5.15 内核（优化内建于内核）","5.15 内核（优化内建于内核）","非 5.15 内核","非 5.15 内核"]

def test_no_listener_frequency_gpu_bus_or_thermal_boost_runtime():
    assert not (ROOT/"boost_monitor.sh").exists()
    runtime="\n".join(text(p.name) for p in ROOT.glob("*.sh"))
    bad=("boost_monitor","inotifyd","/data/cur_powermode.txt","Android/CTS","set_cpu_freq_pct","scaling_max_freq","mod_percent","max_gpu_clk","thermal_pwrlevel","trip_point_2_temp","thermal_message/sconfig","bus_dcvs","init_gpu_unlock","init_perfhal","killall -9 mi_thermald")
    for token in bad: assert token not in runtime,token
    assert not re.search(r'(write_val|lock_val)[^\n]*(/kgsl|/mali|/ged/)',runtime,re.I)

def test_retained_features_and_props():
    for x in ("init_zram","init_mem","init_thp","lru_gen/enabled","init_network","init_android_config","init_miui_disable","init_io","cpq","init_cpuset","smp_affinity_list","init_lpm","qcom_lpm","init_sched"): assert x in SERVICE,x
    props=text("miui.prop")+text("system.prop")
    for x in ("persist.sys.mms.enable=false","persist.sys.miui.damon.enable=false","persist.sys.mthp.enabled=false","ro.sys.fw.bg_apps_limit=128"): assert x in props,x
    miui=text("miui.prop").lower()
    for x in ("enable_templimit=false","thermal.dimming","fps.switch.thermal","gpu.partition"): assert x not in miui,x

def test_zram_lz4_swappiness_and_unchanged_memory_contract():
    zram=extract_function(SERVICE,"init_zram")
    per=extract_function(SERVICE,"init_zram_per")
    assert 'init_zram_per "0" "lz4"' in zram
    assert 'write_val "60" /proc/sys/vm/swappiness' in SERVICE
    assert 'write_val "1" /proc/sys/vm/swappiness' not in SERVICE
    assert 'write_val "0" /proc/sys/vm/page-cluster' in SERVICE
    assert 'write_val "150" /proc/sys/vm/watermark_scale_factor' in SERVICE
    assert 'int($2*2*1024)' in per
    assert 'zram$ZRAM_ID' in per and 'zram1' not in SERVICE
    for token in ('zram_algorithm_supported', '"zstd"', 'ZRAM_CURRENT', 'zram_active_algorithm', 'ZRAM_READBACK', 'zram_recover_swap', 'zram_log_final_state', 'zram_log'):
        assert token in per or token in SERVICE,token
    assert "watermark_scale_factor=150（约 1.5% 间距）" in SERVICE
    assert "hfdem" not in per.lower()
    assert "LZ4 + swappiness 60" in PROP and "安全回退" in PROP and "5.15" in PROP
    assert "主选标准 lz4" in WEBUI and "目标值 60" in WEBUI and "zram.log" in WEBUI

def test_zram_capability_selection_contract():
    support=extract_function(SERVICE,"zram_algorithm_supported")
    assert "comp_algorithm" in SERVICE and "tr '[]' '  '" in support
    # Exact token matching: lz4 must not be confused with lz4hc.
    with tempfile.TemporaryDirectory() as td:
        p=Path(td)/"alg"
        sh=Path(td)/"check.sh"
        sh.write_text("#!/bin/sh\n"+support+'\nzram_algorithm_supported "$1" "$2"\n')
        p.write_text("lzo [lz4hc] zstd\n")
        assert subprocess.run(["sh",str(sh),str(p),"lz4"]).returncode != 0
        assert subprocess.run(["sh",str(sh),str(p),"zstd"]).returncode == 0
        p.write_text("lzo [lz4] zstd\n")
        assert subprocess.run(["sh",str(sh),str(p),"lz4"]).returncode == 0

def run_zram_sandbox(*, algorithms="lzo [zstd] lz4", write_fail="", mkswap_fail=0, swapon_fail=0):
    """Run the real zram state machine against bounded sysfs/command mocks."""
    names=("zram_log","zram_algorithm_supported","zram_active_algorithm","zram_is_active",
           "zram_try_algorithm","zram_recover_swap","zram_log_final_state","init_zram_per")
    funcs="\n\n".join(extract_function(SERVICE,n) for n in names)
    with tempfile.TemporaryDirectory() as td:
        r=Path(td); sys=r/"sys/zram0"; dev=r/"dev"; binp=r/"bin"
        sys.mkdir(parents=True); dev.mkdir(); binp.mkdir()
        (dev/"zram0").write_text(""); (sys/"comp_algorithm").write_text(algorithms)
        (sys/"reset").write_text("0"); (sys/"mem_limit").write_text("1")
        (sys/"disksize").write_text("4096"); (r/"meminfo").write_text("MemTotal: 1024 kB\n")
        (r/"swaps").write_text(f"Filename Type Size Used Priority\n{dev/'zram0'} partition 4 0 -2\n")
        trace=r/"trace"; log=r/"zram.log"
        (binp/"swapoff").write_text('#!/bin/sh\necho swapoff >> "$TRACE"\nprintf "Filename Type Size Used Priority\\n" > "$SWAPS"\n')
        (binp/"mkswap").write_text('#!/bin/sh\nn=$(cat "$MKCOUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$MKCOUNT"; echo "mkswap:$n" >> "$TRACE"; [ "$n" -le "${MKFAIL:-0}" ] && exit 1; exit 0\n')
        (binp/"swapon").write_text('#!/bin/sh\nn=$(cat "$SWCOUNT" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$SWCOUNT"; echo "swapon:$n" >> "$TRACE"; [ "$n" -le "${SWFAIL:-0}" ] && exit 1; printf "%s partition 4 0 -2\\n" "$1" >> "$SWAPS"\n')
        for p in binp.iterdir(): p.chmod(0o755)
        runner=r/"run.sh"
        runner.write_text("""#!/bin/sh
_get_time(){ echo T; }
lock_val(){
  val=$1; path=$2
  case "$path" in
    */reset)
      printf '%s\\n' "$val" > "$path"
      raw=$(tr '[]' '  ' < "${HFD_TEST_ZRAM_SYS_ROOT}/zram0/comp_algorithm")
      printf '%s\\n' "$raw" > "${HFD_TEST_ZRAM_SYS_ROOT}/zram0/comp_algorithm"
      ;;
    */comp_algorithm)
      echo "algwrite:$val" >> "$TRACE"
      case " $WRITE_FAIL " in *" $val "*) return 0;; esac
      raw=$(tr '[]' '  ' < "$path")
      out=""
      for alg in $raw; do
        [ "$alg" = "$val" ] && out="$out [$alg]" || out="$out $alg"
      done
      printf '%s\\n' "${out# }" > "$path"
      ;;
    *) printf '%s\\n' "$val" > "$path" ;;
  esac
}
"""+funcs+'\ninit_zram_per "0" "lz4"\n')
        env=os.environ|{"PATH":str(binp)+os.pathsep+os.environ["PATH"], "MODDIR":str(r),
            "HFD_TEST_ZRAM_SYS_ROOT":str(r/"sys"), "HFD_TEST_ZRAM_DEV_ROOT":str(dev),
            "HFD_TEST_MEMINFO":str(r/"meminfo"), "HFD_TEST_SWAPS":str(r/"swaps"),
            "HFD_TEST_SWAPOFF_BIN":str(binp/"swapoff"), "HFD_TEST_MKSWAP_BIN":str(binp/"mkswap"),
            "HFD_TEST_SWAPON_BIN":str(binp/"swapon"), "HFD_TEST_ZRAM_LOG":str(log),
            "TRACE":str(trace), "SWAPS":str(r/"swaps"), "WRITE_FAIL":write_fail,
            "MKFAIL":str(mkswap_fail), "SWFAIL":str(swapon_fail),
            "MKCOUNT":str(r/"mkcount"), "SWCOUNT":str(r/"swcount")}
        out=subprocess.run(["sh",str(runner)],env=env,text=True,capture_output=True)
        return out, log.read_text(), trace.read_text(), (r/"swaps").read_text(), (sys/"comp_algorithm").read_text()


def test_zram_sandbox_lz4_success():
    out,log,trace,swaps,alg=run_zram_sandbox()
    assert out.returncode==0,out.stderr
    assert "已启用: algorithm=lz4" in log and "最终状态: swap active algorithm=lz4" in log
    assert trace.count("mkswap:")==1 and trace.count("swapon:")==1 and "[lz4]" in alg


def test_zram_sandbox_unsupported_lz4_falls_back_zstd():
    out,log,trace,swaps,alg=run_zram_sandbox(algorithms="lzo [zstd]")
    assert out.returncode==0,out.stderr
    assert "算法候选不受支持: lz4" in log and "已启用: algorithm=zstd" in log
    assert "最终状态: swap active algorithm=zstd" in log and "[zstd]" in alg


def test_zram_sandbox_lz4_write_readback_failure_then_zstd_success():
    out,log,trace,swaps,alg=run_zram_sandbox(write_fail="lz4")
    assert out.returncode==0,out.stderr
    assert "算法写入验证失败: 目标=lz4" in log and "算法写入验证成功: zstd" in log
    assert "最终状态: swap active algorithm=zstd" in log and "[zstd]" in alg


def test_zram_sandbox_all_candidates_fail_logs_inactive():
    out,log,trace,swaps,alg=run_zram_sandbox(algorithms="[lzo] zstd lz4",write_fail="lz4 zstd lzo")
    assert out.returncode==0,out.stderr
    assert "reset 后所有算法候选均验证失败" in log
    assert "开始恢复可用 swap: reason=algorithm-selection-failed" in log
    assert "最终状态: swap inactive（恢复尝试已穷尽）" in log
    assert "zram0" not in "\n".join(swaps.splitlines()[1:])


def test_zram_sandbox_mkswap_and_swapon_failure_trigger_recovery():
    out,log,trace,swaps,alg=run_zram_sandbox(mkswap_fail=1,swapon_fail=1)
    assert out.returncode==0,out.stderr
    assert "主流程 mkswap 失败" in log and "开始恢复可用 swap: reason=mkswap-failed" in log
    assert trace.count("mkswap:")>=3 and trace.count("swapon:")>=2
    assert "恢复成功" in log and "最终状态: swap active" in log and "zram0" in swaps


def test_no_ko_files_or_ko_load_logic_anywhere():
    assert not (ROOT/"ko").exists()
    assert list(ROOT.rglob("*.ko"))==[]
    sources={p.name:p.read_text(encoding="utf-8") for p in list(ROOT.glob("*.sh"))+list(ROOT.glob("*.prop"))+[ROOT/"README.md",ROOT/"webroot/index.html"]}
    allsrc="\n".join(sources.values())
    codesrc="\n".join(v for k,v in sources.items() if k!="README.md")
    for x in ("init_kernel_modules","ko_load.log","KO_LOG","KO_DIR","rmmod","insmod","modinfo","binder_prio","HFD_TEST_KO_DIR","HFD_TEST_BINDER_ORIGINAL","HFD_TEST_SYS_MODULE_ROOT"): assert x not in allsrc,x
    for x in ("moon_binder","moon_kshrink_slabd","moon_kshrink_lruvecd","mi_sw_sync","android13-5.15"): assert x not in codesrc,x
    assert "rotate_log" not in SERVICE
    readme=text("README.md")
    for x in ("不再携带或加载任何第三方 KO","内建于 hfdem 内核","@Amktiao","@温柔浩"): assert x in readme,x
    assert not re.search(r"(?<!不)(?<!不再)(?<!未)集成.{0,6}KO", readme)

def test_uninstall_isolated_from_dynamic_oc():
    u=text("uninstall.sh")
    for x in ("hfdem_dynamic_oc","/dev/hfdem_boost","cur_powermode","Android/CTS"): assert x not in u

def test_readonly_diagnostic():
    s=text("no_oc_check.sh");assert "仅做读取" in s and "write_val" not in s and "lock_val" not in s
    assert not re.search(r'(^|[;&|])\s*(touch|rm\s)',s,re.M) and ">>" not in s

if __name__=="__main__":
    tests=[v for k,v in globals().items() if k.startswith("test_")]
    for t in tests:t();print("PASS",t.__name__)
    print(f"{len(tests)} tests passed")
