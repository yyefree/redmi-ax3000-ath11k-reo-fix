# 08 · 2026-11-11 开机无线全失：QCN6122 固件异常（与 REO 修复无关）

**一句话**：刷机后 T+34h 的一次重启开始，每次开机第 32 秒 5G 侧 QCN6122 固件都会抛异常，
`remoteproc` 恢复后 WMI 握手超时，两个射频都没起来 —— 无线全无、`/sys/class/ieee80211` 为空。
这不是本仓库要修的 `HAL_REO -105` 问题；`HAL_REO=0` 在这里没有诊断意义（固件根本没启动）。

## 现象（复现 3 次：2 次开机 + 1 次模块重载）

```
[32.19] ath11k c000000.wifi : chip_id ... board_id 0x24      ← 2.4G 侧读到芯片信息
[32.44] ath11k wifi1@c000000: chip_id ... board_id 0x60      ← 5G 侧也读到了
[32.83] qcom-q6-mpd cd00000.remoteproc: fatal error received: err_smem_ver.2.1:
         QC Image Version : WLAN.HK.2.7.0.1-01744
         Image Variant    : 5018.wlanfw2.map_spr_spr_evalQ
         :Excep :0 Exception detected  PName:wlan1  TName:WLAN RT0
         PC : 0xd0261f60    BADVA : <垃圾值>   LR : 0xd0165d20
[32.87] remoteproc0: crash detected, type fatal error → handling crash #1 → recovering
[32.93] Direct firmware load for qcn6122/m3_fw.mdt failed (-2) → sysfs fallback
[33.11] remoteproc0: remote processor is now up
[37.69] ath11k wifi1@c000000: failed to receive wmi unified ready event: -110
[37.69] ath11k wifi1@c000000: failed to start core: -110        ← 5G 核启动失败
[42.73] ath11k c000000.wifi : failed to wait wlan config request: -110
[42.75] ath11k c000000.wifi : failed to start firmware: -110    ← 2.4G 随之失败
```

三次的 PC 完全相同（`0xd0261f60`），只有 `BADVA` 不同（`0xef2d6969` / `0xe8055555`）。
**同一段代码 + 每次不同的垃圾地址 = 某次读取拿到无效值后被当地址用掉**，即确定性缺陷路径，
不是随机抖动。

## 已排除的方向

| 方向 | 证据 | 结论 |
|---|---|---|
| 固件文件损坏 | 设备上 36 个 `/lib/firmware` 文件 md5 全部与当初从正常路由器导出的包一致（`q6_fw.mdt 67a213db…`、`cal-ahb…bin 4128fd37…`、两个 `board-2.bin` 均一致） | 排除 |
| 本仓库的中断互换补丁 | 补丁只改 `wifi@c000000`（2.4G 节点）的 `reo2host-status` / `host2tcl-input-ring2`；崩溃发生在 5G 侧的 `wlan1` 固件 | 无关 |
| `qcn6122/m3_fw.mdt` 缺失 | 崩溃（32.83）先发生，缺失告警（32.93）在恢复流程里才出现；且该文件在**能正常工作的那次开机**同样不存在（设备 `/lib/firmware`、只读 `/rom/lib/firmware`、导出包三处均只有 `IPQ5018/m3_fw.*`） | 是后果，不是起因 |
| 校准数据 | `cal-ahb-soc@0:wifi1@c000000.bin`（131,072 B）头结构正常、非全 0 非全 0xFF；`crash` / `crash_syslog` 两个 mtd 分区全 0xFF（固件未写转储） | 无明显异常 |
| NAND / 文件系统 | `ubi0: good PEBs 288, bad 0, corrupted 0`，squashfs 只读挂载无报错 | 排除 |
| 模块重载可恢复 | `rmmod ath11k_ahb; modprobe ath11k_ahb` 重跑 init，停在 `FW memory mode: 2` 后 40 秒无进展，无 phy | 无效 |

## 尚未排除 / 值得查

1. **QCN6122 侧硬件初始化失败**（最大嫌疑）：固件在标定/PLL 阶段读到无效值而崩溃。设备
   刚随人从上海搬到淄博，伴随一次原因不明的重启（11-08 11:08 前后，无 pstore、无崩溃转储），
   供电、连接器、模块焊接都可能受影响。
2. **DTS 里 reserved memory 重叠**：`tz_apps@4a400000` 与 `bootloader@4a800000` 重叠 2 MB
   （`OF: reserved mem: OVERLAP DETECTED!`），每次开机都报。它与 Q6 的 `smem@4ab00000`
   相邻，属“可疑但未证实”。
3. **温度不可读**：`thermal_zone0 = -270000`、`thermal_zone1 = 0`，传感器无有效读数，
   无法用它判断散热。

## 若需要下一步（按代价排序）

1. **物理层**：换原装电源适配器、直插墙插（不经排插/USB 供电）、确认机壳与天线座无松动，
   再断电 10 秒上电。这是唯一还没做且成本最低的一条。
2. **重刷同槽 v2**（擦除重写 rootfs）：用于排除“NAND 上某块内容读出来不对”这种小概率，
   但代价是又一次刷机。注意 `rootfs_1`(mtd19) 当前只剩一个 kernel 卷（`/dev/ubi1_0`，
   无 rootfs 卷），**没有可回退的完整旧系统**，所以别指望 U-Boot 回滚救场。
3. **判定硬件**：若换电源 + 重刷后仍每次 32 秒准点崩溃，基本可判为 QCN6122 侧硬件问题，
   软件手段到顶。

## 记录方式

出现这类“无线全无”时，按下面顺序取证即可复现本页结论：

```
cat /proc/uptime                     # 确认是否重启过、崩了多久
ls /sys/class/ieee80211/             # 空 = 一个 phy 都没有
iw dev                               # 空
dmesg | grep -A14 err_smem_ver       # 拿到 Exception / PC / BADVA
dmesg | grep -E 'failed to (start|receive)'   # 哪些核失败
find /lib/firmware -type f -exec md5sum {} \; # 与已知good包对比
```
