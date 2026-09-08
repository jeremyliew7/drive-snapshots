#requires -Version 7.2
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('drive-snapshots-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testRoot | Out-Null
function Assert($condition,$message) { if (-not $condition) { throw $message } }
try {
    $source=Join-Path $testRoot 'source with spaces'
    $nested=Join-Path $source '中文, folder/deeper'
    New-Item -ItemType Directory -Path $nested -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $source 'a.bin'),[byte[]]::new(11))
    [IO.File]::WriteAllBytes((Join-Path $nested 'b.bin'),[byte[]]::new(29))
    $out=Join-Path $source 'snapshots'
    $config=Join-Path $testRoot 'settings.json'
    & "$project/drive-snapshot.ps1" -Init -Path $source -OutDirRoot $out -MaxDepth 1 -Config $config
    & "$project/drive-snapshot.ps1" -Config $config
    & "$project/drive-snapshot.ps1" -Config $config
    $csv=@(Get-ChildItem -LiteralPath $out -Recurse -Filter *.csv)
    Assert ($csv.Count -eq 2) 'History must retain distinct scans'
    foreach ($file in $csv) {
        $rows=@(Import-Csv -LiteralPath $file.FullName)
        Assert ([long]$rows[0].SizeBytes -eq 40) 'Totals must include deeper files and exclude prior output'
        Assert ([long]$rows[0].FileCount -eq 2) 'Recursive file count'
        Assert ($rows.Count -eq 2) 'Depth limits reported rows only'
        Assert ($rows[0].Incomplete -eq '0') 'Readable fixture should be complete'
    }
    $report=Join-Path $testRoot 'report.html'
    & "$project/export-report.ps1" -Snapshot $csv.FullName -Output $report
    $html=Get-Content -LiteralPath $report -Raw
    Assert ($html.Contains('<style>') -and -not $html.Contains('src="app.js"')) 'Report must bundle assets'
    $bad=Join-Path $testRoot 'injection.csv'
    @([pscustomobject]@{Depth=0;Path='/</script><script>alert(1)</script>';SizeBytes=1;FileCount=1}) | Export-Csv $bad -NoTypeInformation
    & "$project/export-report.ps1" -Snapshot @($bad) -Output $report
    Assert (-not (Get-Content $report -Raw).Contains('/</script><script>alert(1)</script>')) 'Embedded paths must be escaped'
    $failed=$false
    try { & "$project/drive-snapshot.ps1" -Path (Join-Path $testRoot 'missing') -Config $config } catch { $failed=$true }
    Assert $failed 'Missing root must fail instead of writing a zero snapshot'
    $failed=$false
    try { & "$project/drive-snapshot.ps1" -Init -Path $source -Config $config } catch { $failed=$true }
    Assert $failed 'Initialization must not overwrite config'
    if ($IsWindows) {
        # Deny enumeration on an isolated fixture, then restore its ACL before cleanup.
        $blocked=Join-Path $source 'blocked'
        New-Item -ItemType Directory -Path $blocked | Out-Null
        [IO.File]::WriteAllBytes((Join-Path $blocked 'private.bin'),[byte[]]::new(17))
        $original=Get-Acl -LiteralPath $blocked
        $restricted=Get-Acl -LiteralPath $blocked
        $identity=[Security.Principal.WindowsIdentity]::GetCurrent().User
        $rule=[Security.AccessControl.FileSystemAccessRule]::new($identity,[Security.AccessControl.FileSystemRights]::ListDirectory,[Security.AccessControl.AccessControlType]::Deny)
        $restricted.AddAccessRule($rule)
        try {
            Set-Acl -LiteralPath $blocked -AclObject $restricted
            & "$project/drive-snapshot.ps1" -Config $config -MaxDepth 0
            $latest=Get-ChildItem -LiteralPath $out -Recurse -Filter *.csv | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
            $partial=@(Import-Csv -LiteralPath $latest.FullName)
            Assert ($partial.Count -eq 1 -and $partial[0].Incomplete -eq '1') 'Permission failure below report depth must propagate to root'
            Assert ([long]$partial[0].SizeBytes -eq 40) 'Inaccessible bytes must not be invented'
        } finally { Set-Acl -LiteralPath $blocked -AclObject $original }
    }
    Write-Output 'PASS: scanner totals, depth, output exclusion, history, configuration, and safe standalone export'
} finally {
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $tempPrefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($tempPrefix) -and (Split-Path $resolved -Leaf).StartsWith('drive-snapshots-test-')) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
