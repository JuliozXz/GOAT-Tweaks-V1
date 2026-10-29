# GOAT Tweaks: original session, persistence and transaction engine. PS 5.1.
function Assert-GoatPlainFilePath {
    param([Parameter(Mandatory=$true)][string]$Path)
    $current=[IO.Path]::GetFullPath($Path)
    while($current){
        if(Test-Path -LiteralPath $current){$item=Get-Item -LiteralPath $current -Force -ErrorAction Stop;if($item.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Caminho com link/junction/reparse point bloqueado para preservar o destino exato.'}}
        $parent=Split-Path $current -Parent;if($parent -eq $current){break};$current=$parent
    }
}
function Write-GoatJson {
    param([Parameter(Mandatory)]$Value,[Parameter(Mandatory)][string]$Path)
    $Path=[IO.Path]::GetFullPath($Path)
    Assert-GoatPlainFilePath $Path
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
    # Never persist the read-only scan merely because it is visible in the UI.
    # Copy the model so the UI keeps its current inventory in memory.
    $persisted=$Session|ConvertTo-Json -Depth 64|ConvertFrom-Json
    if($Session.Consent -isnot [bool] -or -not $Session.Consent){$persisted.Inventory=$null}
    Write-GoatJson $persisted (Join-Path $Session.Root 'session.json')
}
function Import-GoatSession {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path,[switch]$Demo)
    $file=Get-Item -LiteralPath $Path -ErrorAction Stop
    Assert-GoatPlainFilePath $file.FullName
    if($file.PSIsContainer -or $file.Name -ine 'session.json' -or $file.Length -gt 64MB -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Selecione um arquivo session.json regular de até 64 MiB.'}
    $loadMutex=[Threading.Mutex]::new($false,'Local\GOAT-Tweaks-Actions');$loadLocked=$false
    try {
    try{$loadLocked=$loadMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$loadLocked=$true}
    if(-not $loadLocked){throw 'Outra operação GOAT está ativa. Aguarde antes de retomar a sessão.'}
    $session=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
    if($session -is [array] -or $session.SchemaVersion -ne 1 -or [string]$session.Id -notmatch '^[a-f0-9]{32}$' -or $session.Demo -isnot [bool] -or $session.Consent -isnot [bool] -or $session.State -notin @('Open','Finalizing','Finalized')){throw 'Schema, identidade ou estado da sessão inválido.'}
    $created=[datetime]::MinValue;if(-not [datetime]::TryParse([string]$session.CreatedUtc,[ref]$created)){throw 'Horário da sessão inválido.'}
    foreach($field in @('Events','Exports','Profiles','Benchmarks')){if($session.$field -isnot [array]){throw ('Coleção inválida na sessão: '+$field)}}
    foreach($field in @('Inventory','Root','FinalExport','Comparison','Objective','Mode')){if($null -eq $session.PSObject.Properties[$field]){throw ('Campo ausente na sessão: '+$field)}}
    if($session.Mode -notin @('Local','Remoto') -or $session.Objective -notin @('Equilibrado','Competitivo','Qualidade')){throw 'Contexto de atendimento inválido.'}
    if($PSBoundParameters.ContainsKey('Demo') -and $session.Demo -ne [bool]$Demo){throw 'O modo da sessão não corresponde ao modo de execução solicitado.'}
    $warnings=New-Object 'System.Collections.Generic.List[string]'
    $session.Root=[IO.Path]::GetFullPath($file.DirectoryName)
    if(-not $session.Consent -and $null -ne $session.Inventory){$session.Inventory=$null;$warnings.Add('Inventário encontrado sem consentimento de persistência; descartado da sessão carregada.')}
    # Reading and validating journals also blocks malformed/unknown targets before
    # the imported model can reach any action handler.
    @(Get-GoatTransactions $session)|Out-Null
    if($session.State -eq 'Finalizing'){
        $verified=$false
        if($session.FinalExport -and (Get-Command Test-GoatExport -ErrorAction SilentlyContinue)){
            try{$verified=[bool](Test-GoatExport -Directory $session.FinalExport -ExpectedSessionId $session.Id -RequireFinalized)}catch{$warnings.Add('Exportação de finalização interrompida não validada: '+$_.Exception.Message)}
        }
        if($verified){$session.State='Finalized';$warnings.Add('Finalização interrompida reconciliada com pacote íntegro.')}
        else{$session.State='Open';$warnings.Add('Finalização interrompida: sessão reaberta para revisão. Arquivos parciais e recuperação preservados.')}
        Save-GoatSession $session
    }
    $session|Add-Member RuntimeWarnings @($warnings.ToArray()) -Force -PassThru
    }finally{if($loadLocked){$loadMutex.ReleaseMutex()};$loadMutex.Dispose()}
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
function Assert-GoatRegistrySnapshot {
    param($State)
    if($null -eq $State -or $State.Exists -isnot [bool] -or $State.KeyExists -isnot [bool]){throw 'Snapshot sem flags de presença válidas.'}
    if(-not $State.Exists){if($null -ne $State.Kind -or $null -ne $State.Data){throw 'Snapshot ausente contém tipo/dados.'};return}
    if(-not $State.KeyExists){throw 'Snapshot de valor presente exige chave presente.'}
    if($State.Kind -notin @('String','ExpandString','MultiString','Binary','DWord','QWord')){throw 'Tipo de snapshot inválido.'}
    switch([string]$State.Kind){
        {$_ -in @('String','ExpandString')} {if($State.Data -isnot [string]){throw 'Snapshot textual inválido.'}}
        'MultiString' {if($State.Data -isnot [array] -or @($State.Data|Where-Object{$_ -isnot [string]}).Count){throw 'Snapshot MultiString inválido.'}}
        'Binary' {if($State.Data -isnot [array]){throw 'Snapshot binário inválido.'};foreach($byte in $State.Data){if($byte -isnot [ValueType] -or [double]$byte -lt 0 -or [double]$byte -gt 255 -or [double]$byte -ne [Math]::Truncate([double]$byte)){throw 'Byte de snapshot inválido.'}}}
        {$_ -in @('DWord','QWord')} {if($State.Data -isnot [int] -and $State.Data -isnot [long]){throw 'Snapshot inteiro inválido.'};if($_ -eq 'DWord' -and ([long]$State.Data -lt [int]::MinValue -or [long]$State.Data -gt [int]::MaxValue)){throw 'DWord fora da faixa.'}}
    }
}
function Get-GoatSnapshotHash {
    param($Step)
    $canonical=[ordered]@{Id=[string]$Step.Id;Hive=[string]$Step.Target.Hive;View=[string]$Step.Target.View;Path=[string]$Step.Target.Path;Name=[string]$Step.Target.Name;Original=[ordered]@{KeyExists=$Step.Original.KeyExists;Exists=$Step.Original.Exists;Kind=$Step.Original.Kind;Data=$Step.Original.Data};Proposed=[ordered]@{KeyExists=$Step.Proposed.KeyExists;Exists=$Step.Proposed.Exists;Kind=$Step.Proposed.Kind;Data=$Step.Proposed.Data}}
    $bytes=[Text.Encoding]::UTF8.GetBytes(($canonical|ConvertTo-Json -Depth 16 -Compress));$sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Get-GoatTransactions {
    param($Session)
    $directory=Join-Path $Session.Root 'transactions'
    Assert-GoatPlainFilePath $directory
    if (Test-Path -LiteralPath $directory) {
        foreach ($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -Force | Sort-Object Name)) {
            Assert-GoatPlainFilePath $file.FullName
            # A malformed journal must be visible and block changes, never ignored.
            $value=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
            if($value.Id -cne $file.BaseName){throw 'Nome do diário diverge do ID da transação.'}
            Assert-GoatTransaction $value
            $value | Add-Member JournalPath $file.FullName -Force | Out-Null
            $value | Add-Member OwnerSessionId $Session.Id -Force | Out-Null
            $value | Add-Member OwnerSessionRoot $Session.Root -Force -PassThru
        }
    }
}
function Get-GoatRelatedTransactions {
    param($Session,$Identity)
    # Journals survive a closed UI/new session. Search sibling GOAT session folders
    # while holding the same mutation mutex, so an interrupted batch stays a gate.
    $roots=New-Object 'System.Collections.Generic.List[object]'
    $roots.Add([pscustomobject]@{Id=$Session.Id;Root=[IO.Path]::GetFullPath($Session.Root)})
    $sessionsRoot=Split-Path ([IO.Path]::GetFullPath($Session.Root)) -Parent
    $groups=@($sessionsRoot)
    $groupProperty=$Session.PSObject.Properties['RecoveryGroupRoot']
    $recoveryRoot=if($groupProperty -and $groupProperty.Value){[IO.Path]::GetFullPath([string]$groupProperty.Value)}else{[IO.Path]::GetFullPath($Session.Root)}
    if($groupProperty -and $groupProperty.Value){$mainFile=Join-Path $recoveryRoot 'session.json';if([IO.File]::Exists($mainFile)){$main=Get-Content -LiteralPath $mainFile -Raw -Encoding UTF8|ConvertFrom-Json;$roots.Add([pscustomobject]@{Id=$main.Id;Root=$recoveryRoot})}}
    $embedded=Join-Path $recoveryRoot 'related-sessions';if([IO.Directory]::Exists($embedded)){$groups+=$embedded}
    foreach($group in $groups){foreach($folder in @(Get-ChildItem -LiteralPath $group -Directory -ErrorAction Stop)) {
        if($folder.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Sessão com redirecionamento de pasta bloqueada.'}
        $sessionFile=Join-Path $folder.FullName 'session.json'
        if(-not [IO.File]::Exists($sessionFile)){continue}
        $owner=Get-Content -LiteralPath $sessionFile -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
        if($owner.SchemaVersion -ne 1 -or $owner.Id -cne $folder.Name){continue}
        $roots.Add([pscustomobject]@{Id=$owner.Id;Root=$folder.FullName})
    }}
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($owner in $roots){if(-not $seen.Add([IO.Path]::GetFullPath($owner.Root))){continue};foreach($transaction in @(Get-GoatTransactions $owner)) {
        if($transaction.Identity.Machine -eq $Identity.Machine -and $transaction.Identity.Sid -eq $Identity.Sid){$transaction}
    }}
}
function Get-GoatPendingTransactions {
    param($Session,$Identity)
    Get-GoatRelatedTransactions $Session $Identity | Where-Object State -in @('Applying','Restoring','RestoreFailed','Prepared')
}
function Get-GoatActionPreview {
    param($Session,[string[]]$Ids,[ValidateSet('On','Off')][string]$Direction='On',[switch]$InspectOnly)
    if ($Session.State -ne 'Open') { throw 'Sessão encerrada. Abra uma nova sessão.' }
    $persisted=Get-Content -LiteralPath (Join-Path $Session.Root 'session.json') -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
    if($persisted.Id -cne $Session.Id -or $persisted.State -ne 'Open'){throw 'A sessão persistida foi encerrada ou está em outra operação. Reabra o atendimento antes de continuar.'}
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
    if ($Transaction.SchemaVersion -ne 1 -or [string]$Transaction.Id -notmatch '^[a-f0-9]{32}$' -or [string]::IsNullOrWhiteSpace([string]$Transaction.Identity.Machine) -or [string]::IsNullOrWhiteSpace([string]$Transaction.Identity.Sid)) { throw 'Identidade/schema do diário inválido.' }
    if($null -ne $Identity -and ($Transaction.Identity.Machine -cne $Identity.Machine -or $Transaction.Identity.Sid -cne $Identity.Sid)){throw 'Diário pertence a outro Windows/usuário.'}
    if($Transaction.State -notin @('Prepared','Applying','Applied','Restoring','Restored','RestoreFailed')){throw 'Estado de transação desconhecido.'}
    $timestamp=[datetime]::MinValue;if(-not [datetime]::TryParse([string]$Transaction.CreatedUtc,[ref]$timestamp)){throw 'Horário da transação inválido.'}
    if(@($Transaction.Steps).Count -lt 1 -or @($Transaction.Steps).Count -gt 16 -or @($Transaction.Steps.Id|Select-Object -Unique).Count -ne @($Transaction.Steps).Count){throw 'Etapas ausentes ou duplicadas no diário.'}
    foreach ($step in @($Transaction.Steps)) {
        $allowed=@(Get-GoatActions | Where-Object Id -eq $step.Id)
        if ($allowed.Count -ne 1) { throw 'Diário contém ação não autorizada.' }
        foreach ($field in @('Hive','View','Path','Name')) {
            if ([string]$allowed[0].$field -cne [string]$step.Target.$field) { throw 'Alvo do diário diverge do executor.' }
        }
        if($step.State -notin @('Prepared','Applying','Applied','Restoring','Restored','RestoreFailed','Unchanged')){throw 'Estado de etapa desconhecido.'}
        Assert-GoatRegistrySnapshot $step.Original;Assert-GoatRegistrySnapshot $step.Proposed
        if($step.Proposed.Kind -ne 'DWord' -or -not $step.Proposed.Exists -or $step.Proposed.Data -notin @($allowed[0].On,$allowed[0].Off)){throw 'Pós-condição não pertence ao executor autorizado.'}
        if([string]$step.SnapshotSha256 -notmatch '^[a-f0-9]{64}$' -or $step.SnapshotSha256 -cne (Get-GoatSnapshotHash $step)){throw 'Hash do snapshot divergiu. Preserve o diário para análise.'}
        if($step.State -eq 'Unchanged' -and -not (Test-GoatStateEqual $step.Original $step.Proposed)){throw 'Etapa sem mudança diverge do snapshot.'}
        if($Transaction.State -eq 'Applied' -and $step.State -notin @('Applied','Unchanged')){throw 'Transação aplicada contém etapa não verificada.'}
        if($Transaction.State -eq 'Prepared' -and $step.State -ne 'Prepared'){throw 'Transação preparada contém estado inconsistente.'}
        if($Transaction.State -eq 'Restored' -and $step.State -notin @('Restored','Prepared','Unchanged')){throw 'Transação restaurada contém etapa pendente.'}
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
            $step=[pscustomobject]@{Id=$item.Id;Target=($item.Action|ConvertTo-Json -Depth 8|ConvertFrom-Json);Original=($item.Before|ConvertTo-Json -Depth 16|ConvertFrom-Json);Proposed=($item.Proposed|ConvertTo-Json -Depth 16|ConvertFrom-Json);State='Prepared';Error=$null;SnapshotSha256=$null}
            Assert-GoatRegistrySnapshot $step.Original;Assert-GoatRegistrySnapshot $step.Proposed
            $step.SnapshotSha256=Get-GoatSnapshotHash $step;$transaction.Steps+=$step
        }
        $path=Join-Path $Session.Root ('transactions\'+$transaction.Id+'.json')
        Write-GoatJson $transaction $path # durable exact snapshot before first write
        $saved=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json;Assert-GoatTransaction $saved $identity
        try {
            $transaction.State='Applying'; Write-GoatJson $transaction $path
            foreach ($step in $transaction.Steps) {
                if(Test-GoatStateEqual $step.Original $step.Proposed){$step.State='Unchanged';Write-GoatJson $transaction $path;continue}
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
        if($transaction.State -eq 'Applied'){
            foreach($step in $transaction.Steps){
                if($step.State -eq 'Unchanged'){continue}
                $current=Read-GoatRegistry $step.Target
                if(-not (Test-GoatStateEqual $current $step.Proposed) -and -not (Test-GoatStateEqual $current $step.Original)){throw 'Estado atual diverge do valor aplicado e do original; revisão manual necessária antes da restauração.'}
            }
        }
        Undo-GoatTransactionInternal $transaction $transaction.JournalPath
        Add-GoatEvent $Session 'Restored' ('Restaurada '+$TransactionId)
        return $transaction
    } finally { if($locked){$mutex.ReleaseMutex()};$mutex.Dispose() }
}
