# 07 · 给 openwrt#22583 的回帖（已发布）

> **已发布**：2026-11-10 19:15 (CST) / 11:15 UTC
> 链接：https://github.com/openwrt/openwrt/issues/22583#issuecomment-6765885787
> 账号：yyefree；正文 2,987 字符，与下方“正文（已发布原文）”逐字一致。
>
> 发布时机说明：原计划等 T+72h，但每小时巡检在 T+20h11m 停止，72 h 窗口取不到数据。
> 因此这次发的是 **T+21h18m（uptime 76,680 s，中间无重启）零复现** 的证据，正文里
> 明确写了 “21 hours is not 72” 和反向证据，不把它包装成结论。

## 正文（已发布原文）

```
Data point on Redmi AX3000 (RA81): the PR #21271 interrupt swap alone, without the old REO-status polling patch, on 24.10 / kernel 6.6.137.

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
   52:          0  GIC-0  344  Edge  reo2host-status     <- count stuck at 0 forever
  $ dmesg | grep -c HAL_REO
   158                                                   <- accumulated over days
  Symptom: beacons and association fine, the WPA 4-way handshake never
  completes ("wrong password" on the client), hosts drop off; 5 GHz unaffected;
  only a reboot, or an unbind/bind of c000000.wifi, recovers it.

After the change
  $ grep reo2host-status /proc/interrupts
   52:        190  GIC-0  366  Edge  reo2host-status     <- 366 == 32 + 334, and it counts
  $ dmesg | grep -c HAL_REO
   0
  reo2host-destination-ring1 grew normally throughout (2709 -> 64836 over the
  same boot), so the RX path was genuinely busy the whole time.

Soak (boot 2026-11-09 21:56 CST, 21 hourly samples up to T+20h11m, plus one
manual check at T+21h18m)
  HAL_REO 0 in every sample; 2.4G on ch11 throughout; both AP interfaces up;
  booted from ubi.mtd=rootfs the entire time, no U-Boot rollback; uptime
  76680 s with no reboot in between.
  Interrupt count: 29 (at init) -> 35 -> 37 -> 61 -> 75 -> 84 -> 182 -> 190,
  i.e. a few discrete steps, nowhere near per-packet. That is consistent with
  "this status ring only fires on a handful of conditions", so the counter
  growing does not by itself prove that every REO status entry is now reaped.
  Three steps worth reporting:
   - 05:00  37 -> 61 with a +1048 jump on ring1 within the same 10 min, zero -105.
   - 08:00  ring1 +3409 in one hour, interrupts 61 -> 68 -> 75, zero -105.
   - 14:10  84 -> 182 (+98) while ring1 only +249, i.e. not load driven.
     I have no explanation for that one yet and I am not leaving it out.

Caveat: 21 hours is not 72. Historically this bug shows up after hours of uptime
and specific load, and this issue already has a report that the same fix still
reproduces on another model. So this is a data point in favour, not a claim
that the bug is fixed. I will keep watching and will report back if it comes
back, with dmesg and the matching /proc/interrupts lines.

Reproducible recipe (corrected DTS patch + ImageBuilder steps, including the
FIT rebuild that is easy to miss, plus the three dual-slot prerequisites that
keep U-Boot from rolling the image back):
https://github.com/yyefree/redmi-ax3000-ath11k-reo-fix
```

## 发布前检查结果

- [x] 正文数据来自最后一次实测（19:14 巡检，uptime 76,680 s，HAL_REO 0）
- [x] 压低承诺：正文含 “21 hours is not 72” 与“本 issue 已有反向报告”
- [x] 补上刷入前后的 `/proc/interrupts` 对照（344 恒 0 / 366 计数 190）
- [x] 未含 SSID、密码、MAC、内网 IP（正文只出现公网仓库链接与 github 账号）
- [x] 语气：只给数据 + 复现路径，不评价他人结论、不催 merge
- [ ] ~~48 h / 72 h 窗口跑满~~ —— 未跑满，已在正文如实交代

## 发布后

- 关注 `openwrt#22583` 回复（GitHub 会邮件通知 yyefree）：
  - 若维护者指出数据不足以判定，按对方要求的条件补测（负载、客户端数、时间窗），
    结果写进 `docs/06-soak-report.md`。
  - 若有人贴出“同补丁仍复现”的新日志，把对方的 kernel 版本与 dmesg 片段抄进
    `docs/06-soak-report.md` 的反向证据一节。
  - 若本机和别人的结果分裂（本机好、他人坏），方向转为对比两者 DTS 的
    `interrupt-names` 顺序与 mac80211 补丁集合差异，而不是继续盲跑。
- 若设备在后续使用中复现，回帖附上 `dmesg` 与 `/proc/interrupts` 原始行，
  并同步更新 README 的 Status 段。
- 需要的话，把回帖链接也补进 README 的参考列表（目前未加，避免正文与仓库互相指认成环）。
