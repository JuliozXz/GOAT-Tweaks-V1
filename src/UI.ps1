# GOAT Tweaks v2.2 - Windows PowerShell 5.1 / WPF presentation layer.
# The UI thread only renders completed worker results. System operations run in isolated runspaces.

function New-GoatUiText {
    param([string]$Text, [string]$Color = '#94A3B8', [double]$Size = 11)
    $block = New-Object System.Windows.Controls.TextBlock
    $block.Text = $Text
    $block.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($Color)
    $block.FontSize = $Size
    $block.TextWrapping = 'Wrap'
    return $block
}

function Set-GoatUiStatus {
    param([string]$Text, [bool]$ErrorState = $false)
    $script:GoatUi.Controls.StatusText.Text = $Text
    $color = if ($ErrorState) { '#F29DB8' } else { '#94A3B8' }
    $script:GoatUi.Controls.StatusText.Foreground = [System.Windows.Media.BrushConverter]::new().ConvertFromString($color)
}

function Update-GoatUiSelection {
    $ui = $script:GoatUi
    $selected = @($ui.Checkboxes | Where-Object { $_.IsChecked -eq $true -and $_.IsEnabled })
    $ui.Controls.SelectionCount.Text = '{0} selecionados' -f $selected.Count
    $canApply = ($null -ne $ui.Scan -and -not $ui.Worker -and $selected.Count -gt 0 -and ($ui.Admin -or $ui.Demo))
    $ui.Controls.ApplyButton.IsEnabled = $canApply
    $ui.Controls.RestoreButton.IsEnabled = ($null -ne $ui.Scan -and -not $ui.Worker -and ($ui.Admin -or $ui.Demo))
    $ui.Controls.RescanButton.IsEnabled = (-not $ui.Worker)
}

function Update-GoatUiTweaks {
    $ui = $script:GoatUi
    $ui.Controls.TweaksPanel.Children.Clear()
    $ui.Checkboxes = @()
    $shown = @($ui.Tweaks | Where-Object {
        $ui.Filter -eq 'Todos' -or $_.Category -eq $ui.Filter -or ($ui.Filter -eq 'Jogo' -and ($_.Category -eq 'CPU' -or $_.Category -eq 'GPU' -or $_.Recommended))
    })
    foreach ($tweak in $shown) {
        $check = New-Object System.Windows.Controls.CheckBox
        $check.Tag = $tweak.Id
        $check.IsEnabled = ($tweak.Available -and $tweak.State -ne 'Aplicado' -and -not $ui.Worker)
        $check.IsChecked = ($tweak.Recommended -and $check.IsEnabled)
        if ($ui.Selections.ContainsKey([string]$tweak.Id)) { $check.IsChecked = ($ui.Selections[[string]$tweak.Id] -and $check.IsEnabled) }
        $stack = New-Object System.Windows.Controls.StackPanel
        $title = New-GoatUiText -Text $tweak.Title -Color '#DDE5F3' -Size 11
        $title.FontWeight = 'SemiBold'
        [void]$stack.Children.Add($title)
        $detail = [string]$tweak.Description
        if (-not $tweak.Available -and $tweak.UnavailableReason) { $detail = [string]$tweak.UnavailableReason }
        $description = New-GoatUiText -Text $detail -Color '#74849D' -Size 10
        $description.Margin = '0,4,0,0'
        [void]$stack.Children.Add($description)
        $meta = @($tweak.Risk)
        if ($tweak.RequiresRestart) { $meta += 'reinício necessário' }
        if ($tweak.State -eq 'Aplicado') { $meta += 'já aplicado' }
        $label = New-GoatUiText -Text ($meta -join ' · ') -Color $(if ($tweak.Risk -eq 'Moderado') { '#CBA15D' } else { '#668B80' }) -Size 9
        $label.Margin = '0,4,0,0'
        [void]$stack.Children.Add($label)
        $check.Content = $stack
        $check.Add_Click({
            param($sender, $eventArgs)
            $script:GoatUi.Selections[[string]$sender.Tag] = [bool]$sender.IsChecked
            Update-GoatUiSelection
        })
        [void]$ui.Controls.TweaksPanel.Children.Add($check)
        $ui.Checkboxes += $check
    }
    if ($shown.Count -eq 0) {
        $empty = New-GoatUiText -Text 'Nenhuma alteração automática nesta categoria. Consulte o diagnóstico e as recomendações abaixo.' -Size 12
        $empty.Margin = '0,18,10,0'
        [void]$ui.Controls.TweaksPanel.Children.Add($empty)
    }
    Update-GoatUiSelection
}

