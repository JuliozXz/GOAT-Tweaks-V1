#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipUI,
    [string]$ResultsRoot,
    [ValidateRange(15,600)][int]$TimeoutSeconds = 180,
    [string]$PowerShellPath
)
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
if (-not $ResultsRoot) { $ResultsRoot = Join-Path $projectRoot 'artifacts/test-results' }
$ResultsRoot = [IO.Path]::GetFullPath($ResultsRoot)
[void][IO.Directory]::CreateDirectory($ResultsRoot)
if (-not $PowerShellPath) { $PowerShellPath = (Get-Command powershell.exe -ErrorAction Stop).Source }
$tests = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot 'tests') -File -Filter 'Test-*.ps1' | Sort-Object Name)
if ($tests.Count -eq 0) { throw 'No Test-*.ps1 suites were found.' }
$results = New-Object 'System.Collections.Generic.List[object]'
foreach ($test in $tests) {
    if ($SkipUI -and $test.BaseName -eq 'Test-UI') {
        $results.Add([pscustomobject]@{Name=$test.Name;Status='SKIPPED';Reason='Explicit -SkipUI';ExitCode=$null;DurationSeconds=0;StdOut=$null;StdErr=$null})
        continue
    }
    Write-Host ('Running ' + $test.Name + ' in isolated Windows PowerShell STA...')
    $stdout = Join-Path $ResultsRoot ($test.BaseName + '.stdout.log')
    $stderr = Join-Path $ResultsRoot ($test.BaseName + '.stderr.log')
    $started = [DateTime]::UtcNow
    $status='FAILED';$reason='';$exitCode=$null
    $process=$null
    try {
        # Each suite receives its own process: fixture provider overrides cannot leak.
        # File names come from the local tests directory; Windows paths cannot contain quotes.
        $arguments = '-NoProfile -NonInteractive -STA -File "' + $test.FullName + '"'
        $process = Start-Process -FilePath $PowerShellPath -ArgumentList $arguments -WorkingDirectory $projectRoot -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
        $ownedProcessHandle=$process.Handle # Keep the native handle so PS5.1 retains the exit code.
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            # Only the process created above is terminated; never select by name.
            $process.Kill()
            $process.WaitForExit()
            $reason='Suite exceeded its explicit timeout.'
        } else {
            $process.WaitForExit() # Flush redirected streams before recording the result.
            $process.Refresh()
            $exitCode=$process.ExitCode
            if ($exitCode -eq 0) { $status='PASSED' } else { $reason='Suite returned a nonzero exit code.' }
        }
    } catch { $reason=$_.Exception.Message }
    finally { if ($process) { $process.Dispose() } }
    $results.Add([pscustomobject]@{Name=$test.Name;Status=$status;Reason=$reason;ExitCode=$exitCode;DurationSeconds=[Math]::Round(([DateTime]::UtcNow-$started).TotalSeconds,3);StdOut=$stdout;StdErr=$stderr})
    Write-Host ($status + ': ' + $test.Name)
    if ($status -ne 'PASSED') {
        foreach ($log in @($stdout,$stderr)) {
            if (Test-Path -LiteralPath $log -PathType Leaf) { Get-Content -LiteralPath $log -Tail 35 | Write-Host }
        }
    }
}
$failed=@($results | Where-Object Status -eq 'FAILED').Count
$report=[pscustomobject][ordered]@{
    GeneratedUtc=[DateTime]::UtcNow.ToString('o')
    Engine=$PowerShellPath
    Passed=@($results | Where-Object Status -eq 'PASSED').Count
    Failed=$failed
    Skipped=@($results | Where-Object Status -eq 'SKIPPED').Count
    Suites=$results.ToArray()
    Note='Automated fixtures and UI smoke tests do not replace the documented Windows 10/11 and physical GPU validation matrix.'
}
$reportPath=Join-Path $ResultsRoot 'results.json'
[IO.File]::WriteAllText($reportPath, ($report|ConvertTo-Json -Depth 8), (New-Object Text.UTF8Encoding($false)))
Write-Host ('Results: ' + $reportPath)
if ($failed -gt 0) { throw "$failed test suite(s) failed. Logs and results were preserved." }
Write-Output $report
