# 03 · 刷入：双槽设备为什么会被 U-Boot 回滚

Redmi AX3000 用 U-Boot 双槽（`rootfs` / `rootfs_1`）+ 一组 `fw_env` 标志位做 A/B 升级。
自编镜像刷进去后**能正常启动、能上网、看起来一切成功**，但只要漏掉下面任何一件，
下次重启（甚至本次重启）就会被 U-Boot 判为失败并回滚到旧槽——你会以为
“刷进去了但没生效”。

## 三个必备件

| # | 必备件 | 缺失后果 |
|---|---|---|
| 1 | `/etc/fw_env.config` | `fw_printenv` 失败 → `/etc/init.d/uboot_env` 首行守卫 `fw_printenv >/dev/null \|\| return 0` 直接返回 → 永不置 `flag_boot_success=1` |
| 2 | FIT 配置节点名 `config@mp02.1` | U-Boot 按节点名取 FIT 配置，名字不符就取不到 |
| 3 | `/etc/init.d/uboot_env` 可执行（755） | `S99uboot_env` 启动时根本不跑 → `flag_ota_reboot` 一直为 1、`flag_boot_success` 从未被定义 |

第 3 条最阴：文件存在、symlink 也在，只是权限 644。`ls -l /etc/rc.d/S99uboot_env`
看得见符号链接，很容易以为“它跑了”。

### 1) fw_env.config

原厂内容（32 字节，末尾带一个空格，别照抄错）：

```
/dev/mtd10 0x0 0x10000 0x20000 
```

放进镜像的 `files/etc/fw_env.config`，构建时随镜像进 rootfs。

### 2) FIT 配置节点名

见 `02-build.md` 第 3 步：`mkits.sh -c 'config@mp02.1'`。
校验：`mkimage -l factory.itb | grep -i configuration` 应显示 `config@mp02.1`。

### 3) uboot_env 可执行

两处都要做，缺一个都不算完成：

- **构建期**：`files/etc/init.d/uboot_env` 在源目录里就必须是 755 —— OpenWrt 的
  `FILES=` 会保留权限位，644 会被原样带进镜像。
- **运行期**（已经刷进去了来不及改镜像时）：

```sh
chmod +x /etc/init.d/uboot_env
/etc/init.d/uboot_env boot    # 注意：是 boot 子命令，不是 start
fw_printenv | grep flag_
```

`rc.common` 的 `start` 只跑 `start)` 段，而置标志的代码在 `boot)` 段，所以必须
显式 `boot`。正确结果：

```
flag_last_success=0
flag_ota_reboot=0
flag_boot_success=1
```

## 刷入流程

本机型**只吃 `factory.ubi`**（`mi_dualboot_check_image` 只认前三字节 `UBI`，
`sysupgrade.bin` 会被直接拒绝）。

```sh
# 本地：先校验
head -c 3 factory.ubi            # 必须输出 UBI
sha256sum factory.ubi

# 上传（设备没有 sftp-server，必须 -O）
scp -O factory.ubi root@192.168.2.1:/tmp/

# 设备端：再校验一次
sha256sum /tmp/factory.ubi
head -c 3 /tmp/factory.ubi

# 刷（会立即断 SSH，属正常）
nohup sh -c "sleep 3; sysupgrade -v /tmp/factory.ubi" >/tmp/up.log 2>&1 &
```

刷之前建议先备份配置：`sysupgrade -b /tmp/cfg-backup.tgz`，并把它取下本地。
本次实测配置（SSID/密码/防火墙）完整保留，靠的是 `mi_dualboot.sh` 里的
`nand_restore_config`。

## 刷后确认（三行）

```sh
grep -o 'ubi.mtd=[a-z_0-9]*' /proc/cmdline   # 应切到目标槽（如 ubi.mtd=rootfs）
grep reo2host-status /proc/interrupts        # 应为 GIC-0 366（是 344 就说明跑的还是旧 DTB）
dmesg | grep -c HAL_REO                      # 应为 0
```

## 刷前清理（容易踩）

如果之前手工 `ubiattach` 过目标 mtd 做过取证，`ubiformat` 可能失败。先 detach：

```sh
ubidetach -d 2     # 卷号按 ubi list / ls /dev/ubi* 实际值
```

## 救砖

- 旧固件仍在另一个槽（`mtd19 rootfs_1`），U-Boot 按 `flag_last_success` 自动回滚；
  最坏情况从串口/网线进 U-Boot 手动切槽即可。
- 兜底工具：小米 MIWIFIRepairTool（网线直连）。
- **不要在 `/overlay`（11 MB，仅 10.3 MB 可用）里放大文件**，也别把 factory.ubi
  （19 MB）往那儿拷。
