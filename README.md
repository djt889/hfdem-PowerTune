# hfdem PowerTune

基于 [hfdem 内核](https://github.com/hfdem/android_gki_kernel_5.15_common.git)及 schedhorizon 调度的功耗管理模块。

## 适用环境

- 设备：小米13 (fuxi)
- 系统：HyperOS3
- 内核：[hfdem 内核](https://github.com/hfdem/android_gki_kernel_5.15_common.git)
- 调度：schedhorizon
- 框架：KernelSU + Hybrid Mount 元模块

## 功能概述

| 功能 | 说明 |
|------|------|
| 系统优化 | TCP参数调优、IO调度优化、内存管理优化、后台进程数限制 |
| GPU动态调频 | 根据 Scene 四种模式自动调整 GPU 频率上限 |
| 温控Boost | 游戏模式自动放宽温控阈值，退出自动恢复 |
| 手动Boost | 通过 KernelSU Actions 按钮手动切换，不会被自动控制覆盖 |
| 兼容Eclipse | 不停止 mi_thermald，不修改 sconfig，与定制温控模块互不冲突 |

## Scene 接管 schedhorizon 调度后的四种模式对应策略

| Scene模式 | GPU频率上限 | 温控Boost | 适用场景 |
|-----------|-----------|----------|---------|
| **powersave** | 221MHz（最低） | OFF | 极致省电 |
| **balance** | 221MHz（最低） | OFF | 日常使用 |
| **performance** | 370MHz | ON | 轻度游戏/高性能需求 |
| **fast** | 690MHz（不限制） | ON | 重度游戏 |

## 安装方法

1. 下载 `hfdem-PowerTune-v2.2.0.zip`
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
hfdem PowerTune v2.2.0 | GPU: 省电(221MHz) | 温控: 🔴 OFF | 2026-05-28 20:15:30
```

- GPU：当前频率档位
- 温控：Boost状态（🔴 OFF / 🟢 ON / 手动覆盖）
- 时间：最后一次模式切换时间

## 注意事项

- 本模块基于 hfdem 内核优化，**不适用于其他内核**
- 需要配合 schedhorizon 调度使用
- 不会停止 mi_thermald，与 Eclipse 定制温控模块兼容
- Boost 日志保存在模块目录的 `boost.log` 中

## 版本历史

| 版本 | 更新内容 |
|------|---------|
| v2.2.0 | 改名 PowerTune；修复 devfreq max_freq 限制；移除 sconfig 管理避免与 Eclipse 冲突；添加手动Boost覆盖机制 |
| v2.1.0 | GPU动态调频按Scene模式控制；移除 mi_thermald 停止；install.sh 兼容 KernelSU |
| v2.0.0 | 初始版本，基于 hfdem 省电补丁 |

## 作者

温柔浩
