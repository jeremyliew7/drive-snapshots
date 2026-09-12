<#
.SYNOPSIS
    Exports a full WizTree scan of one or more drives/folders to CSV.

.DESCRIPTION
    Wraps the WizTree command line (/export). Defaults to a full-disk export with
    every optional data column turned on, an MFT-based scan (needs Administrator),
    and a post-run sanity check that the CSV is present and complete.

.PARAMETER Target
    One or more drives or folders, e.g. 'C:', 'D:', 'C:\Users'.

.PARAMETER OutDir
    Directory that receives the CSV. Defaults to the current directory.

.PARAMETER OutFile
    Explicit output file name. Only valid for a single target.

.PARAMETER ExePath
    Override WizTree64.exe discovery.

.PARAMETER SortBy
    0 = name, 1 = size (default), 2 = allocated size, 3 = modified date.

.PARAMETER NoAdmin
    Skip the Administrator relaunch. Scanning then falls back to a directory walk,
    which is much slower and cannot emit valid MFT record numbers.

.PARAMETER Minimal
    Export only the base columns (name, size, allocated, modified, attributes, files, folders).

.EXAMPLE
    .\Export-WizTreeCsv.ps1 -Target 'C:' -OutDir . -FileTypes
#>
[CmdletBinding()]
param(
    [string[]] $Target = @('C:'),
    [string]   $OutDir = (Get-Location).Path,
    [string]   $OutFile,
    [string]   $ExePath,
    [ValidateSet(0, 1, 2, 3)] [int] $SortBy = 1,
    [string]   $Filter,
    [string]   $FilterExclude,
    [switch]   $NoAdmin,
    [switch]   $Minimal,
    [switch]   $FileTypes,
    [switch]   $NoSummary
)

$ErrorActionPreference = 'Stop'

function Resolve-WizTreeExe {
    param([string] $Explicit)

    if ($Explicit) {
        if (-not (Test-Path -LiteralPath $Explicit)) { throw "WizTree executable not found: $Explicit" }
        return (Resolve-Path -LiteralPath $Explicit).Path
    }

    $names = if ([Environment]::Is64BitOperatingSystem) { @('WizTree64.exe', 'WizTree.exe') } else { @('WizTree.exe') }
    $roots = @()
    $uninstallKeys = @(
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $roots += Get-ItemProperty -Path $uninstallKeys -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -like 'WizTree*' -and $_.InstallLocation } |
        ForEach-Object { $_.InstallLocation }
    $roots += 'C:\Program Files\WizTree', 'C:\Program Files (x86)\WizTree', "$env:LOCALAPPDATA\WizTree"

    foreach ($root in ($roots | Select-Object -Unique)) {
        foreach ($name in $names) {
            $candidate = Join-Path $root $name
            if (Test-Path -LiteralPath $candidate) { return (Resolve-Path -LiteralPath $candidate).Path }
        }
    }
    throw "WizTree executable not found. Pass -ExePath, e.g. -ExePath 'C:\Tools\WizTree\WizTree64.exe'."
}

