#requires -Version 7.2
<# .SYNOPSIS
Choose roots, assess reporting depth, and save per-root defaults. Does not capture a snapshot.
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [string]$OutDirRoot,
    [string]$Config = (Join-Path $PSScriptRoot 'snapshot.config.json'),
    [ValidateRange(0,100)][int]$MaxDepth,
    [ValidateRange(1,1000000)][int]$TargetRows = 50000,
    [ValidateSet('Growth','Budget')][string]$Strategy = 'Growth',
    [ValidateRange(1,1000000)][int]$MinAddedRows = 5000,
    [ValidateRange(1.01,1000)][double]$GrowthFactor = 3,
    [ValidateRange(1,100)][int]$MaxProbeDepth = 12,
    [ValidateRange(1,10000000)][int]$MaxEntries = 500000,
    [ValidateRange(1,3600)][int]$TimeBudgetSeconds = 20
)
$ErrorActionPreference='Stop'
$Config=[IO.Path]::GetFullPath($Config)
if (Test-Path -LiteralPath $Config) { throw "Config already exists: $Config. Edit it or choose another -Config." }
$interactive = -not $Path
if ($interactive) {
    if ($IsWindows) {
        [IO.DriveInfo]::GetDrives() | Where-Object IsReady | ForEach-Object { Write-Host ("Available: {0} ({1})" -f $_.Name,$_.DriveType) }
    }
    $answer=Read-Host 'Folders or drives to scan (separate with semicolons)'
    $Path=@($answer.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if (-not $OutDirRoot) { $OutDirRoot=Read-Host 'Output directory (Enter for snapshots beside config)' }
    if (-not $PSBoundParameters.ContainsKey('TargetRows')) {
        $answer=Read-Host 'Probe row ceiling: 1500 compact, 50000 balanced, 200000 detailed (Enter for 50000)'
        if ($answer) {
            $parsed=0
            if (-not [int]::TryParse($answer,[ref]$parsed) -or $parsed -lt 1 -or $parsed -gt 1000000) { throw 'Detail budget must be an integer from 1 to 1000000.' }
            $TargetRows=$parsed
        }
    }
}
if (-not $Path) { throw 'Choose at least one scan root.' }
# Resolve user input before serializing, so future runs do not depend on cwd.
$roots=@($Path | ForEach-Object {
    $item=Get-Item -LiteralPath $_ -Force
    if (-not $item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Choose a real directory: $_" }
    $item.FullName
} | Select-Object -Unique)
if (-not $OutDirRoot) { $OutDirRoot='snapshots' }
$configDir=Split-Path $Config -Parent
if (-not [IO.Path]::IsPathRooted($OutDirRoot)) { $OutDirRoot=Join-Path $configDir $OutDirRoot }
$OutDirRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($OutDirRoot))
$comparison=if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
foreach ($root in $roots) {
    if ($root.Equals($OutDirRoot,$comparison) -or $root.StartsWith($OutDirRoot+[IO.Path]::DirectorySeparatorChar,$comparison)) { throw 'Scan root cannot be inside the output directory.' }
}
$assessments=@(& "$PSScriptRoot/measure-snapshot-depth.ps1" -Path $roots -TargetRows $TargetRows -Strategy $Strategy -MinAddedRows $MinAddedRows -GrowthFactor $GrowthFactor -MaxProbeDepth $MaxProbeDepth -MaxEntries $MaxEntries -TimeBudgetSeconds $TimeBudgetSeconds -ExcludePath $OutDirRoot -Output '')
$depths=[ordered]@{}
foreach ($assessment in $assessments) {
    $chosen=$assessment.RecommendedMaxDepth
    if ($PSBoundParameters.ContainsKey('MaxDepth')) { $chosen=$MaxDepth }
    if ($null -eq $chosen) { throw "No depth recommendation for $($assessment.Path). Check access or explicitly choose -MaxDepth; configuration was not saved." }
    Write-Host ($assessment.DepthRows | Format-Table Depth,AddedRows,CumulativeRows,GrowthRatio,LevelComplete,GrowthOnset -AutoSize | Out-String)
    Write-Host ("{0}: depth {1}, observed rows {2}, confidence {3}, stop {4}" -f $assessment.Path,$chosen,$assessment.RecommendedRows,$assessment.Confidence,$assessment.StopReason)
    if ($assessment.Confidence -ne 'Observed') { Write-Warning "Tentative depth for $($assessment.Path): incomplete assessment. Review the saved assessment before relying on coverage." }
    $depths[$assessment.Path]=[int]$chosen
}
$settings=[ordered]@{
    version=1; paths=$roots; outputDirectory=$OutDirRoot
    maxDepth=if ($PSBoundParameters.ContainsKey('MaxDepth')) { $MaxDepth } else { 5 }
    maxDepthByPath=$depths
    depthAssessment=[ordered]@{targetRows=$TargetRows; strategy=$Strategy; minAddedRows=$MinAddedRows; growthFactor=$GrowthFactor; maxProbeDepth=$MaxProbeDepth; maxEntries=$MaxEntries; timeBudgetSeconds=$TimeBudgetSeconds; assessedAtUtc=[DateTime]::UtcNow.ToString('o'); results=$assessments}
}
New-Item -ItemType Directory -Force -Path $configDir | Out-Null
# CreateNew prevents concurrent initializers from overwriting a configuration.
$stream=[IO.File]::Open($Config,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
try {
    $bytes=[Text.Encoding]::UTF8.GetBytes(($settings | ConvertTo-Json -Depth 12))
    $stream.Write($bytes,0,$bytes.Length)
} finally { $stream.Dispose() }
Write-Output "Configuration saved: $Config"
Write-Output 'Run drive-snapshot.ps1 with the same -Config to capture. Initialization does not scan file sizes.'
