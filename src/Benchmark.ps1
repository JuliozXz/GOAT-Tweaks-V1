# Benchmark analysis never changes Windows settings or launches capture tools.
# An explicit SnapshotPath preserves exactly the analyzed CSV bytes.
# Windows PowerShell 5.1 compatible; metric calculations use actual supplied frames.

function Get-GoatPercentile {
    [CmdletBinding()]
    param([Parameter(Mandatory)][double[]]$SortedValues, [Parameter(Mandatory)][ValidateRange(0,100)][double]$Percentile)
    if ($SortedValues.Count -eq 0) { throw 'No samples were supplied.' }
    $position = ($SortedValues.Count - 1) * $Percentile / 100.0
    $lower = [int][Math]::Floor($position)
    $upper = [int][Math]::Ceiling($position)
    return $SortedValues[$lower] + ($position - $lower) * ($SortedValues[$upper] - $SortedValues[$lower])
}

function Get-GoatFrameMetrics {
    [CmdletBinding()]
    param([Parameter(Mandatory)][double[]]$FrameTimesMs)
    if ($FrameTimesMs.Count -lt 100) { throw 'At least 100 positive frame intervals are required to calculate a 1% low.' }
    foreach ($interval in $FrameTimesMs) {
        if ([double]::IsNaN($interval) -or [double]::IsInfinity($interval) -or $interval -le 0) {
            throw 'Frame intervals must be finite positive milliseconds; no invalid samples are discarded.'
        }
    }
    $sorted = @($FrameTimesMs | Sort-Object)
    $sum = 0.0
    foreach ($interval in $FrameTimesMs) { $sum += $interval }
    if ([double]::IsInfinity($sum)) { throw 'Frame interval sum exceeds numeric limits.' }
    $tailCount = [Math]::Max(1, [int][Math]::Ceiling($sorted.Count * 0.01))
    $tailSum = 0.0
    for ($index = $sorted.Count - $tailCount; $index -lt $sorted.Count; $index++) { $tailSum += $sorted[$index] }
    return [pscustomobject][ordered]@{
        SampleCount = $FrameTimesMs.Count
        DurationSeconds = $sum / 1000.0
        AverageFps = 1000.0 * $FrameTimesMs.Count / $sum
        OnePercentLowFps = 1000.0 * $tailCount / $tailSum
        FrameTimeP50Ms = Get-GoatPercentile -SortedValues $sorted -Percentile 50
        FrameTimeP95Ms = Get-GoatPercentile -SortedValues $sorted -Percentile 95
        FrameTimeP99Ms = Get-GoatPercentile -SortedValues $sorted -Percentile 99
        MinimumFrameTimeMs = $sorted[0]
        MaximumFrameTimeMs = $sorted[$sorted.Count - 1]
        OnePercentLowMethod = '1000 / arithmetic mean of the slowest ceil(1% * N) frame intervals (ms)'
        PercentileMethod = 'R7 linear interpolation at (N-1)*p'
        FpsMethod = 'N * 1000 / sum(frame intervals in ms); presented/displayed semantics depend on the capture column'
        LowSampleWarning = $(if ($FrameTimesMs.Count -lt 1000) { 'Fewer than 1000 intervals: tail metrics have limited precision.' } else { $null })
        InputLatency = $null
        InputLatencyStatus = 'NOT_MEASURED'
        NetworkLatency = $null
        NetworkLatencyStatus = 'NOT_MEASURED'
    }
}