function Add-GoatUiFinding {
    param($Finding)
    $border = New-Object System.Windows.Controls.Border
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#0F1420')
    $border.CornerRadius = New-Object System.Windows.CornerRadius 7
    $border.Padding = '12'
    $border.Margin = '0,0,0,9'
    $stack = New-Object System.Windows.Controls.StackPanel
    $severity = [string]$Finding.Severity
    $color = if ($severity -match 'Warning|Aviso|Aten|Moderad') { '#E1B776' } elseif ($severity -match 'Error|Erro|Cr.tic') { '#F29DB8' } else { '#BBA0E3' }
    $title = New-GoatUiText -Text ('{0}  /  {1}' -f $Finding.Category, $Finding.Title) -Color $color -Size 12
    $title.FontWeight = 'SemiBold'
    [void]$stack.Children.Add($title)
    $detail = New-GoatUiText -Text ([string]$Finding.Detail) -Size 11
    $detail.Margin = '0,6,0,0'
    [void]$stack.Children.Add($detail)
    $border.Child = $stack
    [void]$script:GoatUi.Controls.FindingsPanel.Children.Add($border)
}

function Update-GoatUiFindings {
    $ui = $script:GoatUi
    $ui.Controls.FindingsPanel.Children.Clear()
    if (-not $ui.Scan) { return }
    if ($ui.Filter -eq 'CPU') {
        Add-GoatUiFinding -Finding ([pscustomobject]@{ Category = 'CPU'; Severity = 'Info'; Title = [string]$ui.Scan.CPU.Name; Detail = ('{0} núcleos · {1} threads · plano de energia: {2}' -f $ui.Scan.CPU.Cores, $ui.Scan.CPU.Threads, $ui.Scan.Power.ActiveSchemeName) })
    }
    if ($ui.Filter -eq 'GPU') {
        foreach ($gpu in @($ui.Scan.GPU)) {
            Add-GoatUiFinding -Finding ([pscustomobject]@{ Category = 'GPU'; Severity = 'Info'; Title = [string]$gpu.Name; Detail = ('Driver: {0} · prioridade de interrupção informada: {1}' -f $gpu.DriverVersion, $gpu.InterruptPriority) })
        }
    }
    if ($ui.Filter -eq 'BIOS') {
        $board = $ui.Scan.Motherboard
        Add-GoatUiFinding -Finding ([pscustomobject]@{ Category = 'BIOS'; Severity = 'Info'; Title = ('{0} {1}' -f $board.Manufacturer, $board.Product); Detail = ('BIOS: {0} · data informada: {1}' -f $board.BiosVersion, $board.BiosDate) })
    }
    if ($ui.Filter -eq 'Rede') {
        foreach ($adapter in @($ui.Scan.Network)) {
            Add-GoatUiFinding -Finding ([pscustomobject]@{ Category = 'Rede'; Severity = 'Info'; Title = ('{0} · {1}' -f $adapter.Name, $adapter.Description); Detail = ('Estado informado: {0} · velocidade do enlace: {1}' -f $adapter.Status, $adapter.LinkSpeed) })
        }
    }
    $findings = @($ui.Scan.Findings | Where-Object {
        $ui.Filter -eq 'Todos' -or $ui.Filter -eq 'Jogo' -or $_.Category -eq $ui.Filter -or ($ui.Filter -eq 'Sistema' -and $_.Category -eq 'SO') -or ($ui.Filter -eq 'BIOS' -and $_.Category -match 'BIOS|Placa')
    })
    foreach ($finding in $findings) { Add-GoatUiFinding -Finding $finding }
    if ($findings.Count -eq 0) {
        [void]$ui.Controls.FindingsPanel.Children.Add((New-GoatUiText -Text 'Nenhum alerta adicional foi retornado para esta categoria. Ausência de alerta não substitui testes de estabilidade e medições no jogo.'))
    }
    if ($ui.Filter -eq 'Todos') {
        foreach ($scanError in @($ui.Scan.Errors)) {
            Add-GoatUiFinding -Finding ([pscustomobject]@{ Category = 'Scanner'; Severity = 'Aviso'; Title = 'Consulta indisponível'; Detail = [string]$scanError })
        }
    }
}

