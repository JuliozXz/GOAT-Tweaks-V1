[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\src\Core.ps1')
$script:OriginalWriteGoatLog = (Get-Item Function:Write-GoatLog).ScriptBlock

# These tests exercise the actual catalog, write-ahead journal, allowlist,
# transaction engine and recovery. All Windows mutation boundaries are mocked.
$script:SandboxParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$script:Sandbox = Join-Path $script:SandboxParent ('GOAT-CoreTests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:Sandbox) | Out-Null
$script:Passed = 0
$script:Scan = [pscustomobject]@{ IsDemo=$false; OS=[pscustomobject]@{ Supported=$true }; Power=[pscustomobject]@{ IsLaptop=$false } }

function Assert-Test {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Complete-Test {
    param([string]$Name)
    $script:Passed++
    Write-Output "PASS $Name"
}

function Get-TestValueKey {
    param([string]$Path, [string]$Name)
    return ($Path.ToUpperInvariant() + '|' + $Name.ToUpperInvariant())
}

function Reset-TestScenario {
    param([string]$Name)
    $script:TestRoot = Join-Path $script:Sandbox $Name
    [IO.Directory]::CreateDirectory($script:TestRoot) | Out-Null
    $script:Registry = @{}
    $script:Keys = @{}
    $script:WriteCount = 0
    $script:Writes = New-Object 'System.Collections.Generic.List[object]'
    $script:FailOnWrite = 0
    $script:CheckpointCalls = 0
    $script:CheckpointFails = $false
    $script:MemoryCompression = $false
    $script:MemoryReadFails = $false
    $script:MemoryWriteFails = $false
    $script:FailCommitLog = $false
    $script:CommitFailureObserved = $false
    $script:Points = @()
    $script:MachineGuid = 'TEST-MACHINE-ONE'
    $script:UserSid = 'S-1-5-21-TEST-ONE'
    $script:Admin = $true
    $script:ExpectedOriginals = @{}
}

function Add-TestRegistryValue {
    param([string]$Path, [string]$Name, $Value, [string]$Type='DWord')
    $script:Keys[$Path] = $true
    $script:Registry[(Get-TestValueKey $Path $Name)] = [pscustomobject]@{ Path=$Path; Name=$Name; Exists=$true; KeyExisted=$true; Value=$Value; Type=$Type }
}

function Get-TestJournal {
    $backupRoot = Join-Path $script:TestRoot 'backups'
    if (-not (Test-Path -LiteralPath $backupRoot)) { return $null }
    foreach ($file in @(Get-ChildItem -LiteralPath $backupRoot -Filter '*.json' -File | Sort-Object Name -Descending)) {
        $candidate = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($candidate.MachineGuid -eq $script:MachineGuid -and $candidate.UserSid -eq $script:UserSid) { return $candidate }
    }
    return $null
}

function Test-GoatAdministrator { return $script:Admin }
function Get-GoatStorageRoot { return $script:TestRoot }
function Get-GoatMachineIdentity { return [pscustomobject]@{ MachineGuid=$script:MachineGuid; UserSid=$script:UserSid } }
function Get-GoatActivePowerScheme { return '381b4222-f694-41f0-9685-ff5bb260df2e' }
function Get-GoatTcpAutoTuning { return 'restricted' }
function Get-NetOffloadGlobalSetting { param($ErrorAction) return [pscustomobject]@{ ReceiveSideScaling='Disabled' } }
function Invoke-GoatNative {
    param($File, $Arguments)
    if (($Arguments -join ' ') -eq '/list') { return '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c' }
    throw 'TEST GUARD: native mutation must never be invoked.'
}
function Set-NetTCPSetting { throw 'TEST GUARD: TCP mutation must never be invoked.' }
function Get-MMAgent {
    if ($script:MemoryReadFails) { throw 'SIMULATED: unavailable MMAgent' }
    return [pscustomobject]@{MemoryCompression=$script:MemoryCompression}
}
function Set-TestMemoryCompression {
    param([bool]$Enabled)
    $journal=Get-TestJournal
    Assert-Test ($journal.RestorePoint -eq 123) 'Memory compression write must have verified protection.'
    Assert-Test ($journal.Steps[0].Original -is [bool]) 'Original Boolean memory state must be persisted before writing.'
    Assert-Test ($journal.Steps[0].Status -in @('Applying','Applied','Restoring')) 'Memory step intent must precede writing.'
    $script:WriteCount++
    $script:MemoryCompression=$Enabled
    if ($script:MemoryWriteFails) { $script:MemoryWriteFails=$false; throw 'SIMULATED: MMAgent failed after writing' }
}
function Enable-MMAgent { param([switch]$MemoryCompression) Set-TestMemoryCompression $true }
function Disable-MMAgent { param([switch]$MemoryCompression) Set-TestMemoryCompression $false }
function Set-NetOffloadGlobalSetting { throw 'TEST GUARD: offload mutation must never be invoked.' }
function Checkpoint-Computer { throw 'TEST GUARD: real checkpoint API must never be invoked.' }
function Write-GoatLog {
    param([string]$Path, [string]$Message, [string]$Level='INFO')
    if ($script:FailCommitLog -and $Message.StartsWith('COMMIT -')) {
        Assert-Test ((Get-TestJournal).Status -eq 'Applied') 'The commit log regression must fail after the Applied journal was persisted.'
        $script:CommitFailureObserved = $true
        $script:FailCommitLog = $false
        throw 'SIMULATED: final COMMIT log write failed'
    }
    & $script:OriginalWriteGoatLog $Path $Message $Level
}
function New-GoatRestorePoint {
    param($TransactionId, $LogPath)
    $script:CheckpointCalls++
    if ($script:CheckpointFails) { throw 'SIMULATED: restore point unavailable' }
    $script:Points = @([pscustomobject]@{ SequenceNumber=123; Description="GOAT v2.2 $TransactionId" })
    return 123
}
function Get-CimInstance {
    param($Namespace,$ClassName,$OperationTimeoutSec,$ErrorAction)
    if ($ClassName -ne 'SystemRestore' -or $Namespace -ne 'root/default') { throw 'Unexpected CIM query in transaction tests.' }
    return $script:Points
}
function Get-GoatRegistryState {
    param([string]$Path, [string]$Name)
    $id = Get-TestValueKey $Path $Name
    if ($script:Registry.ContainsKey($id)) {
        $value = $script:Registry[$id]
        return [pscustomobject]@{ Path=$Path; Name=$Name; Exists=$true; KeyExisted=$true; Value=$value.Value; Type=$value.Type }
    }
    return [pscustomobject]@{ Path=$Path; Name=$Name; Exists=$false; KeyExisted=$script:Keys.ContainsKey($Path); Value=$null; Type='DWord' }
}
function Set-GoatRegistryState {
    param($State)
    $script:WriteCount++
    $journal = Get-TestJournal
    Assert-Test ($null -ne $journal) 'Durable backup must exist before every write.'
    Assert-Test ($journal.RestorePoint -eq 123) 'A confirmed restore point must precede writes.'
    Assert-Test ($journal.Status -in @('Applying','Applied','Restoring')) 'Journal must identify a protected apply or restore, including rollback after commit-log failure.'
    $pending = @($journal.Steps | Where-Object { $_.Original.Path -eq $State.Path -and $_.Original.Name -eq $State.Name })
    Assert-Test ($pending.Count -eq 1) 'Every write must have exactly one captured original.'
    Assert-Test ($pending[0].Status -in @('Applying','Applied','Restoring')) 'Step intent must be durable before the write.'
    foreach ($expectedId in $script:ExpectedOriginals.Keys) {
        $original = $script:ExpectedOriginals[$expectedId]
        $persisted = @($journal.Steps | Where-Object { $_.Original.Path -eq $original.Path -and $_.Original.Name -eq $original.Name })
        Assert-Test ($persisted.Count -eq 1) 'ALL originals must be captured before the first write.'
        Assert-Test ((ConvertTo-Json -InputObject $persisted[0].Original -Compress) -eq (ConvertTo-Json -InputObject $original -Compress)) 'Persisted original value/type/existence must match the pre-apply snapshot.'
    }
    $id = Get-TestValueKey $State.Path $State.Name
    $script:Writes.Add([pscustomobject]@{ Name=$State.Name; Value=$State.Value; Exists=$State.Exists; Type=$State.Type })
    if ($State.Exists) {
        $script:Keys[$State.Path] = $true
        $script:Registry[$id] = [pscustomobject]@{ Path=$State.Path; Name=$State.Name; Exists=$true; KeyExisted=$true; Value=$State.Value; Type=$State.Type }
    }
    else {
        $script:Registry.Remove($id)
        $remaining = @($script:Registry.Values | Where-Object { $_.Path -eq $State.Path })
        if (-not $State.KeyExisted -and $remaining.Count -eq 0) { $script:Keys.Remove($State.Path) }
    }
    # Fail after the simulated write to ensure the engine recovers in-flight
    # mutations, rather than only writes known to have completed successfully.
    if ($script:FailOnWrite -gt 0 -and $script:WriteCount -eq $script:FailOnWrite) { throw 'SIMULATED: mutation failed after touching value' }
}

function Save-TestExpectedOriginals {
    param([string[]]$Ids)
    foreach ($tweak in @(Get-GoatTweaks -Scan $script:Scan | Where-Object { $_.Id -in $Ids })) {
        foreach ($target in $tweak.Targets) {
            $original = Get-GoatRegistryState $target.Path $target.Name
            $script:ExpectedOriginals[(Get-TestValueKey $target.Path $target.Name)] = $original
        }
    }
}

function Assert-TestOriginalsRestored {
    foreach ($original in $script:ExpectedOriginals.Values) {
        $actual = Get-GoatRegistryState $original.Path $original.Name
        Assert-Test ((ConvertTo-Json -InputObject $actual -Compress) -eq (ConvertTo-Json -InputObject $original -Compress)) ('Original configuration was not restored: ' + $original.Name)
    }
}

try {
    Reset-TestScenario 'demo'
    $result = Invoke-GoatApply -Ids @('game-mode') -Scan $script:Scan -Demo
    $undo = Restore-GoatLastTransaction -Demo
    Assert-Test ($result.Success -and $undo.Success) 'Demo apply and restore should succeed.'
    Assert-Test ($script:WriteCount -eq 0 -and $script:CheckpointCalls -eq 0) 'Demo must not mutate settings or create checkpoints.'
    Assert-Test (@(Get-ChildItem -LiteralPath $script:TestRoot -Recurse -File).Count -eq 0) 'Demo must not create backups or logs.'
    Complete-Test 'Demo performs no writes or checkpoint calls'

    Reset-TestScenario 'checkpoint-failure'
    Save-TestExpectedOriginals @('game-mode')
    $script:CheckpointFails = $true
    $result = Invoke-GoatApply -Ids @('game-mode') -Scan $script:Scan
    Assert-Test (-not $result.Success) 'Failed protection must abort apply.'
    Assert-Test ($script:WriteCount -eq 0 -and $script:CheckpointCalls -eq 1) 'No mutation may follow checkpoint failure.'
    $journal = Get-TestJournal
    Assert-Test ($journal.Status -eq 'Failed' -and $journal.Steps.Count -eq 2) 'Failed checkpoint must leave an intact original-state journal.'
    Complete-Test 'Failed checkpoint blocks changes after persisting originals'

    Reset-TestScenario 'rollback'
    Add-TestRegistryValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0
    Save-TestExpectedOriginals @('game-mode')
    $script:FailOnWrite = 2
    $result = Invoke-GoatApply -Ids @('game-mode') -Scan $script:Scan
    Assert-Test (-not $result.Success) 'Injected partial failure must fail the transaction.'
    Assert-Test ($script:WriteCount -eq 4) 'Both the applied and in-flight values must be rolled back.'
    Assert-Test ($script:Writes[2].Name -eq 'AllowAutoGameMode' -and $script:Writes[3].Name -eq 'AutoGameModeEnabled') 'Rollback order must reverse mutation order.'
    Assert-Test ((Get-TestJournal).Status -eq 'Failed') 'A fully rolled back transaction must be marked Failed.'
    Assert-TestOriginalsRestored
    Complete-Test 'Partial failure restores applied and in-flight values in reverse order'

    Reset-TestScenario 'successful-restore'
    Add-TestRegistryValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0
    Add-TestRegistryValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 1
    Add-TestRegistryValue 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '1' 'String'
    Save-TestExpectedOriginals @('game-mode','visual-effects')
    $result = Invoke-GoatApply -Ids @('game-mode','visual-effects') -Scan $script:Scan
    Assert-Test ($result.Success -and $script:WriteCount -eq 5) 'Five registry writes should be verified and committed.'
    Assert-Test ((Get-TestJournal).Status -eq 'Applied') 'Successful transaction must be committed.'
    $undo = Restore-GoatLastTransaction
    Assert-Test ($undo.Success) ('Restore failed: ' + $undo.Message)
    Assert-Test ($script:WriteCount -eq 10 -and $script:CheckpointCalls -eq 1) 'Restore must use original captured state and reuse its confirmed restore point.'
    Assert-Test ((Get-TestJournal).Status -eq 'Restored') 'Successful undo must be committed.'
    Assert-TestOriginalsRestored
    Complete-Test 'Apply and undo preserve DWORD/String types, missing values and key existence'

    Reset-TestScenario 'interrupted'
    Save-TestExpectedOriginals @('game-mode')
    $result = Invoke-GoatApply -Ids @('game-mode') -Scan $script:Scan
    Assert-Test ($result.Success) 'Fixture apply failed.'
    $journal = Get-TestJournal
    $journal.Status = 'Applying'
    $journal.Steps[1].Status = 'Applying'
    $journalPath = Join-Path $script:TestRoot ('backups\' + $journal.Id + '.json')
    Write-GoatJournal $journal $journalPath
    $blocked = Invoke-GoatApply -Ids @('visual-effects') -Scan $script:Scan
    Assert-Test (-not $blocked.Success -and $script:WriteCount -eq 2) 'A pending journal must block another apply batch.'
    $script:Points = @()
    $undo = Restore-GoatLastTransaction
    Assert-Test ($undo.Success -and $script:CheckpointCalls -eq 2) 'Interrupted recovery must create protection if the original point is gone.'
    Assert-TestOriginalsRestored
    Complete-Test 'Interrupted write is recoverable and blocks overlapping batches'

    Reset-TestScenario 'wrong-machine'
    $result = Invoke-GoatApply -Ids @('game-mode') -Scan $script:Scan
    Assert-Test ($result.Success) 'Fixture apply failed.'
    $script:MachineGuid = 'OTHER-WINDOWS'
    $undo = Restore-GoatLastTransaction
    Assert-Test (-not $undo.Success -and $script:WriteCount -eq 2) 'Foreign machine journal must be rejected without writes.'
    $script:MachineGuid = 'TEST-MACHINE-ONE'; $script:UserSid = 'S-1-5-21-OTHER-USER'
    $undo = Restore-GoatLastTransaction
    Assert-Test (-not $undo.Success -and $script:WriteCount -eq 2) 'Foreign user journal must be rejected without writes.'
    Complete-Test 'Machine and user identity are checked before restore'

    Reset-TestScenario 'commit-log-failure'
    Add-TestRegistryValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 0
    Save-TestExpectedOriginals @('game-mode')
    $script:FailCommitLog = $true
    $result = Invoke-GoatApply -Ids @('game-mode') -Scan $script:Scan
    Assert-Test ($script:CommitFailureObserved -and -not $result.Success) 'Final COMMIT logging failure must return failure after commit was attempted.'
    Assert-Test ($script:WriteCount -eq 4) 'Commit logging failure must roll back both completed changes.'
    $journal = Get-TestJournal
    Assert-Test ($journal.Status -eq 'Failed') 'Commit logging failure must leave a Failed journal after complete rollback.'
    Assert-Test (@($journal.Steps | Where-Object { $_.Status -ne 'RolledBack' }).Count -eq 0) 'No applied step may be hidden in the failed transaction.'
    Assert-TestOriginalsRestored
    Complete-Test 'Final COMMIT logging failure rolls back already committed changes'

    Reset-TestScenario 'unsupported-original-kind'
    Add-TestRegistryValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 7 'None'
    Save-TestExpectedOriginals @('game-mode')
    $result = Invoke-GoatApply -Ids @('game-mode') -Scan $script:Scan
    Assert-Test (-not $result.Success) 'An unsupported original RegistryValueKind must be rejected.'
    Assert-Test ($script:WriteCount -eq 0 -and $script:CheckpointCalls -eq 0) 'Unsupported original types must stop the batch before any mutation or checkpoint call.'
    Assert-TestOriginalsRestored
    Complete-Test 'Unsupported original registry types prevent all writes'

    Reset-TestScenario 'mixed-identities'
    Save-TestExpectedOriginals @('game-mode')
    $result = Invoke-GoatApply -Ids @('game-mode') -Scan $script:Scan
    Assert-Test ($result.Success) 'Fixture apply failed.'
    $ownJournal = Get-TestJournal
    $foreignJournal = $ownJournal | ConvertTo-Json -Depth 16 | ConvertFrom-Json
    $foreignJournal.Id = '99999999-foreign-user'
    $foreignJournal.UserSid = 'S-1-5-21-FOREIGN-USER'
    $foreignPath = Join-Path $script:TestRoot 'backups\99999999-foreign-user.json'
    Write-GoatJournal $foreignJournal $foreignPath
    $undo = Restore-GoatLastTransaction
    Assert-Test ($undo.Success -and $undo.TransactionId -eq $ownJournal.Id) 'Restore must skip a newer foreign-user journal and restore the latest current-user transaction.'
    Assert-Test ($script:WriteCount -eq 4) 'Only the current-user transaction may be undone.'
    Assert-Test ((Get-TestJournal).Status -eq 'Restored') 'The current-user journal must be marked restored.'
    $foreignAfter = Get-Content -LiteralPath $foreignPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert-Test ($foreignAfter.Status -eq 'Applied' -and $foreignAfter.UserSid -eq 'S-1-5-21-FOREIGN-USER') 'Foreign-user journal must remain unchanged.'
    Assert-TestOriginalsRestored
    Complete-Test 'Newer foreign-user journal is skipped in favor of the current user'

    Reset-TestScenario 'unknown-id'
    $result = Invoke-GoatApply -Ids @('not-a-real-tweak') -Scan $script:Scan
    Assert-Test (-not $result.Success -and $script:WriteCount -eq 0 -and $script:CheckpointCalls -eq 0) 'Unknown tweak must fail before protection or mutations.'
    Complete-Test 'Unknown IDs are rejected'

    Reset-TestScenario 'no-admin'
    $script:Admin = $false
    $result = Invoke-GoatApply -Ids @('game-mode') -Scan $script:Scan
    $undo = Restore-GoatLastTransaction
    Assert-Test (-not $result.Success -and -not $undo.Success -and $script:WriteCount -eq 0) 'Apply and restore require administrator access.'
    Complete-Test 'Administrator guard applies to mutation and recovery'

    Reset-TestScenario 'memory-compression-restore'
    $result=Invoke-GoatApply -Ids @('memory-compression') -Scan $script:Scan
    Assert-Test ($result.Success -and $script:MemoryCompression) 'Compression must enable through protected transaction.'
    Assert-Test ((Get-TestJournal).Steps[0].Original -eq $false) 'Disabled original must be saved as Boolean false.'
    $undo=Restore-GoatLastTransaction
    Assert-Test ($undo.Success -and -not $script:MemoryCompression -and $script:WriteCount -eq 2) 'Undo must restore original compression state.'
    Complete-Test 'Memory compression apply and undo preserve original Boolean state'

    Reset-TestScenario 'memory-compression-partial-failure'
    $script:MemoryWriteFails=$true
    $result=Invoke-GoatApply -Ids @('memory-compression') -Scan $script:Scan
    Assert-Test (-not $result.Success -and -not $script:MemoryCompression -and $script:WriteCount -eq 2) 'Partial compression write must roll back its original state.'
    Complete-Test 'Memory compression partial failure rolls back in-flight change'

    Reset-TestScenario 'memory-compression-unavailable'
    $script:MemoryReadFails=$true
    $result=Invoke-GoatApply -Ids @('memory-compression') -Scan $script:Scan
    Assert-Test (-not $result.Success -and $script:WriteCount -eq 0 -and $script:CheckpointCalls -eq 0) 'Unknown compression state must block mutation.'
    Complete-Test 'Unknown memory compression state blocks apply'

    Reset-TestScenario 'demo-advanced-state'
    $demoScan=[pscustomobject]@{IsDemo=$true;OS=[pscustomobject]@{Supported=$true};AdvancedState=[pscustomobject]@{Readings=@{
        'memory-compression'=[pscustomobject]@{Available=$true;Value=$false}
        'network-autotuning'=[pscustomobject]@{Available=$true;Value='normal'}
        'rss'=[pscustomobject]@{Available=$true;Value='Enabled'}
    }}}
    foreach ($snapshot in @($demoScan,($demoScan|ConvertTo-Json -Depth 8|ConvertFrom-Json))) {
        $demoTweaks=@(Get-GoatTweaks -Scan $snapshot)
        $memory=@($demoTweaks|Where-Object Id -eq 'memory-compression')[0]
        Assert-Test ($memory.Available -and $memory.Recommended) 'Demo compression false must remain available before and after JSON conversion.'
        Assert-Test (@($demoTweaks|Where-Object {$_.Id -in @('tcp-normal','rss-on') -and $_.State -eq 'Aplicado'}).Count -eq 2) 'Demo TCP and RSS must agree with the configured advanced snapshot.'
    }
    Assert-Test ($script:WriteCount -eq 0) 'Demo catalog cannot write Windows state.'
    Complete-Test 'Demo recommendations and native states agree across JSON round-trip'

    Write-Output "PASS: $script:Passed transaction tests; no Windows settings were changed."
}
finally {
    # Only this unique test directory may be recursively removed. Resolve both
    # paths in PowerShell before deletion and keep the entire operation here.
    $resolvedSandbox = [IO.Path]::GetFullPath($script:Sandbox)
    $allowedPrefix = $script:SandboxParent.TrimEnd('\') + '\GOAT-CoreTests-'
    if (-not $resolvedSandbox.StartsWith($allowedPrefix, [StringComparison]::OrdinalIgnoreCase) -or $resolvedSandbox -eq $script:SandboxParent.TrimEnd('\')) {
        throw 'Unsafe test cleanup path rejected.'
    }
    if (Test-Path -LiteralPath $resolvedSandbox) { Remove-Item -LiteralPath $resolvedSandbox -Recurse -Force }
}
