#!/usr/bin/env python3
"""对 patches/ 里那份 DTS 补丁做结构性校验：确认中断数组的第 25 项
(reo2host-status) 是 SPI 334，第 47 项 (host2tcl-input-ring2) 是 SPI 312。

用法: python tools/verify-patch.py [patchfile]
退出码 0 = 通过，1 = 不通过（CI 用）。
"""
import io
import re
import sys

PATH = sys.argv[1] if len(sys.argv) > 1 else (
    "patches/2815-arm64-dts-qcom-ipq5018-add-wifi-support.patch"
)

RE_SPI = re.compile(r"GIC_SPI (\d+) IRQ_TYPE_EDGE_RISING>")

REO2HOST_INDEX = 24      # 0-based；interrupt-names 第 25 项
HOST2TCL_INDEX = 46      # 0-based；interrupt-names 第 47 项

lines = io.open(PATH, encoding="utf-8").read().split("\n")

start = None
for i, l in enumerate(lines):
    if "wifi@c000000" in l:
        start = i
        break
if start is None:
    sys.exit("FAIL: 找不到 wifi@c000000 节点")

spis = []
for l in lines[start:]:
    m = RE_SPI.search(l)
    if m:
        spis.append(int(m.group(1)))
    if l.strip().startswith("+") and "interrupt-names" in l and spis:
        break

if len(spis) < 47:
    sys.exit("FAIL: 中断数组只解析到 %d 项，预期 >= 47" % len(spis))

ok = True
if spis[REO2HOST_INDEX] != 334:
    print("FAIL: 第 %d 项(reo2host-status) = SPI %d，应为 334"
          % (REO2HOST_INDEX + 1, spis[REO2HOST_INDEX]))
    ok = False
else:
    print("OK: 第 %d 项(reo2host-status) = SPI 334" % (REO2HOST_INDEX + 1))

if spis[HOST2TCL_INDEX] != 312:
    print("FAIL: 第 %d 项(host2tcl-input-ring2) = SPI %d，应为 312"
          % (HOST2TCL_INDEX + 1, spis[HOST2TCL_INDEX]))
    ok = False
else:
    print("OK: 第 %d 项(host2tcl-input-ring2) = SPI 312" % (HOST2TCL_INDEX + 1))

print("中断条目总数: %d" % len(spis))
sys.exit(0 if ok else 1)
