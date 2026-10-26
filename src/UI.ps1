# GOAT Tweaks v2.3 - Windows PowerShell 5.1 / WPF presentation layer.
# The UI thread only renders completed worker results. System operations run in isolated runspaces.

function New-GoatUiText {
    param([string]$Text, [string]$Color = '#A0A0A0', [double]$Size = 11)
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
    $color = if ($ErrorState) { '#DA8D87' } else { '#A0A0A0' }
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
    if ($ui.Controls.ContainsKey('CatalogRunButton')) { Update-GoatUiCatalogActions }
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
        $title = New-GoatUiText -Text $tweak.Title -Color '#F3F3F3' -Size 11
        $title.FontWeight = 'SemiBold'
        [void]$stack.Children.Add($title)
        $detail = [string]$tweak.Description
        if (-not $tweak.Available -and $tweak.UnavailableReason) { $detail = [string]$tweak.UnavailableReason }
        $description = New-GoatUiText -Text $detail -Color '#A0A0A0' -Size 10
        $description.Margin = '0,4,0,0'
        [void]$stack.Children.Add($description)
        $meta = @($tweak.Risk)
        if ($tweak.RequiresRestart) { $meta += 'reinício necessário' }
        if ($tweak.State -eq 'Aplicado') { $meta += 'já aplicado' }
        $label = New-GoatUiText -Text ($meta -join ' · ') -Color $(if ($tweak.Risk -eq 'Moderado') { '#D4AE69' } else { '#A0A0A0' }) -Size 9
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
    $border.Background = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#101010')
    $border.CornerRadius = New-Object System.Windows.CornerRadius 7
    $border.Padding = '12'
    $border.Margin = '0,0,0,9'
    $stack = New-Object System.Windows.Controls.StackPanel
    $severity = [string]$Finding.Severity
    $color = if ($severity -match 'Warning|Aviso|Aten|Moderad') { '#D4AE69' } elseif ($severity -match 'Error|Erro|Cr.tic') { '#DA8D87' } else { '#CFB579' }
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
        $architectureReading=$null
        $readings=$ui.Scan.AdvancedState.Readings
        if ($readings -is [Collections.IDictionary]) { $architectureReading=$readings['cpu-architecture'] }
        elseif ($readings) { $property=$readings.PSObject.Properties['cpu-architecture'];if($property){$architectureReading=$property.Value} }
        $architecture=if($architectureReading -and $architectureReading.Text){' · '+[string]$architectureReading.Text}else{''}
        Add-GoatUiFinding -Finding ([pscustomobject]@{ Category = 'CPU'; Severity = 'Info'; Title = [string]$ui.Scan.CPU.Name; Detail = (('{0} núcleos · {1} threads · plano de energia: {2}' -f $ui.Scan.CPU.Cores, $ui.Scan.CPU.Threads, $ui.Scan.Power.ActiveSchemeName)+$architecture) })
    }
    if ($ui.Filter -eq 'GPU') {
        foreach ($gpu in @($ui.Scan.GPU)) {
            Add-GoatUiFinding -Finding ([pscustomobject]@{ Category = 'GPU'; Severity = 'Info'; Title = [string]$gpu.Name; Detail = ('Driver: {0} · prioridade de interrupção informada: {1}' -f $gpu.DriverVersion, $gpu.InterruptPriority) })
        }
    }
    if ($ui.Filter -eq 'RAM') {
        $memory=$ui.Scan.Memory
        Add-GoatUiFinding -Finding ([pscustomobject]@{ Category='RAM'; Severity='Info'; Title='Memória física detectada'; Detail=('{0} GB totais · {1} GB disponíveis · velocidade informada pelo firmware: {2} MT/s' -f $memory.TotalGB,$memory.AvailableGB,$memory.SpeedMHz) })
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
        $ui.Filter -eq 'Todos' -or $ui.Filter -eq 'Jogo' -or $_.Category -eq $ui.Filter -or ($ui.Filter -eq 'RAM' -and $_.Title -match 'mem.ria|RAM') -or ($ui.Filter -eq 'Sistema' -and $_.Category -eq 'SO') -or ($ui.Filter -eq 'BIOS' -and $_.Category -match 'BIOS|Placa')
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

function Test-GoatRecommendationSourceUrl {
    param([string]$Url)
    $uri=$null
    return ([uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme -eq 'https' -and $uri.IsDefaultPort -and -not $uri.UserInfo -and $uri.DnsSafeHost -in @('github.com','raw.githubusercontent.com','learn.microsoft.com','devblogs.microsoft.com'))
}

function Update-GoatUiRecommendations {
    $ui=$script:GoatUi
    $ui.Controls.RecommendationsPanel.Children.Clear()
    $ui.VisibleRecommendations=@()
    if (-not $ui.Scan) { return }
    $recommendations=@($ui.Scan.Recommendations | Where-Object {
        $ui.Filter -eq 'Todos' -or $ui.Filter -eq 'Jogo' -or $_.Category -eq $ui.Filter
    })
    $ui.VisibleRecommendations=$recommendations
    $ui.Controls.RecommendationCount.Text='{0} análises nesta área' -f $recommendations.Count
    foreach ($recommendation in $recommendations) {
        $card=New-Object System.Windows.Controls.Border
        $card.Background=[System.Windows.Media.BrushConverter]::new().ConvertFromString('#101010')
        $card.BorderBrush=[System.Windows.Media.BrushConverter]::new().ConvertFromString('#292929')
        $card.BorderThickness='1';$card.CornerRadius='8';$card.Padding='15';$card.Margin='0,0,0,11'
        $content=New-Object System.Windows.Controls.StackPanel
        $header=New-Object System.Windows.Controls.Grid
        $column=New-Object System.Windows.Controls.ColumnDefinition
        [void]$header.ColumnDefinitions.Add($column)
        $column=New-Object System.Windows.Controls.ColumnDefinition
        $column.Width='Auto'
        [void]$header.ColumnDefinitions.Add($column)
        $title=New-GoatUiText -Text ('{0}  /  {1}' -f $recommendation.Category,$recommendation.Title) -Color '#EBEBEB' -Size 12
        $title.FontWeight='SemiBold';$title.Margin='0,0,14,0'
        [void]$header.Children.Add($title)
        $badge=New-Object System.Windows.Controls.Border
        $badge.CornerRadius='4';$badge.Padding='8,4';$badge.VerticalAlignment='Top'
        $badge.Background=[System.Windows.Media.BrushConverter]::new().ConvertFromString('#242018')
        $statusColor=switch ([string]$recommendation.Status) {
            'Recomendado' {'#E4B95B'}
            'Configurado' {'#CACACA'}
            'Revisão manual' {'#C7AB73'}
            default {'#858585'}
        }
        $badge.Child=New-GoatUiText -Text ([string]$recommendation.Status) -Color $statusColor -Size 10
        [System.Windows.Controls.Grid]::SetColumn($badge,1)
        [void]$header.Children.Add($badge)
        [void]$content.Children.Add($header)
        $current=New-GoatUiText -Text ('Estado atual: '+[string]$recommendation.CurrentState) -Color '#B4B4B4' -Size 11
        $current.Margin='0,9,0,0';[void]$content.Children.Add($current)
        $detail=New-GoatUiText -Text ([string]$recommendation.Detail) -Color '#909090' -Size 11
        $detail.Margin='0,6,0,0';[void]$content.Children.Add($detail)
        if ($recommendation.Conflict) {
            $conflict=New-GoatUiText -Text 'Fontes divergentes · compare a justificativa e valide sob a mesma carga.' -Color '#D2A46B' -Size 10
            $conflict.Margin='0,9,0,0';[void]$content.Children.Add($conflict)
        }
        $native=@($ui.Tweaks | Where-Object Id -eq $recommendation.ActionId)
        $metadata='Risco: '+[string]$recommendation.Risk
        if ($recommendation.ActionId -and $native.Count -gt 0) { $metadata+=' · ajuste disponível no checklist acima' }
        $risk=New-GoatUiText -Text $metadata -Color '#777777' -Size 10
        $risk.Margin='0,9,0,0';[void]$content.Children.Add($risk)
        $sources=New-Object System.Windows.Controls.WrapPanel
        $sources.Margin='0,9,0,0'
        foreach ($source in @($recommendation.Sources)) {
            $sourceName=if ($ui.Repositories.ContainsKey([string]$source.RepositoryId)) { [string]$ui.Repositories[[string]$source.RepositoryId].Name } else { [string]$source.RepositoryId }
            if (Test-GoatRecommendationSourceUrl -Url ([string]$source.Url)) {
                switch (([uri]$source.Url).DnsSafeHost) {
                    'learn.microsoft.com' {$sourceName='Microsoft Learn'}
                    'devblogs.microsoft.com' {$sourceName='Microsoft DevBlogs'}
                }
            }
            $link=New-Object System.Windows.Controls.Button
            $link.Content=$sourceName+' ↗';$link.Tag=[string]$source.Url
            $link.FontSize=10;$link.Padding='9,5';$link.Margin='0,0,7,4'
            $link.Background=[System.Windows.Media.BrushConverter]::new().ConvertFromString('#1A1915')
            $link.Foreground=[System.Windows.Media.BrushConverter]::new().ConvertFromString('#C4AB77')
            $link.ToolTip=('{0} · {1}' -f $source.Stance,$source.Note)
            $link.IsEnabled=Test-GoatRecommendationSourceUrl -Url ([string]$source.Url)
            $link.Add_Click({
                param($sender,$eventArgs)
                if (Test-GoatRecommendationSourceUrl -Url ([string]$sender.Tag)) { Open-GoatUiSourceUrl -Url ([string]$sender.Tag) }
            })
            [void]$sources.Children.Add($link)
        }
        [void]$content.Children.Add($sources)
        $card.Child=$content
        [void]$ui.Controls.RecommendationsPanel.Children.Add($card)
    }
    if ($recommendations.Count -eq 0) {
        [void]$ui.Controls.RecommendationsPanel.Children.Add((New-GoatUiText -Text 'Não há recomendações cruzadas disponíveis para esta área nesta leitura.' -Size 11))
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
        RAM = @('RAM', 'Memória RAM', 'Capacidade, disponibilidade e compressão de memória com contexto das quatro referências.', 'Ajustes de memória')
        BIOS = @('BIOS', 'Placa-mãe & BIOS', 'Identificação da plataforma e itens que exigem verificação no firmware.', 'Plataforma & timers')
        Network = @('Rede', 'Rede & conectividade', 'Adaptadores detectados e configuração da pilha de rede.', 'Ajustes de rede')
        System = @('Sistema', 'Debloat & sistema', 'Configurações reversíveis e comportamento do Windows.', 'Ajustes do sistema')
        Drivers = @('Drivers', 'Drivers & ferramentas', 'Inventário local e acesso às páginas oficiais da bancada.', 'Ferramentas')
        Winutil = @('Biblioteca', 'Winutil', 'Arquivos originais, recursos e aplicativo oficial do Chris Titus Tech.', 'Winutil')
        WinSux = @('Biblioteca', 'WinSux', 'A árvore original de arquivos do projeto FR33THYFR33THY.', 'WinSux')
        Ultimate = @('Biblioteca', 'Ultimate', 'O guia de otimização original, organizado pelas pastas do projeto.', 'Ultimate')
        RyTuneX = @('Biblioteca', 'RyTuneX', 'Código, recursos, releases e página oficial do aplicativo RyTuneX.', 'RyTuneX')
    }
    $settings = $map[$Page]
    $ui.Filter = $settings[0]
    $ui.Controls.HeaderTitle.Text = $settings[1]
    if ($ui.Scan) { $ui.Controls.HeaderSubtitle.Text = $settings[2] }
    $ui.Controls.OptimizerTitle.Text = $settings[3]
    $isDrivers = ($Page -eq 'Drivers')
    $isCatalog = $Page -in @('Winutil','WinSux','Ultimate','RyTuneX')
    $ui.Controls.CatalogSection.Visibility = $(if ($isCatalog) { 'Visible' } else { 'Collapsed' })
    $ui.Controls.DriversSection.Visibility = $(if ($isDrivers) { 'Visible' } else { 'Collapsed' })
    $ui.Controls.DashboardGrid.Visibility = $(if ($isDrivers -or $isCatalog) { 'Collapsed' } else { 'Visible' })
    $ui.Controls.ActionsSection.Visibility = $(if ($isDrivers -or $isCatalog) { 'Collapsed' } else { 'Visible' })
    $ui.Controls.UpdatesSection.Visibility = $(if ($Page -eq 'Home') { 'Visible' } else { 'Collapsed' })
    $ui.Controls.CategorySection.Visibility = $(if ($isCatalog -or -not $ui.Scan) { 'Collapsed' } else { 'Visible' })
    $ui.Controls.CategoryTitle.Text = $(if ($Page -eq 'Home') { 'Recomendações para esta máquina' } else { 'Recomendações por área' })
    $descriptions = @{
        Home = 'Constatações baseadas nas consultas disponíveis. Gargalos e latência exigem medições sob carga.'
        Game = 'A seleção usa o estado encontrado no Windows. Compare desempenho e estabilidade antes e depois.'
        CPU = 'C-States, afinidade e políticas de núcleos dependem do firmware e da carga. Não são alterados automaticamente.'
        GPU = 'MSI é informado a partir do Registro. Suporte a ReBAR e benefícios do HAGS exigem verificação do driver, firmware e jogo.'
        RAM = 'Compare o estado atual com as referências. Compressão e paginação dependem da carga; a aplicação de qualquer ajuste exige seleção e revisão.'
        BIOS = 'Nenhuma configuração de BIOS, HPET, BCD ou resolução de timer é modificada automaticamente.'
        Network = 'Buffers e offloads precisam de medição no adaptador e na rede utilizados. Não há ganho universal de latência.'
        System = 'As alterações disponíveis preservam os valores capturados para uma restauração posterior.'
        Drivers = 'Compare o inventário com as referências e a documentação do fabricante. Uma versão instalada, isoladamente, não comprova que há atualização disponível.'
    }
    if ($descriptions.ContainsKey($Page)) { $ui.Controls.CategoryDescription.Text = $descriptions[$Page] }
    if ($Page -eq 'CPU') { $ui.Controls.CpuTab.IsChecked = $true }
    if ($Page -eq 'GPU') { $ui.Controls.GpuTab.IsChecked = $true }
    if ($Page -eq 'RAM') { $ui.Controls.RamTab.IsChecked = $true }
    if ($isCatalog) { Set-GoatUiCatalog -RepositoryId $Page.ToLowerInvariant() }
    else {
        if (-not $isDrivers) { Update-GoatUiTweaks }
        Update-GoatUiRecommendations
        Update-GoatUiFindings
    }
    $ui.Controls.MainScroll.ScrollToTop()
}

function Set-GoatUiCatalog {
    param([string]$RepositoryId)
    $ui = $script:GoatUi
    $repo = $ui.Repositories[$RepositoryId]
    if (-not $repo) {
        $ui.Controls.CatalogTitle.Text = 'Catálogo indisponível'
        $ui.Controls.CatalogDescription.Text = 'O catálogo local deste projeto não foi carregado. Confira os arquivos da distribuição.'
        $ui.Controls.CatalogGrid.ItemsSource = [object[]]@()
        $ui.Controls.CatalogPrimaryButton.IsEnabled = $false
        return
    }
    if ($ui.CurrentRepository -and $ui.CurrentRepository.Id -eq $RepositoryId) { Update-GoatUiCatalogActions; return }
    $ui.CatalogRefreshing = $true
    try {
        $ui.CurrentRepository = $repo
        $ui.Controls.CatalogTitle.Text = [string]$repo.Name
        $ui.Controls.CatalogDescription.Text = [string]$repo.Description
        $ui.Controls.CatalogRevision.Text = 'Revisão {0} · catálogo {1} · conteúdo original de {2}/{3}' -f $repo.CommitShort, $repo.UpdatedAt, $repo.Owner, $repo.Repository
        $ui.Controls.CatalogSearchBox.Text = ''
        $ui.Controls.CatalogGroupFilter.ItemsSource = [string[]](@('Todas as pastas') + @($repo.Items | Select-Object -ExpandProperty Group -Unique | Sort-Object))
        $ui.Controls.CatalogKindFilter.ItemsSource = [string[]](@('Todos os tipos') + @($repo.Items | Select-Object -ExpandProperty Kind -Unique | Sort-Object))
        $ui.Controls.CatalogGroupFilter.SelectedIndex = 0
        $ui.Controls.CatalogKindFilter.SelectedIndex = 0
        $ui.PrimaryItem = @($repo.Items | Where-Object { $_.Id -eq $repo.PrimaryItemId } | Select-Object -First 1)[0]
        $ui.Controls.CatalogPrimaryButton.Content = $(if ($ui.PrimaryItem) { [string]$ui.PrimaryItem.RunLabel + ' ↗' } else { 'Ver projeto oficial ↗' })
        $ui.Controls.CatalogOperationStatus.Text = 'Catálogo completo: arquivos, recursos e releases. Nada é executado ao abrir esta página.'
        $ui.Controls.CatalogOpenFolderButton.Visibility = 'Collapsed'
    } finally { $ui.CatalogRefreshing = $false }
    Update-GoatUiCatalogFilter
}

function Update-GoatUiCatalogColumns {
    $grid=$script:GoatUi.Controls.CatalogGrid
    if ($grid.ActualWidth -lt 340 -or $grid.Columns.Count -ne 3) { return }
    # Explicit viewport widths avoid stale star-column measurements when the
    # virtualized table is hidden, filtered and reopened inside the page scroller.
    # Only rows are virtualized: all three columns always remain visible.
    $available=[Math]::Floor($grid.ActualWidth - 18)
    $kindWidth=92
    $nameWidth=[Math]::Floor(($available-$kindWidth)*0.56)
    $groupWidth=$available-$kindWidth-$nameWidth
    $grid.Columns[0].Width=New-Object System.Windows.Controls.DataGridLength $nameWidth
    $grid.Columns[1].Width=New-Object System.Windows.Controls.DataGridLength $kindWidth
    $grid.Columns[2].Width=New-Object System.Windows.Controls.DataGridLength $groupWidth
}

function Update-GoatUiCatalogFilter {
    $ui = $script:GoatUi
    if ($ui.CatalogRefreshing -or -not $ui.CurrentRepository) { return }
    $search = $ui.Controls.CatalogSearchBox.Text.Trim()
    $group = [string]$ui.Controls.CatalogGroupFilter.SelectedItem
    $kind = [string]$ui.Controls.CatalogKindFilter.SelectedItem
    $allItems = @($ui.CurrentRepository.Items)
    $visible = @($allItems | Where-Object {
        ($group -eq '' -or $group -eq 'Todas as pastas' -or $_.Group -eq $group) -and
        ($kind -eq '' -or $kind -eq 'Todos os tipos' -or $_.Kind -eq $kind) -and
        ($search -eq '' -or ('{0} {1} {2} {3} {4}' -f $_.Name, $_.Path, $_.Group, $_.Kind, $_.Description).IndexOf($search, [StringComparison]::OrdinalIgnoreCase) -ge 0)
    } | Sort-Object Group,Name)
    $ui.Controls.CatalogGrid.ItemsSource = [object[]]$visible
    Update-GoatUiCatalogColumns
    $ui.Controls.CatalogCount.Text = '{0} de {1} itens · arquivos + recursos + releases' -f $visible.Count, $allItems.Count
    if ($visible.Count -gt 0) { $ui.Controls.CatalogGrid.SelectedIndex = 0 }
    else { Update-GoatUiCatalogDetails }
    Update-GoatUiCatalogActions
}

function Update-GoatUiCatalogDetails {
    $ui = $script:GoatUi
    $item = $ui.Controls.CatalogGrid.SelectedItem
    $ui.CatalogItem = $item
    $ui.Controls.CatalogDetailsScroll.ScrollToTop()
    if (-not $item) {
        $ui.Controls.CatalogItemName.Text = 'Nenhum item selecionado'
        $ui.Controls.CatalogItemKind.Text = ''
        $ui.Controls.CatalogItemPath.Text = ''
        $ui.Controls.CatalogItemDescription.Text = 'Altere a busca ou os filtros para encontrar os arquivos e recursos do projeto.'
        $ui.Controls.CatalogItemWarning.Text = 'A lista mostra todos os tipos de conteúdo quando os filtros estão em Todos.'
        $ui.Controls.CatalogItemHash.Text = ''
        Update-GoatUiCatalogActions
        return
    }
    $ui.Controls.CatalogItemName.Text = [string]$item.Name
    $size = if ($null -ne $item.Size) { if ([double]$item.Size -ge 1MB) { '{0:N1} MB' -f ([double]$item.Size / 1MB) } elseif ([double]$item.Size -ge 1KB) { '{0:N1} KB' -f ([double]$item.Size / 1KB) } else { '{0} bytes' -f $item.Size } } else { 'tamanho não informado' }
    $ui.Controls.CatalogItemKind.Text = '{0} · {1}' -f $item.Kind, $size
    $ui.Controls.CatalogItemPath.Text = [string]$item.Path
    $ui.Controls.CatalogItemDescription.Text = $(if ($item.Description) { [string]$item.Description } else { 'Arquivo original do projeto. Consulte o conteúdo e as instruções do autor.' })
    $ui.Controls.CatalogItemWarning.Text = $(if ($item.Warning) { [string]$item.Warning } else { 'Revise o conteúdo original e as instruções do autor antes de executar este item.' })
    $ui.Controls.CatalogItemHash.Text = $(if ($item.Sha256) { 'SHA-256: ' + [string]$item.Sha256 } elseif ($item.Sha) { 'Git blob: ' + [string]$item.Sha } else { 'Origem: ' + [string]$item.Operation })
    $ui.Controls.CatalogRunButton.Content = $(if ($item.RunLabel) { [string]$item.RunLabel } else { 'Execução não disponível' })
    Update-GoatUiCatalogActions
}

function Update-GoatUiCatalogActions {
    $ui = $script:GoatUi
    $item = $ui.CatalogItem
    $busy = [bool]$ui.Worker
    $ui.Controls.CatalogViewSourceButton.IsEnabled = [bool]($item -and $item.SourceUrl)
    $ui.Controls.CatalogDownloadButton.IsEnabled = [bool]($item -and $item.Operation -in @('RepositoryFile','ReleaseAsset') -and $item.DownloadUrl -and -not $busy)
    $ui.Controls.CatalogRunButton.IsEnabled = [bool]($item -and $item.CanRun -and -not $busy -and ($ui.Admin -or $ui.Demo -or $item.LaunchType -eq 'uri'))
    $primary = $ui.PrimaryItem
    $ui.Controls.CatalogPrimaryButton.IsEnabled = [bool]($ui.CurrentRepository -and -not $busy -and (-not $primary -or ($primary.CanRun -and ($ui.Admin -or $ui.Demo -or $primary.LaunchType -eq 'uri'))))
    $ui.Controls.CatalogPrimaryButton.ToolTip = $(if ($primary -and -not $ui.Admin -and -not $ui.Demo -and $primary.LaunchType -ne 'uri') { 'Abra o GOAT como administrador para executar esta ferramenta externa.' } elseif ($primary) { [string]$primary.Warning } else { 'Abrir o repositório oficial do projeto.' })
    $ui.Controls.CatalogRepositoryButton.IsEnabled = [bool]$ui.CurrentRepository
    $ui.Controls.CatalogLicenseButton.IsEnabled = [bool]($ui.CurrentRepository -and $ui.CurrentRepository.LicenseUrl)
    if ($item -and $item.CanRun -and -not $ui.Admin -and -not $ui.Demo -and $item.LaunchType -ne 'uri') {
        $ui.Controls.CatalogRunButton.ToolTip = 'Abra o GOAT como administrador para executar ferramentas externas.'
    } else { $ui.Controls.CatalogRunButton.ToolTip = [string]$item.Warning }
}

function Open-GoatUiSourceUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return }
    try { Start-Process -FilePath $Url -ErrorAction Stop | Out-Null }
    catch { Set-GoatUiStatus -Text ('Não foi possível abrir a origem: ' + $_.Exception.Message) -ErrorState $true }
}

