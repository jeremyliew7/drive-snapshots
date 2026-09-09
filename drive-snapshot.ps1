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
    $setup=@{Config=$Config}
    foreach ($key in @('Path','OutDirRoot','MaxDepth')) {
        if ($PSBoundParameters.ContainsKey($key)) { $setup[$key]=$PSBoundParameters[$key] }
    }
    & (Join-Path $PSScriptRoot 'initialize-snapshots.ps1') @setup
    return
}
$settings=$null
if (Test-Path -LiteralPath $Config) {
    $settings = Get-Content -LiteralPath $Config -Raw | ConvertFrom-Json -AsHashtable
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
    $reportDepth=$MaxDepth
    if (-not $PSBoundParameters.ContainsKey('MaxDepth') -and $settings -and $settings.maxDepthByPath) {
        foreach ($configuredRoot in $settings.maxDepthByPath.Keys) {
            $resolvedRoot=$configuredRoot
            if (-not [IO.Path]::IsPathRooted($resolvedRoot)) { $resolvedRoot=Join-Path $configDir $resolvedRoot }
            $resolvedRoot=[IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($resolvedRoot))
            if ($resolvedRoot.Equals([IO.Path]::TrimEndingDirectorySeparator($root),$comparison)) {
                $parsedDepth=0
                if (-not [int]::TryParse([string]$settings.maxDepthByPath[$configuredRoot],[ref]$parsedDepth) -or $parsedDepth -lt 0 -or $parsedDepth -gt 100) { throw "Invalid maxDepthByPath for $configuredRoot" }
                $reportDepth=$parsedDepth
                break
            }
        }
    }
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
    $nodes.Values | Where-Object Depth -LE $reportDepth | Sort-Object Depth,Path |
        Select-Object Depth,Path,SizeBytes,SizeGiB,FileCount,DirCount,Reparse,Unreadable,Incomplete |
        Export-Csv -LiteralPath $file -NoTypeInformation -Encoding utf8BOM
    $finished = [DateTime]::UtcNow
    $rootNode = $nodes[$root]
    $culture = [Globalization.CultureInfo]::InvariantCulture
    $log = [Collections.Generic.List[string]]::new()
    function Add-LogField([string]$Name, [object]$Value) {
        $log.Add(('{0,-25}: {1}' -f $Name,$Value))
    }
    function Format-LogSize([long]$Bytes) {
        return ('{0} GiB ({1} bytes)' -f ($Bytes / 1GB).ToString('N2',$culture),$Bytes.ToString('N0',$culture))
    }
    $log.Add('DRIVE SNAPSHOT')
    $log.Add(('=' * 78))
    Add-LogField 'Status' $(if ($rootNode.Incomplete) { 'PARTIAL - measured sizes are lower bounds' } else { 'COMPLETED - no read errors recorded' })
    Add-LogField 'Root path' $root
    Add-LogField 'Started (UTC)' $started.ToString('yyyy-MM-dd HH:mm:ss')
    Add-LogField 'Finished (UTC)' $finished.ToString('yyyy-MM-dd HH:mm:ss')
    Add-LogField 'Elapsed' ('{0} s' -f ($finished-$started).TotalSeconds.ToString('N1',$culture))
    Add-LogField 'Elevated (Windows)' $(if ($IsWindows) { $isAdmin } else { 'N/A' })
    Add-LogField 'Reported depth' "$reportDepth (root = 0; full subtree traversed)"
    Add-LogField 'Output CSV' $file
    Add-LogField 'Excluded output folder' $OutDirRoot
    $log.Add('')
    $log.Add('SCAN SUMMARY')
    $log.Add(('-' * 78))
    Add-LogField 'Observed logical size' (Format-LogSize $rootNode.SizeBytes)
    Add-LogField 'Files observed' $rootNode.FileCount.ToString('N0',$culture)
    Add-LogField 'Directory records' $nodes.Count.ToString('N0',$culture)
    Add-LogField 'Rows exported' (@($nodes.Values | Where-Object Depth -LE $reportDepth).Count.ToString('N0',$culture))
    Add-LogField 'Directories with errors' (@($nodes.Values | Where-Object Unreadable -EQ 1).Count.ToString('N0',$culture))
    Add-LogField 'Read failures' $errors.Count.ToString('N0',$culture)
    Add-LogField 'Directory links skipped' (@($nodes.Values | Where-Object Reparse -EQ 1).Count.ToString('N0',$culture))
    $log.Add('File links are also skipped. Directory records include skipped directory links.')
    $log.Add('')
    $log.Add('VOLUME CAPACITY (filesystem allocation; separate from scan totals)')
    $log.Add(('-' * 78))
    try {
        # Select the longest matching mounted volume, including POSIX mount points.
        $volume = [IO.DriveInfo]::GetDrives() | Where-Object {
            $mount=$_.RootDirectory.FullName
            $prefix=$mount.TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
            $root.Equals($mount,$comparison) -or $root.StartsWith($prefix,$comparison)
        } | Sort-Object { $_.RootDirectory.FullName.Length } -Descending | Select-Object -First 1
        if (-not $volume -or -not $volume.IsReady) { throw 'No ready matching volume.' }
        Add-LogField 'Volume' $volume.RootDirectory.FullName
        Add-LogField 'Total capacity' (Format-LogSize $volume.TotalSize)
        Add-LogField 'Used allocation' (Format-LogSize ($volume.TotalSize-$volume.TotalFreeSpace))
        Add-LogField 'Total free' (Format-LogSize $volume.TotalFreeSpace)
        Add-LogField 'Available to caller' (Format-LogSize $volume.AvailableFreeSpace)
    } catch { $log.Add('Capacity unavailable; directory scan results are still valid.') }
    $log.Add('')
    $log.Add('TOP-LEVEL FOLDERS (recursive size, largest first; up to 30)')
    $log.Add(('-' * 78))
    $log.Add(('{0,12}  {1,12}  {2,-8}  {3}' -f 'Size GiB','Files','Coverage','Path'))
    $topFolders=@($nodes.Values | Where-Object Depth -EQ 1 | Sort-Object SizeBytes -Descending)
    foreach ($folder in ($topFolders | Select-Object -First 30)) {
        $coverage=if ($folder.Reparse) { 'LINK' } elseif ($folder.Incomplete) { 'PARTIAL' } else { 'OK' }
        $log.Add(('{0,12}  {1,12}  {2,-8}  {3}' -f ($folder.SizeBytes/1GB).ToString('N2',$culture),$folder.FileCount.ToString('N0',$culture),$coverage,$folder.Path))
    }
    if (-not $topFolders.Count) { $log.Add('(No child directories observed.)') }
    if ($topFolders.Count -gt 30) { $log.Add("... $($topFolders.Count-30) additional top-level folders omitted from this summary.") }
    $log.Add('OK = no recorded read errors; PARTIAL = lower bound; LINK = not traversed.')
    $log.Add('Root-level files contribute to the scan total, not to these child-folder totals.')
    $log.Add('This summary uses observed directories even when reported depth is 0.')
    $log.Add('')
    $log.Add('READ FAILURES')
    $log.Add(('-' * 78))
    if ($errors.Count) {
        for ($i=0; $i -lt $errors.Count; $i++) { $log.Add(('[{0}] {1}' -f ($i+1),$errors[$i])) }
        $log.Add('Affected directories and their ancestors are marked Incomplete in the CSV.')
        $log.Add('Administrator access may improve coverage; protected or locked data can remain unreadable.')
    } else { $log.Add('None recorded.') }
    $log.Add('')
    $log.Add('INTERPRETATION')
    $log.Add(('-' * 78))
    $log.Add('Compare snapshots with the same root, depth, exclusions, and privilege level.')
    $log.Add('Logical file sizes differ from allocated space (links, sparse files, compression).')
    $log.Add('Do not add recursive parent and child totals. Files can change during a scan.')
    $log.Add('READ-ONLY SCAN: scanned files are unchanged; only snapshot outputs are written.')
    [IO.File]::WriteAllLines([IO.Path]::ChangeExtension($file,'.log'),$log,[Text.UTF8Encoding]::new($true))
    if ($nodes[$root].Incomplete) {
        Write-Warning 'Partial snapshot: some entries could not be read. Sizes are lower bounds; inspect the log. On Windows, -Elevate may improve coverage but cannot guarantee it.'
    }
    Write-Output "Snapshot written: $file"
}
