#requires -Version 7.2
<# .SYNOPSIS
Read-only directory size snapshots. Run -Init once, then run without arguments.
#>
[CmdletBinding()]
param(
    [string[]]$Path,
    [ValidateRange(0,100)][int]$MaxDepth = 5,
    [string]$OutDirRoot,
    [string]$Config = (Join-Path $PSScriptRoot 'snapshot.config.json'),
    [switch]$Init,
    [switch]$Elevate
)
$ErrorActionPreference = 'Stop'
$isAdmin = $false
if ($IsWindows) {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}
if ($Elevate -and -not $IsWindows) { throw '-Elevate is Windows-only. Run pwsh with appropriate privileges on other platforms.' }
if ($Elevate -and -not $isAdmin) {
    # Encode both the parameters and command to preserve spaces, quotes and Unicode.
    $forward = @{}
    foreach ($k in $PSBoundParameters.Keys) { if ($k -ne 'Elevate') { $forward[$k] = $PSBoundParameters[$k] } }
    if ($forward.ContainsKey('Init')) { $forward.Init = [bool]$Init }
    $forward.Config = [IO.Path]::GetFullPath($Config)
    $payload = @{ script=$PSCommandPath; cwd=(Get-Location).Path; parameters=$forward } | ConvertTo-Json -Depth 6 -Compress
    $payload64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($payload))
    $command = "`$ErrorActionPreference='Stop'; try { `$p = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('$payload64')) | ConvertFrom-Json -AsHashtable; Set-Location -LiteralPath `$p.cwd; `$a=`$p.parameters; & `$p.script @a; exit 0 } catch { Write-Error `$_ -ErrorAction Continue; exit 1 }"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($command))
    $child = Start-Process -FilePath (Join-Path $PSHOME 'pwsh.exe') -Verb RunAs -WindowStyle Hidden -Wait -PassThru -ArgumentList @('-NoProfile','-EncodedCommand',$encoded)
    if ($child.ExitCode -ne 0) { throw "Elevated scan failed (exit $($child.ExitCode))." }
    return
}
if ($Init) {
    if (Test-Path -LiteralPath $Config) { throw "Config already exists: $Config. Edit it or choose another -Config." }
    if (-not $Path) {
        $answer = Read-Host 'Folders or drives to scan (separate with semicolons)'
        $Path = @($answer.Split(';') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    }
    if (-not $Path) { throw 'Choose at least one scan root.' }
    $Path = @($Path | ForEach-Object {
        $candidate = Get-Item -LiteralPath $_ -Force
        if (-not $candidate.PSIsContainer -or ($candidate.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw "Choose a real directory, not a file or link: $_" }
        $candidate.FullName
    })
    if (-not $OutDirRoot) {
        $answer = Read-Host 'Output directory (Enter for ./snapshots beside config)'
        $OutDirRoot = if ($answer) { $answer } else { 'snapshots' }
    }
    @{ version=1; paths=$Path; outputDirectory=$OutDirRoot; maxDepth=$MaxDepth } |
        ConvertTo-Json | Set-Content -LiteralPath $Config -Encoding utf8
    Write-Output "Configuration saved: $Config"
    return
}
if (Test-Path -LiteralPath $Config) {
    $settings = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json
    if ($settings.version -ne 1) { throw 'Unsupported config version.' }
    if (-not $Path) { $Path = $settings.paths }
    if (-not $OutDirRoot) { $OutDirRoot = $settings.outputDirectory }
    if (-not $PSBoundParameters.ContainsKey('MaxDepth')) { $MaxDepth = [int]$settings.maxDepth }
}
if (-not $Path) { throw 'Run ./drive-snapshot.ps1 -Init or supply -Path first.' }
if ($MaxDepth -lt 0 -or $MaxDepth -gt 100) { throw 'maxDepth must be 0..100.' }
if (-not $OutDirRoot) { $OutDirRoot = 'snapshots' }
$configDir = Split-Path ([IO.Path]::GetFullPath($Config)) -Parent
if (-not [IO.Path]::IsPathRooted($OutDirRoot)) { $OutDirRoot = Join-Path $configDir $OutDirRoot }
$OutDirRoot = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($OutDirRoot))
$comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
$comparer = if ($IsWindows) { [StringComparer]::OrdinalIgnoreCase } else { [StringComparer]::Ordinal }
foreach ($scanPath in $Path) {
    if (-not [IO.Path]::IsPathRooted($scanPath)) { $scanPath = Join-Path $configDir $scanPath }
    $item = Get-Item -LiteralPath $scanPath -Force
    if (-not $item.PSIsContainer) { throw "Not a directory: $scanPath" }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Scan root must not be a link: $scanPath" }
    $root = $item.FullName
    $outPrefix = $OutDirRoot + [IO.Path]::DirectorySeparatorChar
    if ($root.Equals($OutDirRoot,$comparison) -or $root.StartsWith($outPrefix,$comparison)) { throw 'Scan root cannot be inside the output directory.' }
    $nodes = [Collections.Generic.Dictionary[string,object]]::new($comparer)
    $queue = [Collections.Generic.Queue[object]]::new()
    $queue.Enqueue(@($root,0,$null))
    $errors = [Collections.Generic.List[string]]::new()
    $started = [DateTime]::UtcNow
    while ($queue.Count) {
        $task = $queue.Dequeue(); $folder = $task[0]; $depth = $task[1]; $parent = $task[2]
        $node = [pscustomobject]@{Depth=$depth; Path=$folder; SizeBytes=0L; SizeGiB=0; FileCount=0L; DirCount=0; Reparse=0; Unreadable=0; Incomplete=0; Parent=$parent}
        $nodes[$folder] = $node
        try {
            $info = [IO.DirectoryInfo]::new($folder)
            if ($info.Attributes -band [IO.FileAttributes]::ReparsePoint) { $node.Reparse=1; continue }
            foreach ($entry in $info.EnumerateFileSystemInfos()) {
                if ($entry.FullName.Equals($OutDirRoot,$comparison)) { continue }
                if ($entry -is [IO.DirectoryInfo]) {
                    $node.DirCount++
                    $queue.Enqueue(@($entry.FullName,($depth+1),$folder))
                } elseif (-not ($entry.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
                    try { $node.SizeBytes += $entry.Length; $node.FileCount++ }
                    catch { $node.Unreadable=1; $node.Incomplete=1; $errors.Add("$($entry.FullName): $($_.Exception.Message)") }
                }
            }
        } catch { $node.Unreadable=1; $node.Incomplete=1; $errors.Add("${folder}: $($_.Exception.Message)") }
    }
    foreach ($node in ($nodes.Values | Sort-Object Depth -Descending)) {
        if ($null -ne $node.Parent) {
            $p = $nodes[$node.Parent]; $p.SizeBytes += $node.SizeBytes; $p.FileCount += $node.FileCount
            if ($node.Incomplete) { $p.Incomplete=1 }
        }
        $node.SizeGiB = [math]::Round($node.SizeBytes / 1GB,4)
    }
    $label = ($root -replace '[^a-zA-Z0-9_-]','_').Trim('_')
    if (-not $label) { $label='root' }
    if ($label.Length -gt 60) { $label=$label.Substring(0,60) }
    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($root))).Substring(0,8)
    $outFolder = Join-Path $OutDirRoot "$label-$hash"
    New-Item -ItemType Directory -Force -Path $outFolder | Out-Null
    $file = Join-Path $outFolder ("Drive-Snapshot-{0}-{1}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'),([guid]::NewGuid().ToString('N').Substring(0,6)))
    $nodes.Values | Where-Object Depth -LE $MaxDepth | Sort-Object Depth,Path |
        Select-Object Depth,Path,SizeBytes,SizeGiB,FileCount,DirCount,Reparse,Unreadable,Incomplete |
        Export-Csv -LiteralPath $file -NoTypeInformation -Encoding utf8BOM
    @("Started UTC: $($started.ToString('o'))", "Root: $root", "Reported depth: $MaxDepth (full traversal)",
      "Directories: $($nodes.Count)", "Logical bytes: $($nodes[$root].SizeBytes)",
      "Incomplete: $($nodes[$root].Incomplete)", "Elevated (Windows): $isAdmin", 'Links skipped; output directory excluded.', $errors) |
        Set-Content -LiteralPath ([IO.Path]::ChangeExtension($file,'.log')) -Encoding utf8
    if ($nodes[$root].Incomplete) {
        Write-Warning 'Partial snapshot: some entries could not be read. Sizes are lower bounds; inspect the log. On Windows, -Elevate may improve coverage but cannot guarantee it.'
    }
    Write-Output "Snapshot written: $file"
}
