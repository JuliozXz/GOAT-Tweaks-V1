# GOAT Tweaks v2.2 - mutation engine. Windows PowerShell 5.1 / x64.
# UI and scanner never call a mutation unless the technician requests it.

function Test-GoatAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-GoatStorageRoot {
    if (Test-Path -LiteralPath 'D:\' -PathType Container) { return 'D:\GoatTweaks' }
    return (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'GoatTweaks')
}

function Get-GoatMachineIdentity {
    $machine = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
    return [pscustomobject]@{ MachineGuid = [string]$machine; UserSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value }
}

function Get-GoatRegistryState {
    param([Parameter(Mandatory=$true)][string]$Path, [Parameter(Mandatory=$true)][string]$Name)
    $base = $null; $key = $null
    try {
        if ($Path.StartsWith('HKCU:\')) { $hive = [Microsoft.Win32.RegistryHive]::CurrentUser; $subPath = $Path.Substring(6) }
        elseif ($Path.StartsWith('HKLM:\')) { $hive = [Microsoft.Win32.RegistryHive]::LocalMachine; $subPath = $Path.Substring(6) }
        else { throw "Hive não permitida: $Path" }
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry64)
        $key = $base.OpenSubKey($subPath, $false)
        $keyExists = $null -ne $key
        $exists = $keyExists -and @($key.GetValueNames()) -contains $Name
        $value = $null; $type = 'DWord'
        if ($exists) {
            $type = $key.GetValueKind($Name).ToString()
            $value = $key.GetValue($Name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
        }
        return [pscustomobject]@{ Path=$Path; Name=$Name; Exists=[bool]$exists; KeyExisted=$keyExists; Value=$value; Type=$type }
    } finally { if ($key) { $key.Dispose() }; if ($base) { $base.Dispose() } }
}

function Set-GoatRegistryState {
    param([Parameter(Mandatory=$true)]$State)
    $base = $null; $key = $null
    try {
        if ($State.Path.StartsWith('HKCU:\')) { $hive = [Microsoft.Win32.RegistryHive]::CurrentUser; $subPath = $State.Path.Substring(6) }
        elseif ($State.Path.StartsWith('HKLM:\')) { $hive = [Microsoft.Win32.RegistryHive]::LocalMachine; $subPath = $State.Path.Substring(6) }
        else { throw 'Hive inválida no diário.' }
        $base = [Microsoft.Win32.RegistryKey]::OpenBaseKey($hive, [Microsoft.Win32.RegistryView]::Registry64)
        if ($State.Exists) {
            $kind = [Microsoft.Win32.RegistryValueKind][Enum]::Parse([Microsoft.Win32.RegistryValueKind], [string]$State.Type, $true)
            $value = $State.Value
            switch ([string]$State.Type) {
                'DWord' { $value = [int]$value }
                'QWord' { $value = [long]$value }
                'Binary' { $value = [byte[]]$value }
                'MultiString' { $value = [string[]]$value }
                'String' { $value = [string]$value }
                'ExpandString' { $value = [string]$value }
                default { throw "Tipo de registro não suportado: $($State.Type)" }
            }
            $key = $base.CreateSubKey($subPath)
            $key.SetValue([string]$State.Name, $value, $kind)
        } else {
            $key = $base.OpenSubKey($subPath, $true)
            if ($key) {
                $key.DeleteValue([string]$State.Name, $false)
                $canDelete = (-not $State.KeyExisted) -and $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0
                $key.Dispose(); $key = $null
                if ($canDelete) { $base.DeleteSubKey($subPath, $false) }
            }
        }
    } finally { if ($key) { $key.Dispose() }; if ($base) { $base.Dispose() } }
}

function New-GoatRegistryTarget {
    param([string]$Path, [string]$Name, $Value, [string]$Type = 'DWord')
    return [pscustomobject]@{ Path=$Path; Name=$Name; Exists=$true; KeyExisted=$true; Value=$Value; Type=$Type }
}

function Invoke-GoatNative {
    param([Parameter(Mandatory=$true)][string]$File, [Parameter(Mandatory=$true)][string[]]$Arguments)
    # Only fixed, allowlisted commands use this helper. No Invoke-Expression.
    $output = @(& $File @Arguments 2>&1)
    $code = $LASTEXITCODE
    if ($code -ne 0) { throw "$File retornou $code : $($output -join ' ')" }
    return ($output -join [Environment]::NewLine)
}

function Get-GoatActivePowerScheme {
    $output = Invoke-GoatNative -File "$env:SystemRoot\System32\powercfg.exe" -Arguments @('/getactivescheme')
    $match = [regex]::Match($output, '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    if (-not $match.Success) { throw 'Não foi possível identificar o plano de energia ativo.' }
    return $match.Value.ToLowerInvariant()
}

function Get-GoatTcpAutoTuning {
    $setting = Get-NetTCPSetting -SettingName Internet -ErrorAction Stop
    $value = ([string]$setting.AutoTuningLevelLocal).ToLowerInvariant()
    if ($value -notin @('disabled','highlyrestricted','restricted','normal','experimental')) {
        throw "Auto-tuning não reconhecido: $value"
    }
    return $value
}

function Get-GoatTweaks {
    param([Parameter(Mandatory=$true)]$Scan)
    $list = New-Object System.Collections.Generic.List[object]
    $definitions = @(
        @{ Id='game-mode'; Category='Sistema'; Title='Ativar Modo de Jogo do Windows'; Description='Ativa a preferência do usuário. O efeito depende do jogo e da versão do Windows; não é medição de ganho.'; Risk='Baixo'; Recommended=$true; Restart=$false; Targets=@(
            (New-GoatRegistryTarget 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled' 1),
            (New-GoatRegistryTarget 'HKCU:\Software\Microsoft\GameBar' 'AllowAutoGameMode' 1)) },
        @{ Id='capture-off'; Category='Sistema'; Title='Desativar captura de jogos em segundo plano'; Description='Desliga preferências de captura do usuário. Se o cliente grava clipes pela Xbox Game Bar, mantenha desmarcado.'; Risk='Baixo'; Recommended=$true; Restart=$false; Targets=@(
            (New-GoatRegistryTarget 'HKCU:\Software\Microsoft\Windows\CurrentVersion\GameDVR' 'AppCaptureEnabled' 0),
            (New-GoatRegistryTarget 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled' 0)) },
        @{ Id='visual-effects'; Category='Sistema'; Title='Reduzir efeitos visuais da interface'; Description='Reduz animações de janelas e transparência. Pode melhorar a resposta visual em PCs limitados; sair e entrar na sessão aplica todas as preferências.'; Risk='Baixo'; Recommended=$false; Restart=$true; Targets=@(
            (New-GoatRegistryTarget 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects' 'VisualFXSetting' 2),
            (New-GoatRegistryTarget 'HKCU:\Control Panel\Desktop\WindowMetrics' 'MinAnimate' '0' 'String'),
            (New-GoatRegistryTarget 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' 'EnableTransparency' 0)) },
        @{ Id='mouse-linear'; Category='Sistema'; Title='Desativar aceleração do ponteiro'; Description='Desativa a aceleração do ponteiro do Windows para preferência de entrada linear. Jogos com Raw Input podem ignorar esta configuração. Requer nova sessão.'; Risk='Moderado'; Recommended=$false; Restart=$true; Targets=@(
            (New-GoatRegistryTarget 'HKCU:\Control Panel\Mouse' 'MouseSpeed' '0' 'String'),
            (New-GoatRegistryTarget 'HKCU:\Control Panel\Mouse' 'MouseThreshold1' '0' 'String'),
            (New-GoatRegistryTarget 'HKCU:\Control Panel\Mouse' 'MouseThreshold2' '0' 'String')) },
        @{ Id='background-apps'; Category='Sistema'; Title='Restringir apps UWP em segundo plano'; Description='Define preferência global de atividade em segundo plano para apps compatíveis. Pode afetar notificações. Não desinstala aplicativos.'; Risk='Moderado'; Recommended=$false; Restart=$true; Targets=@(
            (New-GoatRegistryTarget 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' 'GlobalUserDisabled' 1)) }
    )
    foreach ($definition in $definitions) {
        $available = [bool]$Scan.OS.Supported; $reason = ''; $applied = $true
        if (-not $available) { $reason = 'Edição/build do Windows fora da faixa validada (Windows 10/11, build 19041+).' }
        foreach ($target in $definition.Targets) {
            if ($Scan.IsDemo) { $applied = $false; continue }
            try {
                $state = Get-GoatRegistryState -Path $target.Path -Name $target.Name
                if (-not $state.Exists -or $state.Type -ne $target.Type -or [string]$state.Value -ne [string]$target.Value) { $applied = $false }
            } catch { $available = $false; $applied = $false; $reason = $_.Exception.Message }
        }
        $status = 'Disponível'; if ($applied) { $status='Aplicado' }; if (-not $available) { $status='Indisponível' }
        $list.Add([pscustomobject]@{ Id=$definition.Id; Category=$definition.Category; Title=$definition.Title; Description=$definition.Description; Risk=$definition.Risk; Recommended=($definition.Recommended -and -not $applied -and $available); Available=$available; UnavailableReason=$reason; RequiresRestart=$definition.Restart; State=$status; Kind='Registry'; Targets=@($definition.Targets) })
    }
    $powerId = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
    $extras = @(
        @{Id='power-high';Category='CPU';Title='Selecionar plano Alto Desempenho';Description='Usa o plano existente do Windows. Pode aumentar consumo, temperatura e ruído; compare antes/depois. Não altera C-States no firmware.';Kind='Power';Target=$powerId;Restart=$false;Risk='Moderado'},
        @{Id='tcp-normal';Category='Rede';Title='Auto-tuning TCP Internet para Normal';Description='Define Normal apenas no perfil TCP Internet, preservando os demais perfis. Afeta throughput, sem promessa de redução de ping. Não substitui diagnóstico de rede.';Kind='Tcp';Target='normal';Restart=$false;Risk='Moderado'},
        @{Id='rss-on';Category='Rede';Title='Habilitar RSS global';Description='Permite distribuir processamento de recepção em NICs compatíveis. Mantém offloads de checksum e LSO. Não altera propriedades específicas do fabricante.';Kind='Rss';Target='Enabled';Restart=$false;Risk='Moderado'}
    )
    foreach ($definition in $extras) {
        $available = [bool]$Scan.OS.Supported; $reason=''; $applied=$false
        if (-not $available) { $reason='Windows não suportado.' }
        if (-not $Scan.IsDemo -and $available) {
            try {
                switch ($definition.Kind) {
                    'Power' {
                        $plans = Invoke-GoatNative "$env:SystemRoot\System32\powercfg.exe" @('/list')
                        if ($plans -notmatch $powerId) { $available=$false; $reason='Plano não oferecido por este computador (comum em Modern Standby). Nenhum plano será criado.' }
                        $applied = (Get-GoatActivePowerScheme) -eq $powerId
                    }
                    'Tcp' { $applied = (Get-GoatTcpAutoTuning) -eq 'normal' }
                    'Rss' { $applied = ([string](Get-NetOffloadGlobalSetting -ErrorAction Stop).ReceiveSideScaling) -eq 'Enabled' }
                }
            } catch { $available=$false; $reason=$_.Exception.Message }
        }
        $status='Disponível'; if ($applied) {$status='Aplicado'}; if (-not $available) {$status='Indisponível'}
        $list.Add([pscustomobject]@{Id=$definition.Id;Category=$definition.Category;Title=$definition.Title;Description=$definition.Description;Risk=$definition.Risk;Recommended=$false;Available=$available;UnavailableReason=$reason;RequiresRestart=$definition.Restart;State=$status;Kind=$definition.Kind;Target=$definition.Target;Targets=@()})
    }
    return $list.ToArray()
}

function Write-GoatJournal {
    param($Journal, [string]$Path)
    $temporary = "$Path.tmp"
    $json = $Journal | ConvertTo-Json -Depth 16
    $bytes = (New-Object Text.UTF8Encoding($true)).GetBytes($json)
    $stream = New-Object IO.FileStream($temporary, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($bytes,0,$bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
    if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,"$Path.previous",$true) }
    else { [IO.File]::Move($temporary,$Path) }
}

function Write-GoatLog {
    param([string]$Path, [string]$Message, [string]$Level='INFO')
    $line = '{0} [{1}] {2}' -f ([DateTime]::UtcNow.ToString('o')), $Level, $Message
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8 -ErrorAction Stop
}

function Send-GoatProgress {
    param([scriptblock]$Callback, [string]$Message)
    if ($Callback) { & $Callback $Message | Out-Null }
}

function New-GoatRestorePoint {
    param([string]$TransactionId, [string]$LogPath)
    $description = "GOAT v2.2 $TransactionId"
    $before = @(Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -OperationTimeoutSec 20 -ErrorAction Stop)
    $maxSequence = 0
    foreach ($point in $before) { if ([long]$point.SequenceNumber -gt $maxSequence) { $maxSequence=[long]$point.SequenceNumber } }
    Write-GoatLog $LogPath "COMMAND Checkpoint-Computer -Description '$description' -RestorePointType MODIFY_SETTINGS"
    Checkpoint-Computer -Description $description -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
    $after = @(Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -OperationTimeoutSec 20 -ErrorAction Stop)
    $created = @($after | Where-Object { [long]$_.SequenceNumber -gt $maxSequence -and $_.Description -eq $description })
    if ($created.Count -eq 0) {
        throw 'Nenhum ponto de restauração NOVO foi confirmado. O Windows limita a criação a um a cada 24h. Verifique a Proteção do Sistema; nenhum tweak foi aplicado. A frequência de restauração não será alterada automaticamente.'
    }
    $sequence = [long]($created | Sort-Object SequenceNumber -Descending | Select-Object -First 1).SequenceNumber
    Write-GoatLog $LogPath "RestorePoint confirmado: SequenceNumber=$sequence"
    return $sequence
}

function Get-GoatStepOriginal {
    param($Tweak, $Target)
    switch ($Tweak.Kind) {
        'Registry' {
            $state=Get-GoatRegistryState $Target.Path $Target.Name
            if ($state.Exists -and $state.Type -notin @('DWord','QWord','String','ExpandString','Binary','MultiString')) {
                throw "Tipo original de Registro não reversível: $($state.Type). Nenhum ajuste será iniciado."
            }
            return $state
        }
        'Power' { return (Get-GoatActivePowerScheme) }
        'Tcp' { return (Get-GoatTcpAutoTuning) }
        'Rss' {
            $value = [string](Get-NetOffloadGlobalSetting -ErrorAction Stop).ReceiveSideScaling
            if ($value -notin @('Enabled','Disabled')) { throw "RSS não reconhecido: $value" }
            return $value
        }
        default { throw 'Operação não permitida.' }
    }
}

function Set-GoatStepValue {
    param($Step, $Value, [string]$LogPath)
    switch ($Step.Kind) {
        'Registry' {
            Write-GoatLog $LogPath ('REGISTRY ' + ($Value | ConvertTo-Json -Compress -Depth 6))
            Set-GoatRegistryState $Value
            $actual = Get-GoatRegistryState $Value.Path $Value.Name
            if ([bool]$actual.Exists -ne [bool]$Value.Exists) { throw "Falha de verificação: $($Value.Path)\$($Value.Name)" }
            if ($Value.Exists) {
                $expectedJson = ConvertTo-Json -InputObject $Value.Value -Compress
                $actualJson = ConvertTo-Json -InputObject $actual.Value -Compress
                if ($actual.Type -ne $Value.Type -or $actualJson -ne $expectedJson) { throw "Valor não confirmado: $($Value.Path)\$($Value.Name)" }
            }
        }
        'Power' {
            if ([string]$Value -notmatch '^[0-9a-fA-F-]{36}$') { throw 'GUID de energia inválido.' }
            Write-GoatLog $LogPath "COMMAND powercfg.exe /setactive $Value"
            Invoke-GoatNative "$env:SystemRoot\System32\powercfg.exe" @('/setactive',[string]$Value) | Out-Null
            if ((Get-GoatActivePowerScheme) -ne [string]$Value) { throw 'Plano de energia não confirmado.' }
        }
        'Tcp' {
            if ([string]$Value -notin @('disabled','highlyrestricted','restricted','normal','experimental')) { throw 'Auto-tuning inválido.' }
            Write-GoatLog $LogPath "COMMAND Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal $Value"
            Set-NetTCPSetting -SettingName Internet -AutoTuningLevelLocal ([string]$Value) -ErrorAction Stop | Out-Null
            if ((Get-GoatTcpAutoTuning) -ne [string]$Value) { throw 'TCP auto-tuning não confirmado.' }
        }
        'Rss' {
            if ([string]$Value -notin @('Enabled','Disabled')) { throw 'RSS inválido.' }
            Write-GoatLog $LogPath "COMMAND Set-NetOffloadGlobalSetting -ReceiveSideScaling $Value"
            Set-NetOffloadGlobalSetting -ReceiveSideScaling ([string]$Value) -ErrorAction Stop | Out-Null
            if ([string](Get-NetOffloadGlobalSetting -ErrorAction Stop).ReceiveSideScaling -ne [string]$Value) { throw 'RSS não confirmado.' }
        }
        default { throw 'Tipo de operação inválido.' }
    }
}

function New-GoatResult {
    param([bool]$Success, [string]$Message, [string]$TransactionId='', [string]$LogPath='')
    return [pscustomobject]@{Success=$Success;Message=$Message;TransactionId=$TransactionId;LogPath=$LogPath}
}

function Invoke-GoatApply {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string[]]$Ids, [Parameter(Mandatory=$true)]$Scan, [switch]$Demo, [scriptblock]$ProgressCallback)
    if ($Demo -or $Scan.IsDemo) { return New-GoatResult $true "DEMONSTRAÇÃO: $($Ids.Count) opções simuladas. Nenhuma configuração foi alterada." }
    $mutex=$null; $locked=$false; $journal=$null; $journalPath=''; $logPath=''; $transactionId=''
    try {
        if (-not (Test-GoatAdministrator)) { throw 'Abra o aplicativo como administrador para aplicar alterações. O diagnóstico funciona sem elevação.' }
        if (-not [Environment]::Is64BitProcess) { throw 'Use o Windows PowerShell de 64 bits.' }
        if (-not $Scan.OS.Supported) { throw 'Windows não suportado para alterações.' }
        $mutex = New-Object System.Threading.Mutex($false, 'Global\GOAT-Tweaks-v2.2-Mutation')
        try { $locked=$mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $locked=$true }
        if (-not $locked) { throw 'Outra sessão GOAT está aplicando ou restaurando configurações.' }
        $catalog = @(Get-GoatTweaks -Scan $Scan)
        $selected = New-Object System.Collections.Generic.List[object]
        foreach ($id in @($Ids | Select-Object -Unique)) {
            $entry = @($catalog | Where-Object { $_.Id -eq $id })
            if ($entry.Count -ne 1) { throw "Opção desconhecida: $id" }
            if (-not $entry[0].Available) { throw "$($entry[0].Title): $($entry[0].UnavailableReason)" }
            if ($entry[0].State -ne 'Aplicado') { $selected.Add($entry[0]) }
        }
        if ($selected.Count -eq 0) { return New-GoatResult $true 'As opções selecionadas já estão aplicadas ou a seleção está vazia.' }
        $root = Get-GoatStorageRoot
        foreach ($folder in @('logs','backups')) { [IO.Directory]::CreateDirectory((Join-Path $root $folder)) | Out-Null }
        # Refuse a new batch while an interrupted/failed undo still needs recovery.
        foreach ($existing in @(Get-ChildItem -LiteralPath (Join-Path $root 'backups') -Filter '*.json' -File -ErrorAction Stop)) {
            $old = Get-Content -LiteralPath $existing.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($old.Status -in @('Applying','Restoring','RollbackIncomplete')) { throw "Há uma transação pendente ($($old.Id)). Restaure antes de iniciar outro lote." }
        }
        $transactionId = ([DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')) + '-' + [Guid]::NewGuid().ToString('N').Substring(0,8)
        $logPath = Join-Path $root "logs\$transactionId.log"
        $journalPath = Join-Path $root "backups\$transactionId.json"
        $identity = Get-GoatMachineIdentity
        $journal = [pscustomobject]@{SchemaVersion=1;Id=$transactionId;CreatedUtc=[DateTime]::UtcNow.ToString('o');MachineGuid=$identity.MachineGuid;UserSid=$identity.UserSid;Status='Prepared';RestorePoint=$null;Steps=@()}
        Write-GoatLog $logPath "BEGIN $transactionId; requested=$($Ids -join ',')"
        # Capture ALL originals before any system write. Write-ahead journal is durable.
        foreach ($tweak in $selected) {
            $targets = @($tweak.Targets)
            if ($tweak.Kind -ne 'Registry') { $targets=@($tweak.Target) }
            foreach ($target in $targets) {
                $original = Get-GoatStepOriginal $tweak $target
                $journal.Steps += [pscustomobject]@{Id=$tweak.Id;Kind=$tweak.Kind;Original=$original;Target=$target;Status='Prepared'}
            }
        }
        Write-GoatJournal $journal $journalPath
        Send-GoatProgress $ProgressCallback 'Criando e verificando ponto de restauração...'
        $journal.RestorePoint = New-GoatRestorePoint $transactionId $logPath
        $journal.Status='Applying'; Write-GoatJournal $journal $journalPath
        foreach ($step in $journal.Steps) {
            # In-flight persisted BEFORE mutation, so interrupted writes are recoverable.
            $step.Status='Applying'; Write-GoatJournal $journal $journalPath
            Send-GoatProgress $ProgressCallback "Aplicando $($step.Id)..."
            Set-GoatStepValue $step $step.Target $logPath
            $step.Status='Applied'; Write-GoatJournal $journal $journalPath
        }
        $journal.Status='Applied'; Write-GoatJournal $journal $journalPath
        Write-GoatLog $logPath 'COMMIT - todas as alterações foram verificadas.'
        $needsRestart = @($selected | Where-Object RequiresRestart).Count -gt 0
        $message = "$($selected.Count) opções aplicadas e verificadas. Configuração anterior salva para restauração."
        if ($needsRestart) { $message += ' Algumas preferências exigem reinício ou nova sessão.' }
        return New-GoatResult $true $message $transactionId $logPath
    } catch {
        $failure = $_.Exception.Message; $rollbackErrors = @()
        if ($journal -and @($journal.Steps | Where-Object { $_.Status -in @('Applying','Applied') }).Count -gt 0) {
            $reverse = @($journal.Steps); [Array]::Reverse($reverse)
            foreach ($step in $reverse) {
                if ($step.Status -in @('Applying','Applied')) {
                    try { Set-GoatStepValue $step $step.Original $logPath; $step.Status='RolledBack' }
                    catch { $rollbackErrors += $_.Exception.Message }
                }
            }
            $journal.Status='Failed'; if ($rollbackErrors.Count -gt 0) { $journal.Status='RollbackIncomplete' }
        } elseif ($journal) { $journal.Status='Failed' }
        if ($journalPath -and $journal) { try { Write-GoatJournal $journal $journalPath } catch { $rollbackErrors += "Falha ao salvar diário: $($_.Exception.Message)" } }
        if ($logPath) { try { Write-GoatLog $logPath "FAILED $failure; rollback=$($rollbackErrors -join '; ')" 'ERROR' } catch {} }
        if ($rollbackErrors.Count -gt 0) { $failure += " Reversão incompleta: $($rollbackErrors -join '; '). Preserve o backup e verifique o log." }
        return New-GoatResult $false $failure $transactionId $logPath
    } finally { if ($locked -and $mutex) { $mutex.ReleaseMutex() }; if ($mutex) { $mutex.Dispose() } }
}

function Assert-GoatJournal {
    param($Journal)
    if ($Journal.SchemaVersion -ne 1) { throw 'Formato de backup desconhecido.' }
    $identity = Get-GoatMachineIdentity
    if ($Journal.MachineGuid -ne $identity.MachineGuid -or $Journal.UserSid -ne $identity.UserSid) { throw 'Este backup pertence a outro Windows ou outro usuário. Use a mesma identidade da aplicação original.' }
    $dummyScan = [pscustomobject]@{ IsDemo=$true; OS=[pscustomobject]@{Supported=$true} }
    $catalog = @(Get-GoatTweaks -Scan $dummyScan)
    foreach ($step in @($Journal.Steps)) {
        $allowed = @($catalog | Where-Object { $_.Id -eq $step.Id -and $_.Kind -eq $step.Kind })
        if ($allowed.Count -ne 1) { throw 'Operação desconhecida no backup.' }
        if ($step.Kind -eq 'Registry') {
            $match = @($allowed[0].Targets | Where-Object { $_.Path -eq $step.Original.Path -and $_.Name -eq $step.Original.Name })
            if ($match.Count -ne 1) { throw 'Chave fora da lista permitida no backup.' }
        }
    }
}

function Restore-GoatLastTransaction {
    [CmdletBinding()]
    param([switch]$Demo, [scriptblock]$ProgressCallback)
    if ($Demo) { return New-GoatResult $true 'DEMONSTRAÇÃO: restauração simulada. Nenhuma configuração foi alterada.' }
    $mutex=$null; $locked=$false; $logPath=''; $journal=$null; $journalPath=''
    try {
        if (-not (Test-GoatAdministrator)) { throw 'Abra como administrador para restaurar.' }
        if (-not [Environment]::Is64BitProcess) { throw 'Use o Windows PowerShell de 64 bits.' }
        $mutex=New-Object System.Threading.Mutex($false,'Global\GOAT-Tweaks-v2.2-Mutation')
        try { $locked=$mutex.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $locked=$true }
        if (-not $locked) { throw 'Outra sessão GOAT está trabalhando.' }
        $root=Get-GoatStorageRoot
        $backupRoot=Join-Path $root 'backups'
        if (-not (Test-Path -LiteralPath $backupRoot)) { throw 'Nenhum backup encontrado neste computador.' }
        $identity=Get-GoatMachineIdentity
        foreach ($file in @(Get-ChildItem -LiteralPath $backupRoot -Filter '*.json' -File | Sort-Object Name -Descending)) {
            $candidate=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
            if ($candidate.MachineGuid -eq $identity.MachineGuid -and $candidate.UserSid -eq $identity.UserSid -and $candidate.Status -in @('Applied','Applying','Restoring','RollbackIncomplete')) { $journal=$candidate; $journalPath=$file.FullName; break }
        }
        if (-not $journal) { throw 'Nenhuma transação aplicada ou interrompida para restaurar neste Windows/usuário.' }
        Assert-GoatJournal $journal
        $logPath=Join-Path $root "logs\$($journal.Id)-restore.log"
        Write-GoatLog $logPath "RESTORE BEGIN $($journal.Id)"
        # The original verified restore point protects this same transaction and its undo.
        # Reuse it to keep recovery available inside Windows' 24-hour creation limit.
        $points=@(Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -OperationTimeoutSec 20 -ErrorAction Stop)
        $protected=@($points | Where-Object { [long]$_.SequenceNumber -eq [long]$journal.RestorePoint -and $_.Description -eq "GOAT v2.2 $($journal.Id)" })
        if ($protected.Count -eq 0) {
            Send-GoatProgress $ProgressCallback 'Verificando novo ponto de proteção para a restauração...'
            $journal.RestorePoint=New-GoatRestorePoint $journal.Id $logPath
        }
        $journal.Status='Restoring'; Write-GoatJournal $journal $journalPath
        $reverse=@($journal.Steps); [Array]::Reverse($reverse)
        $errors=@(); $restored=0
        foreach ($step in $reverse) {
            if ($step.Status -in @('Applied','Applying','Restoring')) {
                try {
                    $step.Status='Restoring'; Write-GoatJournal $journal $journalPath
                    Send-GoatProgress $ProgressCallback "Restaurando $($step.Id)..."
                    Set-GoatStepValue $step $step.Original $logPath
                    $step.Status='Restored'; $restored++
                    Write-GoatJournal $journal $journalPath
                } catch { $errors += $_.Exception.Message }
            }
        }
        if ($errors.Count -gt 0) { $journal.Status='RollbackIncomplete'; Write-GoatJournal $journal $journalPath; throw ($errors -join '; ') }
        $journal.Status='Restored'; Write-GoatJournal $journal $journalPath
        Write-GoatLog $logPath 'RESTORE COMMIT'
        return New-GoatResult $true "Configuração anterior restaurada ($restored valores/ações). Reinicie ou entre novamente na sessão para concluir preferências visuais." $journal.Id $logPath
    } catch {
        $message=$_.Exception.Message
        if ($logPath) { try { Write-GoatLog $logPath $message 'ERROR' } catch {} }
        $id=''; if ($journal) {$id=$journal.Id}
        return New-GoatResult $false $message $id $logPath
    } finally { if ($locked -and $mutex) {$mutex.ReleaseMutex()}; if ($mutex) {$mutex.Dispose()} }
}
