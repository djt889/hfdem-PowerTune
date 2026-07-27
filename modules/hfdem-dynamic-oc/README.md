# hfdem动态超频模块 v1.0.1

作者：**Jiuxia**

感谢 **@温柔浩** 提供原项目基础。

## 功能边界

本模块仅承担动态超频与调度职责：

- Scene/CTS 双监听、模式归一化、防抖与原子替换恢复。
- 省电、均衡、性能、极速四模式的 CPU/GPU/总线动态调配。
- Qualcomm KGSL、保守识别的 Mali/GPU devfreq、GED、DDR/LLCC/L3/UFS 调配。
- 温控保护与独立 Action 手动 Boost。
- WebUI 保留四模式与 Boost 控制，并只使用本模块 ID、配置、日志和 `/dev/hfdem_dynamic_oc_*` 状态。

本模块不包含 ZRAM、swappiness、THP/MGLRU、网络/后台策略、Joyose、KO/Binder、CPQ、IRQ 或通用 I/O 优化。

## 安装与共存

在 Magisk、KernelSU 或 APatch 管理器中刷入 ZIP 后重启。模块 ID 为 `hfdem_dynamic_oc`，可与 `hfdem附加模块`（ID `hfdem_savemode`）同时安装。两者仅共享 Scene/CTS 模式输入文件，不共享模块运行状态。

## 风险提示

超频和放宽温控可能增加功耗、发热或稳定性风险。建议先使用均衡模式，并确保设备具备恢复或救砖条件。

## 许可说明

当前仓库及所继承上游历史中未发现明确的 `LICENSE` 文件，因此本项目不自行虚构或追加许可声明。原项目权利归对应权利人所有；再分发或修改前请向来源确认授权范围。
