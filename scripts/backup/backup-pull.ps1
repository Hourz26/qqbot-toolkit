# ============================================================
# AstrBot 云端数据备份 —— 本机拉取端
#   1) 触发服务器端热备份（SQLite backup API，不停服）
#   2) scp 拉到本机
#   3) 本地校验（tar 可读 + 大小合理）
#   4) 轮转旧备份
# 用法：powershell -NoProfile -ExecutionPolicy Bypass -File backup-pull.ps1
# 参数：-Keep 30   本地保留份数
# ============================================================
param(
    [string]$SshHost   = 'aliyun',
    [string]$LocalDir  = 'D:\qqbot-backups',
    [int]   $Keep      = 30
)

$ErrorActionPreference = 'Stop'
$sshExe = 'C:\WINDOWS\System32\OpenSSH\ssh.exe'
$scpExe = 'C:\WINDOWS\System32\OpenSSH\scp.exe'
$logDir = Join-Path $LocalDir 'logs'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmmss'

New-Item -ItemType Directory -Force -Path $LocalDir, $logDir | Out-Null
$logFile = Join-Path $logDir "backup-$stamp.log"

function Log($msg) {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line
    Add-Content -Path $logFile -Value $line -Encoding UTF8
}

try {
    Log "=== 开始备份 $stamp ==="

    # ---------- 1) 服务器端热备份 ----------
    Log "触发服务器端热备份..."
    $out = & $sshExe -o BatchMode=yes -o ConnectTimeout=20 $SshHost 'bash /root/backup-astrbot.sh' 2>&1
    $out | ForEach-Object { Log "  remote| $_" }
    if ($LASTEXITCODE -ne 0) { throw "服务器端备份脚本失败 (exit $LASTEXITCODE)" }

    $resultLine = ($out | Where-Object { $_ -match '^RESULT:' } | Select-Object -Last 1)
    if (-not $resultLine) { throw "未拿到 RESULT 行，无法确定归档路径" }
    $parts    = $resultLine -replace '^RESULT:', '' -split ':'
    $remotePath = $parts[0]
    $remoteSize = [long]$parts[1]
    Log "服务器归档: $remotePath ($([math]::Round($remoteSize/1KB,1)) KB)"

    if ($remoteSize -lt 500000) { throw "归档只有 $remoteSize 字节，明显异常（预期 >= 800KB）" }

    # ---------- 2) 拉取到本机 ----------
    $fileName  = Split-Path $remotePath -Leaf
    $localPath = Join-Path $LocalDir $fileName
    Log "拉取到 $localPath ..."
    & $scpExe -o BatchMode=yes -o ConnectTimeout=20 "${SshHost}:$remotePath" $localPath 2>&1 |
        ForEach-Object { Log "  scp| $_" }
    if ($LASTEXITCODE -ne 0) { throw "scp 失败 (exit $LASTEXITCODE)" }
    if (-not (Test-Path $localPath)) { throw "本地文件不存在: $localPath" }

    $localSize = (Get-Item $localPath).Length
    if ($localSize -ne $remoteSize) { throw "大小不一致: 本地 $localSize vs 远端 $remoteSize" }
    Log "本地文件: $localSize 字节 (与远端一致)"

    # ---------- 3) 本地校验 ----------
    Log "校验归档可读性..."
    $test = & tar -tzf $localPath 2>&1
    if ($LASTEXITCODE -ne 0) { throw "归档损坏，tar 无法列出内容" }
    $entryCount = ($test | Measure-Object).Count
    Log "归档条目数: $entryCount"

    $mustHave = @(
        './cmd_config.json',
        './_hotbak/data_v4.db',
        './_hotbak/plugin_data/astrbot_plugin_memory_companion/memory_companion.db',
        './plugin_data/astrbot_plugin_private_companion/companions.json'
    )
    $missing = @()
    foreach ($m in $mustHave) {
        if (-not ($test -contains $m)) { $missing += $m }
    }
    if ($missing.Count -gt 0) { throw "归档缺少关键文件: $($missing -join ', ')" }
    Log "关键文件齐全 (配置/会话/记忆/陪伴数据)"

    # 记录一份可读的清单，方便日后查
    $test | Set-Content -Path (Join-Path $LocalDir "$fileName.list.txt") -Encoding UTF8

    # ---------- 4) 轮转 ----------
    $all = Get-ChildItem $LocalDir -Filter 'astrbot-data-*.tar.gz' | Sort-Object LastWriteTime -Descending
    if ($all.Count -gt $Keep) {
        $all | Select-Object -Skip $Keep | ForEach-Object {
            Remove-Item $_.FullName -Force
            Remove-Item ($_.FullName -replace '\.tar\.gz$', '.tar.gz.list.txt') -Force -ErrorAction SilentlyContinue
            Log "  轮转删除: $($_.Name)"
        }
    }
    $remain = (Get-ChildItem $LocalDir -Filter 'astrbot-data-*.tar.gz' | Measure-Object).Count
    Log "本地现有 $remain 份备份（保留上限 $Keep）"
    Log "=== 备份成功 ==="
    exit 0
}
catch {
    Log "!!! 备份失败: $($_.Exception.Message)"
    exit 1
}
