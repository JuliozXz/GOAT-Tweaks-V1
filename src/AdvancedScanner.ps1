# Read-only advanced probes. Windows PowerShell 5.1; no setting is written.
# API references: https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/options-for-core-parking-cpmincores
# https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapterpowermanagement?view=windowsserver2022-ps
# https://learn.microsoft.com/en-us/powershell/module/netqos/get-netqospolicy?view=windowsserver2025-ps
# https://learn.microsoft.com/en-us/powershell/module/appx/get-appxpackage
# https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set
# https://learn.microsoft.com/en-us/windows-hardware/drivers/storage/msft-physicaldisk
# https://learn.microsoft.com/en-us/windows/win32/api/winbase/ns-winbase-system_power_status

function Invoke-GoatAdvancedReadCommand {
    [CmdletBinding()]
    param([string]$Command,[hashtable]$Parameters=@{},[string[]]$Properties=@(),[int]$First=0,[int]$TimeoutMilliseconds=2500)
    $allowed=@('Get-MMAgent','Get-CimInstance','Get-NetTCPSetting','Get-NetOffloadGlobalSetting','Get-NetQosPolicy','Get-NetAdapterPowerManagement','Get-AppxPackage','Get-PhysicalDisk')
    if ($Command -notin $allowed) { throw 'Consulta avançada fora da lista permitida.' }
    $pipeline=[PowerShell]::Create(); $pending=$null
    try {
        $null=$pipeline.AddCommand($Command)
        foreach ($key in $Parameters.Keys) { $null=$pipeline.AddParameter($key,$Parameters[$key]) }
        $null=$pipeline.AddParameter('ErrorAction','Stop')
        if ($Properties.Count -gt 0 -or $First -gt 0) {
            $null=$pipeline.AddCommand('Select-Object')
            if ($Properties.Count -gt 0) { $null=$pipeline.AddParameter('Property',$Properties) }
            if ($First -gt 0) { $null=$pipeline.AddParameter('First',$First) }
        }
        $pending=$pipeline.BeginInvoke()
        if (-not $pending.AsyncWaitHandle.WaitOne($TimeoutMilliseconds)) { $pipeline.Stop(); throw "Tempo limite de consulta: $Command ($TimeoutMilliseconds ms)." }
        $result=$pipeline.EndInvoke($pending)
        if ($pipeline.HadErrors) { throw ($pipeline.Streams.Error | Out-String).Trim() }
        return $result
    }
    finally { if ($pending) { $pending.AsyncWaitHandle.Close() }; $pipeline.Dispose() }
}

function Invoke-GoatAdvancedNativeRead {
    [CmdletBinding()]
    param([ValidateSet('powercfg','bcdedit')][string]$Command,[string[]]$Arguments,[int]$TimeoutMilliseconds=2500)
    # The only accepted argument shapes are read-only queries with fixed aliases.
    $joined=$Arguments -join ' '
    if ($Command -eq 'powercfg' -and $joined -notmatch '^/(query|qh) SCHEME_CURRENT SUB_PROCESSOR CP(MIN|MAX)CORES$') { throw 'Consulta powercfg não permitida.' }
    if ($Command -eq 'bcdedit' -and $joined -ne '/enum {current}') { throw 'Consulta BCD não permitida.' }
    $start=New-Object Diagnostics.ProcessStartInfo
    $start.FileName=Join-Path $env:SystemRoot ('System32\'+$Command+'.exe')
    $start.Arguments=$joined; $start.UseShellExecute=$false; $start.CreateNoWindow=$true
    $start.RedirectStandardOutput=$true; $start.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process
    $process.StartInfo=$start
    try {
        if (-not $process.Start()) { throw "Não foi possível consultar $Command." }
        $stdout=$process.StandardOutput.ReadToEndAsync(); $stderr=$process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutMilliseconds)) { try {$process.Kill()} catch {}; throw "Tempo limite de consulta: $Command." }
        $output=$stdout.GetAwaiter().GetResult(); $errorText=$stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0) { throw ("{0}: código {1}. {2} {3}" -f $Command,$process.ExitCode,$output.Trim(),$errorText.Trim()) }
        return $output
    }
    finally { $process.Dispose() }
}

