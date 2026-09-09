function Select-SnapshotDepth {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Levels,
        [AllowNull()][object]$FallbackDepth,
        [ValidateSet('Growth','Budget')][string]$Strategy='Growth',
        [int]$MinAddedRows=5000,
        [double]$GrowthFactor=3
    )
    $previous=0
    $annotated=@(foreach ($level in ($Levels | Sort-Object Depth)) {
        $added=$level.CumulativeRows-$previous
        $ratio=if ($previous -gt 0) { $level.CumulativeRows/[double]$previous } else { $null }
        [pscustomobject]@{
            Depth=$level.Depth; AddedRows=$added; CumulativeRows=$level.CumulativeRows
            GrowthRatio=if ($null -ne $ratio) { [math]::Round($ratio,2) } else { $null }
            LevelComplete=$level.LevelComplete
            GrowthOnset=($level.Depth -gt 0 -and $level.LevelComplete -and $added -ge $MinAddedRows -and $ratio -ge $GrowthFactor)
        }
        $previous=$level.CumulativeRows
    })
    $onset=$annotated | Where-Object GrowthOnset | Select-Object -First 1
    $chosen=$FallbackDepth
    $basis='DeepestWithinBudget'
    if ($null -eq $FallbackDepth) { $basis='Unavailable' }
    elseif ($Strategy -eq 'Growth' -and $onset -and $onset.Depth -le $FallbackDepth) {
        # Include the first informative expansion, rather than hiding its detail.
        $chosen=$onset.Depth
        $basis='FirstSignificantGrowth'
    }
    [pscustomobject]@{Depth=$chosen; Basis=$basis; Levels=$annotated}
}
