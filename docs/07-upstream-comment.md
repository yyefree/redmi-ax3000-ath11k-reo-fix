# 07 · 给 openwrt#22583 的回帖（草稿，尚未发布）

> **状态：未发布。**
>
> 原计划等 2026-11-12 21:56 的 72 小时节点数据齐了再发。但 2026-11-10 18:07 之后
> 按用户要求停止了每小时巡检，自动取证止于 **T+20h11m**，48 h / 72 h 窗口没有数据。
> 现在贴出去只是“20 小时未见复现”，对维护者增量有限，故压着不发。
>
> 发布方式：`gh issue comment 22583 --repo openwrt/openwrt --body-file <此文件正文>`
>
> **发布前必须先补一次测量**：手动跑 `monitor-ax3000.ps1`，确认 uptime 连续
> （= 中间没崩、没回滚）、`HAL_REO` 累计仍为 0，再把这一行写进正文 soak 段，
> 把 "20 h" 换成真实值。下面的正文已按 T+20h 更新，直接可用。

---

## 正文（英文，粘贴用）

```
Data point on Redmi AX3000 (RA81): the PR #21271 interrupt swap alone,
without the old REO-status polling patch, at 24.10 / kernel 6.6.137.

Setup
- Xiaomi Redmi AX3000 (RA81), IPQ5018 + QCN6122, target qualcommax/ipq50xx
- ImmortalWrt 24.10-SNAPSHOT r0-cb4f52a, kernel 6.6.137
- ImageBuilder rebuild of the same release; only the DTB changed:
  reo2host-status SPI 312 -> 334, host2tcl-input-ring2 SPI 334 -> 312
  (i.e. exactly the hunk PR #21271 applies to
  target/linux/qualcommax/patches-6.6/2815-arm64-dts-qcom-ipq5018-add-wifi-support.patch)
- The 932-wifi-ath11k-poll-reo-status-ipq5018.patch is NOT present in this tree.

Before the change
  $ grep reo2host-status /proc/interrupts
   52:          0  GIC-0  344  Edge  reo2host-status      <- count stuck at 0 forever
  $ dmesg | grep -c HAL_REO
   158                                                    <- accumulated over days
  Symptom: beacons fine, assoc fine, WPA 4-way handshake never completes,
  hosts report "wrong password"; 5 GHz unaffected; only a reboot or an
  unbind/bind of c000000.wifi recovers it.

After the change
  $ grep reo2host-status /proc/interrupts
   52:        189  GIC-0  366  Edge  reo2host-status      <- 366 == 32 + 334, and it counts
  $ dmesg | grep -c HAL_REO
   0
  reo2host-destination-ring1 continued to grow normally throughout
  (2709 -> 61714 over the same window), so the RX path was genuinely busy.

Soak (boot 2026-11-09 21:56 CST, 21 hourly samples up to T+20h11m)
  HAL_REO 0 in all 21 samples; 2.4G on ch11; both AP interfaces up;
  booted from ubi.mtd=rootfs the whole time, no rollback.
  Interrupt count: 29 (at init) -> 35 -> 37 -> 61 -> 75 -> 84 -> 182 -> 189,
  i.e. a few discrete steps, NOT anywhere near per-packet. That matches
  "this status ring only fires on a handful of conditions", so it does not
  by itself prove that every REO status entry is now reaped.
  Two steps worth noting:
   - 05:00  37 -> 61 with a +1048 jump on ring1 in the same 10 min, zero -105.
   - 08:00  ring1 +3409 in one hour, interrupts 61 -> 68 -> 75, zero -105.
   - 14:10  84 -> 182 (+98) while ring1 only +249, i.e. NOT load driven.
     I have no explanation for that one yet and I am not hiding it.

Caveat: 20 hours is not 72. Historically this bug shows up after hours of
uptime and specific load, and issue #22583 has a report that the same fix
still reproduces. So this is a data point, not a claim that it is fixed.

Reproducible recipe (patch + ImageBuilder steps + the three dual-slot
rollback prerequisites that are easy to miss on this device):
https://github.com/yyefree/redmi-ax3000-ath11k-reo-fix
```

## 发布前的检查清单

- [x] 正文数据已更新到最后一轮采样（T+20h11m，21 个点）
- [ ] 发布前补一次手动测量，把 soak 段的时长改成发布时的真实 uptime
- [ ] 48 h / 72 h 窗口未跑满这一点已在正文里如实写明（不要删掉这句）
- [ ] 补上刷入前后的 `/proc/interrupts` 完整对照（含 344 与 366 两行原始输出）
- [ ] 仓库 README 顶部的“Status”一段与新数据一致（不留旧结论）
- [ ] 检查没有把个人网络信息（SSID、密码、MAC、公网 IP）带进回帖
- [ ] 语气：只给数据 + 复现路径，不评价别人的结论，不催 merge

## 发布后

- 若维护者回应“仍复现”，把对方的日志条件（负载、客户端数、时间窗）抄进
  `docs/06-soak-report.md` 的“反向证据”一节，用于指导下一步 25.12 线验证。
- 若确认有效，把回帖链接补进 README 末尾的参考列表。