function Get-GoatAdvancedRegistryValue {
    [CmdletBinding()]
    param([ValidateSet('HKLM','HKCU')][string]$Hive,[string]$Path,[string]$Name)
    $base=$null; $key=$null
    try {
        $hiveId=[Microsoft.Win32.RegistryHive]::LocalMachine
        if ($Hive -eq 'HKCU') { $hiveId=[Microsoft.Win32.RegistryHive]::CurrentUser }
        $base=[Microsoft.Win32.RegistryKey]::OpenBaseKey($hiveId,[Microsoft.Win32.RegistryView]::Registry64)
        $key=$base.OpenSubKey($Path,$false)
        $exists=$null -ne $key -and @($key.GetValueNames()) -contains $Name
        $value=$null; $type=$null
        if ($exists) { $value=$key.GetValue($Name,$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames); $type=$key.GetValueKind($Name).ToString() }
        return [pscustomobject]@{Hive=$Hive;Path=$Path;Name=$Name;Exists=[bool]$exists;Value=$value;Type=$type}
    }
    finally { if ($key) {$key.Dispose()}; if ($base) {$base.Dispose()} }
}

function ConvertFrom-GoatParkingQuery {
    [CmdletBinding()]
    param([string]$Text)
    # Locale-neutral: numeric AC and DC indices are the final two hex values.
    # Earlier hex fields are the possible minimum/maximum/increment metadata.
    $indices=[regex]::Matches($Text,'(?im)^.*:\s*0x([0-9a-f]{1,8})\s*$')
    if ($indices.Count -lt 2) { throw 'Índices AC/DC não encontrados na saída powercfg.' }
    $ac=[Convert]::ToInt32($indices[$indices.Count-2].Groups[1].Value,16)
    $dc=[Convert]::ToInt32($indices[$indices.Count-1].Groups[1].Value,16)
    if ($ac -lt 0 -or $ac -gt 100 -or $dc -lt 0 -or $dc -gt 100) { throw 'Percentual de core parking fora do intervalo documentado.' }
    $scheme=[regex]::Match($Text,'[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}')
    return [pscustomobject]@{AC=$ac;DC=$dc;Scheme=$(if ($scheme.Success) {$scheme.Value.ToLowerInvariant()} else {$null})}
}

function Get-GoatAdvancedTempObservation {
    [CmdletBinding()]
    param([int]$MaximumEntries=1000,[int]$MaximumMilliseconds=750,[string]$Path=$env:TEMP)
    $clock=[Diagnostics.Stopwatch]::StartNew()
    if (-not $Path -or -not [IO.Directory]::Exists($Path)) { throw 'Pasta TEMP do usuário indisponível.' }
    $root=[IO.Path]::GetFullPath($Path)
    $pending=New-Object 'System.Collections.Generic.Stack[string]'; $pending.Push($root)
    $failures=New-Object 'System.Collections.Generic.List[string]'
    $bytes=0L; $files=0; $visited=0; $seen=0; $truncated=$false
    while ($pending.Count -gt 0) {
        if ($clock.ElapsedMilliseconds -ge $MaximumMilliseconds -or $seen -ge $MaximumEntries) { $truncated=$true; break }
        $directory=$pending.Pop(); $visited++; $enumerator=$null
        try {
            $enumerator=[IO.Directory]::EnumerateFileSystemEntries($directory).GetEnumerator()
            while ($enumerator.MoveNext()) {
                if ($clock.ElapsedMilliseconds -ge $MaximumMilliseconds -or $seen -ge $MaximumEntries) { $truncated=$true; break }
                $entry=$enumerator.Current; $seen++
                try {
                    $attributes=[IO.File]::GetAttributes($entry)
                    if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
                    if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) { $pending.Push($entry) }
                    else { $bytes+=(New-Object IO.FileInfo($entry)).Length; $files++ }
                } catch { $failures.Add($_.Exception.Message) }
            }
        } catch { $failures.Add($_.Exception.Message) }
        finally { if ($enumerator -is [IDisposable]) {$enumerator.Dispose()} }
        if ($truncated) { break }
    }
    $clock.Stop()
    return [pscustomobject]@{Path=$root;BytesObserved=$bytes;FilesObserved=$files;DirectoriesVisited=$visited;Truncated=$truncated;Errors=@($failures.ToArray());DurationMs=$clock.ElapsedMilliseconds}
}

function New-GoatAdvancedReading {
    param([bool]$Available,$Value,[string]$Text,[string]$Error='')
    return [pscustomobject]@{Available=$Available;Value=$Value;Text=$Text;Error=$Error}
}

