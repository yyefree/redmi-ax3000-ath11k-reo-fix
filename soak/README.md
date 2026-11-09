# 样例：本机巡检累积记录（soak-status.log 的格式）

由 `scripts/monitor-ax3000.ps1` 每次执行追加一行。第一行是脚本早期版本的格式
（字段名不同），保留下来说明当时踩过的解析坑。

```
2026-11-09 22:32:44 | rc=0 | HAL=0 | IRQ=29 | 2.4G=[channel 11] | IFC=2 | UP=2189.76 | ubi.mtd=rootfs | 正常
2026-11-09 23:07:18 | rc=0 | HAL=0 | IRQ=29 | 2.4G=[channel 11] | IFC=2 | UP=4264.40 | ubi.mtd=rootfs | 正常
2026-11-10 00:07:09 | rc=0 | HAL=0 | IRQ=35 | 2.4G=[channel 11] | IFC=2 | UP=7854.87 | ubi.mtd=rootfs | 正常
2026-11-10 01:07:18 | rc=0 | HAL=0 | IRQ=35 | 2.4G=[channel 11] | IFC=2 | UP=11464.23 | ubi.mtd=rootfs | 正常
2026-11-10 02:09:13 | rc=0 | HAL=0 | IRQ=35 | 2.4G=[channel 11] | IFC=2 | UP=15179.10 | ubi.mtd=rootfs | 正常
2026-11-10 03:07:07 | rc=0 | HAL=0 | IRQ=35 | 2.4G=[channel 11] | IFC=2 | UP=18653.25 | ubi.mtd=rootfs | 正常
2026-11-10 04:07:03 | rc=0 | HAL=0 | IRQ=35 | 2.4G=[channel 11] | IFC=2 | UP=22249.49 | ubi.mtd=rootfs | 正常
2026-11-10 05:08:07 | rc=0 | HAL=0 | IRQ=61 | 2.4G=[channel 11] | IFC=2 | UP=25913.26 | ubi.mtd=rootfs | 正常
2026-11-10 06:09:06 | rc=0 | HAL=0 | IRQ=61 | 2.4G=[channel 11] | IFC=2 | UP=29572.07 | ubi.mtd=rootfs | 正常
```

字段：时间 | 退出码 | HAL_REO 报错条数 | reo2host-status 中断计数 | 2.4G 信道
| 接口数 | uptime(秒) | 启动槽 | 结论。

对应的设备端黑匣子样例（`/root/ath11k-soak.log`）：

```
# ts | HAL_REO | reo_status_irq | ring1 | ifaces | 2.4G_ch | uptime_s
2026-11-10 04:10:00 | 0 | 36 | 41640 | 2 | channel 11 | 22414.78
2026-11-10 04:20:00 | 0 | 36 | 42376 | 2 | channel 11 | 23014.79
2026-11-10 04:30:00 | 0 | 36 | 43354 | 2 | channel 11 | 23614.79
2026-11-10 04:40:00 | 0 | 37 | 44991 | 2 | channel 11 | 24214.82
2026-11-10 04:50:00 | 0 | 37 | 47986 | 2 | channel 11 | 24814.82
2026-11-10 05:00:00 | 0 | 61 | 49034 | 2 | channel 11 | 25414.82
```

读法：

- `HAL_REO` 一列必须一直是 0。
- `reo_status_irq` 从 0 变成非 0（本例 29）说明中断号接对了；29/35/61 这种阶跃
  说明它在少量事件上触发，**不是**包级中断。
- `ring1` 一列稳步上涨 = 2.4G 真的在收包（不是“在线但什么都不来”）。
- `04:40` 到 `05:00` 之间 ring1 从 44991 跳到 49034，同期 irq 37→61，
  可以对照判断“负载上来时行为是否正常”。
