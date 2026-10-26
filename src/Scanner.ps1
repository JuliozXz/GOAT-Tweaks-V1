function Invoke-GoatCimRead {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ClassName,
        [string]$Namespace = 'root/cimv2',
        [string]$Filter,
        [System.Collections.Generic.List[string]]$Errors,
        [int]$TimeoutSeconds = 5
    )
    try {
        $arguments = @{ ClassName = $ClassName; Namespace = $Namespace; OperationTimeoutSec = $TimeoutSeconds; ErrorAction = 'Stop' }
        if ($Filter) { $arguments.Filter = $Filter }
        Get-CimInstance @arguments
    }
    catch {
        if ($null -ne $Errors) { $Errors.Add(('{0}: {1}' -f $ClassName, $_.Exception.Message)) }
    }
}

function Get-GoatInterruptConfiguration {
    [CmdletBinding()]
    param([string]$PnpDeviceId, [System.Collections.Generic.List[string]]$Errors)

    $enabled = $null
    $priority = $null
    if ($PnpDeviceId) {
        $interruptPath = 'HKLM:\SYSTEM\CurrentControlSet\Enum\{0}\Device Parameters\Interrupt Management' -f $PnpDeviceId
        try {
            $msiPath = Join-Path $interruptPath 'MessageSignaledInterruptProperties'
            if (Test-Path -LiteralPath $msiPath -ErrorAction Stop) {
                $configuration = Get-ItemProperty -LiteralPath $msiPath -ErrorAction Stop
                if ($configuration.PSObject.Properties['MSISupported']) {
                    $enabled = ([int]$configuration.MSISupported -eq 1)
                }
            }
            $affinityPath = Join-Path $interruptPath 'Affinity Policy'
            if (Test-Path -LiteralPath $affinityPath -ErrorAction Stop) {
                $affinity = Get-ItemProperty -LiteralPath $affinityPath -ErrorAction Stop
                if ($affinity.PSObject.Properties['DevicePriority']) {
                    switch ([int]$affinity.DevicePriority) {
                        0 { $priority = 'Indefinida' }
                        1 { $priority = 'Baixa' }
                        2 { $priority = 'Normal' }
                        3 { $priority = 'Alta' }
                        default { $priority = 'Valor desconhecido ({0})' -f $affinity.DevicePriority }
                    }
                }
            }
        }
        catch {
            if ($null -ne $Errors) { $Errors.Add(('Interrupções de {0}: {1}' -f $PnpDeviceId, $_.Exception.Message)) }
        }
    }
    [pscustomobject]@{ MsiEnabled = $enabled; InterruptPriority = $priority }
}

