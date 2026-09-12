#requires -Version 7.2
<# .SYNOPSIS
Bundle CSV snapshots and the offline viewer into one private HTML report.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string[]]$Snapshot,
    [string]$Output = (Join-Path $PSScriptRoot 'reports/latest.html'),
    [switch]$Synthetic
)
$ErrorActionPreference='Stop'
$data = @(
    foreach ($file in ($Snapshot | Sort-Object)) {
        $rows = @(Import-Csv -LiteralPath $file)
        if (-not $rows.Count -or @($rows | Where-Object Depth -EQ '0').Count -ne 1) { throw "Expected one root row: $file" }
        foreach ($row in $rows) {
            foreach ($column in @('Path','Depth','SizeBytes','FileCount')) {
                if ($null -eq $row.PSObject.Properties[$column]) { throw "Missing $column in $file" }
            }
        }
        @{label=[IO.Path]::GetFileName($file); rows=$rows; synthetic=[bool]$Synthetic}
    }
)
$json = ConvertTo-Json -InputObject $data -Depth 8 -Compress
# Prevent filenames from terminating the inert JSON script element.
$json = $json.Replace('<','\u003c').Replace('>','\u003e').Replace('&','\u0026')
$template = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'viewer/index.html') -Raw
$css = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'viewer/style.css') -Raw
$js = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'viewer/app.js') -Raw
$template = $template.Replace('<link rel="stylesheet" href="style.css">',"<style>$css</style>")
$template = $template.Replace('<script src="app.js"></script>',"<script>$js</script>")
$template = $template.Replace('<script id="snapshot-data" type="application/json">[]</script>',"<script id=`"snapshot-data`" type=`"application/json`">$json</script>")
$Output = [IO.Path]::GetFullPath($Output)
New-Item -ItemType Directory -Force -Path (Split-Path $Output -Parent) | Out-Null
Set-Content -LiteralPath $Output -Value ($template.TrimEnd()+"`n") -Encoding utf8 -NoNewline
Write-Output "Report written: $Output"
