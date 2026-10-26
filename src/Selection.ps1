# Hardware/context based convenience selection; no commands or system writes.
# RAM and pressure thresholds are GOAT review policy, not a benchmark result.

function Get-GoatSelectionProperty {
    param($Object,[string]$Name,$Default=$null)
    if($Object -is [Collections.IDictionary]){if($Object.Contains($Name)){return $Object[$Name]};return $Default}
    if($null -ne $Object -and $Object.PSObject.Properties[$Name]){return $Object.PSObject.Properties[$Name].Value}
    return $Default
}

function Get-GoatSelectionReading {
    param($Scan,[string]$Key)
    $advanced=Get-GoatSelectionProperty $Scan 'AdvancedState'
    $readings=Get-GoatSelectionProperty $advanced 'Readings'
    return Get-GoatSelectionProperty $readings $Key
}

function ConvertTo-GoatSelectionNumber {
    param($Value)
    if($null -eq $Value -or $Value -is [bool]){return $null}
    $number=0.0
    if([double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$number)-and -not [double]::IsNaN($number)-and -not [double]::IsInfinity($number)){return $number}
    return $null
}

function Get-GoatMachineProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Scan)
    $reasons=New-Object 'System.Collections.Generic.List[string]'
    $memory=Get-GoatSelectionProperty $Scan 'Memory'
    $memoryGB=ConvertTo-GoatSelectionNumber (Get-GoatSelectionProperty $memory 'TotalGB')
    $availableGB=ConvertTo-GoatSelectionNumber (Get-GoatSelectionProperty $memory 'AvailableGB')
    $knownMemory=$null -ne $memoryGB -and $memoryGB -gt 0
    if(-not $knownMemory){$memoryGB=$null}
    $knownAvailable=$knownMemory -and $null -ne $availableGB -and $availableGB -ge 0 -and $availableGB -le $memoryGB
    if(-not $knownAvailable){$availableGB=$null}
    $lowMemory=$null; $pressure=$null
    if($knownMemory){$lowMemory=($memoryGB -le 8);if($lowMemory){$reasons.Add('RAM total de até 8 GB: faixa reduzida segundo a política de revisão GOAT.')}}
    if($knownAvailable){$pressure=($availableGB -le 1 -or ($availableGB/$memoryGB)-le 0.15);if($pressure){$reasons.Add('Pouca RAM disponível nesta amostra (até 1 GB ou até 15% do total); não é medição de paginação ou gargalo.')}}

    $cpu=Get-GoatSelectionProperty $Scan 'CPU'
    $logical=ConvertTo-GoatSelectionNumber (Get-GoatSelectionProperty $cpu 'Threads')
    $cores=ConvertTo-GoatSelectionNumber (Get-GoatSelectionProperty $cpu 'Cores')
    $knownLogical=$null -ne $logical -and $logical -ge 1 -and [math]::Floor($logical)-eq $logical
    if(-not $knownLogical){$logical=$null}
    if($null -eq $cores -or $cores -lt 1 -or [math]::Floor($cores)-ne $cores){$cores=$null}

    $storage=Get-GoatSelectionReading $Scan 'storage'
    $storageValue=Get-GoatSelectionProperty $storage 'Value'
    $storageAvailable=(Get-GoatSelectionProperty $storage 'Available')-is [bool] -and [bool](Get-GoatSelectionProperty $storage 'Available')
    $disks=@(Get-GoatSelectionProperty $storageValue 'Disks' @())
    $slowStorage=$null; $knownStorage=$false; $knownSlowStorage=$false
    if($storageAvailable -and $disks.Count -gt 0){
        $types=@($disks|ForEach-Object{[string](Get-GoatSelectionProperty $_ 'MediaType' 'Unknown')})
        $knownTypes=@($types|Where-Object{$_ -in @('HDD','SSD','SCM')})
        $knownStorage=$knownTypes.Count -eq $types.Count
        $systemDisks=@($disks|Where-Object{(Get-GoatSelectionProperty $_ 'IsSystem')-is [bool] -and [bool](Get-GoatSelectionProperty $_ 'IsSystem')})
        if($systemDisks.Count -eq 1 -and (Get-GoatSelectionProperty $systemDisks[0] 'MediaType')-in @('HDD','SSD','SCM')){
            $slowStorage=(Get-GoatSelectionProperty $systemDisks[0] 'MediaType')-eq 'HDD';$knownSlowStorage=$true
        }
        elseif($knownStorage -and @($types|Where-Object{$_ -ne 'HDD'}).Count -eq 0){$slowStorage=$true;$knownSlowStorage=$true}
        elseif($knownStorage -and @($types|Where-Object{$_ -eq 'HDD'}).Count -eq 0){$slowStorage=$false;$knownSlowStorage=$true}
        if($slowStorage -eq $true){$reasons.Add('Inventário elegível indica HDD; presença de HDD não mede velocidade nem assegura ganho com ajustes visuais.')}
        elseif($knownStorage -and -not $knownSlowStorage){$reasons.Add('Mídias HDD/SSD mistas sem mapear o disco do Windows/jogo; impacto de armazenamento permanece desconhecido.')}
    }
    if(-not $knownStorage){$reasons.Add('Tipo de armazenamento não confirmado integralmente; modelo do disco não é usado para deduzir HDD/SSD.')}

    $power=Get-GoatSelectionProperty $Scan 'Power'
    $laptop=Get-GoatSelectionProperty $power 'IsLaptop'
    $knownLaptop=$laptop -is [bool];if(-not $knownLaptop){$laptop=$null}
    $battery=Get-GoatSelectionReading $Scan 'battery'
    $batteryValue=Get-GoatSelectionProperty $battery 'Value'
    $onBattery=$null;$onAC=$null
    if((Get-GoatSelectionProperty $battery 'Available')-is [bool] -and [bool](Get-GoatSelectionProperty $battery 'Available')){
        $onBattery=Get-GoatSelectionProperty $batteryValue 'OnBattery';if($onBattery-isnot [bool]){$onBattery=$null}
        $onAC=Get-GoatSelectionProperty $batteryValue 'OnAC';if($onAC-isnot [bool]){$onAC=$null}
    }
    $knownPower=$onBattery-is [bool] -and $onAC-is [bool]
    if($onBattery-eq $true){$reasons.Add('Energia da bateria confirmada: nenhuma preferência de alto consumo é pré-selecionada.')}

    $network=Get-GoatSelectionProperty $Scan 'Network'
    $networkErrors=@((Get-GoatSelectionProperty $Scan 'Errors' @())|Where-Object{$_ -match 'Win32_NetworkAdapter|Get-NetAdapter'})
    $hasAdapter=$null;$knownNetwork=$false
    if($null -ne $network -and $networkErrors.Count -eq 0){
        $adapters=@($network)
        $statuses=@($adapters|ForEach-Object{[string](Get-GoatSelectionProperty $_ 'Status')})
        if(@($statuses|Where-Object{$_ -in @('Up','Connected','Conectado','2')}).Count -gt 0){$hasAdapter=$true;$knownNetwork=$true}
        elseif(@($statuses|Where-Object{$_ -notin @('Disconnected','Desconectado','Down','Mídia desconectada','Hardware ausente','Hardware desativado','0','4','5','7')}).Count -eq 0){$hasAdapter=$false;$knownNetwork=$true}
    }
    if(-not $knownMemory){$reasons.Add('RAM total desconhecida: políticas dependentes de memória não autorizam pré-seleção.')}
    $memoryText=if($knownMemory){'{0:0.#} GB RAM' -f $memoryGB}else{'RAM não informada'}
    if($knownAvailable){$memoryText+='; {0:0.#} GB disponíveis' -f $availableGB}
    $cpuText=if($knownLogical){'{0} processadores lógicos' -f $logical}else{'topologia não informada'}
    $storageText=if($slowStorage-eq $true){'HDD declarado'}elseif($slowStorage-eq $false){'mídia SSD/SCM declarada'}else{'mídia/volume a confirmar'}
    $reasons.Add('Pré-seleção é uma política de conveniência baseada na amostra; capacidade de hardware não garante FPS, latência ou estabilidade.')
    return [pscustomobject]@{
        Summary=($memoryText+' · '+$cpuText+' · '+$storageText);Reasons=@($reasons.ToArray())
        MemoryGB=$memoryGB;AvailableMemoryGB=$availableGB;MemoryPressure=$pressure;LowMemory=$lowMemory;SlowStorage=$slowStorage
        IsLaptop=$laptop;OnBattery=$onBattery;OnAC=$onAC;HasConnectedAdapter=$hasAdapter;LogicalProcessors=$logical;PhysicalCores=$cores
        KnownMemory=$knownMemory;KnownAvailableMemory=$knownAvailable;KnownMemoryPressure=$knownAvailable;KnownStorage=$knownStorage;KnownSlowStorage=$knownSlowStorage
        KnownLaptop=$knownLaptop;KnownPower=$knownPower;KnownNetwork=$knownNetwork;KnownLogicalProcessors=$knownLogical
    }
}

