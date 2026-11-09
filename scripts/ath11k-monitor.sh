#!/bin/sh
# ath11k-monitor.sh — 2.4 GHz / REO 长周期取证记录器
#
# 每 10 分钟往日志追加一行，用来判断 "HAL_REO_CMD_UPDATE_RX_QUEUE -105" 是否复发。
# 日志写在 overlay（/root），重启不丢；不要写 /tmp（tmpfs，重启即清空）。
#
# 用法:
#   scp -O ath11k-monitor.sh root@<router>:/usr/bin/
#   ssh root@<router> 'chmod +x /usr/bin/ath11k-monitor.sh'
#   ssh root@<router> 'echo "*/10 * * * * /usr/bin/ath11k-monitor.sh" >> /etc/crontabs/root'
#   ssh root@<router> '/etc/init.d/cron restart'
#
# 输出格式:
#   # ts | HAL_REO | reo_status_irq | ring1 | ifaces | 2.4G_ch | uptime_s
#   2026-11-10 05:00:00 | 0 | 61 | 49034 | 2 | channel 11 | 25414.82

LOG="${ATH11K_SOAK_LOG:-/root/ath11k-soak.log}"
MAX_LINES=400
KEEP_LINES=200

# 找 2.4 GHz 接口: 不依赖 phyN-ap0 这种 rebind 后会变的名字, 按信道 <=14 判定
find_2g_iface() {
	for i in $(iw dev 2>/dev/null | awk '$1 == "Interface" {print $2}'); do
		ch=$(iw dev "$i" info 2>/dev/null | grep -oE 'channel [0-9]+' | head -1 | awk '{print $2}')
		if [ -n "$ch" ] && [ "$ch" -le 14 ]; then
			echo "$i"
			return 0
		fi
	done
	return 1
}

[ -f "$LOG" ] || echo "# ts | HAL_REO | reo_status_irq | ring1 | ifaces | 2.4G_ch | uptime_s" > "$LOG"

TS=$(date '+%F %T')
HAL=$(dmesg 2>/dev/null | grep -c HAL_REO)

IRQ=$(grep reo2host-status /proc/interrupts 2>/dev/null | awk '{print $2}' | head -1)
[ -z "$IRQ" ] && IRQ=none

R1=$(grep reo2host-destination-ring1 /proc/interrupts 2>/dev/null | awk '{print $2}' | head -1)
[ -z "$R1" ] && R1=none

IFACES=$(iw dev 2>/dev/null | grep -c Interface)

IF2G=$(find_2g_iface 2>/dev/null)
if [ -n "$IF2G" ]; then
	CH=$(iw dev "$IF2G" info 2>/dev/null | grep -oE 'channel [0-9]+' | head -1)
else
	CH=DOWN
fi
[ -z "$CH" ] && CH=DOWN

UP=$(cut -d' ' -f1 /proc/uptime)

echo "$TS | $HAL | $IRQ | $R1 | $IFACES | $CH | $UP" >> "$LOG"

LINES=$(wc -l < "$LOG")
if [ "$LINES" -gt "$MAX_LINES" ]; then
	tail -"$KEEP_LINES" "$LOG" > "$LOG.tmp" && mv "$LOG.tmp" "$LOG"
fi
