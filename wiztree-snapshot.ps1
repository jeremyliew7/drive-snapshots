#requires -Version 7.2
<#
.SYNOPSIS
Create Drive Snapshots data with WizTree, the project's default scanner.
#>
[CmdletBinding()]
param(
    [string[]]$Target,
    [string]$Config = (Join-Path $PSScriptRoot 'snapshot.config.json'),
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'snapshots/wiztree'),
    [string]$ExePath,
    [ValidateRange(0,100)][int]$ViewDepth = 5,
    [switch]$NoAdmin,
    [switch]$Minimal
)
$ErrorActionPreference = 'Stop'

if (-not $IsWindows) { throw 'WizTree capture is Windows-only.' }
if (-not $Target -and (Test-Path -LiteralPath $Config)) {
    $settings = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
    $Target = @($settings.paths)
    if ($settings.maxDepth -ne $null -and -not $PSBoundParameters.ContainsKey('ViewDepth')) {
        $ViewDepth = [int]$settings.maxDepth
    }
}
if (-not $Target) { throw 'Supply -Target or configure paths in snapshot.config.json.' }

$rawDir = Join-Path $OutputDirectory 'raw'
$convertedDir = Join-Path $OutputDirectory 'converted'
$null = New-Item -ItemType Directory -Path $rawDir,$convertedDir -Force
$exporter = Join-Path $PSScriptRoot '.agents/skills/wiztree-csv-export/scripts/Export-WizTreeCsv.ps1'
$converter = Join-Path $PSScriptRoot 'Convert-WizTreeCsv.ps1'
$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$results = @()

foreach ($item in $Target) {
    $targetValue = $item.Trim()
    $label = $targetValue.TrimEnd('\','/') -replace '[^a-zA-Z0-9_-]','_'
    if (-not $label) { $label = 'root' }
    $rawName = '{0}_WizTree_{1}_{2}.csv' -f $label,$stamp,[guid]::NewGuid().ToString('N').Substring(0,6)
    $exportArgs = @{
        Target = @($targetValue)
        OutDir = $rawDir
        OutFile = $rawName
        NoSummary = $true
    }
    if ($ExePath) { $exportArgs.ExePath = $ExePath }
    if ($NoAdmin) { $exportArgs.NoAdmin = $true }
    if ($Minimal) { $exportArgs.Minimal = $true }
    & $exporter @exportArgs | Out-Host
    $rawPath = Join-Path $rawDir $rawName
    $results += & $converter -InputPath $rawPath -OutputDirectory $convertedDir -ViewDepth $ViewDepth
}

$results