function Set-GoatUiNavigation {
    param([string]$Page)
    $ui = $script:GoatUi
    $ui.Page = $Page
    $map = @{
        Home = @('Todos', 'Seu próximo nível começa aqui.', 'Diagnóstico do hardware, ajustes revisáveis e uma bancada mais ágil.', 'Modo Jogo GOAT')
        Game = @('Jogo', 'Modo Jogo GOAT', 'Revise os ajustes disponíveis antes de iniciar a sessão de jogo.', 'Perfil para jogos')
        CPU = @('CPU', 'Processador', 'Topologia, utilização e energia com os limites de cada plataforma.', 'Ajustes de CPU')
        GPU = @('GPU', 'Placa de vídeo', 'Drivers, modo de interrupção e opções do agendador gráfico.', 'Ajustes de GPU')
        BIOS = @('BIOS', 'Placa-mãe & BIOS', 'Identificação da plataforma e itens que exigem verificação no firmware.', 'Plataforma & timers')
        Network = @('Rede', 'Rede & conectividade', 'Adaptadores detectados e configuração da pilha de rede.', 'Ajustes de rede')
        System = @('Sistema', 'Debloat & sistema', 'Configurações reversíveis e comportamento do Windows.', 'Ajustes do sistema')
        Drivers = @('Drivers', 'Drivers & ferramentas', 'Inventário local e acesso às páginas oficiais da bancada.', 'Ferramentas')
    }
    $settings = $map[$Page]
    $ui.Filter = $settings[0]
    $ui.Controls.HeaderTitle.Text = $settings[1]
    if ($ui.Scan) { $ui.Controls.HeaderSubtitle.Text = $settings[2] }
    $ui.Controls.OptimizerTitle.Text = $settings[3]
    $isDrivers = ($Page -eq 'Drivers')
    $ui.Controls.DriversSection.Visibility = $(if ($isDrivers) { 'Visible' } else { 'Collapsed' })
    $ui.Controls.DashboardGrid.Visibility = $(if ($isDrivers) { 'Collapsed' } else { 'Visible' })
    $ui.Controls.ActionsSection.Visibility = $(if ($isDrivers) { 'Collapsed' } else { 'Visible' })
    $ui.Controls.UpdatesSection.Visibility = $(if ($Page -eq 'Home') { 'Visible' } else { 'Collapsed' })
    $ui.Controls.CategorySection.Visibility = $(if ($isDrivers -or -not $ui.Scan) { 'Collapsed' } else { 'Visible' })
    $ui.Controls.CategoryTitle.Text = $(if ($Page -eq 'Home') { 'Diagnóstico da máquina' } else { 'O que o scanner encontrou' })
    $descriptions = @{
        Home = 'Constatações baseadas nas consultas disponíveis. Gargalos e latência exigem medições sob carga.'
        Game = 'A seleção usa o estado encontrado no Windows. Compare desempenho e estabilidade antes e depois.'
        CPU = 'C-States, afinidade e políticas de núcleos dependem do firmware e da carga. Não são alterados automaticamente.'
        GPU = 'MSI é informado a partir do Registro. Suporte a ReBAR e benefícios do HAGS exigem verificação do driver, firmware e jogo.'
        BIOS = 'Nenhuma configuração de BIOS, HPET, BCD ou resolução de timer é modificada automaticamente.'
        Network = 'Buffers e offloads precisam de medição no adaptador e na rede utilizados. Não há ganho universal de latência.'
        System = 'As alterações disponíveis preservam os valores capturados para uma restauração posterior.'
    }
    if ($descriptions.ContainsKey($Page)) { $ui.Controls.CategoryDescription.Text = $descriptions[$Page] }
    if ($Page -eq 'CPU') { $ui.Controls.CpuTab.IsChecked = $true }
    if ($Page -eq 'GPU') { $ui.Controls.GpuTab.IsChecked = $true }
    if (-not $isDrivers) { Update-GoatUiTweaks; Update-GoatUiFindings }
    $ui.Controls.MainScroll.ScrollToTop()
}

