# GPU inventory and assisted guidance. Original implementation for GOAT Tweaks.
# Windows PowerShell 5.1. This module never installs, removes or configures a driver.

function Invoke-GoatGpuInventoryQuery {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$ClassName,[string]$Namespace='root/cimv2',[string]$Filter)
    $parameters=@{ClassName=$ClassName;Namespace=$Namespace;OperationTimeoutSec=6;ErrorAction='Stop'}
    if ($Filter) { $parameters.Filter=$Filter }
    @(Get-CimInstance @parameters)
}

function Get-GoatGpuRemoteContext {
    [CmdletBinding()]
    param()
    $indicators=New-Object 'System.Collections.Generic.List[string]'
    if ($env:SESSIONNAME -match '^RDP-|^ICA-') { $indicators.Add('SESSIONNAME indica RDP/ICA') }
    try {
        $names=@(Get-Process -ErrorAction Stop | Select-Object -ExpandProperty ProcessName)
        if (@($names | Where-Object { $_ -match '^(AnyDesk|TeamViewer|TeamViewer_Service|RustDesk|rustdesk_service|ScreenConnect.*|Splashtop.*|SRServer|Parsec|parsecd|supremo.*|winvnc|tvnserver|remoting_host)$' }).Count -gt 0) {
            $indicators.Add('Software de acesso remoto detectado; conexão ativa não confirmada')
        }
    } catch { $indicators.Add('Detecção de processos indisponível') }
    $state='UNKNOWN'
    if ($indicators.Count -gt 0) { $state='REMOTE_OR_POSSIBLE_REMOTE' }
    elseif ($env:SESSIONNAME -eq 'Console') { $state='LOCAL_CONSOLE' }
    [pscustomobject]@{State=$state;IsRemoteOrUncertain=($state -ne 'LOCAL_CONSOLE');Indicators=@($indicators.ToArray());Source='SESSIONNAME + process inventory';Note='A ausência de processo conhecido não prova atendimento presencial.'}
}

function ConvertFrom-GoatGpuMonitorText {
    param($Value)
    if ($null -eq $Value) { return $null }
    $characters=@($Value | Where-Object { $_ -gt 0 } | ForEach-Object { [char]$_ })
    if ($characters.Count -eq 0) { return $null }
    -join $characters
}

function Get-GoatGpuOfficialDriverSource {
    param([string]$Vendor)
    switch ($Vendor) {
        'NVIDIA' { return 'https://www.nvidia.com/en-us/drivers/' }
        'AMD' { return 'https://www.amd.com/en/support/download/drivers.html' }
        'Intel' { return 'https://www.intel.com/content/www/us/en/download-center/home.html' }
        default { return $null }
    }
}

function Get-GoatGpuOemSource {
    param([string]$Manufacturer)
    switch -Regex ($Manufacturer) {
        'Dell' { return 'https://www.dell.com/support/home/' }
        'LENOVO' { return 'https://support.lenovo.com/' }
        'HP|Hewlett' { return 'https://support.hp.com/drivers' }
        'ASUSTeK|ASUS' { return 'https://www.asus.com/support/download-center/' }
        'Acer' { return 'https://www.acer.com/us-en/support/drivers-and-manuals' }
        'Micro-Star|MSI' { return 'https://www.msi.com/support/download' }
        default { return $null }
    }
}

function New-GoatGpuUnavailableTelemetry {
    param([string]$Reason='Nenhum provedor de sensor validado foi conectado.')
    $metrics=@()
    foreach ($entry in @(@('GpuTotalLoad','%'),@('CoreClock','MHz'),@('MemoryClock','MHz'),@('DedicatedVramUsed','MiB'),@('SharedVramUsed','MiB'),@('Temperature','C'),@('Hotspot','C'),@('Power','W'),@('Throttling','state'))) {
        $metrics += [pscustomobject]@{Name=$entry[0];Value=$null;Unit=$entry[1];Status='UNAVAILABLE';Source=$null;Reason=$Reason}
    }
    [pscustomobject]@{Status='UNAVAILABLE';SampleUtc=[DateTime]::UtcNow.ToString('o');Metrics=$metrics;EngineLoads=@();Note='Telemetria não mede FPS ou input lag. AdapterRAM do WMI não comprova VRAM.'}
}