function Get-GoatAdvancedPowerContext {
    # .NET wraps GetSystemPowerStatus; loading the installed assembly does not
    # compile a helper or change settings. Unknown is retained as null.
    Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
    $status=[System.Windows.Forms.SystemInformation]::PowerStatus
    $line=[string]$status.PowerLineStatus
    $charge=[int]$status.BatteryChargeStatus
    $hasBattery=$null; $onBattery=$null; $onAC=$null; $percentage=$null
    if($charge -ne 255){$hasBattery=(($charge -band 128)-eq 0)}
    if($line -eq 'Online'){$onAC=$true;$onBattery=$false}
    elseif($line -eq 'Offline'){$onAC=$false;if($null -ne $hasBattery){$onBattery=[bool]$hasBattery}}
    if($null -ne $hasBattery -and $hasBattery -and $status.BatteryLifePercent -ge 0 -and $status.BatteryLifePercent -le 1){$percentage=[math]::Round(100*$status.BatteryLifePercent)}
    return [pscustomobject]@{OnBattery=$onBattery;OnAC=$onAC;HasBattery=$hasBattery;ACLineStatus=$line;BatteryChargeStatus=[string]$status.BatteryChargeStatus;BatteryPercent=$percentage;Source='GetSystemPowerStatus / SystemInformation.PowerStatus'}
}

function Get-GoatAdvancedStorageContext {
    $primaryError=''
    try{
        $disks=@(Invoke-GoatAdvancedReadCommand 'Get-PhysicalDisk' @{} @('FriendlyName','MediaType','BusType','Size') -First 32)
        if($disks.Count -eq 0){throw 'Nenhum PhysicalDisk retornado.'}
        $items=@($disks|ForEach-Object{
            $type='Unknown'
            switch(([string]$_.MediaType).ToUpperInvariant()){'3'{$type='HDD'};'HDD'{$type='HDD'};'4'{$type='SSD'};'SSD'{$type='SSD'};'5'{$type='SCM'};'SCM'{$type='SCM'}}
            [pscustomobject]@{Name=$_.FriendlyName;MediaType=$type;MediaTypeKnown=($type-ne 'Unknown');BusType=[string]$_.BusType;Size=$_.Size;Source='Get-PhysicalDisk'}
        })
        return [pscustomobject]@{Disks=$items;Source='Get-PhysicalDisk';Fallback=$false;PrimaryError=''}
    }
    catch{$primaryError=$_.Exception.Message}
    $fallback=@(Invoke-GoatAdvancedReadCommand 'Get-CimInstance' @{ClassName='Win32_DiskDrive';OperationTimeoutSec=2} @('Model','InterfaceType','MediaType','Size') -First 32)
    if($fallback.Count -eq 0){throw ('Inventário de armazenamento indisponível. '+$primaryError)}
    $items=@($fallback|ForEach-Object{
        # Win32_DiskDrive.MediaType describes fixed/removable, not HDD/SSD.
        # Model and NVMe-looking names are never used to guess the media type.
        [pscustomobject]@{Name=$_.Model;MediaType='Unknown';MediaTypeKnown=$false;BusType=[string]$_.InterfaceType;Size=$_.Size;Source='Win32_DiskDrive'}
    })
    return [pscustomobject]@{Disks=$items;Source='Win32_DiskDrive';Fallback=$true;PrimaryError=$primaryError}
}

