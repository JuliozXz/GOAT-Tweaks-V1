function Get-GoatToolRules {
    if (-not $script:GoatToolRulesJson) { throw 'Regras de comparação de ferramentas não carregadas.' }
    $data=$script:GoatToolRulesJson | ConvertFrom-Json -ErrorAction Stop
    if ($data.SchemaVersion -ne 1) {throw 'Regras de ferramentas incompatíveis.'}
    $seen=@{}
    foreach ($rule in @($data.Rules)) {
        $key=$rule.RepositoryId+'|'+$rule.ItemId
        if ($seen.ContainsKey($key) -or -not $rule.ItemId -or $rule.RepositoryId -notin @('winutil','winsux','ultimate','rytunex')) {throw 'Regra de ferramenta duplicada ou inválida.'}
        if ($rule.Hardware -notin @('NVIDIA','AMD-GPU','Intel-GPU','Intel-CPU','AMD-CPU','Any','Unknown') -or $rule.Architecture -notin @('x64','x86','Any','Unknown')) {throw 'Requisito de hardware inválido.'}
        if ($rule.Role -notin @('Driver','Diagnostic','Optimizer','Installer','Reference')) {throw 'Papel de ferramenta inválido.'}
        $seen[$key]=$true
    }
    return @($data.Rules)
}

function Test-GoatToolGpuVendor {
    param([object[]]$Gpus,[string]$Pattern)
    $names=@($Gpus|ForEach-Object{[string]$_.Name})
    if (@($names|Where-Object{$_ -match $Pattern -and $_ -notmatch 'Microsoft Basic|Adaptador de.*[Bb].*Microsoft'}).Count -gt 0) {return $true}
    if ($names.Count -eq 0 -or @($names|Where-Object{$_ -notmatch 'NVIDIA|AMD|Radeon|Intel|Qualcomm|Adreno' -or $_ -match 'Microsoft Basic|Adaptador de.*[Bb].*Microsoft'}).Count -gt 0) {return $null}
    return $false
}