function Read-GoatFrameSource {
    param([Parameter(Mandatory)][string]$Path)
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    if($file.PSIsContainer -or $file.Extension -ine '.csv'){throw 'Choose a CSV capture file.'}
    # Readers are allowed, writers/deletes are not. A live capture must be closed
    # first. Parsed text, hash and optional saved source derive from these bytes.
    $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
    try {
        if($stream.Length -gt 100MB){throw 'Capture exceeds the 100 MiB import limit. Export a bounded capture first.'}
        $bytes=New-Object byte[] ([int]$stream.Length)
        $offset=0
        while($offset -lt $bytes.Length){
            $read=$stream.Read($bytes,$offset,$bytes.Length-$offset)
            if($read -le 0){throw 'Capture ended before its complete byte snapshot could be read.'}
            $offset+=$read
        }
    } finally {$stream.Dispose()}
    $algorithm=[Security.Cryptography.SHA256]::Create()
    try{$hash=([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$algorithm.Dispose()}
    $memory=[IO.MemoryStream]::new([byte[]]$bytes,$false)
    $reader=[IO.StreamReader]::new($memory,[Text.UTF8Encoding]::new($false,$true),$true)
    try{$text=$reader.ReadToEnd()}finally{$reader.Dispose();$memory.Dispose()}
    [pscustomobject]@{Bytes=$bytes;Text=$text;Sha256=$hash;FileName=$file.Name}
}

function Write-GoatCaptureSnapshot {
    param([Parameter(Mandatory)][byte[]]$Bytes,[Parameter(Mandatory)][string]$Path,[Parameter(Mandatory)][string]$ExpectedSha256)
    $full=[IO.Path]::GetFullPath($Path)
    if([IO.Path]::GetExtension($full) -ine '.csv'){throw 'Capture snapshot must use a .csv extension.'}
    $parent=Split-Path $full -Parent
    [void][IO.Directory]::CreateDirectory($parent)
    if([IO.File]::Exists($full)){throw 'Capture snapshot destination already exists; it will not be overwritten.'}
    $temporary=Join-Path $parent ('.goat-capture-'+[guid]::NewGuid().ToString('N')+'.partial')
    # Explicit SnapshotPath saves a copy, never changes Windows settings. Existing
    # files are never overwritten. Only a complete verified temporary is moved to
    # the final CSV name. Failed partial files remain clearly marked for diagnosis.
    $stream=[IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
    try {
        $stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true);$stream.Position=0
        $algorithm=[Security.Cryptography.SHA256]::Create()
        try{$actual=([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$algorithm.Dispose()}
        if($actual -cne $ExpectedSha256 -or $stream.Length -ne $Bytes.Length){throw 'Saved capture snapshot failed byte/hash verification. Preserve the file for diagnosis.'}
    } finally {$stream.Dispose()}
    [IO.File]::Move($temporary,$full) # Same directory, no overwrite on a race.
    [IO.Path]::GetFileName($full)
}

function Import-GoatFrameCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][hashtable]$Conditions,
        [ValidateSet('Baseline','After')][string]$ConditionLabel = 'Baseline',
        [ValidateRange(1,10000)][int]$PassNumber = 1,
        [string]$FrameTimeColumn,
        [Nullable[int]]$ProcessId,
        [char]$Delimiter = ',',
        [string]$CultureName = '',
        [string]$SnapshotPath
    )
    $snapshot=Read-GoatFrameSource -Path $Path
    $culture = [Globalization.CultureInfo]::GetCultureInfo($CultureName)
    $rows = @(ConvertFrom-Csv -InputObject $snapshot.Text -Delimiter $Delimiter -ErrorAction Stop)
    if ($rows.Count -eq 0) { throw 'Capture CSV is empty.' }
    $headers = @($rows[0].PSObject.Properties.Name)
    if ([string]::IsNullOrWhiteSpace($FrameTimeColumn)) {
        foreach ($candidate in @('FrameTimeMs','MsBetweenPresents','MsBetweenDisplayChange','CPUFrameTime','FrameTime')) {
            if ($headers -contains $candidate) { $FrameTimeColumn = $candidate; break }
        }
    }
    if ([string]::IsNullOrWhiteSpace($FrameTimeColumn) -or $headers -notcontains $FrameTimeColumn) {
        throw 'No supported millisecond interval column found. Specify -FrameTimeColumn for a documented interval column.'
    }
    $processColumn = $null
    foreach ($candidate in @('ProcessID','ProcessId','PID')) {
        if ($headers -contains $candidate) { $processColumn = $candidate; break }
    }
    if ($null -ne $ProcessId) {
        if ($null -eq $processColumn) { throw 'Process selection requires a ProcessID or PID column.' }
        $rows = @($rows | Where-Object { [string]$_.$processColumn -eq [string]$ProcessId })
        if ($rows.Count -eq 0) { throw 'Selected process has no capture rows.' }
    } elseif ($null -ne $processColumn) {
        $processes = @($rows | ForEach-Object { [string]$_.$processColumn } | Select-Object -Unique)
        if ($processes.Count -gt 1) { throw 'Capture contains several processes. Select exactly one with -ProcessId.' }
    } elseif ($headers -contains 'Application') {
        $applications = @($rows | ForEach-Object { [string]$_.Application } | Select-Object -Unique)
        if ($applications.Count -gt 1) { throw 'Capture contains several applications. Export one application or provide ProcessID.' }
    }
    # One process may have several swap chains. Mixing independent streams invents FPS.
    foreach ($streamColumn in @('SwapChainAddress','SwapChain')) {
        if ($headers -contains $streamColumn) {
            $streams = @($rows | ForEach-Object { [string]$_.$streamColumn } | Select-Object -Unique)
            if ($streams.Count -gt 1) { throw 'Capture contains multiple swap chains. Export one rendering stream before import.' }
        }
    }
    $intervals = New-Object 'System.Collections.Generic.List[double]'
    $rowNumber = 1
    foreach ($row in $rows) {
        $rowNumber++
        $number = 0.0
        if (-not [double]::TryParse([string]$row.$FrameTimeColumn, [Globalization.NumberStyles]::Float, $culture, [ref]$number)) {
            throw "Invalid interval at CSV row $rowNumber. Check delimiter, units and numeric culture."
        }
        if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -le 0) {
            throw "Non-positive or non-finite interval at CSV row $rowNumber. Export a valid capture; samples are never silently removed."
        }
        $intervals.Add($number)
    }
    $safeConditions = [ordered]@{}
    foreach ($name in @('Game','GameBuild','Scene','Resolution','Preset','Api','Driver','OsBuild','FrameCap','VSync','CaptureTool','CaptureVersion','WarmupSeconds','ExpectedDurationSeconds','FrameGeneration','Upscaler','RenderScale','MonitorRefreshHz','DisplayMode','OverlayState','PowerState','BackgroundState','CaptureProtocol')) {
        if ($Conditions.ContainsKey($name)) { $safeConditions[$name] = [string]$Conditions[$name] }
    }
    $semantics = switch ($FrameTimeColumn.ToLowerInvariant()) {
        'msbetweenpresents' { 'Presented-frame intervals; not display latency or input latency.' }
        'msbetweendisplaychange' { 'Display-change intervals; not input latency.' }
        'cpuframetime' { 'CPU frame intervals; not GPU time, display latency or input latency.' }
        default { 'User-supplied millisecond frame intervals; verify the capture tool definition.' }
    }
    $metrics=Get-GoatFrameMetrics -FrameTimesMs $intervals.ToArray()
    $snapshotName=$null
    if(-not [string]::IsNullOrWhiteSpace($SnapshotPath)){
        $snapshotName=Write-GoatCaptureSnapshot -Bytes $snapshot.Bytes -Path $SnapshotPath -ExpectedSha256 $snapshot.Sha256
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        CaptureId = [guid]::NewGuid().ToString('N')
        ImportedAtUtc = [DateTime]::UtcNow.ToString('o')
        ConditionLabel = $ConditionLabel
        PassNumber = $PassNumber
        Conditions = [pscustomobject]$safeConditions
        Metrics = $metrics
        Source = [pscustomobject]@{
            FileName = $snapshot.FileName
            Sha256 = $snapshot.Sha256
            SnapshotFileName = $snapshotName
            SnapshotStatus = $(if($snapshotName){'SAVED_AND_HASH_VERIFIED'}else{'NOT_REQUESTED'})
            Column = $FrameTimeColumn
            Units = 'ms'
            Semantics = $semantics
            ProcessId = $ProcessId
            RowsImported = $intervals.Count
        }
        RawFrameTimesMs = $intervals.ToArray()
    }
}

