#Requires -Version 5.1
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$script:GoatCoreSource=Get-Content -LiteralPath (Join-Path $project 'src\Core.ps1') -Raw -Encoding UTF8
. ([scriptblock]::Create($script:GoatCoreSource))
. (Join-Path $project 'src\Reports.ps1')
$script:ReportChecks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Report {param([bool]$Condition,[string]$Name)if(-not $Condition){throw "Report assertion failed: $Name"};$script:ReportChecks.Add($Name)}
function Assert-ReportThrows {param([scriptblock]$Code,[string]$Name)$failed=$false;try{&$Code|Out-Null}catch{$failed=$true};Assert-Report $failed $Name}
function Invoke-ReportRecoveryFixture {
    param([string]$Script,[string]$Transaction,[string]$SessionId)
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName='powershell.exe';$start.Arguments='-NoProfile -File "'+$Script+'" -Restore -TransactionId '+$Transaction
    if($SessionId){$start.Arguments+=' -SessionId '+$SessionId}
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start
    try{[void]$process.Start();$output=$process.StandardOutput.ReadToEnd();$errorText=$process.StandardError.ReadToEnd();if(-not $process.WaitForExit(30000)){$process.Kill();throw 'Owned recovery fixture timed out.'};[pscustomobject]@{ExitCode=$process.ExitCode;Output=$output;Error=$errorText}}finally{$process.Dispose()}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('GOAT-Reports-Test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
    $session=New-GoatSession -Demo -Root (Join-Path $root 'sessions')
    $session.Inventory=[pscustomobject]@{OS=[pscustomobject]@{Caption='Windows fixture';HostName='PRIVATE-HOST';SerialNumber='PRIVATE-SERIAL'};CPU='<script>alert("x")</script>';Memory='16 GiB';HostName='PRIVATE-HOST';GpuCenter=[pscustomobject]@{Devices=@([pscustomobject]@{Name='NVIDIA fixture';Vendor='NVIDIA';DriverVersion='1';DriverDate='2025-01-01';PnpDeviceId='PRIVATE-PNP'})}}
    $session.Events=@([pscustomobject]@{Kind='Manual';Utc='2026-01-01';Message='Client C:\Users\PRIVATE-NAME\secret';Token='PRIVATE-TOKEN'})
    $captureId=[guid]::NewGuid().ToString('N');$snapshotName=[guid]::NewGuid().ToString('N')+'.csv'
    [void][IO.Directory]::CreateDirectory((Join-Path $session.Root 'captures'))
    $snapshot=Join-Path $session.Root ('captures\'+$snapshotName);[IO.File]::WriteAllText($snapshot,"FrameTimeMs`r`n16.5`r`n")
    $sourceHash=(Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash.ToLowerInvariant()
    $session.Benchmarks=@([pscustomobject]@{CaptureId=$captureId;ConditionLabel='A';PassNumber=1;Conditions=[pscustomobject]@{Game='Fixture';ExecutablePath='C:\Users\PRIVATE-NAME\game.exe';UserSecret='PRIVATE-SECRET'};Metrics=[pscustomobject]@{AverageFps=60};Source=[pscustomobject]@{Sha256=$sourceHash;Column='FrameTimeMs';Units='ms';Semantics='Fixture intervals';RowsImported=1;SnapshotFileName=$snapshotName};SourcePath='C:\private\capture.csv'})
    $session.Comparison=[pscustomobject]@{Status='INCONCLUSIVE';Note='C:\Users\PRIVATE-NAME\capture.csv';Sid='PRIVATE-SID'}
    Save-GoatSession $session
    $report=Get-GoatPublicReport $session
    $json=$report|ConvertTo-Json -Depth 32
    Assert-Report ($json -notmatch 'PRIVATE-(HOST|SERIAL|PNP|NAME|TOKEN|SECRET|SID)' -and $json -notmatch 'C:\\Users') 'public projection redacts identity paths and secret fields'
    Assert-Report ($report.Hardware.GPUs[0].Vendor -eq 'NVIDIA' -and $report.Benchmarks[0].Metrics.AverageFps -eq 60) 'public report preserves useful hardware and evidence'
    Assert-Report ($report.Version -eq '7.3.0' -and $report.Benchmarks[0].SourceSha256 -eq $sourceHash -and $report.Benchmarks[0].IntervalUnits -eq 'ms') 'official report version and actual capture provenance retained'
    $exports=Join-Path $root 'exports'
    $export=Export-GoatService $session $exports
    Assert-Report (Test-GoatExport $export) 'export verifies hashes for report and private recovery'
    Assert-Report ([IO.File]::Exists((Join-Path $export ('private-recovery\captures\'+$snapshotName))) -and -not [IO.File]::Exists((Join-Path $export ('private-recovery\captures\'+$captureId+'.csv')))) 'capture snapshot filename independent of capture ID preserved'
    Assert-ReportThrows {Test-GoatExport -Directory $export -ExpectedSessionId ('a'*32)} 'export cannot impersonate another session'
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
    $session.State='Finalizing';Save-GoatSession $session
    $loaded=Import-GoatSession -Path (Join-Path $session.Root 'session.json') -Demo
    Assert-Report ($loaded.State -eq 'Finalized' -and $loaded.FinalExport -eq $final) 'loader reconciles crash after valid final export without duplicating it'
    $session.State='Finalizing';Save-GoatSession $session
    $resumed=Complete-GoatSession $session
    Assert-Report ($resumed -eq $final -and $session.State -eq 'Finalized') 'complete resumes durable finalization intent without asking for new operation'

    # Construct journals with the real schema/hash; recovery runs only injected
    # file-backed registry mocks in a separate PS5.1 process, never Windows APIs.
    $recoverySessions=Join-Path $root 'recovery-sessions'
    $older=New-GoatSession -Root $recoverySessions;$newer=New-GoatSession -Root $recoverySessions
    $action=@(Get-GoatActions)[0]
    $identity=[pscustomobject]@{Machine='MACHINE-RECOVERY-FIXTURE';Sid='SID-RECOVERY-FIXTURE'}
    $oldStep=[pscustomobject]@{Id=$action.Id;Target=$action;Original=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='String';Data='ORIGINAL'};Proposed=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='DWord';Data=0};State='Applied';Error=$null;SnapshotSha256=$null}
    $oldStep.SnapshotSha256=Get-GoatSnapshotHash $oldStep
    $newStep=[pscustomobject]@{Id=$action.Id;Target=$action;Original=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='DWord';Data=0};Proposed=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='DWord';Data=1};State='Applied';Error=$null;SnapshotSha256=$null}
    $newStep.SnapshotSha256=Get-GoatSnapshotHash $newStep
    $oldTx=[pscustomobject]@{SchemaVersion=1;Id=[guid]::NewGuid().ToString('N');Identity=$identity;CreatedUtc='2026-01-01T00:00:00.0000000Z';State='Applied';Steps=@($oldStep)}
    $newTx=[pscustomobject]@{SchemaVersion=1;Id=[guid]::NewGuid().ToString('N');Identity=$identity;CreatedUtc='2026-01-02T00:00:00.0000000Z';State='Applied';Steps=@($newStep)}
    Write-GoatJson $oldTx (Join-Path $older.Root ('transactions\'+$oldTx.Id+'.json'));Write-GoatJson $newTx (Join-Path $newer.Root ('transactions\'+$newTx.Id+'.json'))
    $recoveryExport=Export-GoatService $older $exports
    $privateRoot=Join-Path $recoveryExport 'private-recovery'
    Assert-Report ([IO.File]::Exists((Join-Path $privateRoot ('related-sessions\'+$newer.Id+'\transactions\'+$newTx.Id+'.json')))) 'independent recovery pack includes newer related-session journal'
    $registryFixture=Join-Path $root 'registry-fixture.json';Write-GoatJson $newStep.Proposed $registryFixture
    $injection=@'
function Get-GoatIdentity {[pscustomobject]@{Machine='MACHINE-RECOVERY-FIXTURE';Sid='SID-RECOVERY-FIXTURE'}}
function Read-Host {param([string]$Prompt);'RESTAURAR'}
function Read-GoatRegistry {param($Target);Get-Content -LiteralPath '__FIXTURE__' -Raw -Encoding UTF8|ConvertFrom-Json}
function Write-GoatRegistry {param($Target,$State);Write-GoatJson $State '__FIXTURE__'}
'@
    $injection=$injection.Replace('__FIXTURE__',$registryFixture.Replace("'","''"))
    $originalRestore=[IO.File]::ReadAllText((Join-Path $privateRoot 'Restore-GOAT.ps1'),[Text.Encoding]::UTF8)
    $harness=Join-Path $privateRoot 'Recovery-Fixture.ps1'
    $harnessText=$originalRestore.Replace('$main=Get-Content',($injection+"`r`n"+'$main=Get-Content'))
    [IO.File]::WriteAllText($harness,$harnessText,[Text.UTF8Encoding]::new($true))
    # The original application sessions remain outside the pack's scanned roots;
    # ordering is enforced using the independent exported copies.
    $blocked=Invoke-ReportRecoveryFixture $harness $oldTx.Id
    Assert-Report ($blocked.ExitCode -ne 0 -and (Get-Content -LiteralPath $registryFixture -Raw|ConvertFrom-Json).Data -eq 1) 'standalone recovery refuses older transaction without touching registry fixture'
    $restoredNew=Invoke-ReportRecoveryFixture $harness $newTx.Id $newer.Id
    Assert-Report ($restoredNew.ExitCode -eq 0 -and (Get-Content -LiteralPath $registryFixture -Raw|ConvertFrom-Json).Data -eq 0) ('standalone recovery restores newer related session first: '+$restoredNew.Error)
    $restoredOld=Invoke-ReportRecoveryFixture $harness $oldTx.Id
    $originalState=Get-Content -LiteralPath $registryFixture -Raw|ConvertFrom-Json
    Assert-Report ($restoredOld.ExitCode -eq 0 -and $originalState.Kind -eq 'String' -and $originalState.Data -eq 'ORIGINAL') ('standalone recovery returns exact original type/data: '+$restoredOld.Error)
    Assert-Report (Test-GoatExport $recoveryExport) 'working recovery journals never modify immutable exported snapshots'
    $originalOld=Get-Content -LiteralPath (Join-Path $older.Root ('transactions\'+$oldTx.Id+'.json')) -Raw|ConvertFrom-Json
    Assert-Report ($originalOld.State -eq 'Applied') 'independent pack restoration leaves application journals unchanged'
    $runtimeNew=Join-Path $privateRoot ('runtime\'+$newer.Id+'\transactions\'+$newTx.Id+'.json')
    [IO.File]::Delete($runtimeNew)
    $incomplete=Invoke-ReportRecoveryFixture $harness $oldTx.Id
    Assert-Report ($incomplete.ExitCode -ne 0 -and (Get-Content -LiteralPath $registryFixture -Raw|ConvertFrom-Json).Data -eq 'ORIGINAL') 'missing working journal blocks recovery instead of bypassing order'
    function Copy-Item {
        [CmdletBinding()]
        param([string]$LiteralPath,[string]$Destination,[switch]$Recurse)
        Microsoft.PowerShell.Management\Copy-Item @PSBoundParameters
        if($LiteralPath -like '*.csv' -and $Destination -like '*private-recovery*'){[IO.File]::AppendAllText($Destination,'CORRUPTED-COPY-FIXTURE')}
    }
    try{Assert-ReportThrows {Export-GoatService $session $exports} 'capture copy readback rejects data diverging from measured-source hash'}finally{Remove-Item Function:\Copy-Item}
    Assert-Report ((Get-FileHash -LiteralPath $snapshot -Algorithm SHA256).Hash -eq $sourceHash) 'failed capture export preserves original source snapshot'

    [IO.File]::AppendAllText((Join-Path $final 'report.html'),'tampered')
    Assert-ReportThrows {Complete-GoatSession $session} 'idempotent finalize revalidates existing export'
} finally {
    $full=[IO.Path]::GetFullPath($root)
    if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -notlike 'GOAT-Reports-Test-*'){throw 'Unsafe fixture cleanup'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
[pscustomobject]@{Module='Reports';Passed=$script:ReportChecks.Count;Checks=@($script:ReportChecks.ToArray());Mutation='Owned temporary files only; no Windows settings changed'}|ConvertTo-Json -Depth 4
