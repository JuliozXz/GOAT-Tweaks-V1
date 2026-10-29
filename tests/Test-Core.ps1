#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Core.ps1')
$script:CoreChecks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Core {param([bool]$Condition,[string]$Name)if(-not $Condition){throw "Core assertion failed: $Name"};$script:CoreChecks.Add($Name)}
function Assert-CoreThrows {param([scriptblock]$Code,[string]$Name)$failed=$false;try{&$Code|Out-Null}catch{$failed=$true};Assert-Core $failed $Name}
function Copy-FixtureState {param($Value) $Value|ConvertTo-Json -Depth 32|ConvertFrom-Json}
$script:FixtureActions=@(Get-GoatActions)
$script:OriginalActions=@($script:FixtureActions|ForEach-Object{$_|ConvertTo-Json -Depth 16|ConvertFrom-Json})
$script:FixtureContext=[pscustomobject]@{Build=19045;WindowsMajor=10;ProductType=1;Architecture='AMD64';Is64BitProcess=$true;Edition='Professional';IsAdmin=$true;Managed=$false;RemoteState='LOCAL_CONSOLE';Source='FIXTURE'}
$script:FixtureRegistry=@{};$script:FixtureWrites=@();$script:FixtureFailure='';$script:FixtureIdentity=[pscustomobject]@{Machine='MACHINE-FIXTURE';Sid='SID-FIXTURE'}
foreach($action in $script:FixtureActions){$action.ReleaseEnabled=$true;$action.Status='IMPLEMENTED_AND_TESTED'}
function Get-GoatActions {$script:FixtureActions}
function Get-GoatActionContext {param($Session);Copy-FixtureState $script:FixtureContext}
function Get-GoatIdentity {Copy-FixtureState $script:FixtureIdentity}
function Read-GoatRegistry {param($Target)if($script:FixtureRegistry.ContainsKey($Target.Id)){Copy-FixtureState $script:FixtureRegistry[$Target.Id]}else{[pscustomobject]@{KeyExists=$true;Exists=$false;Kind=$null;Data=$null}}}
function Write-GoatRegistry {
    param($Target,$State)
    # Verify a durable in-flight journal precedes every mutation, including undo.
    $journals=@(Get-ChildItem -LiteralPath $script:ActiveSession.Root -Recurse -Filter '*.json'|Where-Object DirectoryName -like '*transactions*'|ForEach-Object{Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8|ConvertFrom-Json})
    $recorded=@($journals|ForEach-Object Steps|Where-Object {$_.Id -eq $Target.Id -and $_.State -in @('Applying','Restoring')})
    if($recorded.Count -eq 0){throw 'No durable journal before fixture write'}
    $script:FixtureWrites+=($Target.Id+':'+[bool]$State.Exists+':'+[string]$State.Data)
    if($script:FixtureFailure -eq 'beforewrite'){$script:FixtureFailure='';throw 'Fixture access denied before first write'}
    if($script:FixtureFailure -eq 'rollback' -and $State.Kind -ne 'DWord'){throw 'Fixture rollback failure'}
    if($script:FixtureFailure -eq 'partial' -and $Target.Id -eq 'explorer-show-hidden' -and $State.Kind -eq 'DWord'){
        $script:FixtureRegistry[$Target.Id]=Copy-FixtureState $State
        $script:FixtureFailure=''
        throw 'Fixture partial write then throw'
    }
    $script:FixtureRegistry[$Target.Id]=Copy-FixtureState $State
    if($script:FixtureFailure -eq 'readback' -and $State.Kind -eq 'DWord'){$script:FixtureRegistry[$Target.Id].Data=99;$script:FixtureFailure=''}
    if($script:FixtureFailure -eq 'rollback' -and $State.Kind -eq 'DWord'){$script:FixtureRegistry[$Target.Id].Data=99}
}
$root=Join-Path ([IO.Path]::GetTempPath()) ('GOAT-Core-Test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($root)
try {
    $script:ActiveSession=New-GoatSession -Root $root
    $session=$script:ActiveSession
    Assert-Core ([IO.File]::Exists((Join-Path $session.Root 'session.json'))) 'session saved with unique ownership'
    $session.Inventory=[pscustomobject]@{PrivateFixture='DO-NOT-PERSIST'};Save-GoatSession $session
    $storedSession=Get-Content -LiteralPath (Join-Path $session.Root 'session.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-Core ($null -eq $storedSession.Inventory -and $session.Inventory.PrivateFixture -eq 'DO-NOT-PERSIST') 'inventory stays in UI memory without persistence consent'
    $session.Consent=$true;Save-GoatSession $session
    $storedSession=Get-Content -LiteralPath (Join-Path $session.Root 'session.json') -Raw -Encoding UTF8|ConvertFrom-Json
    Assert-Core ($storedSession.Inventory.PrivateFixture -eq 'DO-NOT-PERSIST') 'inventory persisted only with explicit boolean consent'
    $loaded=Import-GoatSession -Path (Join-Path $session.Root 'session.json') -Demo:$false
    Assert-Core ($loaded.Id -eq $session.Id -and $loaded.Root -eq $session.Root) 'session loader validates and canonicalizes the actual session directory'
    Assert-CoreThrows {Import-GoatSession -Path (Join-Path $session.Root 'session.json') -Demo} 'session loader cannot silently convert real session to Demo'
    $storedSession.Consent=$false;Write-GoatJson $storedSession (Join-Path $session.Root 'session.json')
    $loaded=Import-GoatSession -Path (Join-Path $session.Root 'session.json')
    Assert-Core ($null -eq $loaded.Inventory -and $loaded.RuntimeWarnings.Count -gt 0) 'loader discards legacy inventory stored without consent'
    $storedSession.State='Finalizing';$storedSession.FinalExport=$null;Write-GoatJson $storedSession (Join-Path $session.Root 'session.json')
    $loaded=Import-GoatSession -Path (Join-Path $session.Root 'session.json')
    Assert-Core ($loaded.State -eq 'Open' -and $loaded.RuntimeWarnings.Count -gt 0) 'interrupted finalization without valid export reopens for review'
    $storedSession.State='ExecuteAnything';Write-GoatJson $storedSession (Join-Path $session.Root 'session.json')
    Assert-CoreThrows {Import-GoatSession -Path (Join-Path $session.Root 'session.json')} 'session loader rejects unknown state'
    Save-GoatSession $session
    $preview=@(Get-GoatActionPreview -Session $session -Ids explorer-show-extensions)
    Assert-Core ($preview.Count -eq 1 -and $preview[0].Changed -and -not $preview[0].Before.Exists -and $preview[0].Proposed.Data -eq 0) 'preview preserves absence and shows proposed DWORD'
    Assert-Core ($script:FixtureWrites.Count -eq 0) 'preview has no registry writes'
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions} 'batch requires consent'
    Assert-CoreThrows {Get-GoatActionPreview $session @('explorer-show-extensions','explorer-show-extensions')} 'duplicate action rejected'
    Assert-CoreThrows {Get-GoatActionPreview $session @('not-real')} 'unknown action rejected'
    $script:FixtureActions[0].Status='SPEC_ONLY_NOT_YET_VERIFIED'
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent} 'spec status cannot execute even with release flag'
    $script:FixtureActions[0].Status='IMPLEMENTED_AND_TESTED';$script:FixtureActions[0].ReleaseEnabled=$false
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent} 'release flag independently gates mutation'
    $script:FixtureActions[0].ReleaseEnabled=$true
    $transaction=Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent
    $disk=@(Get-GoatTransactions $session)[0]
    Assert-Core ($transaction.State -eq 'Applied' -and $disk.State -eq 'Applied' -and $disk.Steps[0].State -eq 'Applied') 'batch durable and verified'
    Assert-Core (-not $disk.Steps[0].Original.Exists -and $disk.Steps[0].Target.Hive -eq 'CurrentUser' -and $disk.Steps[0].Target.View -eq 'Registry64') 'snapshot preserves hive view and absence'
    Assert-Core ($disk.Steps[0].SnapshotSha256 -eq (Get-GoatSnapshotHash $disk.Steps[0])) 'exact snapshot hash persists and verifies'
    $altered=Copy-FixtureState $disk;$altered.Steps[0].Original.Exists=$true;$altered.Steps[0].Original.Kind='String';$altered.Steps[0].Original.Data='ALTERED'
    Assert-CoreThrows {Assert-GoatTransaction $altered $script:FixtureIdentity} 'modified original data cannot pass snapshot integrity'
    $altered=Copy-FixtureState $disk;$altered.Steps[0].State='EXECUTE_SCRIPT'
    Assert-CoreThrows {Assert-GoatTransaction $altered $script:FixtureIdentity} 'unknown journal step cannot skip recovery with false restored state'
    $altered=Copy-FixtureState $disk;$altered.Steps[0].Original.Exists='false'
    Assert-CoreThrows {Assert-GoatTransaction $altered $script:FixtureIdentity} 'presence flag string cannot masquerade as snapshot boolean'
    Assert-CoreThrows {Restore-GoatTransaction $session $transaction.Id} 'restore requires consent'
    Restore-GoatTransaction $session $transaction.Id -Consent|Out-Null
    Assert-Core (-not (Read-GoatRegistry $script:FixtureActions[0]).Exists) 'restore original absence does not set opposite preference'
    $writeCount=$script:FixtureWrites.Count
    Restore-GoatTransaction $session $transaction.Id -Consent|Out-Null
    Assert-Core ($script:FixtureWrites.Count -eq $writeCount) 'restoration idempotent'
    $configured=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='DWord';Data=0};$script:FixtureRegistry['explorer-show-extensions']=Copy-FixtureState $configured
    $writeCount=$script:FixtureWrites.Count;$unchanged=Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent
    Assert-Core ($unchanged.Steps[0].State -eq 'Unchanged' -and $script:FixtureWrites.Count -eq $writeCount) 'already configured preference records no-op without a registry write'
    Restore-GoatTransaction $session $unchanged.Id -Consent|Out-Null
    Assert-Core ($script:FixtureWrites.Count -eq $writeCount) 'restoring no-op never overwrites the unchanged original'
    $drift=Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Direction Off -Consent
    $script:FixtureRegistry['explorer-show-extensions'].Data=99;$writeCount=$script:FixtureWrites.Count
    Assert-CoreThrows {Restore-GoatTransaction $session $drift.Id -Consent} 'external state drift requires review before explicit restoration'
    Assert-Core ($script:FixtureWrites.Count -eq $writeCount) 'drifted value is preserved rather than overwritten'
    $script:FixtureRegistry['explorer-show-extensions'].Data=1;Restore-GoatTransaction $session $drift.Id -Consent|Out-Null

    foreach($fixture in @(@('String','original'),@('ExpandString','%USERPROFILE%\fixture'),@('MultiString',@('a','b')),@('Binary',@([byte]0,[byte]255)),@('QWord',[long]4294967296),@('DWord',-2147483648))) {
        $original=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind=$fixture[0];Data=$fixture[1]}
        $script:FixtureRegistry['explorer-show-extensions']=Copy-FixtureState $original
        $tx=Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent
        Restore-GoatTransaction $session $tx.Id -Consent|Out-Null
        Assert-Core (Test-GoatStateEqual (Read-GoatRegistry $script:FixtureActions[0]) $original) ('exact original kind and data '+$fixture[0])
    }
    $beforeA=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='String';Data='before-a'}
    $beforeB=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='String';Data='before-b'}
    $script:FixtureRegistry['explorer-show-extensions']=Copy-FixtureState $beforeA;$script:FixtureRegistry['explorer-show-hidden']=Copy-FixtureState $beforeB
    $script:FixtureFailure='partial';$script:FixtureWrites=@()
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids @('explorer-show-extensions','explorer-show-hidden') -Consent} 'partial write failure surfaces'
    Assert-Core ((Test-GoatStateEqual (Read-GoatRegistry $script:FixtureActions[0]) $beforeA) -and (Test-GoatStateEqual (Read-GoatRegistry $script:FixtureActions[1]) $beforeB)) 'partially written in-flight step and prior step restored'
    Assert-Core ($script:FixtureWrites[-2] -like 'explorer-show-hidden*' -and $script:FixtureWrites[-1] -like 'explorer-show-extensions*') 'rollback reverses dependency order'
    $script:FixtureFailure='readback'
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent} 'readback mismatch fails batch'
    Assert-Core (Test-GoatStateEqual (Read-GoatRegistry $script:FixtureActions[0]) $beforeA) 'readback failure restored original'
    $script:FixtureFailure='beforewrite';$writes=$script:FixtureWrites.Count
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent} 'pre-mutation write denial surfaces'
    Assert-Core ($script:FixtureWrites.Count -eq ($writes+1) -and (Test-GoatStateEqual (Read-GoatRegistry $script:FixtureActions[0]) $beforeA) -and @(Get-GoatPendingTransactions $session $script:FixtureIdentity).Count -eq 0) 'unchanged original is verified without unnecessary rollback writes'
    $script:FixtureFailure='rollback'
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent} 'rollback failure surfaces'
    $failed=@(Get-GoatTransactions $session|Where-Object State -eq RestoreFailed)[0]
    Assert-Core ($failed.Steps[0].Original.Data -eq 'before-a' -and [IO.File]::Exists($failed.JournalPath)) 'failed rollback preserves original journal'
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids explorer-show-hidden -Consent} 'pending recovery blocks new mutation'
    $other=New-GoatSession -Root $root
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $other -Ids explorer-show-hidden -Consent} 'pending journal in earlier session blocks new session'
    $script:FixtureFailure=''
    Restore-GoatTransaction $session $failed.Id -Consent|Out-Null
    Assert-Core (Test-GoatStateEqual (Read-GoatRegistry $script:FixtureActions[0]) $beforeA) 'retry completes failed rollback'

    $tx1=Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent
    $tx2=Invoke-GoatActionBatch -Session $session -Ids explorer-show-hidden -Consent
    Assert-CoreThrows {Restore-GoatTransaction $session $tx1.Id -Consent} 'older transaction cannot override newer batch'
    $stored=@(Get-GoatTransactions $session|Where-Object Id -eq $tx2.Id)[0]
    $originalTarget=$stored.Steps[0].Target.Path;$stored.Steps[0].Target.Path='Software\WrongTarget'
    Write-GoatJson $stored $stored.JournalPath
    $beforeWrites=$script:FixtureWrites.Count
    Assert-CoreThrows {Restore-GoatTransaction $session $tx2.Id -Consent} 'tampered journal target rejected'
    Assert-Core ($script:FixtureWrites.Count -eq $beforeWrites) 'tampered target causes no write'
    $stored.Steps[0].Target.Path=$originalTarget;Write-GoatJson $stored $stored.JournalPath
    $script:FixtureIdentity.Sid='OTHER-SID'
    Assert-CoreThrows {Restore-GoatTransaction $session $tx2.Id -Consent} 'wrong user identity rejected'
    $script:FixtureIdentity.Sid='SID-FIXTURE';$script:FixtureIdentity.Machine='OTHER-MACHINE'
    Assert-CoreThrows {Restore-GoatTransaction $session $tx2.Id -Consent} 'wrong Windows identity rejected'
    $script:FixtureIdentity.Machine='MACHINE-FIXTURE'
    Restore-GoatTransaction $session $tx2.Id -Consent|Out-Null
    Restore-GoatTransaction $session $tx1.Id -Consent|Out-Null
    $crash=Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent
    $crashJournal=@(Get-GoatTransactions $session|Where-Object Id -eq $crash.Id)[0]
    $crashJournal.State='Applying';$crashJournal.Steps[0].State='Applying';Write-GoatJson $crashJournal $crashJournal.JournalPath
    Restore-GoatTransaction $session $crash.Id -Consent|Out-Null
    Assert-Core ((Get-GoatTransactions $session|Where-Object Id -eq $crash.Id).State -eq 'Restored') 'recovery handles crash with durable in-flight step'
    $older=Invoke-GoatActionBatch -Session $session -Ids explorer-show-extensions -Consent
    $script:ActiveSession=$other
    $newer=Invoke-GoatActionBatch -Session $other -Ids explorer-show-hidden -Consent
    $script:ActiveSession=$session
    Assert-CoreThrows {Restore-GoatTransaction $session $older.Id -Consent} 'restore order is enforced across sibling sessions'
    $script:ActiveSession=$other;Restore-GoatTransaction $other $newer.Id -Consent|Out-Null
    $script:ActiveSession=$session;Restore-GoatTransaction $session $older.Id -Consent|Out-Null
    $native=@($script:OriginalActions|Where-Object ExecutorKind -eq 'RegistryValue')
    Assert-Core ($native.Count -ge 12) 'at least twelve native executors have explicit fixed registry targets'
    foreach($action in $native){
        Assert-Core ($action.ReleaseEnabled -and $action.Status -eq 'IMPLEMENTED_AND_TESTED' -and $action.ValidationScope -match 'HKCU' -and @($action.Sources).Count -gt 0) ('metadata declares executor validation scope and sources '+$action.Id)
        $script:FixtureContext.Build=if($action.MaxBuild -gt 0){$action.MaxBuild}else{[Math]::Max(26100,$action.MinBuild)}
        foreach($direction in @('On','Off')){
            $original=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='String';Data=('ORIGINAL-'+$action.Id)}
            $script:FixtureRegistry[$action.Id]=Copy-FixtureState $original
            $tx=Invoke-GoatActionBatch -Session $session -Ids $action.Id -Direction $direction -Consent -ApprovedActionIds @($action.Id)
            Assert-Core ($tx.State -eq 'Applied' -and (Read-GoatRegistry $action).Data -eq $action.$direction) ('native apply and readback '+$action.Id+'/'+$direction)
            Restore-GoatTransaction $session $tx.Id -Consent|Out-Null
            Assert-Core (Test-GoatStateEqual (Read-GoatRegistry $action) $original) ('native restores exact prior kind/data '+$action.Id+'/'+$direction)
        }
        $script:FixtureFailure='readback'
        Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids $action.Id -Consent -ApprovedActionIds @($action.Id)} ('native failure surfaces '+$action.Id)
        Assert-Core (Test-GoatStateEqual (Read-GoatRegistry $action) $original) ('native failure rollback verifies '+$action.Id)
    }
    $script:FixtureContext.Build=26100
    $policy=@($script:FixtureActions|Where-Object Id -eq 'capture-recording-policy')[0]
    $preview=@(Get-GoatActionPreview -Session $session -Ids $policy.Id -InspectOnly)[0]
    Assert-Core (-not $preview.ExecutionAllowed -and $preview.EffectiveState -eq 'UNKNOWN') 'Windows11 capture policy stays ineligible and effective state is never inferred'
    $script:FixtureContext.Build=19045;$script:FixtureContext.IsAdmin=$false
    Assert-CoreThrows {Invoke-GoatActionBatch $session @($policy.Id) -Consent -ApprovedActionIds @($policy.Id)} 'HKLM action requires elevation even with explicit approval'
    $script:FixtureContext.IsAdmin=$true;$script:FixtureContext.Edition='Core'
    Assert-CoreThrows {Invoke-GoatActionBatch $session @($policy.Id) -Consent -ApprovedActionIds @($policy.Id)} 'unsupported Home edition cannot apply Pro policy'
    $script:FixtureContext.Edition='Professional';$script:FixtureContext.Managed=$true
    Assert-CoreThrows {Invoke-GoatActionBatch $session @($policy.Id) -Consent -ApprovedActionIds @($policy.Id)} 'managed computer policy gate cannot be bypassed by action approval'
    $script:FixtureContext.Managed=$false;$script:FixtureContext.RemoteState='REMOTE_OR_POSSIBLE_REMOTE'
    Assert-CoreThrows {Invoke-GoatActionBatch $session @($policy.Id) -Consent -ApprovedActionIds @($policy.Id)} 'capture policy blocked in remote or uncertain context'
    $script:FixtureContext.RemoteState='LOCAL_CONSOLE'
    Assert-CoreThrows {Invoke-GoatActionBatch $session @($policy.Id) -Consent} 'approval-class action requires approval of its exact ID'
    Assert-CoreThrows {Invoke-GoatActionBatch $session @($policy.Id,'explorer-show-hidden') -Consent -ApprovedActionIds @($policy.Id)} 'individual action cannot be mixed into a batch'
    $safeIds=@($native|Where-Object ExecutionClass -eq 'A_AUTO_SAFE'|Select-Object -First 8 -ExpandProperty Id)
    Assert-CoreThrows {Invoke-GoatActionBatch $session $safeIds -Consent} 'batch hard limit is seven even for low-risk preferences'
    $script:FixtureContext.Architecture='ARM64'
    Assert-CoreThrows {Invoke-GoatActionBatch $session @('explorer-show-hidden') -Consent} 'unsupported architecture blocks real executor'
    $script:FixtureContext.Architecture='AMD64';$script:FixtureContext.ProductType=3
    Assert-CoreThrows {Invoke-GoatActionBatch $session @('explorer-show-hidden') -Consent} 'Windows Server does not pass client support gate'
    $script:FixtureContext.ProductType=1;$script:FixtureContext.Build=$null
    Assert-CoreThrows {Invoke-GoatActionBatch $session @('explorer-show-hidden') -Consent} 'unknown build cannot become eligible'
    $script:FixtureContext.Build=19045
    Assert-CoreThrows {Invoke-GoatActionBatch $session @('ui-taskbar-animations-guide') -Consent} 'manual animation guide is included but never executable'
    $legacy=Copy-FixtureState $transaction;$legacy.PSObject.Properties.Remove('Approval');$legacy.Steps[0].Target.PSObject.Properties.Remove('Kind');$legacy.Steps[0].Target.PSObject.Properties.Remove('ExecutorKind')
    Assert-GoatTransaction $legacy $script:FixtureIdentity
    Assert-Core $true '7.3.0 exact-target DWORD journals remain valid without new target metadata'
    $reviewed=@(Get-GoatActionPreview $session @('explorer-show-extensions'))
    $changedAfterPreview=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='String';Data='changed after consent preview'}
    $script:FixtureRegistry['explorer-show-extensions']=$changedAfterPreview;$writes=$script:FixtureWrites.Count
    Assert-CoreThrows {Invoke-GoatActionBatch $session @('explorer-show-extensions') -Consent -ReviewedPreview $reviewed} 'reviewed preview detects changed state before the first write'
    Assert-Core ($script:FixtureWrites.Count -eq $writes -and (Test-GoatStateEqual (Read-GoatRegistry $script:FixtureActions[0]) $changedAfterPreview)) 'preview mismatch preserves the externally changed preference'
    $script:FixturePowerPending=$true
    function Get-GoatPowerPendingTransactions {param($Session,$Identity);if($script:FixturePowerPending){[pscustomobject]@{State='Applying';Identity=$Identity}}}
    $writes=$script:FixtureWrites.Count
    Assert-CoreThrows {Invoke-GoatActionBatch $session @('explorer-show-extensions') -Consent} 'interrupted power transaction blocks new registry batch'
    Assert-Core ($script:FixtureWrites.Count -eq $writes) 'cross-engine pending gate runs before any registry write'
    $script:FixturePowerPending=$false
    $reviewed=@(Get-GoatActionPreview $session @('explorer-show-extensions'))
    $anotherSession=New-GoatSession -Root $root;$writes=$script:FixtureWrites.Count
    Assert-CoreThrows {Invoke-GoatActionBatch $anotherSession @('explorer-show-extensions') -Consent -ReviewedPreview $reviewed} 'identical target and state cannot reuse a preview from another session'
    Assert-Core ($script:FixtureWrites.Count -eq $writes -and $reviewed[0].SessionId -eq $session.Id) 'preview session binding is checked before journal or registry write'
    $malformed=Join-Path $session.Root 'transactions\malformed.json';[IO.File]::WriteAllText($malformed,'{broken')
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids explorer-show-hidden -Consent} 'malformed journal blocks new action'
    [IO.File]::SetAttributes($malformed,[IO.FileAttributes]::Hidden)
    Assert-CoreThrows {Invoke-GoatActionBatch -Session $session -Ids explorer-show-hidden -Consent} 'hidden malformed journal cannot disappear from recovery gate'
    [IO.File]::Delete($malformed)
    $demo=New-GoatSession -Demo -Root $root
    $writes=$script:FixtureWrites.Count;$demoTx=Invoke-GoatActionBatch -Session $demo -Ids explorer-show-hidden -Consent
    Assert-Core ($demoTx.State -eq 'DEMO' -and $writes -eq $script:FixtureWrites.Count -and @(Get-GoatTransactions $demo).Count -eq 0) 'demo has no mutation or recovery journal'
    $demo.State='Finalized'
    Assert-CoreThrows {Get-GoatActionPreview $demo @('explorer-show-hidden')} 'finalized session blocks new preview and action'
    $session.State='Finalized';Save-GoatSession $session;$session.State='Open'
    Assert-CoreThrows {Get-GoatActionPreview $session @('explorer-show-hidden')} 'stale in-memory model cannot reopen a finalized persisted session'
} finally {
    $full=[IO.Path]::GetFullPath($root)
    if(-not $full.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $full -Leaf) -notlike 'GOAT-Core-Test-*'){throw 'Unsafe fixture cleanup'}
    Remove-Item -LiteralPath $full -Recurse -Force
}
[pscustomobject]@{Module='Core';Passed=$script:CoreChecks.Count;Checks=@($script:CoreChecks.ToArray());Mutation='In-memory registry fixtures only'}|ConvertTo-Json -Depth 4
