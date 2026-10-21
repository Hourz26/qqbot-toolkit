#requires -Version 5.1
<#
    One-click launcher for SnowLuma + AstrBot QQ bot.
    Idempotent: safe to run when everything is already up.

    Steps
      1. Make sure PM2 has astrbot + snowluma online
      2. Wait for :5099 :3000 :3001 :6185 :6199
      3. Make sure the regular QQ client (Roaming\QQ) is running and logged
         in as the bot account, then inject the SnowLuma hook into it
      4. Verify OneBot / get_login_info and the ws link to AstrBot

    Deliberately does NOT restore SnowLuma-Guard or pm2 save.
#>

param(
    [int]$LoginWaitSeconds = 180
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------
# Config
# --------------------------------------------------------------------------
$SnowLumaApi   = 'http://127.0.0.1:5099'
$SnowLumaUser  = 'admin'
$SnowLumaPass  = 'REPLACE_WITH_PASSWORD'
$OneBotToken   = 'REPLACE_WITH_SNOWLUMA_MCP_TOKEN'
$OneBotBase    = 'http://127.0.0.1:3000'

$BotUin        = '3799652874'
$BotNick       = 'DSH'
$QQExe         = 'C:\Program Files\Tencent\QQNT\QQ.exe'
$IsolatedData  = 'QQ-SnowLuma'   # the OTHER instance, must NOT be used for the bot

$CorePorts     = @(5099, 6185, 6199)   # up as soon as the services are up
$OneBotPorts   = @(3000, 3001)         # only appear after the hook has a session

# --------------------------------------------------------------------------
# Helpers
# --------------------------------------------------------------------------
$script:StepNo = 0

function Step([string]$Text) {
    $script:StepNo++
    Write-Host ''
    Write-Host ("[{0}] {1}" -f $script:StepNo, $Text) -ForegroundColor Cyan
}

function Ok([string]$Text)   { Write-Host "    OK   $Text" -ForegroundColor Green }
function Info([string]$Text) { Write-Host "    ..   $Text" -ForegroundColor Gray }
function Warn([string]$Text) { Write-Host "    WARN $Text" -ForegroundColor Yellow }

function Fail([string]$Text) {
    Write-Host "    FAIL $Text" -ForegroundColor Red
    Write-Host ''
    Write-Host 'Launch aborted.' -ForegroundColor Red
    exit 1
}

function Test-Port([string]$Target, [int]$Port, [int]$TimeoutMs = 1500) {
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Target, $Port, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($TimeoutMs)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        try { $client.Close() } catch { }
    }
}

function Get-Pm2Raw {
    # NOTE: do not ConvertFrom-Json this -- pm2 jlist contains both "username"
    # and "USERNAME", which PowerShell 5.1 rejects as duplicate keys.
    try { return ((& cmd /c "pm2 jlist 2>nul") | Out-String) } catch { return '' }
}

function Test-Pm2AppKnown([string]$Name) {
    $raw = Get-Pm2Raw
    return ($raw -match ('"name":"' + [regex]::Escape($Name) + '"'))
}

function Start-Pm2App([string]$Name, [string]$ExePath, [string]$WorkDir, [string]$ExtraArgs) {
    if ((Test-Pm2AppKnown $Name)) {
        Info "pm2 start $Name"
        & cmd /c "pm2 start $Name 2>&1" | Out-Null
    } else {
        # The app is not registered with pm2 yet (fresh machine / pm2 resurrect
        # never ran). Register it with the same shape dump.pm2 uses.
        Info "pm2 app '$Name' not registered -> creating it"
        $cmd = "pm2 start `"$ExePath`" --name $Name --cwd `"$WorkDir`" --time"
        if ($ExtraArgs) { $cmd = "$cmd -- $ExtraArgs" }
        & cmd /c "$cmd 2>&1" | Out-Null
    }
}

function Ensure-Pm2App([string]$Name, [int]$Port, [string]$ExePath, [string]$WorkDir, [string]$ExtraArgs) {
    if (Test-Port '127.0.0.1' $Port 1200) {
        Ok "$Name already serving on :$Port"
        return
    }
    Start-Pm2App $Name $ExePath $WorkDir $ExtraArgs
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline) {
        if (Test-Port '127.0.0.1' $Port 1200) { Ok "$Name up on :$Port"; return }
        Start-Sleep -Seconds 2
    }
    Fail "$Name never started listening on :$Port (try 'pm2 logs $Name')"
}

