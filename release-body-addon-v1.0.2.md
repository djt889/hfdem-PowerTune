## hfdem PowerTune 双模块拆分补丁发布

本 Release 对应 `split-modules-v1` / `main`。本次只更新附加模块 A；动态超频模块 B 的 v1.0.1 资产保持不变。

### hfdem附加模块 v1.0.2
- ID：`hfdem_savemode`，versionCode 33，作者 Jiuxia。
- 移除全部四个第三方 5.15 KO（moon_binder、moon_kshrink_lruvecd、moon_kshrink_slabd、mi_sw_sync）及其加载逻辑：不再携带 .ko 文件，不再执行 Binder 替换/回滚，不再生成 ko_load.log。
- 原因：hfdem 内核已内建原 @Amktiao 的 5.15 附加优化，随内核启动即生效，无需模块侧加载。
- WebUI 的 5.15 KO 卡片改为“内核内建优化状态”：仅显示当前内核是否为 5.15 系列及模块提示，不显示各 KO 加载成功/失败，也不依赖 ko_load.log。
- 电池温度 v1.0.1 修复保留：稳健归一化为摄氏度，兼容整数摄氏度、小数摄氏度、0.1°C 与毫摄氏度节点。
- LZ4 + swappiness 60、安全回退，以及内存/网络/I/O/IRQ/LPM、CPQ、MGLRU、THP、Joyose/MIUI 净化等既有优化全部保留。
- 不含动态超频、Action 或频率写入，可与动态超频模块同时安装。
- 感谢 @温柔浩 提供原模块基础；感谢 @Amktiao 提供 5.15 内核优化（已内建于内核）。

### hfdem动态超频模块 v1.0.1（资产保持不变）
- ID：`hfdem_dynamic_oc`，versionCode 2，作者 Jiuxia。
- 基于 CTS 和 schedhorizon 调度（按需自选二选一）；仅含动态调度职责。
- schedhorizon 按需自行安装：[下载 schedhorizon-20241107.zip](https://github.com/hfdem/android_gki_kernel_5.15_common/releases/download/v25.06.15/schedhorizon-20241107.zip)。
- 感谢 @温柔浩 提供原项目基础。

两个模块的 ID、配置、日志、PID 与运行状态相互隔离。附加模块最终 ZIP 已完成 pytest、bash/sh/dash Shell 语法、JS 最小探针、CRC、元数据、排除项及 SHA-256 复验。