function Get-GoatGpuTelemetry {
    [CmdletBinding()]
    param([switch]$Demo)
    if ($Demo) { return New-GoatGpuUnavailableTelemetry -Reason 'Demo: nenhum sensor real consultado.' }
    $result=New-GoatGpuUnavailableTelemetry
    try {
        $engines=@(Invoke-GoatGpuInventoryQuery -ClassName 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine')
        $readings=@()
        foreach ($engine in $engines) {
            $value=0.0
            if ([double]::TryParse([string]$engine.UtilizationPercentage,[ref]$value) -and $value -ge 0 -and $value -le 100) {
                $readings += [pscustomobject]@{Instance=[string]$engine.Name;Value=$value;Unit='%';Source='Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine';Status='READ_ONLY'}
            }
        }
        $result.EngineLoads=$readings
        if ($readings.Count -gt 0) { $result.Status='PARTIAL';$result.Note='Uso por instância de motor do Windows; não somado nem tratado como carga total da GPU. Sem FPS/input lag.' }
    } catch { $result.Note='Motores GPU indisponíveis: '+$_.Exception.Message }
    $result
}

function Get-GoatGpuGuides {
    [CmdletBinding()]
    param([ValidateSet('NVIDIA','AMD','Intel','Desconhecido')][string]$Vendor='Desconhecido',$RemoteContext,[switch]$LocalOperatorConfirmed,[switch]$RecoveryPlanConfirmed)
    if ($null -eq $RemoteContext) { $RemoteContext=Get-GoatGpuRemoteContext }
    $remote=([string]$RemoteContext.State -ne 'LOCAL_CONSOLE')
    $dduAllowed=(-not $remote -and $LocalOperatorConfirmed -and $RecoveryPlanConfirmed)
    $guides=@()
    $guides += [pscustomobject]@{Id='gpu-driver-update';Title='Atualizar driver com acompanhamento';Status='MANUAL_GUIDE';Risk='B_APPROVAL';CanExecute=$false;Source=(Get-GoatGpuOfficialDriverSource -Vendor $Vendor);Steps=@('Registrar versão instalada, modelo/PCI ID e Windows. Em notebook, conferir primeiro o driver homologado pelo OEM.','No site oficial, revisar suporte ao modelo, sistema e notas da versão. O inventário offline não verifica a versão mais recente.','Baixar manualmente o pacote adequado. Conferir assinatura Authenticode e editor antes de executar.','Guardar instalador anterior e um plano de recuperação. Ponto de restauração é proteção adicional, sem garantia de reverter driver.','Executar manualmente com consentimento. Reiniciar somente após aprovação; depois refazer inventário e conferir imagem, monitores, áudio e captura.');Recovery='Gerenciador de Dispositivos: voltar ao driver anterior quando disponível, ou reinstalar manualmente um pacote compatível previamente guardado.'}
    $guides += [pscustomobject]@{Id='gpu-ddu';Title='DDU: procedimento manual excepcional';Status=$(if($dduAllowed){'MANUAL_GUIDE'}else{'BLOCKED'});Risk='C_MANUAL';CanExecute=$false;Source=$null;Steps=@('Não usar como rotina de otimização. Não há download, execução, SafeBoot, RunOnce ou reinício automático neste app.','Exigir operador fisicamente presente, consentimento e recuperação local testada. Pode ocorrer tela preta e perda de acesso remoto.','Conferir notebook híbrido, BitLocker, monitores, HDR e políticas corporativas. Guardar pacote OEM/driver anterior e dados de recuperação em local seguro.','O técnico executa qualquer procedimento externo manualmente e valida funcionamento e versão depois.');Recovery='Recuperação de driver é procedimento separado, sem rollback automático pelo GOAT.';BlockReason=$(if($remote){'Sessão remota ou contexto desconhecido. Manutenção com risco de perder vídeo/acesso bloqueada.'}elseif(-not $LocalOperatorConfirmed -or -not $RecoveryPlanConfirmed){'Confirme operador local e plano de recuperação antes de consultar o procedimento manual.'}else{$null})}
    $vendorSteps=switch ($Vendor) {
        'NVIDIA' { @('Painel NVIDIA > Gerenciar configurações 3D > Configurações de programa. Selecionar somente o jogo confirmado.','Conferir suporte do jogo a Reflex antes de sugerir modo de baixa latência do driver. Não impor Ultra globalmente.','Conferir suporte/ativação real de G-SYNC/VRR, V-Sync e cap no jogo; evitar limitadores concorrentes.','Anotar os valores originais e restaurar o perfil do programa manualmente se houver regressão.') }
        'AMD' { @('AMD Software > Jogos > perfil do jogo confirmado; nomes variam com versão do driver.','Anti-Lag, Chill, limite de FPS e Enhanced Sync dependem de suporte da versão e do jogo. Não inferir capacidade só pelo fabricante.','Revisar FreeSync, V-Sync, captura/streaming e conflitos entre limitadores antes de alterar uma variável.','Guardar valores originais e restaurar manualmente apenas o perfil do jogo se houver regressão.') }
        'Intel' { @('Abrir o painel Intel disponível no driver: Intel Graphics Software ou ferramenta correspondente. Confirmar modelo e versão.','Não presumir que Intel iGPU e Arc oferecem os mesmos controles. Conferir suporte real a VRR, sincronização e cap no jogo.','Alterar uma variável por teste e preservar captura/qualidade conforme objetivo.','Guardar valores originais e restaurar manualmente o perfil correspondente se houver regressão.') }
        default { @('GPU/fabricante não identificado com confiança. Conferir Gerenciador de Dispositivos e driver OEM.','Não recomendar controles de painel específicos sem modelo e capacidades confirmados.') }
    }
    $guides += [pscustomobject]@{Id='gpu-vendor-profile';Title=('Perfil por jogo — '+$Vendor);Status='MANUAL_GUIDE';Risk='C_MANUAL';CanExecute=$false;Source=(Get-GoatGpuOfficialDriverSource -Vendor $Vendor);Steps=$vendorSteps;Recovery='Restaurar os valores originais no painel/jogo; o GOAT não afirma ter modificado ou restaurado esses controles.'}
    $guides += [pscustomobject]@{Id='gpu-windows-settings';Title='Configurações gráficas do Windows';Status='MANUAL_GUIDE';Risk='C_MANUAL';CanExecute=$false;Source='https://support.microsoft.com/windows';Steps=@('Abrir Configurações > Sistema > Tela > Elementos gráficos. Confirmar a opção disponível no Windows/driver atual.','Preferência de GPU por aplicativo, HAGS e otimização de jogos em janela são controles distintos. Ausência de controle não equivale a desativado.','Conferir Game Mode, overlays/captura e finalidade do atendimento. Testar uma alteração por vez e reiniciar apenas com consentimento quando solicitado.');Recovery='Restaurar manualmente o valor original confirmado na interface do Windows.'}
    $guides
}

function Get-GoatGpuCenter {
    [CmdletBinding()]
    param([switch]$Demo,[switch]$IncludeTelemetry)
    if ($Demo) {
        $remote=[pscustomobject]@{State='LOCAL_CONSOLE';IsRemoteOrUncertain=$false;Indicators=@();Source='DEMO';Note='Exemplo, sem detecção real.'}
        return [pscustomobject]@{SchemaVersion=1;Status='DEMO';ReadOnly=$true;SampleUtc=[DateTime]::UtcNow.ToString('o');Devices=@([pscustomobject]@{Name='GPU NVIDIA de exemplo';Vendor='NVIDIA';VendorId='10DE';DeviceId='DEMO';PnpDeviceId='DEMO';DriverVersion='Exemplo';DriverDate=$null;DriverProvider='Exemplo';DriverSigned=$null;DriverInf=$null;DriverSource=(Get-GoatGpuOfficialDriverSource NVIDIA);LatestDriverStatus='NOT_CHECKED';AdapterRAMGB=$null;GpuType='UNKNOWN';Status='DEMO';Source='DEMO';Confidence='DEMO';CurrentControllerMode=$null});Monitors=@();System=[pscustomobject]@{Manufacturer='Exemplo';Model='Exemplo';IsNotebook=$null;OemDriverSource=$null;Source='DEMO'};RemoteContext=$remote;Telemetry=(New-GoatGpuUnavailableTelemetry -Reason 'Demo: sensores não consultados.');DriverGuides=@(Get-GoatGpuGuides -Vendor NVIDIA -RemoteContext $remote);Recommendations=@('Perfil e métricas são exemplos. Nenhuma alteração foi realizada.');Warnings=@('DEMO: inventário fictício explicitamente identificado.');Capabilities=[pscustomobject]@{Vrr='UNKNOWN';Hags='UNKNOWN';ActiveGameGpu='UNKNOWN';DedicatedVram='UNKNOWN'}}
    }
    $warnings=New-Object 'System.Collections.Generic.List[string]'
    $read=@{}
    foreach ($request in @(@('Video','Win32_VideoController','root/cimv2',''),@('Drivers','Win32_PnPSignedDriver','root/cimv2',"DeviceClass = 'DISPLAY'"),@('Computer','Win32_ComputerSystem','root/cimv2',''),@('Enclosure','Win32_SystemEnclosure','root/cimv2',''),@('Monitor','WmiMonitorID','root/wmi',''))) {
        try { $read[$request[0]]=@(Invoke-GoatGpuInventoryQuery -ClassName $request[1] -Namespace $request[2] -Filter $request[3]) }
        catch { $read[$request[0]]=@();$warnings.Add(($request[1]+': '+$_.Exception.Message)) }
    }
    $computer=@($read.Computer | Select-Object -First 1)
    $manufacturer=$null;$model=$null;$notebook=$null
    if ($computer.Count -gt 0) { $manufacturer=[string]$computer[0].Manufacturer;$model=[string]$computer[0].Model;if($computer[0].PCSystemType -eq 2){$notebook=$true} }
    $chassis=@($read.Enclosure | ForEach-Object {$_.ChassisTypes})
    if (@($chassis | Where-Object { $_ -in @(8,9,10,11,14,30,31,32) }).Count -gt 0) { $notebook=$true }
    elseif ($chassis.Count -gt 0 -and @($chassis | Where-Object {$_ -notin @(0,1,2)}).Count -gt 0 -and $null -eq $notebook) { $notebook=$false }
    $system=[pscustomobject]@{Manufacturer=$manufacturer;Model=$model;IsNotebook=$notebook;OemDriverSource=(Get-GoatGpuOemSource $manufacturer);Source='Win32_ComputerSystem + Win32_SystemEnclosure'}
    $devices=@()
    foreach ($gpu in @($read.Video)) {
        $pnp=[string]$gpu.PNPDeviceID;$vendorId=$null;$deviceId=$null;$vendor='Desconhecido';$confidence='LOW'
        if ($pnp -match '(?i)VEN_([0-9A-F]{4})') { $vendorId=$Matches[1].ToUpperInvariant();$confidence='PCI_ID' }
        if ($pnp -match '(?i)DEV_([0-9A-F]{4})') { $deviceId=$Matches[1].ToUpperInvariant() }
        switch ($vendorId) { '10DE' {$vendor='NVIDIA'} '1002' {$vendor='AMD'} '8086' {$vendor='Intel'} }
        if (-not $vendorId -and [string]$gpu.Name -notmatch 'Microsoft|Basic Display|Render|Remote|Virtual') {
            switch -Regex ([string]$gpu.Name) { 'NVIDIA' {$vendor='NVIDIA';$confidence='NAME_ONLY'} 'AMD|Radeon' {$vendor='AMD';$confidence='NAME_ONLY'} 'Intel' {$vendor='Intel';$confidence='NAME_ONLY'} }
        }
        $signed=@($read.Drivers | Where-Object { $pnp -and [string]$_.DeviceID -eq $pnp } | Select-Object -First 1)
        $driverProvider=$null;$driverSigned=$null;$inf=$null;$driverVersion=[string]$gpu.DriverVersion;$date=$null
        $rawDate=$gpu.DriverDate
        if ($signed.Count -gt 0) { $driverProvider=[string]$signed[0].DriverProviderName;$driverSigned=$signed[0].IsSigned;$inf=[string]$signed[0].InfName;if($signed[0].DriverVersion){$driverVersion=[string]$signed[0].DriverVersion};if($signed[0].DriverDate){$rawDate=$signed[0].DriverDate} }
        if ($rawDate) {
            try { if($rawDate -is [datetime]){$date=$rawDate.ToUniversalTime().ToString('o')}elseif([string]$rawDate -match '^\d{14}\.'){ $date=[Management.ManagementDateTimeConverter]::ToDateTime([string]$rawDate).ToUniversalTime().ToString('o') }else{$parsed=[datetime]::MinValue;if([datetime]::TryParse([string]$rawDate,[ref]$parsed)){$date=$parsed.ToUniversalTime().ToString('o')}else{throw 'Formato desconhecido'}} }
            catch { $warnings.Add(('Data de driver inválida para '+[string]$gpu.Name)) }
        }
        $mode=$null
        if ($gpu.CurrentHorizontalResolution -gt 0 -and $gpu.CurrentVerticalResolution -gt 0) {
            $hz=$null;if($gpu.CurrentRefreshRate -gt 1 -and $gpu.CurrentRefreshRate -lt 1000){$hz=[int]$gpu.CurrentRefreshRate}
            $mode=[pscustomobject]@{Width=[int]$gpu.CurrentHorizontalResolution;Height=[int]$gpu.CurrentVerticalResolution;RefreshRateHz=$hz;Source='Win32_VideoController';MonitorAssociation='UNKNOWN';Note='Modo reportado pelo controlador; não comprova modos suportados do monitor.'}
        }
        if ($gpu.AdapterRAM) { $warnings.Add(('VRAM de '+[string]$gpu.Name+': AdapterRAM WMI descartado por poder truncar; capacidade dedicada indisponível.')) }
        if ($signed.Count -eq 0) { $warnings.Add(('Metadados de driver assinado indisponíveis para '+[string]$gpu.Name)) }
        $devices += [pscustomobject]@{Name=[string]$gpu.Name;Vendor=$vendor;VendorId=$vendorId;DeviceId=$deviceId;PnpDeviceId=$pnp;DriverVersion=$driverVersion;DriverDate=$date;DriverProvider=$driverProvider;DriverSigned=$driverSigned;DriverInf=$inf;DriverSource=(Get-GoatGpuOfficialDriverSource $vendor);LatestDriverStatus='NOT_CHECKED';AdapterRAMGB=$null;GpuType='UNKNOWN';Status=$(if($gpu.ConfigManagerErrorCode -and $gpu.ConfigManagerErrorCode -ne 0){'DEVICE_ERROR'}else{'READ_ONLY'});DeviceErrorCode=$gpu.ConfigManagerErrorCode;Source='Win32_VideoController + Win32_PnPSignedDriver';Confidence=$confidence;CurrentControllerMode=$mode}
    }
    $monitors=@()
    foreach ($monitor in @($read.Monitor)) {
        $monitors += [pscustomobject]@{Name=(ConvertFrom-GoatGpuMonitorText $monitor.UserFriendlyName);Manufacturer=(ConvertFrom-GoatGpuMonitorText $monitor.ManufacturerName);InstanceName=[string]$monitor.InstanceName;Active=$monitor.Active;RefreshRateHz=$null;SupportedModes=$null;GpuAssociation='UNKNOWN';Source='root/wmi:WmiMonitorID';Status='READ_ONLY';Note='EDID identificação somente; frequência/VRR e associação à GPU não confirmados.'}
    }
    if ($devices.Count -eq 0) { $warnings.Add('Nenhuma GPU identificada. Não converter falha de consulta em recurso desativado.') }
    if ($devices.Count -gt 1) { $warnings.Add('Múltiplas GPUs detectadas. iGPU/dGPU/eGPU e GPU usada pelo jogo exigem confirmação adicional.') }
    if ($notebook -eq $true) { $warnings.Add('Notebook: conferir driver homologado pelo fabricante e dependências do vídeo híbrido antes de usar pacote genérico.') }
    $remote=Get-GoatGpuRemoteContext
    $telemetry=New-GoatGpuUnavailableTelemetry
    if ($IncludeTelemetry) { $telemetry=Get-GoatGpuTelemetry }
    $guides=@();foreach($vendor in @($devices | Select-Object -ExpandProperty Vendor -Unique)){$guides+=@(Get-GoatGpuGuides -Vendor $vendor -RemoteContext $remote)}
    [pscustomobject]@{SchemaVersion=1;Status=$(if($devices.Count -gt 0){'READ_ONLY'}else{'UNAVAILABLE'});ReadOnly=$true;SampleUtc=[DateTime]::UtcNow.ToString('o');Devices=$devices;Monitors=$monitors;System=$system;RemoteContext=$remote;Telemetry=$telemetry;DriverGuides=$guides;Recommendations=@('Driver instalado não significa driver mais recente. Revisar versão e compatibilidade na fonte oficial.','Confirmar jogo, monitor e capacidades antes de recomendar Reflex/Anti-Lag/VRR/HAGS.','Comparar a mesma cena/configuração em 3–5 passes por condição; FPS/input lag não foram medidos pelo inventário.');Warnings=@($warnings.ToArray());Capabilities=[pscustomobject]@{Vrr='UNKNOWN';Hags='UNKNOWN';ActiveGameGpu='UNKNOWN';DedicatedVram='UNKNOWN'}}
}

function New-GoatGpuGameProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][string]$GameId,[string]$GameName,[string]$ExecutablePath,[switch]$AuthorizedPath,[string]$Launcher,[string]$GpuPnpId,[ValidateSet('Competitivo','Equilibrado','Qualidade / Captura')][string]$Goal='Equilibrado',[string]$Resolution,[ValidateRange(0,1000)][double]$RefreshRateHz=0,[ValidateSet('Unknown','Enabled','Disabled','Unsupported')][string]$Reflex='Unknown',[ValidateSet('Unknown','Enabled','Disabled','Unsupported')][string]$Vrr='Unknown',[ValidateSet('Unknown','Enabled','Disabled')][string]$VSync='Unknown',[ValidateRange(0,2000)][double]$FpsCap=0,[switch]$CaptureRequired)
    if ($GameId.Length -gt 200 -or $GameId -match '[\x00-\x1f]') { throw 'GameId inválido.' }
    $canonical=$null
    if ($ExecutablePath) {
        if (-not $AuthorizedPath) { throw 'O caminho do jogo exige autorização explícita.' }
        if (-not [IO.Path]::IsPathRooted($ExecutablePath) -or [IO.Path]::GetExtension($ExecutablePath) -ine '.exe') { throw 'Selecione caminho absoluto para um executável .exe existente.' }
        $item=Get-Item -LiteralPath $ExecutablePath -ErrorAction Stop
        if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'O executável deve ser arquivo regular, sem reparse point.' }
        $canonical=$item.FullName
    }
    if ($Resolution -and $Resolution -notmatch '^\d{3,5}x\d{3,5}$') { throw 'Resolução deve ter formato 1920x1080.' }
    $profile=[pscustomobject]@{Schema='GOAT_GPU_GAME_PROFILE';SchemaVersion=1;Id=[guid]::NewGuid().ToString();GameId=$GameId;GameName=$GameName;ExecutablePath=$canonical;PathAuthorized=[bool]$AuthorizedPath;Launcher=$Launcher;GpuPnpId=$GpuPnpId;Goal=$Goal;Resolution=$Resolution;RefreshRateHz=$(if($RefreshRateHz -gt 0){$RefreshRateHz}else{$null});Reflex=$Reflex;Vrr=$Vrr;VSync=$VSync;FpsCap=$(if($FpsCap -gt 0){$FpsCap}else{$null});CaptureRequired=[bool]$CaptureRequired;CapabilitySource='USER_CONFIRMED_OR_UNKNOWN';CreatedUtc=[DateTime]::UtcNow.ToString('o');Status='GUIDANCE_ONLY';WindowsSettingsChanged=$false;DriverSettingsChanged=$false}
    Assert-GoatGpuGameProfile $profile
    return $profile
}

