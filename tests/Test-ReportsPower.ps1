#Requires -Version 5.1
# Independent export/recovery integration. Every native boundary is a file fixture.
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
$script:GoatCoreSource=Get-Content -LiteralPath (Join-Path $project 'src\Core.ps1') -Raw -Encoding UTF8
$script:GoatPowerSource=Get-Content -LiteralPath (Join-Path $project 'src\Power.ps1') -Raw -Encoding UTF8
. ([scriptblock]::Create($script:GoatCoreSource))
. ([scriptblock]::Create($script:GoatPowerSource))
. (Join-Path $project 'src\Reports.ps1')
$script:GoatVersion=(Get-Content -LiteralPath (Join-Path $project 'VERSION') -Raw).Trim()
$script:ReportPowerChecks=New-Object 'System.Collections.Generic.List[string]'
function Assert-ReportPower {param([bool]$Condition,[string]$Name)if(-not $Condition){throw ('Report/power assertion failed: '+$Name)};$script:ReportPowerChecks.Add($Name)}
function Assert-ReportPowerThrows {param([scriptblock]$Code,[string]$Name)$failed=$false;try{&$Code|Out-Null}catch{$failed=$true};Assert-ReportPower $failed $Name}
function Get-GoatIdentity {[pscustomobject]@{Machine='REPORT-POWER-PRIVATE-MACHINE';Sid='REPORT-POWER-PRIVATE-SID'}}
function Invoke-GoatPowerCfg {throw 'Native powercfg must never run in report integration fixtures.'}
function New-ReportPowerTransaction {
    param($Owner,[int]$Sequence,[string]$Original,[string]$Proposed,[string]$State='Applied',$Identity=(Get-GoatIdentity))
    $record=[pscustomobject]@{Type='POWER_SCHEME';SchemaVersion=1;Id=[guid]::NewGuid().ToString('N');SessionId=$Owner.Id;Identity=$Identity;CreatedUtc=([datetime]'2026-01-01T00:00:00Z').AddMinutes($Sequence).ToUniversalTime().ToString('o');Sequence=$Sequence;OriginalSchemeGuid=$Original;ProposedSchemeGuid=$Proposed;SnapshotSha256=$null;State=$State;ReadBackVerified=$true;LastExitCode=0;Error=$null;Message='Fixture native readback verified'}
    $record.SnapshotSha256=Get-GoatPowerSnapshotHash $record
    Write-GoatPowerJournal $record (Join-Path $Owner.Root ('power-transactions\'+$record.Id+'.json'))
    $record
}
function Invoke-ReportPowerRecovery {
    param([string]$Script,[string]$Transaction,[string]$SessionId,[switch]$Restore)
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName='powershell.exe';$start.Arguments='-NoProfile -File "'+$Script+'" -Kind Power'
    if($Restore){$start.Arguments+=' -Restore -TransactionId '+$Transaction}
    if($SessionId){$start.Arguments+=' -SessionId '+$SessionId}
    $start.UseShellExecute=$false;$start.CreateNoWindow=$true;$start.RedirectStandardOutput=$true;$start.RedirectStandardError=$true
    # A PS7 parent otherwise passes its incompatible module directories to the
    # PS5.1 child. Recovery is tested against Windows PowerShell built-ins only.
    $start.EnvironmentVariables['PSModulePath']=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\Modules'
    $process=New-Object Diagnostics.Process;$process.StartInfo=$start
    try{
        [void]$process.Start();$output=$process.StandardOutput.ReadToEndAsync();$errorText=$process.StandardError.ReadToEndAsync()
        if(-not $process.WaitForExit(30000)){$process.Kill();$process.WaitForExit();throw 'Owned recovery fixture timed out.'}
        $process.WaitForExit()
        [pscustomobject]@{ExitCode=$process.ExitCode;Output=$output.Result;Error=$errorText.Result}
    }finally{$process.Dispose()}
}
function New-ReportPowerRecoveryHarness {
    param([string]$PrivateRoot,[string]$StatePath,[switch]$ForeignIdentity)
    $injection=@'
function Get-GoatIdentity {[pscustomobject]@{Machine='REPORT-POWER-PRIVATE-MACHINE';Sid='__SID__'}}
function Read-Host {param([string]$Prompt);'RESTAURAR'}
function Get-GoatPowerContext {param($Session);[pscustomobject]@{IsAdministrator=$true;RemoteOrUnknown=$false;IsNotebook=$false;Reasons=@()}}
function Get-GoatPowerPlans {
    param([switch]$Demo)
    if($Demo){throw 'Real recovery fixture must not pretend to be Demo.'}
    $state=Get-Content -LiteralPath '__STATE__' -Raw -Encoding UTF8|ConvertFrom-Json
    [pscustomobject]@{SchemaVersion=1;Status='READ_ONLY';Demo=$false;ReadOnly=$true;ActiveSchemeGuid=$state.Active;Plans=@($state.Plans|ForEach-Object {[pscustomobject]@{Guid=$_;Name='Existing fixture';IsActive=($_ -eq $state.Active)}});Errors=@()}
}
function Invoke-GoatPowerCfg {
    param([string]$Option,[string]$SchemeGuid)
    $state=Get-Content -LiteralPath '__STATE__' -Raw -Encoding UTF8|ConvertFrom-Json
    if($Option -eq '/query'){
        if($state.Plans -notcontains $SchemeGuid){return [pscustomobject]@{ExitCode=5;TimedOut=$false;StdOut='';StdErr='Fixture removed plan'}}
    }elseif($Option -eq '/setactive'){
        if($state.Plans -notcontains $SchemeGuid){throw 'Fixture refuses creation of a power plan.'}
        $inflight=@(Get-GoatPowerTransactions -Session $session -IncludeRelated -Identity (Get-GoatIdentity)|Where-Object State -eq 'Restoring')
        if($inflight.Count -ne 1 -or $inflight[0].OriginalSchemeGuid -ne $SchemeGuid){throw 'Fixture mutation without one exact durable restoration snapshot.'}
        $state.Active=$SchemeGuid;$state.Writes=@($state.Writes)+$SchemeGuid
        Write-GoatJson $state '__STATE__'
    }else{throw ('Unexpected native command in recovery fixture: '+$Option)}
    [pscustomobject]@{ExitCode=0;TimedOut=$false;StdOut='Fixture success';StdErr=''}
}
'@
    $sid=if($ForeignIdentity){'FOREIGN-SID'}else{'REPORT-POWER-PRIVATE-SID'}
    $injection=$injection.Replace('__STATE__',$StatePath.Replace("'","''")).Replace('__SID__',$sid)
    $original=[IO.File]::ReadAllText((Join-Path $PrivateRoot 'Restore-GOAT.ps1'),[Text.Encoding]::UTF8)
    $marker='$main=Get-Content'
    if(-not $original.Contains($marker)){throw 'Recovery fixture injection marker changed; review the harness.'}
    $harness=Join-Path $PrivateRoot ('Recovery-Power-Fixture-'+[guid]::NewGuid().ToString('N')+'.ps1')
    [IO.File]::WriteAllText($harness,$original.Replace($marker,($injection+"`r`n"+$marker)),[Text.UTF8Encoding]::new($true))
    $harness
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('GOAT-ReportsPower-Test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try{
    $a='381b4222-f694-41f0-9685-ff5bb260df2e';$b='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';$c='a1841308-3541-4fab-bc81-f71556f20b4a'
    $sessions=Join-Path $root 'sessions';$exports=Join-Path $root 'exports'
    $older=New-GoatSession -Root $sessions;$newer=New-GoatSession -Root $sessions
    $old=New-ReportPowerTransaction $older 1 $a $b;$new=New-ReportPowerTransaction $newer 2 $b $c
    $oldOriginal=Join-Path $older.Root ('power-transactions\'+$old.Id+'.json');$newOriginal=Join-Path $newer.Root ('power-transactions\'+$new.Id+'.json')
    $oldHash=(Get-FileHash -LiteralPath $oldOriginal).Hash;$newHash=(Get-FileHash -LiteralPath $newOriginal).Hash
    $public=Get-GoatPublicReport $older;$json=$public|ConvertTo-Json -Depth 32
    Assert-ReportPower ($public.PowerTransactions.Count -eq 1 -and $public.PowerTransactions[0].Id -eq $old.Id -and $public.PowerTransactions[0].OriginalSchemeGuid -eq $a) 'public report shows exact power GUID delta and verified state'
    Assert-ReportPower ($json -notmatch 'REPORT-POWER-PRIVATE|SnapshotSha256|JournalPath|OwnerSessionRoot') 'public power projection omits Windows identity private paths and journal internals'
    $export=Export-GoatService $older $exports;$private=Join-Path $export 'private-recovery'
    Assert-ReportPower (Test-GoatExport $export) 'power recovery export verifies original manifest'
    $copiedOld=Join-Path $private ('power-transactions\'+$old.Id+'.json');$copiedNew=Join-Path $private ('related-sessions\'+$newer.Id+'\power-transactions\'+$new.Id+'.json')
    Assert-ReportPower ([IO.File]::Exists($copiedOld) -and [IO.File]::Exists($copiedNew)) 'pack includes current and newer related power journals'
    Assert-ReportPower ((Get-FileHash -LiteralPath $copiedOld).Hash -eq $oldHash -and (Get-FileHash -LiteralPath $copiedNew).Hash -eq $newHash) 'private exported power snapshots preserve exact original bytes'
    $csv=Import-Csv -LiteralPath (Join-Path $export 'transactions.csv')
    Assert-ReportPower (@($csv).Count -eq 1 -and $csv.Id -eq $old.Id) 'public transaction CSV includes the current power transaction'
    $restore=Join-Path $private 'Restore-GOAT.ps1';$restoreHash=(Get-FileHash -LiteralPath $restore).Hash
    $tokens=$null;$errors=$null;[Management.Automation.Language.Parser]::ParseFile($restore,[ref]$tokens,[ref]$errors)|Out-Null
    Assert-ReportPower (@($errors).Count -eq 0) 'standalone embedded Core and Power recovery parses'
    $statePath=Join-Path $root 'power-state.json';Write-GoatJson ([pscustomobject]@{Active=$c;Plans=@($a,$b,$c);Writes=@()}) $statePath
    $harness=New-ReportPowerRecoveryHarness $private $statePath
    $listed=Invoke-ReportPowerRecovery $harness
    Assert-ReportPower ($listed.ExitCode -eq 0 -and $listed.Output -match $old.Id -and $listed.Output -match $new.Id) ('standalone read-only list discovers both sessions: '+$listed.Error)
    Assert-ReportPower (-not [IO.Directory]::Exists((Join-Path $private 'runtime')) -and @((Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json).Writes).Count -eq 0) 'listing creates no mutable runtime and performs no native changes'
    $blocked=Invoke-ReportPowerRecovery $harness $old.Id -Restore
    Assert-ReportPower ($blocked.ExitCode -ne 0 -and $blocked.Error -match 'recente') 'standalone recovery refuses to restore older power journal first'
    $state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
    Assert-ReportPower ($state.Active -eq $c -and @($state.Writes).Count -eq 0) 'ordering rejection preserves current power plan'
    $runtimeNew=Join-Path $private ('runtime\'+$newer.Id+'\power-transactions\'+$new.Id+'.json');$runtimeOld=Join-Path $private ('runtime\'+$older.Id+'\power-transactions\'+$old.Id+'.json')
    Assert-ReportPower ([IO.File]::Exists($runtimeNew) -and [IO.File]::Exists($runtimeOld)) 'recovery stages all owners before any restoration'
    $marker=Get-Content -LiteralPath (Join-Path $private ('runtime\'+$newer.Id+'\recovery-ready.json')) -Raw|ConvertFrom-Json
    Assert-ReportPower ($marker.SessionId -eq $newer.Id -and @($marker.PowerTransactionIds) -contains $new.Id) 'durable runtime marker retains related power journal identity'
    $foreignHarness=New-ReportPowerRecoveryHarness $private $statePath -ForeignIdentity
    $foreign=Invoke-ReportPowerRecovery $foreignHarness $new.Id $newer.Id -Restore
    Assert-ReportPower ($foreign.ExitCode -ne 0 -and @((Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json).Writes).Count -eq 0) 'independent recovery refuses another Windows user before native change'
    $newResult=Invoke-ReportPowerRecovery $harness $new.Id $newer.Id -Restore
    Assert-ReportPower ($newResult.ExitCode -eq 0 -and (Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json).Active -eq $b) ('standalone recovery restores newer related plan first: '+$newResult.Error)
    $newRuntime=Get-Content -LiteralPath $runtimeNew -Raw|ConvertFrom-Json
    Assert-ReportPower ($newRuntime.State -eq 'Restored' -and $newRuntime.ReadBackVerified) 'newer working journal records verified GUID restoration'
    $oldResult=Invoke-ReportPowerRecovery $harness $old.Id -Restore
    $state=Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json
    Assert-ReportPower ($oldResult.ExitCode -eq 0 -and $state.Active -eq $a -and ($state.Writes -join ',') -eq ($b+','+$a)) ('standalone recovery returns exact oldest original GUID in reverse order: '+$oldResult.Error)
    Assert-ReportPower ((Get-Content -LiteralPath $runtimeOld -Raw|ConvertFrom-Json).State -eq 'Restored') 'oldest working journal records completion'
    Assert-ReportPower ((Get-FileHash -LiteralPath $copiedOld).Hash -eq $oldHash -and (Get-FileHash -LiteralPath $copiedNew).Hash -eq $newHash -and (Get-FileHash -LiteralPath $restore).Hash -eq $restoreHash -and (Test-GoatExport $export)) 'recovery leaves immutable exported snapshots script and manifest valid'
    Assert-ReportPower ((Get-FileHash -LiteralPath $oldOriginal).Hash -eq $oldHash -and (Get-FileHash -LiteralPath $newOriginal).Hash -eq $newHash) 'independent restoration never edits original application session journals'
    $again=Invoke-ReportPowerRecovery $harness $old.Id -Restore
    Assert-ReportPower ($again.ExitCode -eq 0 -and @((Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json).Writes).Count -eq 2) 'repeated verified restoration is idempotent'
    [IO.File]::Delete($runtimeNew)
    $missing=Invoke-ReportPowerRecovery $harness $old.Id -Restore
    Assert-ReportPower ($missing.ExitCode -ne 0 -and $missing.Error -match 'ausente' -and @((Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json).Writes).Count -eq 2) 'missing related runtime power journal blocks recovery instead of bypassing order'
    Assert-ReportPower (Test-GoatExport $export) 'missing mutable journal does not alter original manifest snapshots'
    [IO.File]::AppendAllText($copiedOld,'CORRUPTED-FIXTURE')
    $corrupt=Invoke-ReportPowerRecovery $harness $old.Id -Restore
    Assert-ReportPower ($corrupt.ExitCode -ne 0 -and @((Get-Content -LiteralPath $statePath -Raw|ConvertFrom-Json).Writes).Count -eq 2) 'corrupt immutable recovery journal fails manifest verification before mutation'

    $pendingRoot=Join-Path $root 'pending-sessions';$pendingOwner=New-GoatSession -Root $pendingRoot
    $pending=New-ReportPowerTransaction $pendingOwner 1 $a $b 'Prepared'
    foreach($pendingState in @('Prepared','Applying','Restoring','RestoreFailed','Conflict')){
        $pending.State=$pendingState;Write-GoatPowerJournal $pending (Join-Path $pendingOwner.Root ('power-transactions\'+$pending.Id+'.json'))
        Assert-ReportPowerThrows {Complete-GoatSession $pendingOwner $exports -Consent} ('finalization blocks unresolved power state '+$pendingState)
        Assert-ReportPower ($pendingOwner.State -eq 'Open' -and $null -eq $pendingOwner.FinalExport) ('blocked finalization preserves open session for '+$pendingState)
    }
    $sibling=New-GoatSession -Root $pendingRoot
    Assert-ReportPowerThrows {Complete-GoatSession $sibling $exports -Consent} 'related pending power transaction blocks sibling finalization'
    $savedPowerSource=$script:GoatPowerSource;$script:GoatPowerSource=$null
    try{Assert-ReportPowerThrows {Export-GoatService $older $exports} 'missing Power source refuses nonrestorable power export'}finally{$script:GoatPowerSource=$savedPowerSource}
    Assert-ReportPower ((Get-FileHash -LiteralPath $oldOriginal).Hash -eq $oldHash) 'missing recovery source preserves original power snapshot'

    # A registry-owning session can include Power only through a related owner.
    # Its independent recovery must still embed the Power engine.
    $mixedRoot=Join-Path $root 'mixed-sessions';$registryOwner=New-GoatSession -Root $mixedRoot;$powerOwner=New-GoatSession -Root $mixedRoot
    $relatedPower=New-ReportPowerTransaction $powerOwner 1 $a $b
    $action=@(Get-GoatActions)[0]
    $step=[pscustomobject]@{Id=$action.Id;Target=$action;Original=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='DWord';Data=1};Proposed=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='DWord';Data=0};State='Applied';Error=$null;SnapshotSha256=$null};$step.SnapshotSha256=Get-GoatSnapshotHash $step
    $registryTx=[pscustomobject]@{SchemaVersion=1;Id=[guid]::NewGuid().ToString('N');Identity=(Get-GoatIdentity);CreatedUtc='2026-01-01T00:00:00.0000000Z';State='Applied';Steps=@($step)}
    Write-GoatJson $registryTx (Join-Path $registryOwner.Root ('transactions\'+$registryTx.Id+'.json'))
    $mixed=Export-GoatService $registryOwner $exports
    Assert-ReportPower ([IO.File]::Exists((Join-Path $mixed ('private-recovery\related-sessions\'+$powerOwner.Id+'\power-transactions\'+$relatedPower.Id+'.json'))) -and (Test-GoatExport $mixed)) 'mixed registry export retains related Power snapshots'
    $script:GoatPowerSource=$null
    try{Assert-ReportPowerThrows {Export-GoatService $registryOwner $exports} 'related-only Power recovery also requires embedded Power source'}finally{$script:GoatPowerSource=$savedPowerSource}
}finally{
    $full=[IO.Path]::GetFullPath($root);$temporary=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    if(-not $full.StartsWith($temporary,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -notlike 'GOAT-ReportsPower-Test-*'){throw 'Unsafe fixture cleanup'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
[pscustomobject]@{Module='ReportsPower';Passed=$script:ReportPowerChecks.Count;Checks=@($script:ReportPowerChecks.ToArray());Mutation='Owned temporary files and injected file-backed providers only; no Windows power settings changed'}|ConvertTo-Json -Depth 4
