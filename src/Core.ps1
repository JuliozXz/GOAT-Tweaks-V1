# GOAT Tweaks: original session, persistence and transaction engine. PS 5.1.
function Write-GoatJson {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
    $Path=[IO.Path]::GetFullPath($Path)
    $directory = Split-Path -Parent $Path
    [void][IO.Directory]::CreateDirectory($directory)
    $temporary = Join-Path $directory ([guid]::NewGuid().ToString('N') + '.tmp')
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth 64))
    try {
        $stream = [IO.File]::Open($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
        if ([IO.File]::Exists($Path)) {
            # PS5.1 coerces a null backupFileName to an invalid empty string.
            # Use a unique sibling backup and remove it only after atomic replace.
            $previous=$temporary+'.previous'
            [IO.File]::Replace($temporary,$Path,$previous)
            if([IO.File]::Exists($previous)){[IO.File]::Delete($previous)}
        }
        else { [IO.File]::Move($temporary,$Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}
function Get-GoatIdentity {
    $machine = [Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography','MachineGuid',$null)
    if (-not $machine) { throw 'Identidade do Windows indisponível; mutações bloqueadas.' }
    [pscustomobject]@{Machine=[string]$machine;Sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value}
}
function New-GoatSession {
    param([switch]$Demo,[string]$Root)
    if (-not $Root) { $Root=Join-Path $env:LOCALAPPDATA 'GOAT-Tweaks\Sessions' }
    $id=[guid]::NewGuid().ToString('N')
    $session=[pscustomobject]@{
        SchemaVersion=1;Id=$id;CreatedUtc=[DateTime]::UtcNow.ToString('o');State='Open';Demo=[bool]$Demo
        Objective='Equilibrado';Mode='Local';Consent=$false;Inventory=$null;Profiles=@();Benchmarks=@();Comparison=$null
        Root=(Join-Path ([IO.Path]::GetFullPath($Root)) $id);Events=@();Exports=@();FinalExport=$null
    }
    [void][IO.Directory]::CreateDirectory($session.Root)
    Save-GoatSession $session
    return $session
}
function Save-GoatSession {
    param($Session)
    Write-GoatJson $Session (Join-Path $Session.Root 'session.json')
}
function Add-GoatEvent {
    param($Session,[string]$Kind,[string]$Message)
    $event=[pscustomobject]@{Utc=[DateTime]::UtcNow.ToString('o');Kind=$Kind;Message=$Message}
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($event|ConvertTo-Json -Compress)+"`r`n")
    $stream=[IO.File]::Open((Join-Path $Session.Root 'audit.jsonl'),[IO.FileMode]::Append,[IO.FileAccess]::Write,[IO.FileShare]::Read)
    try{$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    $Session.Events+= $event
    Save-GoatSession $Session
}
function Get-GoatActions {
    # These are preferences, never advertised as FPS optimizations. Mutation release
    # is intentionally gated until the documented VM/physical matrix is completed.
    @(
        [pscustomobject]@{Id='explorer-show-extensions';Title='Mostrar extensões de arquivos';Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='HideFileExt';On=0;Off=1;Risk='Baixo / preferência';Reboot=$false;Benefit='Ajuda a identificar tipos de arquivo; FPS não medido.'},
        [pscustomobject]@{Id='explorer-show-hidden';Title='Mostrar arquivos ocultos';Path='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced';Name='Hidden';On=1;Off=2;Risk='Baixo / preferência';Reboot=$false;Benefit='Inspeção técnica; arquivos de sistema protegidos permanecem protegidos.'}
    ) | ForEach-Object {
        $_ | Add-Member Hive 'CurrentUser' -PassThru | Add-Member View 'Registry64' -PassThru |
            Add-Member Status 'IMPLEMENTED_NOT_VALIDATED' -PassThru | Add-Member ReleaseEnabled $false -PassThru
    }
}
function Read-GoatRegistry {
    param($Target)
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$($Target.Hive),[Microsoft.Win32.RegistryView]::$($Target.View))
    try {
        $key=$base.OpenSubKey([string]$Target.Path,$false)
        if (-not $key) { return [pscustomobject]@{KeyExists=$false;Exists=$false;Kind=$null;Data=$null} }
        try {
            if ($key.GetValueNames() -notcontains [string]$Target.Name) { return [pscustomobject]@{KeyExists=$true;Exists=$false;Kind=$null;Data=$null} }
            $kind=$key.GetValueKind([string]$Target.Name).ToString()
            if ($kind -notin @('String','ExpandString','MultiString','Binary','DWord','QWord')) { throw 'Tipo de Registro não suportado.' }
            $data=$key.GetValue([string]$Target.Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
            return [pscustomobject]@{KeyExists=$true;Exists=$true;Kind=$kind;Data=$data}
        } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}
function Write-GoatRegistry {
    param($Target,$State)
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$($Target.Hive),[Microsoft.Win32.RegistryView]::$($Target.View))
    try {
        if (-not $State.Exists) {
            $key=$base.OpenSubKey([string]$Target.Path,$true)
            if ($key) { try { $key.DeleteValue([string]$Target.Name,$false); $key.Flush() } finally { $key.Dispose() } }
            return # Never delete a parent key, even if it did not exist originally.
        }
        $key=$base.CreateSubKey([string]$Target.Path)
        try {
            $data=switch ([string]$State.Kind) {
                Binary { [byte[]]@($State.Data) }; MultiString { [string[]]@($State.Data) }
                DWord { [int]$State.Data }; QWord { [long]$State.Data }
                String { [string]$State.Data }; ExpandString { [string]$State.Data }
                default { throw 'Tipo de Registro não suportado.' }
            }
            $key.SetValue([string]$Target.Name,$data,[Microsoft.Win32.RegistryValueKind]::$($State.Kind)); $key.Flush()
        } finally { $key.Dispose() }
    } finally { $base.Dispose() }
}
function Test-GoatStateEqual {
    param($A,$B)
    if ([bool]$A.Exists -ne [bool]$B.Exists) { return $false }
    if (-not $A.Exists) { return $true }
    if ([string]$A.Kind -cne [string]$B.Kind) { return $false }
    return (($A.Data | ConvertTo-Json -Compress -Depth 8) -ceq ($B.Data | ConvertTo-Json -Compress -Depth 8))
}
function Get-GoatTransactions {
    param($Session)
    $directory=Join-Path $Session.Root 'transactions'
    if (Test-Path -LiteralPath $directory) {
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File | Sort-Object Name)) {
            # A malformed journal must be visible and block changes, never ignored.
            $value=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            $value | Add-Member JournalPath $file.FullName -Force -PassThru
        }
    }
}
function Get-GoatRelatedTransactions {
    param($Session,$Identity)
    # Journals survive a closed UI/new session. Search sibling GOAT session folders
    # while holding the same mutation mutex, so an interrupted batch stays a gate.
    $sessionsRoot=Split-Path ([IO.Path]::GetFullPath($Session.Root)) -Parent
    foreach($folder in @(Get-ChildItem -LiteralPath $sessionsRoot -Directory -ErrorAction Stop)) {
        $sessionFile=Join-Path $folder.FullName 'session.json'
        if(-not [IO.File]::Exists($sessionFile)){continue}
        $owner=Get-Content -LiteralPath $sessionFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if($owner.SchemaVersion -ne 1 -or $owner.Id -cne $folder.Name){continue}
        $owner.Root=$folder.FullName
        foreach($transaction in @(Get-GoatTransactions $owner)) {
            if($transaction.Identity.Machine -eq $Identity.Machine -and $transaction.Identity.Sid -eq $Identity.Sid){$transaction}
        }
    }
}
function Get-GoatPendingTransactions {
    param($Session,$Identity)
    Get-GoatRelatedTransactions $Session $Identity | Where-Object State -in @('Applying','Restoring','RestoreFailed','Prepared')
}
function Get-GoatActionPreview {
    param($Session,[string[]]$Ids,[ValidateSet('On','Off')][string]$Direction='On',[switch]$InspectOnly)
    if ($Session.State -ne 'Open') { throw 'Sessão encerrada. Abra uma nova sessão.' }
    if (@($Ids).Count -eq 0 -or @($Ids | Select-Object -Unique).Count -ne @($Ids).Count) { throw 'Seleção vazia ou duplicada.' }
    foreach ($id in $Ids) {
        $action=@(Get-GoatActions | Where-Object Id -eq $id)
        if ($action.Count -ne 1) { throw ('Ação desconhecida: '+$id) }
        $action=$action[0]
        $allowed=($Session.Demo -or ($action.ReleaseEnabled -and $action.Status -eq 'IMPLEMENTED_AND_TESTED'))
        if (-not $allowed -and -not $InspectOnly) { throw 'Ação aguardando validação de bancada. Disponível apenas para simulação.' }
        $before=if($Session.Demo){[pscustomobject]@{KeyExists=$true;Exists=$false;Kind=$null;Data=$null}}else{Read-GoatRegistry $action}
        $proposed=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='DWord';Data=$action.$Direction}
        [pscustomobject]@{Id=$id;Action=$action;Before=$before;Proposed=$proposed;Direction=$Direction;Changed=(-not (Test-GoatStateEqual $before $proposed));ExecutionAllowed=$allowed;Note=$(if($allowed){'Revise a prévia antes de aplicar.'}else{'Somente leitura; executor aguardando validação de bancada.'})}
    }
}
function Assert-GoatTransaction {
    param($Transaction,$Identity)
    if ($Transaction.SchemaVersion -ne 1 -or $Transaction.Identity.Machine -ne $Identity.Machine -or $Transaction.Identity.Sid -ne $Identity.Sid) { throw 'Diário pertence a outro Windows/usuário ou schema desconhecido.' }
    foreach ($step in @($Transaction.Steps)) {
        $allowed=@(Get-GoatActions | Where-Object Id -eq $step.Id)
        if ($allowed.Count -ne 1) { throw 'Diário contém ação não autorizada.' }
        foreach ($field in @('Hive','View','Path','Name')) {
            if ([string]$allowed[0].$field -cne [string]$step.Target.$field) { throw 'Alvo do diário diverge do executor.' }
        }
        if ($step.Original.Exists -and $step.Original.Kind -notin @('String','ExpandString','MultiString','Binary','DWord','QWord')) { throw 'Snapshot inválido.' }
    }
}
function Undo-GoatTransactionInternal {
    param($Transaction,[string]$Path)
    $Transaction.State='Restoring'; Write-GoatJson $Transaction $Path
    $steps=@($Transaction.Steps); [array]::Reverse($steps)
    $failures=@()
    foreach ($step in $steps) {
        if ($step.State -in @('Applying','Applied','Restoring','RestoreFailed')) {
            try {
                $step.State='Restoring'; Write-GoatJson $Transaction $Path
                Write-GoatRegistry $step.Target $step.Original
                if (-not (Test-GoatStateEqual (Read-GoatRegistry $step.Target) $step.Original)) { throw 'Leitura após reversão divergiu.' }
                $step.State='Restored'; $step.Error=$null; Write-GoatJson $Transaction $Path
            } catch { $step.State='RestoreFailed';$step.Error=$_.Exception.Message;$failures+=$_.Exception.Message;Write-GoatJson $Transaction $Path }
        }
    }
    $Transaction.State=if($failures.Count){'RestoreFailed'}else{'Restored'}
    Write-GoatJson $Transaction $Path
    if ($failures.Count) { throw ('Reversão incompleta. Preserve diário: '+($failures -join '; ')) }
}
function Invoke-GoatActionBatch {
    param($Session,[string[]]$Ids,[ValidateSet('On','Off')][string]$Direction='On',[switch]$Consent)
    if (-not $Consent) { throw 'Consentimento contextual necessário após revisar a prévia.' }
    $preview=@(Get-GoatActionPreview $Session $Ids $Direction)
    if ($Session.Demo) {
        Add-GoatEvent $Session 'DEMO' ('Simulação de '+($Ids -join ', ')+'; nenhuma alteração do Windows.')
        return [pscustomobject]@{State='DEMO';Steps=$preview;Message='Simulação concluída; nenhuma alteração do Windows.'}
    }
    $mutex=[Threading.Mutex]::new($false,'Local\GOAT-Tweaks-Actions')
    $locked=$false
    try {
        try { $locked=$mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $locked=$true }
        if (-not $locked) { throw 'Outra operação GOAT está ativa.' }
        $identity=Get-GoatIdentity
        $pending=@(Get-GoatPendingTransactions $Session $identity)
        if ($pending.Count) { throw 'Recupere a transação interrompida antes de novas ações.' }
        # Re-read under the resource lock. The preview does not authorize stale state.
        $preview=@(Get-GoatActionPreview $Session $Ids $Direction)
        $transaction=[pscustomobject]@{SchemaVersion=1;Id=[guid]::NewGuid().ToString('N');Identity=$identity;CreatedUtc=[DateTime]::UtcNow.ToString('o');State='Prepared';Steps=@()}
        foreach ($item in $preview) {
            $transaction.Steps+=[pscustomobject]@{Id=$item.Id;Target=$item.Action;Original=$item.Before;Proposed=$item.Proposed;State='Prepared';Error=$null}
        }
        $path=Join-Path $Session.Root ('transactions\'+$transaction.Id+'.json')
        Write-GoatJson $transaction $path # durable exact snapshot before first write
        try {
            $transaction.State='Applying'; Write-GoatJson $transaction $path
            foreach ($step in $transaction.Steps) {
                $step.State='Applying'; Write-GoatJson $transaction $path
                Write-GoatRegistry $step.Target $step.Proposed
                if (-not (Test-GoatStateEqual (Read-GoatRegistry $step.Target) $step.Proposed)) { throw 'Verificação após aplicação falhou.' }
                $step.State='Applied'; Write-GoatJson $transaction $path
            }
            $transaction.State='Applied'; Write-GoatJson $transaction $path
            Add-GoatEvent $Session 'Applied' ('Transação verificada '+$transaction.Id)
            return $transaction
        } catch {
            $failure=$_.Exception.Message
            Undo-GoatTransactionInternal $transaction $path
            throw ('Aplicação falhou e foi revertida: '+$failure)
        }
    } finally { if($locked){$mutex.ReleaseMutex()};$mutex.Dispose() }
}
function Restore-GoatTransaction {
    param($Session,[string]$TransactionId,[switch]$Consent)
    if (-not $Consent) { throw 'Confirme a restauração da transação selecionada.' }
    if ($Session.Demo) { return [pscustomobject]@{State='DEMO';Message='Restauração simulada; nenhuma alteração.'} }
    $mutex=[Threading.Mutex]::new($false,'Local\GOAT-Tweaks-Actions');$locked=$false
    try {
        try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw 'Outra operação GOAT está ativa.'}
        $all=@(Get-GoatTransactions $Session)
        $transaction=@($all | Where-Object Id -eq $TransactionId)
        if($transaction.Count -ne 1){throw 'Transação não encontrada.'}
        $transaction=$transaction[0]
        Assert-GoatTransaction $transaction (Get-GoatIdentity)
        if($transaction.State -eq 'Restored'){return $transaction}
        $later=@(Get-GoatRelatedTransactions $Session (Get-GoatIdentity) | Where-Object { $_.CreatedUtc -gt $transaction.CreatedUtc -and $_.State -ne 'Restored' })
        if($later.Count){throw 'Restaure primeiro a transação mais recente para preservar a ordem dos valores.'}
        Undo-GoatTransactionInternal $transaction $transaction.JournalPath
        Add-GoatEvent $Session 'Restored' ('Restaurada '+$TransactionId)
        return $transaction
    } finally { if($locked){$mutex.ReleaseMutex()};$mutex.Dispose() }
}