function Get-GoatGpuProfileAdvice {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Profile)
    Assert-GoatGpuGameProfile $Profile
    $advice=New-Object 'System.Collections.Generic.List[string]';$conflicts=New-Object 'System.Collections.Generic.List[string]'
    if (-not $Profile.GpuPnpId) { $conflicts.Add('GPU do jogo não confirmada; não selecionar uma GPU por inferência.') }
    if (-not $Profile.Resolution -or -not $Profile.RefreshRateHz) { $conflicts.Add('Resolução e/ou frequência do monitor não confirmadas.') }
    if ($Profile.Reflex -eq 'Enabled') { $advice.Add('Reflex informado como ativo no jogo: revisar sua integração antes de alterar modo de baixa latência do driver. Não impor Ultra global.') }
    elseif ($Profile.Reflex -eq 'Unknown') { $advice.Add('Suporte/estado de Reflex desconhecido. Verificar menu e documentação do jogo.') }
    if ($Profile.Vrr -eq 'Enabled') {
        $advice.Add('VRR informado como ativo: confirmar faixa real de operação e comportamento de V-Sync/cap no jogo antes de recomendar limite.')
        if ($Profile.FpsCap -and $Profile.RefreshRateHz -and $Profile.FpsCap -ge $Profile.RefreshRateHz) { $conflicts.Add('Cap de FPS alcança/excede a frequência informada: pode sair da faixa VRR; revisar a faixa real e objetivo.') }
    } elseif ($Profile.Vrr -eq 'Unknown') { $advice.Add('VRR não confirmado; fabricante da GPU não prova suporte do monitor/modo atual.') }
    if ($Profile.VSync -eq 'Enabled' -and $Profile.Goal -eq 'Competitivo') { $advice.Add('V-Sync ativo pode trocar tearing por latência. Comparar no jogo e contexto VRR; não desativar universalmente.') }
    if ($Profile.CaptureRequired -or $Profile.Goal -eq 'Qualidade / Captura') { $advice.Add('Preservar overlays/captura necessários; medir render lag/encoder e qualidade em OBS/Discord conforme workload.') }
    if ($Profile.Goal -eq 'Competitivo') { $advice.Add('Priorizar consistência de frametime e responsividade comprovada; FPS ilimitado ou energia máxima não são recomendações universais.') }
    elseif ($Profile.Goal -eq 'Qualidade / Captura') { $advice.Add('Priorizar qualidade/captura e estabilidade; conferir encoder disponível e margem de GPU antes de escolher preset.') }
    else { $advice.Add('Perfil equilibrado: comparar estabilidade, qualidade, consumo e captura antes de manter mudanças.') }
    $advice.Add('Registrar valores originais, mudar uma variável, fazer 3–5 passes idênticos antes/depois e restaurar manualmente se houver regressão.')
    [pscustomobject]@{Status='GUIDANCE_ONLY';CanApply=$false;ProfileId=$Profile.Id;Recommendations=@($advice.ToArray());Conflicts=@($conflicts.ToArray());MeasuredBenefit='NOT_MEASURED';Note='Prévia local de hipóteses; nenhuma preferência do Windows, jogo ou driver foi alterada.'}
}