function Update-GoatUiChart {
    $ui = $script:GoatUi
    $canvas = $ui.Controls.ChartCanvas
    $width = $canvas.ActualWidth
    $height = $canvas.ActualHeight
    if ($width -lt 10 -or $height -lt 10) { return }
    $now = Get-Date
    $metric = $ui.Metric
    $samples = @($ui.Samples | Where-Object { ($now - $_.Timestamp).TotalSeconds -le 60 })
    $ui.Samples = $samples
    $points = New-Object System.Windows.Media.PointCollection
    $valid = @($samples | Where-Object { $null -ne $_.$metric })
    $latest = if ($samples.Count -gt 0) { $samples[-1].$metric } else { $null }
    $ui.Controls.MainMetric.Text = $(if ($null -eq $latest) { '—' } else { '{0:N0}' -f [double]$latest })
    $ui.Controls.ChartEmpty.Visibility = $(if ($valid.Count -gt 0) { 'Collapsed' } else { 'Visible' })
    if ($valid.Count -eq 0) {
        $ui.Controls.ChartEmpty.Text = $(if ($metric -eq 'GPU') { 'Contador da GPU indisponível neste sistema.' } else { 'Aguardando amostras do Windows…' })
    }
    foreach ($sample in $valid) {
        $x = [Math]::Max(0, $width * (1 - (($now - $sample.Timestamp).TotalSeconds / 60)))
        $y = $height - 4 - ([Math]::Max(0, [Math]::Min(100, [double]$sample.$metric)) / 100 * ($height - 8))
        $points.Add((New-Object System.Windows.Point $x, $y))
    }
    $ui.Controls.ChartLine.Points = $points
    $fill = New-Object System.Windows.Media.PointCollection
    if ($points.Count -gt 0) {
        $fill.Add((New-Object System.Windows.Point $points[0].X, $height))
        foreach ($point in $points) { $fill.Add($point) }
        $last = $points[$points.Count - 1]
        $fill.Add((New-Object System.Windows.Point $last.X, $height))
        [System.Windows.Controls.Canvas]::SetLeft($ui.Controls.ChartDot, $last.X - 3.5)
        [System.Windows.Controls.Canvas]::SetTop($ui.Controls.ChartDot, $last.Y - 3.5)
        $ui.Controls.ChartDot.Visibility = 'Visible'
    } else { $ui.Controls.ChartDot.Visibility = 'Collapsed' }
    $ui.Controls.ChartFill.Points = $fill
}

function Set-GoatUiMetric {
    param([string]$Metric)
    $script:GoatUi.Metric = $Metric
    $script:GoatUi.Controls.MetricTitle.Text = switch ($Metric) {
        'CPU' { 'UTILIZAÇÃO DO PROCESSADOR' }
        'GPU' { 'UTILIZAÇÃO DA GPU · CONTADOR DO WINDOWS' }
        'RAM' { 'MEMÓRIA FÍSICA EM USO' }
    }
    Update-GoatUiChart
}

function Update-GoatUiWindowScale {
    $ui = $script:GoatUi
    $window = $ui.Window
    $scale = [Math]::Min(1, [Math]::Min($window.ActualWidth / 1180, $window.ActualHeight / 740))
    if ($scale -le 0) { return }
    $root = $window.Content
    if ($scale -lt 1) {
        # Preserve the full desktop layout when the logical work area is smaller
        # because of display resolution or Windows text/display scaling.
        $root.Width = $window.ActualWidth / $scale
        $root.Height = $window.ActualHeight / $scale
        $root.LayoutTransform = New-Object System.Windows.Media.ScaleTransform $scale, $scale
    } else {
        $root.Width = [double]::NaN
        $root.Height = [double]::NaN
        $root.LayoutTransform = [System.Windows.Media.Transform]::Identity
    }
}

