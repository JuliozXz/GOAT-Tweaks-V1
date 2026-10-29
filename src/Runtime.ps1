function Get-GoatRuntimeCatalog {
    param([object[]]$Catalog,$Inventory)
    $actions=@(Get-GoatActions|Where-Object {$_.ExecutorKind -eq 'RegistryValue' -and $_.ReleaseEnabled})
    $guides=@(Get-GoatAdvancedGuides -Catalog $Catalog -Inventory $Inventory)
    foreach($record in $Catalog){
        $item=$record|Select-Object *
        $native=@($actions|Where-Object {@($_.CatalogIds) -contains $record.id})
        $guide=@($guides|Where-Object Id -eq $record.id)
        $target='Reference';$mode='Referência';$ids=@();$status='SPEC_ONLY_NOT_YET_VERIFIED'
        if($native.Count){$target='Native';$mode='Ajuste nativo';$ids=@($native|ForEach-Object Id);$status='NATIVE_EXECUTOR';$item.execution_class=$(if(@($native|Where-Object RequiresIndividualApproval).Count){'B_APPROVAL'}else{'A_AUTO_SAFE'})}
        elseif($record.id -in @('PWR-PLAN','POWER-PLAN-A_B','WIN-006','GAME-005')){$target='Power';$mode='Plano de energia';$status='POWER_EXECUTOR';$item.execution_class='B_APPROVAL'}
        elseif($guide.Count){$target='Advanced';$mode='Procedimento assistido';$status=[string]$guide[0].Status;$item.execution_class='C_MANUAL'}
        $item|Add-Member SpecificationClass ([string]$record.execution_class) -Force
        $item|Add-Member RuntimeTarget $target -Force
        $item|Add-Member RuntimeMode $mode -Force
        $item|Add-Member RuntimeStatus $status -Force
        $item|Add-Member RuntimeActionIds $ids -Force
        $item
    }
}
function Open-GoatSettingsPage {
    param([Parameter(Mandatory)][string]$Uri)
    # The allowlist comes from program definitions, never from catalog text.
    $allowed=@(Get-GoatAdvancedSettingsAllowlist)
    if($Uri -cnotin $allowed){throw 'Página de configurações não autorizada pelo aplicativo.'}
    Start-Process -FilePath $Uri -ErrorAction Stop|Out-Null
}
function Format-GoatAdvancedGuide {
    param($Guide)
    if(-not $Guide){return 'Selecione um procedimento.'}
    $lines=New-Object 'System.Collections.Generic.List[string]'
    $lines.Add([string]$Guide.Title);$lines.Add('ID: '+$Guide.Id+' · '+$Guide.Status)
    $lines.Add('Risco: '+$Guide.Risk);$lines.Add('Modo: procedimento assistido; não é uma automação de aplicação.')
    $lines.Add('');$lines.Add([string]$Guide.Reason)
    if($Guide.State){$lines.Add('Estado: '+$(if($Guide.State.Known){[string]$Guide.State.Value}else{'desconhecido / não consultado'}));$lines.Add('Fonte do estado: '+$(if($Guide.State.Source){[string]$Guide.State.Source}else{'indisponível nesta leitura'}))}
    $lines.Add('');$lines.Add('PRÉ-REQUISITOS')
    $labels=@{AdminRequired='Exige administrador';StablePowerRequired='Exige alimentação estável';BackupRequired='Exige cópia de segurança';RestartMayBeRequired='Pode exigir reinício manual';RemoteOrUnknown='Acesso remoto ou contexto incerto';LocalOperatorConfirmed='Operador local confirmado';RecoveryPlanConfirmed='Recuperação conferida';MaintenanceReady='Pré-requisitos de manutenção atendidos';Note='Orientação'}
    foreach($property in $Guide.Prerequisites.PSObject.Properties){if($labels.ContainsKey($property.Name)){$value=if($property.Value -is [bool]){if($property.Value){'Sim'}else{'Não'}}else{[string]$property.Value};$lines.Add('• '+$labels[$property.Name]+': '+$value)}}
    $lines.Add('');$lines.Add('PROCEDIMENTO')
    $n=0;foreach($entry in @($Guide.Steps)){$n++;$lines.Add([string]$n+'. '+[string]$entry)}
    $lines.Add('');$lines.Add('RECUPERAÇÃO')
    foreach($entry in @($Guide.Recovery)){$lines.Add('• '+[string]$entry)}
    $lines.Add('');$lines.Add('FONTES')
    foreach($entry in @($Guide.Sources)){$lines.Add([string]$entry)}
    $lines -join "`r`n"
}
function Format-GoatPowerPreview {
    param($Preview,[string]$Result)
    if(-not $Preview){return 'Selecione um plano existente e gere a prévia.'}
    $lines=New-Object 'System.Collections.Generic.List[string]'
    if($Result){$lines.Add($Result);$lines.Add('')}
    $lines.Add('Plano proposto: '+$Preview.ProposedName)
    $lines.Add('Original: '+$Preview.OriginalSchemeGuid);$lines.Add('Proposto: '+$Preview.ProposedSchemeGuid)
    $lines.Add('Estado: '+$Preview.Status+' · '+$(if($Preview.Changed){'troca de plano'}else{'plano já selecionado / sem delta'}))
    $lines.Add('Elegível agora: '+$(if($Preview.ExecutionAllowed){'Sim'}else{'Não'}))
    $lines.Add('Administrador exigido: '+$(if($Preview.RequiresAdmin){'Sim'}else{'Não'}));$lines.Add('Reinício automático: não')
    foreach($reason in @($Preview.Reasons)){$lines.Add('• '+[string]$reason)}
    $lines.Add('');$lines.Add('CONSEQUÊNCIAS / RECUPERAÇÃO')
    foreach($item in @($Preview.Tradeoffs)){$lines.Add('• '+[string]$item)}
    $lines -join "`r`n"
}
function Add-GoatManualRecord {
    param($Session,[string]$GuideId,[object[]]$Guides,[switch]$Confirmed)
    if($Session.State -ne 'Open'){throw 'Sessão encerrada.'}
    if(-not $Confirmed){throw 'Confirme somente um procedimento que você realmente realizou.'}
    $guide=@($Guides|Where-Object Id -eq $GuideId)
    if($guide.Count -ne 1 -or $guide[0].Status -ne 'MANUAL_GUIDE'){throw 'Este procedimento não permite registrar aplicação manual.'}
    if($guide[0].Prerequisites.PSObject.Properties['MaintenanceReady'] -and -not $guide[0].Prerequisites.MaintenanceReady){throw 'Confirme os pré-requisitos de manutenção antes de registrar o procedimento.'}
    if(-not $Session.PSObject.Properties['ManualRecords']){$Session|Add-Member ManualRecords @()}
    $record=[pscustomobject]@{Id=$GuideId;Title=[string]$guide[0].Title;Utc=[DateTime]::UtcNow.ToString('o');State='REPORTED_MANUALLY';AutomaticallyVerified=$false;Risk=[string]$guide[0].Risk}
    $Session.ManualRecords+=$record
    Add-GoatEvent $Session 'Manual' ('Procedimento relatado pelo técnico: '+$GuideId+'; sem verificação automática.')
    $record
}
function Format-GoatActionPreview {
    param([object[]]$Preview)
    if(-not $Preview.Count){return 'Selecione uma preferência e gere a prévia.'}
    $lines=New-Object 'System.Collections.Generic.List[string]'
    foreach($item in $Preview){
        $action=$item.Action
        $lines.Add($action.Title+' · '+$item.Direction)
        $lines.Add([string]$action.Description);$lines.Add('Risco: '+$action.Risk+' · classe: '+$action.ExecutionClass)
        $lines.Add('Administrador: '+$action.RequiresAdmin+' · reinício: '+$(if($null -eq $action.RequiresReboot){'pode exigir nova sessão'}else{[string]$action.RequiresReboot}))
        $lines.Add('Consequências: '+$action.Tradeoffs);$lines.Add('Verificação: '+$action.Verification)
        $lines.Add('Elegível agora: '+$item.ExecutionAllowed+' · '+(@($item.Eligibility.Reasons) -join '; '))
        $lines.Add('Estado original e proposta:');$lines.Add(($item|Select-Object Id,Direction,Before,After,Original,Proposed,Changed,EffectiveState|ConvertTo-Json -Depth 12))
        $lines.Add('Fontes: '+(@($action.Sources) -join ' | '));$lines.Add('')
    }
    $lines -join "`r`n"
}
