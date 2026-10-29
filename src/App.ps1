function Set-GoatStatus {
    param([string]$Text,[switch]$ErrorState)
    $script:GoatApp.Controls.StatusText.Text=$Text
    $script:GoatApp.Controls.StatusText.Foreground=if($ErrorState){[Windows.Media.Brushes]::Salmon}else{[Windows.Media.BrushConverter]::new().ConvertFromString('#CFBB8F')}
}
function Invoke-GoatUiCommand {
    param([scriptblock]$Action)
    try { & $Action } catch { Set-GoatStatus -Text $_.Exception.Message -ErrorState }
}
function Confirm-GoatUi {
    param([string]$Message)
    if($script:GoatApp.Session.Demo -and $script:GoatUiAutoConfirm){return $true}
    return [Windows.MessageBox]::Show($script:GoatApp.Window,$Message,'GOAT Tweaks — revisão','YesNo','Question') -eq 'Yes'
}
function Assert-GoatOpenSession {
    if($script:GoatApp.Session.State -ne 'Open'){throw 'Esta sessão foi finalizada. Abra uma nova sessão para continuar.'}
    if($script:GoatApp.Worker){throw 'Aguarde a análise atual.'}
    if([string]$script:GoatApp.Controls.ServiceModeBox.SelectedItem -cne [string]$script:GoatApp.Session.Mode){throw 'Salve o contexto local/remoto do atendimento antes de continuar.'}
}
function Get-GoatUiInventoryContext {
    $a=$script:GoatApp;$inventory=$a.Session.Inventory
    if($a.Session.Mode -eq 'Remoto'){
        $inventory=if($inventory){$inventory|Select-Object *}else{[pscustomobject]@{Demo=[bool]$a.Session.Demo}}
        $inventory|Add-Member RemoteContext ([pscustomobject]@{IsRemote=$true;RemoteProcessNames=@()}) -Force
    }
    $inventory
}
function Reset-GoatUiReview {
    $a=$script:GoatApp;$c=$a.Controls
    $a.ResettingReview=$true
    try {
    $a.Preview=@();$a.PowerPreview=$null;$a.PowerPlans=$null
    $c.ActionConsent.IsChecked=$false;$c.PowerConsent.IsChecked=$false;$c.ManualDoneCheck.IsChecked=$false
    $c.LocalOperatorCheck.IsChecked=$false;$c.RecoveryPlanCheck.IsChecked=$false
    $c.ApplyButton.IsEnabled=$false;$c.PowerApplyButton.IsEnabled=$false
    $c.PowerPlanBox.ItemsSource=[object[]]@();$c.ActionDetail.Text='Gere uma nova prévia para esta sessão e contexto.';$c.PowerDetail.Text='Gere uma nova prévia para esta sessão e contexto.'
    Update-GoatAdvancedView -Rebuild
    }finally{$a.ResettingReview=$false}
}
function Get-GoatDisplayJson {
    param($Value)
    if($null -eq $Value){return 'Indisponível / não medido.'}
    return $Value | ConvertTo-Json -Depth 32
}
function Open-GoatOfficialLink {
    param([string]$Url)
    $uri=$null
    if(-not [uri]::TryCreate($Url,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https' -or $uri.UserInfo -or $uri.Port -ne 443){throw 'Somente páginas HTTPS oficiais permitidas.'}
    $hosts=@('nvidia.com','amd.com','intel.com','microsoft.com','steampowered.com','discord.com','obsproject.com','wagnardsoft.com','dell.com','hp.com','lenovo.com','asus.com','acer.com','msi.com')
    $valid=$false
    foreach($hostName in $hosts){if($uri.DnsSafeHost -eq $hostName -or $uri.DnsSafeHost.EndsWith('.'+$hostName)){$valid=$true}}
    if(-not $valid){throw 'Domínio não incluído nas fontes oficiais deste aplicativo.'}
    Start-Process -FilePath $uri.AbsoluteUri -ErrorAction Stop | Out-Null
}
function Update-GoatSessionView {
    param([switch]$SyncContext)
    $a=$script:GoatApp;$s=$a.Session;$c=$a.Controls
    $c.SessionLabel.Text=('Sessão {0} · {1} · {2} · {3}' -f $s.Id.Substring(0,8),$s.Objective,$s.Mode,$s.State)
    $c.ModeLabel.Text=if($s.Demo){$script:GoatVersion+' · DEMO / EXEMPLOS'}else{$script:GoatVersion+' · EDIÇÃO OFICIAL'}
    $c.SessionDetails.Text=('ID: {0}{1}Armazenamento privado: {2}{1}Criada: {3}{1}Estado: {4}' -f $s.Id,[Environment]::NewLine,$s.Root,$s.CreatedUtc,$s.State)
    if($SyncContext){$c.ObjectiveBox.SelectedItem=$s.Objective;$c.ServiceModeBox.SelectedItem=$s.Mode;$c.ConsentBox.IsChecked=$s.Consent}
    $c.ApplyButton.IsEnabled=($s.State -eq 'Open' -and -not $a.Worker -and [bool]$c.ActionConsent.IsChecked -and $a.Preview.Count -gt 0 -and @($a.Preview|Where-Object {-not $_.ExecutionAllowed}).Count -eq 0)
    $c.ApplyButton.Content=if($s.Demo){'Simular seleção (Demo)'}else{'Aplicar seleção revisada'}
    $c.PowerApplyButton.IsEnabled=($s.State -eq 'Open' -and -not $a.Worker -and $null -ne $a.PowerPreview -and $a.PowerPreview.ExecutionAllowed -and [bool]$c.PowerConsent.IsChecked)
    if($s.State -ne 'Open' -or $a.Worker){$c.ManualRecordButton.IsEnabled=$false}
    $c.FinishButton.IsEnabled=(-not $a.Worker)
    $c.CancelReadButton.Visibility=if($a.Worker){'Visible'}else{'Collapsed'}
    $c.ImportCaptureButton.IsEnabled=($s.State -eq 'Open' -and -not $a.Worker)
}
function Update-GoatCatalogView {
    $a=$script:GoatApp;$c=$a.Controls;$q=$c.CatalogSearch.Text.Trim();$category=[string]$c.CategoryBox.SelectedItem;$class=[string]$c.ClassBox.SelectedItem
    $items=@($a.Catalog | Where-Object {
        (-not $q -or ([string]$_.title+' '+$_.id+' '+$_.short_explanation).IndexOf($q,[StringComparison]::OrdinalIgnoreCase) -ge 0) -and
        ($category -eq 'Todas as categorias' -or -not $category -or $_.category -eq $category) -and
        ($class -eq 'Todas as classes' -or -not $class -or $_.execution_class -eq $class)
    })
    $c.CatalogGrid.ItemsSource=[object[]]$items
    $c.CatalogCount.Text=('{0} de {1} registros · cada item informa ajuste nativo, procedimento assistido ou referência' -f $items.Count,$a.Catalog.Count)
}
function Update-GoatDocumentsView {
    $a=$script:GoatApp;$q=$a.Controls.DocumentSearch.Text.Trim()
    $items=@($a.Documents | Where-Object { -not $q -or ([string]$_.path+' '+$_.content).IndexOf($q,[StringComparison]::OrdinalIgnoreCase) -ge 0 })
    $a.Controls.DocumentsList.ItemsSource=[object[]]$items
}
function Update-GoatHistoryView {
    $a=$script:GoatApp;$transactions=@(Get-GoatTransactions $a.Session)
    $a.Controls.TransactionBox.ItemsSource=[object[]]$transactions
    if($transactions.Count){$a.Controls.TransactionBox.SelectedIndex=$transactions.Count-1}
    $a.Controls.HistoryDetail.Text=Format-GoatHistoryView -Session $a.Session -Transactions $transactions
    $a.Controls.HistoryDetail.Text+="`r`n`r`nENERGIA`r`n"+(Get-GoatDisplayJson @(Get-GoatPowerTransactions $a.Session))+"`r`n`r`nETAPAS MANUAIS (relatadas; sem verificação automática)`r`n"+(Get-GoatDisplayJson @($a.Session.ManualRecords))
}
function Update-GoatPowerView {
    param([switch]$Refresh)
    $a=$script:GoatApp;$c=$a.Controls
    if($Refresh -or -not $a.PowerPlans){
        $selectedGuid=[string]$c.PowerPlanBox.SelectedItem.Guid;$a.PowerPlans=Get-GoatPowerPlans -Demo:$a.Session.Demo;$c.PowerPlanBox.ItemsSource=[object[]]@($a.PowerPlans.Plans);$a.PowerPreview=$null;$c.PowerConsent.IsChecked=$false
        $selected=@($a.PowerPlans.Plans|Where-Object Guid -eq $selectedGuid);if(-not $selected.Count){$selected=@($a.PowerPlans.Plans|Where-Object IsActive)};if($selected.Count){$c.PowerPlanBox.SelectedItem=$selected[0]}
    }
    if(-not $c.PowerPlanBox.SelectedItem){$chosen=@($a.PowerPlans.Plans|Where-Object IsActive);if($chosen.Count){$c.PowerPlanBox.SelectedItem=$chosen[0]}}
    $active=@($a.PowerPlans.Plans|Where-Object IsActive);$activeName=if($active.Count){[string]$active[0].Name}else{'indisponível'}
    $c.PowerCurrentText.Text='Plano ativo: '+$activeName+' · '+[string]$a.PowerPlans.ActiveSchemeGuid+' · '+$a.PowerPlans.Status+' · '+(@($a.PowerPlans.Errors) -join '; ')
    $c.PowerApplyButton.IsEnabled=($a.Session.State -eq 'Open' -and -not $a.Worker -and $null -ne $a.PowerPreview -and $a.PowerPreview.ExecutionAllowed -and [bool]$c.PowerConsent.IsChecked)
    $c.PowerApplyButton.Content=if($a.Session.Demo){'Simular troca (Demo)'}else{'Aplicar plano revisado'}
    $transactions=@(Get-GoatPowerTransactions $a.Session)
    $c.PowerTransactionBox.ItemsSource=[object[]]$transactions
    if($transactions.Count){$c.PowerTransactionBox.SelectedIndex=$transactions.Count-1}
    $c.PowerHistoryDetail.Text=Get-GoatDisplayJson $transactions
}
function Update-GoatAdvancedView {
    param([switch]$Rebuild)
    $a=$script:GoatApp;$c=$a.Controls;$id=[string]$c.AdvancedList.SelectedItem.Id
    if($Rebuild){
        $inventory=Get-GoatUiInventoryContext
        $a.Guides=@(Get-GoatAdvancedGuides -Catalog $a.SourceCatalog -Inventory $inventory -LocalOperatorConfirmed:([bool]$c.LocalOperatorCheck.IsChecked) -RecoveryPlanConfirmed:([bool]$c.RecoveryPlanCheck.IsChecked))
        $a.Catalog=@(Get-GoatRuntimeCatalog -Catalog $a.SourceCatalog -Inventory $inventory)
        $c.AdvancedList.ItemsSource=[object[]]$a.Guides
        $found=@($a.Guides|Where-Object Id -eq $id);if($found.Count){$c.AdvancedList.SelectedItem=$found[0]}
    }
    $guide=$c.AdvancedList.SelectedItem
    $c.AdvancedDetail.Text=Format-GoatAdvancedGuide $guide
    $c.AdvancedSettingsButton.IsEnabled=($null -ne $guide -and $guide.CanOpenSettings)
    $c.AdvancedSourceButton.IsEnabled=($null -ne $guide -and @($guide.Sources|Where-Object {Test-GoatAdvancedSourceUrl $_}).Count -gt 0)
    $c.ManualRecordButton.IsEnabled=($a.Session.State -eq 'Open' -and -not $a.Worker -and $null -ne $guide -and $guide.Status -eq 'MANUAL_GUIDE' -and $guide.Prerequisites.MaintenanceReady -and [bool]$c.ManualDoneCheck.IsChecked)
}
function Open-GoatCatalogResource {
    $a=$script:GoatApp;$item=$a.Controls.CatalogGrid.SelectedItem;if(-not $item){throw 'Selecione um item do catálogo.'}
    switch($item.RuntimeTarget){
        'Native' {$a.Controls.Navigation.SelectedItem='Windows / preferências';$a.Controls.ActionsList.SelectedItems.Clear();foreach($action in $a.Controls.ActionsList.Items){if(@($item.RuntimeActionIds) -contains $action.Id){[void]$a.Controls.ActionsList.SelectedItems.Add($action)}}}
        'Power' {$a.Controls.Navigation.SelectedItem='Energia'}
        'Advanced' {$a.Controls.Navigation.SelectedItem='Procedimentos avançados';$guide=@($a.Guides|Where-Object Id -eq $item.id);if($guide.Count){$a.Controls.AdvancedList.SelectedItem=$guide[0]}}
        default {throw 'Este item tem documentação consultiva. Consulte a fonte indicada no detalhe.'}
    }
}
function Update-GoatInventoryView {
    $a=$script:GoatApp;$c=$a.Controls;$i=$a.Session.Inventory
    if(-not $i){Reset-GoatUiReview;return}
    Update-GoatAdvancedView -Rebuild
    $a.PowerPlans=$i.PowerPlans;$a.PowerPreview=$null;$a.Preview=@();$c.PowerConsent.IsChecked=$false;$c.ActionConsent.IsChecked=$false
    $c.PowerPlanBox.ItemsSource=[object[]]@($a.PowerPlans.Plans)
    $c.CpuSummary.Text=if([string]::IsNullOrWhiteSpace([string]$i.CPU.Name)){'Indisponível nesta leitura'}else{[string]$i.CPU.Name}
    $c.GpuSummary.Text=(@($i.GpuCenter.Devices | ForEach-Object { $_.Name+' · '+$(if($_.DriverVersion){$_.DriverVersion}else{'driver indisponível'}) }) -join "`n")
    if(-not $c.GpuSummary.Text){$c.GpuSummary.Text='Indisponível'}
    $c.MemorySummary.Text=if($null -ne $i.Memory.TotalBytes){('{0:N1} GB' -f ($i.Memory.TotalBytes/1GB))+' · '+$(if($null -ne $i.Memory.UsedPercent){[string]$i.Memory.UsedPercent+' % em uso'}else{'utilização indisponível'})}else{'Indisponível'}
    $c.OsSummary.Text=if($i.OS.Name){[string]$i.OS.Name+' · build '+$(if($i.OS.Build){[string]$i.OS.Build}else{'indisponível'})}else{'Windows: leitura indisponível'}
    $c.GpuDetail.Text=Format-GoatGpuView $i.GpuCenter
    $c.OemLinkButton.IsEnabled=(-not [string]::IsNullOrWhiteSpace([string]$i.GpuCenter.System.OemDriverSource))
    $c.ProfileGpuBox.ItemsSource=[string[]](@('Não confirmada')+@($i.GpuCenter.Devices | ForEach-Object Name));$c.ProfileGpuBox.SelectedIndex=0
    $c.DiagnosisPanel.Children.Clear()
    foreach($finding in @(Get-GoatDiagnosis -Inventory $i -Objective $a.Session.Objective)){
        $card=[Windows.Controls.Border]::new();$card.Style=$a.Window.FindResource('Card')
        $stack=[Windows.Controls.StackPanel]::new()
        $title=[Windows.Controls.TextBlock]::new();$title.Text=$finding.Title;$title.FontSize=15;$title.FontWeight='SemiBold';$stack.Children.Add($title)|Out-Null
        $body=[Windows.Controls.TextBlock]::new();$body.Text=($finding.Reason+"`n"+$finding.Recommendation+"`nConfiança: "+$finding.Confidence+' · desempenho: não medido');$body.Margin='0,10,0,0';$body.Foreground=[Windows.Media.Brushes]::LightGray;$stack.Children.Add($body)|Out-Null
        $card.Child=$stack;$c.DiagnosisPanel.Children.Add($card)|Out-Null
    }
}
function Start-GoatInventoryWorker {
    $a=$script:GoatApp
    if($a.Worker){return}
    if($a.Session.State -ne 'Open'){Set-GoatStatus 'Abra nova sessão para analisar novamente.';return}
    $source='param([bool]$demo)' + "`r`n" + $script:GoatSources.Gpu + "`r`n" + $script:GoatSources.Inventory + "`r`n"+$script:GoatSources.Power+"`r`n"+'$inventory=Get-GoatCompleteInventory -Demo:$demo; try{$plans=Get-GoatPowerPlans -Demo:$demo}catch{$plans=[pscustomobject]@{Status="UNAVAILABLE";Plans=@();Reason=$_.Exception.Message}}; $inventory|Add-Member PowerPlans $plans -Force -PassThru'
    $ps=[PowerShell]::Create();[void]$ps.AddScript($source);[void]$ps.AddArgument([bool]$a.Session.Demo)
    try{$a.Worker=@{PS=$ps;Handle=$ps.BeginInvoke();Kind='Inventory';Started=[DateTime]::UtcNow;CancelRequested=$false;StopHandle=$null};$a.Controls.RefreshButton.IsEnabled=$false;Update-GoatSessionView;Set-GoatStatus 'Consultando hardware em segundo plano…'}
    catch{$ps.Dispose();throw}
}
function Start-GoatFrameImportWorker {
    param([string]$Path,[hashtable]$Conditions,[string]$ConditionLabel,[int]$PassNumber)
    Assert-GoatOpenSession
    $a=$script:GoatApp;$folder=Join-Path $a.Session.Root 'captures';[void][IO.Directory]::CreateDirectory($folder)
    $snapshot=Join-Path $folder ([guid]::NewGuid().ToString('N')+'.csv')
    $source='param($capturePath,$captureConditions,$captureLabel,$capturePass,$snapshotPath)'+"`r`n"+$script:GoatSources.Benchmark+"`r`n"+'Import-GoatFrameCapture -Path $capturePath -Conditions $captureConditions -ConditionLabel $captureLabel -PassNumber $capturePass -SnapshotPath $snapshotPath'
    $ps=[PowerShell]::Create();[void]$ps.AddScript($source)
    foreach($argument in @($Path,$Conditions,$ConditionLabel,$PassNumber,$snapshot)){[void]$ps.AddArgument($argument)}
    try{$a.Worker=@{PS=$ps;Handle=$ps.BeginInvoke();Kind='FrameCapture';Started=[DateTime]::UtcNow;CancelRequested=$false;StopHandle=$null};$a.Controls.RefreshButton.IsEnabled=$false;Update-GoatSessionView;Set-GoatStatus 'Importando e verificando captura em segundo plano…'}catch{$ps.Dispose();throw}
}
function Stop-GoatInventoryWorker {
    $a=$script:GoatApp;$w=$a.Worker
    if(-not $w -or $w.CancelRequested){return}
    $w.CancelRequested=$true
    $w.StopHandle=$w.PS.BeginStop($null,$null)
    Set-GoatStatus 'Cancelando a leitura. Os dados já salvos serão preservados.'
}
function Complete-GoatInventoryWorker {
    $a=$script:GoatApp;$w=$a.Worker
    if(-not $w){return}
    if(-not $w.Handle.IsCompleted){
        if(([DateTime]::UtcNow-$w.Started).TotalSeconds -gt 90 -and -not $w.CancelRequested){Stop-GoatInventoryWorker}
        return
    }
    try{
        $result=@($w.PS.EndInvoke($w.Handle))
        if($w.CancelRequested){Set-GoatStatus 'Leitura cancelada; nenhum ajuste foi aplicado.';return}
        if($w.PS.HadErrors){throw ($w.PS.Streams.Error | Out-String)}
        if($result.Count -ne 1){throw 'A tarefa retornou resultado inesperado.'}
        if($w.Kind -eq 'FrameCapture'){
            $a.Session.Benchmarks+=$result[0];$a.Session.Comparison=$null;Save-GoatSession $a.Session
            $a.Controls.BenchmarkDetail.Text=Format-GoatBenchmarkView -Captures @($a.Session.Benchmarks)
            Set-GoatStatus 'Captura importada com hash e dados originais preservados.'
        }else{
            $a.Session.Inventory=$result[0];Save-GoatSession $a.Session;Update-GoatInventoryView
            Set-GoatStatus 'Inventário concluído. Fontes sem leitura aparecem como indisponíveis; FPS e input lag não medidos.'
        }
    }catch{if($w.CancelRequested){Set-GoatStatus 'Leitura cancelada; nenhum ajuste foi aplicado.'}else{Set-GoatStatus $_.Exception.Message -ErrorState}}
    finally{$w.PS.Dispose();$a.Worker=$null;$a.Controls.RefreshButton.IsEnabled=$true;Update-GoatSessionView;Set-GoatPage $a.Page}
}
function Set-GoatPage {
    param([string]$Page)
    $a=$script:GoatApp;$c=$a.Controls;$a.Page=$Page;$c.PageTitle.Text=$Page
    foreach($name in @('Overview','Service','Catalog','Gpu','Profiles','Actions','Advanced','Power','Benchmarks','History','Documents','Detail')){$c[$name+'Page'].Visibility='Collapsed'}
    $map=@{'Visão geral'='Overview';'Atendimento'='Service';'Catálogo completo'='Catalog';'GPU CENTER'='Gpu';'Jogos / perfis'='Profiles';'Windows / preferências'='Actions';'Procedimentos avançados'='Advanced';'Energia'='Power';'Benchmarks'='Benchmarks';'Histórico / reversão'='History';'Documentação'='Documents'}
    if($map.ContainsKey($Page)){$c[$map[$Page]+'Page'].Visibility='Visible'}else{$c.DetailPage.Visibility='Visible'}
    $i=$a.Session.Inventory
    switch($Page){
        'Catálogo completo' {Update-GoatCatalogView}
        'Documentação' {Update-GoatDocumentsView}
        'Histórico / reversão' {Update-GoatHistoryView}
        'Energia' {Update-GoatPowerView}
        'Procedimentos avançados' {Update-GoatAdvancedView}
        'CPU / RAM' {$c.DetailIntro.Text='Topologia, memória e amostra de uso. Afinidade, prioridade e firmware exigem diagnóstico específico.';$c.DetailText.Text=Format-GoatHardwareView -Title 'CPU / RAM' -Value ([pscustomobject]@{CPU=$i.CPU;Memory=$i.Memory;Telemetry=$i.Telemetry})}
        'Rede / latência' {$c.DetailIntro.Text='RTT, jitter e perda são métricas de rede; não são FPS nem input lag. Nenhum adaptador é reconfigurado.';$c.DetailText.Text=Format-GoatHardwareView -Title 'Adaptadores de rede' -Value $i.Network}
        'Armazenamento' {$c.DetailIntro.Text='Saúde reportada pelo provedor, espaço e discos. Ausência de SMART é desconhecido. Nenhum benchmark de escrita automático.';$c.DetailText.Text=Format-GoatHardwareView -Title 'Armazenamento' -Value ([pscustomobject]@{Disks=$i.Disks;PhysicalDisks=$i.PhysicalDisks;StorageReliability=$i.StorageReliability})}
        'Inicialização / apps' {$c.DetailIntro.Text='Inventário somente leitura. Nenhum programa é encerrado e nenhuma entrada Run/RunOnce é apagada.';$c.DetailText.Text=Format-GoatHardwareView -Title 'Inicialização e aplicativos' -Value ([pscustomobject]@{Startup=$i.Startup;Apps=$i.Apps})}
        'Steam / Discord / OBS' {$c.DetailIntro.Text='Guias assistidos: confirme versão, preserve captura e compare uma variável. Siga as etapas do aplicativo e registre o resultado.';$docs=@($a.Documents|Where-Object {$_.path -match '03_GUIAS_MANUAIS|04_STEAM_DISCORD'});$c.DetailText.Text=((Format-GoatHardwareView -Title 'Aplicativos detectados' -Value $i.Apps)+"`r`n`r`n"+(@($docs|ForEach-Object content) -join "`r`n`r`n"))}
        'Relatórios' {$c.DetailIntro.Text='Exportação HTML/JSON/CSV com dados pessoais minimizados e pacote privado de reversão. O botão Exportar permite escolher o destino.';$c.DetailText.Text=Get-GoatDisplayJson (Get-GoatPublicReport $a.Session)}
        'Laboratório / bloqueios' {$c.DetailIntro.Text='Os procedimentos de segurança, firmware, OC e driver estão em Procedimentos avançados. Controles privados ou dependentes de modelo mostram os requisitos que faltam. Esta lista preserva a classificação original do pacote.';$c.DetailText.Text=Get-GoatDisplayJson @($a.SourceCatalog|Where-Object execution_class -in @('X_BLOCKED','D_LAB_ONLY')|Select-Object id,title,execution_class,risk,when_not_to_use)}
    }
}
function Select-GoatFile {
    param([string]$Filter='Todos os arquivos|*.*')
    $dialog=[Microsoft.Win32.OpenFileDialog]::new();$dialog.Filter=$Filter
    if($dialog.ShowDialog($script:GoatApp.Window)){return $dialog.FileName}
}
function Select-GoatExportDirectory {
    $dialog=[Windows.Forms.FolderBrowserDialog]::new();$dialog.Description='Escolha a pasta para relatório e pacote privado de reversão'
    try{if($dialog.ShowDialog() -eq [Windows.Forms.DialogResult]::OK){return $dialog.SelectedPath}}finally{$dialog.Dispose()}
}
function New-GoatProfileFromUi {
    $a=$script:GoatApp;$c=$a.Controls;$gpuId=$null
    $selected=[string]$c.ProfileGpuBox.SelectedItem
    $gpu=@($a.Session.Inventory.GpuCenter.Devices|Where-Object Name -eq $selected)
    if($gpu.Count -eq 1){$gpuId=$gpu[0].PnpDeviceId}
    New-GoatGpuGameProfile -GameId $c.GameIdBox.Text -GameName $c.GameNameBox.Text -ExecutablePath $c.GamePathBox.Text -AuthorizedPath:([bool]$c.GamePathConsent.IsChecked) -GpuPnpId $gpuId -Goal ([string]$c.ProfileGoalBox.SelectedItem) -Resolution $c.ResolutionBox.Text -RefreshRateHz ([double]$c.HzBox.Text) -Reflex ([string]$c.ReflexBox.SelectedItem) -Vrr ([string]$c.VrrBox.SelectedItem) -VSync ([string]$c.VSyncBox.SelectedItem) -FpsCap ([double]$c.FpsBox.Text) -CaptureRequired:([bool]$c.CaptureBox.IsChecked)
}
function Show-GoatApp {
    param([switch]$Demo,[string]$DataRoot,[string]$SessionPath)
    Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms
    $window=[Windows.Markup.XamlReader]::Parse($script:GoatXaml)
    $logoStream=[IO.MemoryStream]::new([Convert]::FromBase64String($script:GoatLogoBase64))
    try {
        $logo=[Windows.Media.Imaging.BitmapImage]::new();$logo.BeginInit()
        $logo.CacheOption=[Windows.Media.Imaging.BitmapCacheOption]::OnLoad;$logo.StreamSource=$logoStream
        $logo.EndInit();$logo.Freeze()
    }finally{$logoStream.Dispose()}
    $window.FindName('AppLogo').Source=$logo;$window.Icon=$logo
    $window.Title='GOAT Tweaks '+$script:GoatVersion+' · GPU Center'
    $area=[Windows.SystemParameters]::WorkArea
    if($area.Width -gt 0){$window.MinWidth=[Math]::Min($window.MinWidth,$area.Width);$window.Width=[Math]::Min($window.Width,$area.Width);$window.MaxWidth=$area.Width}
    if($area.Height -gt 0){$window.MinHeight=[Math]::Min($window.MinHeight,$area.Height);$window.Height=[Math]::Min($window.Height,$area.Height);$window.MaxHeight=$area.Height}
    $controls=@{}
    foreach($match in [regex]::Matches($script:GoatXaml,'x:Name="([^"]+)"')){$controls[$match.Groups[1].Value]=$window.FindName($match.Groups[1].Value)}
    $session=$null
    if($SessionPath){
        $session=Import-GoatSession -Path $SessionPath -Demo:$Demo
    }else{$session=New-GoatSession -Demo:$Demo -Root $DataRoot}
    $sourceCatalog=@(($script:GoatCatalogJson|ConvertFrom-Json).controls)
    $script:GoatApp=@{Window=$window;Controls=$controls;Session=$session;Worker=$null;Page='Visão geral';DataRoot=$DataRoot;SourceCatalog=$sourceCatalog;Catalog=@(Get-GoatRuntimeCatalog -Catalog $sourceCatalog);Guides=@(Get-GoatAdvancedGuides -Catalog $sourceCatalog);Documents=@(($script:GoatDocumentsJson|ConvertFrom-Json).documents);Preview=@();PowerPreview=$null;LastExport=$null}
    $a=$script:GoatApp;$c=$controls
    $accessible=@{Navigation='Seções do GOAT Tweaks';CatalogSearch='Buscar configurações no catálogo';CategoryBox='Categoria';ClassBox='Classe de execução';DocumentSearch='Buscar documentação';GameIdBox='Identificador do jogo';GameNameBox='Nome do jogo';GamePathBox='Caminho autorizado do executável';ProfileGoalBox='Objetivo do perfil';ProfileGpuBox='GPU confirmada para o jogo';ResolutionBox='Resolução confirmada';HzBox='Taxa de atualização em Hz';FpsBox='Limite FPS confirmado';ReflexBox='Estado de Reflex';VrrBox='Estado de VRR';VSyncBox='Estado de V-Sync';ConditionsBox='Condições das capturas, em JSON';ConditionLabelBox='Condição antes ou depois';ObjectiveBox='Objetivo do atendimento';ServiceModeBox='Atendimento local ou remoto';GpuVendorBox='Fabricante da GPU';TransactionBox='Transação para restaurar';DirectionBox='Direção da preferência'}
    foreach($name in $accessible.Keys){[Windows.Automation.AutomationProperties]::SetName($c[$name],$accessible[$name])}
    $pages=@('Visão geral','Atendimento','Catálogo completo','Windows / preferências','Energia','Procedimentos avançados','CPU / RAM','GPU CENTER','Jogos / perfis','Steam / Discord / OBS','Rede / latência','Armazenamento','Inicialização / apps','Benchmarks','Histórico / reversão','Relatórios','Documentação','Laboratório / bloqueios')
    $c.Navigation.ItemsSource=[string[]]$pages
    $c.ObjectiveBox.ItemsSource=[string[]]@('Equilibrado','Competitivo','Qualidade');$c.ServiceModeBox.ItemsSource=[string[]]@('Local','Remoto')
    $c.CategoryBox.ItemsSource=[string[]](@('Todas as categorias')+@($a.Catalog|ForEach-Object category|Sort-Object -Unique));$c.CategoryBox.SelectedIndex=0
    $c.ClassBox.ItemsSource=[string[]]@('Todas as classes','A_AUTO_SAFE','B_APPROVAL','C_MANUAL','D_LAB_ONLY','X_BLOCKED');$c.ClassBox.SelectedIndex=0
    $c.GpuVendorBox.ItemsSource=[string[]]@('NVIDIA','AMD','Intel','Desconhecido');$c.GpuVendorBox.SelectedIndex=0
    $c.ProfileGoalBox.ItemsSource=[string[]]@('Competitivo','Equilibrado','Qualidade / Captura');$c.ProfileGoalBox.SelectedIndex=1
    foreach($name in @('ReflexBox','VrrBox','VSyncBox')){$c[$name].ItemsSource=[string[]]@('Unknown','Enabled','Disabled');$c[$name].SelectedIndex=0}
    $c.ActionsList.ItemsSource=[object[]]@(Get-GoatActions);$c.DirectionBox.ItemsSource=[string[]]@('On','Off');$c.DirectionBox.SelectedIndex=0
    $c.ConditionLabelBox.ItemsSource=[string[]]@('Baseline','After');$c.ConditionLabelBox.SelectedIndex=0
    $c.ConditionsBox.Text='{"Game":"","GameBuild":"","Scene":"","Resolution":"","Preset":"","Api":"","Driver":"","OsBuild":"","FrameCap":"","VSync":"","CaptureTool":"","CaptureVersion":""}'
    $c.Navigation.Add_SelectionChanged({Invoke-GoatUiCommand {Set-GoatPage ([string]$script:GoatApp.Controls.Navigation.SelectedItem)}})
    $c.RefreshButton.Add_Click({Invoke-GoatUiCommand {Start-GoatInventoryWorker}})
    $c.CancelReadButton.Add_Click({Invoke-GoatUiCommand {Stop-GoatInventoryWorker}})
    $c.SaveSessionButton.Add_Click({Invoke-GoatUiCommand {
        $a=$script:GoatApp;if($a.Session.State -ne 'Open' -or $a.Worker){throw 'Salve o contexto somente em sessão aberta, após a análise.'};$a.Session.Objective=[string]$a.Controls.ObjectiveBox.SelectedItem;$a.Session.Mode=[string]$a.Controls.ServiceModeBox.SelectedItem;$a.Session.Consent=[bool]$a.Controls.ConsentBox.IsChecked;Save-GoatSession $a.Session;Reset-GoatUiReview;Update-GoatSessionView;Update-GoatInventoryView;Set-GoatStatus 'Contexto salvo; revise o plano antes de qualquer ação.'
    }})
    $c.NewSessionButton.Add_Click({Invoke-GoatUiCommand {
        if($script:GoatApp.Worker){throw 'Aguarde o inventário.'}
        if(Confirm-GoatUi 'Abrir nova sessão? A sessão atual continuará salva para retomada.'){$a=$script:GoatApp;$a.Session=New-GoatSession -Demo:$a.Session.Demo -Root $a.DataRoot;Reset-GoatUiReview;Update-GoatSessionView -SyncContext;Start-GoatInventoryWorker}
    }})
    $c.ResumeButton.Add_Click({Invoke-GoatUiCommand {
        if($script:GoatApp.Worker){throw 'Aguarde o inventário.'}
        $path=Select-GoatFile 'Sessão GOAT|session.json';if(-not $path){return}
        $s=Import-GoatSession -Path $path -Demo:$script:GoatApp.Session.Demo
        $script:GoatApp.Session=$s;Reset-GoatUiReview;Update-GoatSessionView -SyncContext;Update-GoatInventoryView;Set-GoatPage 'Histórico / reversão';Set-GoatStatus 'Sessão recuperada; confira transações pendentes.'
    }})
    $c.CatalogSearch.Add_TextChanged({Update-GoatCatalogView});$c.CategoryBox.Add_SelectionChanged({Update-GoatCatalogView});$c.ClassBox.Add_SelectionChanged({Update-GoatCatalogView})
    $c.CatalogGrid.Add_SelectionChanged({$item=$script:GoatApp.Controls.CatalogGrid.SelectedItem;$script:GoatApp.Controls.CatalogOpenButton.IsEnabled=($null -ne $item -and $item.RuntimeTarget -ne 'Reference');if($item){$script:GoatApp.Controls.CatalogDetail.Text=Format-GoatCatalogView $item}})
    $c.CatalogOpenButton.Add_Click({Invoke-GoatUiCommand {Open-GoatCatalogResource}})
    $c.DocumentSearch.Add_TextChanged({Update-GoatDocumentsView})
    $c.DocumentsList.Add_SelectionChanged({$doc=$script:GoatApp.Controls.DocumentsList.SelectedItem;if($doc){$script:GoatApp.Controls.DocumentText.Text=('Fonte: '+$doc.path+"`r`nSHA256: "+$doc.sha256+"`r`nTipo: "+$doc.kind+"`r`nReferência documental histórica: os recursos e critérios atuais aparecem no catálogo e nas páginas de ajustes. O conteúdo abaixo não é executado.`r`n`r`n"+$doc.content)}})
    $c.DriverLinkButton.Add_Click({Invoke-GoatUiCommand {Open-GoatOfficialLink (Get-GoatGpuOfficialDriverSource ([string]$script:GoatApp.Controls.GpuVendorBox.SelectedItem))}})
    $c.OemLinkButton.Add_Click({Invoke-GoatUiCommand {Open-GoatOfficialLink ([string]$script:GoatApp.Session.Inventory.GpuCenter.System.OemDriverSource)}})
    $c.GpuGuideButton.Add_Click({Invoke-GoatUiCommand {
        $a=$script:GoatApp;$remote=$a.Session.Inventory.GpuCenter.RemoteContext
        if($a.Session.Mode -eq 'Remoto'){$remote=[pscustomobject]@{State='REMOTE_OR_POSSIBLE_REMOTE';IsRemoteOrUncertain=$true;Indicators=@('Atendimento remoto informado pelo técnico')}}
        $a.Controls.GpuDetail.Text=Format-GoatGpuGuides @(Get-GoatGpuGuides -Vendor ([string]$a.Controls.GpuVendorBox.SelectedItem) -RemoteContext $remote)
    }})
    $c.ProfilePreviewButton.Add_Click({Invoke-GoatUiCommand {$p=New-GoatProfileFromUi;$script:GoatApp.Controls.ProfileDetail.Text=Format-GoatProfileView (Get-GoatGpuProfileAdvice $p)}})
    $c.ProfileSaveButton.Add_Click({Invoke-GoatUiCommand {
        Assert-GoatOpenSession;$a=$script:GoatApp;$p=New-GoatProfileFromUi;$folder=Join-Path $a.Session.Root 'profiles';[void][IO.Directory]::CreateDirectory($folder)
        $result=Save-GoatGpuGameProfile $p (Join-Path $folder ($p.Id+'.goat-profile.json'));$a.Session.Profiles+= $p;Save-GoatSession $a.Session;$a.Controls.ProfileDetail.Text=Format-GoatProfileView (Get-GoatGpuProfileAdvice $p);Set-GoatStatus ('Perfil local salvo: '+$result.Path)
    }})
    $c.ProfileImportButton.Add_Click({Invoke-GoatUiCommand {Assert-GoatOpenSession;$path=Select-GoatFile 'Perfil GOAT|*.goat-profile.json';if($path){$p=Import-GoatGpuGameProfile $path;$script:GoatApp.Session.Profiles+=$p;Save-GoatSession $script:GoatApp.Session;$script:GoatApp.Controls.ProfileDetail.Text=Format-GoatProfileView (Get-GoatGpuProfileAdvice $p)}}})
    $c.PreviewButton.Add_Click({Invoke-GoatUiCommand {
        Assert-GoatOpenSession;$a=$script:GoatApp;$ids=@($a.Controls.ActionsList.SelectedItems|ForEach-Object Id);$a.Preview=@(Get-GoatActionPreview $a.Session $ids ([string]$a.Controls.DirectionBox.SelectedItem) -InspectOnly);$a.Controls.ActionConsent.IsChecked=$false;$a.Controls.ActionDetail.Text=Format-GoatActionPreview $a.Preview;Update-GoatSessionView
    }})
    $invalidatePreview={$a=$script:GoatApp;$a.Preview=@();$a.Controls.ActionConsent.IsChecked=$false;$a.Controls.ApplyButton.IsEnabled=$false}
    $c.ActionsList.Add_SelectionChanged($invalidatePreview);$c.DirectionBox.Add_SelectionChanged($invalidatePreview)
    $c.ActionConsent.Add_Checked({if(-not $script:GoatApp.ResettingReview){Update-GoatSessionView}});$c.ActionConsent.Add_Unchecked({if(-not $script:GoatApp.ResettingReview){Update-GoatSessionView}})
    $c.ApplyButton.Add_Click({Invoke-GoatUiCommand {
        Assert-GoatOpenSession;$a=$script:GoatApp;if(-not $a.Controls.ActionConsent.IsChecked){throw 'Revise a prévia e marque o consentimento.'}
        $ids=@($a.Controls.ActionsList.SelectedItems|ForEach-Object Id);if(-not $a.Preview.Count -or ($a.Preview.Id -join ',') -ne ($ids -join ',') -or @($a.Preview|Where-Object Direction -ne ([string]$a.Controls.DirectionBox.SelectedItem)).Count){throw 'Gere uma prévia para esta seleção e direção.'}
        $individual=@($a.Preview|Where-Object {$_.Action.RequiresIndividualApproval})
        $approved=@()
        foreach($item in $individual){if(-not (Confirm-GoatUi ($item.Action.Title+"`nRisco: "+$item.Action.Risk+"`n"+$item.Action.Tradeoffs+"`nConfirma esta mudança individual?"))){throw 'Ação individual cancelada.'};$approved+=$item.Id}
        $result=Invoke-GoatActionBatch $a.Session $ids ([string]$a.Controls.DirectionBox.SelectedItem) -Consent -ApprovedActionIds $approved -ReviewedPreview @($a.Preview);$a.Controls.ActionDetail.Text=Get-GoatDisplayJson $result;$a.Preview=@();Update-GoatSessionView;Set-GoatStatus $(if($result.Message){$result.Message}else{'Transação '+$result.State+'; revise o histórico e as informações de reinício.'})
    }})
    $c.AdvancedList.Add_SelectionChanged({$script:GoatApp.Controls.ManualDoneCheck.IsChecked=$false;Update-GoatAdvancedView})
    foreach($name in @('LocalOperatorCheck','RecoveryPlanCheck')){$c[$name].Add_Checked({if(-not $script:GoatApp.ResettingReview){Update-GoatAdvancedView -Rebuild}});$c[$name].Add_Unchecked({if(-not $script:GoatApp.ResettingReview){Update-GoatAdvancedView -Rebuild}})}
    $c.ManualDoneCheck.Add_Checked({Update-GoatAdvancedView});$c.ManualDoneCheck.Add_Unchecked({Update-GoatAdvancedView})
    $c.AdvancedSettingsButton.Add_Click({Invoke-GoatUiCommand {$guide=$script:GoatApp.Controls.AdvancedList.SelectedItem;if(-not $guide.CanOpenSettings){throw 'Página não disponível neste contexto.'};Open-GoatSettingsPage $guide.SettingsUri}})
    $c.AdvancedSourceButton.Add_Click({Invoke-GoatUiCommand {$guide=$script:GoatApp.Controls.AdvancedList.SelectedItem;$url=@($guide.Sources|Where-Object {Test-GoatAdvancedSourceUrl $_}|Select-Object -First 1);if(-not $url.Count){throw 'Fonte oficial não disponível.'};Open-GoatOfficialLink $url[0]}})
    $c.ManualRecordButton.Add_Click({Invoke-GoatUiCommand {Assert-GoatOpenSession;$a=$script:GoatApp;Add-GoatManualRecord $a.Session ([string]$a.Controls.AdvancedList.SelectedItem.Id) $a.Guides -Confirmed:([bool]$a.Controls.ManualDoneCheck.IsChecked)|Out-Null;$a.Controls.ManualDoneCheck.IsChecked=$false;Save-GoatSession $a.Session;Set-GoatStatus 'Etapa registrada como relato manual; sem verificação automática.'}})
    $c.PowerRefreshButton.Add_Click({Invoke-GoatUiCommand {Update-GoatPowerView -Refresh}})
    $c.PowerPlanBox.Add_SelectionChanged({$a=$script:GoatApp;$a.PowerPreview=$null;$a.Controls.PowerConsent.IsChecked=$false;$a.Controls.PowerApplyButton.IsEnabled=$false})
    $c.PowerPreviewButton.Add_Click({Invoke-GoatUiCommand {Assert-GoatOpenSession;$a=$script:GoatApp;$plan=$a.Controls.PowerPlanBox.SelectedItem;if(-not $plan){throw 'Selecione um plano existente.'};$a.PowerPreview=Get-GoatPowerPreview $a.Session $plan.Guid;$a.Controls.PowerConsent.IsChecked=$false;$a.Controls.PowerDetail.Text=Format-GoatPowerPreview $a.PowerPreview;Update-GoatPowerView}})
    $c.PowerConsent.Add_Checked({if(-not $script:GoatApp.ResettingReview){Update-GoatPowerView}});$c.PowerConsent.Add_Unchecked({if(-not $script:GoatApp.ResettingReview){Update-GoatPowerView}})
    $c.PowerApplyButton.Add_Click({Invoke-GoatUiCommand {
        Assert-GoatOpenSession;$a=$script:GoatApp;$plan=$a.Controls.PowerPlanBox.SelectedItem
        if(-not $a.Controls.PowerConsent.IsChecked -or -not $a.PowerPreview -or $a.PowerPreview.ProposedSchemeGuid -cne $plan.Guid){throw 'Revise a prévia deste plano e confirme o consentimento.'}
        if(Confirm-GoatUi ('Trocar para '+$plan.Name+"?`n"+($a.PowerPreview.Tradeoffs -join "`n"))){$reviewed=$a.PowerPreview;$result=Invoke-GoatPowerChange $a.Session $plan.Guid -Consent -ReviewedPreview $reviewed;$a.Controls.PowerDetail.Text=Format-GoatPowerPreview $reviewed ($result.State+': '+$result.Message);Update-GoatPowerView -Refresh;Set-GoatStatus $result.Message}
    }})
    $c.PowerRestoreButton.Add_Click({Invoke-GoatUiCommand {$a=$script:GoatApp;$transaction=$a.Controls.PowerTransactionBox.SelectedItem;if(-not $transaction){throw 'Selecione uma transação de energia.'};if(Confirm-GoatUi ('Restaurar o plano original de '+$transaction.Id+'?')){Restore-GoatPowerChange $a.Session $transaction.Id -Consent|Out-Null;Update-GoatPowerView -Refresh;Set-GoatStatus 'Plano original restaurado e conferido.'}}})
    $c.ImportCaptureButton.Add_Click({Invoke-GoatUiCommand {
        Assert-GoatOpenSession;$a=$script:GoatApp;$conditionsObject=$a.Controls.ConditionsBox.Text|ConvertFrom-Json -ErrorAction Stop;$conditions=@{};foreach($property in $conditionsObject.PSObject.Properties){$conditions[$property.Name]=$property.Value}
        $path=Select-GoatFile 'Frametimes CSV|*.csv';if(-not $path){return}
        $label=[string]$a.Controls.ConditionLabelBox.SelectedItem;$pass=@($a.Session.Benchmarks|Where-Object ConditionLabel -eq $label).Count+1
        Start-GoatFrameImportWorker -Path $path -Conditions $conditions -ConditionLabel $label -PassNumber $pass
    }})
    $c.CompareButton.Add_Click({Invoke-GoatUiCommand {
        Assert-GoatOpenSession;$a=$script:GoatApp;$comparison=Compare-GoatBenchmarkRuns -BaselineRuns @($a.Session.Benchmarks|Where-Object ConditionLabel -eq 'Baseline') -AfterRuns @($a.Session.Benchmarks|Where-Object ConditionLabel -eq 'After') -StabilityVerified:([bool]$a.Controls.StabilityCheck.IsChecked);$a.Session.Comparison=$comparison;Save-GoatSession $a.Session;$a.Controls.BenchmarkDetail.Text=Format-GoatBenchmarkView -Captures @($a.Session.Benchmarks) -Comparison $comparison;Set-GoatStatus ('Comparação: '+$comparison.Status)
    }})
    $c.ClearCapturesButton.Add_Click({Invoke-GoatUiCommand {Assert-GoatOpenSession;if(Confirm-GoatUi 'Iniciar outra comparação? Os CSV originais preservados não serão apagados.'){$a=$script:GoatApp;$a.Session.Benchmarks=@();$a.Session.Comparison=$null;Save-GoatSession $a.Session;$a.Controls.BenchmarkDetail.Text='Nova comparação. Importe passes de cada condição.'}}})
    $c.RestoreButton.Add_Click({Invoke-GoatUiCommand {
        $a=$script:GoatApp;$transaction=$a.Controls.TransactionBox.SelectedItem;if(-not $transaction){throw 'Selecione uma transação.'}
        if(Confirm-GoatUi ('Restaurar os valores originais da transação '+$transaction.Id+'?')){Restore-GoatTransaction $a.Session $transaction.Id -Consent|Out-Null;Update-GoatHistoryView;Set-GoatStatus 'Restauração verificada. Confira o histórico.'}
    }})
    $c.ExportButton.Add_Click({Invoke-GoatUiCommand {
        if($script:GoatApp.Worker){throw 'Aguarde a análise para exportar.'}
        $destination=Select-GoatExportDirectory;if($destination){$a=$script:GoatApp;$a.LastExport=Export-GoatService $a.Session $destination;Set-GoatStatus ('Exportação validada: '+$a.LastExport)}
    }})
    $c.FinishButton.Add_Click({Invoke-GoatUiCommand {
        if($script:GoatApp.Worker){throw 'Aguarde a análise antes de finalizar.'}
        if(Confirm-GoatUi 'Finalizar esta sessão após validar relatório e pacote privado de reversão? Os arquivos de recuperação serão preservados.'){
            $destination=if($script:GoatApp.Session.State -eq 'Finalized'){$null}else{Select-GoatExportDirectory}
            if($destination -or $script:GoatApp.Session.State -eq 'Finalized'){$a=$script:GoatApp;$a.LastExport=Complete-GoatSession $a.Session $destination -Consent;Update-GoatSessionView;Set-GoatStatus ('Serviço finalizado; exportação validada: '+$a.LastExport)}
        }
    }})
    $timer=[Windows.Threading.DispatcherTimer]::new();$timer.Interval=[TimeSpan]::FromMilliseconds(150);$timer.Add_Tick({Complete-GoatInventoryWorker});$a.Timer=$timer
    $window.Add_Loaded({$script:GoatApp.Timer.Start();Start-GoatInventoryWorker;if($script:GoatUiTestHook){& $script:GoatUiTestHook $script:GoatApp.Window}})
    $window.Add_Closed({$a=$script:GoatApp;$a.Timer.Stop();if($a.Worker){$a.Worker.PS.Stop();$a.Worker.PS.Dispose();$a.Worker=$null}})
    Update-GoatSessionView -SyncContext;$c.Navigation.SelectedIndex=0
    [void]$window.ShowDialog()
}