function Get-GoatToolRecommendations {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Scan,[Parameter(Mandatory=$true)][string]$CatalogJson)
    $catalog=$CatalogJson | ConvertFrom-Json -ErrorAction Stop
    $rules=@{};foreach ($rule in @(Get-GoatToolRules)) {$rules[$rule.RepositoryId+'|'+$rule.ItemId]=$rule}
    $gpus=@($Scan.GPU | Where-Object {-not [string]::IsNullOrWhiteSpace([string]$_.Name)})
    $cpuName=[string]$Scan.CPU.Name
    $architecture=$null
    if ($Scan.AdvancedState.Readings -is [Collections.IDictionary]) {$architecture=$Scan.AdvancedState.Readings['cpu-architecture']}
    elseif ($Scan.AdvancedState.Readings) {$architecture=$Scan.AdvancedState.Readings.PSObject.Properties['cpu-architecture'].Value}
    $archName=if ($architecture -and $architecture.Available) {[string]$architecture.Value.Name} else {''}
    $results=New-Object 'System.Collections.Generic.List[object]';$catalogKeys=@{}
    foreach ($repository in @($catalog.Repositories)) {
        foreach ($item in @($repository.Items)) {
            $key=$repository.Id+'|'+$item.Id;$catalogKeys[$key]=$true
            $rule=$rules[$key];$status='Referência';$reason='Arquivo de apoio ou código-fonte: consulte no contexto do projeto original.'
            $alias=[string]$item.Name;$category=[string]$item.Group;$family='';$rank=0;$reviewed=$false
            if ($item.CanRun -or $item.Operation -in @('Feature','ReleaseAsset','OpenUri')) {$status='Revisão manual';$reason='Este item não possui uma regra de compatibilidade individual validada. Nenhum ganho de FPS foi inferido do nome ou da extensão.'}
            if ($rule) {
                $reviewed=$true;$category=[string]$rule.Category;$family=[string]$rule.Family;$rank=[int]$rule.Priority
                if ($rule.Alias) {$alias=[string]$rule.Alias}
                $reason=[string]$rule.Reason
                $hardwareMatch=$null
                switch ($rule.Hardware) {
                    'Any' {$hardwareMatch=$true}
                    'NVIDIA' {$hardwareMatch=Test-GoatToolGpuVendor $gpus 'NVIDIA'}
                    'AMD-GPU' {$hardwareMatch=Test-GoatToolGpuVendor $gpus 'AMD|Radeon'}
                    'Intel-GPU' {$hardwareMatch=Test-GoatToolGpuVendor $gpus 'Intel'}
                    'Intel-CPU' {if ($cpuName -match 'Intel|AMD') {$hardwareMatch=$cpuName -match 'Intel'}}
                    'AMD-CPU' {if ($cpuName -match 'Intel|AMD') {$hardwareMatch=$cpuName -match 'AMD'}}
                }
                $archMatch=$null
                if ($rule.Architecture -eq 'Any') {$archMatch=$true}
                elseif ($archName -eq 'x64' -and $rule.Architecture -eq 'x64') {$archMatch=$true}
                elseif ($archName -eq 'x86' -and $rule.Architecture -eq 'x86') {$archMatch=$true}
                elseif ($archName -eq 'x64' -and $rule.Architecture -eq 'x86' -and $rule.Role -ne 'Driver') {$archMatch=$true}
                elseif ($archName -in @('x64','x86','ARM64') -and $rule.Architecture -ne 'Unknown') {$archMatch=$false}
                $status='Revisão manual'
                if (-not $Scan.OS.Supported) {$status='Não aplicável';$reason+=' Windows fora da faixa atendida pelo GOAT.'}
                elseif ($null -ne $hardwareMatch -and -not $hardwareMatch) {$status='Não aplicável';$reason+=' O fabricante necessário não foi identificado no hardware desta máquina.'}
                elseif ($null -ne $archMatch -and -not $archMatch) {$status='Não aplicável';$reason+=' Arquitetura detectada incompatível com esta publicação.'}
                elseif ($null -eq $hardwareMatch -or $null -eq $archMatch) {$reason+=' Faltam dados de compatibilidade: avaliação manual obrigatória.'}
                elseif ($rule.Role -eq 'Reference') {$status='Referência'}
                elseif ($rule.Requires -eq 'Manual' -or $rule.Role -eq 'Optimizer') {$reason+=' O hardware compatível não autoriza todos os ajustes internos do programa; revise o procedimento original.'}
                else {
                    $status='Compatível';$reason+=' Fabricante/arquitetura atendem à regra revisada; versão de driver, licenças e instalação devem ser conferidas.'
                    # Only reviewed diagnostic tools may be suggested automatically.
                    # Optimizers, drivers and installers are never selected from a filename.
                    if ($rule.CanRecommend -is [bool] -and $rule.CanRecommend -and $rule.Role -eq 'Diagnostic' -and $item.CanRun -and $rule.Requires -eq 'Any') {
                        $status='Recomendado';$reason+=' Sugerido para diagnóstico desta máquina, sem previsão de ganho de FPS.'
                    }
                }
            }
            $results.Add([pscustomobject]@{RepositoryId=$repository.Id;ItemId=$item.Id;Alias=$alias;Status=$status;Reason=$reason;Category=$category;Family=$family;Priority=$rank;Reviewed=$reviewed;CanRun=[bool]$item.CanRun})
        }
    }
    foreach ($key in $rules.Keys) {if (-not $catalogKeys.ContainsKey($key)) {throw ('Regra aponta para item ausente: '+$key)}}
    foreach ($group in @($results.ToArray() | Where-Object {$_.Status -eq 'Recomendado' -and $_.Family} | Group-Object Family)) {
        $ordered=@($group.Group | Sort-Object @{Expression='Priority';Descending=$true},RepositoryId,ItemId)
        for ($index=1;$index -lt $ordered.Count;$index++) {$ordered[$index].Status='Compatível';$ordered[$index].Reason+=' Alternativa ao diagnóstico '+$ordered[0].Alias+'; evite abrir equivalentes simultaneamente.'}
    }
    return $results.ToArray()
}