function Start-GoatUiWorker {
    param([ValidateSet('Scan','Apply','Restore','Telemetry')] [string]$Kind, [string[]]$Ids = @())
    $ui = $script:GoatUi
    if ($Kind -eq 'Telemetry' -and $ui.TelemetryWorker) { return }
    if ($Kind -ne 'Telemetry' -and $ui.Worker) { return }
    $workerSource = @'
param($goatWorkerDemo, $goatWorkerKind, $goatWorkerIds, $goatWorkerScan, $goatWorkerProgress)
'@
    $workerSource += "`r`n" + $script:GoatScannerSource + "`r`n" + $script:GoatCoreSource + "`r`n"
    $workerSource += @'
$ErrorActionPreference = 'Stop'
switch ($goatWorkerKind) {
    'Scan' {
        $scan = Get-GoatHardwareScan -Demo:$goatWorkerDemo
        $game = if ($goatWorkerDemo) { 'Nenhum jogo detectado · demonstração' } else { Get-GoatDetectedGame }
        [pscustomobject]@{ Scan = $scan; Tweaks = @(Get-GoatTweaks -Scan $scan); Game = $game }
    }
    'Apply' { Invoke-GoatApply -Ids $goatWorkerIds -Scan $goatWorkerScan -Demo:$goatWorkerDemo -ProgressCallback { param($message) $goatWorkerProgress.Enqueue([string]$message) } }
    'Restore' { Restore-GoatLastTransaction -Demo:$goatWorkerDemo -ProgressCallback { param($message) $goatWorkerProgress.Enqueue([string]$message) } }
    'Telemetry' { [pscustomobject]@{ Sample = Get-GoatTelemetrySample; Game = Get-GoatDetectedGame } }
}
'@
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript($workerSource)
    [void]$ps.AddArgument($ui.Demo)
    [void]$ps.AddArgument($Kind)
    [void]$ps.AddArgument($Ids)
    [void]$ps.AddArgument($ui.Scan)
    [void]$ps.AddArgument($ui.Progress)
    try {
        $worker = @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Kind = $Kind; Started = Get-Date }
        if ($Kind -eq 'Telemetry') { $ui.TelemetryWorker = $worker; return }
        $ui.Worker = $worker
        foreach ($check in $ui.Checkboxes) { $check.IsEnabled = $false }
        $ui.Controls.ScannerBadge.Text = $(if ($Kind -eq 'Scan') { '●  ANALISANDO' } else { '●  PROCESSANDO' })
        Set-GoatUiStatus -Text $(switch ($Kind) { 'Scan' { 'Consultando hardware e configuração do Windows em segundo plano…' }; 'Apply' { 'Preparando ponto de restauração e registro dos valores originais…' }; 'Restore' { 'Preparando a recuperação da configuração anterior…' } })
        Update-GoatUiSelection
    } catch {
        $ps.Dispose()
        Set-GoatUiStatus -Text ('Não foi possível iniciar a operação: ' + $_.Exception.Message) -ErrorState $true
    }
}

function Update-GoatUiScan {
    param($Result)
    $ui = $script:GoatUi
    $ui.Scan = $Result.Scan
    $ui.Tweaks = @($Result.Tweaks)
    $scan = $ui.Scan
    $ui.Controls.CpuName.Text = [string]$scan.CPU.Name
    $ui.Controls.GpuName.Text = (@($scan.GPU | ForEach-Object { $_.Name }) -join ' / ')
    $speed = if ($scan.Memory.SpeedMHz) { ' · {0} MT/s (firmware)' -f $scan.Memory.SpeedMHz } else { '' }
    $ui.Controls.MemoryName.Text = '{0} GB{1}' -f $scan.Memory.TotalGB, $speed
    $ui.Controls.GameName.Text = [string]$Result.Game
    $ui.Controls.SystemIdentity.Text = '{0}  ·  {1} núcleos / {2} threads' -f $scan.OS.Caption, $scan.CPU.Cores, $scan.CPU.Threads
    $ui.Controls.ScannerBadge.Text = $(if (@($scan.Errors).Count -gt 0) { '●  LEITURA PARCIAL' } else { '●  ANÁLISE CONCLUÍDA' })
    $recommended = @($ui.Tweaks | Where-Object { $_.Recommended -and $_.Available -and $_.State -ne 'Aplicado' }).Count
    $ui.Controls.FindingSummary.Text = '{0} ajustes sugeridos para revisão' -f $recommended
    $ui.Controls.ScanCount.Text = '{0} constatações · {1} opções disponíveis · sem estimativa artificial de FPS' -f @($scan.Findings).Count, @($ui.Tweaks | Where-Object { $_.Available }).Count
    $ui.Controls.ModeBadge.Text = $(if (@($ui.Tweaks | Where-Object { $_.Id -eq 'game-mode' -and $_.State -eq 'Aplicado' }).Count -gt 0) { 'GAME MODE ATIVO' } else { 'REVISÃO TÉCNICA' })
    $ui.Controls.ActionHint.Text = $(if (-not $ui.Admin -and -not $ui.Demo) { 'Para aplicar, abra o aplicativo como administrador.' } elseif ($ui.Demo) { 'Demonstração: nenhuma configuração do PC será alterada.' } else { 'Ponto de restauração obrigatório. Cada alteração é registrada.' })
    $ui.Controls.DriverSummary.Text = '{0} drivers registrados no inventário. Versões são informadas pelo Windows.' -f @($scan.Drivers).Count
    $ui.Controls.DriversPanel.Children.Clear()
    foreach ($driver in @($scan.Drivers | Sort-Object DeviceName)) {
        $row = New-Object System.Windows.Controls.Border
        $row.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#222B3B')
        $row.BorderThickness = '0,0,0,1'
        $row.Padding = '0,9'
        $text = New-GoatUiText -Text ('{0}    ·    {1}    ·    {2}' -f $driver.DeviceName, $driver.DriverVersion, $driver.Manufacturer) -Size 11
        $row.Child = $text
        [void]$ui.Controls.DriversPanel.Children.Add($row)
    }
    Set-GoatUiNavigation -Page $ui.Page
    Set-GoatUiStatus -Text ('Diagnóstico concluído em {0:HH:mm:ss}. Revise as opções antes de aplicar.' -f (Get-Date))
}

