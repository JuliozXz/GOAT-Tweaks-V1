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
    # Hard-coded native allow-list. No catalog or document text creates executors.
    $folderSource='https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/3c837e92-016e-4148-86e5-b4f0381a757f'
    $commonSource='https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-common#personalization---colors'
    $gamingSource='https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11#gaming-game-bar-game-mode-gaming-shortcuts'
    $explorerSource='https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-windowsexplorer'
    $advanced='Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced'
    $personalize='Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
    $specs=@(
        @{Id='explorer-show-extensions';Title='Mostrar extensões de arquivos';Path=$advanced;Name='HideFileExt';On=0;Off=1;Category='Explorer';Description='Preferência de exibição de extensões conhecidas.';Tradeoffs='Ocultar extensões pode dificultar identificar o tipo real do arquivo.';Sources=@($folderSource)},
        @{Id='explorer-show-hidden';Title='Mostrar arquivos ocultos';Path=$advanced;Name='Hidden';On=1;Off=2;Category='Explorer';Description='Exibe arquivos marcados como ocultos sem alterar a proteção de arquivos do sistema.';Tradeoffs='Aparecerão mais arquivos e pastas; não exclua itens desconhecidos.';Sources=@($folderSource)},
        @{Id='explorer-show-infotips';Title='Mostrar descrições no Explorer';Path=$advanced;Name='ShowInfoTip';On=1;Off=0;Category='Explorer';Description='Preferência para dicas textuais de arquivos e pastas.';Tradeoffs='Dicas podem ocupar a área sob o ponteiro; benefício de FPS não medido.';Sources=@($folderSource)},
        @{Id='explorer-color-compressed';Title='Destacar arquivos compactados ou criptografados';Path=$advanced;Name='ShowCompColor';On=1;Off=0;Category='Explorer';Description='Preferência visual para distinguir atributos NTFS por cor.';Tradeoffs='Pode conflitar com a preferência visual ou percepção de cores do cliente.';Sources=@($folderSource)},
        @{Id='explorer-folder-size-tips';Title='Informações de tamanho nas dicas de pastas';Path=$advanced;Name='FolderContentsInfoTip';On=1;Off=0;Category='Explorer';Description='Preferência de detalhes nas dicas de pastas.';Tradeoffs='A coleta de tamanho pode custar tempo em pastas grandes ou remotas.';Sources=@($folderSource)},
        @{Id='explorer-full-title-path';Title='Caminho completo no título do Explorer';Path='Software\Microsoft\Windows\CurrentVersion\Explorer\CabinetState';Name='FullPath';On=1;Off=0;Category='Explorer';Description='Preferência para identificar a pasta pelo caminho no título.';Tradeoffs='O caminho pessoal pode ficar visível em compartilhamento de tela.';Sources=@($folderSource)},
        @{Id='explorer-separate-process';Title='Janelas de pastas em processo separado';Path=$advanced;Name='SeparateProcess';On=1;Off=0;Category='Explorer';Description='Preferência de isolamento das janelas do Explorer.';Tradeoffs='Pode aumentar uso de memória; requer reabrir janelas para avaliar. O app não encerra o Explorer.';ExecutionClass='B_APPROVAL';RequiresIndividualApproval=$true;BlockRemote=$true;Sources=@($folderSource)},
        @{Id='ui-transparency';Title='Efeitos de transparência';Path=$personalize;Name='EnableTransparency';On=1;Off=0;Category='Interface';Description='Persiste a preferência de transparência das superfícies do Windows.';Tradeoffs='Troca estética e legibilidade; não comprova redução de carga ou ganho em jogos.';CatalogIds=@('WIN-TRANSPARENCY');Sources=@($commonSource)},
        @{Id='ui-apps-light-theme';Title='Tema claro dos aplicativos';Path=$personalize;Name='AppsUseLightTheme';On=1;Off=0;Category='Interface';Description='Escolhe a preferência claro/escuro dos aplicativos compatíveis.';Tradeoffs='Aplicativos podem ignorar o tema; confirmar conforto e acessibilidade com o cliente.';Sources=@($commonSource)},
        @{Id='ui-system-light-theme';Title='Tema claro do Windows';Path=$personalize;Name='SystemUsesLightTheme';On=1;Off=0;Category='Interface';Description='Escolhe a preferência claro/escuro do shell.';Tradeoffs='Pode mudar contraste percebido. Nenhum aplicativo é reiniciado automaticamente.';Sources=@($commonSource)},
        @{Id='ui-titlebar-accent';Title='Cor de destaque nas bordas e títulos';Path='Software\Microsoft\Windows\DWM';Name='ColorPrevalence';On=1;Off=0;Category='Interface';Description='Preferência visual de cor em títulos e bordas de janelas.';Tradeoffs='Nem todas as janelas usam essa preferência; não mede desempenho.';Sources=@($commonSource)},
        @{Id='ui-auto-accent';Title='Escolher cor de destaque automaticamente';Path='Control Panel\Desktop';Name='AutoColorization';On=1;Off=0;Category='Interface';Description='Preferência de escolha automática da cor a partir do fundo.';Tradeoffs='Não muda o papel de parede; efeito visual depende do tema.';Sources=@($commonSource)},
        @{Id='gaming-game-mode';Title='Preferência de Modo de Jogo';Path='Software\Microsoft\GameBar';Name='AutoGameModeEnabled';On=1;Off=0;Category='Jogos';Description='Persiste a preferência de Modo de Jogo documentada para Windows 11.';Tradeoffs='Não prova que o jogo está usando otimizações nem promete FPS. Testar uma variável por vez.';MinBuild=22000;ExecutionClass='B_APPROVAL';RequiresIndividualApproval=$true;CatalogIds=@('WIN-GAMEMODE','WIN-GAME-MODE','WIN-001');Sources=@($gamingSource)},
        @{Id='gaming-controller-gamebar';Title='Permitir abrir Game Bar pelo controle';Path='Software\Microsoft\GameBar';Name='UseNexusForGameBarEnabled';On=1;Off=0;Category='Jogos';Description='Preferência do botão do controle para abrir Game Bar, conforme Windows 11.';Tradeoffs='Desativar este atalho não desinstala Game Bar nem desativa todos os tipos de captura.';MinBuild=22000;ExecutionClass='B_APPROVAL';RequiresIndividualApproval=$true;Sources=@($gamingSource)},
        @{Id='capture-recording-policy';Title='Permitir gravação e transmissão do Windows (política Win10)';Hive='LocalMachine';Path='Software\Policies\Microsoft\Windows\GameDVR';Name='AllowGameDVR';On=1;Off=0;Category='Captura';Description='Configura a política de permissão da gravação do Windows em Windows 10 desktop suportado.';Tradeoffs='Desativar pode interromper gravação/transmissão desejadas. A Microsoft não garante aplicação desta política no Windows 11. Não desinstala componentes.';RequiresAdmin=$true;MinBuild=19041;MaxBuild=19045;SupportedEditions=@('Professional','ProfessionalN','ProfessionalEducation','ProfessionalWorkstation','Enterprise','EnterpriseS','Education','IoTEnterprise','IoTEnterpriseS');BlockWhenManaged=$true;BlockRemote=$true;ExecutionClass='B_APPROVAL';RequiresIndividualApproval=$true;CatalogIds=@('WIN-CAPTURE','WIN-002','APP-XBOX-CAPTURE-BACKGROUND');Sources=@('https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-applicationmanagement#allowgamedvr')},
        @{Id='explorer-confirm-delete';Title='Confirmar envio de arquivos à Lixeira';Path='Software\Microsoft\Windows\CurrentVersion\Policies\Explorer';Name='ConfirmFileDelete';On=1;Off=0;Category='Explorer';Description='Política para confirmar exclusões enviadas à Lixeira; não remove nenhum arquivo.';Tradeoffs='A política pode limitar a escolha pela interface. Não altera a exclusão permanente nem recupera arquivos já apagados.';MinBuild=22000;SupportedEditions=@('Professional','ProfessionalN','ProfessionalEducation','ProfessionalWorkstation','Enterprise','EnterpriseS','Education','IoTEnterprise','IoTEnterpriseS');BlockWhenManaged=$true;ExecutionClass='B_APPROVAL';RequiresIndividualApproval=$true;Sources=@($explorerSource+'#confirmfiledelete')}
    )
    foreach($spec in $specs){
        $action=[ordered]@{Id=$spec.Id;Version=1;Title=$spec.Title;Description=$spec.Description;Category=$spec.Category;Hive='CurrentUser';View='Registry64';Path=$spec.Path;Name=$spec.Name;Kind='DWord';On=$spec.On;Off=$spec.Off;Risk='Baixo / preferência';RiskClass='Low';risk_class='Low';Effects='Preferência persistida; estado efetivo requer conferir a interface do Windows.';Tradeoffs=$spec.Tradeoffs;Benefit='Preferência funcional/visual; ganho de FPS não medido.';RequiresAdmin=$false;RequiresReboot=$null;Reboot=$false;Activation='Pode exigir nova sessão ou reabrir a interface; nunca há reinício automático.';ExecutionClass='A_AUTO_SAFE';RequiresIndividualApproval=$false;BlockRemote=$false;BlockWhenManaged=$false;MinBuild=19041;MaxBuild=0;SupportedEditions=@();CatalogIds=@();Sources=$spec.Sources;ExecutorKind='RegistryValue';Status='IMPLEMENTED_AND_TESTED';ReleaseEnabled=$true;Released=$true;ValidationScope='PS5.1: aplicação, read-back, falhas e restauração com fixtures; API real de Registro somente em chave HKCU descartável. Efeito nas preferências e desempenho em hardware não certificado.';Verification='Read-back exato de presença/tipo/dados no Registro; estado efetivo do Windows permanece não confirmado.';Rollback='Restaurar presença, tipo e dados capturados; não remover a chave pai.'}
        foreach($key in $spec.Keys){$action[$key]=$spec[$key]}
        if($action.ExecutionClass -eq 'B_APPROVAL'){$action.Risk='Moderado / mudança com trade-off';$action.RiskClass='Medium';$action.risk_class='Medium'}
        [pscustomobject]$action
    }
    [pscustomobject]@{Id='ui-taskbar-animations-guide';Version=1;Title='Animações da barra de tarefas — guia';Description='Consultar Acessibilidade > Efeitos visuais e conferir o controle disponível no Windows.';Category='Interface';Hive=$null;View=$null;Path=$null;Name=$null;Kind=$null;On=$null;Off=$null;Risk='Preferência visual / procedimento manual';RiskClass='Low';risk_class='Low';Effects='Nenhuma escrita pelo app.';Tradeoffs='Não foi confirmada uma API pública de escrita ou contrato atual para TaskbarAnimations.';Benefit='Conforto visual; FPS não medido.';RequiresAdmin=$false;RequiresReboot=$null;Reboot=$false;ExecutionClass='C_MANUAL';RequiresIndividualApproval=$false;BlockRemote=$false;BlockWhenManaged=$false;MinBuild=19041;MaxBuild=0;SupportedEditions=@();CatalogIds=@('WIN-ANIMATION','WIN-VISUAL-EFFECTS');Sources=@('https://support.microsoft.com/en-us/accessibility/windows/make-it-easier-to-focus-on-tasks');ExecutorKind='ManualGuide';Status='MANUAL_GUIDE';ReleaseEnabled=$false;Released=$false;ValidationScope='Guia consultivo; não é executor nativo.';Verification='Verificação manual em Configurações.';Rollback='Anotar e restaurar o valor original pela interface do Windows.'}
}
function Get-GoatActionContext {
    param($Session)
    $build=$null;$version=$null;$productType=$null;$edition=$null;$managed=$null;$issues=@()
    try{$os=Get-CimInstance -ClassName Win32_OperatingSystem -OperationTimeoutSec 6 -ErrorAction Stop;$build=[int]$os.BuildNumber;$version=[version]$os.Version;$productType=[int]$os.ProductType}catch{$issues+='Windows/build indisponível: '+$_.Exception.Message}
    try{$edition=[Microsoft.Win32.Registry]::GetValue('HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows NT\CurrentVersion','EditionID',$null)}catch{$issues+='Edição indisponível.'}
    try{$computer=Get-CimInstance -ClassName Win32_ComputerSystem -OperationTimeoutSec 6 -ErrorAction Stop;$managed=[bool]$computer.PartOfDomain;$base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::LocalMachine,[Microsoft.Win32.RegistryView]::Registry64);try{$mdm=$base.OpenSubKey('SOFTWARE\Microsoft\Provisioning\OMADM\Accounts',$false);if($mdm){try{if($mdm.SubKeyCount -gt 0){$managed=$true}}finally{$mdm.Dispose()}}}finally{$base.Dispose()}}catch{$managed=$null;$issues+='Gerenciamento corporativo não confirmado.'}
    $admin=$false;try{$admin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}catch{$issues+='Elevação não confirmada.'}
    $remote='UNKNOWN'
    if($Session.Mode -eq 'Remoto'){$remote='REMOTE_OR_POSSIBLE_REMOTE'}elseif(Get-Command Get-GoatGpuRemoteContext -ErrorAction SilentlyContinue){$remote=[string](Get-GoatGpuRemoteContext).State}elseif($env:SESSIONNAME -eq 'Console'){$remote='LOCAL_CONSOLE'}
    [pscustomobject]@{Build=$build;WindowsMajor=$(if($version){$version.Major}else{$null});ProductType=$productType;Architecture=$env:PROCESSOR_ARCHITECTURE;Is64BitProcess=[Environment]::Is64BitProcess;Edition=[string]$edition;IsAdmin=$admin;Managed=$managed;RemoteState=$remote;Source='Win32_OperatingSystem + Win32_ComputerSystem + Windows registry + token';Issues=$issues}
}
function Get-GoatActionEligibility {
    param($Action,$Context,[switch]$Demo)
    $reasons=New-Object 'System.Collections.Generic.List[string]'
    if($Action.ExecutorKind -ne 'RegistryValue'){$reasons.Add('Procedimento manual sem executor de Registro.')}
    if(-not $Action.ReleaseEnabled -or $Action.Status -ne 'IMPLEMENTED_AND_TESTED'){$reasons.Add('Executor sem liberação de código/testes.')}
    if(-not $Demo){
        if($Context.WindowsMajor -ne 10 -or $Context.ProductType -ne 1 -or $Context.Build -lt $Action.MinBuild -or ($Action.MaxBuild -gt 0 -and $Context.Build -gt $Action.MaxBuild)){$reasons.Add('Windows cliente/build fora do escopo documentado ou desconhecido.')}
        if(-not $Context.Is64BitProcess -or $Context.Architecture -ne 'AMD64'){$reasons.Add('Aplicação real requer Windows/PowerShell x64.')}
        if($Action.RequiresAdmin -and -not $Context.IsAdmin){$reasons.Add('Requer processo elevado na conta apropriada.')}
        if(@($Action.SupportedEditions).Count -gt 0 -and $Context.Edition -notin $Action.SupportedEditions){$reasons.Add('Edição não suportada por esta política ou não confirmada.')}
        if($Action.BlockWhenManaged -and $Context.Managed -ne $false){$reasons.Add('Política em máquina gerenciada ou gerenciamento desconhecido: usar administração responsável.')}
        if($Action.BlockRemote -and $Context.RemoteState -ne 'LOCAL_CONSOLE'){$reasons.Add('Mudança bloqueada durante acesso remoto ou contexto não confirmado.')}
    }
    [pscustomobject]@{Eligible=($reasons.Count -eq 0);Reasons=@($reasons.ToArray());Scope='REGISTRY_PREFERENCE_ONLY';EffectiveState='UNKNOWN';PerformanceGain='NOT_MEASURED';Context=$Context}
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
                Binary { ,([byte[]]@($State.Data)) }; MultiString { ,([string[]]@($State.Data)) }
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
    if(-not $InspectOnly -and @($Ids).Count -gt 7){throw 'O lote revisável permite no máximo sete ações.'}
    $context=if($Session.Demo){[pscustomobject]@{Source='DEMO';RemoteState='DEMO'}}else{Get-GoatActionContext $Session}
    foreach ($id in $Ids) {
        $action=@(Get-GoatActions | Where-Object Id -eq $id)
        if ($action.Count -ne 1) { throw ('Ação desconhecida: '+$id) }
        $action=$action[0]
        $eligibility=Get-GoatActionEligibility $action $context -Demo:$Session.Demo
        $allowed=[bool]$eligibility.Eligible
        if (-not $allowed -and -not $InspectOnly) { throw ('Ação não elegível: '+($eligibility.Reasons -join '; ')) }
        $before=$null;$proposed=$null;$changed=$false
        if($action.ExecutorKind -eq 'RegistryValue'){
            $before=if($Session.Demo){[pscustomobject]@{KeyExists=$true;Exists=$false;Kind=$null;Data=$null}}else{Read-GoatRegistry $action}
            $kind=if($action.Kind){[string]$action.Kind}else{'DWord'}
            $proposed=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind=$kind;Data=$action.$Direction}
            $changed=-not (Test-GoatStateEqual $before $proposed)
        }
        [pscustomobject]@{SessionId=$Session.Id;Id=$id;Action=$action;Before=$before;Proposed=$proposed;Direction=$Direction;Changed=$changed;ExecutionAllowed=$allowed;Eligibility=$eligibility;EffectiveState='UNKNOWN';Note=$(if($allowed){'Revise a mudança e seus trade-offs. Read-back confirma somente o valor persistido, não efeito visual nem FPS.'}else{'Somente leitura: '+($eligibility.Reasons -join '; ')} )}
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
        if ($allowed.Count -ne 1 -or $allowed[0].ExecutorKind -ne 'RegistryValue') { throw 'Diário contém ação não autorizada.' }
        foreach ($field in @('Hive','View','Path','Name')) {
            if ([string]$allowed[0].$field -cne [string]$step.Target.$field) { throw 'Alvo do diário diverge do executor.' }
        }
        if($step.State -notin @('Prepared','Applying','Applied','Restoring','Restored','RestoreFailed','Unchanged')){throw 'Estado de etapa desconhecido.'}
        Assert-GoatRegistrySnapshot $step.Original;Assert-GoatRegistrySnapshot $step.Proposed
        $kind=if($allowed[0].Kind){[string]$allowed[0].Kind}else{'DWord'}
        $onState=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind=$kind;Data=$allowed[0].On};$offState=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind=$kind;Data=$allowed[0].Off}
        if(-not (Test-GoatStateEqual $step.Proposed $onState) -and -not (Test-GoatStateEqual $step.Proposed $offState)){throw 'Pós-condição não pertence ao executor autorizado.'}
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
                # An apply denied before its first write may already equal the
                # original. Verify that fact instead of forcing another write.
                if(-not (Test-GoatStateEqual (Read-GoatRegistry $step.Target) $step.Original)){Write-GoatRegistry $step.Target $step.Original}
                if (-not (Test-GoatStateEqual (Read-GoatRegistry $step.Target) $step.Original)) { throw 'Leitura após reversão divergiu.' }
                $step.State='Restored'; $step.Error=$null; Write-GoatJson $Transaction $Path
            } catch { $step.State='RestoreFailed';$step.Error=$_.Exception.Message;$failures+=$_.Exception.Message;Write-GoatJson $Transaction $Path }
        }
    }
    $Transaction.State=if($failures.Count){'RestoreFailed'}else{'Restored'}
    Write-GoatJson $Transaction $Path
    if ($failures.Count) { throw ('Reversão incompleta. Preserve diário: '+($failures -join '; ')) }
}
function Assert-GoatBatchApproval {
    param([object[]]$Preview,[string[]]$ApprovedActionIds)
    foreach($item in $Preview){
        if($item.Action.ExecutionClass -eq 'B_APPROVAL' -and $item.Id -notin $ApprovedActionIds){throw ('Aprovação individual da mudança necessária: '+$item.Id)}
        if($item.Action.RequiresIndividualApproval -and $Preview.Count -ne 1){throw 'Esta mudança requer execução individual; remova os demais itens do lote.'}
    }
}
function Invoke-GoatActionBatch {
    param($Session,[string[]]$Ids,[ValidateSet('On','Off')][string]$Direction='On',[switch]$Consent,[string[]]$ApprovedActionIds=@(),[object[]]$ReviewedPreview=@())
    if (-not $Consent) { throw 'Consentimento contextual necessário após revisar a prévia.' }
    if ($Session.Demo) {
        $preview=@(Get-GoatActionPreview $Session $Ids $Direction);Assert-GoatBatchApproval $preview $ApprovedActionIds
        if($ReviewedPreview.Count -gt 0 -and @($ReviewedPreview|Where-Object SessionId -cne $Session.Id).Count){throw 'A prévia pertence a outra sessão.'}
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
        if(Get-Command Get-GoatPowerPendingTransactions -ErrorAction SilentlyContinue){
            if(@(Get-GoatPowerPendingTransactions -Session $Session -Identity $identity).Count){throw 'Recupere a transação de energia interrompida antes de aplicar preferências de Registro.'}
        }
        # Re-read under the resource lock. The preview does not authorize stale state.
        $preview=@(Get-GoatActionPreview $Session $Ids $Direction)
        Assert-GoatBatchApproval $preview $ApprovedActionIds
        if($ReviewedPreview.Count -gt 0){
            if($ReviewedPreview.Count -ne $preview.Count){throw 'A seleção diverge da prévia revisada. Gere outra prévia.'}
            for($index=0;$index -lt $preview.Count;$index++){
                $reviewed=$ReviewedPreview[$index];$current=$preview[$index]
                if($reviewed.SessionId -cne $Session.Id -or $reviewed.Id -cne $current.Id -or $reviewed.Direction -cne $current.Direction -or -not $reviewed.ExecutionAllowed -or -not (Test-GoatStateEqual $reviewed.Before $current.Before) -or -not (Test-GoatStateEqual $reviewed.Proposed $current.Proposed)){throw 'A sessão ou o estado mudou após a prévia. Nenhuma alteração foi realizada; revise novamente.'}
                foreach($field in @('Hive','View','Path','Name')){if([string]$reviewed.Action.$field -cne [string]$current.Action.$field){throw 'O alvo diverge da prévia revisada.'}}
            }
        }
        $transaction=[pscustomobject]@{SchemaVersion=1;Id=[guid]::NewGuid().ToString('N');Identity=$identity;CreatedUtc=[DateTime]::UtcNow.ToString('o');State='Prepared';Steps=@();Approval=[pscustomobject]@{Consent=$true;ApprovedActionIds=@($ApprovedActionIds);Utc=[DateTime]::UtcNow.ToString('o')}}
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
