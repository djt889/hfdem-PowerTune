# hfdem PowerTune 双模块拆分版

本发布分支在保留原 Git 历史和默认分支源码的前提下，将原综合模块拆分为两个可独立安装、也可同时安装的模块。默认分支 `main` 未被覆盖。

## 模块

| 模块 | 目录 | ID / 版本 | 职责 |
|---|---|---|---|
| hfdem附加模块 | `modules/hfdem-addon` | `hfdem_savemode` / v1.0.0（31） | LZ4 + swappiness 60、内存/网络/后台、I/O/IRQ/LPM、Joyose 净化、5.15 KO 与安全回退；**不含动态超频** |
| hfdem动态超频模块 | `modules/hfdem-dynamic-oc` | `hfdem_dynamic_oc` / v1.0.1（2） | 基于 CTS 与 schedhorizon 调度，四模式 CPU/GPU/总线动态调配，支持 KGSL、Mali/GED、温控与手动 Boost；**仅含动态调度职责** |

## 安装

1. 从本仓库 [Releases](https://github.com/djt889/hfdem-PowerTune/releases) 下载对应 ZIP。
2. 在 Magisk、KernelSU 或 APatch 管理器中选择“从本地安装”。
3. 刷入后重启。

两个模块 ID、配置、日志、PID 与 `/dev` 状态均相互隔离，可以同时安装。它们仅共享 Scene/CTS 模式文件作为动态模块的业务输入；附加模块不会监听或修改这些文件。

### 升级 ID

- 附加模块继续使用原 ID `hfdem_savemode`，可覆盖升级此前同 ID 版本。
- 动态超频模块使用独立 ID `hfdem_dynamic_oc`，从 v1.0.0 可覆盖升级至 v1.0.1。

## 功能与安全边界

### hfdem附加模块

- ZRAM 主选标准 `lz4`，`swappiness=60`。
- 算法采用能力枚举、写入后回读和候选回退；失败时记录日志并尝试恢复可用 swap。
- 保留 THP、MGLRU、网络、后台、I/O、IRQ、LPM、CPQ 和 5.15 内核附加优化。
- 不含 Scene/CTS 监听、CPU/GPU/总线频率写入、温控 Boost 或 Action；WebUI 只读。
- 5.15 Binder 替换有恢复门禁与失败回滚，其余 KO 逐项隔离失败。

### hfdem动态超频模块

- 基于 **CTS 与 schedhorizon 调度**；**schedhorizon 按需自行安装**：[下载 schedhorizon-20241107.zip](https://github.com/hfdem/android_gki_kernel_5.15_common/releases/download/v25.06.15/schedhorizon-20241107.zip)。
- 保留省电、均衡、性能、极速四模式 CPU/GPU/总线动态调配，以及 KGSL、Mali/GED、DDR/LLCC/L3/UFS、温控保护与手动 Boost。
- 不包含 ZRAM、swappiness、THP/MGLRU、网络/后台、Joyose、KO/Binder、CPQ、IRQ 或通用 I/O 优化。
- 超频可能增加功耗、温度和不稳定风险；请从均衡模式开始，并确保具备恢复条件。

## 源码、测试与 ZIP

两个源码目录均保留 `tests/` 与必要文档。Release ZIP 根目录直接是模块文件，并排除 `tests/`、缓存、任务目录、运行日志、`*.pyc` 和 legacy `install.sh`。发布前会对源码和最终实包中的全部 Shell 分别执行 `bash -n`、`sh -n`、`dash -n`，并运行各模块 pytest 与交叉边界审计。

## 致谢与来源

- 感谢 **[@温柔浩](https://github.com/wenrouhao)** 提供原模块基础。
- 感谢 **@Amktiao** 提供 5.15 内核优化模块；`modules/hfdem-addon/ko/` 中第三方 5.15 KO 来源于该模块，兼容性依赖目标内核。
- 当前 fork 与上游历史中未发现明确的 `LICENSE` 文件，因此本分支不虚构或追加许可声明。原项目和第三方文件权利归各自权利人所有；再分发或修改前请向对应来源确认授权范围。