function Get-GoatRunProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object -is [System.Collections.IDictionary]) { return $Object[$Name] }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) { return $property.Value }
    return $null
}

function Get-GoatRunSummary {
    param([double[]]$Values)
    $sorted = @($Values | Sort-Object)
    return [pscustomobject]@{
        Median = Get-GoatPercentile -SortedValues $sorted -Percentile 50
        Minimum = $sorted[0]
        Maximum = $sorted[$sorted.Count - 1]
        Range = $sorted[$sorted.Count - 1] - $sorted[0]
        PassCount = $sorted.Count
    }
}

function Compare-GoatBenchmarkRuns {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$BaselineRuns,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$AfterRuns,
        [ValidateSet('AverageFps','OnePercentLowFps','FrameTimeP95Ms','FrameTimeP99Ms')][string]$PrimaryMetric = 'AverageFps',
        [switch]$StabilityVerified
    )
    $result = [ordered]@{
        Status = 'INCONCLUSIVE'
        Reason = ''
        PrimaryMetric = $PrimaryMetric
        BaselinePassCount = $BaselineRuns.Count
        AfterPassCount = $AfterRuns.Count
        ConditionsMatch = $false
        ConditionsIssues = @()
        StabilityVerified = [bool]$StabilityVerified
        Method = 'Median and observed min/max per condition. Non-overlapping observed ranges indicate repeatability in supplied runs; this is not a confidence interval or universal gain guarantee. No fixed percentage threshold.'
        Metrics = @()
        InputLatencyStatus = 'NOT_MEASURED'
        NetworkLatencyStatus = 'NOT_MEASURED'
    }
    if ($BaselineRuns.Count -eq 0 -or $AfterRuns.Count -eq 0) {
        $result.Reason = 'Baseline and after captures are both required.'
        return [pscustomobject]$result
    }
    $allRuns = @($BaselineRuns) + @($AfterRuns)
    $issues = New-Object 'System.Collections.Generic.List[string]'
    foreach ($field in @('Game','GameBuild','Scene','Resolution','Preset','Api','Driver','OsBuild','FrameCap','VSync','CaptureTool','CaptureVersion')) {
        $reference = [string](Get-GoatRunProperty -Object (Get-GoatRunProperty $allRuns[0] 'Conditions') -Name $field)
        if ([string]::IsNullOrWhiteSpace($reference) -or $reference -match '^(unknown|unavailable|not measured|not verified|N/?D|N/?A|desconhecido|indisponivel)$') { $issues.Add("Missing or unverified condition: $field"); continue }
        foreach ($run in $allRuns) {
            $value = [string](Get-GoatRunProperty -Object (Get-GoatRunProperty $run 'Conditions') -Name $field)
            if ([string]::IsNullOrWhiteSpace($value) -or $value -cne $reference) { $issues.Add("Different or missing condition: $field"); break }
        }
    }
    foreach ($field in @('WarmupSeconds','ExpectedDurationSeconds','FrameGeneration','Upscaler','RenderScale','MonitorRefreshHz','DisplayMode','OverlayState','PowerState','BackgroundState','CaptureProtocol')) {
        $values=@($allRuns | ForEach-Object { [string](Get-GoatRunProperty -Object (Get-GoatRunProperty $_ 'Conditions') -Name $field) })
        if (@($values | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }).Count -gt 0) {
            $reference=$values[0]
            if ([string]::IsNullOrWhiteSpace($reference) -or @($values | Where-Object { $_ -cne $reference }).Count -gt 0) { $issues.Add("Different or partially documented condition: $field") }
        }
    }
    # Prevent comparing a displayed-frame stream to a presented/CPU frame stream.
    $referenceColumn = [string](Get-GoatRunProperty -Object (Get-GoatRunProperty $allRuns[0] 'Source') -Name 'Column')
    if ([string]::IsNullOrWhiteSpace($referenceColumn)) { $issues.Add('Missing capture interval column provenance.') }
    foreach ($run in $allRuns) {
        $column = [string](Get-GoatRunProperty -Object (Get-GoatRunProperty $run 'Source') -Name 'Column')
        if ($column -cne $referenceColumn) { $issues.Add('Different capture interval column semantics.'); break }
    }
    foreach ($field in @('OnePercentLowMethod','PercentileMethod','FpsMethod')) {
        $referenceMethod = [string](Get-GoatRunProperty -Object (Get-GoatRunProperty $allRuns[0] 'Metrics') -Name $field)
        if ([string]::IsNullOrWhiteSpace($referenceMethod)) { $issues.Add("Missing calculation method: $field"); continue }
        foreach ($run in $allRuns) {
            $method = [string](Get-GoatRunProperty -Object (Get-GoatRunProperty $run 'Metrics') -Name $field)
            if ($method -cne $referenceMethod) { $issues.Add("Different calculation method: $field"); break }
        }
    }
    foreach ($group in @(@{Label='Baseline'; Runs=$BaselineRuns}, @{Label='After'; Runs=$AfterRuns})) {
        $passIds = @($group.Runs | ForEach-Object { Get-GoatRunProperty $_ 'PassNumber' })
        if (@($passIds | Select-Object -Unique).Count -ne $passIds.Count) { $issues.Add("Duplicate pass numbers: $($group.Label)") }
    }
    $hashes = @($allRuns | ForEach-Object { [string](Get-GoatRunProperty -Object (Get-GoatRunProperty $_ 'Source') -Name 'Sha256') } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($hashes.Count -ne $allRuns.Count -or @($hashes | Where-Object { $_ -notmatch '^[a-fA-F0-9]{64}$' }).Count -gt 0) { $issues.Add('Every pass requires a valid SHA-256 provenance hash.') }
    if (@($hashes | Select-Object -Unique).Count -ne $hashes.Count) { $issues.Add('The same raw capture was reused as more than one pass.') }
    $result.ConditionsIssues = $issues.ToArray()
    $result.ConditionsMatch = $issues.Count -eq 0
    if ($issues.Count -gt 0) {
        $result.Reason = 'Conditions are missing, incompatible or not independent; no performance gain is calculated.'
        return [pscustomobject]$result
    }
    $comparisons = New-Object 'System.Collections.Generic.List[object]'
    foreach ($metric in @('AverageFps','OnePercentLowFps','FrameTimeP50Ms','FrameTimeP95Ms','FrameTimeP99Ms')) {
        $before = New-Object 'System.Collections.Generic.List[double]'
        $after = New-Object 'System.Collections.Generic.List[double]'
        foreach ($pair in @(@{Runs=$BaselineRuns; Values=$before}, @{Runs=$AfterRuns; Values=$after})) {
            foreach ($run in $pair.Runs) {
                $value = Get-GoatRunProperty -Object (Get-GoatRunProperty $run 'Metrics') -Name $metric
                if ($null -eq $value) { $result.Reason = "Missing metric: $metric"; return [pscustomobject]$result }
                try { $number = [double]$value } catch { $result.Reason = "Invalid metric: $metric"; return [pscustomobject]$result }
                if ([double]::IsNaN($number) -or [double]::IsInfinity($number) -or $number -le 0) {
                    $result.Reason = "Invalid metric: $metric"
                    return [pscustomobject]$result
                }
                $pair.Values.Add($number)
            }
        }
        $beforeSummary = Get-GoatRunSummary $before.ToArray()
        $afterSummary = Get-GoatRunSummary $after.ToArray()
        $higherIsBetter = $metric -in @('AverageFps','OnePercentLowFps')
        $direction = 'OVERLAPPING_OR_UNCHANGED'
        if ($higherIsBetter) {
            if ($afterSummary.Minimum -gt $beforeSummary.Maximum) { $direction = 'IMPROVEMENT_OBSERVED' }
            elseif ($afterSummary.Maximum -lt $beforeSummary.Minimum) { $direction = 'REGRESSION_OBSERVED' }
        } else {
            if ($afterSummary.Maximum -lt $beforeSummary.Minimum) { $direction = 'IMPROVEMENT_OBSERVED' }
            elseif ($afterSummary.Minimum -gt $beforeSummary.Maximum) { $direction = 'REGRESSION_OBSERVED' }
        }
        $comparisons.Add([pscustomobject]@{
            Name = $metric
            Units = $(if ($higherIsBetter) { 'FPS' } else { 'ms' })
            HigherIsBetter = $higherIsBetter
            Before = $beforeSummary
            After = $afterSummary
            AbsoluteDelta = $afterSummary.Median - $beforeSummary.Median
            RelativeDeltaPercent = $(if ($BaselineRuns.Count -ge 3 -and $AfterRuns.Count -ge 3) { 100.0 * ($afterSummary.Median - $beforeSummary.Median) / $beforeSummary.Median } else { $null })
            ObservedDirection = $direction
        })
    }
    $result.Metrics = $comparisons.ToArray()
    if ($BaselineRuns.Count -lt 3 -or $AfterRuns.Count -lt 3) {
        $result.Reason = 'Fewer than three independent passes per condition; collect 3-5 passes and increase if variability remains high.'
        return [pscustomobject]$result
    }
    $regressions = @($result.Metrics | Where-Object ObservedDirection -eq 'REGRESSION_OBSERVED')
    $primary = @($result.Metrics | Where-Object Name -eq $PrimaryMetric)[0]
    if ($regressions.Count -gt 0) {
        $result.Status = 'REGRESSION_DETECTED'
        $result.Reason = 'At least one measured metric regressed across the observed pass ranges; review trade-offs before keeping changes.'
    } elseif ($primary.ObservedDirection -eq 'IMPROVEMENT_OBSERVED' -and $StabilityVerified) {
        $result.Status = 'BENEFIT_CONFIRMED'
        $result.Reason = 'Primary metric improved across independent comparable runs, with separated observed ranges and stability explicitly verified. Conclusion applies to this capture protocol only.'
    } elseif ($primary.ObservedDirection -eq 'IMPROVEMENT_OBSERVED') {
        $result.Reason = 'Primary metric improved in the supplied runs, but stability, temperature and required features have not been verified.'
    } else {
        $result.Reason = 'Observed pass ranges overlap or show no improvement. Collect more comparable passes; no confirmed gain.'
    }
    return [pscustomobject]$result
}
