#!/bin/sh
# wifi-reo-watchdog.sh — 2.4 GHz REO 故障兜底自愈
#
# 机型: Redmi AX3000 (IPQ5018 + QCN6122) / ImmortalWrt 24.10
# 用途: dmesg 里 "HAL_REO_CMD_UPDATE_RX_QUEUE cmd, tid X (-105)" 计数增长时自动恢复
# 原理: 计数增量 >= THRESHOLD -> sysfs unbind/bind c000000.wifi -> wifi up radio0
#       (只动 2.4G, 5G 的 phy 和客户端不受影响; 实测约 28 秒恢复)
#
# 安装:
#   scp -O wifi-reo-watchdog.sh root@<router>:/usr/bin/
#   ssh root@<router> 'chmod +x /usr/bin/wifi-reo-watchdog.sh'
#   ssh root@<router> 'echo "*/5 * * * * /usr/bin/wifi-reo-watchdog.sh" >> /etc/crontabs/root'
#   ssh root@<router> '/etc/init.d/cron restart'
# 卸载: 删掉 /etc/crontabs/root 里对应行, 再 /etc/init.d/cron restart
#
# 注意: 这是兜底/保险, 不是修复本身。触发一次就会断 2.4G 约半分钟。
#       正常情况下它不写日志, 判断它是否在跑要看 STATE 文件的 mtime。

DEV=c000000.wifi
DEV_PATH=/sys/devices/platform/soc@0/c000000.wifi
RADIO=radio0
STATE=/tmp/wifi-reo-watchdog.state
LAST_ACTION=/tmp/wifi-reo-watchdog.last
LOCK=/var/lock/wifi-reo-watchdog.lock
LOG="${WIFI_REO_WD_LOG:-/var/log/wifi-reo-watchdog.log}"
THRESHOLD=3      # 一次至少新增几条报错才动作
COOLDOWN=1800    # 两次动作的最小间隔(秒), 避免重建风暴

# 可选: 只认某个 SSID 的 AP 算"起来了"。留空 = 任意 ssid 均可。
AP_SSID="${WIFI_REO_WD_SSID:-}"

log() {
	echo "$(date '+%Y-%m-%d %H:%M:%S') $*" >> "$LOG"
}

# 日志超过 256KB 滚动一次
if [ -f "$LOG" ] && [ "$(wc -c < "$LOG")" -gt 262144 ]; then
	mv "$LOG" "$LOG.old"
fi

# 互斥, 防止 cron 叠加
exec 9>"$LOCK"
flock -n 9 || exit 0

ap_up() {
	if [ -n "$AP_SSID" ]; then
		iw dev 2>/dev/null | grep -qE "ssid ${AP_SSID}$"
	else
		iw dev 2>/dev/null | grep -q 'ssid '
	fi
}

# 等 AP 起来, 最多 8*5 = 40 秒
wait_ap() {
	i=0
	while [ "$i" -lt 8 ]; do
		ap_up && return 0
		sleep 5
		i=$((i + 1))
	done
	ap_up
}

cnt=$(dmesg 2>/dev/null | grep -c HAL_REO)

if [ ! -f "$STATE" ]; then
	echo "$cnt" > "$STATE"
	log "baseline HAL_REO=$cnt"
	exit 0
fi

prev=$(cat "$STATE" 2>/dev/null)
case "$prev" in ''|*[!0-9]*) prev=0 ;; esac
echo "$cnt" > "$STATE"

# 计数回落(重启后 dmesg 清空) 只更新基线
[ "$cnt" -le "$prev" ] && exit 0

delta=$((cnt - prev))
[ "$delta" -lt "$THRESHOLD" ] && exit 0

now=$(date +%s)
if [ -f "$LAST_ACTION" ]; then
	last=$(cat "$LAST_ACTION" 2>/dev/null)
	case "$last" in ''|*[!0-9]*) last=0 ;; esac
	if [ $((now - last)) -lt "$COOLDOWN" ]; then
		log "detected +$delta (total $cnt) but cooldown $((now - last))s, skip"
		exit 0
	fi
fi
echo "$now" > "$LAST_ACTION"

log "detected +$delta HAL_REO (total $cnt), recovering 2.4G"

drv=$(readlink -f "$DEV_PATH/driver")
if [ -z "$drv" ] || [ ! -d "$drv" ]; then
	log "ERROR: $DEV_PATH/driver missing, abort"
	exit 1
fi

if echo "$DEV" > "$drv/unbind"; then log "unbind ok"; else log "unbind FAILED"; fi
sleep 3
if echo "$DEV" > "$drv/bind"; then log "bind ok"; else log "bind FAILED"; fi
sleep 8

# 只重启 2.4G 射频
wifi up "$RADIO" >/dev/null 2>&1

if wait_ap; then
	log "recovered, 2.4G AP up"
	exit 0
fi

log "radio0 still down, fallback full wifi up"
wifi up >/dev/null 2>&1

if wait_ap; then
	log "recovered via full wifi up, 2.4G AP up"
	exit 0
fi

log "FAILED: 2.4G still down after rebind, manual power cycle may be needed"
exit 1