function Assert-GoatGpuGameProfile {
    param($Profile)
    if($null -eq $Profile -or $Profile -is [array] -or $Profile.Schema -cne 'GOAT_GPU_GAME_PROFILE' -or $Profile.SchemaVersion -ne 1){throw 'Perfil GPU desconhecido.'}
    $fields=@('Schema','SchemaVersion','Id','GameId','GameName','ExecutablePath','PathAuthorized','Launcher','GpuPnpId','Goal','Resolution','RefreshRateHz','Reflex','Vrr','VSync','FpsCap','CaptureRequired','CapabilitySource','CreatedUtc','Status','WindowsSettingsChanged','DriverSettingsChanged')
    foreach($field in $fields){if($null -eq $Profile.PSObject.Properties[$field]){throw ('Campo ausente no perfil: '+$field)}}
    foreach($property in $Profile.PSObject.Properties){if($property.Name -notin $fields){throw ('Campo não reconhecido no perfil: '+$property.Name)}}
    if([string]$Profile.Id -notmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'){throw 'Identificador do perfil inválido.'}
    if($Profile.GameId -isnot [string] -or [string]::IsNullOrWhiteSpace($Profile.GameId) -or $Profile.GameId.Length -gt 200 -or $Profile.GameId -match '[\x00-\x1f]'){throw 'GameId inválido.'}
    foreach($field in @('GameName','Launcher','GpuPnpId','Resolution','ExecutablePath')){if($null -ne $Profile.$field -and ($Profile.$field -isnot [string] -or $Profile.$field.Length -gt 2048 -or $Profile.$field -match '[\x00-\x1f]')){throw ('Texto inválido no perfil: '+$field)}}
    foreach($field in @('PathAuthorized','CaptureRequired','WindowsSettingsChanged','DriverSettingsChanged')){if($Profile.$field -isnot [bool]){throw ('Flag inválida no perfil: '+$field)}}
    if($Profile.Status -cne 'GUIDANCE_ONLY' -or $Profile.WindowsSettingsChanged -or $Profile.DriverSettingsChanged -or $Profile.CapabilitySource -cne 'USER_CONFIRMED_OR_UNKNOWN'){throw 'Perfil não é somente orientação.'}
    if($Profile.Goal -notin @('Competitivo','Equilibrado','Qualidade / Captura') -or $Profile.Reflex -notin @('Unknown','Enabled','Disabled','Unsupported') -or $Profile.Vrr -notin @('Unknown','Enabled','Disabled','Unsupported') -or $Profile.VSync -notin @('Unknown','Enabled','Disabled')){throw 'Objetivo ou capacidade do perfil inválido.'}
    foreach($field in @('RefreshRateHz','FpsCap')){
        if($null -ne $Profile.$field){
            if($Profile.$field -isnot [ValueType] -or $Profile.$field -is [bool]){throw ('Métrica do perfil inválida: '+$field)}
            $value=[double]$Profile.$field;$maximum=if($field -eq 'RefreshRateHz'){1000}else{2000}
            if([double]::IsNaN($value) -or [double]::IsInfinity($value) -or $value -le 0 -or $value -gt $maximum){throw ('Métrica fora da faixa: '+$field)}
        }
    }
    if($Profile.Resolution){if($Profile.Resolution -notmatch '^(\d{3,5})x(\d{3,5})$' -or [int]$Matches[1] -lt 100 -or [int]$Matches[2] -lt 100 -or [int]$Matches[1] -gt 65535 -or [int]$Matches[2] -gt 65535){throw 'Resolução inválida.'}}
    if($Profile.ExecutablePath -and (-not $Profile.PathAuthorized -or -not [IO.Path]::IsPathRooted($Profile.ExecutablePath) -or [IO.Path]::GetExtension($Profile.ExecutablePath) -ine '.exe')){throw 'Caminho de jogo inválido ou não autorizado.'}
    $created=[datetime]::MinValue;if(-not [datetime]::TryParse([string]$Profile.CreatedUtc,[ref]$created)){throw 'Horário do perfil inválido.'}
}

function Save-GoatGpuGameProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Profile,[Parameter(Mandatory=$true)][string]$Path)
    Get-GoatGpuProfileAdvice -Profile $Profile | Out-Null
    if (-not [IO.Path]::IsPathRooted($Path) -or $Path -notlike '*.goat-profile.json') { throw 'Use caminho absoluto terminado em .goat-profile.json.' }
    $full=[IO.Path]::GetFullPath($Path);$parent=Split-Path $full -Parent
    if (-not (Test-Path -LiteralPath $parent -PathType Container)) { throw 'A pasta de destino deve existir.' }
    if (Test-Path -LiteralPath $full) { throw 'O arquivo já existe. Escolha outro nome para preservar o original.' }
    $bytes=[Text.Encoding]::UTF8.GetBytes(($Profile | ConvertTo-Json -Depth 8))
    $temporary=Join-Path $parent ([guid]::NewGuid().ToString('N')+'.goat-profile.tmp')
    try {
        $stream=New-Object IO.FileStream($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        try {$stream.Write($bytes,0,$bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
        [IO.File]::Move($temporary,$full)
    }finally{if([IO.File]::Exists($temporary)){[IO.File]::Delete($temporary)}}
    [pscustomobject]@{Path=$full;Sha256=(Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash.ToLowerInvariant();Status='SAVED_LOCAL_PROFILE';SystemSettingsChanged=$false}
}

function Import-GoatGpuGameProfile {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$Path)
    $item=Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $item.Length -gt 65536 -or $item.Name -notlike '*.goat-profile.json') { throw 'Arquivo de perfil inválido ou maior que 64 KiB.' }
    $profile=Get-Content -LiteralPath $item.FullName -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop
    Get-GoatGpuProfileAdvice -Profile $profile | Out-Null
    if ($profile.WindowsSettingsChanged -ne $false -or $profile.DriverSettingsChanged -ne $false -or $profile.Status -ne 'GUIDANCE_ONLY') { throw 'Perfil não é somente orientação.' }
    $profile
}