function Complete-GoatUiWorkers {
    $ui = $script:GoatUi
    $progressMessage = ''
    while ($ui.Progress.TryDequeue([ref]$progressMessage)) { Set-GoatUiStatus -Text $progressMessage }
    if ($ui.Worker -and $ui.Worker.Handle.IsCompleted) {
        $worker = $ui.Worker
        $ui.Worker = $null
        try {
            $output = @($worker.PowerShell.EndInvoke($worker.Handle))
            if ($worker.PowerShell.HadErrors) { throw ($worker.PowerShell.Streams.Error | Out-String) }
            if ($output.Count -eq 0) { throw 'A operação não retornou um resultado.' }
            $result = $output[-1]
            if ($worker.Kind -eq 'Scan') { Update-GoatUiScan -Result $result }
            else {
                $message = [string]$result.Message
                if ($result.LogPath) { $message += '  Log: ' + [string]$result.LogPath }
                $ui.Controls.ScannerBadge.Text = $(if ($result.Success) { '●  OPERAÇÃO CONCLUÍDA' } else { '●  OPERAÇÃO INTERROMPIDA' })
                if ($result.Success) {
                    $ui.Selections.Clear()
                    if ($ui.Demo) { $message = 'Simulação concluída. Nenhuma configuração do sistema foi alterada.' }
                    if (-not $ui.Demo) { Start-GoatUiWorker -Kind Scan }
                }
                Set-GoatUiStatus -Text $message -ErrorState (-not $result.Success)
            }
        } catch {
            $ui.Controls.ScannerBadge.Text = '●  VERIFICAR OPERAÇÃO'
            Set-GoatUiStatus -Text ('A operação não foi concluída: ' + $_.Exception.Message) -ErrorState $true
        } finally {
            $worker.PowerShell.Dispose()
            if (-not $ui.Worker) { Update-GoatUiTweaks }
        }
    }
    if ($ui.TelemetryWorker -and $ui.TelemetryWorker.Handle.IsCompleted) {
        $worker = $ui.TelemetryWorker
        $ui.TelemetryWorker = $null
        try {
            $output = @($worker.PowerShell.EndInvoke($worker.Handle))
            if ($output.Count -gt 0 -and -not $worker.PowerShell.HadErrors) {
                $result = $output[-1]
                if ($result.Sample) { $ui.Samples += $result.Sample }
                if ($result.Game) { $ui.Controls.GameName.Text = [string]$result.Game }
            }
        } catch {
            $ui.Controls.HardwareFootnote.Text = 'Uma leitura do monitor não está disponível. Os demais dados permanecem no diagnóstico.'
        } finally { $worker.PowerShell.Dispose() }
        Update-GoatUiChart
    }
    if (((Get-Date) - $ui.LastTelemetry).TotalSeconds -ge 2) {
        $ui.LastTelemetry = Get-Date
        if ($ui.Demo) {
            # Explicitly identified demonstration data; never presented as readings from this PC.
            $tick = ((Get-Date) - $ui.Started).TotalSeconds
            $ui.Samples += [pscustomobject]@{ Timestamp = Get-Date; CPU = (24 + 12 * [Math]::Sin($tick / 7)); GPU = (39 + 16 * [Math]::Sin($tick / 9)); RAM = (42 + 3 * [Math]::Sin($tick / 15)) }
            Update-GoatUiChart
        } elseif ($ui.Scan -and -not $ui.Worker) { Start-GoatUiWorker -Kind Telemetry }
    }
}