function Get-SnowLumaToken {
    $body = @{ username = $SnowLumaUser; password = $SnowLumaPass } | ConvertTo-Json -Compress
    $resp = Invoke-RestMethod -Uri "$SnowLumaApi/api/login" -Method Post `
        -ContentType 'application/json' -Body $body -TimeoutSec 20
    if ($resp.token) { return $resp.token }
    if ($resp.data -and $resp.data.token) { return $resp.data.token }
    throw 'SnowLuma login returned no token'
}

function Get-QqProcesses($Headers) {
    $resp = Invoke-RestMethod -Uri "$SnowLumaApi/api/processes" -Headers $Headers -TimeoutSec 20
    return @($resp.list)
}

function Test-RegularQqRunning {
    $procs = Get-CimInstance Win32_Process -Filter "Name='QQ.exe'" -ErrorAction SilentlyContinue |
             Where-Object { $_.CommandLine -and -not ($_.CommandLine -like "*$IsolatedData*") }
    return [bool]$procs
}

# --------------------------------------------------------------------------
# Banner
# --------------------------------------------------------------------------
Write-Host ''
Write-Host '==================================================' -ForegroundColor Cyan
Write-Host '   QQ Bot Launcher  --  SnowLuma + AstrBot'         -ForegroundColor Cyan
Write-Host '   bot account : 3799652874 (DSH)'                    -ForegroundColor Cyan
Write-Host '==================================================' -ForegroundColor Cyan

# --------------------------------------------------------------------------
# 1. PM2 apps
# --------------------------------------------------------------------------
Step 'Starting PM2 applications'

if (-not (Get-Command pm2 -ErrorAction SilentlyContinue)) {
    $pm2Fallback = Join-Path $env:APPDATA 'npm\pm2.cmd'
    if (Test-Path $pm2Fallback) {
        $env:Path = "$env:Path;$env:APPDATA\npm"
        Info 'pm2 found in %APPDATA%\npm, added to PATH'
    } else {
        Fail 'pm2 not found on PATH and not in %APPDATA%\npm'
    }
}

Ensure-Pm2App 'astrbot'  6185 'D:\Apps\astrbot-venv\Scripts\astrbot.exe' 'D:\Apps\astrbot' 'run'
Ensure-Pm2App 'snowluma' 5099 'D:\Apps\snowluma\index.mjs' 'D:\Apps\snowluma' ''

# --------------------------------------------------------------------------
# 2. Service ports
# --------------------------------------------------------------------------
Step 'Waiting for service ports'

$deadline = (Get-Date).AddSeconds(90)
$pending = @($CorePorts)
while ((Get-Date) -lt $deadline -and $pending.Count -gt 0) {
    $pending = @($pending | Where-Object { -not (Test-Port '127.0.0.1' $_ 800) })
    if ($pending.Count -gt 0) { Start-Sleep -Seconds 2 }
}

if ($pending.Count -gt 0) {
    Fail ("ports still not listening: {0}" -f ($pending -join ', '))
}
Ok ("service ports listening ({0})" -f ($CorePorts -join ' '))

# --------------------------------------------------------------------------
# 3. Hook injection
# --------------------------------------------------------------------------
Step 'Preparing the QQ client for the bot account'

$token   = Get-SnowLumaToken
$headers = @{ Authorization = "Bearer $token" }

$target = $null
foreach ($p in (Get-QqProcesses $headers)) {
    if ($p.account -and $p.account.uin -eq $BotUin) { $target = $p; break }
}

if (-not $target) {
    Warn "bot account $BotUin is not logged in anywhere yet"
    if (-not (Test-RegularQqRunning)) {
        if (-not (Test-Path $QQExe)) { Fail "QQ.exe not found at $QQExe" }
        Info "starting the regular QQ client"
        Start-Process $QQExe | Out-Null
    } else {
        Info 'regular QQ client is running but not logged in as the bot account'
    }
    Info "log in as $BotUin ($BotNick) in the QQ window -- waiting up to $LoginWaitSeconds s"

    $loginDeadline = (Get-Date).AddSeconds($LoginWaitSeconds)
    while ((Get-Date) -lt $loginDeadline -and -not $target) {
        Start-Sleep -Seconds 3
        foreach ($p in (Get-QqProcesses $headers)) {
            if ($p.account -and $p.account.uin -eq $BotUin) { $target = $p; break }
        }
    }

    if (-not $target) {
        $seen = (Get-QqProcesses $headers) |
                ForEach-Object { if ($_.account) { "$($_.account.uin)" } } |
                Where-Object { $_ } | Select-Object -Unique
        if ($seen) { Warn ("accounts seen instead: {0}" -f ($seen -join ', ')) }
        Fail "timed out waiting for $BotUin to log in"
    }
}

$pid_ = $target.pid
Ok "found bot account $BotUin on PID $pid_"

if ($target.injected) {
    if ($target.connected) {
        Ok 'hook already injected and connected'
    } else {
        Info 'hook injected but not connected -> reloading'
        try {
            Invoke-RestMethod -Uri "$SnowLumaApi/api/processes/$pid_/unload" -Method Post `
                -Headers $headers -ContentType 'application/json' -Body '{}' -TimeoutSec 40 | Out-Null
        } catch { Warn "unload failed: $($_.Exception.Message)" }
        Start-Sleep -Seconds 2
        $target.injected = $false
    }
}

