function ConvertTo-GoatPublicValue {
    param($Value,[int]$Depth=0)
    if ($Depth -gt 24) { return '[profundidade omitida]' }
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        if ($Value -match '(?i)([a-z]:[\\/]|\\\\[^\\\s]+\\|file://|/users/|/home/)') { return '[caminho pessoal omitido]' }
        $safe=$Value -replace '(?i)\bS-1-\d+(?:-\d+){2,}\b','[SID omitido]'
        return ($safe -replace '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b','[email omitido]')
    }
    if ($Value -is [ValueType]) { return $Value }
    if ($Value -is [Collections.IDictionary]) {
        $result=[ordered]@{}
        foreach($key in $Value.Keys) {
            if([string]$key -match '(?i)(password|secret|token|credential|serial|hostname|computername|username|accountname|email|macaddress|ipaddress|pnp|deviceid|executablepath|journalpath|^sid$|^machine$|^root$|^path$|^sourcepath$)'){continue}
            $result[$key]=ConvertTo-GoatPublicValue $Value[$key] ($Depth+1)
        }
        return [pscustomobject]$result
    }
    if ($Value -is [Collections.IEnumerable]) {
        $result=@();foreach($item in $Value){$result+=,(ConvertTo-GoatPublicValue $item ($Depth+1))};return ,$result
    }
    $result=[ordered]@{}
    foreach($property in $Value.PSObject.Properties){
        if($property.Name -match '(?i)(password|secret|token|credential|serial|hostname|computername|username|accountname|email|macaddress|ipaddress|pnp|deviceid|executablepath|journalpath|^sid$|^machine$|^root$|^path$|^sourcepath$)'){continue}
        $result[$property.Name]=ConvertTo-GoatPublicValue $property.Value ($Depth+1)
    }
    return [pscustomobject]$result
}
function Get-GoatPublicReport {
    param($Session)
    $hardware=$null
    if ($Session.Inventory) {
        # Explicit projection: no host name, SID, PnP IDs, serials or personal paths.
        $i=$Session.Inventory
        $hardware=[pscustomobject]@{OS=$i.OS;CPU=$i.CPU;Memory=$i.Memory}
        if($i.GpuCenter){
            $hardware | Add-Member GPUs @($i.GpuCenter.Devices | Select-Object Name,Vendor,DriverVersion,DriverDate)
        }
    }
    $transactions=@(Get-GoatTransactions $Session | ForEach-Object {
        [pscustomobject]@{Id=$_.Id;State=$_.State;CreatedUtc=$_.CreatedUtc;Steps=@($_.Steps | Select-Object Id,State,Error)}
    })
    $power=@();if(Get-Command Get-GoatPowerTransactions -ErrorAction SilentlyContinue){$power=@(Get-GoatPowerTransactions $Session|Select-Object Id,State,CreatedUtc,OriginalSchemeGuid,ProposedSchemeGuid,ReadBackVerified)}
    $manual=@($Session.ManualRecords|Where-Object {$null -ne $_}|Select-Object Id,Title,Utc,State,AutomaticallyVerified,Risk)
    $report=[pscustomobject]@{
        Product='GOAT Tweaks';Version=$(if($script:GoatVersion){$script:GoatVersion}else{'7.4.1'});SchemaVersion=1;Session=$Session.Id;CreatedUtc=$Session.CreatedUtc
        Objective=$Session.Objective;Mode=$Session.Mode;Demo=$Session.Demo;State=$(if($Session.State -eq 'Finalizing'){'Finalized'}else{$Session.State})
        Hardware=$hardware;Transactions=$transactions;PowerTransactions=$power;ManualRecords=$manual
        Benchmarks=@($Session.Benchmarks | ForEach-Object { [pscustomobject]@{ConditionLabel=$_.ConditionLabel;PassNumber=$_.PassNumber;Conditions=$_.Conditions;Metrics=$_.Metrics;SourceSha256=$_.Source.Sha256;IntervalColumn=$_.Source.Column;IntervalUnits=$_.Source.Units;IntervalSemantics=$_.Source.Semantics;RowsImported=$_.Source.RowsImported} })
        Comparison=$Session.Comparison;Events=@($Session.Events | Where-Object Kind -in @('DEMO','Applied','Restored','Manual','PowerApplied','PowerRestored','PowerNoOp') | Select-Object Utc,Kind)
        PerformanceClaim='Nenhum ganho atribuído a ajustes sem comparação válida. Telemetria não mede input lag.'
        Recovery='Diários completos e identidade do Windows ficam somente no pacote privado de reversão.'
        Limitations=@('Aplicativo sem assinatura digital. Matriz física Windows 10/11 e NVIDIA/AMD/Intel incompleta. Leitura de Registro/GUID confirma persistência, não efeito em desempenho.','Etapas manuais são relatos do técnico, sem verificação automática. Controles de fabricante dependem do modelo e da versão.','Sem instalações, serviços persistentes, tarefas agendadas ou reinício automático.')
    }
    ConvertTo-GoatPublicValue $report
}
function Test-GoatExport {
    param([string]$Directory,[string]$ExpectedSessionId,[switch]$RequireFinalized)
    $Directory=[IO.Path]::GetFullPath($Directory)
    Assert-GoatPlainFilePath $Directory
    $manifestPath=Join-Path $Directory 'manifest.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if($manifest.SchemaVersion -ne 1 -or @($manifest.Files).Count -lt 3){throw 'Manifesto de exportação inválido.'}
    if([string]$manifest.Session -notmatch '^[a-f0-9]{32}$' -or ($ExpectedSessionId -and $manifest.Session -cne $ExpectedSessionId)){throw 'Exportação pertence a outra sessão.'}
    $names=@($manifest.Files | ForEach-Object { ([string]$_.Path).Replace('/','\') })
    if(@($names|Select-Object -Unique).Count -ne $names.Count){throw 'Manifesto contém caminhos duplicados.'}
    foreach($required in @('report.json','report.html','transactions.csv','private-recovery\session.json','private-recovery\Restore-GOAT.ps1','private-recovery\LEIA-ME.txt')){
        if($names -notcontains $required){throw ('Arquivo obrigatório ausente no manifesto: '+$required)}
    }
    foreach($item in $manifest.Files){
        if($item.Path -match '(^|[/\\])\.\.([/\\]|$)|:' -or [IO.Path]::IsPathRooted($item.Path)){throw 'Caminho inválido no manifesto.'}
        $file=Join-Path $Directory $item.Path
        Assert-GoatPlainFilePath $file
        if(-not [IO.File]::Exists($file) -or [string]$item.Sha256 -notmatch '^[a-fA-F0-9]{64}$' -or (Get-Item -LiteralPath $file).Length -ne $item.Size -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.Sha256){throw ('Exportação corrompida: '+$item.Path)}
        if((Get-Item -LiteralPath $file).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Arquivo de recuperação redirecionado.'}
    }
    $report=Get-Content -LiteralPath (Join-Path $Directory 'report.json') -Raw -Encoding UTF8|ConvertFrom-Json -ErrorAction Stop
    if($report.Session -cne $manifest.Session -or ($RequireFinalized -and $report.State -ne 'Finalized')){throw 'Relatório diverge da sessão ou da finalização esperada.'}
    return $true
}
function Export-GoatServiceInternal {
    param($Session,[Parameter(Mandatory)][string]$Destination,[string]$ExportDirectory)
    $destinationRoot=[IO.Path]::GetFullPath($Destination)
    Assert-GoatPlainFilePath $destinationRoot
    [void][IO.Directory]::CreateDirectory($destinationRoot)
    $directory=if($ExportDirectory){[IO.Path]::GetFullPath($ExportDirectory)}else{Join-Path $destinationRoot ('GOAT-'+$Session.Id+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))}
    if([IO.Directory]::Exists($directory) -or [IO.File]::Exists($directory)){throw 'Destino de exportação já existe; escolha outro nome para preservar o original.'}
    [void][IO.Directory]::CreateDirectory($directory)
    $report=Get-GoatPublicReport $Session
    Write-GoatJson $report (Join-Path $directory 'report.json')
    $encode={param($v) [Net.WebUtility]::HtmlEncode([string]$v)}
    $json=& $encode ($report | ConvertTo-Json -Depth 32)
    $summary=if($report.Demo){'Modo demonstração: nenhuma alteração do Windows foi realizada.'}else{'As alterações registradas e seus resultados aparecem abaixo. Aplicação verificada não comprova ganho de desempenho.'}
    $rows=''
    $tableTransactions=@($report.Transactions)+@($report.PowerTransactions)+@($report.ManualRecords|ForEach-Object {[pscustomobject]@{Id=$_.Id+' (manual)';State=$_.State;CreatedUtc=$_.Utc}})
    foreach($transaction in $tableTransactions){
        $rows+='<tr><td>'+(& $encode $transaction.Id)+'</td><td>'+(& $encode $transaction.State)+'</td><td>'+(& $encode $transaction.CreatedUtc)+'</td></tr>'
    }
    if(-not $rows){$rows='<tr><td colspan="3">Nenhuma alteração nativa registrada neste atendimento.</td></tr>'}
    $html='<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>GOAT Tweaks — relatório</title><style>body{background:#111;color:#eee;font:16px Segoe UI,sans-serif;max-width:960px;margin:40px auto;padding:24px;line-height:1.6}h1,h2{color:#e4b95b}table{width:100%;border-collapse:collapse}td,th{padding:12px;text-align:left;border-bottom:1px solid #444;overflow-wrap:anywhere}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#1c1c1c;padding:20px;border-radius:10px}summary{cursor:pointer;color:#e4b95b}</style><h1>GOAT Tweaks · relatório de atendimento</h1><p>'+(& $encode $summary)+'</p><p><strong>Objetivo:</strong> '+(& $encode $report.Objective)+' · <strong>Estado:</strong> '+(& $encode $report.State)+'</p><h2>Procedimentos registrados</h2><table><thead><tr><th>Transação</th><th>Resultado</th><th>Horário UTC</th></tr></thead><tbody>'+$rows+'</tbody></table><h2>Medições e recuperação</h2><p>Nenhum ganho é atribuído a ajustes sem comparação válida. Sensores de utilização não medem input lag. O anexo técnico registra medições disponíveis e resultados inconclusivos.</p><p>Guarde a pasta <strong>private-recovery</strong> em local privado: contém valores originais e instruções de reversão para o mesmo Windows e usuário. Procedimentos em drivers exigem recuperação manual própria.</p><details><summary>Anexo técnico: inventário, evidências e limitações</summary><pre>'+$json+'</pre></details></html>'
    [IO.File]::WriteAllText((Join-Path $directory 'report.html'),$html,[Text.UTF8Encoding]::new($false))
    $csvPath=Join-Path $directory 'transactions.csv'
    if($tableTransactions.Count){$tableTransactions | Select-Object Id,State,CreatedUtc | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8}
    else{[IO.File]::WriteAllText($csvPath,'"Id","State","CreatedUtc"'+"`r`n",[Text.UTF8Encoding]::new($true))}
    $recovery=Join-Path $directory 'private-recovery'
    [void][IO.Directory]::CreateDirectory($recovery)
    # Only copies GOAT-owned session artifacts; never deletes originals.
    Copy-Item -LiteralPath (Join-Path $Session.Root 'session.json') -Destination (Join-Path $recovery 'session.json')
    $audit=Join-Path $Session.Root 'audit.jsonl'
    if(Test-Path -LiteralPath $audit){Copy-Item -LiteralPath $audit -Destination (Join-Path $recovery 'audit.jsonl')}
    $captureRoot=Join-Path $Session.Root 'captures'
    if(@($Session.Benchmarks).Count -gt 0){
        if(-not [IO.Directory]::Exists($captureRoot)){throw 'Pasta de capturas originais ausente; exportação incompleta preservada.'}
        [void][IO.Directory]::CreateDirectory((Join-Path $recovery 'captures'))
        foreach($capture in @($Session.Benchmarks)){
            if($capture.CaptureId -notmatch '^[a-f0-9]{32}$'){throw 'Identificador de captura inválido.'}
            $snapshotName=if($capture.Source.SnapshotFileName){[string]$capture.Source.SnapshotFileName}else{$capture.CaptureId+'.csv'}
            if($snapshotName -notmatch '^[a-f0-9]{32}\.csv$'){throw 'Nome do snapshot de captura inválido.'}
            $original=Join-Path $captureRoot $snapshotName
            Assert-GoatPlainFilePath $original
            if(-not (Test-Path -LiteralPath $original) -or (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ne $capture.Source.Sha256){throw 'Dados originais de captura ausentes ou alterados.'}
            $copied=Join-Path $recovery ('captures\'+$snapshotName)
            Copy-Item -LiteralPath $original -Destination $copied -ErrorAction Stop
            if((Get-FileHash -LiteralPath $copied -Algorithm SHA256).Hash -ne $capture.Source.Sha256){throw 'Cópia da captura divergiu do hash usado nas métricas; exportação incompleta preservada.'}
        }
    }
    foreach($journalKind in @('transactions','power-transactions')){
      $journalRoot=Join-Path $Session.Root $journalKind
      if(Test-Path -LiteralPath $journalRoot){
        [void][IO.Directory]::CreateDirectory((Join-Path $recovery $journalKind))
        foreach($file in @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File -Force)){
            Assert-GoatPlainFilePath $file.FullName
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $recovery ($journalKind+'\'+$file.Name))
        }
      }
    }
    $currentTransactions=@(Get-GoatTransactions $Session)
    $currentPower=@();if(Get-Command Get-GoatPowerTransactions -ErrorAction SilentlyContinue){$currentPower=@(Get-GoatPowerTransactions $Session)}
    $hasPowerRecovery=($currentPower.Count -gt 0)
    if([IO.Directory]::Exists((Join-Path $Session.Root 'power-transactions')) -and -not (Get-Command Get-GoatPowerTransactions -ErrorAction SilentlyContinue)){throw 'Módulo de energia ausente; exportação não pode validar seus diários.'}
    if($currentTransactions.Count -gt 0 -or $currentPower.Count -gt 0){
        $identity=if($currentTransactions.Count){$currentTransactions[0].Identity}else{$currentPower[0].Identity}
        $related=@(Get-GoatRelatedTransactions $Session $identity | Where-Object OwnerSessionRoot -ne $Session.Root)
        if(Get-Command Get-GoatPowerTransactions -ErrorAction SilentlyContinue){$related+=@(Get-GoatPowerTransactions $Session -IncludeRelated -Identity $identity|Where-Object OwnerSessionRoot -ne $Session.Root)}
        if(@($related|Where-Object Type -eq 'POWER_SCHEME').Count){$hasPowerRecovery=$true}
        foreach($group in @($related|Group-Object OwnerSessionId)){
            if($group.Name -notmatch '^[a-f0-9]{32}$'){throw 'ID de sessão relacionada inválido.'}
            $relatedRoot=Join-Path $recovery ('related-sessions\'+$group.Name)
            [void][IO.Directory]::CreateDirectory((Join-Path $relatedRoot 'transactions'))
            $header=[pscustomobject]@{SchemaVersion=1;Id=$group.Name;CreatedUtc=$group.Group[0].CreatedUtc;State='Open';Demo=$false;Objective='Equilibrado';Mode='Local';Consent=$false;Inventory=$null;Profiles=@();Benchmarks=@();Comparison=$null;Root=$relatedRoot;Events=@();Exports=@();FinalExport=$null}
            Write-GoatJson $header (Join-Path $relatedRoot 'session.json')
            foreach($transaction in $group.Group){
                $kind=if($transaction.Type -eq 'POWER_SCHEME'){'power-transactions'}else{'transactions'}
                [void][IO.Directory]::CreateDirectory((Join-Path $relatedRoot $kind))
                Copy-Item -LiteralPath $transaction.JournalPath -Destination (Join-Path $relatedRoot ($kind+'\'+$transaction.Id+'.json')) -ErrorAction Stop
            }
        }
    }
    if(-not $script:GoatCoreSource){throw 'Fonte de recuperação ausente; nenhuma limpeza foi realizada.'}
    if($hasPowerRecovery -and -not $script:GoatPowerSource){throw 'Fonte de recuperação de energia ausente.'}
    $restore=@'
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Restore,[string]$TransactionId,[string]$SessionId,[ValidateSet('Registry','Power')][string]$Kind='Registry')
$ErrorActionPreference='Stop'
'@
    $restore+="`r`n"+$script:GoatCoreSource+"`r`n"+$script:GoatPowerSource+"`r`nfunction Test-GoatExport {`r`n"+(Get-Command Test-GoatExport).Definition+"`r`n}`r`n"+@'
$main=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
[void](Test-GoatExport -Directory (Split-Path $PSScriptRoot -Parent) -ExpectedSessionId $main.Id)
if(-not $SessionId){$SessionId=$main.Id}
if($SessionId -notmatch '^[a-f0-9]{32}$'){throw 'SessionId inválido.'}
$source=if($SessionId -eq $main.Id){$PSScriptRoot}else{Join-Path $PSScriptRoot ('related-sessions\'+$SessionId)}
if(-not [IO.File]::Exists((Join-Path $source 'session.json'))){throw 'Sessão não incluída no pacote de recuperação.'}
$runtime=Join-Path $PSScriptRoot 'runtime'
$packMutex=[Threading.Mutex]::new($false,'Local\GOAT-Tweaks-Actions');$packLocked=$false
try {
if($Restore){
    if(-not $TransactionId){throw 'Informe -TransactionId após revisar a lista.'}
    $answer=Read-Host 'Restaurar os valores originais desta transação no mesmo Windows/usuário? Digite RESTAURAR'
    if($answer -cne 'RESTAURAR'){throw 'Restauração cancelada.'}
    try{$packLocked=$packMutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$packLocked=$true}
    if(-not $packLocked){throw 'Outra operação GOAT está ativa.'}
    # Original exported snapshots stay immutable and keep matching the manifest.
    # Working journals for all included sessions live beside one another, so the
    # same cross-session ordering gate works without the installed application.
    $sources=@($PSScriptRoot)
    $related=Join-Path $PSScriptRoot 'related-sessions'
    if([IO.Directory]::Exists($related)){$sources+=@(Get-ChildItem -LiteralPath $related -Directory|Select-Object -ExpandProperty FullName)}
    foreach($folder in $sources){
        $header=Get-Content -LiteralPath (Join-Path $folder 'session.json') -Raw -Encoding UTF8|ConvertFrom-Json
        if($header.Id -notmatch '^[a-f0-9]{32}$'){throw 'Identidade de sessão inválida no pacote.'}
        $target=Join-Path $runtime $header.Id
        if(-not [IO.Directory]::Exists($target)){
            [void][IO.Directory]::CreateDirectory($runtime)
            $staging=Join-Path $runtime ('.staging-'+[guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($staging)
            Copy-Item -LiteralPath (Join-Path $folder 'session.json') -Destination (Join-Path $staging 'session.json') -ErrorAction Stop
            $journals=Join-Path $folder 'transactions';if([IO.Directory]::Exists($journals)){Copy-Item -LiteralPath $journals -Destination (Join-Path $staging 'transactions') -Recurse -ErrorAction Stop}
            $powerJournals=Join-Path $folder 'power-transactions';if([IO.Directory]::Exists($powerJournals)){Copy-Item -LiteralPath $powerJournals -Destination (Join-Path $staging 'power-transactions') -Recurse -ErrorAction Stop}
            $sourceOwner=[pscustomobject]@{Id=$header.Id;Root=$folder};$stageOwner=[pscustomobject]@{Id=$header.Id;Root=$staging}
            $expectedIds=@(Get-GoatTransactions $sourceOwner|Select-Object -ExpandProperty Id)
            $copiedIds=@(Get-GoatTransactions $stageOwner|Select-Object -ExpandProperty Id)
            if(($expectedIds|Sort-Object|ConvertTo-Json -Compress) -cne ($copiedIds|Sort-Object|ConvertTo-Json -Compress)){throw 'Cópia dos diários de trabalho incompleta; preserve a pasta staging.'}
            $expectedPower=@();if(Get-Command Get-GoatPowerTransactions -ErrorAction SilentlyContinue){$expectedPower=@(Get-GoatPowerTransactions $sourceOwner|Select-Object -ExpandProperty Id);$copiedPower=@(Get-GoatPowerTransactions $stageOwner|Select-Object -ExpandProperty Id);if(($expectedPower|Sort-Object|ConvertTo-Json -Compress) -cne ($copiedPower|Sort-Object|ConvertTo-Json -Compress)){throw 'Cópia dos diários de energia incompleta.'}}
            Write-GoatJson ([pscustomobject]@{SchemaVersion=1;SessionId=$header.Id;TransactionIds=$expectedIds;PowerTransactionIds=$expectedPower}) (Join-Path $staging 'recovery-ready.json')
            [IO.Directory]::Move($staging,$target)
        }
        $readyFile=Join-Path $target 'recovery-ready.json'
        if(-not [IO.File]::Exists($readyFile)){throw 'Área de recuperação incompleta; preserve-a para revisão antes de continuar.'}
        $ready=Get-Content -LiteralPath $readyFile -Raw -Encoding UTF8|ConvertFrom-Json
        if($ready.SchemaVersion -ne 1 -or $ready.SessionId -cne $header.Id){throw 'Marcador de recuperação inválido.'}
        foreach($id in @($ready.TransactionIds)){if($id -notmatch '^[a-f0-9]{32}$' -or -not [IO.File]::Exists((Join-Path $target ('transactions\'+$id+'.json')))){throw 'Diário de recuperação ausente; não prosseguir fora da ordem.'}}
        foreach($id in @($ready.PowerTransactionIds|Where-Object {$null -ne $_})){if($id -notmatch '^[a-f0-9]{32}$' -or -not [IO.File]::Exists((Join-Path $target ('power-transactions\'+$id+'.json')))){throw 'Diário de energia ausente; não prosseguir fora da ordem.'}}
    }
}
$working=Join-Path $runtime $SessionId
$session=Get-Content -LiteralPath (Join-Path $(if([IO.Directory]::Exists($working)){$working}else{$source}) 'session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$session.Root=if([IO.Directory]::Exists($working)){$working}else{$source}
if(-not [IO.Directory]::Exists($working)){$session|Add-Member RecoveryGroupRoot $PSScriptRoot -Force}
$transactions=@(Get-GoatRelatedTransactions $session (Get-GoatIdentity))
$transactions|Sort-Object CreatedUtc -Descending|Select-Object OwnerSessionId,Id,State,CreatedUtc|Format-Table
$powerTransactions=@();if(Get-Command Get-GoatPowerTransactions -ErrorAction SilentlyContinue){$powerTransactions=@(Get-GoatPowerTransactions $session -IncludeRelated -Identity (Get-GoatIdentity));$powerTransactions|Sort-Object Sequence -Descending|Select-Object OwnerSessionId,Id,State,Sequence,OriginalSchemeGuid,ProposedSchemeGuid|Format-Table}
if($Restore){
    if($Kind -eq 'Power'){
        if(-not (Get-Command Restore-GoatPowerChange -ErrorAction SilentlyContinue)){throw 'Este pacote não contém recuperação de energia.'}
        Restore-GoatPowerChange -Session $session -TransactionId $TransactionId -Consent
    }else{Restore-GoatTransaction -Session $session -TransactionId $TransactionId -Consent}
}
}finally{if($packLocked){$packMutex.ReleaseMutex()};$packMutex.Dispose()}
'@
    [IO.File]::WriteAllText((Join-Path $recovery 'Restore-GOAT.ps1'),$restore,[Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $recovery 'LEIA-ME.txt'),'PRIVADO: contém identidade do Windows e valores originais. Não publique. Execute Restore-GOAT.ps1 para listar transações. Use -Restore -TransactionId ID e, para sessão relacionada, -SessionId ID. Para energia adicione -Kind Power (padrão Registry). Restaure da mais recente para a mais antiga; energia usa Sequence. Snapshots exportados são preservados; diários de trabalho ficam em runtime. Drivers e etapas manuais exigem recuperação própria. Preserve também a sessão original.',[Text.UTF8Encoding]::new($true))
    $files=@(Get-ChildItem -LiteralPath $directory -Recurse -File | ForEach-Object {
        [pscustomobject]@{Path=$_.FullName.Substring($directory.Length+1);Sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash;Size=$_.Length}
    })
    Write-GoatJson ([pscustomobject]@{SchemaVersion=1;Session=$Session.Id;Files=$files}) (Join-Path $directory 'manifest.json')
    [void](Test-GoatExport -Directory $directory -ExpectedSessionId $Session.Id)
    $Session.Exports+=$directory;Save-GoatSession $Session
    return $directory
}
function Export-GoatService {
    param($Session,[Parameter(Mandatory)][string]$Destination,[string]$ExportDirectory)
    $mutex=[Threading.Mutex]::new($false,'Local\GOAT-Tweaks-Actions');$locked=$false
    try{try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true};if(-not $locked){throw 'Outra operação GOAT está ativa.'};Export-GoatServiceInternal $Session $Destination $ExportDirectory}
    finally{if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
function Complete-GoatSession {
    param($Session,[string]$Destination,[switch]$Consent)
    if($Session.State -eq 'Finalized'){
        [void](Test-GoatExport -Directory $Session.FinalExport -ExpectedSessionId $Session.Id -RequireFinalized)
        return $Session.FinalExport
    }
    if(-not $Consent -and $Session.State -ne 'Finalizing'){throw 'Revise o atendimento e confirme a finalização.'}
    $mutex=[Threading.Mutex]::new($false,'Local\GOAT-Tweaks-Actions');$locked=$false
    try {
        try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw 'Outra operação GOAT está ativa.'}
        if($Session.State -eq 'Finalizing' -and $Session.FinalExport){
            try{
                [void](Test-GoatExport -Directory $Session.FinalExport -ExpectedSessionId $Session.Id -RequireFinalized)
                $Session.State='Finalized';Save-GoatSession $Session;return $Session.FinalExport
            }catch{# Keep the interrupted export intact; a fresh export uses a new directory.
            }
        }
        if(-not $Consent){throw 'A exportação interrompida precisa de revisão antes de tentar finalizar novamente.'}
        $unresolved=@(Get-GoatTransactions $Session | Where-Object State -in @('Prepared','Applying','Restoring','RestoreFailed'))
        if(Get-Command Get-GoatPowerPendingTransactions -ErrorAction SilentlyContinue){$unresolved+=@(Get-GoatPowerPendingTransactions $Session (Get-GoatIdentity))}
        if($unresolved.Count){throw 'Finalização bloqueada por transação pendente; preserve o diário e restaure primeiro.'}
        $destinationRoot=[IO.Path]::GetFullPath($Destination)
        $planned=Join-Path $destinationRoot ('GOAT-'+$Session.Id+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
        $Session.State='Finalizing';$Session.FinalExport=$planned;Save-GoatSession $Session
        try {
            $export=Export-GoatService -Session $Session -Destination $Destination -ExportDirectory $planned
            $Session.State='Finalized';$Session.FinalExport=$export;Save-GoatSession $Session
        } catch {
            $Session.State='Open';$Session.FinalExport=$null;Save-GoatSession $Session
            throw
        }
        # Portable application: nothing installed, no services/tasks/helpers to delete.
        return $export
    } finally {if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
