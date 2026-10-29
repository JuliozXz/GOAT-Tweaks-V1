#Requires -Version 5.1
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Core.ps1')
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src/Power.ps1')
$script:PowerChecks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Power {param([bool]$Condition,[string]$Name);if(-not $Condition){throw ('Power assertion: '+$Name)};$script:PowerChecks.Add($Name)}
function Assert-PowerThrows {param([scriptblock]$Code,[string]$Name);$threw=$false;try{&$Code|Out-Null}catch{$threw=$true};Assert-Power $threw $Name}
$script:PowerA='381b4222-f694-41f0-9685-ff5bb260df2e'
$script:PowerB='8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$script:PowerC='a1841308-3541-4fab-bc81-f71556f20b4a'
$script:PowerUnknown='11111111-2222-3333-4444-555555555555'
$script:PowerIdentity=[pscustomobject]@{Machine='POWER-MACHINE-FIXTURE';Sid='POWER-SID-FIXTURE'}
$script:SavedPowerNative=(Get-Command Invoke-GoatPowerCfg).ScriptBlock
$script:SavedPowerJson=(Get-Command Write-GoatJson).ScriptBlock
$script:SavedPowerPending=(Get-Command Get-GoatPendingTransactions).ScriptBlock
function Get-GoatIdentity {[pscustomobject]@{Machine=$script:PowerIdentity.Machine;Sid=$script:PowerIdentity.Sid}}
function Get-GoatPowerContext {param($Session);$script:PowerContextReads++;[pscustomobject]@{IsAdministrator=$script:PowerAdmin;RemoteOrUnknown=$script:PowerRemote;IsNotebook=$true;Reasons=@('Fixture: local/remote context')}}
function Write-GoatJson {
    param($Value,[string]$Path)
    if($script:PowerJournalDenied -and $Path -match 'power-transactions'){throw 'Fixture disk full before durable journal'}
    & $script:SavedPowerJson $Value $Path
}
function Get-GoatPendingTransactions {param($Session,$Identity);if($script:PowerNativePending){[pscustomobject]@{State='Applying'}}else{&$script:SavedPowerPending $Session $Identity}}
function New-PowerNativeResult {param([int]$Exit=0,[string]$Out='', [string]$ErrorText='', [bool]$TimedOut=$false);[pscustomobject]@{ExitCode=$Exit;StdOut=$Out;StdErr=$ErrorText;TimedOut=$TimedOut}}
function Invoke-GoatPowerCfg {
    param([string]$Option,[string]$SchemeGuid,[int]$TimeoutSeconds=10)
    $script:PowerCalls+=($Option+' '+$SchemeGuid)
    switch($Option){
        '/list' {
            if($script:PowerFault -eq 'list-fail'){return (New-PowerNativeResult 5 '' 'Fixture access denied')}
            $lines=@('Planos existentes (fixture):')
            foreach($key in @($script:PowerPlanMap.Keys|Sort-Object)){$lines+=('GUID do Esquema de Energia: '+$key+' ('+$script:PowerPlanMap[$key]+') '+$(if($key -eq $script:PowerActive){'*'}else{''}))}
            if($script:PowerFault -eq 'duplicate'){$lines+=$lines[1]}
            return (New-PowerNativeResult -Out ($lines -join "`r`n"))
        }
        '/getactivescheme' {
            $script:PowerActiveReads++
            if($script:PowerFault -eq 'precondition' -and $script:PowerActiveReads -eq 3){$script:PowerActive=$script:PowerC}
            if($script:PowerFault -eq 'active-invalid'){return (New-PowerNativeResult -Out 'no GUID')}
            return (New-PowerNativeResult -Out ('Power Scheme GUID: '+$script:PowerActive+' (Fixture)'))
        }
        '/query' {
            if(-not $script:PowerPlanMap.ContainsKey($SchemeGuid) -or $script:PowerFault -eq 'query-fail'){return (New-PowerNativeResult 5 '' 'Fixture plan missing or policy denied')}
            return (New-PowerNativeResult -Out ('Power Scheme GUID: '+$SchemeGuid+' (Fixture)'))
        }
        '/setactive' {
            # Every write, including rollback, must have a readable in-flight
            # durable snapshot before this fixture native boundary is reached.
            $journals=@(Get-GoatPowerTransactions $script:PowerSession)
            $inflight=@($journals|Where-Object State -in @('Applying','Restoring'))
            Assert-Power ($inflight.Count -eq 1) 'durable in-flight journal precedes native change'
            Assert-Power ($inflight[0].SnapshotSha256 -eq (Get-GoatPowerSnapshotHash $inflight[0])) 'durable snapshot hash verifies before native change'
            $script:PowerWrites+=$SchemeGuid
            if($script:PowerFault -eq 'no-change'){return (New-PowerNativeResult)}
            if($script:PowerFault -eq 'foreign'){$script:PowerActive=$script:PowerC;return (New-PowerNativeResult)}
            if($script:PowerFault -eq 'partial-once'){$script:PowerActive=$SchemeGuid;$script:PowerFault='';return (New-PowerNativeResult 5 '' 'Fixture partial success then failure')}
            if($script:PowerFault -eq 'rollback-fail'){if($SchemeGuid -eq $script:PowerB){$script:PowerActive=$SchemeGuid};return (New-PowerNativeResult 5 '' 'Fixture native failure')}
            if($script:PowerFault -eq 'remote-failure'){$script:PowerActive=$SchemeGuid;$script:PowerRemote=$true;return (New-PowerNativeResult 5 '' 'Fixture connection context changed')}
            if($script:PowerFault -eq 'timeout'){$script:PowerActive=$SchemeGuid;$script:PowerFault='';return (New-PowerNativeResult 0 '' '' $true)}
            $script:PowerActive=$SchemeGuid
            return (New-PowerNativeResult)
        }
        default {throw ('Unexpected or prohibited powercfg option: '+$Option)}
    }
}
$script:PowerTemp=Join-Path ([IO.Path]::GetTempPath()) ('GOAT-Power-Test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:PowerTemp)
function New-PowerScenario {
    $script:PowerPlanMap=@{};$script:PowerPlanMap[$script:PowerA]='Balanced';$script:PowerPlanMap[$script:PowerB]='Custom (OEM)';$script:PowerPlanMap[$script:PowerC]='Economia'
    $script:PowerActive=$script:PowerA;$script:PowerCalls=@();$script:PowerWrites=@();$script:PowerFault='';$script:PowerAdmin=$true;$script:PowerRemote=$false;$script:PowerContextReads=0;$script:PowerActiveReads=0;$script:PowerJournalDenied=$false;$script:PowerNativePending=$false
    $script:PowerIdentity=[pscustomobject]@{Machine='POWER-MACHINE-FIXTURE';Sid='POWER-SID-FIXTURE'}
    $script:PowerDataRoot=Join-Path $script:PowerTemp ([guid]::NewGuid().ToString('N'))
    $script:PowerSession=New-GoatSession -Root $script:PowerDataRoot
}
try{
    New-PowerScenario
    $plans=Get-GoatPowerPlans
    Assert-Power ($plans.ReadOnly -and $plans.Status -eq 'READ_ONLY' -and $plans.Plans.Count -eq 3) 'existing plans inventoried without mutation'
    Assert-Power ($plans.ActiveSchemeGuid -eq $script:PowerA -and @($plans.Plans|Where-Object IsActive).Count -eq 1) 'actual active GUID read independently'
    Assert-Power (@($plans.Plans|Where-Object Guid -eq $script:PowerB)[0].Name -eq 'Custom (OEM)') 'custom plan name with parentheses retained'
    Assert-Power ($script:PowerWrites.Count -eq 0) 'read-only inventory has no native writes'
    $preview=Get-GoatPowerPreview $script:PowerSession $script:PowerB.ToUpperInvariant()
    Assert-Power ($preview.ExecutionAllowed -and $preview.Changed -and $preview.OriginalSchemeGuid -eq $script:PowerA -and $preview.ProposedSchemeGuid -eq $script:PowerB) 'preview normalizes GUID and shows exact delta'
    Assert-Power ($preview.RequiresAdmin -and $preview.IsNotebook -and $preview.Tradeoffs.Count -ge 4) 'administrator and notebook trade-offs are visible'
    Assert-Power (@(Get-GoatPowerTransactions $script:PowerSession).Count -eq 0 -and $script:PowerWrites.Count -eq 0) 'preview creates no transaction or mutation'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB} 'change requires contextual consent'
    $unknown=Get-GoatPowerPreview $script:PowerSession $script:PowerUnknown
    Assert-Power (-not $unknown.ExecutionAllowed -and $unknown.Status -eq 'BLOCKED') 'unknown valid GUID is blocked'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerUnknown -Consent} 'unknown plan cannot be activated'
    Assert-PowerThrows {Get-GoatPowerPreview $script:PowerSession ($script:PowerB+'; calc')} 'GUID command injection rejected'
    Assert-PowerThrows {&$script:SavedPowerNative -Option /delete} 'production wrapper cannot delete a plan'
    Assert-PowerThrows {&$script:SavedPowerNative -Option /setactive -SchemeGuid 'invalid'} 'production wrapper rejects malformed native arguments before launch'
    Assert-PowerThrows {Get-GoatActionPreview $script:PowerSession @('power-select-existing')} 'power action remains outside the native automatic batch'
    $script:PowerAdmin=$false
    $preview=Get-GoatPowerPreview $script:PowerSession $script:PowerB
    Assert-Power (-not $preview.ExecutionAllowed -and $preview.RequiresAdmin) 'non-elevated mutations conservatively gated'
    $plans=Get-GoatPowerPlans
    Assert-Power ($plans.Status -eq 'READ_ONLY') 'read-only inventory works without the administrator gate'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'administrator gate prevents native mutation'
    $script:PowerAdmin=$true;$script:PowerRemote=$true
    Assert-Power (-not (Get-GoatPowerPreview $script:PowerSession $script:PowerB).ExecutionAllowed) 'remote or uncertain context blocks a change'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'remote mutation refuses to start'
    Assert-Power ($script:PowerWrites.Count -eq 0) 'rejected previews and calls have no native side effects'

    New-PowerScenario
    $reviewed=Get-GoatPowerPreview $script:PowerSession $script:PowerB
    $script:PowerActive=$script:PowerC
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent -ReviewedPreview $reviewed} 'stale reviewed original GUID cannot authorize a new snapshot'
    Assert-Power ($script:PowerWrites.Count -eq 0 -and @(Get-GoatPowerTransactions $script:PowerSession).Count -eq 0) 'stale review aborts before mutation and journaling'
    $script:PowerActive=$script:PowerA
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerC -Consent -ReviewedPreview $reviewed} 'review for one proposed scheme cannot authorize another'
    $reviewed.Changed=$false
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent -ReviewedPreview $reviewed} 'reviewed delta flag must match the current preview'
    $reviewed=Get-GoatPowerPreview $script:PowerSession $script:PowerB
    $otherSession=New-GoatSession -Root $script:PowerDataRoot
    Assert-PowerThrows {Invoke-GoatPowerChange $otherSession $script:PowerB -Consent -ReviewedPreview $reviewed} 'review from another session cannot authorize the same GUID delta'
    Assert-Power ($script:PowerWrites.Count -eq 0 -and @(Get-GoatPowerTransactions $otherSession).Count -eq 0) 'cross-session review rejection precedes journaling and mutation'

    New-PowerScenario;$script:PowerAdmin=$false;$script:PowerRemote=$true
    $noOp=Invoke-GoatPowerChange $script:PowerSession $script:PowerA -Consent
    Assert-Power ($noOp.State -eq 'NoOp' -and $noOp.ReadBackVerified) 'already active plan is a verified no-op'
    Assert-Power ($script:PowerWrites.Count -eq 0 -and @(Get-GoatPowerTransactions $script:PowerSession).Count -eq 0) 'no-op never invokes setactive or creates a recovery journal'

    New-PowerScenario
    $reviewed=Get-GoatPowerPreview $script:PowerSession $script:PowerB
    $changed=Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent -ReviewedPreview $reviewed
    Assert-Power ($changed.State -eq 'Applied' -and $changed.ReadBackVerified -and $script:PowerActive -eq $script:PowerB) 'activation verifies the actual active GUID'
    Assert-Power ($script:PowerWrites.Count -eq 1 -and $script:PowerWrites[0] -eq $script:PowerB) 'minimum single native activation'
    $record=@(Get-GoatPowerTransactions $script:PowerSession)[0]
    Assert-Power ($record.Type -eq 'POWER_SCHEME' -and $record.OriginalSchemeGuid -eq $script:PowerA -and $record.Identity.Sid -eq 'POWER-SID-FIXTURE') 'typed durable journal preserves original GUID and identity'
    Assert-PowerThrows {Restore-GoatPowerChange $script:PowerSession $changed.Id} 'restore requires contextual consent'
    $restored=Restore-GoatPowerChange $script:PowerSession $changed.Id -Consent
    Assert-Power ($restored.State -eq 'Restored' -and $script:PowerActive -eq $script:PowerA) 'explicit restore returns exact prior plan'
    $count=$script:PowerWrites.Count
    Restore-GoatPowerChange $script:PowerSession $changed.Id -Consent|Out-Null
    Assert-Power ($script:PowerWrites.Count -eq $count) 'restore is idempotent'

    New-PowerScenario;$script:PowerFault='partial-once'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'partial native failure is visible'
    $record=@(Get-GoatPowerTransactions $script:PowerSession)[0]
    Assert-Power ($record.State -eq 'Restored' -and $script:PowerActive -eq $script:PowerA) 'partial failure restores and verifies original plan'
    Assert-Power (($script:PowerWrites -join ',') -eq ($script:PowerB+','+$script:PowerA)) 'rollback uses exact prior GUID, not a presumed default'

    New-PowerScenario;$script:PowerFault='no-change'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'exit zero without changed state is never success'
    Assert-Power (@(Get-GoatPowerTransactions $script:PowerSession)[0].State -eq 'Restored' -and $script:PowerWrites.Count -eq 1) 'unchanged original needs no second native write during rollback'

    New-PowerScenario;$script:PowerFault='timeout'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'native timeout triggers recovery rather than success'
    Assert-Power ($script:PowerActive -eq $script:PowerA -and @(Get-GoatPowerTransactions $script:PowerSession)[0].State -eq 'Restored') 'timeout with changed state is rolled back and verified'

    New-PowerScenario;$script:PowerFault='rollback-fail'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'rollback failure is surfaced'
    $record=@(Get-GoatPowerTransactions $script:PowerSession)[0]
    Assert-Power ($record.State -eq 'RestoreFailed' -and $record.OriginalSchemeGuid -eq $script:PowerA -and [IO.File]::Exists($record.JournalPath)) 'failed rollback retains durable snapshot'
    $script:PowerFault=''
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerC -Consent} 'pending power recovery blocks another change'
    Restore-GoatPowerChange $script:PowerSession $record.Id -Consent|Out-Null
    Assert-Power ($script:PowerActive -eq $script:PowerA) 'failed rollback can be retried safely'

    New-PowerScenario;$script:PowerFault='foreign'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'external third-plan interference is detected'
    $record=@(Get-GoatPowerTransactions $script:PowerSession)[0]
    Assert-Power ($record.State -eq 'Conflict' -and $script:PowerActive -eq $script:PowerC -and $script:PowerWrites.Count -eq 1) 'rollback never overwrites an unrelated external plan'
    Assert-PowerThrows {Restore-GoatPowerChange $script:PowerSession $record.Id -Consent} 'external plan requires manual review before restore'
    $script:PowerFault='';$script:PowerActive=$script:PowerB
    Restore-GoatPowerChange $script:PowerSession $record.Id -Consent|Out-Null
    Assert-Power ($script:PowerActive -eq $script:PowerA) 'conflict resolves after original/proposed context is restored manually'

    New-PowerScenario;$script:PowerFault='precondition'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'concurrent plan change before apply aborts'
    Assert-Power ($script:PowerWrites.Count -eq 0 -and @(Get-GoatPowerTransactions $script:PowerSession)[0].State -eq 'Conflict') 'precondition conflict has no native mutation'

    New-PowerScenario;$script:PowerFault='remote-failure'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'loss of trusted local context surfaces'
    $record=@(Get-GoatPowerTransactions $script:PowerSession)[0]
    Assert-Power ($record.State -eq 'RestoreFailed' -and $script:PowerWrites.Count -eq 1) 'recovery does not mutate after remote context becomes uncertain'

    New-PowerScenario
    $changed=Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent
    $script:PowerPlanMap.Remove($script:PowerA)
    Assert-PowerThrows {Restore-GoatPowerChange $script:PowerSession $changed.Id -Consent} 'removed original plan cannot be recreated or replaced by a default'
    Assert-Power (@(Get-GoatPowerTransactions $script:PowerSession)[0].State -eq 'RestoreFailed' -and $script:PowerWrites.Count -eq 1) 'removed plan leaves recoverable evidence without a native restore write'

    New-PowerScenario;$firstSession=$script:PowerSession
    $first=Invoke-GoatPowerChange $firstSession $script:PowerB -Consent
    $script:PowerSession=New-GoatSession -Root $script:PowerDataRoot;$secondSession=$script:PowerSession
    $second=Invoke-GoatPowerChange $secondSession $script:PowerC -Consent
    Assert-Power ($second.Sequence -gt $first.Sequence -and @(Get-GoatPowerTransactions -Session $secondSession -IncludeRelated).Count -eq 2) 'monotonic order spans sibling sessions'
    Assert-PowerThrows {Restore-GoatPowerChange $firstSession $first.Id -Consent} 'older session cannot override a later power transaction'
    Restore-GoatPowerChange $secondSession $second.Id -Consent|Out-Null
    $script:PowerSession=$firstSession
    Restore-GoatPowerChange $firstSession $first.Id -Consent|Out-Null
    Assert-Power ($script:PowerActive -eq $script:PowerA) 'cross-session reverse order restores exact chain'

    New-PowerScenario
    $changed=Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent
    $record=@(Get-GoatPowerTransactions $script:PowerSession)[0];$record.State='Applying'
    Write-GoatPowerJournal $record $record.JournalPath
    $oldSession=$script:PowerSession;$script:PowerSession=New-GoatSession -Root $script:PowerDataRoot
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerC -Consent} 'interrupted transaction in another session blocks new change'
    $script:PowerSession=$oldSession
    Restore-GoatPowerChange $oldSession $changed.Id -Consent|Out-Null
    Assert-Power ($script:PowerActive -eq $script:PowerA) 'interrupted Applying journal is reconciled by explicit verified restore'

    New-PowerScenario
    $changed=Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent
    $script:PowerIdentity.Sid='OTHER-SID'
    Assert-PowerThrows {Restore-GoatPowerChange $script:PowerSession $changed.Id -Consent} 'different user cannot restore a foreign snapshot'
    $script:PowerIdentity.Sid='POWER-SID-FIXTURE';$script:PowerIdentity.Machine='OTHER-WINDOWS'
    Assert-PowerThrows {Restore-GoatPowerChange $script:PowerSession $changed.Id -Consent} 'different Windows cannot restore a foreign snapshot'
    $script:PowerIdentity.Machine='POWER-MACHINE-FIXTURE'
    $record=@(Get-GoatPowerTransactions $script:PowerSession)[0];$record.OriginalSchemeGuid=$script:PowerC
    & $script:SavedPowerJson $record $record.JournalPath
    Assert-PowerThrows {Get-GoatPowerTransactions $script:PowerSession} 'snapshot tampering fails hash validation'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerC -Consent} 'tampered journal blocks new mutation'

    New-PowerScenario;$script:PowerJournalDenied=$true
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'durable journal write failure blocks apply'
    Assert-Power ($script:PowerWrites.Count -eq 0) 'no native write occurs without durable snapshot'
    $script:PowerJournalDenied=$false;$script:PowerNativePending=$true
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'pending registry transaction blocks new power mutation'
    Assert-Power ($script:PowerWrites.Count -eq 0) 'native pending gate has no side effects'

    foreach($fault in @('list-fail','active-invalid','duplicate')){
        New-PowerScenario;$script:PowerFault=$fault;$failed=Get-GoatPowerPlans
        Assert-Power ($failed.Status -eq 'UNAVAILABLE' -and $null -eq $failed.ActiveSchemeGuid -and $failed.Plans.Count -eq 0 -and $failed.Errors.Count -gt 0) ('failed inventory stays unknown: '+$fault)
    }
    New-PowerScenario;$script:PowerFault='query-fail'
    Assert-PowerThrows {Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent} 'selected plan query/access failure aborts before apply'
    Assert-Power ($script:PowerWrites.Count -eq 0 -and @(Get-GoatPowerTransactions $script:PowerSession).Count -eq 0) 'failed plan eligibility leaves no mutation journal'

    New-PowerScenario;$script:PowerSession.State='Finalized';Save-GoatSession $script:PowerSession
    Assert-PowerThrows {Get-GoatPowerPreview $script:PowerSession $script:PowerB} 'finalized session cannot prepare new power actions'
    New-PowerScenario;$script:PowerSession.Demo=$true;Save-GoatSession $script:PowerSession
    $script:PowerCalls=@();$demoPlans=Get-GoatPowerPlans -Demo
    $demo=Invoke-GoatPowerChange $script:PowerSession $script:PowerB -Consent
    $demoRestore=Restore-GoatPowerChange $script:PowerSession 'ignored-demo-id' -Consent
    Assert-Power ($demoPlans.Status -eq 'DEMO' -and $demo.State -eq 'DEMO' -and $demoRestore.State -eq 'DEMO') 'Demo outcomes are visibly simulated'
    Assert-Power ($script:PowerCalls.Count -eq 0 -and $script:PowerWrites.Count -eq 0 -and @(Get-GoatPowerTransactions $script:PowerSession).Count -eq 0) 'Demo never runs powercfg or creates a real power transaction'
    [pscustomobject]@{Module='Power';Passed=$script:PowerChecks.Count;Checks=$script:PowerChecks.ToArray();Mutation='Fixture native provider only; no real powercfg command executed'}|ConvertTo-Json -Depth 4
}finally{
    $resolved=[IO.Path]::GetFullPath($script:PowerTemp)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'GOAT-Power-Test-*'){throw 'Unsafe power fixture cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
