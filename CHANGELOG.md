# hfdem PowerTune 更新日志

## v2.4.2-beta
- 取消 zram 重置为 zstd
- 保留 swappiness=60
- 测试纯 swappiness=60 的效果

## v2.4.1
- 添加 zram 重置为 zstd 压缩算法，提高压缩率 30-50%
- init_zram 提前到 boot_complete 之前，开机即生效
- swappiness 改为 60，解决打开应用瞬时功耗高的问题

## v2.4.0
- 全面优化 CPU/总线/内存/GPU/手动 Boost