function Show-GoatWindow {
    [CmdletBinding()]
    param([switch]$Demo)
    if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'A interface precisa ser aberta no Windows PowerShell com -STA.' }
    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
    if (-not $script:GoatXaml) { $script:GoatXaml = Get-Content -LiteralPath (Join-Path $script:GoatRoot 'src\UI.xaml') -Raw -Encoding UTF8 }
    $reader = New-Object System.Xml.XmlNodeReader ([xml]$script:GoatXaml)
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $workArea = [System.Windows.SystemParameters]::WorkArea
    $availableWidth = [Math]::Max(1, $workArea.Width - 24)
    $availableHeight = [Math]::Max(1, $workArea.Height - 24)
    $window.MinWidth = [Math]::Min(1180, $availableWidth)
    $window.MinHeight = [Math]::Min(740, $availableHeight)
    $window.Width = [Math]::Min(1480, $availableWidth)
    $window.Height = [Math]::Min(970, $availableHeight)
    $window.WindowStartupLocation = 'Manual'
    $window.Left = $workArea.Left + ($workArea.Width - $window.Width) / 2
    $window.Top = $workArea.Top + ($workArea.Height - $window.Height) / 2
    $controls = @{}
    foreach ($node in ([xml]$script:GoatXaml).SelectNodes('//*[@*[local-name()="Name"]]')) {
        $attribute = $node.Attributes | Where-Object { $_.LocalName -eq 'Name' } | Select-Object -First 1
        $controls[$attribute.Value] = $window.FindName($attribute.Value)
    }
    $script:GoatUi = @{
        Window = $window; Controls = $controls; Demo = [bool]$Demo; Admin = [bool](Test-GoatAdministrator)
        Scan = $null; Tweaks = @(); Checkboxes = @(); Selections = @{}; Samples = @(); Metric = 'CPU'; Filter = 'Todos'; Page = 'Home'
        Worker = $null; TelemetryWorker = $null; LastTelemetry = Get-Date; Started = Get-Date
        Progress = [System.Collections.Concurrent.ConcurrentQueue[string]]::new(); Closing = $false
    }
    $ui = $script:GoatUi
    $controls.PrivilegeText.Text = $(if ($ui.Admin) { 'Administrador · sessão local' } else { 'Leitura · sessão sem elevação' })
    if ($Demo) {
        $controls.DemoBadge.Visibility = 'Visible'
        $controls.LiveBadge.Text = '●  SIMULAÇÃO'
        $controls.HardwareFootnote.Text = 'Dados demonstrativos. Este gráfico não representa as medições deste PC.'
        $controls.FooterIdentity.Text = 'GOAT TWEAKS 2.2   /   DEMONSTRAÇÃO SEM ALTERAÇÕES'
        # Demo includes a clearly marked synthetic history; real mode only uses
        # samples actually returned after the monitor starts.
        $demoNow=Get-Date
        for ($age=60; $age -ge 2; $age-=2) {
            $tick=-$age
            $ui.Samples += [pscustomobject]@{Timestamp=$demoNow.AddSeconds(-$age);CPU=(24+12*[Math]::Sin($tick/7));GPU=(39+16*[Math]::Sin($tick/9));RAM=(42+3*[Math]::Sin($tick/15))}
        }
    }
    $navMap = @{ NavHome = 'Home'; NavGame = 'Game'; NavCPU = 'CPU'; NavGPU = 'GPU'; NavBIOS = 'BIOS'; NavNetwork = 'Network'; NavSystem = 'System'; NavDrivers = 'Drivers' }
    foreach ($name in $navMap.Keys) {
        $controls[$name].Tag = $navMap[$name]
        $controls[$name].Add_Checked({ param($sender, $eventArgs) Set-GoatUiNavigation -Page ([string]$sender.Tag) })
    }
    $controls.CpuTab.Add_Checked({ Set-GoatUiMetric -Metric CPU })
    $controls.GpuTab.Add_Checked({ Set-GoatUiMetric -Metric GPU })
    $controls.RamTab.Add_Checked({ Set-GoatUiMetric -Metric RAM })
    $controls.ChartCanvas.Add_SizeChanged({ Update-GoatUiChart })
    $window.Add_SizeChanged({ Update-GoatUiWindowScale })
    $controls.RescanButton.Add_Click({ Start-GoatUiWorker -Kind Scan })
    $controls.ApplyButton.Add_Click({
        $ids = @($script:GoatUi.Checkboxes | Where-Object { $_.IsChecked -eq $true -and $_.IsEnabled } | ForEach-Object { [string]$_.Tag })
        if ($ids.Count -gt 0) { Start-GoatUiWorker -Kind Apply -Ids $ids }
    })
    $controls.RestoreButton.Add_Click({ Start-GoatUiWorker -Kind Restore })
    $controls.MinimizeButton.Add_Click({ $script:GoatUi.Window.WindowState = 'Minimized' })
    $controls.CloseButton.Add_Click({ $script:GoatUi.Window.Close() })
    $controls.DragBar.Add_MouseLeftButtonDown({
        param($sender, $eventArgs)
        if ($eventArgs.ClickCount -eq 2) {
            $script:GoatUi.Window.WindowState = $(if ($script:GoatUi.Window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' })
        } else { $script:GoatUi.Window.DragMove() }
    })
    $tools = @(
        @('NVCleanstall', 'Instalação personalizada de drivers NVIDIA.', 'https://www.techpowerup.com/nvcleanstall/'),
        @('Display Driver Uninstaller', 'Página do desenvolvedor Wagnardsoft.', 'https://www.wagnardsoft.com/'),
        @('DirectX Runtime', 'Componentes legados oficiais da Microsoft.', 'https://www.microsoft.com/en-us/download/details.aspx?id=35'),
        @('Visual C++ Redistributable', 'Pacotes e orientações da Microsoft.', 'https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist'),
        @('Drivers NVIDIA', 'Downloads oficiais para placas NVIDIA.', 'https://www.nvidia.com/Download/index.aspx'),
        @('Drivers AMD', 'Drivers de GPU e chipset AMD.', 'https://www.amd.com/en/support'),
        @('Intel Driver & Support', 'Suporte e identificação da Intel.', 'https://www.intel.com/content/www/us/en/support/detect.html'),
        @('Windows Update', 'Abrir as configurações locais de atualização.', 'ms-settings:windowsupdate')
    )
    foreach ($tool in $tools) {
        $button = New-Object System.Windows.Controls.Button
        $button.Width = 252
        $button.Height = 91
        $button.Margin = '0,0,12,12'
        $button.Padding = '14'
        $button.HorizontalContentAlignment = 'Left'
        $button.Tag = $tool[2]
        $stack = New-Object System.Windows.Controls.StackPanel
        $title = New-GoatUiText -Text ($tool[0] + ' ↗') -Color '#D5B9F5' -Size 12
        $title.FontWeight = 'SemiBold'
        [void]$stack.Children.Add($title)
        $detail = New-GoatUiText -Text $tool[1] -Size 10
        $detail.Margin = '0,7,0,0'
        [void]$stack.Children.Add($detail)
        $button.Content = $stack
        $button.Add_Click({
            param($sender, $eventArgs)
            try { Start-Process -FilePath ([string]$sender.Tag) -ErrorAction Stop | Out-Null }
            catch { Set-GoatUiStatus -Text ('Não foi possível abrir o link: ' + $_.Exception.Message) -ErrorState $true }
        })
        [void]$controls.ToolsPanel.Children.Add($button)
    }
    $timer = New-Object System.Windows.Threading.DispatcherTimer
    $timer.Interval = [TimeSpan]::FromMilliseconds(250)
    $timer.Add_Tick({
        try { Complete-GoatUiWorkers }
        catch { Set-GoatUiStatus -Text ('Erro na atualização da interface: ' + $_.Exception.Message) -ErrorState $true }
    })
    $ui.Timer = $timer
    $window.Add_Closing({
        param($sender, $eventArgs)
        if ($script:GoatUi.Worker -and $script:GoatUi.Worker.Kind -ne 'Scan') {
            $eventArgs.Cancel = $true
            Set-GoatUiStatus -Text 'Aguarde a operação terminar antes de fechar. O registro da transação precisa ser concluído.'
        }
    })
    $window.Add_Closed({
        $script:GoatUi.Closing = $true
        $script:GoatUi.Timer.Stop()
        foreach ($worker in @($script:GoatUi.Worker, $script:GoatUi.TelemetryWorker)) {
            if ($worker) {
                try { [void]$worker.PowerShell.BeginStop($null, $null) } catch { }
            }
        }
    })
    $window.Add_ContentRendered({
        if (-not $script:GoatUi.Worker -and -not $script:GoatUi.Scan) { Start-GoatUiWorker -Kind Scan }
    })
    $timer.Start()
    if ($script:GoatUiTestHook -is [scriptblock]) { & $script:GoatUiTestHook $window }
    try { [void]$window.ShowDialog() }
    finally {
        $timer.Stop()
        foreach ($worker in @($ui.Worker, $ui.TelemetryWorker)) {
            if ($worker) { try { $worker.PowerShell.Dispose() } catch { } }
        }
    }
}
