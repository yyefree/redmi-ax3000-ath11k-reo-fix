# 05 · 踩坑清单

按“代价从大到小”排。每条都是实测撞过的，不是听说。

## 会让你误判成功的

1. **改了 DTB 但没重建 FIT** —— `make image` 复用旧的 `redmi_ax3000-uImage.itb`，
   里面还是原始 DTB。镜像能刷、能启动、能上网，`/proc/interrupts` 里却仍旧是
   `GIC-0 344`。必须按 `02-build.md` 第 3 步手工重建 FIT 并覆盖 `build_dir` 里的
   `.itb` / `.its`。
2. **“刷完当场没报错”当成功** —— 该故障常在跑数小时后、特定负载下才出现。
   本次修复后 7 小时才等到第一次中断计数变化，12 小时内也没有任何报错；
   这类指标只有小时级的连续采样有意义。
3. **漏了 `uboot_env` 权限** —— 文件在、symlink 在、只是 644。启动时 `S99uboot_env`
   静默不执行，`flag_ota_reboot` 保持 1、`flag_boot_success` 从未被写。
   本次就是这样“成功启动一次，但下次重启必回滚”。
4. **用 `start` 而不是 `boot`** —— `/etc/init.d/uboot_env start` 只跑 `start)` 段，
   置标志的代码在 `boot)` 段。正确：`/etc/init.d/uboot_env boot`。
5. **全局正则改 DTS** —— `GIC_SPI 312` / `334` 在别的节点也出现，全局替换会误伤。
   必须按 `wifi@c000000 { ... };` 切片。

## 构建

6. **包名不存在**：该 feed 没有 `ath11k-firmware-ipq5018` / `ath11k-firmware-qcn6122`，
   照搬整机包清单会 `Error 255`。用 `-包名` 排除，固件二进制从设备导出后走 `FILES=`。
7. **`mkits.sh` 在 `scripts/`**，不在 `staging_dir/host/bin/`。
8. **没有 `dumpimage`**：`staging_dir/host/bin/` 里只有 `mkimage`。看 FIT 头用
   `mkimage -l`。
9. **FIT 配置节点名**：必须是 `config@mp02.1`（`ipq50xx.mk` 的 `DEVICE_DTS_CONFIG`），
   写成 `config@1` U-Boot 取不到配置。
10. **UBI 里的 FIT 跨 LEB**：按字节 offset 切出来算 md5 一定不对（实测得
    `b870a0ab…`）。要按 EC/VID 头重组卷；本机型 `vid_off` / `data_off` 在 EC 头偏移
    **16 / 20** 字节（不是常见的 8 / 12）。
11. **反编译后的 `interrupt-names`** 是一个 `\0` 分隔长串，按文本搜索名字搜不到，
    要按 cell 下标换算：`cell_idx = 3 * name_idx`。

## 传输与刷机

12. **`Invoke-WebRequest` 拉 CDN 大文件必断**（`Received an unexpected EOF`）。
    用 `curl -L -C -` 循环续传到文件大小达标，再比 sha256。
13. **`scp` 必须 `-O`**：设备没有 sftp-server，不加会报协议不支持。
14. **`ubiformat` 前先 `ubidetach`**：之前手工 attach 过的卷不 detach 会失败。
15. **`sysupgrade.bin` 会被拒**：`mi_dualboot_check_image` 只接受前三字节 `UBI` 的
    `factory.ubi`。
16. **`/overlay` 只有 ~10 MB 可用**：不要往里放镜像或大文件；`/tmp` 是 tmpfs，
    重启全丢，要留证据就写 `/root`（overlay）。

## 平台/工具

17. **Windows 上没有裸 `curl` / `ping` 简写**：写全路径 `C:\Windows\System32\curl.exe`。
18. **PowerShell 单条命令前台 ~15 s 会转后台**：长命令需要取回输出时注意用
    `TaskOutput` 等价机制。
19. **`$HOST` 是 PowerShell 只读自动变量**，做变量名会炸；用 `$RHOST` 之类。
20. **`-replace` 剥前缀会误吃**：`channel` 里的 `ch` 被剥掉导致解析成 `annel`。
    远端直接输出整行 `KEY=VALUE`、本地按 `^([A-Z]+)=(.*)$` 解析更稳。
21. **驱动目录名**：`/sys/bus/platform/drivers/ath11k`，不是 `ath11k_ahb`。
22. **`ubus call network.wireless up` 不顶用**：接口建出来但 hostapd 30 s 起不来；
    `wifi up`（不带参数）会重建全部频段导致 SSH 必断。只重启一个频段用
    `wifi up radio0`。
23. **rebind 后 phy 序号会变**（phy1 → phy2 → phy5），脚本里别硬编码 `phy1-ap0`，
    按 channel ≤ 14 自动识别 2.4 GHz 接口。
