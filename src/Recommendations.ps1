function Get-GoatRecommendationMatrix {
    if (-not $script:GoatRecommendationJson) { throw 'Matriz de recomendações não carregada.' }
    $matrix=$script:GoatRecommendationJson | ConvertFrom-Json -ErrorAction Stop
    if ($matrix.SchemaVersion -ne 1 -or @($matrix.Rules).Count -eq 0) { throw 'Matriz de recomendações inválida.' }
    foreach ($rule in $matrix.Rules) {
        if ($rule.Id -notmatch '^[a-z0-9-]+$' -or $rule.ProbeKey -notmatch '^[a-z0-9-]+$') { throw 'Identificador de recomendação inválido.' }
        if ($rule.Evaluation -notin @('BooleanTrue','Equals','Review','Unsupported')) { throw 'Avaliação de recomendação não permitida.' }
        if ($rule.ActionId -and $rule.ActionId -notin @('memory-compression','tcp-normal','rss-on')) { throw 'Ação fora da lista de recomendações permitidas.' }
        foreach ($source in @($rule.Sources)) {
            $uri=$null
            if (-not [Uri]::TryCreate([string]$source.Url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Port -ne 443) { throw 'Origem de recomendação inválida.' }
        }
    }
    return $matrix
}

function Get-GoatRecommendations {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Scan,[Parameter(Mandatory=$true)]$AdvancedState)
    $matrix=Get-GoatRecommendationMatrix
    $results=New-Object 'System.Collections.Generic.List[object]'
    # One canonical system effect per probe. Preserve every reviewed source,
    # but never stack duplicate changes or resolve contradictory values blindly.
    foreach ($group in @($matrix.Rules | Group-Object ProbeKey)) {
        $rule=$group.Group[0]
        $sources=New-Object 'System.Collections.Generic.List[object]'
        $sourceKeys=@{}; $conflict=$false; $incompatible=$false
        $signature=($rule | Select-Object Evaluation,Desired,ActionId | ConvertTo-Json -Compress)
        foreach ($candidate in $group.Group) {
            if ($candidate.Conflict) { $conflict=$true }
            if (($candidate | Select-Object Evaluation,Desired,ActionId | ConvertTo-Json -Compress) -ne $signature) { $incompatible=$true; $conflict=$true }
            foreach ($source in @($candidate.Sources)) {
                $key=([string]$source.RepositoryId)+'|'+([string]$source.ItemId)+'|'+([string]$source.Url)
                if (-not $sourceKeys.ContainsKey($key)) { $sourceKeys[$key]=$true; $sources.Add($source) }
            }
        }
        $stances=@($sources.ToArray() | Select-Object -ExpandProperty Stance -ErrorAction SilentlyContinue)
        if ($stances -contains 'Enable' -and $stances -contains 'Disable') { $conflict=$true }
        $reading=$null
        if ($AdvancedState.Readings -is [Collections.IDictionary]) { $reading=$AdvancedState.Readings[[string]$rule.ProbeKey] }
        elseif ($AdvancedState.Readings) { $property=$AdvancedState.Readings.PSObject.Properties[[string]$rule.ProbeKey]; if ($property) { $reading=$property.Value } }
        $status='Indisponível'; $current='O Windows não retornou um estado confiável para este item.'
        $detail=[string]$rule.Recommendation; $action=''
        if ($reading -and $reading.Text) { $current=[string]$reading.Text }
        if ($reading -and $reading.Available) {
            switch ($rule.Evaluation) {
                'BooleanTrue' {
                    if ($reading.Value -is [bool]) { $status=if ($reading.Value) {'Configurado'} else {'Recomendado'} }
                }
                'Equals' {
                    if (($reading.Value -is [string] -and -not [string]::IsNullOrWhiteSpace($reading.Value)) -or $reading.Value -is [ValueType]) {
                        $status=if ([string]$reading.Value -ieq [string]$rule.Desired) {'Configurado'} else {'Recomendado'}
                    }
                }
                'Review' { $status='Revisão manual' }
                'Unsupported' { $status='Revisão manual' }
            }
        }
        if ($incompatible) { if ($status -ne 'Indisponível') { $status='Revisão manual' }; $detail+=' Há valores conflitantes na matriz; nenhuma ação foi escolhida automaticamente.' }
        elseif ($conflict) { $detail+=' As referências divergem. A orientação acima é uma decisão revisada do GOAT; compare sob a mesma carga antes de manter a alteração.' }
        if ($status -eq 'Recomendado' -and $Scan.OS.Supported -and -not $incompatible) { $action=[string]$rule.ActionId }
        if (-not $Scan.OS.Supported -and $status -eq 'Recomendado') { $status='Revisão manual'; $detail+=' Este Windows está fora da matriz de aplicação do GOAT.' }
        $results.Add([pscustomobject]@{
            Id=[string]$rule.Id; Category=[string]$rule.Category; Title=[string]$rule.Title
            Status=$status; CurrentState=$current; Detail=$detail; Risk=[string]$rule.Risk
            ActionId=$action; Sources=@($sources.ToArray()); Conflict=$conflict
            ProbeKey=[string]$rule.ProbeKey; ReviewedAt=$matrix.ReviewedAt
        })
    }
    return $results.ToArray()
}

function Get-GoatRecommendationSelection {
    param([object[]]$Recommendations,[object[]]$Tweaks)
    $byId=@{}; foreach ($tweak in $Tweaks) {$byId[[string]$tweak.Id]=$tweak}
    foreach ($recommendation in $Recommendations) {
        $copy=$recommendation.PSObject.Copy()
        if ($copy.ActionId -and $byId.ContainsKey([string]$copy.ActionId)) {
            $tweak=$byId[[string]$copy.ActionId]
            if (-not $tweak.Available) {$copy.Status='Indisponível'}
            elseif ($tweak.OnState) {$copy.Status='Configurado'}
            elseif ($tweak.Recommended) {$copy.Status='Recomendado'}
            elseif ($copy.Status -eq 'Recomendado') {$copy.Status='Revisão manual'}
            if ($tweak.RecommendationReason) {$copy.Detail+=' Seleção para este PC: '+$tweak.RecommendationReason}
        }
        $copy
    }
}

function Get-GoatUnifiedScan {
    param([switch]$Demo)
    $scan=Get-GoatHardwareScan -Demo:$Demo
    $advanced=Get-GoatAdvancedState -Demo:$Demo -Scan $scan
    $scan | Add-Member -NotePropertyName AdvancedState -NotePropertyValue $advanced -Force
    $scan | Add-Member -NotePropertyName Recommendations -NotePropertyValue @(Get-GoatRecommendations -Scan $scan -AdvancedState $advanced) -Force
    if (Get-Command Get-GoatMachineProfile -ErrorAction SilentlyContinue) {
        $scan | Add-Member -NotePropertyName MachineProfile -NotePropertyValue (Get-GoatMachineProfile -Scan $scan) -Force
        $scan | Add-Member -NotePropertyName NativeTweaks -NotePropertyValue @(Set-GoatTweakRecommendations -Tweaks @(Get-GoatTweaks -Scan $scan) -Scan $scan) -Force
        $scan.Recommendations=@(Get-GoatRecommendationSelection -Recommendations $scan.Recommendations -Tweaks $scan.NativeTweaks)
    }
    if (Get-Command Get-GoatToolRecommendations -ErrorAction SilentlyContinue) {
        $scan | Add-Member -NotePropertyName ToolRecommendations -NotePropertyValue @(Get-GoatToolRecommendations -Scan $scan -CatalogJson $script:GoatCatalogJson) -Force
    }
    return $scan
}
