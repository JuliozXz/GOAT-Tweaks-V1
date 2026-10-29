# Original read-only inventory and evidence-limited diagnosis. PowerShell 5.1.
function Invoke-GoatInventoryCim {
    param([string]$ClassName,[string]$Namespace='root/cimv2',[string[]]$Property,[string]$Filter,[int]$TimeoutSec=4)
    $parameters=@{ClassName=$ClassName;Namespace=$Namespace;OperationTimeoutSec=$TimeoutSec;ErrorAction='Stop'}
    if($Property){$parameters.Property=$Property}
    if($Filter){$parameters.Filter=$Filter}
    @(Get-CimInstance @parameters)
}
function Read-GoatInventoryRegistry {
    param([ValidateSet('LocalMachine','CurrentUser')][string]$Hive,[string]$Path,[string]$Name,[switch]$KeyExists)
    $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$Hive,[Microsoft.Win32.RegistryView]::Registry64)
    try {
        $key=$base.OpenSubKey($Path,$false)
        if($KeyExists){if($key){$key.Dispose();return $true};return $false}
        if(-not $key){return $null}
        try {$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)} finally {$key.Dispose()}
    } finally {$base.Dispose()}
}
function Get-GoatInventoryApps {
    # Read uninstall metadata only. No command lines, account paths, user IDs or tokens.
    $applications=New-Object 'System.Collections.Generic.List[object]'
    foreach($hive in @('LocalMachine','CurrentUser')) {
        foreach($view in @('Registry64','Registry32')) {
            $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::$hive,[Microsoft.Win32.RegistryView]::$view)
            try {
                $uninstall=$base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',$false)
                if(-not $uninstall){continue}
                try {
                    foreach($childName in $uninstall.GetSubKeyNames()) {
                        $child=$uninstall.OpenSubKey($childName,$false)
                        if(-not $child){continue}
                        try {
                            $name=[string]$child.GetValue('DisplayName',$null)
                            if($name -match '^(Steam|Discord|OBS Studio)(\s|$)') {
                                $applications.Add([pscustomobject]@{Name=$name;Version=$child.GetValue('DisplayVersion',$null);Source=('Uninstall metadata/'+$hive+'/'+$view);Confidence='Installed metadata; running version not confirmed'})
                            }
                        } finally {$child.Dispose()}
                    }
                } finally {$uninstall.Dispose()}
            } finally {$base.Dispose()}
        }
    }
    @($applications | Sort-Object Name,Version -Unique)
}
function ConvertTo-GoatInventoryNumber {
    param($Value)
    if($null -eq $Value){return $null}
    $parsed=0.0
    if([double]::TryParse([string]$Value,[Globalization.NumberStyles]::Float,[Globalization.CultureInfo]::InvariantCulture,[ref]$parsed) -and -not [double]::IsNaN($parsed) -and -not [double]::IsInfinity($parsed)){return $parsed}
    return $null
}
function Get-GoatInventory {
    [CmdletBinding()]
    param([switch]$Demo,[switch]$IncludeGpu,[switch]$SkipGpuTelemetry,[ValidateRange(1,15)][int]$TimeoutSec=4,[scriptblock]$QueryProvider,[scriptblock]$RegistryProvider,[scriptblock]$ProcessProvider,[scriptblock]$AppProvider)
    Set-StrictMode -Off # Missing CIM properties are reported as unknown, including under a strict caller.
    $now=[DateTime]::UtcNow.ToString('o')
    if($Demo) {
        # Explicit sample data; this branch does not invoke any system provider.
        return [pscustomobject]@{
            SchemaVersion=1;Demo=$true;CollectedUtc=$now;ReadOnly=$true;Status='DEMO'
            OS=[pscustomobject]@{Name='Windows 11 (DEMO)';Version='10.0';Build='26100';Edition='Demo';Architecture='64-bit';Source='Demo sample';Confidence='Simulated'}
            CPU=[pscustomobject]@{Name='CPU de demonstracao';Models=@('CPU de demonstracao');Cores=8;LogicalProcessors=16;Source='Demo sample';Confidence='Simulated'}
            Memory=[pscustomobject]@{TotalBytes=17179869184;InstalledBytes=17179869184;FreeBytes=8589934592;UsedPercent=50;Modules=@();Source='Demo sample';Confidence='Simulated'}
            Disks=@([pscustomobject]@{Name='C:';FileSystem='NTFS';SizeBytes=512000000000;FreeBytes=256000000000;FreePercent=50;Source='Demo sample';Confidence='Simulated'})
            PhysicalDisks=@();StorageReliability=[pscustomobject]@{Status='UNAVAILABLE';Devices=@();Source=$null;Note='Demo: nenhum dispositivo ou sensor consultado.'}
            Network=@([pscustomobject]@{Name='Adaptador DEMO';SpeedBitsPerSecond=1000000000;Source='Demo sample';Confidence='Simulated'})
            Startup=@([pscustomobject]@{Name='Entrada de demonstracao';Location='DEMO';Source='Demo sample'})
            Apps=@([pscustomobject]@{Name='Steam (DEMO)';Version='amostra';Source='Demo sample';Confidence='Simulated'})
            RemoteContext=[pscustomobject]@{IsRemote=$null;IsRdp=$false;RemoteProcessNames=@();Confidence='Demo; presence not established';DriverMaintenanceBlocked=$true;Source='Demo sample'}
            Security=[pscustomobject]@{UacEnabled=$null;HvciConfigured=$null;VbsStatus=$null;DefenderEnabled=$null;Source='Demo: nao consultado';Confidence='Unknown'}
            Reboot=[pscustomobject]@{Pending=$null;Reasons=@();Source='Demo: nao consultado';Confidence='Unknown'}
            Telemetry=[pscustomobject]@{SampleUtc=$now;CPU=[pscustomobject]@{TotalPercent=$null;Threads=@();Status='UNAVAILABLE';Source=$null};RAM=[pscustomobject]@{UsedPercent=$null;CommittedBytes=$null;CommitLimitBytes=$null;Status='UNAVAILABLE';Source=$null};GpuEngines=@();GpuTotalPercent=$null;Note='Demo sem medicao. Telemetria nao mede input lag nem FPS.'}
            GpuCenter=$null;SourceIssues=@();Providers=@();Privacy='Sem identificadores de cliente, serial, MAC, IP ou linha de comando.'
        }
    }
    if(-not $QueryProvider){$QueryProvider={param($ClassName,$Namespace,$Property,$Filter,$TimeoutSec) Invoke-GoatInventoryCim -ClassName $ClassName -Namespace $Namespace -Property $Property -Filter $Filter -TimeoutSec $TimeoutSec}}
    if(-not $RegistryProvider){$RegistryProvider={param($Hive,$Path,$Name,$KeyExists) Read-GoatInventoryRegistry -Hive $Hive -Path $Path -Name $Name -KeyExists:$KeyExists}}
    if(-not $ProcessProvider){$ProcessProvider={@(Get-Process -ErrorAction Stop | Select-Object -ExpandProperty ProcessName)}}
    if(-not $AppProvider){$AppProvider={Get-GoatInventoryApps}}
    $issues=New-Object 'System.Collections.Generic.List[object]'
    $providers=New-Object 'System.Collections.Generic.List[object]'
    function Read-InventoryQuery {
        param([string]$ClassName,[string[]]$Property,[string]$Namespace='root/cimv2',[string]$Filter)
        $watch=[Diagnostics.Stopwatch]::StartNew()
        try {
            $items=@(& $QueryProvider $ClassName $Namespace $Property $Filter $TimeoutSec | Where-Object {$null -ne $_})
            $status=if($items.Count){'READ_ONLY'}else{'EMPTY'}
            if(-not $items.Count){$issues.Add([pscustomobject]@{Source=($Namespace+'/'+$ClassName);Status='EMPTY';Reason='Provider retornou zero registros; dados permanecem indisponiveis.'})}
        } catch {
            $items=@();$status='UNAVAILABLE'
            $issues.Add([pscustomobject]@{Source=($Namespace+'/'+$ClassName);Status=$status;Reason=('Falha de consulta: '+$_.Exception.GetType().Name)})
        }
        $watch.Stop();$providers.Add([pscustomobject]@{Source=($Namespace+'/'+$ClassName);Status=$status;Count=$items.Count;DurationMs=$watch.ElapsedMilliseconds;OperationTimeoutSec=$TimeoutSec})
        return $items
    }
    function Read-InventoryValue {
        param([string]$Hive,[string]$Path,[string]$Name,[bool]$KeyExists=$false)
        try { & $RegistryProvider $Hive $Path $Name $KeyExists } catch {
            $issues.Add([pscustomobject]@{Source=($Hive+'/'+$Path+'/'+$Name);Status='UNAVAILABLE';Reason=('Falha de leitura: '+$_.Exception.GetType().Name)})
            return $null
        }
    }
    $osRows=@(Read-InventoryQuery 'Win32_OperatingSystem' @('Caption','Version','BuildNumber','OperatingSystemSKU','OSArchitecture','TotalVisibleMemorySize','FreePhysicalMemory'))
    $cpuRows=@(Read-InventoryQuery 'Win32_Processor' @('Name','NumberOfCores','NumberOfLogicalProcessors'))
    $memoryRows=@(Read-InventoryQuery 'Win32_PhysicalMemory' @('Capacity','Speed','ConfiguredClockSpeed'))
    $diskRows=@(Read-InventoryQuery 'Win32_LogicalDisk' @('DeviceID','FileSystem','Size','FreeSpace','DriveType') 'root/cimv2' 'DriveType=3')
    $physicalRows=@(Read-InventoryQuery 'Win32_DiskDrive' @('Model','MediaType','Size','InterfaceType','Status'))
    $reliabilityRows=@(Read-InventoryQuery 'MSFT_StorageReliabilityCounter' @('DeviceId','Temperature','Wear','ReadErrorsTotal','WriteErrorsTotal','PowerOnHours') 'root/Microsoft/Windows/Storage')
    $networkRows=@(Read-InventoryQuery 'Win32_NetworkAdapter' @('Name','NetConnectionID','Speed','PhysicalAdapter','NetEnabled') 'root/cimv2' 'NetEnabled=True')
    $startupRows=@(Read-InventoryQuery 'Win32_StartupCommand' @('Name','Location'))
    $deviceGuardRows=@(Read-InventoryQuery 'Win32_DeviceGuard' @('VirtualizationBasedSecurityStatus','SecurityServicesConfigured','SecurityServicesRunning') 'root/Microsoft/Windows/DeviceGuard')
    $defenderRows=@(Read-InventoryQuery 'MSFT_MpComputerStatus' @('AntivirusEnabled','RealTimeProtectionEnabled','AMServiceEnabled') 'root/Microsoft/Windows/Defender')
    $cpuPerf=@(Read-InventoryQuery 'Win32_PerfFormattedData_PerfOS_Processor' @('Name','PercentProcessorTime'))
    $memoryPerf=@(Read-InventoryQuery 'Win32_PerfFormattedData_PerfOS_Memory' @('CommittedBytes','CommitLimit','AvailableBytes'))
    $gpuPerf=@();if(-not $SkipGpuTelemetry){$gpuPerf=@(Read-InventoryQuery 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' @('Name','UtilizationPercentage'))}
    $os=if($osRows.Count){$osRows[0]}else{$null}
    $totalKb=ConvertTo-GoatInventoryNumber $os.TotalVisibleMemorySize
    $freeKb=ConvertTo-GoatInventoryNumber $os.FreePhysicalMemory
    $totalBytes=if($null -ne $totalKb -and $totalKb -gt 0){$totalKb*1024}else{$null}
    $freeBytes=if($null -ne $freeKb -and $freeKb -ge 0){$freeKb*1024}else{$null}
    $usedPercent=if($null -ne $totalBytes -and $totalBytes -gt 0 -and $null -ne $freeBytes -and $freeBytes -ge 0 -and $freeBytes -le $totalBytes){[Math]::Round(100*(1-$freeBytes/$totalBytes),2)}else{$null}
    $capacities=@($memoryRows | ForEach-Object {ConvertTo-GoatInventoryNumber $_.Capacity} | Where-Object {$null -ne $_ -and $_ -gt 0})
    $installedBytes=if($capacities.Count){($capacities | Measure-Object -Sum).Sum}else{$null}
    $models=@($cpuRows | ForEach-Object {$_.Name} | Where-Object {$_} | Sort-Object -Unique)
    $coreValues=@($cpuRows | ForEach-Object {ConvertTo-GoatInventoryNumber $_.NumberOfCores} | Where-Object {$null -ne $_ -and $_ -gt 0})
    $threadValues=@($cpuRows | ForEach-Object {ConvertTo-GoatInventoryNumber $_.NumberOfLogicalProcessors} | Where-Object {$null -ne $_ -and $_ -gt 0})
    $coreCount=if($coreValues.Count){($coreValues | Measure-Object -Sum).Sum}else{$null}
    $threadCount=if($threadValues.Count){($threadValues | Measure-Object -Sum).Sum}else{$null}
    $isRdp=($env:SESSIONNAME -match '^RDP-|^ICA-')
    $processKnown=$true
    try {$processNames=@(& $ProcessProvider)}catch{$processNames=@();$processKnown=$false;$issues.Add([pscustomobject]@{Source='Get-Process';Status='UNAVAILABLE';Reason='Nomes de processo indisponiveis; contexto remoto permanece incerto.'})}
    $remoteNames=@($processNames | Where-Object {$_ -match '^(AnyDesk|TeamViewer|TeamViewer_Service|RustDesk|rustdesk_service|ScreenConnect.*|Splashtop.*|SRServer|Parsec|parsecd|supremo.*|winvnc|tvnserver|remoting_host)$'} | Sort-Object -Unique)
    $remoteState=if($isRdp){$true}elseif($remoteNames.Count){$null}elseif($processKnown -and $env:SESSIONNAME -eq 'Console'){$false}else{$null}
    try {$apps=@(& $AppProvider)}catch{$apps=@();$issues.Add([pscustomobject]@{Source='Uninstall metadata';Status='UNAVAILABLE';Reason='Versoes dos aplicativos indisponiveis.'})}
    $uac=Read-InventoryValue 'LocalMachine' 'SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System' 'EnableLUA'
    $hvci=Read-InventoryValue 'LocalMachine' 'SYSTEM\CurrentControlSet\Control\DeviceGuard\Scenarios\HypervisorEnforcedCodeIntegrity' 'Enabled'
    $cbs=Read-InventoryValue 'LocalMachine' 'SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending' '' $true
    $wu=Read-InventoryValue 'LocalMachine' 'SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired' '' $true
    $pendingRename=Read-InventoryValue 'LocalMachine' 'SYSTEM\CurrentControlSet\Control\Session Manager' 'PendingFileRenameOperations'
    $rebootReasons=@();if($cbs -eq $true){$rebootReasons+='Component Based Servicing'};if($wu -eq $true){$rebootReasons+='Windows Update'};if($null -ne $pendingRename -and @($pendingRename).Count -gt 0){$rebootReasons+='Pending file operations'}
    $rebootReadFailed=@($issues | Where-Object {$_.Status -eq 'UNAVAILABLE' -and $_.Source -match 'Component Based Servicing|WindowsUpdate.+RebootRequired|Session Manager/PendingFileRenameOperations'}).Count -gt 0
    $rebootPending=if($rebootReasons.Count){$true}elseif($null -ne $cbs -and $null -ne $wu -and -not $rebootReadFailed){$false}else{$null}
    $cpuTotal=@($cpuPerf | Where-Object Name -eq '_Total' | Select-Object -First 1)
    $cpuNumber=if($cpuTotal.Count){ConvertTo-GoatInventoryNumber $cpuTotal[0].PercentProcessorTime}else{$null}
    $cpuValue=if($null -ne $cpuNumber -and $cpuNumber -ge 0 -and $cpuNumber -le 100){$cpuNumber}else{$null}
    $gpuEngines=@(foreach($engine in $gpuPerf){$engineValue=ConvertTo-GoatInventoryNumber $engine.UtilizationPercentage;if($null -ne $engineValue -and $engineValue -ge 0 -and $engineValue -le 100){[pscustomobject]@{Instance=$engine.Name;Percent=$engineValue;Source='Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine';Confidence='Per-engine instance only; not GPU total'}}})
    $reliability=@(foreach($row in $reliabilityRows){[pscustomobject]@{DeviceId=$row.DeviceId;TemperatureC=$row.Temperature;WearPercent=$row.Wear;ReadErrorsTotal=$row.ReadErrorsTotal;WriteErrorsTotal=$row.WriteErrorsTotal;PowerOnHours=$row.PowerOnHours;Source='MSFT_StorageReliabilityCounter';Confidence='Provider-reported; support varies'}})
    $gpuCenter=$null
    if($IncludeGpu -and (Get-Command Get-GoatGpuCenter -ErrorAction SilentlyContinue)) {try{$gpuCenter=Get-GoatGpuCenter -IncludeTelemetry}catch{$issues.Add([pscustomobject]@{Source='Get-GoatGpuCenter';Status='UNAVAILABLE';Reason=$_.Exception.GetType().Name})}}
    [pscustomobject]@{
        SchemaVersion=1;Demo=$false;CollectedUtc=$now;ReadOnly=$true;Status=$(if($issues.Count){'PARTIAL'}else{'READ_ONLY'})
        OS=[pscustomobject]@{Name=$os.Caption;Version=$os.Version;Build=$os.BuildNumber;Edition=$os.OperatingSystemSKU;Architecture=$os.OSArchitecture;Source='Win32_OperatingSystem';Confidence=$(if($os){'Provider-reported'}else{'Unknown'})}
        CPU=[pscustomobject]@{Name=($models -join '; ');Models=$models;Cores=$coreCount;LogicalProcessors=$threadCount;Source='Win32_Processor';Confidence=$(if($cpuRows.Count){'Provider-reported'}else{'Unknown'})}
        Memory=[pscustomobject]@{TotalBytes=$totalBytes;InstalledBytes=$installedBytes;FreeBytes=$freeBytes;UsedPercent=$usedPercent;Modules=@($memoryRows | ForEach-Object {[pscustomobject]@{CapacityBytes=$_.Capacity;SpeedMhz=$_.Speed;ConfiguredSpeedMhz=$_.ConfiguredClockSpeed}});Source='Win32_OperatingSystem + Win32_PhysicalMemory';Confidence=$(if($null -ne $usedPercent){'Read-only snapshot'}else{'Unknown'})}
        Disks=@($diskRows | ForEach-Object {$diskSize=ConvertTo-GoatInventoryNumber $_.Size;$diskFree=ConvertTo-GoatInventoryNumber $_.FreeSpace;[pscustomobject]@{Name=$_.DeviceID;FileSystem=$_.FileSystem;SizeBytes=$diskSize;FreeBytes=$diskFree;FreePercent=$(if($null -ne $diskSize -and $diskSize -gt 0 -and $null -ne $diskFree -and $diskFree -ge 0 -and $diskFree -le $diskSize){[Math]::Round(100*$diskFree/$diskSize,2)}else{$null});Source='Win32_LogicalDisk';Confidence='Provider-reported'}})
        PhysicalDisks=@($physicalRows | ForEach-Object {[pscustomobject]@{Model=$_.Model;MediaType=$_.MediaType;SizeBytes=$_.Size;InterfaceType=$_.InterfaceType;ProviderStatus=$_.Status;Source='Win32_DiskDrive';Note='ProviderStatus does not prove full SMART health.'}})
        StorageReliability=[pscustomobject]@{Status=$(if($reliability.Count){'PARTIAL'}else{'UNAVAILABLE'});Devices=$reliability;Source='MSFT_StorageReliabilityCounter';Note='Metricas so quando o provedor expuser; ausencia nao significa disco saudavel.'}
        Network=@($networkRows | ForEach-Object {[pscustomobject]@{Name=$_.Name;ConnectionName=$_.NetConnectionID;SpeedBitsPerSecond=$_.Speed;PhysicalAdapter=$_.PhysicalAdapter;Source='Win32_NetworkAdapter';Confidence='Link metadata; no RTT, jitter or throughput measured'}})
        Startup=@($startupRows | ForEach-Object {[pscustomobject]@{Name=$_.Name;Location=$_.Location;Source='Win32_StartupCommand';Note='Comando e usuario omitidos; impacto nao medido.'}})
        Apps=$apps
        RemoteContext=[pscustomobject]@{IsRemote=$remoteState;IsRdp=$isRdp;RemoteProcessNames=$remoteNames;Confidence=$(if($isRdp){'SESSIONNAME indicates RDP/ICA'}elseif($remoteNames.Count){'Remote software present; active connection unknown'}else{'Session environment and process names; physical presence not proven'});DriverMaintenanceBlocked=$true;Source='SESSIONNAME + Get-Process names';Note='Liberacao de manutencao de driver exige pessoa local e plano de recuperacao em fluxo separado.'}
        Security=[pscustomobject]@{UacEnabled=$(if($null -ne $uac){[bool]$uac}else{$null});HvciConfigured=$(if($null -ne $hvci){[bool]$hvci}else{$null});VbsStatus=$(if($deviceGuardRows.Count){$deviceGuardRows[0].VirtualizationBasedSecurityStatus}else{$null});SecurityServicesRunning=$(if($deviceGuardRows.Count){@($deviceGuardRows[0].SecurityServicesRunning)}else{@()});DefenderEnabled=$(if($defenderRows.Count){$defenderRows[0].AntivirusEnabled}else{$null});DefenderRealTimeEnabled=$(if($defenderRows.Count){$defenderRows[0].RealTimeProtectionEnabled}else{$null});Source='Registry read + DeviceGuard/Defender CIM';Confidence='Reported state; no security setting changed'}
        Reboot=[pscustomobject]@{Pending=$rebootPending;Reasons=$rebootReasons;Source='CBS + Windows Update + Session Manager flags';Confidence='Known indicators only; not a complete reboot guarantee'}
        Telemetry=[pscustomobject]@{SampleUtc=$now;CPU=[pscustomobject]@{TotalPercent=$cpuValue;Threads=@($cpuPerf | Where-Object Name -ne '_Total' | ForEach-Object {[pscustomobject]@{Name=$_.Name;Percent=$_.PercentProcessorTime}});Status=$(if($null -ne $cpuValue){'READ_ONLY'}else{'UNAVAILABLE'});Source='Win32_PerfFormattedData_PerfOS_Processor'};RAM=[pscustomobject]@{UsedPercent=$usedPercent;CommittedBytes=$(if($memoryPerf.Count){$memoryPerf[0].CommittedBytes}else{$null});CommitLimitBytes=$(if($memoryPerf.Count){$memoryPerf[0].CommitLimit}else{$null});Status=$(if($null -ne $usedPercent){'READ_ONLY'}else{'UNAVAILABLE'});Source='Win32_OperatingSystem + PerfOS_Memory'};GpuEngines=$gpuEngines;GpuTotalPercent=$null;Note='Snapshot; motores GPU nao sao somados. Sem temperatura/clocks/VRAM de fonte validada = indisponivel. Sem medicao de input lag/FPS.'}
        GpuCenter=$gpuCenter;SourceIssues=@($issues.ToArray());Providers=@($providers.ToArray());Privacy='No client name, serial, MAC, IP, process command line, startup command or credentials collected.'
    }
}
function Get-GoatCompleteInventory {
    [CmdletBinding()]
    param([switch]$Demo)
    Set-StrictMode -Off
    # GPU telemetry is queried by the GPU module once; the base inventory skips it.
    $inventory=Get-GoatInventory -Demo:$Demo -SkipGpuTelemetry
    try {
        if(-not (Get-Command Get-GoatGpuCenter -ErrorAction SilentlyContinue)){throw 'GpuModuleUnavailable'}
        $inventory.GpuCenter=Get-GoatGpuCenter -Demo:$Demo -IncludeTelemetry
        $inventory.Telemetry.GpuEngines=@($inventory.GpuCenter.Telemetry.EngineLoads | ForEach-Object {
            [pscustomobject]@{Instance=$_.Instance;Percent=$_.Value;Source=$_.Source;Confidence='Per-engine instance only; not GPU total'}
        })
        $inventory.Telemetry.GpuTotalPercent=$null
        if($inventory.GpuCenter.RemoteContext.IsRemoteOrUncertain -and $inventory.RemoteContext.IsRemote -eq $false){
            $inventory.RemoteContext.IsRemote=$null
            $inventory.RemoteContext.Confidence='GPU safety provider indicates remote or unknown; physical presence not proven'
        }
        $inventory.RemoteContext.DriverMaintenanceBlocked=$true
    } catch {
        $inventory.GpuCenter=[pscustomobject]@{
            SchemaVersion=1;Status='UNAVAILABLE';ReadOnly=$true;Devices=@();Monitors=@();System=$null
            RemoteContext=[pscustomobject]@{State='UNKNOWN';IsRemoteOrUncertain=$true;Indicators=@('GPU provider unavailable');Source='Get-GoatCompleteInventory'}
            Telemetry=[pscustomobject]@{Status='UNAVAILABLE';Metrics=@();EngineLoads=@();Note='GPU provider unavailable; no values invented.'}
            DriverGuides=@();Recommendations=@();Warnings=@('GPU inventory unavailable; dependent capabilities remain unknown.')
            Capabilities=[pscustomobject]@{Vrr='UNKNOWN';Hags='UNKNOWN';ActiveGameGpu='UNKNOWN';DedicatedVram='UNKNOWN'}
        }
        $inventory.SourceIssues+= [pscustomobject]@{Source='Get-GoatGpuCenter';Status='UNAVAILABLE';Reason=$_.Exception.GetType().Name}
        if(-not $Demo){$inventory.Status='PARTIAL'}
    }
    $inventory
}
function Get-GoatDiagnosis {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)]$Inventory,[ValidateSet('Equilibrado','Competitivo','Qualidade')][string]$Objective='Equilibrado')
    $items=New-Object 'System.Collections.Generic.List[object]'
    function Add-InventoryAdvice {
        param([string]$Id,[string]$Title,[string]$Reason,[string]$Recommendation,[string]$Risk,[string]$Confidence,[string]$Source)
        if($items.Count -lt 7){$items.Add([pscustomobject]@{Id=$Id;Title=$Title;Reason=$Reason;Recommendation=$Recommendation;Risk=$Risk;Confidence=$Confidence;Source=$Source;PerformanceEvidence='Nao medido';Execution='GuideOnly';Objective=$Objective;Demo=[bool]$Inventory.Demo})}
    }
    if($Inventory.Demo){Add-InventoryAdvice 'DEMO' 'Sessao de demonstracao' 'O inventario contem amostras explicitamente simuladas.' 'Execute um inventario real para avaliar esta maquina; nenhum ganho foi medido.' 'Nenhum: leitura' 'Simulated' 'Demo'}
    if($Inventory.Reboot.Pending -eq $true){Add-InventoryAdvice 'REBOOT-READINESS' 'Reinicio pendente' ($Inventory.Reboot.Reasons -join '; ') 'Combine reinicio com o cliente antes de comparar condicoes. Nunca reiniciar automaticamente.' 'Perda de acesso remoto se reiniciar' 'Known Windows flags' $Inventory.Reboot.Source}
    if($Inventory.RemoteContext.IsRemote -ne $false -or @($Inventory.RemoteContext.RemoteProcessNames).Count){Add-InventoryAdvice 'REMOTE-PROTECTION' 'Proteger acesso remoto e video' $Inventory.RemoteContext.Confidence 'Mantenha manutencao de driver/DDU bloqueada sem pessoa local e plano de recuperacao.' 'Perda de video/acesso' 'Conservative safety gate' $Inventory.RemoteContext.Source}
    if($Inventory.GpuCenter -and @($Inventory.GpuCenter.Capabilities.PSObject.Properties | Where-Object {$_.Value -eq 'UNKNOWN'}).Count){Add-InventoryAdvice 'GPU-CAPABILITIES' 'Confirmar capacidades da GPU e monitor' 'HAGS, VRR, GPU ativa no jogo ou VRAM dedicada ainda possuem estado desconhecido.' 'Confira capacidades do jogo/driver/monitor e os paineis oficiais antes de recomendar. Nao use chaves privadas de driver para preencher ou alterar estados desconhecidos.' 'Tradeoffs de video/captura dependem de suporte real' 'Unknown capabilities' 'GPU CENTER / Capabilities'}
    $lowSpace=@($Inventory.Disks | Where-Object {$null -ne $_.FreePercent -and [double]$_.FreePercent -lt 15})
    if($lowSpace.Count){Add-InventoryAdvice 'DISK-SPACE' 'Pouco espaco livre' (($lowSpace | ForEach-Object {$_.Name+': '+$_.FreePercent+'% livre'}) -join '; ') 'Revise arquivos com o cliente e ferramentas nativas; nao remover dados ou logs automaticamente. 15% e triagem, nao garantia de desempenho.' 'Exclusao requer revisao' 'Free-space snapshot' 'Win32_LogicalDisk'}
    if($null -ne $Inventory.Memory.UsedPercent -and [double]$Inventory.Memory.UsedPercent -ge 85){Add-InventoryAdvice 'RAM-PRESSURE' 'Pressao de memoria no snapshot' ('RAM usada: '+$Inventory.Memory.UsedPercent+'%.') 'Meça commit e o mesmo jogo sob carga. Revise apps por consumo; mantenha pagefile suportado. Nao limpar standby como ganho universal.' 'Fechar apps pode perder trabalho' 'Single snapshot; workload not confirmed' $Inventory.Memory.Source}
    if(@($Inventory.Startup).Count -gt 0){Add-InventoryAdvice 'STARTUP-REVIEW' 'Revisar inicializacao por aplicativo' (@($Inventory.Startup).Count.ToString()+' entradas inventariadas; impacto ainda nao medido.') 'Identifique itens dispensaveis com o cliente e verifique impacto por entrada nas configuracoes do Windows; preservar ferramentas remotas.' 'Pode afetar funcionalidades do app' 'Inventory only' 'Win32_StartupCommand'}
    if(@($Inventory.SourceIssues).Count -gt 0){Add-InventoryAdvice 'MISSING-EVIDENCE' 'Dados parciais ou indisponiveis' (@($Inventory.SourceIssues).Count.ToString()+' consultas ou leituras sem evidencia completa.') 'Consulte as fontes indisponiveis antes de recomendar alteracoes dependentes delas. N/D nunca equivale a zero ou estado saudavel.' 'Nenhum: leitura' 'Unknown for missing providers' 'SourceIssues'}
    if($Objective -eq 'Qualidade'){Add-InventoryAdvice 'CAPTURE-COMPAT' 'Preservar captura e qualidade' 'Objetivo de qualidade selecionado.' 'Registre resolucao, encoder e configuracao de captura; confira render/encode lag no OBS antes de desativar overlays ou recursos.' 'Mudancas podem interromper captura' 'Workload context required' 'Objetivo do atendimento'}
    elseif($Objective -eq 'Competitivo'){Add-InventoryAdvice 'FRAME-PACING' 'Avaliar consistencia no jogo alvo' 'Objetivo competitivo selecionado; latencia nao foi medida.' 'Use o mesmo cenario e 3-5 passadas A/B. Registre Reflex/VRR/V-Sync/cap do jogo e evite limites sobrepostos.' 'Tradeoffs de tearing/qualidade dependem do jogo' 'Hypothesis; no measured gain' 'Objetivo do atendimento + benchmark comparavel'}
    else{Add-InventoryAdvice 'BALANCED-BASELINE' 'Estabelecer baseline equilibrado' 'Objetivo equilibrado selecionado.' 'Registre cena, driver, resolucao, captura e condicoes; compare desempenho e estabilidade antes/depois sem prometer ganho.' 'Nenhum: medicao guiada' 'Hypothesis; no measured gain' 'Objetivo do atendimento + benchmark comparavel'}
    @($items.ToArray())
}