function Get-GoatHardwareScan {
    [CmdletBinding()]
    param([switch]$Demo)

    if ($Demo) {
        return [pscustomobject]@{
            Timestamp = Get-Date
            IsDemo = $true
            ComputerName = 'GOAT-DEMONSTRACAO'
            OS = [pscustomobject]@{ Caption = 'Windows 11 Pro (demonstração)'; Version = '10.0.26100'; Build = 26100; Supported = $true }
            CPU = [pscustomobject]@{ Name = 'AMD Ryzen 7 7800X3D · dados de demonstração'; Cores = 8; Threads = 16; LoadPercent = 18 }
            GPU = @([pscustomobject]@{ Name = 'NVIDIA GeForce RTX 4070 SUPER'; DriverVersion = 'Exemplo'; PnpDeviceId = 'DEMO\GPU'; MsiEnabled = $true; InterruptPriority = 'Indefinida' })
            Memory = [pscustomobject]@{ TotalGB = 32; AvailableGB = 22.4; SpeedMHz = 6000 }
            Motherboard = [pscustomobject]@{ Manufacturer = 'ASUSTeK'; Product = 'TUF GAMING B650-PLUS (exemplo)'; BiosVersion = 'Demonstração'; BiosDate = $null }
            Network = @([pscustomobject]@{ Name = 'Ethernet'; Description = 'Adaptador 2.5 GbE (exemplo)'; Status = 'Up'; LinkSpeed = '2.5 Gbps' })
            Power = [pscustomobject]@{ ActiveScheme = '381b4222-f694-41f0-9685-ff5bb260df2e'; ActiveSchemeName = 'Equilibrado'; IsLaptop = $false }
            Drivers = @([pscustomobject]@{ DeviceName = 'NVIDIA GeForce RTX 4070 SUPER'; DriverVersion = 'Exemplo'; DriverDate = $null; Manufacturer = 'NVIDIA' })
            Findings = @(
                [pscustomobject]@{ Category = 'CPU'; Severity = 'Info'; Title = '8 núcleos / 16 threads'; Detail = 'Exemplo de diagnóstico. Afinidade e C-States dependem da carga e do firmware; não são alterados automaticamente.' },
                [pscustomobject]@{ Category = 'GPU'; Severity = 'Info'; Title = 'MSI declarado no Registro'; Detail = 'Dado demonstrativo. A declaração do driver não comprova a interrupção usada em execução nem mede latência DPC.' },
                [pscustomobject]@{ Category = 'BIOS'; Severity = 'Info'; Title = 'Verificação presencial de BIOS'; Detail = 'Resizable BAR, EXPO/XMP e C-States precisam ser conferidos no firmware e no painel do fabricante.' },
                [pscustomobject]@{ Category = 'Sistema'; Severity = 'Info'; Title = 'Modo de demonstração'; Detail = 'Todos os dados exibidos são exemplos. Nenhuma configuração do Windows será alterada.' }
            )
            Errors = @()
        }
    }

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $findings = New-Object 'System.Collections.Generic.List[object]'
    $processors = @(Invoke-GoatCimRead -ClassName 'Win32_Processor' -Errors $errors)
    $systems = @(Invoke-GoatCimRead -ClassName 'Win32_ComputerSystem' -Errors $errors)
    $operatingSystems = @(Invoke-GoatCimRead -ClassName 'Win32_OperatingSystem' -Errors $errors)
    $videoControllers = @(Invoke-GoatCimRead -ClassName 'Win32_VideoController' -Errors $errors)
    $boards = @(Invoke-GoatCimRead -ClassName 'Win32_BaseBoard' -Errors $errors)
    $biosItems = @(Invoke-GoatCimRead -ClassName 'Win32_BIOS' -Errors $errors)
    $ramModules = @(Invoke-GoatCimRead -ClassName 'Win32_PhysicalMemory' -Errors $errors)
    $networkAdapters = @(Invoke-GoatCimRead -ClassName 'Win32_NetworkAdapter' -Filter 'PhysicalAdapter=True' -Errors $errors)
    $signedDrivers = @(Invoke-GoatCimRead -ClassName 'Win32_PnPSignedDriver' -Errors $errors -TimeoutSeconds 8)

    $system = $systems | Select-Object -First 1
    $os = $operatingSystems | Select-Object -First 1
    $board = $boards | Select-Object -First 1
    $bios = $biosItems | Select-Object -First 1
    $cpuName = $null
    $cores = $null
    $threads = $null
    $cpuLoad = $null
    if ($processors.Count -gt 0) {
        $cpuName = (($processors | ForEach-Object { ([string]$_.Name).Trim() } | Select-Object -Unique) -join ' + ')
        $cores = ($processors | Measure-Object -Property NumberOfCores -Sum).Sum
        $threads = ($processors | Measure-Object -Property NumberOfLogicalProcessors -Sum).Sum
        $loadValues = @($processors | Where-Object { $null -ne $_.LoadPercentage })
        if ($loadValues.Count -gt 0) { $cpuLoad = [math]::Round(($loadValues | Measure-Object -Property LoadPercentage -Average).Average, 1) }
        $findings.Add([pscustomobject]@{ Category = 'CPU'; Severity = 'Info'; Title = ('{0} núcleos / {1} threads' -f $cores, $threads); Detail = 'Topologia informada pelo Windows. A divisão entre núcleos de desempenho e eficiência e os C-States não é inferida por nome comercial.' })
        if ($null -ne $cpuLoad -and $cpuLoad -ge 85) {
            $findings.Add([pscustomobject]@{ Category = 'CPU'; Severity = 'Warning'; Title = 'Uso de CPU elevado nesta amostra'; Detail = ('Uso observado: {0}%. Identifique os processos ativos e compare sob a mesma carga antes de concluir que há um gargalo.' -f $cpuLoad) })
        }
    }

    $gpus = @()
    foreach ($controller in $videoControllers) {
        $interrupt = Get-GoatInterruptConfiguration -PnpDeviceId $controller.PNPDeviceID -Errors $errors
        $gpus += [pscustomobject]@{
            Name = $controller.Name
            DriverVersion = $controller.DriverVersion
            PnpDeviceId = $controller.PNPDeviceID
            MsiEnabled = $interrupt.MsiEnabled
            InterruptPriority = $interrupt.InterruptPriority
        }
        $msiSummary = 'A configuração MSI não foi declarada ou não pôde ser lida.'
        if ($null -ne $interrupt.MsiEnabled) {
            if ($interrupt.MsiEnabled) { $msiSummary = 'O driver tem MSISupported=1 no Registro.' }
            else { $msiSummary = 'O driver tem MSISupported=0 no Registro.' }
        }
        $findings.Add([pscustomobject]@{ Category = 'GPU'; Severity = 'Info'; Title = $controller.Name; Detail = ('{0} Isso não comprova o tipo de interrupção em execução nem mede latência DPC. Alterações exigem compatibilidade confirmada pelo fabricante.' -f $msiSummary) })
        if ($controller.Name -match 'Microsoft Basic|Adaptador de [Vv].*?[Bb].*?[Mm]icrosoft') {
            $findings.Add([pscustomobject]@{ Category = 'Drivers'; Severity = 'Warning'; Title = 'Driver de vídeo básico detectado'; Detail = 'Confirme o modelo da GPU e instale o pacote oficial do fabricante antes de avaliar o desempenho gráfico.' })
        }
    }

    $totalGB = $null
    $availableGB = $null
    $speedMHz = $null
    if ($null -ne $system -and $system.TotalPhysicalMemory -gt 0) { $totalGB = [math]::Round(([double]$system.TotalPhysicalMemory / 1GB), 1) }
    elseif ($null -ne $os -and $os.TotalVisibleMemorySize -gt 0) { $totalGB = [math]::Round(([double]$os.TotalVisibleMemorySize / 1MB), 1) }
    if ($null -ne $os -and $null -ne $os.FreePhysicalMemory) { $availableGB = [math]::Round(([double]$os.FreePhysicalMemory / 1MB), 1) }
    $clockSpeeds = @($ramModules | ForEach-Object { if ($_.ConfiguredClockSpeed -gt 0) { [int]$_.ConfiguredClockSpeed } elseif ($_.Speed -gt 0) { [int]$_.Speed } })
    if ($clockSpeeds.Count -gt 0) { $speedMHz = ($clockSpeeds | Measure-Object -Maximum).Maximum }
    if ($null -ne $totalGB -and $totalGB -gt 0 -and $null -ne $availableGB -and ($availableGB / $totalGB) -lt 0.15) {
        $findings.Add([pscustomobject]@{ Category = 'RAM'; Severity = 'Warning'; Title = 'Pouca memória RAM disponível'; Detail = ('{0} GB disponíveis de {1} GB nesta amostra. Examine a carga e o uso de paginação antes de recomendar hardware.' -f $availableGB, $totalGB) })
    }

    $build = $null
    $supported = $false
    if ($null -ne $os) {
        $parsedBuild = 0
        if ([int]::TryParse([string]$os.BuildNumber, [ref]$parsedBuild)) { $build = $parsedBuild }
        $supported = ($null -ne $build -and $build -ge 19041 -and $os.ProductType -eq 1 -and [Environment]::Is64BitOperatingSystem)
        if (-not $supported) {
            $findings.Add([pscustomobject]@{ Category = 'Sistema'; Severity = 'Warning'; Title = 'Sistema fora da matriz de compatibilidade'; Detail = 'Este aplicativo foi destinado a Windows 10/11 cliente de 64 bits, build 19041 ou superior. Ações devem permanecer indisponíveis em outros sistemas.' })
        }
        else {
            $findings.Add([pscustomobject]@{ Category = 'Sistema'; Severity = 'Info'; Title = ('Build {0} detectada' -f $build); Detail = 'Compatibilidade técnica do aplicativo verificada. Isso não valida o suporte de segurança da edição do Windows nem a presença das últimas atualizações.' })
        }
    }

    $network = @()
    foreach ($adapter in $networkAdapters) {
        $state = 'Desconhecido'
        switch ($adapter.NetConnectionStatus) {
            0 { $state = 'Desconectado' }
            2 { $state = 'Up' }
            4 { $state = 'Hardware ausente' }
            5 { $state = 'Hardware desativado' }
            7 { $state = 'Mídia desconectada' }
        }
        $linkSpeed = $null
        if ($adapter.Speed -gt 0) {
            if ([double]$adapter.Speed -ge 1e9) { $linkSpeed = '{0:0.##} Gbps' -f ([double]$adapter.Speed / 1e9) }
            else { $linkSpeed = '{0:0.##} Mbps' -f ([double]$adapter.Speed / 1e6) }
        }
        $network += [pscustomobject]@{ Name = $adapter.NetConnectionID; Description = $adapter.Name; Status = $state; LinkSpeed = $linkSpeed }
    }
    $connectedAdapters = @($network | Where-Object { $_.Status -eq 'Up' })
    if ($connectedAdapters.Count -eq 0) {
        $findings.Add([pscustomobject]@{ Category = 'Rede'; Severity = 'Warning'; Title = 'Nenhum adaptador físico conectado foi identificado'; Detail = 'Confira a conexão, VPN ou adaptador virtual. O scanner não mede ping ou perda de pacotes automaticamente.' })
    }
    else {
        $findings.Add([pscustomobject]@{ Category = 'Rede'; Severity = 'Info'; Title = ('{0} conexão(ões) física(s) ativa(s)' -f $connectedAdapters.Count); Detail = 'Velocidade do enlace não representa velocidade da Internet ou latência do jogo. TCP, offloads e energia do adaptador dependem do driver e da carga.' })
    }

    $activeScheme = $null
    $activeSchemeName = $null
    try {
        $powercfgPath = Join-Path $env:SystemRoot 'System32\powercfg.exe'
        $powerOutput = (& $powercfgPath /getactivescheme 2>&1 | Out-String)
        if ($LASTEXITCODE -ne 0) { throw $powerOutput.Trim() }
        if ($powerOutput -match '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}') { $activeScheme = $Matches[0].ToLowerInvariant() }
        if ($powerOutput -match '\(([^)]+)\)') { $activeSchemeName = $Matches[1] }
    }
    catch { $errors.Add(('Plano de energia: {0}' -f $_.Exception.Message)) }
    $isLaptop = $null
    if ($null -ne $system) { $isLaptop = ([int]$system.PCSystemType -in @(2, 8)) }

    $driverResults = @($signedDrivers | ForEach-Object {
        [pscustomobject]@{ DeviceName = $_.DeviceName; DriverVersion = $_.DriverVersion; DriverDate = $_.DriverDate; Manufacturer = $_.Manufacturer }
    } | Sort-Object DeviceName)
    $findings.Add([pscustomobject]@{ Category = 'Drivers'; Severity = 'Info'; Title = ('{0} registros de drivers coletados' -f $driverResults.Count); Detail = 'Versões instaladas não indicam se há atualização. Confirme o dispositivo, a versão e o pacote no site oficial do fabricante.' })
    $findings.Add([pscustomobject]@{ Category = 'BIOS'; Severity = 'Info'; Title = 'Ajustes de firmware exigem revisão manual'; Detail = 'C-States, EXPO/XMP, Resizable BAR, PCIe e HPET não têm detecção universal confiável por CIM. Nenhum valor de BIOS é alterado pelo aplicativo.' })

    [pscustomobject]@{
        Timestamp = Get-Date
        IsDemo = $false
        ComputerName = $env:COMPUTERNAME
        OS = [pscustomobject]@{ Caption = $(if ($os) { $os.Caption } else { $null }); Version = $(if ($os) { $os.Version } else { $null }); Build = $build; Supported = $supported }
        CPU = [pscustomobject]@{ Name = $cpuName; Cores = $cores; Threads = $threads; LoadPercent = $cpuLoad }
        GPU = @($gpus)
        Memory = [pscustomobject]@{ TotalGB = $totalGB; AvailableGB = $availableGB; SpeedMHz = $speedMHz }
        Motherboard = [pscustomobject]@{ Manufacturer = $(if ($board) { $board.Manufacturer } else { $null }); Product = $(if ($board) { $board.Product } else { $null }); BiosVersion = $(if ($bios) { $bios.SMBIOSBIOSVersion } else { $null }); BiosDate = $(if ($bios) { $bios.ReleaseDate } else { $null }) }
        Network = @($network)
        Power = [pscustomobject]@{ ActiveScheme = $activeScheme; ActiveSchemeName = $activeSchemeName; IsLaptop = $isLaptop }
        Drivers = @($driverResults)
        Findings = @($findings.ToArray())
        Errors = @($errors.ToArray())
    }
}