function Invoke-GoatUiExternalAction {
    param([ValidateSet('Download','Run')][string]$Action, $Item)
    $ui = $script:GoatUi
    if ($ui.Worker -or -not $Item -or -not $ui.CurrentRepository) { return }
    if ($Action -eq 'Run' -and -not $Item.CanRun) { return }
    if ($Action -eq 'Run' -and $Item.LaunchType -ne 'uri' -and -not $ui.Demo) {
        $review = @(
            ('Projeto: {0}' -f $ui.CurrentRepository.Name),
            ('Item: {0}' -f $Item.Path),
            '', [string]$Item.Warning, '',
            'Este comando abre o arquivo original em um processo externo com privilégios de administrador.',
            'Será exigido um ponto de restauração e a operação será registrada. Alterações da ferramenta externa não são revertidas pelo botão Restaurar do GOAT.',
            'Leia o arquivo e as instruções do autor. A ferramenta pode reiniciar o PC ou exigir etapas adicionais.',
            '', 'Executar este item agora?'
        ) -join "`r`n"
        $answer = [System.Windows.MessageBox]::Show($ui.Window, $review, ('Revisar execução · ' + $Item.Name), [System.Windows.MessageBoxButton]::YesNo, [System.Windows.MessageBoxImage]::Warning, [System.Windows.MessageBoxResult]::No)
        if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    }
    Start-GoatUiWorker -Kind Integration -RepositoryId $ui.CurrentRepository.Id -ItemId $Item.Id -ExternalAction $Action
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
    param([ValidateSet('Scan','Apply','Restore','Telemetry','Integration')] [string]$Kind, [string[]]$Ids = @(), [string]$RepositoryId, [string]$ItemId, [string]$ExternalAction)
    $ui = $script:GoatUi
    if ($Kind -eq 'Telemetry' -and $ui.TelemetryWorker) { return }
    if ($Kind -ne 'Telemetry' -and $ui.Worker) { return }
    $workerSource = @'
param($goatWorkerDemo, $goatWorkerKind, $goatWorkerIds, $goatWorkerScan, $goatWorkerProgress, $goatWorkerCatalogJson, $goatWorkerRepositoryId, $goatWorkerItemId, $goatWorkerExternalAction, $goatWorkerRecommendationJson)
'@
    $workerSource += "`r`n" + $script:GoatScannerSource + "`r`n" + $script:GoatCoreSource + "`r`n"
    if ($Kind -eq 'Scan') { $workerSource += $script:GoatAdvancedScannerSource + "`r`n" + $script:GoatRecommendationSource + "`r`n" }
    if ($Kind -eq 'Integration') { $workerSource += $script:GoatIntegrationSource + "`r`n" }
    $workerSource += @'
$ErrorActionPreference = 'Stop'
$script:GoatCatalogJson = $goatWorkerCatalogJson
$script:GoatRecommendationJson = $goatWorkerRecommendationJson
switch ($goatWorkerKind) {
    'Scan' {
        $scan = Get-GoatHardwareScan -Demo:$goatWorkerDemo
        $advanced = Get-GoatAdvancedState -Demo:$goatWorkerDemo -Scan $scan
        $recommendations = @(Get-GoatRecommendations -Scan $scan -AdvancedState $advanced)
        Add-Member -InputObject $scan -NotePropertyName AdvancedState -NotePropertyValue $advanced -Force
        Add-Member -InputObject $scan -NotePropertyName Recommendations -NotePropertyValue $recommendations -Force
        $game = if ($goatWorkerDemo) { 'Nenhum jogo detectado · demonstração' } else { Get-GoatDetectedGame }
        [pscustomobject]@{ Scan = $scan; Tweaks = @(Get-GoatTweaks -Scan $scan); Game = $game }
    }
    'Apply' { Invoke-GoatApply -Ids $goatWorkerIds -Scan $goatWorkerScan -Demo:$goatWorkerDemo -ProgressCallback { param($message) $goatWorkerProgress.Enqueue([string]$message) } }
    'Restore' { Restore-GoatLastTransaction -Demo:$goatWorkerDemo -ProgressCallback { param($message) $goatWorkerProgress.Enqueue([string]$message) } }
    'Telemetry' { [pscustomobject]@{ Sample = Get-GoatTelemetrySample; Game = Get-GoatDetectedGame } }
    'Integration' { Invoke-GoatExternalItem -RepositoryId $goatWorkerRepositoryId -ItemId $goatWorkerItemId -Action $goatWorkerExternalAction -Demo:$goatWorkerDemo -ProgressCallback { param($message) $goatWorkerProgress.Enqueue([string]$message) } }
}
'@
    $ps = [PowerShell]::Create()
    [void]$ps.AddScript($workerSource)
    [void]$ps.AddArgument($ui.Demo)
    [void]$ps.AddArgument($Kind)
    [void]$ps.AddArgument($Ids)
    [void]$ps.AddArgument($ui.Scan)
    [void]$ps.AddArgument($ui.Progress)
    [void]$ps.AddArgument($script:GoatCatalogJson)
    [void]$ps.AddArgument($RepositoryId)
    [void]$ps.AddArgument($ItemId)
    [void]$ps.AddArgument($ExternalAction)
    [void]$ps.AddArgument($script:GoatRecommendationJson)
    try {
        $worker = @{ PowerShell = $ps; Handle = $ps.BeginInvoke(); Kind = $Kind; Started = Get-Date; ExternalAction = $ExternalAction; RepositoryId = $RepositoryId; ItemId = $ItemId }
        if ($Kind -eq 'Telemetry') { $ui.TelemetryWorker = $worker; return }
        $ui.Worker = $worker
        foreach ($check in $ui.Checkboxes) { $check.IsEnabled = $false }
        $ui.Controls.ScannerBadge.Text = $(if ($Kind -eq 'Scan') { '●  ANALISANDO' } else { '●  PROCESSANDO' })
        $message = switch ($Kind) { 'Scan' { 'Consultando hardware e configuração do Windows em segundo plano…' }; 'Apply' { 'Preparando ponto de restauração e registro dos valores originais…' }; 'Restore' { 'Preparando a recuperação da configuração anterior…' }; 'Integration' { if ($ExternalAction -eq 'Download') { 'Baixando o arquivo original e validando a integridade…' } else { 'Preparando a abertura da ferramenta externa selecionada…' } } }
        Set-GoatUiStatus -Text $message
        if ($Kind -eq 'Integration') { $ui.Controls.CatalogOperationStatus.Text = $message }
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
    $reviewCount=@($scan.Recommendations | Where-Object Status -eq 'Revisão manual').Count
    $configuredCount=@($scan.Recommendations | Where-Object Status -eq 'Configurado').Count
    $ui.Controls.FindingSummary.Text = '{0} ajustes sugeridos · {1} análises cruzadas' -f $recommended,@($scan.Recommendations).Count
    $ui.Controls.ScanCount.Text = '{0} configurados · {1} para revisão manual · confirme a evidência por área' -f $configuredCount,$reviewCount
    $ui.Controls.ModeBadge.Text = $(if (@($ui.Tweaks | Where-Object { $_.Id -eq 'game-mode' -and $_.State -eq 'Aplicado' }).Count -gt 0) { 'GAME MODE ATIVO' } else { 'REVISÃO TÉCNICA' })
    $ui.Controls.ActionHint.Text = $(if (-not $ui.Admin -and -not $ui.Demo) { 'Para aplicar, abra o aplicativo como administrador.' } elseif ($ui.Demo) { 'Demonstração: nenhuma configuração do PC será alterada.' } else { 'Ponto de restauração obrigatório. Cada alteração é registrada.' })
    $ui.Controls.DriverSummary.Text = '{0} drivers registrados no inventário. Versões são informadas pelo Windows.' -f @($scan.Drivers).Count
    $ui.Controls.DriversPanel.Children.Clear()
    foreach ($driver in @($scan.Drivers | Sort-Object DeviceName)) {
        $row = New-Object System.Windows.Controls.Border
        $row.BorderBrush = [System.Windows.Media.BrushConverter]::new().ConvertFromString('#242424')
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
    while ($ui.Progress.TryDequeue([ref]$progressMessage)) {
        Set-GoatUiStatus -Text $progressMessage
        if ($ui.Worker -and $ui.Worker.Kind -eq 'Integration') { $ui.Controls.CatalogOperationStatus.Text = $progressMessage }
    }
    if ($ui.Worker -and $ui.Worker.Handle.IsCompleted) {
        $worker = $ui.Worker
        $ui.Worker = $null
        try {
            $output = @($worker.PowerShell.EndInvoke($worker.Handle))
            if ($worker.PowerShell.HadErrors) { throw ($worker.PowerShell.Streams.Error | Out-String) }
            if ($output.Count -eq 0) { throw 'A operação não retornou um resultado.' }
            $result = $output[-1]
            if ($worker.Kind -eq 'Scan') { Update-GoatUiScan -Result $result }
            elseif ($worker.Kind -eq 'Integration') {
                $message = [string]$result.Message
                if ($result.LogPath) { $message += '  Log: ' + [string]$result.LogPath }
                $ui.Controls.CatalogOperationStatus.Text = $message
                Set-GoatUiStatus -Text $message -ErrorState (-not $result.Success)
                $ui.Controls.ScannerBadge.Text = $(if ($result.Success) { '●  OPERAÇÃO CONCLUÍDA' } else { '●  VERIFICAR OPERAÇÃO' })
                if ($result.Success -and $result.LocalPath -and -not $ui.Demo) {
                    $ui.LastExternalPath = [string]$result.LocalPath
                    $ui.Controls.CatalogOpenFolderButton.Visibility = 'Visible'
                }
            }
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
            if ($worker.Kind -eq 'Integration') { $ui.Controls.CatalogOperationStatus.Text = 'A operação não foi concluída: ' + $_.Exception.Message }
        } finally {
            $worker.PowerShell.Dispose()
            if (-not $ui.Worker) { Update-GoatUiTweaks }
            Update-GoatUiCatalogActions
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
        Repositories = @{}; CurrentRepository = $null; CatalogItem = $null; PrimaryItem = $null; CatalogRefreshing = $false; LastExternalPath = $null
        VisibleRecommendations = @()
    }
    $ui = $script:GoatUi
    if ($script:GoatLogoBase64) {
        try {
            $logoStream = New-Object System.IO.MemoryStream (,[Convert]::FromBase64String($script:GoatLogoBase64))
            $logoImage = New-Object System.Windows.Media.Imaging.BitmapImage
            $logoImage.BeginInit()
            $logoImage.CacheOption = 'OnLoad'
            $logoImage.DecodePixelWidth = 160
            $logoImage.StreamSource = $logoStream
            $logoImage.EndInit()
            $logoImage.Freeze()
            $logoStream.Dispose()
            $controls.GoatLogo.Source = $logoImage
        } catch { Set-GoatUiStatus -Text 'O logotipo não pôde ser carregado nesta distribuição.' -ErrorState $true }
    }
    if (Get-Command Get-GoatRepositoryCatalog -ErrorAction SilentlyContinue) {
        try {
            $catalog = Get-GoatRepositoryCatalog
            foreach ($repository in @($catalog.Repositories)) { $ui.Repositories[[string]$repository.Id] = $repository }
        } catch { Set-GoatUiStatus -Text ('Não foi possível carregar o catálogo: ' + $_.Exception.Message) -ErrorState $true }
    }
    $controls.PrivilegeText.Text = $(if ($ui.Admin) { 'Administrador · sessão local' } else { 'Leitura · sessão sem elevação' })
    if ($Demo) {
        $controls.DemoBadge.Visibility = 'Visible'
        $controls.LiveBadge.Text = '●  SIMULAÇÃO'
        $controls.HardwareFootnote.Text = 'Dados demonstrativos. Este gráfico não representa as medições deste PC.'
        $controls.FooterIdentity.Text = 'GOAT TWEAKS 2.3   /   DEMONSTRAÇÃO SEM ALTERAÇÕES'
        # Demo includes a clearly marked synthetic history; real mode only uses
        # samples actually returned after the monitor starts.
        $demoNow=Get-Date
        for ($age=60; $age -ge 2; $age-=2) {
            $tick=-$age
            $ui.Samples += [pscustomobject]@{Timestamp=$demoNow.AddSeconds(-$age);CPU=(24+12*[Math]::Sin($tick/7));GPU=(39+16*[Math]::Sin($tick/9));RAM=(42+3*[Math]::Sin($tick/15))}
        }
    }
    $navMap = @{ NavHome = 'Home'; NavGame = 'Game'; NavCPU = 'CPU'; NavGPU = 'GPU'; NavRAM = 'RAM'; NavBIOS = 'BIOS'; NavNetwork = 'Network'; NavSystem = 'System'; NavDrivers = 'Drivers'; NavWinutil = 'Winutil'; NavWinSux = 'WinSux'; NavUltimate = 'Ultimate'; NavRyTuneX = 'RyTuneX' }
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
    $controls.CatalogSearchBox.Add_TextChanged({ Update-GoatUiCatalogFilter })
    $controls.CatalogGroupFilter.Add_SelectionChanged({ Update-GoatUiCatalogFilter })
    $controls.CatalogKindFilter.Add_SelectionChanged({ Update-GoatUiCatalogFilter })
    $controls.CatalogGrid.Add_SelectionChanged({ Update-GoatUiCatalogDetails })
    $controls.CatalogGrid.Add_SizeChanged({ Update-GoatUiCatalogColumns })
    $controls.CatalogViewSourceButton.Add_Click({ Open-GoatUiSourceUrl -Url ([string]$script:GoatUi.CatalogItem.SourceUrl) })
    $controls.CatalogRepositoryButton.Add_Click({ Open-GoatUiSourceUrl -Url ([string]$script:GoatUi.CurrentRepository.RepositoryUrl) })
    $controls.CatalogLicenseButton.Add_Click({ Open-GoatUiSourceUrl -Url ([string]$script:GoatUi.CurrentRepository.LicenseUrl) })
    $controls.CatalogDownloadButton.Add_Click({ Invoke-GoatUiExternalAction -Action Download -Item $script:GoatUi.CatalogItem })
    $controls.CatalogRunButton.Add_Click({ Invoke-GoatUiExternalAction -Action Run -Item $script:GoatUi.CatalogItem })
    $controls.CatalogPrimaryButton.Add_Click({
        if ($script:GoatUi.PrimaryItem) { Invoke-GoatUiExternalAction -Action Run -Item $script:GoatUi.PrimaryItem }
        else { Open-GoatUiSourceUrl -Url ([string]$script:GoatUi.CurrentRepository.RepositoryUrl) }
    })
    $controls.CatalogOpenFolderButton.Add_Click({
        if ($script:GoatUi.LastExternalPath) {
            try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('/select,"{0}"' -f $script:GoatUi.LastExternalPath) -ErrorAction Stop | Out-Null }
            catch { Set-GoatUiStatus -Text ('Não foi possível abrir a pasta: ' + $_.Exception.Message) -ErrorState $true }
        }
    })
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
        $title = New-GoatUiText -Text ($tool[0] + ' ↗') -Color '#E4B95B' -Size 12
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
