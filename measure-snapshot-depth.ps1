#requires -Version 7.2
<#
.SYNOPSIS
Recommend a reporting depth per local disk using a bounded, read-only directory probe.
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [ValidateRange(1,1000000)][int]$TargetRows = 10000,
    [ValidateRange(1,100)][int]$MaxProbeDepth = 12,
    [ValidateRange(1,10000000)][int]$MaxEntries = 500000,
    [ValidateRange(1,3600)][int]$TimeBudgetSeconds = 20,
    [string[]]$ExcludePath = @((Join-Path $PSScriptRoot 'snapshots'),(Join-Path $PSScriptRoot 'reports')),
    [string]$Output = (Join-Path $PSScriptRoot 'reports/depth-assessment.json')
)
$ErrorActionPreference = 'Stop'
if (-not $Path) {
    if (-not $IsWindows) { throw 'Specify -Path for mount points or directories on this platform.' }
    $Path = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' } | ForEach-Object { $_.RootDirectory.FullName })
}
if (-not $Path) { throw 'No ready fixed drives found; specify -Path explicitly.' }
$comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$excluded = @($ExcludePath | ForEach-Object { [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($_)) })
$results = @(foreach ($scanPath in $Path) {
    $watch = [Diagnostics.Stopwatch]::StartNew()
    $levels = [Collections.Generic.List[object]]::new()
    $failures = [Collections.Generic.List[string]]::new()
    $entries = 0; $links = 0; $rows = 1; $recommended = $null; $reason = 'DepthLimit'; $root = [IO.Path]::GetFullPath($scanPath)
    try {
        $item = Get-Item -LiteralPath $root -Force
        if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Root must be a real directory, not a file or link.' }
        $root = $item.FullName
        $parents = @($root)
        $recommended = 0
        $levels.Add([pscustomobject]@{Depth=0; CumulativeRows=1; LevelComplete=$true})
        :probe for ($depth=1; $depth -le $MaxProbeDepth; $depth++) {
            $next = [Collections.Generic.List[string]]::new()
            $before = $rows; $complete = $true
            foreach ($folder in $parents) {
                if ($watch.Elapsed.TotalSeconds -ge $TimeBudgetSeconds) { $reason='TimeBudget'; $complete=$false; break }
                try {
                    $info = [IO.DirectoryInfo]::new($folder)
                    # Recheck links in case the tree changed since discovery.
                    if ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) { $links++; continue }
                    foreach ($entry in $info.EnumerateFileSystemInfos()) {
                        if ($watch.Elapsed.TotalSeconds -ge $TimeBudgetSeconds) { $reason='TimeBudget'; $complete=$false; break }
                        if ($entries -ge $MaxEntries) { $reason='EntryBudget'; $complete=$false; break }
                        $entries++
                        if ($entry -isnot [IO.DirectoryInfo]) { continue }
                        $skip=$false
                        foreach ($exclude in $excluded) { if ($entry.FullName.Equals($exclude,$comparison)) { $skip=$true; break } }
                        if ($skip) { continue }
                        $rows++
                        if ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) { $links++ } else { $next.Add($entry.FullName) }
                        if ($rows -gt $TargetRows) { $reason='RowBudget'; $complete=$false; break }
                    }
                } catch {
                    $failures.Add("${folder}: $($_.Exception.Message)")
                    if ($depth -eq 1) { $recommended=$null }
                }
                if (-not $complete) { break }
            }
            $levels.Add([pscustomobject]@{Depth=$depth; CumulativeRows=$rows; LevelComplete=$complete})
            if (-not $complete) { break probe }
            if ($null -eq $recommended) { $reason='RootUnreadable'; break probe }
            if ($rows -gt $before) { $recommended=$depth }
            if (-not $next.Count) { $reason='TreeExhausted'; break probe }
            $parents=$next.ToArray()
        }
    } catch { $reason='InvalidRoot'; $recommended=$null; $failures.Add($_.Exception.Message) }
    $watch.Stop()
    $confidence = if ($null -eq $recommended) { 'Unavailable' } elseif ($failures.Count -or $reason -in @('TimeBudget','EntryBudget')) { 'Low' } else { 'Observed' }
    [pscustomobject]@{
        Path=$root; RecommendedMaxDepth=$recommended; Confidence=$confidence; StopReason=$reason
        RecommendedRows=if ($null -ne $recommended) { ($levels | Where-Object Depth -EQ $recommended | Select-Object -First 1).CumulativeRows } else { $null }
        MaxProbeDepth=$MaxProbeDepth; MaxEntries=$MaxEntries; TimeBudgetSeconds=$TimeBudgetSeconds
        TargetRows=$TargetRows; ObservedRows=$rows; EntriesInspected=$entries; LinksSkipped=$links
        ReadFailures=$failures.Count; ElapsedSeconds=[math]::Round($watch.Elapsed.TotalSeconds,2)
        DepthRows=$levels.ToArray(); Errors=$failures.ToArray()
    }
})
if ($Output) {
    $destination=[IO.Path]::GetFullPath($Output)
    New-Item -ItemType Directory -Force -Path (Split-Path $destination -Parent) | Out-Null
    @{version=1; assessedAtUtc=[DateTime]::UtcNow.ToString('o'); results=$results} |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $destination -Encoding utf8
}
$results
