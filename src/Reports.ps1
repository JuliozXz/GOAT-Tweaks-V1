function ConvertTo-GoatPublicValue {
    param($Value,[int]$Depth=0)
    if ($Depth -gt 24) { return '[profundidade omitida]' }
    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) {
        if ($Value -match '(?i)([a-z]:[\\/]|\\\\[^\\\s]+\\|file://|/users/|/home/)') { return '[caminho pessoal omitido]' }
        return $Value
    }
    if ($Value -is [ValueType]) { return $Value }
    if ($Value -is [Collections.IDictionary]) {
        $result=[ordered]@{}
        foreach($key in $Value.Keys) {
            if([string]$key -match '(?i)(password|secret|token|credential|serial|hostname|computername|pnp|deviceid|executablepath|journalpath|^sid$|^machine$|^root$|^path$|^sourcepath$)'){continue}
            $result[$key]=ConvertTo-GoatPublicValue $Value[$key] ($Depth+1)
        }
        return [pscustomobject]$result
    }
    if ($Value -is [Collections.IEnumerable]) {
        $result=@();foreach($item in $Value){$result+=,(ConvertTo-GoatPublicValue $item ($Depth+1))};return ,$result
    }
    $result=[ordered]@{}
    foreach($property in $Value.PSObject.Properties){
        if($property.Name -match '(?i)(password|secret|token|credential|serial|hostname|computername|pnp|deviceid|executablepath|journalpath|^sid$|^machine$|^root$|^path$|^sourcepath$)'){continue}
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
    $report=[pscustomobject]@{
        Product='GOAT Tweaks';Version='7.3.0-preview';SchemaVersion=1;Session=$Session.Id;CreatedUtc=$Session.CreatedUtc
        Objective=$Session.Objective;Mode=$Session.Mode;Demo=$Session.Demo;State=$(if($Session.State -eq 'Finalizing'){'Finalized'}else{$Session.State})
        Hardware=$hardware;Transactions=$transactions
        Benchmarks=@($Session.Benchmarks | ForEach-Object { [pscustomobject]@{ConditionLabel=$_.ConditionLabel;PassNumber=$_.PassNumber;Conditions=$_.Conditions;Metrics=$_.Metrics;SourceSha256=$_.Source.Sha256;IntervalColumn=$_.Source.Column} })
        Comparison=$Session.Comparison;Events=@($Session.Events | Where-Object Kind -in @('DEMO','Applied','Restored','Manual') | Select-Object Utc,Kind)
        PerformanceClaim='Nenhum ganho atribuído a ajustes sem comparação válida. Telemetria não mede input lag.'
        Recovery='Diários completos e identidade do Windows ficam somente no pacote privado de reversão.'
        Limitations=@('Prévia sem assinatura digital. Matriz física Windows 10/11 e NVIDIA/AMD/Intel incompleta.','Itens de catálogo documentam requisitos; não comprovam execução.','Sem instalações, serviços persistentes, tarefas agendadas ou reinício automático.')
    }
    ConvertTo-GoatPublicValue $report
}
function Test-GoatExport {
    param([string]$Directory)
    $manifestPath=Join-Path $Directory 'manifest.json'
    $manifest=Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    if($manifest.SchemaVersion -ne 1 -or @($manifest.Files).Count -lt 3){throw 'Manifesto de exportação inválido.'}
    $names=@($manifest.Files | ForEach-Object { ([string]$_.Path).Replace('/','\') })
    if(@($names|Select-Object -Unique).Count -ne $names.Count){throw 'Manifesto contém caminhos duplicados.'}
    foreach($required in @('report.json','report.html','transactions.csv','private-recovery\session.json','private-recovery\Restore-GOAT.ps1','private-recovery\LEIA-ME.txt')){
        if($names -notcontains $required){throw ('Arquivo obrigatório ausente no manifesto: '+$required)}
    }
    foreach($item in $manifest.Files){
        if($item.Path -match '(^|[/\\])\.\.([/\\]|$)|:' -or [IO.Path]::IsPathRooted($item.Path)){throw 'Caminho inválido no manifesto.'}
        $file=Join-Path $Directory $item.Path
        if(-not [IO.File]::Exists($file) -or (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash -ne $item.Sha256){throw ('Exportação corrompida: '+$item.Path)}
    }
    return $true
}
function Export-GoatService {
    param($Session,[Parameter(Mandatory)][string]$Destination)
    $destinationRoot=[IO.Path]::GetFullPath($Destination)
    [void][IO.Directory]::CreateDirectory($destinationRoot)
    $directory=Join-Path $destinationRoot ('GOAT-'+$Session.Id+'-'+[guid]::NewGuid().ToString('N').Substring(0,8))
    [void][IO.Directory]::CreateDirectory($directory)
    $report=Get-GoatPublicReport $Session
    Write-GoatJson $report (Join-Path $directory 'report.json')
    $encode={param($v) [Net.WebUtility]::HtmlEncode([string]$v)}
    $json=& $encode ($report | ConvertTo-Json -Depth 32)
    $summary=if($report.Demo){'Modo demonstração: nenhuma alteração do Windows foi realizada.'}else{'As alterações registradas e seus resultados aparecem abaixo. Aplicação verificada não comprova ganho de desempenho.'}
    $rows=''
    foreach($transaction in @($report.Transactions)){
        $rows+='<tr><td>'+(& $encode $transaction.Id)+'</td><td>'+(& $encode $transaction.State)+'</td><td>'+(& $encode $transaction.CreatedUtc)+'</td></tr>'
    }
    if(-not $rows){$rows='<tr><td colspan="3">Nenhuma alteração nativa registrada neste atendimento.</td></tr>'}
    $html='<!doctype html><html lang="pt-BR"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>GOAT Tweaks — relatório</title><style>body{background:#111;color:#eee;font:16px Segoe UI,sans-serif;max-width:960px;margin:40px auto;padding:24px;line-height:1.6}h1,h2{color:#e4b95b}table{width:100%;border-collapse:collapse}td,th{padding:12px;text-align:left;border-bottom:1px solid #444;overflow-wrap:anywhere}pre{white-space:pre-wrap;overflow-wrap:anywhere;background:#1c1c1c;padding:20px;border-radius:10px}summary{cursor:pointer;color:#e4b95b}</style><h1>GOAT Tweaks · relatório de atendimento</h1><p>'+(& $encode $summary)+'</p><p><strong>Objetivo:</strong> '+(& $encode $report.Objective)+' · <strong>Estado:</strong> '+(& $encode $report.State)+'</p><h2>Procedimentos registrados</h2><table><thead><tr><th>Transação</th><th>Resultado</th><th>Horário UTC</th></tr></thead><tbody>'+$rows+'</tbody></table><h2>Medições e recuperação</h2><p>Nenhum ganho é atribuído a ajustes sem comparação válida. Sensores de utilização não medem input lag. O anexo técnico registra medições disponíveis e resultados inconclusivos.</p><p>Guarde a pasta <strong>private-recovery</strong> em local privado: contém valores originais e instruções de reversão para o mesmo Windows e usuário. Procedimentos em drivers exigem recuperação manual própria.</p><details><summary>Anexo técnico: inventário, evidências e limitações</summary><pre>'+$json+'</pre></details></html>'
    [IO.File]::WriteAllText((Join-Path $directory 'report.html'),$html,[Text.UTF8Encoding]::new($false))
    $csvPath=Join-Path $directory 'transactions.csv'
    if(@($report.Transactions).Count){$report.Transactions | Select-Object Id,State,CreatedUtc | Export-Csv -LiteralPath $csvPath -NoTypeInformation -Encoding UTF8}
    else{[IO.File]::WriteAllText($csvPath,'"Id","State","CreatedUtc"'+"`r`n",[Text.UTF8Encoding]::new($true))}
    $recovery=Join-Path $directory 'private-recovery'
    [void][IO.Directory]::CreateDirectory($recovery)
    # Only copies GOAT-owned session artifacts; never deletes originals.
    Copy-Item -LiteralPath (Join-Path $Session.Root 'session.json') -Destination (Join-Path $recovery 'session.json')
    $audit=Join-Path $Session.Root 'audit.jsonl'
    if(Test-Path -LiteralPath $audit){Copy-Item -LiteralPath $audit -Destination (Join-Path $recovery 'audit.jsonl')}
    $captureRoot=Join-Path $Session.Root 'captures'
    if(Test-Path -LiteralPath $captureRoot){
        [void][IO.Directory]::CreateDirectory((Join-Path $recovery 'captures'))
        foreach($capture in @($Session.Benchmarks)){
            if($capture.CaptureId -notmatch '^[a-f0-9]{32}$'){throw 'Identificador de captura inválido.'}
            $original=Join-Path $captureRoot ($capture.CaptureId+'.csv')
            if(-not (Test-Path -LiteralPath $original) -or (Get-FileHash -LiteralPath $original -Algorithm SHA256).Hash -ne $capture.Source.Sha256){throw 'Dados originais de captura ausentes ou alterados.'}
            Copy-Item -LiteralPath $original -Destination (Join-Path $recovery ('captures\'+$capture.CaptureId+'.csv'))
        }
    }
    $journalRoot=Join-Path $Session.Root 'transactions'
    if(Test-Path -LiteralPath $journalRoot){
        [void][IO.Directory]::CreateDirectory((Join-Path $recovery 'transactions'))
        foreach($file in @(Get-ChildItem -LiteralPath $journalRoot -Filter '*.json' -File)){
            Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $recovery ('transactions\'+$file.Name))
        }
    }
    if(-not $script:GoatCoreSource){throw 'Fonte de recuperação ausente; nenhuma limpeza foi realizada.'}
    $restore=@'
#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Restore,[string]$TransactionId)
$ErrorActionPreference='Stop'
'@
    $restore+="`r`n"+$script:GoatCoreSource+"`r`n"+@'
$session=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'session.json') -Raw -Encoding UTF8 | ConvertFrom-Json
$session.Root=$PSScriptRoot
$transactions=@(Get-GoatTransactions $session)
$transactions | Select-Object Id,State,CreatedUtc | Format-Table
if($Restore){
    if(-not $TransactionId){throw 'Informe -TransactionId após revisar a lista.'}
    $answer=Read-Host 'Restaurar os valores originais desta transação no mesmo Windows/usuário? Digite RESTAURAR'
    if($answer -cne 'RESTAURAR'){throw 'Restauração cancelada.'}
    Restore-GoatTransaction -Session $session -TransactionId $TransactionId -Consent
}
'@
    [IO.File]::WriteAllText((Join-Path $recovery 'Restore-GOAT.ps1'),$restore,[Text.UTF8Encoding]::new($true))
    [IO.File]::WriteAllText((Join-Path $recovery 'LEIA-ME.txt'),'PRIVADO: contém identidade do Windows e valores originais. Não publique. Execute Restore-GOAT.ps1 para listar transações. Use -Restore -TransactionId ID para solicitar reversão verificada. Drivers exigem recuperação manual. Preserve também a sessão original.',[Text.UTF8Encoding]::new($true))
    $files=@(Get-ChildItem -LiteralPath $directory -Recurse -File | ForEach-Object {
        [pscustomobject]@{Path=$_.FullName.Substring($directory.Length+1);Sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash;Size=$_.Length}
    })
    Write-GoatJson ([pscustomobject]@{SchemaVersion=1;Session=$Session.Id;Files=$files}) (Join-Path $directory 'manifest.json')
    [void](Test-GoatExport $directory)
    $Session.Exports+=$directory;Save-GoatSession $Session
    return $directory
}
function Complete-GoatSession {
    param($Session,[string]$Destination,[switch]$Consent)
    if($Session.State -eq 'Finalized'){
        [void](Test-GoatExport $Session.FinalExport)
        return $Session.FinalExport
    }
    if(-not $Consent){throw 'Revise o atendimento e confirme a finalização.'}
    $mutex=[Threading.Mutex]::new($false,'Local\GOAT-Tweaks-Actions');$locked=$false
    try {
        try{$locked=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$locked=$true}
        if(-not $locked){throw 'Outra operação GOAT está ativa.'}
        $unresolved=@(Get-GoatTransactions $Session | Where-Object State -in @('Prepared','Applying','Restoring','RestoreFailed'))
        if($unresolved.Count){throw 'Finalização bloqueada por transação pendente; preserve o diário e restaure primeiro.'}
        $Session.State='Finalizing';Save-GoatSession $Session
        try {
            $export=Export-GoatService $Session $Destination
            $Session.State='Finalized';$Session.FinalExport=$export;Save-GoatSession $Session
        } catch {
            $Session.State='Open';Save-GoatSession $Session
            throw
        }
        # Portable application: nothing installed, no services/tasks/helpers to delete.
        return $export
    } finally {if($locked){$mutex.ReleaseMutex()};$mutex.Dispose()}
}
