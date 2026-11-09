# monitor-ax3000.ps1 — 2.4 GHz REO 修复效果巡检（只读）
#
# 每次执行: SSH 采集路由器状态, 追加一行到 soak-status.log; 异常时明确告警。
# 不重启设备、不改任何配置、不刷机。
#
# 用法:
#   $env:AX3000_PASS = '你的 root 密码'
#   .\monitor-ax3000.ps1                       # 默认 192.168.2.1
#   .\monitor-ax3000.ps1 -Router 192.168.2.1
#
# 依赖 Windows 上的 msys2 sshpass/ssh (或自行改 $SP/$SSH 指向别的客户端)。
# 接进 Windows 计划任务即可每小时无人值守跑一次。

param(
    [string]$Router = '192.168.2.1',
    [string]$User = 'root'
)

$SP = 'C:\msys64\usr\bin\sshpass.exe'
$SSH = 'C:\msys64\usr\bin\ssh.exe'
$SSHOPT = @('-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=/dev/null', '-o', 'ConnectTimeout=10')

$PASS = $env:AX3000_PASS
if (-not $PASS) {
    Write-Host 'ERROR: 环境变量 AX3000_PASS 未设置（不提供默认密码）。'
    exit 2
}

$DIR = $PSScriptRoot
if (-not $DIR) { $DIR = (Get-Location).Path }
$LOCALLOG = Join-Path $DIR 'soak-status.log'
$REPORT = Join-Path $DIR 'soak-latest.txt'

# 远端只输出 KEY=VALUE 整行，避免本地用正则剥前缀时误吃（例如 channel 里的 ch）
$remoteCmd = 'HAL=$(dmesg | grep -c HAL_REO); IRQ=$(grep reo2host-status /proc/interrupts | awk "{print \$2}" | head -1); CH=$(iw dev phy1-ap0 info 2>/dev/null | grep -oE "channel [0-9]+" | head -1); IFC=$(iw dev 2>/dev/null | grep -c Interface); UP=$(cut -d" " -f1 /proc/uptime); MTD=$(grep -oE "ubi.mtd=[a-zA-Z0-9_]+" /proc/cmdline); BOOT=$(fw_printenv 2>/dev/null | grep -E "flag_boot_success|flag_last_success|flag_ota_reboot" | tr "\n" ","); echo "HAL=$HAL"; echo "IRQ=$IRQ"; echo "CHANNEL=$CH"; echo "IFC=$IFC"; echo "UP=$UP"; echo "MTD=$MTD"; echo "BOOT=$BOOT"; echo "---TAIL"; tail -6 /root/ath11k-soak.log'

$raw = & $SP -p $PASS $SSH @SSHOPT "$User@$Router" $remoteCmd 2>$null
$rc = $LASTEXITCODE
$now = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

$kv = @{}
$tail = @()
$inTail = $false
foreach ($l in ($raw -split "`n")) {
    $l = $l.Trim()
    if ($l -eq '---TAIL') { $inTail = $true; continue }
    if ($inTail) { if ($l) { $tail += $l }; continue }
    if ($l -match '^([A-Z]+)=(.*)$') { $kv[$Matches[1]] = $Matches[2] }
}

$verdict = '正常'
$alerts = @()
if ($rc -ne 0) {
    $verdict = '无法连接设备'
    $alerts += "SSH 连不上 $Router（路由器可能重启中、断网，或密码被改）"
} else {
    if ($kv['HAL'] -ne '0') { $verdict = 'HAL_REO 报错'; $alerts += "HAL_REO=$($kv['HAL'])（修复前基线 158）→ 根因可能未根治" }
    if ($kv['CHANNEL'] -notmatch '^channel') { if ($verdict -eq '正常') { $verdict = '2.4G 未起来' }; $alerts += "2.4G 接口状态=[$($kv['CHANNEL'])]" }
    if ($kv['IFC'] -ne '2') { if ($verdict -eq '正常') { $verdict = '频段数量异常' }; $alerts += "接口数=$($kv['IFC'])（应为 2）" }
    if ($kv['BOOT'] -notmatch 'flag_boot_success=1') { $alerts += "启动标志异常：$($kv['BOOT'])" }
}

$line = "$now | rc=$rc | HAL=$($kv['HAL']) | IRQ=$($kv['IRQ']) | 2.4G=[$($kv['CHANNEL'])] | IFC=$($kv['IFC']) | UP=$($kv['UP']) | $($kv['MTD']) | $verdict"
Add-Content -LiteralPath $LOCALLOG -Value $line -Encoding utf8

$out = @()
$out += "巡检时间：$now"
$out += "结论：$verdict"
$out += "HAL_REO 报错条数：$($kv['HAL'])（正常 0）"
$out += "reo2host-status 中断计数：$($kv['IRQ'])（修正后应为 GIC-0 366，而不是 344）"
$out += "2.4G：$($kv['CHANNEL'])    接口数：$($kv['IFC'])    开机时长(s)：$($kv['UP'])"
$out += "启动槽：$($kv['MTD'])"
$out += "启动标志：$($kv['BOOT'])"
if ($alerts.Count -gt 0) { $out += '告警：'; foreach ($a in $alerts) { $out += " - $a" } }
if ($tail.Count -gt 0) { $out += ''; $out += '路由器最近黑匣子记录：'; $out += $tail }
$out -join "`r`n" | Set-Content -LiteralPath $REPORT -Encoding utf8
$out -join "`r`n"
