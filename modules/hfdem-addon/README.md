# hfdem附加模块 v1.0.2

作者：**Jiuxia**

感谢 **@温柔浩** 提供原模块基础；感谢 **@Amktiao** 提供 5.15 内核优化。

## 功能边界

本模块保留基础附加优化，不包含动态超频、Scene/CTS 监听或手动 Boost：

- ZRAM 主选标准 `lz4`，写入后回读验证；不支持或失败时按能力安全回退。
- `vm.swappiness=60`，并保留既有 THP、MGLRU、网络、后台、I/O、IRQ、LPM 等已验收能力。
- 保留 Joyose/MIUI 净化链路，但不包含 CPU/GPU/总线调频命令。
- 5.15 附加优化已内建于 hfdem 内核；本模块自 v1.0.2 起不再携带或加载任何第三方 KO，也不再执行 Binder 替换/回滚。
- WebUI 为只读诊断，不写入调频参数。
- WebUI 将电池温度稳健归一化为摄氏度，并显示内核内建优化状态（仅判断内核是否为 5.15 系列，不依赖 KO 加载日志）。
- 动态调频监听由独立超频模块负责；本模块不执行 CPU/GPU/总线频率写入。

## 5.15 附加优化说明

原 **@Amktiao** 的 5.15 内核优化（moon_binder、moon_kshrink_lruvecd、moon_kshrink_slabd、mi_sw_sync 对应的 binder / kshrink / sw_sync 等能力）已直接内建于 hfdem 内核，随内核启动生效。本模块 ZIP 不再集成或加载这些 KO，仅通过 WebUI 显示内核内建优化状态。

## 安装与升级

在 Magisk、KernelSU 或 APatch 管理器中刷入 ZIP 后重启。模块 ID 保持 `hfdem_savemode`，可覆盖升级此前同 ID 版本。可与 `动态超频模块`（ID `hfdem_dynamic_oc`）同时安装。

## 安全说明

ZRAM 会进行“能力枚举 → 写入 → 回读 → 回退”。本模块不再执行 KO 加载、卸载或 Binder 替换操作。刷入前仍建议备份并确认设备具备救砖条件。

## 许可说明

当前仓库及所继承上游历史中未发现明确的 `LICENSE` 文件，因此本项目不自行虚构或追加许可声明。原项目与 5.15 内核优化的权利归其各自权利人所有；再分发或修改前请向对应来源确认授权范围。