function Set-GoatTweakRecommendations {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][AllowEmptyCollection()][object[]]$Tweaks,[Parameter(Mandatory=$true)]$Scan,
        [ValidateSet('Equilibrado','Jogos')][string]$Profile='Equilibrado',[bool]$PreserveCapture=$true)
    $machine=Get-GoatMachineProfile -Scan $Scan
    $items=New-Object 'System.Collections.Generic.List[object]'
    $supported=(Get-GoatSelectionProperty (Get-GoatSelectionProperty $Scan 'OS') 'Supported')-is [bool] -and [bool](Get-GoatSelectionProperty (Get-GoatSelectionProperty $Scan 'OS') 'Supported')
    $fallbackPolicies=@{'game-mode'='Gaming';'capture-off'='Gaming';'memory-compression'='MemoryPressure';'visual-effects'='LowMemory';'tcp-normal'='NetworkRepair';'rss-on'='NetworkRepair'}
    foreach($tweak in $Tweaks){
        $copy=[ordered]@{};foreach($property in $tweak.PSObject.Properties){$copy[$property.Name]=$property.Value}
        $id=[string](Get-GoatSelectionProperty $tweak 'Id')
        $policy=[string](Get-GoatSelectionProperty $tweak 'SelectionPolicy' '')
        if(-not $policy){if($fallbackPolicies.ContainsKey($id)){$policy=$fallbackPolicies[$id]}else{$policy='Manual'}}
        $copy.SelectionPolicy=$policy;$copy.Recommended=$false;$copy.RecommendationReason='Preferência manual; não existe evidência suficiente para pré-seleção automática.';$copy.Confidence='Baixa'
        $direction=[string](Get-GoatSelectionProperty $tweak 'DesiredState' (Get-GoatSelectionProperty $tweak 'RecommendedDirection' 'On'))
        $copy.DesiredState=$direction
        $available=Get-GoatSelectionProperty $tweak 'Available'
        $state=[string](Get-GoatSelectionProperty $tweak 'State')
        $configured=$null
        if($direction-eq 'On'){
            $configured=Get-GoatSelectionProperty $tweak 'OnState'
            if($configured-isnot [bool]){if($state-eq 'Aplicado'){$configured=$true}elseif($state-eq 'Disponível'){$configured=$false}else{$configured=$null}}
        }
        elseif($direction-eq 'Off'){$configured=Get-GoatSelectionProperty $tweak 'OffState';if($configured-isnot [bool]){$configured=$null}}
        if($available-isnot [bool] -or -not $available -or $state-eq 'Indisponível'){$copy.RecommendationReason='Opção indisponível ou estado não confirmado nesta leitura.';$copy.Confidence='Indisponível'}
        elseif($configured-is [bool] -and $configured){$copy.RecommendationReason='A configuração alvo '+$direction+' já foi confirmada; não é necessário reaplicá-la.';$copy.Confidence='Alta'}
        elseif(-not $supported){$copy.RecommendationReason='Windows fora da matriz de aplicação ou suporte não confirmado.';$copy.Confidence='Indisponível'}
        elseif($configured-isnot [bool]){$copy.RecommendationReason='Estado atual do alvo '+$direction+' desconhecido; revise antes de selecionar.';$copy.Confidence='Indisponível'}
        elseif($direction-eq 'Off' -and (Get-GoatSelectionProperty $tweak 'CanDisable')-ne $true){$copy.RecommendationReason='Desativação indisponível; não selecionar um alvo Off sem suporte confirmado.';$copy.Confidence='Indisponível'}
        elseif($id-eq 'power-high' -or $id-match '^power-.*performance'){
            $copy.RecommendationReason=if($machine.OnBattery-eq $true){'Alto desempenho permanece manual e não é sugerido na bateria: aumenta consumo/temperatura.'}else{'Plano de alto desempenho permanece manual; valide consumo, temperatura e a carga mesmo conectado à energia.'}
        }
        else{
            switch($policy){
                'Gaming'{
                    if($Profile-ne 'Jogos'){$copy.RecommendationReason='Apenas o perfil Jogos autoriza esta preferência; Equilibrado preserva a escolha atual.'}
                    elseif($id-match 'capture|game.?dvr|record|grava'){
                        if($PreserveCapture){$copy.RecommendationReason='Gravação e clipes foram preservados pela preferência do técnico.'}
                        else{$copy.Recommended=$true;$copy.Confidence='Alta';$copy.RecommendationReason='Perfil Jogos com preservação de captura desmarcada: preferência explícita para desligar captura em segundo plano.'}
                    }
                    else{$copy.Recommended=$true;$copy.Confidence='Moderada';$copy.RecommendationReason='Preferência explícita do perfil Jogos, com estado alvo ainda não aplicado; efeito depende do jogo e do Windows.'}
                }
                'MemoryPressure'{
                    $reading=Get-GoatSelectionReading $Scan 'memory-compression'
                    $known=(Get-GoatSelectionProperty $reading 'Available')-is [bool] -and [bool](Get-GoatSelectionProperty $reading 'Available') -and (Get-GoatSelectionProperty $reading 'Value')-is [bool]
                    if(-not $known){$copy.RecommendationReason='Compressão de memória não lida com confiança; ausência de leitura não significa desativada.';$copy.Confidence='Indisponível'}
                    elseif([bool](Get-GoatSelectionProperty $reading 'Value')){$copy.RecommendationReason='Compressão já está ativada; não há motivo para reaplicar.';$copy.Confidence='Alta'}
                    elseif($direction-eq 'Off' -or $id-match 'compression.*off|compression.*disable' -or (Get-GoatSelectionProperty $tweak 'Target')-eq $false){$copy.RecommendationReason='Desativar compressão é uma preferência manual; não é inferido como ganho para PC com muita RAM.'}
                    elseif($machine.LowMemory-eq $true -or $machine.MemoryPressure-eq $true){$copy.Recommended=$true;$copy.Confidence='Moderada';$copy.RecommendationReason=if($machine.MemoryPressure-eq $true){'Compressão desativada e pouca RAM disponível nesta amostra: considerar ativação, comparando custo de CPU e paginação.'}else{'Compressão desativada e RAM total de até 8 GB: política conservadora para considerar ativação; não garante desempenho.'}}
                    else{$copy.RecommendationReason='Compressão desativada, mas sem RAM reduzida ou baixa disponibilidade observada; mantenha revisão manual.'}
                }
                'LowMemory'{
                    if($id-eq 'visual-effects' -and $Profile-ne 'Jogos'){$copy.RecommendationReason='Reduzir efeitos visuais exige perfil Jogos explícito; Equilibrado preserva a aparência.'}
                    elseif($machine.LowMemory-eq $true -or ($id-eq 'visual-effects' -and $machine.SlowStorage-eq $true)){$copy.Recommended=$true;$copy.Confidence='Moderada';$copy.RecommendationReason='RAM reduzida ou HDD declarado e perfil compatível: reduzir efeitos pode favorecer a resposta visual; não é previsão de FPS.'}
                    else{$copy.RecommendationReason='RAM reduzida/armazenamento elegível não confirmado; preserve esta preferência.'}
                }
                'SlowStorage'{
                    if($machine.KnownSlowStorage -and $machine.SlowStorage-eq $true){$copy.Recommended=$true;$copy.Confidence='Moderada';$copy.RecommendationReason='HDD elegível confirmado pelo inventário; revisar o efeito sob a mesma carga, sem inferir velocidade pelo nome do modelo.'}
                    else{$copy.RecommendationReason='HDD do contexto elegível não confirmado; mídias mistas ou desconhecidas não autorizam seleção.'}
                }
                'NetworkRepair'{
                    if(-not $machine.KnownNetwork -or $machine.HasConnectedAdapter-ne $true){$copy.RecommendationReason='Nenhum adaptador conectado foi confirmado; não selecionar reparo de rede automaticamente.'}
                    elseif($id-eq 'tcp-normal'){
                        $reading=Get-GoatSelectionReading $Scan 'network-autotuning'
                        $value=Get-GoatSelectionProperty $reading 'Value'
                        if((Get-GoatSelectionProperty $reading 'Available')-eq $true -and $value-is [string] -and $value-in @('disabled','restricted','highlyrestricted')){$copy.Recommended=$true;$copy.Confidence='Moderada';$copy.RecommendationReason='Adaptador conectado e auto-tuning Internet restringido confirmado: considerar Normal após revisar política; não promete menor ping.'}
                        else{$copy.RecommendationReason='Auto-tuning restringido não foi confirmado; Normal/Experimental/desconhecido não autorizam pré-seleção.'}
                    }
                    elseif($id-eq 'rss-on'){
                        $reading=Get-GoatSelectionReading $Scan 'rss';$value=Get-GoatSelectionProperty $reading 'Value'
                        if((Get-GoatSelectionProperty $reading 'Available')-eq $true -and $value-is [string] -and $value-eq 'Disabled' -and $machine.KnownLogicalProcessors -and $machine.LogicalProcessors-ge 2){$copy.Recommended=$true;$copy.Confidence='Moderada';$copy.RecommendationReason='RSS global desativado, conexão ativa e pelo menos dois processadores lógicos: considerar ativação conforme suporte da NIC/driver.'}
                        else{$copy.RecommendationReason='RSS desativado, conexão ou topologia elegível não foram confirmados; suporte por adaptador precisa de revisão.'}
                    }
                    else{$copy.RecommendationReason='Esta ação de rede não tem critério de leitura mapeado para pré-seleção; mantenha revisão manual.'}
                }
                default{$copy.RecommendationReason='Política manual ou desconhecida: nenhuma seleção automática.'}
            }
        }
        $items.Add([pscustomobject]$copy)
    }
    # Never select the same action twice. Mutually exclusive targets in a
    # conflict group require review; equal effects keep the first candidate.
    $seen=@{}
    foreach($item in $items){if($seen.ContainsKey([string]$item.Id)){$item.Recommended=$false;$item.RecommendationReason='Ação duplicada; a primeira ocorrência representa esta configuração.';$item.Confidence='Baixa'}else{$seen[[string]$item.Id]=$true}}
    foreach($group in @($items|Where-Object{$_.Recommended -and (Get-GoatSelectionProperty $_ 'ConflictGroup')}|Group-Object ConflictGroup)){
        if($group.Count-le 1){continue}
        $signatures=@($group.Group|ForEach-Object{ConvertTo-Json -InputObject ([pscustomobject]@{DesiredState=$_.DesiredState;Target=(Get-GoatSelectionProperty $_ 'Target')}) -Compress}|Select-Object -Unique)
        if($signatures.Count-gt 1){foreach($item in $group.Group){$item.Recommended=$false;$item.RecommendationReason='Opções do mesmo grupo pedem estados diferentes; revisão manual necessária.';$item.Confidence='Baixa'}}
        else{$winner=$group.Group[0];foreach($item in @($group.Group|Select-Object -Skip 1)){$item.Recommended=$false;$item.RecommendationReason='Efeito já coberto pela opção '+$winner.Title+'.';$item.Confidence='Baixa'}}
    }
    return $items.ToArray()
}
