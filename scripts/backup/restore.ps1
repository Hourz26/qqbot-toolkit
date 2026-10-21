# ============================================================
# AstrBot 数据还原（从本机备份归档恢复回云端）
#
# 用法：
#   powershell -NoProfile -ExecutionPolicy Bypass -File restore.ps1 -Archive "D:\qqbot-backups\astrbot-data-20261020-142648.tar.gz"
#   powershell ... -Archive "..." -WhatIf      # 只看会做什么，不动服务器
#
# 步骤：
#   1) 上传归档到服务器
#   2) 服务器端把当前 data 整目录另存一份（restore-backup-<ts>）
#   3) 停 astrbot 容器
#   4) 解包覆盖，_hotbak/*.db 归位到原路径
#   5) 启动容器 + 依赖恢复脚本
# ============================================================
param(
    [Parameter(Mandatory = $true)][string]$Archive,
    [string]$SshHost = 'aliyun',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$sshExe = 'C:\WINDOWS\System32\OpenSSH\ssh.exe'
$scpExe = 'C:\WINDOWS\System32\OpenSSH\scp.exe'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'

function Log($msg) { Write-Host ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg) }

if (-not (Test-Path $Archive)) { throw "归档不存在: $Archive" }
$Archive = (Resolve-Path $Archive).Path
$size = (Get-Item $Archive).Length
Log "归档: $Archive ($([math]::Round($size/1KB,1)) KB)"

Log "本地校验..."
$list = & tar -tzf $Archive 2>&1
if ($LASTEXITCODE -ne 0) { throw "归档损坏" }
foreach ($m in @('./_hotbak/data_v4.db', './cmd_config.json')) {
    if (-not ($list -contains $m)) { throw "归档缺少 $m，拒绝还原" }
}
Log "校验通过（$($list.Count) 个条目）"

if ($WhatIf) {
    Log "WhatIf 模式：不做任何修改。"
    Log "将执行：scp -> /root/_restore.tar.gz；备份当前 data -> /root/restore-backup-$stamp；"
    Log "        停容器；解包覆盖 /opt/astrbot/data；_hotbak 归位；启容器；补依赖"
    exit 0
}

# 1) 上传
$remoteTar = "/root/_restore-$stamp.tar.gz"
Log "上传到 $remoteTar ..."
& $scpExe -o BatchMode=yes -o ConnectTimeout=20 $Archive "${SshHost}:$remoteTar"
if ($LASTEXITCODE -ne 0) { throw "上传失败" }

# 2~4) 服务器端还原
Log "服务器端还原中（会停容器几秒）..."
$script = @'
set -uo pipefail
STAMP="__STAMP__"
TAR="__TAR__"
DATA=/opt/astrbot/data
SAFE=/root/restore-backup-$STAMP

echo "  [1/6] 保存当前状态 -> $SAFE"
mkdir -p "$SAFE"
cp -a "$DATA"/. "$SAFE"/ 2>/dev/null

echo "  [2/6] 停容器"
cd /opt/astrbot && docker compose stop astrbot >/dev/null 2>&1

echo "  [3/6] 解包"
STAGE=/root/_restore_stage_$STAMP
rm -rf "$STAGE"; mkdir -p "$STAGE"
tar -xzf "$TAR" -C "$STAGE" || { echo "解包失败"; exit 1; }

echo "  [4/6] 覆盖数据（_hotbak/*.db 归位）"
# 先拷非 db 内容
rsync -a --exclude='_hotbak' "$STAGE"/ "$DATA"/ 2>/dev/null || cp -a "$STAGE"/. "$DATA"/
# 再把一致性快照里的 db 放回原路径
if [ -d "$STAGE/_hotbak" ]; then
  cd "$STAGE/_hotbak" || exit 1
  find . -name '*.db' | while read -r f; do
    rel=${f#./}
    dest="$DATA/$rel"
    mkdir -p "$(dirname "$dest")"
    cp -a "$f" "$dest"
    echo "    restored $rel"
  done
  cd /
fi
rm -rf "$DATA/_hotbak"

echo "  [5/6] 启容器"
cd /opt/astrbot && docker compose start astrbot >/dev/null 2>&1
sleep 12
docker ps --format '{{.Names}} {{.Status}}'

echo "  [6/6] 补插件依赖"
[ -f /root/restore-deps.sh ] && bash /root/restore-deps.sh 2>&1 | tail -2

rm -rf "$STAGE" "$TAR"
echo "RESTORE_OK"
'@
$script = $script.Replace('__STAMP__', $stamp).Replace('__TAR__', $remoteTar)

$tmp = Join-Path $env:TEMP "restore-$stamp.sh"
[System.IO.File]::WriteAllText($tmp, $script, (New-Object System.Text.UTF8Encoding($false)))
$remoteSh = "/root/_restore-$stamp.sh"
& $scpExe -o BatchMode=yes $tmp "${SshHost}:$remoteSh" | Out-Null

$out = & $sshExe -o BatchMode=yes -o ConnectTimeout=20 $SshHost "bash $remoteSh" 2>&1
$out | ForEach-Object { Log "  $_" }
$ok = $out | Where-Object { $_ -match 'RESTORE_OK' }
Remove-Item $tmp -Force -ErrorAction SilentlyContinue

if (-not $ok) { throw "服务器端还原未报告成功，请检查上面输出" }

Log "等待 AstrBot 就绪（约 60s）..."
Start-Sleep -Seconds 55
$health = & $sshExe -o BatchMode=yes $SshHost "curl -s -o /dev/null -w '%{http_code}' -m 8 http://127.0.0.1:6185/ ; echo; systemctl is-active napcat; ss -tn state established '( sport = :6199 )' | tail -n +2 | wc -l" 2>&1
$health | ForEach-Object { Log "  $_" }

Log "=== 还原完成 ==="
Log "回滚方式：ssh $SshHost 'cd /opt/astrbot && docker compose stop astrbot && rm -rf data && cp -a /root/restore-backup-$stamp data && docker compose start astrbot'"