function Get-GoatAdvancedState {
    [CmdletBinding()]
    param([switch]$Demo,$Scan)
    $readings=@{}; $errors=New-Object 'System.Collections.Generic.List[string]'
    if ($Demo) {
        $fixture=@{
            'memory-compression'=@($true,$false,'Compressão de memória desativada (exemplo).')
            'system-cache'=@($true,0,'LargeSystemCache=0 (preferência de Registro; exemplo).')
            'core-parking'=@($true,[pscustomobject]@{MinimumAC=10;MinimumDC=10;MaximumAC=100;MaximumDC=100;ActiveScheme='381b4222-f694-41f0-9685-ff5bb260df2e'},'Plano de demonstração: mínimo AC/DC 10%; máximo AC/DC 100%. Não mede núcleos estacionados agora.')
            'cpu-architecture'=@($true,[pscustomobject]@{Code=9;Name='x64';Cores=8;Threads=16},'x64; 8 núcleos / 16 threads (exemplo). Sem inferência de núcleos P/E.')
            'process-scheduling'=@($true,38,'Win32PrioritySeparation=38 (0x26); valor bruto de exemplo.')
            'msi-gpu'=@($true,@([pscustomobject]@{Name='GPU de demonstração';PnpDeviceId='DEMO\GPU';MsiEnabled=$true;InterruptPriority='Indefinida'}),'MSI declarado no Registro da GPU de exemplo; não comprova interrupção em execução.')
            'msi-storage'=@($true,@([pscustomobject]@{Name='Controlador NVMe de exemplo';PnpDeviceId='DEMO\NVME';MsiEnabled=$true;InterruptPriority=$null}),'MSI configurado para controlador de exemplo; estado runtime não medido.')
            'hags'=@($true,2,'HwSchMode=2: preferência ligada no exemplo; suporte e uso runtime não comprovados.')
            'rebar'=@($false,$null,'Resizable BAR precisa de validação no firmware e painel oficial; sem detecção universal confiável.')
            'cstates'=@($false,$null,'C-States exigem leitura específica de firmware/hardware; não são inferidos do nome da CPU.')
            'timers'=@($true,@{useplatformclock=$null;useplatformtick=$null;disabledynamictick=$null;tscsyncpolicy=$null;debug=$null;bootdebug=$null},'Exemplo sem overrides BCD. Isso não identifica o timer efetivamente usado.')
            'network-autotuning'=@($true,'normal','Auto-tuning do perfil Internet: normal (exemplo).')
            'rss'=@($true,'Enabled','RSS global: Enabled (exemplo); suporte por NIC varia.')
            'qos'=@($true,[pscustomobject]@{Policies=@();NonBestEffortLimit=[pscustomobject]@{Exists=$false;Value=$null}},'Exemplo: nenhuma política QoS efetiva; limite não configurado. Não implica perda de 20% da conexão.')
            'adapter-power'=@($true,@([pscustomobject]@{Name='Ethernet (exemplo)';AllowComputerToTurnOffDevice='Enabled';SelectiveSuspend='Unsupported'}),'Energia do adaptador de exemplo; propriedade não suportada não é desativada.')
            'windows-update'=@($true,[pscustomobject]@{Services=@([pscustomobject]@{Name='wuauserv';StartMode='Manual';State='Stopped'});Policies=@()},'Windows Update: início manual, parado (exemplo); não indica falha ou bloqueio por si só.')
            'services'=@($true,@([pscustomobject]@{Name='SysMain';DisplayName='SysMain';StartMode='Auto';State='Running'}),'Serviços de exemplo para revisão; nenhum é classificado como supérfluo automaticamente.')
            'appx'=@($true,@([pscustomobject]@{Name='Microsoft.WindowsCalculator';Version='Exemplo';PackageFullName='DEMO';IsFramework=$false;NonRemovable=$false}),'Pacotes do usuário atual: exemplo ilustrativo; nenhuma remoção.')
            'cache'=@($true,[pscustomobject]@{Path='C:\Demo\Temp';BytesObserved=1048576;FilesObserved=12;DirectoriesVisited=2;Truncated=$true;Errors=@();DurationMs=0},'Amostra de TEMP: 1 MB / 12 arquivos (exemplo limitado). Não representa espaço garantido recuperável.')
            'explorer'=@($true,@{SeparateProcess=[pscustomobject]@{Exists=$false;Value=$null;Type=$null};StartupDelayInMSec=[pscustomobject]@{Exists=$false;Value=$null;Type=$null}},'Preferências de Explorer ausentes no exemplo; Windows/usuário definem os padrões.')
            'drivers'=@($true,@([pscustomobject]@{DeviceName='GPU de exemplo';DriverVersion='Exemplo';DriverDate=$null;Manufacturer='Fabricante'}),'Inventário demonstrativo, sem afirmar que o driver é o mais recente.')
            'storage'=@($true,[pscustomobject]@{Disks=@([pscustomobject]@{Name='SSD de exemplo';MediaType='SSD';MediaTypeKnown=$true;BusType='NVMe';Size=512GB;Source='Demonstração'});Source='Demonstração';Fallback=$false;PrimaryError=''},'SSD/NVMe declarado no exemplo; tipo de mídia não é benchmark.')
            'battery'=@($true,[pscustomobject]@{OnBattery=$false;OnAC=$true;HasBattery=$false;ACLineStatus='Online';BatteryChargeStatus='NoSystemBattery';BatteryPercent=$null;Source='Demonstração'},'Exemplo conectado à energia, sem bateria de sistema.')
        }
        foreach ($key in $fixture.Keys) { $entry=$fixture[$key]; $readings[$key]=New-GoatAdvancedReading ([bool]$entry[0]) $entry[1] ('DEMONSTRAÇÃO: '+$entry[2]) }
        return [pscustomobject]@{Readings=$readings;Errors=@();Timestamp=[DateTime]::Parse('2026-10-26T00:00:00Z').ToUniversalTime();IsDemo=$true}
    }

    # Each probe catches its own error. A failed query has a null value rather
    # than a fabricated disabled/zero reading; other categories still complete.
    $probes=[ordered]@{
        'memory-compression'={
            $data=@(Invoke-GoatAdvancedReadCommand 'Get-MMAgent' @{} @('MemoryCompression'))
            if ($data.Count -eq 0 -or $null -eq $data[0].MemoryCompression) { throw 'MemoryCompression não foi exposta pelo provedor.' }
            $enabled=[bool]$data[0].MemoryCompression
            New-GoatAdvancedReading $true $enabled ('Compressão de memória: '+$(if($enabled){'ativada'}else{'desativada'})+'. Estado informado pelo MMAgent; não estima ganho de FPS.')
        }
        'system-cache'={
            $value=Get-GoatAdvancedRegistryValue HKLM 'SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' 'LargeSystemCache'
            $text='LargeSystemCache ausente: preferência padrão do Windows, sem impor um valor inferido.'
            if ($value.Exists) {$text='LargeSystemCache='+$value.Value+' ('+$value.Type+'). Preferência de Registro; não mede cache em uso.'}
            New-GoatAdvancedReading $true $value.Value $text
        }
        'cpu-architecture'={
            $cpus=@(Invoke-GoatAdvancedReadCommand 'Get-CimInstance' @{ClassName='Win32_Processor';OperationTimeoutSec=2} @('Architecture','NumberOfCores','NumberOfLogicalProcessors'))
            if ($cpus.Count -eq 0 -or $null -eq $cpus[0].Architecture) { throw 'Arquitetura de CPU não informada.' }
            $code=[int]$cpus[0].Architecture; $architecture='Desconhecida ('+$code+')'
            switch($code) {0{$architecture='x86'};5{$architecture='ARM'};9{$architecture='x64'};12{$architecture='ARM64'}}
            $value=[pscustomobject]@{Code=$code;Name=$architecture;Cores=($cpus|Measure-Object NumberOfCores -Sum).Sum;Threads=($cpus|Measure-Object NumberOfLogicalProcessors -Sum).Sum}
            New-GoatAdvancedReading $true $value ("$architecture; $($value.Cores) núcleos / $($value.Threads) threads. CIM não determina universalmente a divisão P/E nem os C-States.")
        }
        'core-parking'={
            $minimum=ConvertFrom-GoatParkingQuery (Invoke-GoatAdvancedNativeRead powercfg @('/qh','SCHEME_CURRENT','SUB_PROCESSOR','CPMINCORES'))
            $maximum=ConvertFrom-GoatParkingQuery (Invoke-GoatAdvancedNativeRead powercfg @('/qh','SCHEME_CURRENT','SUB_PROCESSOR','CPMAXCORES'))
            if ($minimum.Scheme -and $maximum.Scheme -and $minimum.Scheme -ne $maximum.Scheme) { throw 'O plano de energia mudou durante a leitura.' }
            $value=[pscustomobject]@{MinimumAC=$minimum.AC;MinimumDC=$minimum.DC;MaximumAC=$maximum.AC;MaximumDC=$maximum.DC;ActiveScheme=$minimum.Scheme}
            New-GoatAdvancedReading $true $value ("Núcleos disponíveis: mínimo AC/DC $($minimum.AC)%/$($minimum.DC)%; máximo AC/DC $($maximum.AC)%/$($maximum.DC)%. Política do plano ativo, não contagem runtime. Classes de eficiência podem ter parâmetros adicionais.")
        }
        'process-scheduling'={
            $state=Get-GoatAdvancedRegistryValue HKLM 'SYSTEM\CurrentControlSet\Control\PriorityControl' 'Win32PrioritySeparation'
            $text='Win32PrioritySeparation ausente: padrão do Windows; nenhum quantum é inferido.'
            if ($state.Exists) {$text=('Win32PrioritySeparation={0} (0x{1:X}). Valor bruto; não mede latência nem prioridade real de processos.' -f $state.Value,[long]$state.Value)}
            New-GoatAdvancedReading $true $state.Value $text
        }
        'msi-gpu'={
            if ($null -eq $Scan -or @($Scan.GPU).Count -eq 0) { throw 'Inventário de GPU indisponível no scanner de hardware.' }
            $gpus=@($Scan.GPU | Select-Object Name,PnpDeviceId,MsiEnabled,InterruptPriority)
            $details=@($gpus | ForEach-Object { $_.Name+': MSI '+$(if($null -eq $_.MsiEnabled){'não declarado'}elseif($_.MsiEnabled){'configurado'}else{'configurado como 0'}) })
            New-GoatAdvancedReading $true $gpus (($details -join '; ')+'. Leitura de configuração do driver; não comprova interrupção em execução nem mede DPC.')
        }
        'msi-storage'={
            $controllers=@(Invoke-GoatAdvancedReadCommand 'Get-CimInstance' @{ClassName='Win32_SCSIController';OperationTimeoutSec=2} @('Name','PNPDeviceID'))
            $controllers+=@(Invoke-GoatAdvancedReadCommand 'Get-CimInstance' @{ClassName='Win32_IDEController';OperationTimeoutSec=2} @('Name','PNPDeviceID'))
            if ($controllers.Count -eq 0) { throw 'Nenhum controlador SCSI/IDE foi exposto por CIM; estado MSI desconhecido.' }
            if (-not (Get-Command Get-GoatInterruptConfiguration -ErrorAction SilentlyContinue)) { throw 'Módulo de leitura de interrupções não foi carregado.' }
            $items=@(); $interruptErrors=New-Object 'System.Collections.Generic.List[string]'
            foreach($controller in @($controllers|Sort-Object PNPDeviceID -Unique)) {
                $configuration=Get-GoatInterruptConfiguration -PnpDeviceId $controller.PNPDeviceID -Errors $interruptErrors
                $items+=[pscustomobject]@{Name=$controller.Name;PnpDeviceId=$controller.PNPDeviceID;MsiEnabled=$configuration.MsiEnabled;InterruptPriority=$configuration.InterruptPriority}
            }
            New-GoatAdvancedReading $true $items ("$($items.Count) controlador(es) consultado(s). MSI/prioridade são configurações declaradas no Registro, não confirmação runtime; ausente significa não declarado.") ($interruptErrors.ToArray()-join '; ')
        }
        'hags'={
            $state=Get-GoatAdvancedRegistryValue HKLM 'SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'
            $text='HwSchMode ausente: preferência padrão do Windows/driver.'
            if ($state.Exists) {$text='HwSchMode='+$state.Value+' ('+$state.Type+'): preferência de Registro';if($state.Value -eq 2){$text+=' ligada'}elseif($state.Value -eq 1){$text+=' desligada'};$text+='.'}
            New-GoatAdvancedReading $true $state.Value ($text+' Isto não comprova suporte da GPU/driver ou uso de HAGS em execução.')
        }
        'timers'={
            $output=Invoke-GoatAdvancedNativeRead bcdedit @('/enum','{current}')
            $flags=@{}; $summary=@()
            foreach($flag in @('useplatformclock','useplatformtick','disabledynamictick','tscsyncpolicy','debug','bootdebug')) {
                $match=[regex]::Match($output,'(?im)^\s*'+[regex]::Escape($flag)+'\s+([^\r\n]+)$')
                $flags[$flag]=$null
                if($match.Success){$flags[$flag]=$match.Groups[1].Value.Trim()}
                $summary+=($flag+'='+$(if($null -eq $flags[$flag]){'ausente'}else{$flags[$flag]}))
            }
            New-GoatAdvancedReading $true $flags (($summary-join '; ')+'. Flags BCD são overrides de inicialização/depuração; ausência não identifica HPET ou timer runtime.')
        }
        'network-autotuning'={
            $settings=@(Invoke-GoatAdvancedReadCommand 'Get-NetTCPSetting' @{SettingName='Internet'} @('AutoTuningLevelLocal'))
            if($settings.Count -eq 0 -or -not [string]$settings[0].AutoTuningLevelLocal){throw 'Perfil TCP Internet não forneceu AutoTuningLevelLocal.'}
            $value=([string]$settings[0].AutoTuningLevelLocal).ToLowerInvariant()
            New-GoatAdvancedReading $true $value ('Auto-tuning TCP do perfil Internet: '+$value+'. Não mede ping, throughput ou perda de pacotes.')
        }
        'rss'={
            $data=@(Invoke-GoatAdvancedReadCommand 'Get-NetOffloadGlobalSetting' @{} @('ReceiveSideScaling'))
            if($data.Count -eq 0 -or -not [string]$data[0].ReceiveSideScaling){throw 'Estado global de RSS não informado.'}
            $value=[string]$data[0].ReceiveSideScaling
            New-GoatAdvancedReading $true $value ('RSS global: '+$value+'. Suporte e configuração por adaptador podem variar.')
        }
        'qos'={
            $policies=@(Invoke-GoatAdvancedReadCommand 'Get-NetQosPolicy' @{PolicyStore='ActiveStore'} @('Name','Owner','Precedence','DSCPValue','MinBandwidthWeightAction','ThrottleRateActionBitsPerSecond') -First 100)
            $limit=Get-GoatAdvancedRegistryValue HKLM 'SOFTWARE\Policies\Microsoft\Windows\Psched' 'NonBestEffortLimit'
            $value=[pscustomobject]@{Policies=$policies;NonBestEffortLimit=$limit}
            $text="$($policies.Count) política(s) QoS efetiva(s) consultada(s) (limite de 100). NonBestEffortLimit="+$(if($limit.Exists){[string]$limit.Value}else{'não configurado'})+'. Isso não indica perda fixa de 20% da conexão.'
            New-GoatAdvancedReading $true $value $text
        }
        'adapter-power'={
            $adapters=@(Invoke-GoatAdvancedReadCommand 'Get-NetAdapterPowerManagement' @{Name='*'} @('Name','InterfaceDescription','AllowComputerToTurnOffDevice','SelectiveSuspend','DeviceSleepOnDisconnect','WakeOnMagicPacket','WakeOnPattern') -First 32)
            if($adapters.Count -eq 0){throw 'Nenhum adaptador com estado de energia acessível foi retornado.'}
            New-GoatAdvancedReading $true $adapters ("$($adapters.Count) adaptador(es) com propriedades de energia lidas. Unsupported/ausente não equivale a desativado; economia de energia e offload são configurações diferentes.")
        }
        'appx'={
            $packages=@(Invoke-GoatAdvancedReadCommand 'Get-AppxPackage' @{} @('Name','PackageFullName','Version','IsFramework','NonRemovable') -First 400 -TimeoutMilliseconds 4000)
            New-GoatAdvancedReading $true $packages ("$($packages.Count) pacote(s) do usuário atual inventariado(s), limitado a 400. Nenhum pacote é removido ou classificado automaticamente como inútil.")
        }
        'cache'={
            $observation=Get-GoatAdvancedTempObservation
            $text=('{0} MB observados em {1} arquivos da TEMP atual; {2} pastas visitadas.' -f [math]::Round($observation.BytesObserved/1MB,2),$observation.FilesObserved,$observation.DirectoriesVisited)
            if($observation.Truncated){$text+=' Amostra limitada por tempo/entradas; não é o tamanho total.'}
            $text+=' Sem tocar caches do Windows, navegadores, shaders ou arquivos; não representa espaço garantido recuperável.'
            New-GoatAdvancedReading $true $observation $text ($observation.Errors-join '; ')
        }
        'explorer'={
            $values=@{
                SeparateProcess=(Get-GoatAdvancedRegistryValue HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'SeparateProcess')
                StartupDelayInMSec=(Get-GoatAdvancedRegistryValue HKCU 'Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize' 'StartupDelayInMSec')
                MenuShowDelay=(Get-GoatAdvancedRegistryValue HKCU 'Control Panel\Desktop' 'MenuShowDelay')
            }
            $summary=@($values.Keys|Sort-Object|ForEach-Object{$_+'='+$(if($values[$_].Exists){[string]$values[$_].Value}else{'padrão/ausente'})})
            New-GoatAdvancedReading $true $values (($summary-join '; ')+'. Preferências do usuário; não medem resposta do Explorer.')
        }
        'drivers'={
            if($null -eq $Scan -or -not $Scan.PSObject.Properties['Drivers']){throw 'Inventário de drivers não foi fornecido pelo scanner de hardware.'}
            if(@($Scan.Drivers).Count -eq 0 -and @($Scan.Errors|Where-Object{$_ -match 'PnPSignedDriver'}).Count -gt 0){throw 'Consulta de drivers falhou no scanner de hardware.'}
            $drivers=@($Scan.Drivers | Select-Object DeviceName,DriverVersion,DriverDate,Manufacturer)
            New-GoatAdvancedReading $true $drivers ("$($drivers.Count) registros de drivers instalados. Versão/data não comprova atualização; confirme no site do fabricante.")
        }
        'storage'={
            $value=Get-GoatAdvancedStorageContext
            $known=@($value.Disks|Where-Object MediaTypeKnown).Count
            $text="$($value.Disks.Count) disco(s) inventariado(s), $known com tipo de mídia declarado. HDD/SSD desconhecido não é inferido por modelo; o volume do Windows/jogo não foi mapeado."
            if($value.Fallback){$text+=' Provedor principal indisponível; fallback CIM preserva o tipo como desconhecido.'}
            New-GoatAdvancedReading $true $value $text $value.PrimaryError
        }
        'battery'={
            $value=Get-GoatAdvancedPowerContext
            $text='Alimentação: '+$value.ACLineStatus+'. '
            if($value.OnBattery -is [bool]){$text+=$(if($value.OnBattery){'Operando na bateria.'}else{'Sem descarga de bateria informada.'})}
            else{$text+='Descarga de bateria desconhecida; nenhuma condição AC é inferida.'}
            New-GoatAdvancedReading $true $value $text
        }
    }
    foreach($entry in $probes.GetEnumerator()) {
        try {
            $reading=& $entry.Value
            if($null -eq $reading -or -not $reading.PSObject.Properties['Available']){throw 'Consulta não produziu leitura estruturada.'}
            $readings[$entry.Key]=$reading
            if($reading.Error){$errors.Add($entry.Key+': '+$reading.Error)}
        }
        catch {
            $message=$_.Exception.Message
            $readings[$entry.Key]=New-GoatAdvancedReading $false $null ('Indisponível: '+$message) $message
            $errors.Add($entry.Key+': '+$message)
        }
    }
    # Query services once and reuse the exact same snapshot for both categories.
    try {
        $serviceNames=@('wuauserv','BITS','SysMain','WSearch','DiagTrack','MapsBroker','Spooler','DPS','WinDefend','Schedule','XblAuthManager','XblGameSave','XboxNetApiSvc')
        $filter=($serviceNames|ForEach-Object{"Name='$_'"})-join ' OR '
        $services=@(Invoke-GoatAdvancedReadCommand 'Get-CimInstance' @{ClassName='Win32_Service';Filter=$filter;OperationTimeoutSec=2} @('Name','DisplayName','StartMode','State') -First 32)
        if($services.Count -eq 0){throw 'Nenhum estado de serviço foi retornado pelo provedor.'}
        $readings['services']=New-GoatAdvancedReading $true $services ("$($services.Count) serviços específicos disponíveis para revisão. StartMode/State são observações; nenhum é declarado supérfluo automaticamente.")
        $updateServices=@($services|Where-Object{$_.Name -in @('wuauserv','BITS')})
        if($updateServices.Count -lt 2){throw 'Windows Update ou BITS não foi exposto pelo provedor de serviços.'}
        $policies=@(
            (Get-GoatAdvancedRegistryValue HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'NoAutoUpdate'),
            (Get-GoatAdvancedRegistryValue HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'AUOptions'),
            (Get-GoatAdvancedRegistryValue HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' 'UseWUServer'),
            (Get-GoatAdvancedRegistryValue HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'WUServer'),
            (Get-GoatAdvancedRegistryValue HKLM 'SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' 'DisableWindowsUpdateAccess')
        )
        $value=[pscustomobject]@{Services=$updateServices;Policies=$policies}
        $description=@($updateServices|ForEach-Object{$_.Name+': '+$_.StartMode+'/'+$_.State})-join '; '
        $readings['windows-update']=New-GoatAdvancedReading $true $value ($description+'. Serviço parado/manual isoladamente não comprova bloqueio; políticas ausentes seguem padrões/GPO/MDM não enumerados integralmente.')
    }
    catch {
        $message=$_.Exception.Message
        foreach($key in @('services','windows-update')) {
            if(-not $readings.ContainsKey($key)){$readings[$key]=New-GoatAdvancedReading $false $null ('Indisponível: '+$message) $message}
        }
        $errors.Add('services/windows-update: '+$message)
    }
    $readings['rebar']=New-GoatAdvancedReading $false $null 'Resizable BAR: sem API CIM universal confiável para confirmar o estado; confira firmware e painel oficial da GPU.'
    $readings['cstates']=New-GoatAdvancedReading $false $null 'C-States: estado de firmware/hardware não inferido de nome de CPU, core parking ou plano de energia; exige ferramenta compatível.'
    return [pscustomobject]@{Readings=$readings;Errors=@($errors.ToArray());Timestamp=Get-Date;IsDemo=$false}
}
