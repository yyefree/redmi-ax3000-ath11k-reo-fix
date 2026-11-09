# 01 · 根因：一个接空的中断号

## 现象复述

```
ath11k c000000.wifi: failed to send HAL_REO_CMD_UPDATE_RX_QUEUE cmd, tid 3 (-105)
```

`tid` 的取值会变（实测见过 2 / 3 / 4 / 9），`-105` 是 `-ENOBUFS`：
命令发不出去、缓冲区拿不到。同一条日志刷到几十上百行后，2.4 GHz 的
`ath11k` 侧 RX 队列更新彻底停摆，表现出来的就是“能扫到、能发起关联、卡在
WPA 握手、手机提示密码错误”。5 GHz 走的是另一个 rproc（QCN6122），很多情况下
不受影响，所以容易误判成“2.4G 单独坏了”。

## 为什么是中断号

IPQ5018 的 WiFi 子系统（`wifi@c000000`）用一串 SPI 中断与 host 通信，其中一个叫
`reo2host-status`：REO（Receive Engine Offload）状态环有新条目时通知 host 去回收。
REO 状态环如果不被回收，ring 满了以后所有 REO 命令（包括 `UPDATE_RX_QUEUE`）
都发不进去 —— 正是 `-105` 的来源。

而 QCA 在 IPQ5018 上把这根线的 DTS 映射写错了。设备树里它接的是 `GIC_SPI 312`：

```
$ grep reo2host-status /proc/interrupts
 52:          0  GIC-0  344  Edge  reo2host-status
```

Linux 的 irq 号 = `32 + SPI`，即 `344 = 32 + 312`。**计数恒为 0，且不随任何流量变化**
——不是“很少触发”，是这个号上根本没有中断源。

对照组（同一个 WiFi 节点里其它中断）都正常：

```
 49: 49034  GIC-0  348  Edge  reo2host-destination-ring1
 48:  xxxxx GIC-0  347  Edge  reo2host-destination-ring2
 47:  xxxxx GIC-0  346  Edge  reo2host-destination-ring3
 46:  xxxxx GIC-0  345  Edge  reo2host-destination-ring4
 46:      0  GIC-0  342  Edge  reo2ost-exception
```

注意 `reo2ost-exception`（拼写就是上游原样）也是 0，这是正常的——异常路径平时不触发。
所以“计数为 0”本身不能证明错，必须结合“该有事件却始终不来”判断。

## 上游怎么说的

1. **openwrt/openwrt#21264**（closed）：MX5500 上同样刷 `-105`，georgemoussalem 定位到
   `wifi` 节点的 `reo2host-status` 中断号分配错误。
2. **openwrt/openwrt PR #21271**：修正方案就两行 —— 把 `reo2host-status` 从
   `GIC_SPI 312` 改成 `GIC_SPI 334`，并把原本占 334 的 `host2tcl-input-ring2` 改成 312
   （**一对互换**，不是单方面改一个数，漏掉另一边会把 host2tcl 打坏）。
   同一个 PR 还删掉了 164 行的绕过补丁 `932-wifi-ath11k-poll-reo-status-ipq5018.patch`
   ——那份补丁的存在本身就是“硬件中断映射坏了，只能改用定时轮询”的证据。
3. **openwrt/openwrt#22583**（open）：GL-B3000 同症状，richfelker 报告打完这套修正
   **仍然复现**。这是本方案唯一的、也是最硬的反向证据，必须如实写在这里。

## 本机的验证结果

| 判据 | 修复前 | 修复后 |
|---|---|---|
| 中断号 | `GIC-0 344`（SPI 312） | `GIC-0 366`（SPI 334） |
| 中断计数 | 恒 0，任何负载下都不动 | 启动阶段 29，随后 35，再 61（有真实事件源） |
| `dmesg \| grep -c HAL_REO` | 158（历史累计） | 0 |
| `reo2host-destination-ring1` | 正常增长 | 正常增长 |

计数从 0 变成“会涨”，证明这根线现在接对了（空号和真号的区别）；但**它只在
REO 初始化/少量事件时触发，不是每包中断**，所以“计数在涨”不能等价于
“每个包走对了中断”，更不能直接推出“已经断根”。

## 其余的排除项（为什么不是别的原因）

| 假设 | 实测结论 |
|---|---|
| 换固件版本 | 所有分支（ImmortalWrt / OpenWrt / kmiit）用的都是同一份 `WLAN.HK.2.7.0.1-01744-QCAHKSWPL_SILICONZ-1`（2022-08-04），已是 QUIC 放出的最高版，换版本只是换壳 |
| 补 m3 固件 | 上游 commit 423cda97 明确说明会 Q6 crash、WiFi 完全不工作 |
| 改 htmode / 关 PMF / 关 WMM / 降带宽 / 重建接口 / rmmod+modprobe | 全部无效，故障复现时间不变 |
| 换第三方固件（kwrt、hzyitc QSDK 线） | kwrt 包不带 WiFi；hzyitc 线 kernel 4.4/5.4/5.15，2024-07 停更，作者自评 2.4G unstable |
| 官方 25.12 / master | `ipq50xx.mk` 设备列表里没有 `redmi_ax3000`，本机型只在 kmiit 线里维护 |

结论：能改且值得改的只有 DTS 这一个点。这也是本仓库存在的原因。
