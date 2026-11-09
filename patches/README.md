# patches/

## `2815-arm64-dts-qcom-ipq5018-add-wifi-support.patch`

这是 kmiit `redmi_ax3000-24.10` 分支里同一个文件的**已修正版本**（drop-in 替换）：

```
target/linux/qualcommax/patches-6.6/2815-arm64-dts-qcom-ipq5018-add-wifi-support.patch
```

相对上游原文只改了两行（见下），作用是把 `wifi@c000000` 的 `reo2host-status`
接到真正有中断源的 SPI 334，并把原本占 334 的 `host2tcl-input-ring2` 让出来接 312。

## `0001-swap-reo2host-status-irq.diff`

可审阅的两行 diff，方便你确认“到底改了什么”。可以直接 `git apply` 到
kmiit 24.10 树上，也可以用 `patch -p1`：

```sh
cd <kmiit buildroot>
git apply /path/to/0001-swap-reo2host-status-irq.diff
```

内容等价于：

```
-<GIC_SPI 312 IRQ_TYPE_EDGE_RISING>,   # reo2host-status      → 334
-<GIC_SPI 334 IRQ_TYPE_EDGE_RISING>,   # host2tcl-input-ring2 → 312
```

## 为什么是“互换”而不是“改一个”

如果只把 `reo2host-status` 改成 334，334 这根线会被两个设备同时占用（中断号冲突），
`host2tcl` 路径会跟着坏。上游 PR #21271 是成对交换的，本仓库保持与上游一致。

## 校验

改完后在设备上：

```
$ grep reo2host-status /proc/interrupts
 52:  61  0  GIC-0 366 Edge  reo2host-status      # 366 = 32 + 334，且计数会增长
```

旧映射下是 `GIC-0 344`（= 32 + 312）且计数恒 0。

**别指望在这里看到 `host2tcl-input-ring2`。** 本机实测它根本不出现
（该环在当前配置下没有被 driver 请求中断），所以“找不到 344 那一行”不是失败信号。
判据只有一个：`reo2host-status` 落在 **366** 且计数从 0 变成非 0。
