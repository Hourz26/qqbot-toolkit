# WorkBuddy upstream DNS pin (2026-10-19)
# Problem: www.workbuddy.cn / www.codebuddy.cn / copilot.tencent.com resolve to
#   183.131.191.220 and 183.134.50.5 (Tencent EdgeOne, eo.dnse5.com).
#   TCP SYN to :443 on both IPs is silently dropped from this network.
# Fix: pin the three hostnames to 162.14.3.241, the fallback address that
#   WorkBuddy's own failover config (~/.workbuddy/failover.json) already uses.
# Reverse: delete the three "# workbuddy-pin" lines (or restore the .bak file),
#   then run: ipconfig /flushdns

$hosts  = Join-Path $env:SystemRoot 'System32\drivers\etc\hosts'
$backup = "$hosts.bak-workbuddy-20261019"

if (-not (Test-Path $backup)) {
    Copy-Item -LiteralPath $hosts -Destination $backup -Force
    Write-Output "backup created: $backup"
} else {
    Write-Output "backup already exists: $backup"
}

$current = Get-Content -LiteralPath $hosts -Raw

if ($current -match '162\.14\.3\.241') {
    Write-Output 'pin already present, nothing to do'
} else {
    $lines = @(
        ''
        '# workbuddy-pin - EdgeOne edges unreachable on this network, using official fallback'
        '162.14.3.241 www.workbuddy.cn'
        '162.14.3.241 www.codebuddy.cn'
        '162.14.3.241 copilot.tencent.com'
    )
    Add-Content -LiteralPath $hosts -Value $lines -Encoding ascii
    Write-Output 'hosts entries appended'
}

ipconfig /flushdns | Out-Null
Write-Output 'dns cache flushed'
Write-Output '--- verify ---'
foreach ($n in @('www.workbuddy.cn','www.codebuddy.cn','copilot.tencent.com')) {
    $ips = (Resolve-DnsName $n -Type A -ErrorAction SilentlyContinue |
            Where-Object { $_.IPAddress } |
            Select-Object -ExpandProperty IPAddress) -join ', '
    Write-Output ("{0,-24} -> {1}" -f $n, $ips)
}
