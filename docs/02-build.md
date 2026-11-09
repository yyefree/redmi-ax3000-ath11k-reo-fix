# 02 · 构建：用 ImageBuilder 只换 DTB

本仓库的做法是**不编译完整固件**，只在官方 ImageBuilder 产物里换掉 DTB、重建 FIT，
再打回 `factory.ubi`。好处是 20 分钟能出一个镜像，且与现用固件同线（kernel 6.6.137）。

## 0. 前置

- ImageBuilder（本机用的是 kmiit release
  `ci-redmi_ax3000-24.10-20260514-122123-UTC` 的
  `immortalwrt-imagebuilder-qualcommax-ipq50xx.Linux-x86_64.tar.zst`，78 MB）
- 该 release 附带的 `config.buildinfo`（包清单来源）
- `dtc`（设备树编译器）、`libdeflate-gzip`、`mkimage`（ImageBuilder 的
  `staging_dir/host/bin/` 里自带后两个，`dtc` 需要自己装）

## 1. 改 DTS 补丁（推荐路径）

把仓库里的 `patches/2815-arm64-dts-qcom-ipq5018-add-wifi-support.patch` 覆盖到
ImageBuilder 的同一路径：

```sh
cp patches/2815-...patch \
   target/linux/qualcommax/patches-6.6/2815-arm64-dts-qcom-ipq5018-add-wifi-support.patch
```

改动本身只有两行（见 `patches/0001-swap-reo2host-status-irq.diff`）：

```
 +  <GIC_SPI 312 ...>  →  +  <GIC_SPI 334 ...>   # reo2host-status
 +  <GIC_SPI 334 ...>  →  +  <GIC_SPI 312 ...>   # host2tcl-input-ring2
```

> ImageBuilder 用的是预编译 kernel，通常**不会**因为改 `patches-6.6` 而重新编 DTS，
> 所以实际流程是：先按下面第 2 步直接改已经生成的 DTB。补丁文件放在仓库里是为了
> 让“源码层面到底改了什么”有据可查，也方便你在自己的 buildroot 里复现。

## 2. 直接改 DTB（ImageBuilder 路线实际用的）

```sh
# 反编译
dtc -I dtb -O dts -o /tmp/orig.dts \
  build_dir/target-aarch64_cortex-a53_musl/linux-qualcommax_ipq50xx/image-ipq5000-ax3000.dtb
# 只切 wifi@c000000 节点，改完重编译
dtc -I dts -O dtb -o image-ipq5000-ax3000.dtb /tmp/fixed.dts
```

要点（踩过）：

- **不要用全局正则替换**。`GIC_SPI 312` / `334` 在别的节点里也有，一改就误伤。
  必须按 `wifi@c000000 {` 到匹配的 `};` 切片再改。
- 反编译后 `interrupt-names` 会被压成一整个 `\0` 分隔的长串（52 个名字），
  按名字定位时要注意：**`interrupts` 数组是扁平 cell 序列，每条中断 3 个 cell**。
  本机型里 `reo2host-status` 是名字列表第 25 项（0-based 24）→ 对应 cell 下标 73；
  `host2tcl-input-ring2` 是第 47 项（0-based 46）→ cell 下标 139。
  换算关系：`cell_idx = 3 * name_idx`。
- 改完用 `dtc` 再反编译一遍，逐字段对比原始，确认只有这一对值变了。
  成品 DTB 19,498 B，md5 `e40117860e484eb58e8fd32afb6ebf16`。

## 3. FIT 必须重建（否则前功尽弃）

`redmi_ax3000-uImage.itb` 里打包着 DTB。只改 `image-ipq5000-ax3000.dtb` 而不重建
FIT，`make image` 会复用旧的 `.itb`，你刷进去的还是原始 DTB —— **而且看起来“刷成功了”**。
这是本项目最贵的一个坑。

```sh
staging_dir/host/bin/libdeflate-gzip -f -12 -c \
  build_dir/.../linux-qualcommax_ipq50xx/Image > /tmp/kImage.gz

./scripts/mkits.sh -A arm64 -C gzip -a 0x41000000 -e 0x41000000 \
  -v 6.6.137 -k /tmp/kImage.gz -D redmi_ax3000 \
  -d "$(pwd)/build_dir/.../image-ipq5000-ax3000.dtb" \
  -c 'config@mp02.1' -o /tmp/new.its

staging_dir/host/bin/mkimage -f /tmp/new.its /tmp/new.itb
# 覆盖 build_dir 里的 itb 与 its，再 make image
```

- `mkits.sh` 在 `scripts/`，**不在** `staging_dir/host/bin/`。
- 配置节点名**必须是 `config@mp02.1`**（`ipq50xx.mk` 里 `DEVICE_DTS_CONFIG` 定的）。
  手搓成 `config@1` 会让 U-Boot 找不到配置。
- 本机上 `staging_dir/host/bin/` 里**没有 `dumpimage`**，看 FIT 头信息用
  `mkimage -l`。

## 4. 包列表：两个包名不存在

照搬整机 208 个包会报 `Error 255`，真因是：

```
Unknown package 'ath11k-firmware-ipq5018'
Unknown package 'ath11k-firmware-qcn6122'
```

这个 feed 里没有这两个包名。用排除法：

```sh
make image PROFILE=redmi_ax3000 \
  PACKAGES="$(cat /tmp/pkgs.txt) -ath11k-firmware-ipq5018 -ath11k-firmware-qcn6122" \
  FILES=files
```

ath11k 固件二进制（`WLAN.HK.2.7.0.1-01744`）从路由器 `/lib/firmware/` 原样导出来，
放进 `files/lib/firmware/IPQ5018/` 与 `files/lib/firmware/ath11k/IPQ5018/hw1.0/`，
靠 `FILES=` 带进镜像。

## 5. 产物自检（四项，缺一不可）

| 检查 | 期望 |
|---|---|
| FIT md5 | `699406cea2b56afaa980d32973843328`（本机 v2/v3） |
| FIT 内嵌 DTB | 19,498 B，md5 `e40117860e484eb58e8fd32afb6ebf16` |
| `mkimage -l` | `Default Configuration: 'config@mp02.1'` |
| rootfs squashfs | 含 `etc/fw_env.config`、`etc/init.d/uboot_env`（755） |

镜像里的 FIT 是**跨 LEB 存放**的，直接按字节 offset 切出来算 md5 一定对不上
（实测得到 `b870a0ab…`）。必须按 UBI 的 EC/VID 头重组卷再校验：

- EC 头里 `vid_off` / `data_off` 在本机型放在偏移 **16 / 20** 字节处（不是常见的 8/12）
- 卷按 LEB 顺序拼接后才是 FIT 的连续字节

参考实现思路：`ubireader`（python），或自己按上述偏移解析。

## 6. 为什么要粘在 24.10 线上

kmiit 的 `redmi_ax3000-25.12` 分支（kernel 6.12 / mac80211 6.18.26）**已经带**这处
DTS 修正，但它没有 CI 产物（release 页面只有 24.10 目录），要走这条线必须自编整棵
buildroot 并跨大版本升级。本方案刻意保持 24.10 同线：改动面最小，出问题能原样回滚。
