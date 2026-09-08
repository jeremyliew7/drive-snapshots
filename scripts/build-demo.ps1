#requires -Version 7.2
$ErrorActionPreference='Stop'
$project = Split-Path $PSScriptRoot -Parent
$demo = Join-Path $project 'demo'
New-Item -ItemType Directory -Force -Path $demo | Out-Null
# Entirely invented directory names and sizes. Never enumerate the host.
$leaves = [ordered]@{
    'Projects/Atlas/source'=2; 'Projects/Atlas/build'=12; 'Projects/Orion/assets'=18;
    'Projects/Orion/node_modules'=8; 'Media/Films'=42; 'Media/Photography'=28;
    'Media/Audio'=9; 'Archives/2024'=24; 'Archives/2025'=32;
    'Downloads/Installers'=16; 'Downloads/Exports'=11; 'Environments/Python'=19;
    'Environments/Containers'=26; 'Documents/Research'=7; 'Documents/Personal'=3
}
$files=@()
foreach ($day in 1..4) {
    $sizes=@{}
    foreach ($entry in $leaves.GetEnumerator()) {
        $value=[long]($entry.Value * 1GB)
        if ($entry.Key -eq 'Projects/Atlas/build') { $value += ($day-1)*3GB }
        if ($entry.Key -eq 'Media/Photography') { $value += ($day-1)*2GB }
        if ($entry.Key -eq 'Downloads/Installers' -and $day -ge 3) { $value=4GB }
        if ($entry.Key -eq 'Downloads/Exports' -and $day -eq 4) { continue }
        $sizes['/Demo/'+$entry.Key]=$value
    }
    if ($day -eq 4) { $sizes['/Demo/Projects/Nova']=6GB }
    $totals=@{}; $counts=@{}
    foreach ($p in @($sizes.Keys)) {
        $cursor=$p
        while ($cursor) {
            $totals[$cursor] += $sizes[$p]; $counts[$cursor] += 120
            $cursor=$cursor -replace '/[^/]+$',''
        }
    }
    $rows=foreach ($p in ($totals.Keys | Sort-Object)) {
        [pscustomobject]@{Depth=($p.Split('/').Count-2);Path=$p;SizeBytes=$totals[$p];SizeGiB=$totals[$p]/1GB;FileCount=$counts[$p];DirCount=0;Reparse=0;Unreadable=0;Incomplete=0}
    }
    $file=Join-Path $demo "Demo-2026010${day}_120000.csv"
    $rows | Export-Csv -LiteralPath $file -NoTypeInformation -Encoding utf8BOM
    $files += $file
}
& (Join-Path $project 'export-report.ps1') -Snapshot $files -Output (Join-Path $demo 'index.html') -Synthetic
