# Redmi AX3000 (RA81) — ath11k 2.4 GHz REO 中断映射修复

> Fixing the `failed to send HAL_REO_CMD_UPDATE_RX_QUEUE cmd, tid N (-105)` loop on
> Redmi AX3000 (IPQ5018 + QCN6122) running ImmortalWrt 24.10 — by correcting the
> `reo2host-status` interrupt mapping in the device tree, which upstream has
> documented as wrong (openwrt/openwrt#21264, PR #21271).

[中文](#中文) · [English](#english-summary)

---

## 中文

### 这是什么

Redmi AX3000（RA81，IPQ5018 + QCN6122，OpenWrt target `qualcommax/ipq50xx`）在
ImmortalWrt / OpenWrt 上跑一段时间后，2.4 GHz 会出现这样的现象：

- 客户端能看到 SSID、也能发起关联，但**卡在 WPA 四次握手**，手机会提示“密码错误 / 拒绝接入”；
- `dmesg` 反复刷：

  ```
  ath11k c000000.wifi: failed to send HAL_REO_CMD_UPDATE_RX_QUEUE cmd, tid 3 (-105)
  ```

- 5 GHz 可能一切正常，重启整机才能恢复（或 rebind `c000000.wifi` 后恢复）。

根因不是固件版本、不是信道、不是加密方式：**DTS 里 `wifi@c000000` 节点的
`reo2host-status` 中断号（SPI 312）本身是错的，该中断从来没有中断源**，REO 状态环
得不到回收，队列反压后所有 REO 命令都发不出去，`-105`（`-ENOBUFS`）就刷屏了。

本仓库把这个修复做成可复现的东西：改好的 DTS 补丁、ImageBuilder 构建步骤、
刷入时避免被 U-Boot 回滚的必备件、以及验证是否真断根的取证工具。

### 修复内容

`reo2host-status` 与 `host2tcl-input-ring2` 的 SPI 号**互换**（与上游 PR #21271 一致）：

| 中断名 | 修复前 SPI | 修复后 SPI |
|---|---|---|
| `reo2host-status` | 312 | **334** |
| `host2tcl-input-ring2` | 334 | **312** |

在设备上可以直接看出来：

```
$ grep reo2host-status /proc/interrupts
 52:  61  GIC-0  366  Edge  reo2host-status      # 修复后（linux irq = 32 + 334）
 52:   0  GIC-0  344  Edge  reo2host-status      # 修复前（linux irq = 32 + 312），计数恒 0
```

计数恒 0 是“这个号上根本没有中断源”的直接证据；改为 334 后，计数会随射频初始化
和部分事件增长（本机实测 0 → 29 → 35 → 61）。

### 实测状态（截至 2026-11-10）

| 判据 | 修复前 | 修复后 |
|---|---|---|
| `reo2host-status` | `GIC-0 344`，计数恒 0 | `GIC-0 366`，计数会增长 |
| `dmesg \| grep -c HAL_REO` | 158（历史累计） | 0 |
| 2.4 GHz | 偶发失效，需重启 | 正常，ch11，实测 26–46 Mbps 内网吞吐 |
| 启动槽 | — | 新槽 `ubi.mtd=rootfs`，启动标志正常 |

**这不是“已断根”的结论。** 本机连续跑满 20 小时 11 分（21 轮巡检）零报错，采集在此
停止，48–72 小时窗口没有取到数据；而这类故障历史上常在跑数小时、遇到特定负载之后
才爆。仓库里 `docs/04-verification.md` 写了判定标准（48–72 小时零报错）与这次仍存在
的反向证据：上游 issue #22583（GL-B3000 同症状）中有开发者称打完同样的中断修正
**仍然复现**。所以本仓库给出的是“一个证据充分的候选修复 + 可复现的构建方法和验证
方法”，不是“上游已盖章的终极答案”。

### 仓库结构

```
.
├── patches/
│   ├── 2815-arm64-dts-qcom-ipq5018-add-wifi-support.patch   # 已修正的 DTS 补丁（drop-in）
│   └── 0001-swap-reo2host-status-irq.diff                   # 相对上游原文的两行改动
├── docs/
│   ├── 01-root-cause.md        # 证据链：为什么是这个中断号
│   ├── 02-build.md             # ImageBuilder 构建（含 FIT 必须重建）
│   ├── 03-flash.md             # 刷入 + 双槽设备不被回滚的三个必备件
│   ├── 04-verification.md      # 怎么证明修好了 / 怎么证明没修好
│   └── 05-pitfalls.md          # 踩过的坑清单
├── scripts/
│   ├── wifi-reo-watchdog.sh    # 设备端兜底：检测到报错就 rebind 2.4G（约 28 s 恢复）
│   ├── ath11k-monitor.sh       # 设备端黑匣子：每 10 min 记一行到 overlay
│   └── monitor-ax3000.ps1      # 本机巡检：只读采集 + 异常告警
├── soak/
│   └── sample-soak.log         # 巡检记录样例（格式说明见 docs/04）
└── .github/workflows/ci.yml    # 脚本语法检查
```

### 怎么用

1. **只想拿改好的固件**：按 `docs/02-build.md` 用 ImageBuilder 出 `factory.ubi`，
   或直接把你手头 24.10 线的 ImageBuilder 里
   `target/linux/qualcommax/patches-6.6/2815-...patch` 换成 `patches/` 下的同名文件后
   `make image`。
2. **刷入**：`docs/03-flash.md`。双槽（rootfs / rootfs_1）设备上，光改 DTB 一定会
   被 U-Boot 回滚，原因和三个必备件都写在那篇里。
3. **验证**：`docs/04-verification.md`。把两个脚本推上设备，等 48–72 小时。

⚠️ 这些文件只针对 Redmi AX3000（RA81）。其它 IPQ5018 机型（MX5500、GL-B3000 等）
也可能命中同一个 bug，但 DTS 文件名、包列表、分区布局都不一样，别直接照搬。

### 参考

- openwrt/openwrt#21264 — 指出中断映射错误的 issue（closed）
- openwrt/openwrt PR #21271 — 修正 `reo2host-status` SPI 并删除轮询绕过补丁
- openwrt/openwrt#22583 — GL-B3000 同症状，修正后**仍有人复现**（open）
- kmiit/Redmi_AX3000_immortalwrt — 本机型 24.10 / 25.12 维护线，25.12 分支已含此修正

### 许可

GPL-2.0（全文见 `LICENSE`），与 OpenWrt 生态一致；`patches/` 里的 DTS 改动本身源自
上游 openwrt PR #21271 的写法，按上游同样条款使用。脚本与文档按现状提供，刷机有
变砖风险，后果自负。

Copyright (C) 2026 yyefree

### 长跑记录与上游反馈

- `docs/06-soak-report.md` — 逐小时巡检数据（21 轮，止于 T+20h11m，采集已停止）
- `docs/07-upstream-comment.md` — 已发布到 openwrt#22583 的数据回帖（原文与链接，
  [issue comment](https://github.com/openwrt/openwrt/issues/22583#issuecomment-6765885787)）

---

## English summary

**Problem.** On Redmi AX3000 (RA81, IPQ5018 + QCN6122) the 2.4 GHz radio periodically
stops accepting clients: association succeeds but the WPA 4-way handshake never
completes, and `dmesg` floods with
`failed to send HAL_REO_CMD_UPDATE_RX_QUEUE cmd, tid N (-105)`.

**Root cause.** In the device tree, the `reo2host-status` interrupt of
`wifi@c000000` is wired to `GIC_SPI 312`, an interrupt line with no source on
IPQ5018 — `/proc/interrupts` shows it stuck at count 0 forever. The REO status ring
is never reaped, the queue backs up and every subsequent REO command fails with
`-105`. Upstream documented this in openwrt#21264 and fixed it in PR #21271 by
swapping SPI 312 ↔ 334 (the latter belonged to `host2tcl-input-ring2`).

**This repo** contains the corrected DTS patch, the ImageBuilder recipe (the FIT
container must be rebuilt or your new DTB is silently discarded), the three
prerequisites that keep a dual-slot device from being rolled back by U-Boot
(`/etc/fw_env.config`, `config@mp02.1`, executable `/etc/init.d/uboot_env`),
and tooling to tell whether the fix actually holds over 48–72 hours.

**Status.** On the author's unit: interrupt now at `GIC-0 366` and counting
(189 events at T+20h), `HAL_REO` errors 0 across 21 hourly samples spanning
20 h 11 m, 2.4 GHz stable, no U-Boot rollback. Data collection stopped there,
so the 48 h / 72 h marks were not reached. Not yet conclusive — openwrt#22583
reports the same symptom persisting for another model after this patch, so treat
it as a well-evidenced candidate fix, not a proven one.

GPL-2.0 licensed (see `LICENSE`), matching the OpenWrt ecosystem.

- `docs/06-soak-report.md` — hourly soak data, 21 samples, collection stopped at T+20h11m
- `docs/07-upstream-comment.md` — data point posted to openwrt#22583
  ([comment link](https://github.com/openwrt/openwrt/issues/22583#issuecomment-6765885787))
