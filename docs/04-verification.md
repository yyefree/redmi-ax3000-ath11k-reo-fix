# 04 · 验证：怎么证明修好了，怎么证明没修好

## 判定标准

| 项 | 通过条件 | 说明 |
|---|---|---|
| `dmesg \| grep -c HAL_REO` | 连续 **48–72 小时**保持 0 | 这类故障常在跑数小时后、遇到特定负载才爆，几分钟的“看起来没事”没有意义 |
| `reo2host-status` | 出现在 `/proc/interrupts` 且**不是** `GIC-0 344` | 344 = SPI 312 = 旧映射；366 = SPI 334 = 修正后的映射 |
| 2.4 GHz 接口 | `iw dev` 里始终有 `channel` 与 `ssid` | 只有 `Interface` 没有 `ssid` 说明 hostapd 没起来 |
| 接口数 | 恒为 2（双频都在） | 变 1 意味着某个频段掉了 |
| 启动槽 | `ubi.mtd=rootfs`（或你刷入的目标槽） | 变回 `rootfs_1` 说明被 U-Boot 回滚了，你测的是旧固件 |
| 启动标志 | `flag_boot_success=1`、`flag_ota_reboot=0` | 见 `03-flash.md` |
| 吞吐 | 2.4 GHz 内网实测 20 Mbps 以上 | 排除“在线但实际半死” 

任何一项不通过，就**不能**说修好了。

## 中断计数的正确读法（别过度解读）

- **恒为 0**：说明这个号上没有中断源 → 映射错了（旧状态）。
- **会增长，但增长很慢**（本机 29 → 35 → 61，历经 8 小时）：正常。该中断在 REO
  初始化时必然触发几次，之后只在少量状态事件上触发。
- **每次采样都在涨，且和 `reo2host-destination-ring1` 同步大幅增长**：才是
  “每个包都走这根线”的形态；本机没观察到，说明这个 status 环不是包级中断。

结论边界：**计数从 0 变成“会涨”只能证明“号接对了”，不能证明“-105 从此不会来”。**
真正的判据只有第一条（长时间零报错）。

## 取证工具（两个脚本）

### 设备端黑匣子 `scripts/ath11k-monitor.sh`

```sh
scp -O scripts/ath11k-monitor.sh root@192.168.2.1:/usr/bin/
ssh root@192.168.2.1 'chmod +x /usr/bin/ath11k-monitor.sh'
ssh root@192.168.2.1 'echo "*/10 * * * * /usr/bin/ath11k-monitor.sh" >> /etc/crontabs/root; /etc/init.d/cron restart'
```

每 10 分钟追加一行到 `/root/ath11k-soak.log`（写 overlay，**重启不丢**；`/tmp` 是
tmpfs，重启即清空，别放那儿）。格式：

```
# ts | HAL_REO | reo_status_irq | ring1 | ifaces | 2.4G_ch | uptime_s
2026-11-10 05:00:00 | 0 | 61 | 49034 | 2 | channel 11 | 25414.82
```

脚本自动识别 2.4 GHz 接口（按 channel ≤ 14 判定），不依赖 `phyN-ap0` 这种会变的
名字；日志超过 400 行保留最后 200 行。

### 设备端兜底 `scripts/wifi-reo-watchdog.sh`（可选）

每 5 分钟检测 `HAL_REO` 计数增量，超阈值就 `unbind/bind c000000.wifi` +
`wifi up radio0`，约 28 秒恢复。**它是保险，不是修复**：触发时会断 2.4G 半分钟，
且会把故障现场“修没”。它的日志只在三种时刻写（baseline / 触发 / 失败），
**判断它是否在跑不能看日志**，要看 `/tmp/wifi-reo-watchdog.state` 的 mtime。

```sh
scp -O scripts/wifi-reo-watchdog.sh root@192.168.2.1:/usr/bin/
ssh root@192.168.2.1 'chmod +x /usr/bin/wifi-reo-watchdog.sh; echo "*/5 * * * * /usr/bin/wifi-reo-watchdog.sh" >> /etc/crontabs/root; /etc/init.d/cron restart'
```

### 本机巡检 `scripts/monitor-ax3000.ps1`

Windows 侧只读采集 + 结论判定，不重启设备、不改配置：

```powershell
$env:AX3000_PASS = '你的密码'
.\scripts\monitor-ax3000.ps1 -Router 192.168.2.1
```

输出：结论 / HAL_REO / 中断计数 / 2.4G 频道 / 接口数 / uptime / 启动槽 / 启动标志 /
黑匣子尾 6 行；同时追加一行到 `soak-status.log`，覆盖写 `soak-latest.txt`。
接进 Windows 计划任务即可无人值守。

样例记录见 `soak/sample-soak.log`。

## 如果 48–72 小时后仍然复现

那说明“只改中断号”不足以根治（这与 openwrt#22583 的报告一致）。下一步两条路：

1. **跨到 25.12 线**（kernel 6.12 / mac80211 6.18.26，kmiit 的
   `redmi_ax3000-25.12` 分支自带这处 DTS 修正）。代价：无 CI 产物，要自编整棵
   buildroot，跨大版本升级。
2. **往 ath11k 驱动里挖**：抓 REO 命令路径的 tracepoint，看
   `HAL_REO_CMD_UPDATE_RX_QUEUE` 到底卡在哪个环节（`-105` 是 `-ENOBUFS`，
   即 REO command ring 满，本质是 status ring 没被回收）。

在那之前，保留 watchdog 作为止损是合理的；它只是不构成“修好了”的证据。
