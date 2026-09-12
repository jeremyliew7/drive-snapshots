#requires -Version 7.2
<#
.SYNOPSIS
Convert a WizTree CSV export into the directory snapshot schema used by the viewer.

.DESCRIPTION
Reads the WizTree export as a stream and writes one row per folder. The original
WizTree CSV remains the source artifact; the converted file is optimized for the
offline Drive Snapshots viewer and report exporter.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [Alias('FullName')]
    [string[]]$InputPath,
    [string]$OutputDirectory = (Join-Path $PSScriptRoot 'snapshots/wiztree/converted'),
    [ValidateRange(0,100)][int]$ViewDepth = 5,
    [switch]$Force
)

begin {
    $ErrorActionPreference = 'Stop'
    $rowPattern = [regex]'^"(?<path>[^"]*)",(?<size>\d+),(?<allocated>\d*),(?<modified>[^,]*),(?<attributes>\d+),(?<files>\d+),(?<folders>\d+),'
    $utf8Bom = [Text.UTF8Encoding]::new($true)

    function Get-RelativeDepth([string]$Root, [string]$Path) {
        $rootValue = $Root.TrimEnd('\')
        $pathValue = $Path.TrimEnd('\')
        if ($pathValue.Equals($rootValue, [StringComparison]::OrdinalIgnoreCase)) { return 0 }
        $prefix = $rootValue + '\'
        if (-not $pathValue.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Folder is outside the WizTree root: $Path"
        }
        $relative = $pathValue.Substring($prefix.Length)
        return 1 + ([regex]::Matches($relative, '\\').Count)
    }
}

process {
    foreach ($candidate in $InputPath) {
        $source = (Get-Item -LiteralPath $candidate -Force).FullName
        if ([IO.Path]::GetExtension($source) -ne '.csv') { throw "Expected a CSV file: $source" }
        $null = New-Item -ItemType Directory -Path $OutputDirectory -Force
        $outDir = (Resolve-Path -LiteralPath $OutputDirectory).Path
        $stem = [IO.Path]::GetFileNameWithoutExtension($source)
        $output = Join-Path $outDir ($stem + '_folders.csv')
        if ((Test-Path -LiteralPath $output) -and -not $Force) {
            throw "Output already exists: $output (use -Force to replace it)"
        }

        $reader = [IO.StreamReader]::new($source, [Text.Encoding]::UTF8, $true, 1MB)
        $temp = Join-Path $outDir ('.' + [IO.Path]::GetFileName($output) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
        $writer = [IO.StreamWriter]::new($temp, $false, $utf8Bom, 1MB)
        $root = $null
        $folders = 0L
        $completed = $false
        try {
            $banner = $reader.ReadLine()
            $header = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($banner) -or [string]::IsNullOrWhiteSpace($header)) {
                throw "WizTree CSV is missing its banner or header: $source"
            }
            $writer.WriteLine('Depth,Path,SizeBytes,SizeGiB,FileCount,DirCount,DescendantDirCount,AllocatedBytes,Reparse,Unreadable,Incomplete,SnapshotScope,ViewDepth,Source,Coverage')
            while ($null -ne ($line = $reader.ReadLine())) {
                $match = $rowPattern.Match($line)
                if (-not $match.Success) { continue }
                $path = $match.Groups['path'].Value
                if (-not $path.EndsWith('\')) { continue }
                if (-not $root) { $root = $path }
                $depth = Get-RelativeDepth -Root $root -Path $path
                $size = [long]$match.Groups['size'].Value
                $allocatedRaw = $match.Groups['allocated'].Value
                $allocated = if ($allocatedRaw) { [long]$allocatedRaw } else { 0L }
                $files = [long]$match.Groups['files'].Value
                $descendantFolders = [long]$match.Groups['folders'].Value
                $escapedPath = $path.Replace('"','""')
                $sizeGiB = ($size / 1GB).ToString('0.0000', [Globalization.CultureInfo]::InvariantCulture)
                $writer.WriteLine(('{0},"{1}",{2},{3},{4},0,{5},{6},{7},0,0,Full,{8},WizTree,Unknown' -f
                    $depth,$escapedPath,$size,$sizeGiB,$files,$descendantFolders,$allocated,0,$ViewDepth))
                $folders++
            }
            if (-not $root -or $folders -eq 0) { throw "No folder rows were found in WizTree CSV: $source" }
            $completed = $true
        } finally {
            $reader.Dispose()
            $writer.Dispose()
            if (-not $completed -and (Test-Path -LiteralPath $temp)) {
                Remove-Item -LiteralPath $temp -Force
            }
        }

        if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
        Move-Item -LiteralPath $temp -Destination $output
        [pscustomobject]@{
            SourceCsv = $source
            SnapshotCsv = $output
            Root = $root
            FolderRows = $folders
            Coverage = 'Unknown'
        }
    }
}
