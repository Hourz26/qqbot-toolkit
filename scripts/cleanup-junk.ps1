$ErrorActionPreference = 'SilentlyContinue'
$freed = 0
$report = @()

function Get-Size($p) {
    if (-not (Test-Path -LiteralPath $p)) { return 0 }
    return (Get-ChildItem -LiteralPath $p -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum
}

function Clean-Dir($label, $path, $keepRoot = $true) {
    $before = Get-Size $path
    if (-not $before) { return }
    if ($keepRoot) {
        Get-ChildItem -LiteralPath $path -Force -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
    } else {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction SilentlyContinue
    }
    $after = Get-Size $path
    $delta = $before - $after
    $script:freed += $delta
    $script:report += [pscustomobject]@{ Item=$label; FreedMB=[math]::Round($delta/1MB,1); LeftMB=[math]::Round($after/1MB,1) }
}

# 1. WinGet installer leftovers (Ollama 1.5G + FFmpeg 245M)
Clean-Dir 'WinGet installer cache' "$env:TEMP\WinGet"

# 2. My own plugin-install temp packages
Clean-Dir 'dshops-payload' "$env:TEMP\dshops-payload" $false
Clean-Dir 'dshmem-probe'   "$env:TEMP\dshmem-probe"   $false

# 3. Crash dumps from games
Clean-Dir 'CrashDumps' "$env:LOCALAPPDATA\CrashDumps"

# 4. System diagnostics temp dirs
Clean-Dir 'Temp\Diagnostics' "$env:TEMP\Diagnostics" $false
Clean-Dir 'Temp\AK'          "$env:TEMP\AK"          $false

# 5. Python _MEI temp unpack dirs (skip ones held by running processes)
Get-ChildItem "$env:TEMP" -Directory -Force -Filter '_MEI*' -ErrorAction SilentlyContinue | ForEach-Object {
    $n = $_.Name
    $before = Get-Size $_.FullName
    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $_.FullName) {
        $script:report += [pscustomobject]@{ Item="$n (in use, skipped)"; FreedMB=0; LeftMB=[math]::Round($before/1MB,1) }
    } else {
        $script:freed += $before
        $script:report += [pscustomobject]@{ Item=$n; FreedMB=[math]::Round($before/1MB,1); LeftMB=0 }
    }
}

# 6. Windows Error Reporting
Clean-Dir 'WER ReportArchive' "$env:PROGRAMDATA\Microsoft\Windows\WER\ReportArchive"
Clean-Dir 'WER ReportQueue'   "$env:PROGRAMDATA\Microsoft\Windows\WER\ReportQueue"

# 7. Recycle bin
$rbBefore = (Get-ChildItem 'C:\$Recycle.Bin' -Recurse -File -Force -ErrorAction SilentlyContinue |
             Measure-Object Length -Sum).Sum
if (-not $rbBefore) { $rbBefore = 0 }
Clear-RecycleBin -DriveLetter C -Force -ErrorAction SilentlyContinue
$rbAfter = (Get-ChildItem 'C:\$Recycle.Bin' -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object Length -Sum).Sum
if (-not $rbAfter) { $rbAfter = 0 }
$script:freed += ($rbBefore - $rbAfter)
$script:report += [pscustomobject]@{ Item='Recycle Bin C:'; FreedMB=[math]::Round(($rbBefore-$rbAfter)/1MB,1); LeftMB=[math]::Round($rbAfter/1MB,1) }

# 8. Old profile backups (keep 4 newest)
$bakDir = "$env:USERPROFILE\.dsh\profiles\desktop"
Get-ChildItem $bakDir -File -Force -Filter '*.bak*' -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 4 | ForEach-Object {
        $nm = $_.Name
        $sz = $_.Length
        Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $_.FullName)) {
            $script:freed += $sz
            $script:report += [pscustomobject]@{ Item=$nm; FreedMB=[math]::Round($sz/1MB,2); LeftMB=0 }
        }
    }

Write-Output '=== cleanup detail ==='
$report | Format-Table -AutoSize | Out-String
Write-Output ('TOTAL FREED: {0:N1} MB' -f ($freed/1MB))
