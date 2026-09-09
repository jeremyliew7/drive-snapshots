#requires -Version 7.2
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$fixture=Join-Path ([IO.Path]::GetTempPath()) ('drive-depth-test-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $fixture | Out-Null
function Assert($value,$message) { if (-not $value) { throw $message } }
try {
    $tree=Join-Path $fixture 'tree'
    foreach ($p in @('a/x','a/y','b/x','b/y')) { New-Item -ItemType Directory -Path (Join-Path $tree $p) -Force | Out-Null }
    $result=& "$project/measure-snapshot-depth.ps1" -Path $tree -TargetRows 3 -Output ''
    Assert ($result.RecommendedMaxDepth -eq 1 -and $result.StopReason -eq 'RowBudget') 'Wide next level should recommend the previous complete level'
    $result=& "$project/measure-snapshot-depth.ps1" -Path $tree -TargetRows 20 -Output ''
    Assert ($result.RecommendedMaxDepth -eq 2 -and $result.ObservedRows -eq 7) 'Small tree should retain all observed detail'
    $result=& "$project/measure-snapshot-depth.ps1" -Path $tree -MaxEntries 1 -Output ''
    Assert ($result.StopReason -eq 'EntryBudget' -and $result.Confidence -eq 'Low' -and $result.RecommendedMaxDepth -eq 0) 'Truncated level must not be recommended as complete'
    $result=& "$project/measure-snapshot-depth.ps1" -Path $tree -ExcludePath (Join-Path $tree 'a') -Output ''
    Assert ($result.ObservedRows -eq 4) 'Output exclusions must be omitted'
    $result=@(& "$project/measure-snapshot-depth.ps1" -Path (Join-Path $fixture 'missing'),$tree -Output '')
    Assert ($null -eq $result[0].RecommendedMaxDepth -and $result[1].RecommendedMaxDepth -eq 2) 'Invalid disk must not prevent other assessments'
    $empty=Join-Path $fixture 'empty'
    New-Item -ItemType Directory -Path $empty | Out-Null
    $config=Join-Path $fixture 'snapshot.config.json'
    $output=Join-Path $fixture 'output'
    & "$project/initialize-snapshots.ps1" -Path $tree,$empty -OutDirRoot $output -Config $config
    $settings=Get-Content $config -Raw | ConvertFrom-Json -AsHashtable
    Assert ($settings.maxDepthByPath[$tree] -eq 2 -and $settings.maxDepthByPath[$empty] -eq 0) 'Initialization must save independent depths for each root'
    Assert (-not (Test-Path $output)) 'Initialization must not generate snapshots'
    $hash=(Get-FileHash $config).Hash
    $failed=$false
    try { & "$project/initialize-snapshots.ps1" -Path $tree -Config $config } catch { $failed=$true }
    Assert ($failed -and (Get-FileHash $config).Hash -eq $hash) 'Existing config must be preserved'
    & "$project/drive-snapshot.ps1" -Config $config
    $csv=@(Get-ChildItem $output -Recurse -Filter *.csv)
    Assert ($csv.Count -eq 2) 'Both configured roots must be captured'
    foreach ($file in $csv) {
        $rows=@(Import-Csv $file.FullName)
        $expected=if ($rows[0].Path -eq $tree) { 7 } else { 1 }
        Assert ($rows.Count -eq $expected) 'Scanner must use each root depth'
    }
    & "$project/drive-snapshot.ps1" -Config $config -Path $tree -MaxDepth 0
    $latest=Get-ChildItem $output -Recurse -Filter *.csv | Sort-Object LastWriteTimeUtc | Select-Object -Last 1
    Assert (@(Import-Csv $latest.FullName).Count -eq 1) 'Explicit depth must override per-root defaults'
    Assert ((Get-FileHash $config).Hash -eq $hash) 'One-off scan must not rewrite defaults'
    Write-Output 'PASS: depth budgets, initialization, per-root defaults, overrides, and config preservation'
} finally {
    $resolved=[IO.Path]::GetFullPath($fixture)
    $prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd([IO.Path]::DirectorySeparatorChar)+[IO.Path]::DirectorySeparatorChar
    if ($resolved.StartsWith($prefix) -and (Split-Path $resolved -Leaf).StartsWith('drive-depth-test-')) { Remove-Item -LiteralPath $resolved -Recurse -Force }
}
