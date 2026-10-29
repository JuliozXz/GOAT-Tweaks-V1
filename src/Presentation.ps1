# Human-readable read-only projections for the technician. PowerShell 5.1.
# Values are always treated as text, never evaluated as commands.
function Get-GoatViewProperty {
    param($Value,[string]$Name)
    if($null -eq $Value){return}
    if($Value -is [Collections.IDictionary]){if($null -ne $Value[$Name]){return $Value[$Name]};return}
    $property=$Value.PSObject.Properties[$Name]
    if($null -ne $property -and $null -ne $property.Value){return $property.Value}
    return
}
function Format-GoatViewValue {
    param($Value,[string]$Unit)
    if($null -eq $Value -or ($Value -is [string] -and [string]::IsNullOrWhiteSpace($Value))){return 'N/D — não confirmado'}
    if($Value -is [bool]){if($Value){return 'Sim'}else{return 'Não'}}
    if($Value -is [double] -or $Value -is [single] -or $Value -is [decimal]){
        $number=[double]$Value
        if([double]::IsNaN($number) -or [double]::IsInfinity($number)){return 'N/D — valor inválido'}
        $text=$number.ToString('0.###',[Globalization.CultureInfo]::GetCultureInfo('pt-BR'))
    }else{$text=[string]$Value}
    if($text -in @('UNKNOWN','UNAVAILABLE','NOT_MEASURED','NOT_CHECKED')){
        $translated=switch($text){'UNKNOWN'{'Desconhecido'}'UNAVAILABLE'{'Indisponível'}'NOT_MEASURED'{'Não medido'}'NOT_CHECKED'{'Não verificado'}}
        return ($translated+' ('+$text+')')
    }
    if($Unit){return ($text+' '+$Unit)}
    return $text
}
function Get-GoatViewLabel {
    param([string]$Name)
    $labels=@{Name='Nome';Title='Título';State='Estado';Status='Status';Source='Fonte';Confidence='Confiança';Note='Observação';Reason='Motivo';Caption='Sistema';Version='Versão';Build='Build';Architecture='Arquitetura';Manufacturer='Fabricante';Model='Modelo';Cores='Núcleos';Threads='Threads';LogicalProcessors='Processadores lógicos';TotalGB='Total (GiB)';AvailableGB='Disponível (GiB)';UsedPercent='Uso (%)';FreePercent='Livre (%)';SizeGB='Capacidade (GiB)';FreeGB='Livre (GiB)';HealthStatus='Saúde';MediaType='Tipo de mídia';BusType='Barramento';OperationalStatus='Estado operacional';ReadOnly='Somente leitura';Demo='Demonstração';Pending='Pendente';Reasons='Motivos';OS='Windows';CPU='Processador';Memory='Memória';Disks='Armazenamento';PhysicalDisks='Discos físicos';Network='Rede';Reboot='Reinicialização';SourceIssues='Limitações das fontes';RemoteContext='Contexto de acesso remoto';Apps='Aplicativos';Startup='Inicialização';Objective='Objetivo';Risk='Risco';Recommendation='Orientação';Execution='Execução';PerformanceEvidence='Evidência de desempenho';DriverVersion='Versão do driver';DriverDate='Data do driver';DriverProvider='Fornecedor do driver';IsRemote='Sessão remota';IsRemoteOrUncertain='Remoto ou não confirmado';RemoteProcessNames='Processos remotos detectados';Services='Serviços';PowerPlan='Plano de energia';WindowsSettings='Preferências Windows'}
    if($labels.ContainsKey($Name)){return $labels[$Name]}
    return $Name
}
function Format-GoatHardwareView {
    param([string]$Title='Informações',$Value,[switch]$IncludeTechnicalJson)
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $lines.Add($Title.ToUpperInvariant());$lines.Add('')
    function Add-GoatViewLines {
        param($Object,[int]$Depth=0,[string]$Label)
        $indent='  '*$Depth
        if($Depth -gt 5){$lines.Add($indent+'Mais detalhes disponíveis no relatório técnico.');return}
        if($null -eq $Object -or $Object -is [string] -or $Object -is [ValueType]){
            $prefix=if($Label){(Get-GoatViewLabel $Label)+': '}else{''}
            $lines.Add($indent+$prefix+(Format-GoatViewValue $Object));return
        }
        if($Label){$lines.Add($indent+(Get-GoatViewLabel $Label));$Depth++;$indent='  '*$Depth}
        if($Object -is [Collections.IDictionary]){
            foreach($key in $Object.Keys){Add-GoatViewLines $Object[$key] $Depth ([string]$key)}
        }elseif($Object -is [Collections.IEnumerable]){
            $items=@($Object)
            if($items.Count -eq 0){$lines.Add($indent+'Nenhum registro disponível.');return}
            $index=0
            foreach($item in $items){
                if($index -ge 20){$lines.Add($indent+($items.Count-$index)+' registros adicionais no relatório técnico.');break}
                $index++;$lines.Add($indent+'• Registro '+$index);Add-GoatViewLines $item ($Depth+1)
            }
        }else{
            foreach($property in $Object.PSObject.Properties){Add-GoatViewLines $property.Value $Depth $property.Name}
        }
    }
    Add-GoatViewLines $Value
    if($IncludeTechnicalJson){$lines.Add('');$lines.Add('ANEXO TÉCNICO (JSON)');$lines.Add(($Value|ConvertTo-Json -Depth 12))}
    $lines -join "`r`n"
}
function Format-GoatGpuView {
    param($GpuCenter)
    if($null -eq $GpuCenter){return "GPU CENTER`r`nInventário ainda indisponível. Nenhuma capacidade ou métrica foi presumida."}
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('GPU CENTER');$lines.Add('Diagnóstico somente leitura · '+(Format-GoatViewValue (Get-GoatViewProperty $GpuCenter Status)))
    $lines.Add('Amostra UTC: '+(Format-GoatViewValue (Get-GoatViewProperty $GpuCenter SampleUtc)));$lines.Add('')
    $devices=@(Get-GoatViewProperty $GpuCenter Devices)
    if($devices.Count -eq 0){$lines.Add('Nenhuma GPU identificada com confiança. Consulte os avisos das fontes.')}
    foreach($device in $devices){
        $lines.Add('• '+(Format-GoatViewValue (Get-GoatViewProperty $device Name)))
        foreach($entry in @(@('Fabricante','Vendor'),@('PCI VEN','VendorId'),@('PCI DEV','DeviceId'),@('Driver instalado','DriverVersion'),@('Data do driver','DriverDate'),@('Fornecedor','DriverProvider'),@('Driver assinado','DriverSigned'),@('Arquivo INF','DriverInf'),@('Tipo iGPU/dGPU/eGPU','GpuType'),@('Confiança','Confidence'),@('Fonte de inventário','Source'),@('Download oficial','DriverSource'),@('Versão mais recente','LatestDriverStatus'))){$lines.Add('  '+$entry[0]+': '+(Format-GoatViewValue (Get-GoatViewProperty $device $entry[1])))}
        $mode=Get-GoatViewProperty $device CurrentControllerMode
        if($mode){$lines.Add('  Modo reportado pelo controlador: '+(Format-GoatViewValue (Get-GoatViewProperty $mode Width))+' × '+(Format-GoatViewValue (Get-GoatViewProperty $mode Height))+' · '+(Format-GoatViewValue (Get-GoatViewProperty $mode RefreshRateHz) 'Hz'));$lines.Add('  Associação deste modo a um monitor: '+(Format-GoatViewValue (Get-GoatViewProperty $mode MonitorAssociation)))}
        $lines.Add('  VRAM dedicada: N/D — AdapterRAM do WMI não comprova capacidade real.');$lines.Add('')
    }
    $system=Get-GoatViewProperty $GpuCenter System
    $lines.Add('OEM / NOTEBOOK')
    $lines.Add('Fabricante: '+(Format-GoatViewValue (Get-GoatViewProperty $system Manufacturer))+' · Modelo: '+(Format-GoatViewValue (Get-GoatViewProperty $system Model)))
    $lines.Add('Notebook: '+(Format-GoatViewValue (Get-GoatViewProperty $system IsNotebook)))
    $lines.Add('Suporte OEM: '+(Format-GoatViewValue (Get-GoatViewProperty $system OemDriverSource)))
    $lines.Add('Em notebook, conferir driver homologado e vídeo híbrido antes de escolher pacote genérico.');$lines.Add('')
    $lines.Add('MONITORES')
    $monitors=@(Get-GoatViewProperty $GpuCenter Monitors)
    if($monitors.Count -eq 0){$lines.Add('Identificação EDID indisponível. Frequência, modos e VRR não confirmados.')}
    foreach($monitor in $monitors){$lines.Add('• '+(Format-GoatViewValue (Get-GoatViewProperty $monitor Name))+' · '+(Format-GoatViewValue (Get-GoatViewProperty $monitor Manufacturer)));$lines.Add('  Frequência confirmada: '+(Format-GoatViewValue (Get-GoatViewProperty $monitor RefreshRateHz) 'Hz'));$lines.Add('  Fonte: '+(Format-GoatViewValue (Get-GoatViewProperty $monitor Source)));$lines.Add('  '+(Format-GoatViewValue (Get-GoatViewProperty $monitor Note)))}
    $lines.Add('');$lines.Add('TELEMETRIA')
    $telemetry=Get-GoatViewProperty $GpuCenter Telemetry
    $lines.Add('Disponibilidade: '+(Format-GoatViewValue (Get-GoatViewProperty $telemetry Status)))
    $metricLabels=@{GpuTotalLoad='Carga total GPU';CoreClock='Clock do núcleo';MemoryClock='Clock da memória';DedicatedVramUsed='VRAM dedicada usada';SharedVramUsed='Memória compartilhada usada';Temperature='Temperatura';Hotspot='Hotspot';Power='Potência';Throttling='Limitação térmica/elétrica'}
    foreach($metric in @(Get-GoatViewProperty $telemetry Metrics)){
        $name=[string](Get-GoatViewProperty $metric Name);$label=if($metricLabels.ContainsKey($name)){$metricLabels[$name]}else{$name}
        $lines.Add('• '+$label+': '+(Format-GoatViewValue (Get-GoatViewProperty $metric Value) ([string](Get-GoatViewProperty $metric Unit))))
    }
    $engines=@(Get-GoatViewProperty $telemetry EngineLoads)
    if($engines.Count -gt 0){$lines.Add('Motores do Windows: '+$engines.Count+' instâncias disponíveis; não somadas como carga total.');foreach($engine in @($engines|Select-Object -First 8)){$lines.Add('  '+(Format-GoatViewValue (Get-GoatViewProperty $engine Instance))+': '+(Format-GoatViewValue (Get-GoatViewProperty $engine Value) '%'))}}
    $lines.Add('FPS e input lag não foram medidos por este inventário.');$lines.Add('')
    $remote=Get-GoatViewProperty $GpuCenter RemoteContext
    $lines.Add('Acesso remoto: '+(Format-GoatViewValue (Get-GoatViewProperty $remote State)))
    foreach($warning in @(Get-GoatViewProperty $GpuCenter Warnings)){$lines.Add('Aviso: '+[string]$warning)}
    foreach($advice in @(Get-GoatViewProperty $GpuCenter Recommendations)){$lines.Add('Orientação: '+[string]$advice)}
    $lines -join "`r`n"
}
function Format-GoatGpuGuides {
    param([AllowEmptyCollection()][object[]]$Guides=@())
    $lines=New-Object 'System.Collections.Generic.List[string]';$lines.Add('GUIAS GPU · PROCEDIMENTOS MANUAIS');$lines.Add('Consultar um guia não executa suas instruções.');$lines.Add('')
    foreach($guide in $Guides){
        $lines.Add((Format-GoatViewValue (Get-GoatViewProperty $guide Title))+' ['+(Format-GoatViewValue (Get-GoatViewProperty $guide Id))+']')
        $lines.Add('Estado: '+(Format-GoatViewValue (Get-GoatViewProperty $guide Status))+' · Risco: '+(Format-GoatViewValue (Get-GoatViewProperty $guide Risk)))
        $reason=Get-GoatViewProperty $guide BlockReason;if($reason){$lines.Add('BLOQUEIO: '+[string]$reason)}
        $number=0;foreach($step in @(Get-GoatViewProperty $guide Steps)){$number++;$lines.Add($number.ToString()+'. '+[string]$step)}
        $lines.Add('Recuperação: '+(Format-GoatViewValue (Get-GoatViewProperty $guide Recovery)))
        $source=Get-GoatViewProperty $guide Source;if($source){$lines.Add('Fonte oficial: '+[string]$source)}
        $lines.Add('')
    }
    if($Guides.Count -eq 0){$lines.Add('Nenhum guia disponível para os dados atuais.')}
    $lines -join "`r`n"
}
function Format-GoatProfileView {
    param($Advice)
    $lines=New-Object 'System.Collections.Generic.List[string]';$lines.Add('PRÉVIA DO PERFIL POR JOGO');$lines.Add('Estado: '+(Format-GoatViewValue (Get-GoatViewProperty $Advice Status)));$lines.Add('Benefício medido: '+(Format-GoatViewValue (Get-GoatViewProperty $Advice MeasuredBenefit)));$lines.Add('')
    $conflicts=@(Get-GoatViewProperty $Advice Conflicts)
    if($conflicts.Count -gt 0){$lines.Add('CONFLITOS / CONFIRMAÇÕES NECESSÁRIAS');foreach($conflict in $conflicts){$lines.Add('• '+[string]$conflict)};$lines.Add('')}
    $lines.Add('ORIENTAÇÕES CONTEXTUAIS');foreach($recommendation in @(Get-GoatViewProperty $Advice Recommendations)){$lines.Add('• '+[string]$recommendation)}
    $lines.Add('');$lines.Add((Format-GoatViewValue (Get-GoatViewProperty $Advice Note)))
    $lines.Add('Perfil local de orientação: nenhuma configuração do Windows, driver ou jogo foi aplicada.')
    $lines -join "`r`n"
}
function Format-GoatCatalogView {
    param($Item)
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $lines.Add((Format-GoatViewValue (Get-GoatViewProperty $Item title)).ToUpperInvariant());$lines.Add('ID: '+(Format-GoatViewValue (Get-GoatViewProperty $Item id)))
    foreach($entry in @(@('Categoria','category'),@('O que faz','short_explanation'),@('Como funciona','how_it_works'),@('Benefício possível','potential_benefit'),@('Quando considerar','when_to_use'),@('Quando evitar','when_not_to_use'),@('Risco / trade-off','risk'),@('Evidência','evidence_level'),@('Elegibilidade','eligibility'),@('Estado de implementação','implementation_status'),@('Classe de execução','execution_class'),@('Reinicialização','reboot_required'),@('Como verificar','verification'),@('Restauração do original','rollback'))){$lines.Add('');$lines.Add($entry[0]+': '+(Format-GoatViewValue (Get-GoatViewProperty $Item $entry[1])))}
    $lines.Add('');$lines.Add('EXECUÇÃO DESABILITADA');$lines.Add('apply_allowed: false');$lines.Add('Este registro é documentação consultiva. Texto importado não autoriza nem executa comandos.')
    $lines.Add('');$lines.Add('PROVENIÊNCIA');$lines.Add('Documento: '+(Format-GoatViewValue (Get-GoatViewProperty $Item source_path)));$lines.Add('SHA256: '+(Format-GoatViewValue (Get-GoatViewProperty $Item source_sha256)))
    foreach($source in @(Get-GoatViewProperty $Item sources)){$lines.Add('Fonte: '+[string]$source)}
    $related=@(Get-GoatViewProperty $Item related_ids);if($related.Count){$lines.Add('IDs relacionados: '+($related -join ', '))}
    $lines -join "`r`n"
}
function Format-GoatBenchmarkView {
    param([AllowEmptyCollection()][object[]]$Captures=@(),$Comparison)
    $lines=New-Object 'System.Collections.Generic.List[string]';$lines.Add('BENCHMARKS · DADOS IMPORTADOS');$lines.Add('Capturas disponíveis: '+$Captures.Count);$lines.Add('')
    if($Captures.Count -eq 0){$lines.Add('FPS médio, 1% low e frametime: não medidos. Importe capturas originais antes de comparar.')}
    foreach($capture in $Captures){
        $lines.Add('• '+(Format-GoatViewValue (Get-GoatViewProperty $capture ConditionLabel))+' — passada '+(Format-GoatViewValue (Get-GoatViewProperty $capture PassNumber)))
        $metrics=Get-GoatViewProperty $capture Metrics
        foreach($entry in @(@('FPS médio','AverageFps','FPS'),@('1% low','OnePercentLowFps','FPS'),@('Frametime p50','FrameTimeP50Ms','ms'),@('Frametime p95','FrameTimeP95Ms','ms'),@('Frametime p99','FrameTimeP99Ms','ms'),@('Duração','DurationSeconds','s'),@('Intervalos de quadros','SampleCount',''))){$lines.Add('  '+$entry[0]+': '+(Format-GoatViewValue (Get-GoatViewProperty $metrics $entry[1]) $entry[2]))}
        $lines.Add('  Método 1% low: '+(Format-GoatViewValue (Get-GoatViewProperty $metrics OnePercentLowMethod)))
        $lines.Add('  Método percentis: '+(Format-GoatViewValue (Get-GoatViewProperty $metrics PercentileMethod)))
        $source=Get-GoatViewProperty $capture Source;$hash=Get-GoatViewProperty $source Sha256;if(-not $hash){$hash=Get-GoatViewProperty $capture SourceSha256}
        $lines.Add('  SHA256 da captura: '+(Format-GoatViewValue $hash));$lines.Add('  Coluna e unidade: '+(Format-GoatViewValue (Get-GoatViewProperty $source Column))+' · '+(Format-GoatViewValue (Get-GoatViewProperty $source Units)))
        $conditions=Get-GoatViewProperty $capture Conditions
        foreach($entry in @(@('Jogo','Game'),@('Cena','Scene'),@('Resolução','Resolution'),@('Preset','Preset'),@('API','Api'),@('Driver','Driver'))){$value=Get-GoatViewProperty $conditions $entry[1];if($value){$lines.Add('  '+$entry[0]+': '+[string]$value)}}
        $lines.Add('')
    }
    if($Comparison){
        $lines.Add('COMPARAÇÃO ANTES / DEPOIS');$lines.Add('Resultado: '+(Format-GoatViewValue (Get-GoatViewProperty $Comparison Status)));$lines.Add('Motivo: '+(Format-GoatViewValue (Get-GoatViewProperty $Comparison Reason)))
        $lines.Add('Passadas: baseline '+(Format-GoatViewValue (Get-GoatViewProperty $Comparison BaselinePassCount))+' · depois '+(Format-GoatViewValue (Get-GoatViewProperty $Comparison AfterPassCount)))
        foreach($metric in @(Get-GoatViewProperty $Comparison Metrics)){
            $name=[string](Get-GoatViewProperty $metric Name);$label=switch($name){AverageFps{'FPS médio'}OnePercentLowFps{'1% low'}FrameTimeP50Ms{'Frametime p50'}FrameTimeP95Ms{'Frametime p95'}FrameTimeP99Ms{'Frametime p99'}default{$name}}
            $before=Get-GoatViewProperty $metric Before;$after=Get-GoatViewProperty $metric After;$unit=[string](Get-GoatViewProperty $metric Units)
            $lines.Add('• '+$label+': mediana antes '+(Format-GoatViewValue (Get-GoatViewProperty $before Median) $unit)+' → depois '+(Format-GoatViewValue (Get-GoatViewProperty $after Median) $unit))
            $delta=Get-GoatViewProperty $metric RelativeDeltaPercent;if($null -ne $delta){$lines.Add('  Diferença observada: '+(Format-GoatViewValue $delta '%')+' · '+(Format-GoatViewValue (Get-GoatViewProperty $metric ObservedDirection)))}
        }
        foreach($issue in @(Get-GoatViewProperty $Comparison ConditionsIssues)){$lines.Add('Condição a revisar: '+[string]$issue)}
        $lines.Add('Método declarado: '+(Format-GoatViewValue (Get-GoatViewProperty $Comparison Method)))
    }
    $lines.Add('');$lines.Add('Comparar a mesma cena/configuração e 3–5 passadas independentes por condição. Ampliar se a variação for alta.');$lines.Add('Input lag e latência de rede: não medidos por métricas de frametime. Nenhum ganho universal é prometido.')
    $lines -join "`r`n"
}
function Format-GoatHistoryView {
    param($Session,[AllowEmptyCollection()][object[]]$Transactions=@())
    $lines=New-Object 'System.Collections.Generic.List[string]';$lines.Add('HISTÓRICO / RESTAURAÇÃO');$lines.Add('Sessão: '+(Format-GoatViewValue (Get-GoatViewProperty $Session Id)));$lines.Add('Estado: '+(Format-GoatViewValue (Get-GoatViewProperty $Session State)));$lines.Add('')
    if($Transactions.Count -eq 0){$lines.Add('Nenhuma transação nativa registrada nesta sessão.')}
    foreach($transaction in $Transactions){
        $lines.Add('• Transação '+(Format-GoatViewValue (Get-GoatViewProperty $transaction Id))+' · '+(Format-GoatViewValue (Get-GoatViewProperty $transaction State)))
        $lines.Add('  Horário UTC: '+(Format-GoatViewValue (Get-GoatViewProperty $transaction CreatedUtc)))
        foreach($step in @(Get-GoatViewProperty $transaction Steps)){$lines.Add('  Ação '+(Format-GoatViewValue (Get-GoatViewProperty $step Id))+': '+(Format-GoatViewValue (Get-GoatViewProperty $step State)));$errorText=Get-GoatViewProperty $step Error;if($errorText){$lines.Add('  Erro: '+[string]$errorText)}}
    }
    $lines.Add('');$lines.Add('EVENTOS DO ATENDIMENTO')
    $events=@(Get-GoatViewProperty $Session Events)
    if($events.Count -eq 0){$lines.Add('Nenhum evento registrado.')}
    foreach($event in $events){$lines.Add('• '+(Format-GoatViewValue (Get-GoatViewProperty $event Utc))+' · '+(Format-GoatViewValue (Get-GoatViewProperty $event Kind))+' · '+(Format-GoatViewValue (Get-GoatViewProperty $event Message)))}
    $lines.Add('');$lines.Add('Pasta privada de recuperação: '+(Format-GoatViewValue (Get-GoatViewProperty $Session Root)));$lines.Add('Restaurar original recupera os valores capturados, inclusive ausência. É diferente de escolher Desativar.');$lines.Add('Drivers e perfis alterados manualmente têm recuperação separada. DEMO registra somente simulação.');$lines.Add('Se houver falha na reversão, preserve os diários e resolva a pendência antes de novas ações.')
    $lines -join "`r`n"
}
