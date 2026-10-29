# Existing Windows power schemes only. Windows PowerShell 5.1; Core.ps1 required.
function ConvertTo-GoatPowerGuid {
    param([Parameter(Mandatory=$true)][string]$Value)
    $parsed=[guid]::Empty
    if($Value -notmatch '^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$' -or -not [guid]::TryParse($Value,[ref]$parsed) -or $parsed -eq [guid]::Empty){throw 'Informe o GUID completo de um plano existente.'}
    $parsed.ToString('D').ToLowerInvariant()
}
function Invoke-GoatPowerCfg {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateSet('/list','/getactivescheme','/query','/setactive')][string]$Option,[string]$SchemeGuid,[ValidateRange(1,30)][int]$TimeoutSeconds=10)
    $arguments=$Option
    if($Option -in @('/query','/setactive')){$arguments+=' '+(ConvertTo-GoatPowerGuid $SchemeGuid)}
    elseif($SchemeGuid){throw 'Este comando de leitura nao aceita GUID.'}
    $system=[Environment]::SystemDirectory
    if(-not [Environment]::Is64BitProcess -and [Environment]::Is64BitOperatingSystem){$system=Join-Path (Split-Path $system -Parent) 'Sysnative'}
    $executable=Join-Path $system 'powercfg.exe'
    $process=[Diagnostics.Process]::new()
    $process.StartInfo=[Diagnostics.ProcessStartInfo]::new()
    $process.StartInfo.FileName=$executable;$process.StartInfo.Arguments=$arguments
    $process.StartInfo.UseShellExecute=$false;$process.StartInfo.CreateNoWindow=$true
    $process.StartInfo.RedirectStandardOutput=$true;$process.StartInfo.RedirectStandardError=$true
    try{
        if(-not $process.Start()){throw 'Nao foi possivel iniciar powercfg.'}
        $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
        $timedOut=-not $process.WaitForExit($TimeoutSeconds*1000)
        if($timedOut){$process.Kill();$process.WaitForExit()}else{$process.WaitForExit()}
        [pscustomobject]@{ExitCode=$process.ExitCode;StdOut=$out.Result;StdErr=$err.Result;TimedOut=$timedOut;Option=$Option}
    }finally{$process.Dispose()}
}
function Assert-GoatPowerCommandResult {
    param($Result,[string]$Option)
    if($null -eq $Result -or $Result.TimedOut -ne $false -or $null -eq $Result.ExitCode -or $Result.ExitCode -ne 0){
        $exit=if($Result){[string]$Result.ExitCode}else{'indisponivel'}
        $detail=if($Result){[string]$Result.StdErr}else{''}
        throw ('powercfg '+$Option+' falhou (exit='+$exit+'). '+$detail)
    }
}
function Get-GoatPowerPlans {
    [CmdletBinding()]
    param([switch]$Demo)
    $result=[ordered]@{SchemaVersion=1;Status='UNAVAILABLE';Demo=[bool]$Demo;ReadOnly=$true;ActiveSchemeGuid=$null;Plans=@();Source='powercfg /list + /getactivescheme';CollectedUtc=[DateTime]::UtcNow.ToString('o');Errors=@()}
    if($Demo){
        $result.Status='DEMO';$result.Source='DEMO: exemplos; nenhum powercfg executado'
        $result.ActiveSchemeGuid='381b4222-f694-41f0-9685-ff5bb260df2e'
        $result.Plans=@(
            [pscustomobject]@{Guid=$result.ActiveSchemeGuid;Name='Equilibrado (DEMO)';IsActive=$true},
            [pscustomobject]@{Guid='a1841308-3541-4fab-bc81-f71556f20b4a';Name='Economia (DEMO)';IsActive=$false},
            [pscustomobject]@{Guid='8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c';Name='Alto desempenho (DEMO)';IsActive=$false}
        )
        return [pscustomobject]$result
    }
    try{
        $listed=Invoke-GoatPowerCfg /list;Assert-GoatPowerCommandResult $listed '/list'
        $active=Invoke-GoatPowerCfg /getactivescheme;Assert-GoatPowerCommandResult $active '/getactivescheme'
        $pattern='[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}'
        $activeLines=@([string]$active.StdOut -split '\r?\n'|Where-Object{$_ -match $pattern})
        if($activeLines.Count -ne 1){throw 'Nao foi possivel determinar um unico plano ativo.'}
        $activeGuid=ConvertTo-GoatPowerGuid ([regex]::Match($activeLines[0],$pattern).Value)
        $plans=New-Object 'System.Collections.Generic.List[object]';$seen=@{}
        foreach($line in ([string]$listed.StdOut -split '\r?\n')){
            $match=[regex]::Match($line,'^\s*[^:]+:\s*(?<guid>'+ $pattern +')\s+\((?<name>.*)\)\s*\*?\s*$')
            if(-not $match.Success){continue}
            $id=ConvertTo-GoatPowerGuid $match.Groups['guid'].Value
            if($seen.ContainsKey($id)){throw 'A lista de planos contem GUID duplicado.'}
            $seen[$id]=$true
            $plans.Add([pscustomobject]@{Guid=$id;Name=$match.Groups['name'].Value;IsActive=($id -eq $activeGuid)})
        }
        if($plans.Count -eq 0 -or -not $seen.ContainsKey($activeGuid)){throw 'Lista de planos vazia ou plano ativo ausente da lista.'}
        $result.Status='READ_ONLY';$result.ActiveSchemeGuid=$activeGuid;$result.Plans=$plans.ToArray()
    }catch{$result.Errors=@($_.Exception.Message);$result.Plans=@();$result.ActiveSchemeGuid=$null}
    [pscustomobject]$result
}
function Get-GoatPowerContext {
    param($Session)
    $isAdmin=$false
    try{$isAdmin=([Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)}catch{}
    $indicators=New-Object 'System.Collections.Generic.List[string]'
    if($Session.Mode -ne 'Local'){$indicators.Add('Atendimento remoto ou modo nao confirmado.')}
    if($env:SESSIONNAME -ne 'Console'){$indicators.Add('Console fisico nao confirmado pelo ambiente da sessao.')}
    try{
        $names=@(Get-Process -ErrorAction Stop|Select-Object -ExpandProperty ProcessName)
        if(@($names|Where-Object{$_ -match '^(AnyDesk|TeamViewer|TeamViewer_Service|RustDesk|rustdesk_service|ScreenConnect.*|Splashtop.*|SRServer|Parsec|parsecd|supremo.*|winvnc|tvnserver|remoting_host)$'}).Count){$indicators.Add('Ferramenta de acesso remoto presente; conexao ativa incerta.')}
    }catch{$indicators.Add('Nao foi possivel conferir ferramentas de acesso remoto.')}
    $notebook=$null
    $inventoryProperty=$Session.PSObject.Properties['Inventory']
    if($inventoryProperty -and $inventoryProperty.Value){
        $inventory=$inventoryProperty.Value;$remoteProperty=$inventory.PSObject.Properties['RemoteContext']
        if($remoteProperty -and $remoteProperty.Value){
            $remote=$remoteProperty.Value;$isRemoteProperty=$remote.PSObject.Properties['IsRemote']
            if($isRemoteProperty -and ($isRemoteProperty.Value -isnot [bool] -or $isRemoteProperty.Value)){$indicators.Add('Inventario indica acesso remoto ou contexto incerto.')}
        }
        $gpuProperty=$inventory.PSObject.Properties['GpuCenter']
        if($gpuProperty -and $gpuProperty.Value){$systemProperty=$gpuProperty.Value.PSObject.Properties['System'];if($systemProperty -and $systemProperty.Value){$p=$systemProperty.Value.PSObject.Properties['IsNotebook'];if($p -and $p.Value -is [bool]){$notebook=$p.Value}}}
    }
    [pscustomobject]@{IsAdministrator=$isAdmin;RemoteOrUnknown=($indicators.Count -gt 0);IsNotebook=$notebook;Reasons=$indicators.ToArray()}
}
function Assert-GoatPowerSession {
    param($Session,[switch]$AllowClosed)
    if($null -eq $Session -or $Session.SchemaVersion -ne 1 -or [string]$Session.Id -notmatch '^[a-f0-9]{32}$' -or $Session.Demo -isnot [bool]){throw 'Sessao de energia invalida.'}
    $root=[IO.Path]::GetFullPath([string]$Session.Root);Assert-GoatPlainFilePath $root
    $stored=Get-Content -LiteralPath (Join-Path $root 'session.json') -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
    if($stored.Id -cne $Session.Id -or $stored.Demo -ne $Session.Demo -or $stored.State -notin @('Open','Finalizing','Finalized')){throw 'Sessao persistida invalida ou divergente.'}
    if(-not $AllowClosed -and ($Session.State -ne 'Open' -or $stored.State -ne 'Open')){throw 'Abra uma sessao ativa antes de alterar energia.'}
}
function Get-GoatPowerPreview {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Session,[Parameter(Mandatory=$true)][string]$SchemeGuid)
    Assert-GoatPowerSession $Session
    $target=ConvertTo-GoatPowerGuid $SchemeGuid
    $inventory=Get-GoatPowerPlans -Demo:$Session.Demo
    $reasons=New-Object 'System.Collections.Generic.List[string]'
    $chosen=@($inventory.Plans|Where-Object Guid -eq $target)
    if($inventory.Status -notin @('READ_ONLY','DEMO')){$reasons.Add('Inventario de energia indisponivel: '+($inventory.Errors -join '; '))}
    if($chosen.Count -ne 1){$reasons.Add('O GUID proposto nao e um plano existente confirmado.')}
    $changed=($null -ne $inventory.ActiveSchemeGuid -and $inventory.ActiveSchemeGuid -cne $target)
    $context=if($Session.Demo){[pscustomobject]@{IsAdministrator=$false;RemoteOrUnknown=$false;IsNotebook=$null;Reasons=@()}}else{Get-GoatPowerContext $Session}
    if($changed -and -not $Session.Demo){
        if(-not $context.IsAdministrator){$reasons.Add('Esta implementacao exige executar como administrador para trocar o plano; nao ha elevacao silenciosa.')}
        if($context.RemoteOrUnknown){foreach($reason in $context.Reasons){$reasons.Add($reason)};if(@($context.Reasons).Count -eq 0){$reasons.Add('Troca de plano bloqueada em contexto remoto ou incerto.')}}
    }
    [pscustomobject]@{
        SessionId=$Session.Id;ActionId='power-select-existing';ExecutionClass='B_APPROVAL';Status=$(if($reasons.Count){'BLOCKED'}elseif($Session.Demo){'DEMO'}elseif(-not $changed){'NO_OP'}else{'ELIGIBLE'})
        OriginalSchemeGuid=$inventory.ActiveSchemeGuid;CurrentSchemeGuid=$inventory.ActiveSchemeGuid;ProposedSchemeGuid=$target
        ProposedName=$(if($chosen.Count -eq 1){$chosen[0].Name}else{$null});Changed=$changed;ExecutionAllowed=($reasons.Count -eq 0)
        RequiresAdmin=($changed -and -not $Session.Demo);IsAdministrator=$context.IsAdministrator;RemoteOrUnknown=$context.RemoteOrUnknown;IsNotebook=$context.IsNotebook
        RequiresReboot=$false;RequiresGoatRuntime=$false;Persistence='NativeWindows';Reasons=$reasons.ToArray();ReadOnly=$true
        Tradeoffs=@('Trocar o plano aplica suas politicas existentes de desempenho, suspensao e energia de dispositivos.','Notebook: consumo, bateria, calor e ruido podem mudar; confirme tomada e condicoes termicas.','Nenhum ganho de FPS e garantido; medir a mesma carga antes/depois.','Nenhum plano e criado, excluido ou editado; a reversao restaura o GUID anteriormente ativo.')
    }
}
function Get-GoatPowerSnapshotHash {
    param($Transaction)
    $stamp=if($Transaction.CreatedUtc -is [datetime]){$Transaction.CreatedUtc.ToUniversalTime().ToString('o')}else{[datetime]::Parse([string]$Transaction.CreatedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind).ToUniversalTime().ToString('o')}
    $canonical=[ordered]@{Type=$Transaction.Type;SchemaVersion=$Transaction.SchemaVersion;Id=$Transaction.Id;SessionId=$Transaction.SessionId;Machine=$Transaction.Identity.Machine;Sid=$Transaction.Identity.Sid;CreatedUtc=$stamp;Sequence=$Transaction.Sequence;OriginalSchemeGuid=$Transaction.OriginalSchemeGuid;ProposedSchemeGuid=$Transaction.ProposedSchemeGuid}
    $sha=[Security.Cryptography.SHA256]::Create()
    try{([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes(($canonical|ConvertTo-Json -Compress -Depth 6))))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
}
function Assert-GoatPowerTransaction {
    param($Transaction,$Identity)
    if($Transaction.Type -cne 'POWER_SCHEME' -or $Transaction.SchemaVersion -ne 1 -or [string]$Transaction.Id -notmatch '^[a-f0-9]{32}$' -or [string]$Transaction.SessionId -notmatch '^[a-f0-9]{32}$'){throw 'Diario de energia invalido.'}
    if($Transaction.State -notin @('Prepared','Applying','Applied','Restoring','Restored','RestoreFailed','Conflict')){throw 'Estado de energia desconhecido.'}
    if($Transaction.Sequence -isnot [int] -and $Transaction.Sequence -isnot [long]){throw 'Ordem de energia invalida.'}
    if($Transaction.Sequence -le 0 -or [string]::IsNullOrWhiteSpace($Transaction.Identity.Machine) -or [string]::IsNullOrWhiteSpace($Transaction.Identity.Sid)){throw 'Identidade/ordem de energia ausente.'}
    $stamp=[datetime]::MinValue
    if($Transaction.CreatedUtc -is [datetime]){$stamp=$Transaction.CreatedUtc}
    elseif(-not [datetime]::TryParse([string]$Transaction.CreatedUtc,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::RoundtripKind,[ref]$stamp)){throw 'Data de energia invalida.'}
    $original=ConvertTo-GoatPowerGuid $Transaction.OriginalSchemeGuid;$proposed=ConvertTo-GoatPowerGuid $Transaction.ProposedSchemeGuid
    if($original -cne $Transaction.OriginalSchemeGuid -or $proposed -cne $Transaction.ProposedSchemeGuid -or $original -eq $proposed){throw 'Snapshot de energia invalido ou sem delta.'}
    if($Transaction.SnapshotSha256 -cne (Get-GoatPowerSnapshotHash $Transaction)){throw 'Hash do snapshot de energia divergente.'}
    if($null -ne $Identity -and ($Transaction.Identity.Machine -cne $Identity.Machine -or $Transaction.Identity.Sid -cne $Identity.Sid)){throw 'Diario de energia pertence a outro Windows/usuario.'}
}
function Get-GoatPowerTransactions {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Session,[switch]$IncludeRelated,$Identity)
    $owners=New-Object 'System.Collections.Generic.List[object]';$owners.Add([pscustomobject]@{Id=$Session.Id;Root=[IO.Path]::GetFullPath($Session.Root)})
    if($IncludeRelated){
        $groups=@((Split-Path ([IO.Path]::GetFullPath($Session.Root)) -Parent))
        $groupProperty=$Session.PSObject.Properties['RecoveryGroupRoot']
        $recovery=if($groupProperty -and $groupProperty.Value){[IO.Path]::GetFullPath([string]$groupProperty.Value)}else{[IO.Path]::GetFullPath($Session.Root)}
        if($groupProperty -and $groupProperty.Value){$header=Join-Path $recovery 'session.json';if([IO.File]::Exists($header)){$main=Get-Content -LiteralPath $header -Raw -Encoding UTF8|ConvertFrom-Json;$owners.Add([pscustomobject]@{Id=$main.Id;Root=$recovery})}}
        $embedded=Join-Path $recovery 'related-sessions';if([IO.Directory]::Exists($embedded)){$groups+=$embedded}
        foreach($group in $groups){Assert-GoatPlainFilePath $group;foreach($folder in @(Get-ChildItem -LiteralPath $group -Directory -ErrorAction Stop)){
            if($folder.Name -notmatch '^[a-f0-9]{32}$'){continue}
            Assert-GoatPlainFilePath $folder.FullName
            $header=Join-Path $folder.FullName 'session.json';if(-not [IO.File]::Exists($header)){continue}
            $owner=Get-Content -LiteralPath $header -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
            if($owner.SchemaVersion -eq 1 -and $owner.Id -ceq $folder.Name){$owners.Add([pscustomobject]@{Id=$owner.Id;Root=$folder.FullName})}
        }}
    }
    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach($owner in $owners){
        if(-not $seen.Add([IO.Path]::GetFullPath($owner.Root))){continue}
        $directory=Join-Path $owner.Root 'power-transactions';Assert-GoatPlainFilePath $directory
        if(-not [IO.Directory]::Exists($directory)){continue}
        foreach($file in @(Get-ChildItem -LiteralPath $directory -Filter '*.json' -File -Force|Sort-Object Name)){
            Assert-GoatPlainFilePath $file.FullName
            if($file.Length -gt 1MB){throw 'Diario de energia excede o limite.'}
            $record=Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
            Assert-GoatPowerTransaction $record
            if($record.Id -cne $file.BaseName -or $record.SessionId -cne $owner.Id){throw 'Identidade/nome do diario de energia divergente.'}
            if($null -ne $Identity -and ($record.Identity.Machine -cne $Identity.Machine -or $record.Identity.Sid -cne $Identity.Sid)){continue}
            $record|Add-Member JournalPath $file.FullName -Force|Out-Null
            $record|Add-Member OwnerSessionId $owner.Id -Force|Out-Null
            $record|Add-Member OwnerSessionRoot $owner.Root -Force -PassThru
        }
    }
}
function Get-GoatPowerPendingTransactions {
    param($Session,$Identity)
    Get-GoatPowerTransactions -Session $Session -IncludeRelated -Identity $Identity|Where-Object State -in @('Prepared','Applying','Restoring','RestoreFailed','Conflict')
}
function Write-GoatPowerJournal {
    param($Transaction,[string]$Path)
    Assert-GoatPowerTransaction $Transaction
    Write-GoatJson $Transaction $Path
    $written=Get-Content -LiteralPath $Path -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
    Assert-GoatPowerTransaction $written
    if($written.Id -cne $Transaction.Id -or $written.State -cne $Transaction.State -or $written.SnapshotSha256 -cne $Transaction.SnapshotSha256){throw 'Verificacao do diario duravel falhou; nenhuma nova mudanca autorizada.'}
}
function Get-GoatPowerVerifiedInventory {
    $inventory=Get-GoatPowerPlans
    if($inventory.Status -ne 'READ_ONLY' -or -not $inventory.ActiveSchemeGuid){throw ('Estado de energia desconhecido: '+($inventory.Errors -join '; '))}
    $inventory
}
function Assert-GoatPowerPlanExists {
    param([string]$SchemeGuid,$Inventory)
    if(@($Inventory.Plans|Where-Object Guid -eq $SchemeGuid).Count -ne 1){throw 'O plano necessario foi removido ou nao esta disponivel; nao sera recriado.'}
    $query=Invoke-GoatPowerCfg -Option /query -SchemeGuid $SchemeGuid
    Assert-GoatPowerCommandResult $query '/query'
}
function Restore-GoatPowerInternal {
    param($Transaction,[string]$Path,$Session)
    try{
        $inventory=Get-GoatPowerVerifiedInventory
        if($inventory.ActiveSchemeGuid -cne $Transaction.OriginalSchemeGuid -and $inventory.ActiveSchemeGuid -cne $Transaction.ProposedSchemeGuid){
            $Transaction.State='Conflict';$Transaction.Error='Plano ativo alterado fora desta transacao; revisao manual necessaria.';Write-GoatPowerJournal $Transaction $Path
            throw $Transaction.Error
        }
        Assert-GoatPowerPlanExists -SchemeGuid $Transaction.OriginalSchemeGuid -Inventory $inventory
        if($inventory.ActiveSchemeGuid -cne $Transaction.OriginalSchemeGuid){
            $context=Get-GoatPowerContext $Session
            if(-not $context.IsAdministrator -or $context.RemoteOrUnknown){throw 'Restauracao automatica suspensa: privilegio ou console local nao confirmado. Preserve o diario.'}
            $Transaction.State='Restoring';Write-GoatPowerJournal $Transaction $Path
            $latest=Get-GoatPowerVerifiedInventory
            if($latest.ActiveSchemeGuid -cne $Transaction.ProposedSchemeGuid){throw 'Plano mudou durante a revisao; restauracao nao foi executada.'}
            $native=Invoke-GoatPowerCfg -Option /setactive -SchemeGuid $Transaction.OriginalSchemeGuid
            $Transaction.LastExitCode=$native.ExitCode
            Assert-GoatPowerCommandResult $native '/setactive'
            $readback=Get-GoatPowerVerifiedInventory
            if($readback.ActiveSchemeGuid -cne $Transaction.OriginalSchemeGuid){throw 'powercfg encerrou sem restaurar o GUID original.'}
        }
        $Transaction.State='Restored';$Transaction.ReadBackVerified=$true;$Transaction.Message='Plano original restaurado e verificado.';Write-GoatPowerJournal $Transaction $Path
    }catch{
        $failure=$_.Exception.Message
        if($Transaction.State -ne 'Conflict'){$Transaction.State='RestoreFailed';$Transaction.Error='Restauracao nao concluida; preserve o diario. '+$failure;Write-GoatPowerJournal $Transaction $Path}
        throw $failure
    }
    $Transaction
}
function Invoke-GoatPowerChange {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Session,[Parameter(Mandatory=$true)][string]$SchemeGuid,[switch]$Consent,$ReviewedPreview)
    if(-not $Consent){throw 'Revise a previa e confirme a troca do plano de energia.'}
    Assert-GoatPowerSession $Session
    $mutex=[Threading.Mutex]::new($false,'Local\GOAT-Tweaks-Actions');$locked=$false
    try{
        try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw 'Outra operacao GOAT esta ativa.'}
        $preview=Get-GoatPowerPreview -Session $Session -SchemeGuid $SchemeGuid
        if($null -ne $ReviewedPreview){
            if($ReviewedPreview.SessionId -cne $Session.Id -or $ReviewedPreview.Changed -isnot [bool] -or $ReviewedPreview.OriginalSchemeGuid -cne $preview.OriginalSchemeGuid -or $ReviewedPreview.ProposedSchemeGuid -cne $preview.ProposedSchemeGuid -or $ReviewedPreview.Changed -ne $preview.Changed){throw 'A previa revisada ficou obsoleta ou pertence a outra sessao/selecao. Revise novamente antes de aplicar.'}
        }
        if(-not $preview.ExecutionAllowed){throw ($preview.Reasons -join ' ')}
        if($Session.Demo){Add-GoatEvent $Session 'DEMO' ('Simulacao de energia: '+$preview.ProposedSchemeGuid);return [pscustomobject]@{Type='POWER_SCHEME';State='DEMO';Message='Simulacao; nenhum comando powercfg foi executado.';Preview=$preview}}
        $identity=Get-GoatIdentity
        $related=@(Get-GoatPowerTransactions -Session $Session -IncludeRelated -Identity $identity)
        if(@($related|Where-Object State -in @('Prepared','Applying','Restoring','RestoreFailed','Conflict')).Count){throw 'Recupere primeiro a transacao de energia pendente.'}
        if(@(Get-GoatPendingTransactions $Session $identity).Count){throw 'Recupere primeiro a transacao nativa pendente.'}
        if(-not $preview.Changed){$current=Get-GoatPowerVerifiedInventory;if($current.ActiveSchemeGuid -cne $preview.ProposedSchemeGuid){throw 'Plano mudou durante a leitura; revise novamente.'};Add-GoatEvent $Session 'PowerNoOp' ('Plano ja ativo: '+$preview.ProposedSchemeGuid);return [pscustomobject]@{Type='POWER_SCHEME';State='NoOp';Message='O plano selecionado ja esta ativo; nenhuma troca executada.';OriginalSchemeGuid=$preview.OriginalSchemeGuid;ProposedSchemeGuid=$preview.ProposedSchemeGuid;ReadBackVerified=$true}}
        $inventory=Get-GoatPowerVerifiedInventory
        if($inventory.ActiveSchemeGuid -cne $preview.OriginalSchemeGuid){throw 'O plano ativo mudou apos a previa; revise novamente.'}
        Assert-GoatPowerPlanExists -SchemeGuid $preview.ProposedSchemeGuid -Inventory $inventory
        $sequence=1L;foreach($old in $related){if($old.Sequence -ge $sequence){if($old.Sequence -eq [long]::MaxValue){throw 'Sequencia de energia esgotada.'};$sequence=[long]$old.Sequence+1}}
        $transaction=[pscustomobject]@{Type='POWER_SCHEME';SchemaVersion=1;Id=[guid]::NewGuid().ToString('N');SessionId=$Session.Id;Identity=$identity;CreatedUtc=[DateTime]::UtcNow.ToString('o');Sequence=$sequence;OriginalSchemeGuid=$preview.OriginalSchemeGuid;ProposedSchemeGuid=$preview.ProposedSchemeGuid;SnapshotSha256='';State='Prepared';ReadBackVerified=$false;LastExitCode=$null;Error=$null;Message='Troca de plano preparada; nenhuma alteracao executada.'}
        $transaction.SnapshotSha256=Get-GoatPowerSnapshotHash $transaction
        $path=Join-Path $Session.Root ('power-transactions\'+$transaction.Id+'.json')
        Write-GoatPowerJournal $transaction $path
        try{
            $latest=Get-GoatPowerVerifiedInventory
            if($latest.ActiveSchemeGuid -cne $transaction.OriginalSchemeGuid){$transaction.State='Conflict';$transaction.Error='Plano alterado externamente antes da aplicacao.';Write-GoatPowerJournal $transaction $path;throw $transaction.Error}
            $safety=Get-GoatPowerContext $Session
            if(-not $safety.IsAdministrator -or $safety.RemoteOrUnknown){throw 'Contexto ou privilegio mudou; a troca de energia foi cancelada.'}
            $transaction.State='Applying';Write-GoatPowerJournal $transaction $path
            $native=Invoke-GoatPowerCfg -Option /setactive -SchemeGuid $transaction.ProposedSchemeGuid
            $transaction.LastExitCode=$native.ExitCode
            Assert-GoatPowerCommandResult $native '/setactive'
            $readback=Get-GoatPowerVerifiedInventory
            if($readback.ActiveSchemeGuid -cne $transaction.ProposedSchemeGuid){throw 'powercfg encerrou sem ativar o GUID proposto.'}
            $transaction.State='Applied';$transaction.ReadBackVerified=$true;$transaction.Message='Plano existente ativado e verificado; beneficio de desempenho nao medido.';Write-GoatPowerJournal $transaction $path
            Add-GoatEvent $Session 'PowerApplied' ('Plano verificado: '+$transaction.ProposedSchemeGuid)
            $transaction
        }catch{
            $failure=$_.Exception.Message
            if($transaction.State -ne 'Conflict'){
                $transaction.Error='Aplicacao falhou: '+$failure
                Restore-GoatPowerInternal -Transaction $transaction -Path $path -Session $Session|Out-Null
            }
            throw ('Troca de energia falhou. '+$failure)
        }
    }finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Restore-GoatPowerChange {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Session,[Parameter(Mandatory=$true)][string]$TransactionId,[switch]$Consent)
    if(-not $Consent){throw 'Confirme a restauracao do plano original.'}
    Assert-GoatPowerSession $Session -AllowClosed
    if($Session.Demo){return [pscustomobject]@{Type='POWER_SCHEME';State='DEMO';Message='Restauracao simulada; nenhum powercfg executado.'}}
    if($TransactionId -notmatch '^[a-f0-9]{32}$'){throw 'ID de transacao de energia invalido.'}
    $mutex=[Threading.Mutex]::new($false,'Local\GOAT-Tweaks-Actions');$locked=$false
    try{
        try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw 'Outra operacao GOAT esta ativa.'}
        $identity=Get-GoatIdentity
        $matches=@(Get-GoatPowerTransactions $Session|Where-Object Id -eq $TransactionId)
        if($matches.Count -ne 1){throw 'Transacao de energia nao encontrada nesta sessao.'}
        $transaction=$matches[0];Assert-GoatPowerTransaction $transaction $identity
        if($transaction.State -eq 'Restored'){return $transaction}
        $later=@(Get-GoatPowerTransactions -Session $Session -IncludeRelated -Identity $identity|Where-Object{$_.Sequence -gt $transaction.Sequence -and $_.State -ne 'Restored'})
        if($later.Count){throw 'Restaure primeiro a troca de energia mais recente, inclusive de outras sessoes.'}
        $context=Get-GoatPowerContext $Session
        if(-not $context.IsAdministrator -or $context.RemoteOrUnknown){throw 'Restauracao de energia exige administrador e console local confirmado.'}
        $restored=Restore-GoatPowerInternal -Transaction $transaction -Path $transaction.JournalPath -Session $Session
        Add-GoatEvent $Session 'PowerRestored' ('Plano original verificado: '+$transaction.OriginalSchemeGuid)
        $restored
    }finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
