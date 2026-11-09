# 07 · 给 openwrt#22583 的回帖（草稿，尚未发布）

> **状态：未发布。** 等 2026-11-12 21:56 的 72 小时节点数据齐了再发。
> 现在发只会变成“又一个人说有效/无效”，对维护者没有增量价值。
>
> 发布方式：`gh issue comment 22583 --repo openwrt/openwrt --body-file <此文件正文>`

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
   52:         61  GIC-0  366  Edge  reo2host-status      <- 366 == 32 + 334, and it counts
  $ dmesg | grep -c HAL_REO
   0
  reo2host-destination-ring1 continued to grow normally throughout
  (2709 -> 50815 over the same window), so the RX path was genuinely busy.

Soak so far (boot 2026-11-09 21:56 CST)
  T+9h05m: HAL_REO 0, 2.4G on ch11, both AP interfaces up, no rollback.
  Interrupt count: 29 (at init) -> 35 -> 37 -> 61, i.e. a few discrete events,
  NOT anywhere near per-packet. That matches "this status ring only fires on
  a handful of conditions", so it does not by itself prove that every REO
  status entry is now reaped.
  Notable: the 37 -> 61 step at 05:00 happened in the same 10-minute window
  as a +1048 jump on ring1, with zero -105 in dmesg.

Caveat: 9 hours is nothing. Historically this bug shows up after hours of
uptime and specific load, so I am not claiming it is fixed. I will report back
at T+72h (2026-11-12 21:56 CST) either way, including a negative result.

Reproducible recipe (patch + ImageBuilder steps + the three dual-slot
rollback prerequisites that are easy to miss on this device):
https://github.com/yyefree/redmi-ax3000-ath11k-reo-fix
```

## 发布前的检查清单

- [ ] 72 小时窗口跑满，`HAL_REO` 累计仍为 0（或如实写复现数据）
- [ ] `docs/06-soak-report.md` 已补齐 T+72h 那几行
- [ ] 补上刷入前后的 `/proc/interrupts` 完整对照（含 344 与 366 两行原始输出）
- [ ] 仓库 README 顶部的“Status”一段与新数据一致（不留旧结论）
- [ ] 检查没有把个人网络信息（SSID、密码、MAC、公网 IP）带进回帖
- [ ] 语气：只给数据 + 复现路径，不评价别人的结论，不催 merge

## 发布后

- 若维护者回应“仍复现”，把对方的日志条件（负载、客户端数、时间窗）抄进
  `docs/06-soak-report.md` 的“反向证据”一节，用于指导下一步 25.12 线验证。
- 若确认有效，把回帖链接补进 README 末尾的参考列表。
