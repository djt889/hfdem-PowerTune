# hfdem PowerTune

基于 [hfdem 内核](https://github.com/hfdem/android_gki_kernel_5.15_common.git)及 schedhorizon 调度的功耗管理模块。经测试可用在Jianke等没有附加模块的内核上。
理论上只基于[schedhorizon](https://github.com/hfdem/android_gki_kernel_5.15_common/releases)还有新增支持CTS调度。

## 适用环境

- 设备：小米13 (fuxi)
- 系统：HyperOS3
- 内核：[hfdem 内核](https://github.com/hfdem/android_gki_kernel_5.15_common.git)
- 调度：[schedhorizon](https://github.com/hfdem/android_gki_kernel_5.15_common/releases)
- 框架：KernelSU + Hybrid Mount 元模块

## 功能概述

| 功能 | 说明 |
|------|------|
| CPU优化 | 解除频率限制、禁用核心控制(core_ctl)、设置msm_performance频率范围、后台限小核(cpuset)、IRQ中断限小核(smp_affinity)、禁用LPM限制、PELT加速 |
| GPU优化 | 解锁频率限制(pwrlevel/throttling/devfreq/gpu_clk)、允许低功耗状态(force_clk_on/force_no_nap/force_rail_on/bcl)、动态调频(mod_percent) |
| 总线优化 | DDR/LLCC/L3频率上限、DDRQOS配置 |
| 内存优化 | swappiness=1、min_free_kbytes=64MB、透明大页(THP)、多代LRU、LMKD参数、vm参数调优 |
| IO优化 | none调度器、禁用iostats/nomerges、128KB预读 |
| 网络优化 | 13个TCP参数调优（autocorking/tw_reuse/fin_timeout/缓冲区等） |
| Android配置 | 不限制缓存/幽灵进程数、禁用minfree级别、禁用压缩 |
| MIUI优化 | 停止无用服务、禁用SPC/MMS/MFZ/DAMON等内存管理、ART虚拟机优化、LMKD参数 |
| 温控Boost | 极致模式自动放宽温控阈值到105°C，其他模式保持100°C |
| 手动Boost | DCVS总线满速+GPU超频+UFS满速+温控放宽，通过Actions按钮切换 |
| 兼容Eclipse | 不停止mi_thermald，与定制温控模块互不冲突 |

## Scene 接管 schedhorizon 调度后的四种模式对应策略

| Scene模式 | GPU调频 | 温控Boost | 适用场景 |
|-----------|---------|----------|---------|
| **powersave** | 100% | OFF (100°C) | 极致省电 |
| **balance** | 100% | OFF (100°C) | 日常使用 |
| **performance** | 120% | OFF (100°C) | 轻度游戏/高性能需求 |
| **fast** | 120% | ON (105°C) | 重度游戏 |

## 安装方法

1. 从 [Releases](https://github.com/djt889/hfdem-PowerTune/releases) 下载最新版 ZIP
2. 打开 KernelSU 管理器
3. 选择「模块」→「从本地安装」
4. 选择下载的 ZIP 文件
5. 等待安装完成，重启生效

## 更新方法

直接覆盖刷入新版本 ZIP 即可，无需卸载旧版本。安装脚本会自动清理旧文件。

## 手动Boost切换

在 KernelSU 管理器中，点击 hfdem PowerTune 模块的「操作」按钮，即可手动切换温控Boost开关。

- 手动切换后，自动控制不会覆盖你的选择
- 当 Scene 切换模式时（如从 balance 切到 fast），手动状态会被清除，恢复自动控制
- 模块描述会显示「手动覆盖」标记

## 模块状态查看

刷入重启后，KernelSU 管理器中的模块描述会实时显示：

```
hfdem PowerTune v2.3.2 | GPU: 调频100% | 温控: 🔴 OFF | 2026-05-28 20:15:30
```

- GPU：当前调频器百分比（100%/120%）
- 温控：Boost状态（🔴 OFF 100°C / 🟢 ON 105°C / 手动覆盖）
- 时间：最后一次模式切换时间

## 注意事项

- 本模块基于 hfdem 内核优化，**不适用于其他内核**
- 需要配合 schedhorizon 调度使用
- 不会停止 mi_thermald，与 Eclipse 定制温控模块兼容
- Boost 日志保存在模块目录的 `boost.log` 中


## 作者

原作者：[温柔浩](https://github.com/wenrouhao)
修改者：[djt889](https://github.com/djt889)