if (-not $target.injected) {
    Info "injecting hook into PID $pid_"
    try {
        $res = Invoke-RestMethod -Uri "$SnowLumaApi/api/processes/$pid_/load" -Method Post `
            -Headers $headers -ContentType 'application/json' -Body '{}' -TimeoutSec 60
        if (-not $res.success) { Fail "injection failed: $($res | ConvertTo-Json -Compress)" }
        Ok "hook injected via $($res.process.method)"
    } catch {
        Fail "injection request failed: $($_.Exception.Message)"
    }
}

# --------------------------------------------------------------------------
# 4. Verify end to end
# --------------------------------------------------------------------------
Step 'Verifying the message pipeline'

$onebotHeaders = @{ Authorization = "Bearer $OneBotToken" }
$loginOk = $false
$verifyDeadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $verifyDeadline -and -not $loginOk) {
    try {
        $info = Invoke-RestMethod -Uri "$OneBotBase/get_login_info" -Method Post `
            -Headers $onebotHeaders -ContentType 'application/json' -Body '{}' -TimeoutSec 10
        if ($info.status -eq 'ok' -and "$($info.data.user_id)" -eq $BotUin) { $loginOk = $true }
    } catch { }
    if (-not $loginOk) { Start-Sleep -Seconds 3 }
}

if (-not $loginOk) { Fail 'OneBot get_login_info did not confirm the bot account' }
Ok "OneBot reports $BotUin ($($info.data.nickname))"

# :3000 / :3001 come up together with the OneBot session, so they are a good
# second proof that the adapter really started for this account.
$adapterDeadline = (Get-Date).AddSeconds(30)
$adapterPending  = @($OneBotPorts)
while ((Get-Date) -lt $adapterDeadline -and $adapterPending.Count -gt 0) {
    $adapterPending = @($adapterPending | Where-Object { -not (Test-Port '127.0.0.1' $_ 800) })
    if ($adapterPending.Count -gt 0) { Start-Sleep -Seconds 1 }
}
if ($adapterPending.Count -gt 0) {
    Warn ("OneBot adapters not listening: {0}" -f ($adapterPending -join ', '))
} else {
    Ok 'OneBot HTTP/WS adapters listening on :3000 :3001'
}

$wsOk = $false
$wsDeadline = (Get-Date).AddSeconds(30)
while ((Get-Date) -lt $wsDeadline -and -not $wsOk) {
    $conn = Get-NetTCPConnection -LocalPort 6199 -State Established -ErrorAction SilentlyContinue
    if ($conn) { $wsOk = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $wsOk) { Fail 'no websocket connection to AstrBot on :6199' }
Ok 'SnowLuma is connected to AstrBot on :6199'

# --------------------------------------------------------------------------
# Done
# --------------------------------------------------------------------------
Write-Host ''
Write-Host '==================================================' -ForegroundColor Green
Write-Host '   ALL SYSTEMS GO'                                  -ForegroundColor Green
Write-Host '==================================================' -ForegroundColor Green
Write-Host "   bot account : $BotUin ($($info.data.nickname))"  -ForegroundColor Green
Write-Host "   AstrBot UI  : http://127.0.0.1:6185"             -ForegroundColor Green
Write-Host "   SnowLuma UI : http://127.0.0.1:5099"             -ForegroundColor Green
Write-Host ''
Write-Host '   Send a message to the bot from another account to test.' -ForegroundColor Gray
Write-Host ''
