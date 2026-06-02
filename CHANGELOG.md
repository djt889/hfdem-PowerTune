# hfdem PowerTune 更新日志

## v2.4.4-beta
- 删除 GPU force_clk_on/force_no_nap/force_rail_on/bcl 参数，解决打开应用瞬时功耗高的问题
- GPU 恢复可进入低功耗状态

## v2.4.3-beta
- 删除 init_cpu_freq，解决打开应用瞬时功耗高的问题
- 保留 init_bus_dcvs，确保游戏数据吞吐

## v2.4.1
- 添加 zram 重置为 zstd 压缩算法，提高压缩率 30-50%
- init_zram 提前到 boot_complete 之前，开机即生效
- swappiness 改为 60，解决打开应用瞬时功耗高的问题

## v2.4.0
- 全面优化 CPU/总线/内存/GPU/手动 Boost

## v2.3.2
- 省电模式 mod_percent 从 80% 改为 100% 避免潜在卡顿
- README 同步更新

## v2.3.1
- 优化启动延迟和模式切换轮询间隔

## v2.3.0
- GPU 动态调频改为运行时读取频率表
- 刷入时可选开启

## v2.2.0
- 初始版本
- 基于 hfdem 内核及 schedhorizon 调度的功耗管理模块
