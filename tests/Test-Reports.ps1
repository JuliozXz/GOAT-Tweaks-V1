#Requires -Version 5.1
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$script:GoatCoreSource=Get-Content -LiteralPath (Join-Path $project 'src\Core.ps1') -Raw -Encoding UTF8
. ([scriptblock]::Create($script:GoatCoreSource))
. (Join-Path $project 'src\Reports.ps1')
$script:ReportChecks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Report {param([bool]$Condition,[string]$Name)if(-not $Condition){throw "Report assertion failed: $Name"};$script:ReportChecks.Add($Name)}
function Assert-ReportThrows {param([scriptblock]$Code,[string]$Name)$failed=$false;try{&$Code|Out-Null}catch{$failed=$true};Assert-Report $failed $Name}
$root=Join-Path ([IO.Path]::GetTempPath()) ('GOAT-Reports-Test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
    $session=New-GoatSession -Demo -Root (Join-Path $root 'sessions')
    $session.Inventory=[pscustomobject]@{OS=[pscustomobject]@{Caption='Windows fixture';HostName='PRIVATE-HOST';SerialNumber='PRIVATE-SERIAL'};CPU='<script>alert("x")</script>';Memory='16 GiB';HostName='PRIVATE-HOST';GpuCenter=[pscustomobject]@{Devices=@([pscustomobject]@{Name='NVIDIA fixture';Vendor='NVIDIA';DriverVersion='1';DriverDate='2025-01-01';PnpDeviceId='PRIVATE-PNP'})}}
    $session.Events=@([pscustomobject]@{Kind='Manual';Utc='2026-01-01';Message='Client C:\Users\PRIVATE-NAME\secret';Token='PRIVATE-TOKEN'})
    $session.Benchmarks=@([pscustomobject]@{ConditionLabel='A';PassNumber=1;Conditions=[pscustomobject]@{Game='Fixture';ExecutablePath='C:\Users\PRIVATE-NAME\game.exe';UserSecret='PRIVATE-SECRET'};Metrics=[pscustomobject]@{AverageFps=60};SourceSha256='fixture-sha';SourcePath='C:\private\capture.csv'})
    $session.Comparison=[pscustomobject]@{Status='INCONCLUSIVE';Note='C:\Users\PRIVATE-NAME\capture.csv';Sid='PRIVATE-SID'}
    Save-GoatSession $session
    $report=Get-GoatPublicReport $session
    $json=$report|ConvertTo-Json -Depth 32
    Assert-Report ($json -notmatch 'PRIVATE-(HOST|SERIAL|PNP|NAME|TOKEN|SECRET|SID)' -and $json -notmatch 'C:\\Users') 'public projection redacts identity paths and secret fields'
    Assert-Report ($report.Hardware.GPUs[0].Vendor -eq 'NVIDIA' -and $report.Benchmarks[0].Metrics.AverageFps -eq 60) 'public report preserves useful hardware and evidence'
    $exports=Join-Path $root 'exports'
    $export=Export-GoatService $session $exports
    Assert-Report (Test-GoatExport $export) 'export verifies hashes for report and private recovery'
    Assert-Report ([IO.File]::Exists((Join-Path $export 'transactions.csv'))) 'empty transaction CSV has header'
    $html=Get-Content -LiteralPath (Join-Path $export 'report.html') -Raw -Encoding UTF8
    Assert-Report ($html -notmatch '<script>' -and ($html -match '&lt;script&gt;|\\u003cscript')) 'HTML escapes untrusted inventory text'
    Assert-Report ($html -notmatch 'PRIVATE-(HOST|SERIAL|PNP|NAME|TOKEN|SECRET|SID)') 'HTML contains no private fixture identifiers'
    $private=Get-Content -LiteralPath (Join-Path $export 'private-recovery\session.json') -Raw -Encoding UTF8
    Assert-Report ($private -match 'PRIVATE-NAME' -and [IO.File]::Exists((Join-Path $export 'private-recovery\Restore-GOAT.ps1'))) 'private recovery preserves originals in separate marked folder'
    $restore=Join-Path $export 'private-recovery\Restore-GOAT.ps1'
    $errors=$null;$tokens=$null;[Management.Automation.Language.Parser]::ParseFile($restore,[ref]$tokens,[ref]$errors)|Out-Null
    Assert-Report (@($errors).Count -eq 0) 'standalone recovery source parses in PS5.1'
    $manifestPath=Join-Path $export 'manifest.json';$originalManifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8
    $manifest=$originalManifest|ConvertFrom-Json
    $manifest.Files[0].Path='..\outside.json';Write-GoatJson $manifest $manifestPath
    Assert-ReportThrows {Test-GoatExport $export} 'manifest path traversal rejected'
    $manifest=$originalManifest|ConvertFrom-Json;$manifest.Files=@($manifest.Files[0],$manifest.Files[0],$manifest.Files[0]);Write-GoatJson $manifest $manifestPath
    Assert-ReportThrows {Test-GoatExport $export} 'duplicate or incomplete manifest rejected'
    [IO.File]::WriteAllText($manifestPath,$originalManifest,[Text.UTF8Encoding]::new($false))
    $reportPath=Join-Path $export 'report.json';$originalReport=[IO.File]::ReadAllText($reportPath);[IO.File]::AppendAllText($reportPath,'tampered')
    Assert-ReportThrows {Test-GoatExport $export} 'corrupt export detected'
    [IO.File]::WriteAllText($reportPath,$originalReport,[Text.UTF8Encoding]::new($false))
    Assert-Report (Test-GoatExport $export) 'restored export verifies again'
    Assert-ReportThrows {Complete-GoatSession $session $exports} 'finalization requires consent'
    $pending=[pscustomobject]@{SchemaVersion=1;Id='pending';State='Applying';CreatedUtc='2026-01-01';Identity=[pscustomobject]@{Machine='fixture';Sid='fixture'};Steps=@()}
    $journalPath=Join-Path $session.Root 'transactions\pending.json';Write-GoatJson $pending $journalPath
    $before=@(Get-ChildItem -LiteralPath $exports -Directory).Count
    Assert-ReportThrows {Complete-GoatSession $session $exports -Consent} 'unresolved transaction blocks finalization'
    Assert-Report ($session.State -eq 'Open' -and @(Get-ChildItem -LiteralPath $exports -Directory).Count -eq $before -and [IO.File]::Exists($journalPath)) 'blocked finalize preserves state journals and exports'
    [IO.File]::Delete($journalPath)
    $bad=Join-Path $root 'destination-file';[IO.File]::WriteAllText($bad,'keep')
    Assert-ReportThrows {Complete-GoatSession $session $bad -Consent} 'export failure surfaces and stops finalize'
    Assert-Report ($session.State -eq 'Open' -and [IO.File]::Exists((Join-Path $session.Root 'session.json')) -and [IO.File]::ReadAllText($bad) -eq 'keep') 'failed export preserves session and existing destination'
    $originalSource=$script:GoatCoreSource;$script:GoatCoreSource=$null
    Assert-ReportThrows {Complete-GoatSession $session $exports -Consent} 'missing recovery source blocks finalize'
    Assert-Report ($session.State -eq 'Open' -and [IO.File]::Exists((Join-Path $session.Root 'session.json'))) 'missing recovery never deletes original'
    $script:GoatCoreSource=$originalSource
    $final=Complete-GoatSession $session $exports -Consent
    $finalReport=Get-Content -LiteralPath (Join-Path $final 'report.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-Report ($session.State -eq 'Finalized' -and $finalReport.State -eq 'Finalized' -and (Test-GoatExport $final)) 'finalize records valid export and final report state'
    $before=@(Get-ChildItem -LiteralPath $exports -Directory).Count
    $again=Complete-GoatSession $session
    Assert-Report ($again -eq $final -and @(Get-ChildItem -LiteralPath $exports -Directory).Count -eq $before) 'finalization idempotent with no duplicate export'
    [IO.File]::AppendAllText((Join-Path $final 'report.html'),'tampered')
    Assert-ReportThrows {Complete-GoatSession $session} 'idempotent finalize revalidates existing export'
} finally {
    $full=[IO.Path]::GetFullPath($root)
    if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -notlike 'GOAT-Reports-Test-*'){throw 'Unsafe fixture cleanup'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
[pscustomobject]@{Module='Reports';Passed=$script:ReportChecks.Count;Checks=@($script:ReportChecks.ToArray());Mutation='Owned temporary files only; no Windows settings changed'}|ConvertTo-Json -Depth 4