function Get-GoatTelemetrySample {
    [CmdletBinding()]
    param([switch]$Demo)

    if ($Demo) {
        $seconds = [DateTime]::Now.TimeOfDay.TotalSeconds
        return [pscustomobject]@{ Timestamp = Get-Date; CPU = [math]::Round(24 + 9 * [math]::Sin($seconds / 4), 1); GPU = [math]::Round(33 + 12 * [math]::Sin($seconds / 6), 1); RAM = [math]::Round(32 + 2 * [math]::Sin($seconds / 15), 1); IsDemo = $true }
    }

    $cpuUsage = $null
    $gpuUsage = $null
    $ramUsage = $null
    $cpuCounters = @(Invoke-GoatCimRead -ClassName 'Win32_PerfFormattedData_PerfOS_Processor' -Filter "Name='_Total'" -TimeoutSeconds 2)
    if ($cpuCounters.Count -gt 0 -and $null -ne $cpuCounters[0].PercentProcessorTime) { $cpuUsage = [math]::Min(100, [math]::Max(0, [double]$cpuCounters[0].PercentProcessorTime)) }
    if ($null -eq $cpuUsage) {
        # Performance counters can be unavailable or disabled. WMI's current
        # processor load remains a valid, lower resolution read-only fallback.
        $processorSamples = @(Invoke-GoatCimRead -ClassName 'Win32_Processor' -TimeoutSeconds 2 | Where-Object { $null -ne $_.LoadPercentage })
        if ($processorSamples.Count -gt 0) { $cpuUsage = [math]::Round(($processorSamples | Measure-Object -Property LoadPercentage -Average).Average, 1) }
    }
    $memoryCounters = @(Invoke-GoatCimRead -ClassName 'Win32_OperatingSystem' -TimeoutSeconds 2)
    if ($memoryCounters.Count -gt 0 -and $memoryCounters[0].TotalVisibleMemorySize -gt 0) {
        $ramUsage = [math]::Round(100 * (1 - [double]$memoryCounters[0].FreePhysicalMemory / [double]$memoryCounters[0].TotalVisibleMemorySize), 1)
    }
    # Windows exposes process-level engine counters. Sum processes per physical
    # 3D engine and report the busiest 3D engine, not the sum of unrelated engines.
    $gpuCounters = @(Invoke-GoatCimRead -ClassName 'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' -Filter "Name LIKE '%engtype_3D%'" -TimeoutSeconds 2)
    if ($gpuCounters.Count -gt 0) {
        $engines = @{}
        foreach ($counter in $gpuCounters) {
            if ($counter.Name -match '(luid_.+?_phys_\d+_eng_\d+)_engtype_3D') {
                $engineKey = $Matches[1]
                if (-not $engines.ContainsKey($engineKey)) { $engines[$engineKey] = 0.0 }
                $engines[$engineKey] += [double]$counter.UtilizationPercentage
            }
        }
        if ($engines.Count -gt 0) { $gpuUsage = [math]::Min(100, [math]::Max(0, ($engines.Values | Measure-Object -Maximum).Maximum)) }
    }
    [pscustomobject]@{ Timestamp = Get-Date; CPU = $cpuUsage; GPU = $gpuUsage; RAM = $ramUsage; IsDemo = $false }
}

function Get-GoatDetectedGame {
    [CmdletBinding()]
    param([switch]$Demo)

    if ($Demo) { return 'Counter-Strike 2 (demonstração)' }
    # Exact executable names only. This is a convenience allowlist, not a claim
    # to detect every game, launcher or anti-cheat process.
    $knownNames = @('cs2', 'csgo', 'VALORANT-Win64-Shipping', 'FortniteClient-Win64-Shipping', 'r5apex', 'RocketLeague', 'League of Legends', 'Overwatch', 'RainbowSix', 'RainbowSix_Vulkan', 'dota2', 'pubg', 'TslGame', 'GTA5', 'GTA5_Enhanced', 'bf2042', 'cod', 'Minecraft.Windows', 'eldenring', 'Cyberpunk2077', 'DeadByDaylight-Win64-Shipping')
    try {
        $games = @(Get-Process -ErrorAction Stop | Where-Object { $_.ProcessName -in $knownNames } | Sort-Object ProcessName)
        if ($games.Count -gt 0) { return (($games | Select-Object -ExpandProperty ProcessName -Unique) -join ', ') }
    }
    catch { return 'Detecção de jogos indisponível' }
    return 'Nenhum jogo detectado'
}
