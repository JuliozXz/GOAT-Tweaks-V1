[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
. (Join-Path $PSScriptRoot '../src/Benchmark.ps1')
$script:assertions = 0
function Assert-True { param($Condition,[string]$Message); $script:assertions++; if (-not $Condition) { throw "FAILED: $Message" } }
function Assert-Near { param([double]$Actual,[double]$Expected,[string]$Message); Assert-True ([Math]::Abs($Actual-$Expected) -lt 0.000001) "$Message (actual=$Actual expected=$Expected)" }
function Assert-Throws { param([scriptblock]$Action,[string]$Message); $didThrow=$false; try { & $Action | Out-Null } catch { $didThrow=$true }; Assert-True $didThrow $Message }
$temp = Join-Path ([IO.Path]::GetTempPath()) ('goat-benchmark-tests-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($temp) | Out-Null
try {
    $frames = [double[]](@(1..100 | ForEach-Object { 10.0 }))
    $metrics = Get-GoatFrameMetrics $frames
    Assert-Near $metrics.AverageFps 100 'average FPS uses total time'
    Assert-Near $metrics.OnePercentLowFps 100 'tail FPS on uniform capture'
    Assert-Near $metrics.FrameTimeP95Ms 10 'uniform percentile'
    Assert-True ($metrics.InputLatencyStatus -eq 'NOT_MEASURED') 'input latency stays unmeasured'
    Assert-True ($metrics.NetworkLatencyStatus -eq 'NOT_MEASURED') 'network latency stays unmeasured'
    $ramp = [double[]](1..100)
    $rampMetrics = Get-GoatFrameMetrics $ramp
    Assert-Near $rampMetrics.AverageFps (1000.0/50.5) 'average is reciprocal mean, not mean of reciprocal FPS'
    Assert-Near $rampMetrics.OnePercentLowFps 10 'slowest ceil 1% tail method'
    Assert-Near $rampMetrics.FrameTimeP50Ms 50.5 'R7 median'
    Assert-Near $rampMetrics.FrameTimeP95Ms 95.05 'R7 p95'
    Assert-Near $rampMetrics.FrameTimeP99Ms 99.01 'R7 p99'
    Assert-Throws { Get-GoatFrameMetrics ([double[]](1..99)) } 'insufficient sample rejected'
    Assert-Throws { Get-GoatFrameMetrics ([double[]](@(0.0) + @(1..100))) } 'zero sample rejected'
    Assert-Throws { Get-GoatFrameMetrics ([double[]](@([double]::NaN) + @(1..100))) } 'NaN rejected'
    Assert-Throws { Get-GoatFrameMetrics ([double[]](@([double]::PositiveInfinity) + @(1..100))) } 'infinity rejected'
    Assert-Throws { Get-GoatFrameMetrics ([double[]](@(-1.0) + @(1..100))) } 'negative sample rejected'
    $conditions = @{Game='Fixture game';GameBuild='1';Scene='route A';Resolution='1920x1080';Preset='High';Api='DX12';Driver='1';OsBuild='22631';FrameCap='off';VSync='off';CaptureTool='Fixture';CaptureVersion='1'}
    $path = Join-Path $temp 'frames.csv'
    [IO.File]::WriteAllLines($path, [string[]](@('Application,ProcessID,SwapChainAddress,MsBetweenPresents') + @(1..100 | ForEach-Object { 'game.exe,42,0x01,10' })))
    $capture = Import-GoatFrameCapture -Path $path -Conditions $conditions
    Assert-True ($capture.Source.RowsImported -eq 100) 'CSV imports exact frame count'
    Assert-True ($capture.Source.Column -eq 'MsBetweenPresents') 'PresentMon field detected'
    Assert-True ($capture.Source.Sha256.Length -eq 64) 'raw source hash recorded'
    Assert-True ($capture.RawFrameTimesMs.Count -eq 100) 'raw samples retained'
    Assert-True ($capture.Source.PSObject.Properties.Name -notcontains 'FullPath') 'personal directory path omitted'
    Assert-Near $capture.Metrics.AverageFps 100 'CSV metrics match supplied frames'
    $selected = Import-GoatFrameCapture -Path $path -Conditions $conditions -ProcessId 42
    Assert-True ($selected.Source.RowsImported -eq 100) 'explicit PID selection works'
    Assert-Throws { Import-GoatFrameCapture -Path $path -Conditions $conditions -ProcessId 99 } 'missing PID rejected'
    [IO.File]::AppendAllText($path, "`nother.exe,84,0x02,10")
    Assert-Throws { Import-GoatFrameCapture -Path $path -Conditions $conditions } 'multi-process aggregation rejected'
    $selected = Import-GoatFrameCapture -Path $path -Conditions $conditions -ProcessId 42
    Assert-True ($selected.Source.RowsImported -eq 100) 'PID selects only requested process'
    [IO.File]::WriteAllLines($path, [string[]](@('ProcessID,SwapChainAddress,MsBetweenPresents') + @(1..100 | ForEach-Object { '42,0x01,10' }) + @('42,0x02,10')))
    Assert-Throws { Import-GoatFrameCapture -Path $path -Conditions $conditions } 'multiple swapchains rejected'
    [IO.File]::WriteAllLines($path, [string[]](@('FrameTimeMs;Other') + @(1..100 | ForEach-Object { '10,5;safe' })))
    $localized = Import-GoatFrameCapture -Path $path -Conditions $conditions -Delimiter ';' -CultureName 'pt-BR'
    Assert-Near $localized.Metrics.FrameTimeP50Ms 10.5 'localized decimal and delimiter explicit'
    Assert-Throws { Import-GoatFrameCapture -Path $path -Conditions $conditions -Delimiter ';' } 'wrong decimal culture rejected'
    [IO.File]::WriteAllLines($path, [string[]](@('FrameTimeMs') + @(1..100 | ForEach-Object { '10' }) + @('not-a-number')))
    Assert-Throws { Import-GoatFrameCapture -Path $path -Conditions $conditions } 'invalid rows never silently dropped'
    [IO.File]::WriteAllText($path, 'Timestamp,Value')
    Assert-Throws { Import-GoatFrameCapture -Path $path -Conditions $conditions } 'empty CSV rejected'
    function New-FixtureRun {
        param([double]$Interval,[int]$Pass,[string]$Label='Baseline')
        [pscustomobject]@{PassNumber=$Pass; ConditionLabel=$Label; Conditions=[pscustomobject]$conditions.Clone(); Metrics=(Get-GoatFrameMetrics ([double[]](@(1..100 | ForEach-Object { $Interval })))); Source=[pscustomobject]@{Column='FrameTimeMs';Sha256=([guid]::NewGuid().ToString('N')+[guid]::NewGuid().ToString('N'))}}
    }
    $baseline = @(1..3 | ForEach-Object { New-FixtureRun 10 $_ })
    $after = @(1..3 | ForEach-Object { New-FixtureRun 9.999 $_ 'After' })
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True ($comparison.Status -eq 'BENEFIT_CONFIRMED') 'tiny repeatable gain is not discarded by percentage threshold'
    Assert-True ($comparison.Metrics.Count -eq 5) 'five metrics compared'
    Assert-True ($comparison.ConditionsMatch) 'same conditions recognized'
    $comparison = Compare-GoatBenchmarkRuns $baseline $after
    Assert-True ($comparison.Status -eq 'INCONCLUSIVE') 'unverified stability never confirmed as benefit'
    $comparison = Compare-GoatBenchmarkRuns @($baseline[0]) @($after[0]) -StabilityVerified
    Assert-True ($comparison.Status -eq 'INCONCLUSIVE') 'single pass stays inconclusive'
    Assert-True ($null -eq $comparison.Metrics[0].RelativeDeltaPercent) 'single pass does not print gain percentage'
    $after[0].Conditions.Resolution='2560x1440'
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True (-not $comparison.ConditionsMatch) 'different resolution detected'
    Assert-True ($comparison.Metrics.Count -eq 0) 'no delta calculated on incompatible runs'
    $after[0].Conditions.Resolution='1920x1080'
    $after[0].Conditions.Driver='unknown'
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True ($comparison.Status -eq 'INCONCLUSIVE') 'driver changes prevent attribution'
    $after[0].Conditions.Driver='1'
    foreach ($run in $baseline) { $run.Conditions.Driver='unknown' }
    foreach ($run in $after) { $run.Conditions.Driver='unknown' }
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True (-not $comparison.ConditionsMatch) 'matching unknown drivers are still unverified'
    foreach ($run in $baseline) { $run.Conditions.Driver='1' }
    foreach ($run in $after) { $run.Conditions.Driver='1' }
    foreach ($run in $baseline) { $run.Conditions|Add-Member -NotePropertyName FrameGeneration -NotePropertyValue 'off' }
    foreach ($run in $after) { $run.Conditions|Add-Member -NotePropertyName FrameGeneration -NotePropertyValue 'on' }
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True (-not $comparison.ConditionsMatch) 'documented frame generation changes prevent false FPS attribution'
    foreach ($run in @($baseline)+@($after)) { $run.Conditions.PSObject.Properties.Remove('FrameGeneration') }
    $after[0].Metrics.OnePercentLowMethod='different method'
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True (-not $comparison.ConditionsMatch) 'mixed percentile methods are rejected'
    $after[0].Metrics.OnePercentLowMethod=$baseline[0].Metrics.OnePercentLowMethod
    $after[0].Source.Column='MsBetweenDisplayChange'
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True (-not $comparison.ConditionsMatch) 'different metric semantics blocked'
    $after[0].Source.Column='FrameTimeMs'
    $after[0].Source.Sha256=''
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True (-not $comparison.ConditionsMatch) 'missing provenance hash blocks comparison'
    $after[0].Source.Sha256=$baseline[0].Source.Sha256
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True (-not $comparison.ConditionsMatch) 'duplicated raw capture cannot count as independent pass'
    $after = @(1..3 | ForEach-Object { New-FixtureRun 12 $_ 'After' })
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True ($comparison.Status -eq 'REGRESSION_DETECTED') 'repeatable regression detected'
    $after = @((New-FixtureRun 9 1 'After'),(New-FixtureRun 10 2 'After'),(New-FixtureRun 11 3 'After'))
    $comparison = Compare-GoatBenchmarkRuns $baseline $after -StabilityVerified
    Assert-True ($comparison.Status -eq 'INCONCLUSIVE') 'overlapping run ranges stay inconclusive'
    $comparison = Compare-GoatBenchmarkRuns @() @()
    Assert-True ($comparison.Status -eq 'INCONCLUSIVE') 'no data produces no fake measurements'
    Write-Output "PASS: $script:assertions benchmark assertions. No system settings were changed."
} finally {
    $resolvedTemp = [IO.Path]::GetFullPath($temp)
    $resolvedTempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedTemp.StartsWith($resolvedTempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path -Leaf $resolvedTemp) -notlike 'goat-benchmark-tests-*') { throw 'Refusing cleanup outside owned fixture directory.' }
    Remove-Item -LiteralPath $resolvedTemp -Recurse -Force -ErrorAction SilentlyContinue
}