function Test-IsElevated {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-TargetLabel {
    param([string] $Value)
    $v = $Value.TrimEnd('\', '/')
    if ($v -match '^([A-Za-z]):$') { return $Matches[1] }
    return (Split-Path -Leaf $v)
}

# WizTree writes UTF-8 with a BOM, then a banner line and a localized header line.
function Read-CsvPreview {
    param([string] $Path, [int] $Lines = 2)
    $reader = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8)
    try {
        $out = @()
        for ($i = 0; $i -lt $Lines; $i++) {
            if ($reader.EndOfStream) { break }
            $out += $reader.ReadLine()
        }
        return $out
    } finally { $reader.Dispose() }
}

# Columns: 0=name 1=size 2=allocated 3=modified 4=attributes ...
# The name field is the only quoted field that can contain commas, and file names
# cannot contain a double quote, so this anchored match is safe and fast.
$script:RowPattern = [regex]'^"(?<name>[^"]*)",(?<size>\d+),(?<alloc>\d*),'

function Get-CsvSummary {
    param([string] $Path, [int] $TopN = 10)

    $reader = [System.IO.StreamReader]::new($Path, [System.Text.Encoding]::UTF8)
    $total = 0; $files = 0; $folders = 0; $bytes = 0; $hardLinks = 0
    $capacity = $null
    $top = [System.Collections.Generic.List[object]]::new()
    $minTop = [long]::MinValue

    try {
        $reader.ReadLine() | Out-Null   # banner
        $reader.ReadLine() | Out-Null   # header
        while ($null -ne ($line = $reader.ReadLine())) {
            $total++
            $m = $script:RowPattern.Match($line)
            if (-not $m.Success) { continue }

            $name = $m.Groups['name'].Value
            $isFolder = $name.EndsWith('\')
            if ($isFolder) { $folders++ } else { $files++ }

            $size = [long]$m.Groups['size'].Value
            $allocRaw = $m.Groups['alloc'].Value
            # A leading zero on the allocated size marks a hard link: it consumes no extra disk space.
            if ($allocRaw.Length -gt 1 -and $allocRaw[0] -eq '0') { $hardLinks++ }

            if (-not $isFolder) {
                $bytes += $size
                if ($size -gt $minTop) {
                    $top.Add([pscustomobject]@{ Size = $size; Path = $name })
                    if ($top.Count -gt $TopN) {
                        $sorted = $top | Sort-Object Size -Descending
                        $top.Clear()
                        for ($i = 0; $i -lt $TopN; $i++) { $top.Add($sorted[$i]) }
                        $minTop = $top[$top.Count - 1].Size
                    } elseif ($top.Count -eq $TopN) {
                        $minTop = ($top | Sort-Object Size | Select-Object -First 1).Size
                    }
                }
            }

            # The capacity quartet (capacity, free, used, reserved) is always the last four
            # columns and carries data only on the first data record. In the full layout that
            # is 18-21, in the base layout 7-10, so read it from the end of the row.
            if ($total -eq 1) {
                $fields = $line.Split(',')
                if ($fields.Count -ge 11 -and [long]$fields[$fields.Count - 4] -gt 0) {
                    $drive = if ($fields.Count -ge 22) { $fields[13].Trim('"') }
                             elseif ($name -match '^([A-Za-z]):') { "$($Matches[1]):" }
                             else { $name }
                    $capacity = [pscustomobject]@{
                        Drive    = $drive
                        Total    = [long]$fields[$fields.Count - 4]
                        Free     = [long]$fields[$fields.Count - 3]
                        Used     = [long]$fields[$fields.Count - 2]
                        Reserved = [long]$fields[$fields.Count - 1]
                    }
                }
            }
        }
    } finally { $reader.Dispose() }

    return [pscustomobject]@{
        Rows      = $total
        Files     = $files
        Folders   = $folders
        FileBytes = $bytes
        HardLinks = $hardLinks
        Capacity  = $capacity
        Largest   = ($top | Sort-Object Size -Descending)
    }
}

function Format-Size {
    param([long] $Bytes)
    $units = 'B', 'KB', 'MB', 'GB', 'TB', 'PB'
    $v = [double]$Bytes; $i = 0
    while ($v -ge 1024 -and $i -lt $units.Count - 1) { $v /= 1024; $i++ }
    return ('{0:N2} {1}' -f $v, $units[$i])
}

function New-WizTreeArgs {
    param(
        [string] $TargetPath, [string] $CsvPath, [string] $TypePath,
        [bool] $Admin, [int] $SortBy, [bool] $Minimal, [string] $Filter, [string] $FilterExclude
    )
    $admin = if ($Admin) { '/admin=1' } else { '/admin=0' }
    $a = @("`"$TargetPath`"", "/export=`"$CsvPath`"", "/sortby=$SortBy", $admin)
    if (-not $Minimal) {
        $a += '/exportmftrecno=1', '/exportalldates=1', '/exportallsizes=1',
              '/exportsplitfilename=1', '/exportdrivecapacity=1', '/exportpercentofparent=1'
    }
    if ($Filter)        { $a += "/filter=`"$Filter`"" }
    if ($FilterExclude) { $a += "/filterexclude=`"$FilterExclude`"" }
    if ($TypePath)      { $a += "/exportfiletypes=`"$TypePath`"" }
    return $a
}

function Wait-ForExport {
    param([string] $Path, [int] $TimeoutSeconds = 60)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $lastLength = -1
    while ((Get-Date) -lt $deadline) {
        if (Test-Path -LiteralPath $Path) {
            $len = (Get-Item -LiteralPath $Path).Length
            if ($len -gt 0 -and $len -eq $lastLength) { return $true }
            $lastLength = $len
        }
        Start-Sleep -Milliseconds 500
    }
    return (Test-Path -LiteralPath $Path)
}

# ---------------------------------------------------------------- main

# `pwsh -File script.ps1 -Target 'C:','D:'` hands the whole list over as one literal
# string, so split comma-separated values back into separate targets.
if ($Target.Count -eq 1 -and $Target[0] -match ',') {
    $Target = $Target[0].Split(',') | ForEach-Object { $_.Trim().Trim("'").Trim('"') } | Where-Object { $_ }
}

$exe = Resolve-WizTreeExe -Explicit $ExePath
$OutDir = (New-Item -ItemType Directory -Force -Path $OutDir).FullName
if ($OutFile -and $Target.Count -gt 1) { throw '-OutFile can only be used with a single -Target.' }

$elevated = Test-IsElevated
$useAdmin = -not $NoAdmin
if ($useAdmin -and -not $elevated) {
    Write-Host 'Not elevated: the scan will relaunch WizTree through UAC to enable the fast MFT scan.'
}

$stamp = Get-Date -Format 'yyyyMMddHHmmss'
$results = @()

foreach ($t in $Target) {
    $csvName = if ($OutFile) { $OutFile }
               elseif ($Target.Count -eq 1) { "WizTree_$stamp.csv" }
               else { "$(Get-TargetLabel $t)_WizTree_$stamp.csv" }
    $csvPath = if ([System.IO.Path]::IsPathRooted($csvName)) { $csvName } else { Join-Path $OutDir $csvName }

    $typePath = $null
    if ($FileTypes) {
        $typePath = [System.IO.Path]::ChangeExtension($csvPath, $null).TrimEnd('.') + '_filetypes.csv'
    }

    $newArgs = @{
        TargetPath = $t; CsvPath = $csvPath; TypePath = $typePath
        SortBy = $SortBy; Minimal = $Minimal.IsPresent; Filter = $Filter; FilterExclude = $FilterExclude
    }
    $argList = New-WizTreeArgs @newArgs -Admin $useAdmin

    # A leftover file at the same path would make the completion check below pass instantly.
    foreach ($stale in @($csvPath, $typePath)) {
        if ($stale -and (Test-Path -LiteralPath $stale)) { Remove-Item -LiteralPath $stale -Force }
    }

    Write-Host "Scanning $t -> $csvPath"
    $sw = [Diagnostics.Stopwatch]::StartNew()

    $needsUac = $useAdmin -and -not $elevated
    $startArgs = @{ FilePath = $exe; ArgumentList = $argList; PassThru = $true }
    if ($needsUac) { $startArgs.Verb = 'RunAs' }

    try {
        $proc = Start-Process @startArgs
        $proc.WaitForExit()
    } catch {
        if (-not $needsUac) { throw }
        Write-Warning "Elevation was declined or failed: $($_.Exception.Message)"
        Write-Warning 'Retrying without Administrator (slower directory walk, no MFT record numbers).'
        $useAdmin = $false
        $argList = New-WizTreeArgs @newArgs -Admin $false
        $proc = Start-Process -FilePath $exe -ArgumentList $argList -PassThru
        $proc.WaitForExit()
    }
    $sw.Stop()

    if (-not (Wait-ForExport -Path $csvPath)) {
        throw "WizTree finished but no CSV was written to $csvPath (exit code $($proc.ExitCode))."
    }

    $item = Get-Item -LiteralPath $csvPath
    $preview = Read-CsvPreview -Path $csvPath -Lines 2
    $summary = $null
    if (-not $NoSummary) { $summary = Get-CsvSummary -Path $csvPath }

    Write-Host ''
    Write-Host "  file      : $($item.FullName)"
    Write-Host "  size      : $(Format-Size $item.Length)"
    Write-Host "  elapsed   : $([int]$sw.Elapsed.TotalSeconds)s"
    Write-Host "  banner    : $($preview[0])"
    Write-Host "  header    : $($preview[1])"
    if ($summary) {
        Write-Host "  rows      : $($summary.Rows)  (files: $($summary.Files), folders: $($summary.Folders))"
        Write-Host "  file bytes: $($summary.FileBytes)  ($(Format-Size $summary.FileBytes))"
        if ($summary.HardLinks) { Write-Host "  hard links: $($summary.HardLinks) file rows flagged with a leading 0 in the allocated column" }
        if ($summary.Capacity) {
            $c = $summary.Capacity
            Write-Host "  drive $($c.Drive)$([char]32)  used $(Format-Size $c.Used)  free $(Format-Size $c.Free)  total $(Format-Size $c.Total)"
        }
        if ($summary.Largest.Count) {
            Write-Host '  largest files:'
            $summary.Largest | ForEach-Object { Write-Host ("    {0,12}  {1}" -f (Format-Size $_.Size), $_.Path) }
        }
    }
    Write-Host ''

    $results += [pscustomobject]@{
        Target = $t; Csv = $item.FullName; Bytes = $item.Length
        Rows = if ($summary) { $summary.Rows } else { $null }
        FileTypesCsv = if ($typePath -and (Test-Path -LiteralPath $typePath)) { $typePath } else { $null }
    }
}

$results | Format-List
