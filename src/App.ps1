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
    $a=$script:GoatApp;$s=$a.Session;$c=$a.Controls
    $c.SessionLabel.Text=('Sessão {0} · {1} · {2} · {3}' -f $s.Id.Substring(0,8),$s.Objective,$s.Mode,$s.State)
    $c.ModeLabel.Text=if($s.Demo){'7.3 · DEMO / DADOS DE EXEMPLO'}else{'7.3 · PRÉVIA DE ENGENHARIA'}
    $c.SessionDetails.Text=('ID: {0}{1}Armazenamento privado: {2}{1}Criada: {3}{1}Estado: {4}' -f $s.Id,[Environment]::NewLine,$s.Root,$s.CreatedUtc,$s.State)
    $c.ObjectiveBox.SelectedItem=$s.Objective;$c.ServiceModeBox.SelectedItem=$s.Mode;$c.ConsentBox.IsChecked=$s.Consent
    $c.ApplyButton.IsEnabled=($s.Demo -and $s.State -eq 'Open' -and -not $a.Worker)
    $c.ApplyButton.Content=if($s.Demo){'Simular seleção (Demo)'}else{'Aplicação aguardando validação'}
    $c.FinishButton.IsEnabled=(-not $a.Worker)
}
function Update-GoatCatalogView {
    $a=$script:GoatApp;$c=$a.Controls;$q=$c.CatalogSearch.Text.Trim();$category=[string]$c.CategoryBox.SelectedItem;$class=[string]$c.ClassBox.SelectedItem
    $items=@($a.Catalog | Where-Object {
        (-not $q -or ([string]$_.title+' '+$_.id+' '+$_.short_explanation).IndexOf($q,[StringComparison]::OrdinalIgnoreCase) -ge 0) -and
        ($category -eq 'Todas as categorias' -or -not $category -or $_.category -eq $category) -and
        ($class -eq 'Todas as classes' -or -not $class -or $_.execution_class -eq $class)
    })
    $c.CatalogGrid.ItemsSource=[object[]]$items
    $c.CatalogCount.Text=('{0} de {1} registros · execução documental desabilitada' -f $items.Count,$a.Catalog.Count)
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
}
function Update-GoatInventoryView {
    $a=$script:GoatApp;$c=$a.Controls;$i=$a.Session.Inventory
    if(-not $i){return}
    $c.CpuSummary.Text=[string]$i.CPU.Name
    $c.GpuSummary.Text=(@($i.GpuCenter.Devices | ForEach-Object { $_.Name+' · '+$_.DriverVersion }) -join "`n")
    if(-not $c.GpuSummary.Text){$c.GpuSummary.Text='Indisponível'}
    $c.MemorySummary.Text=if($null -ne $i.Memory.TotalBytes){'{0:N1} GB · {1} % em uso' -f ($i.Memory.TotalBytes/1GB),$i.Memory.UsedPercent}else{'Indisponível'}
    $c.OsSummary.Text=('{0} · build {1}' -f $i.OS.Name,$i.OS.Build)
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
    $source='param([bool]$demo)' + "`r`n" + $script:GoatSources.Gpu + "`r`n" + $script:GoatSources.Inventory + "`r`nGet-GoatCompleteInventory -Demo:`$demo"
    $ps=[PowerShell]::Create();[void]$ps.AddScript($source);[void]$ps.AddArgument([bool]$a.Session.Demo)
    try{$a.Worker=@{PS=$ps;Handle=$ps.BeginInvoke();Started=[DateTime]::UtcNow};$a.Controls.RefreshButton.IsEnabled=$false;Update-GoatSessionView;Set-GoatStatus 'Consultando hardware em segundo plano…'}
    catch{$ps.Dispose();throw}
}
function Complete-GoatInventoryWorker {
    $a=$script:GoatApp;$w=$a.Worker
    if(-not $w){return}
    if(-not $w.Handle.IsCompleted){return}
    try{
        $result=@($w.PS.EndInvoke($w.Handle))
        if($w.PS.HadErrors){throw ($w.PS.Streams.Error | Out-String)}
        if($result.Count -ne 1){throw 'Inventário retornou resultado inesperado.'}
        $a.Session.Inventory=$result[0];Save-GoatSession $a.Session;Update-GoatInventoryView
        Set-GoatStatus 'Inventário concluído. Fontes sem leitura aparecem como indisponíveis; FPS e input lag não medidos.'
    }catch{Set-GoatStatus $_.Exception.Message -ErrorState}
    finally{$w.PS.Dispose();$a.Worker=$null;$a.Controls.RefreshButton.IsEnabled=$true;Update-GoatSessionView;Set-GoatPage $a.Page}
}
function Set-GoatPage {
    param([string]$Page)
    $a=$script:GoatApp;$c=$a.Controls;$a.Page=$Page;$c.PageTitle.Text=$Page
    foreach($name in @('Overview','Service','Catalog','Gpu','Profiles','Actions','Benchmarks','History','Documents','Detail')){$c[$name+'Page'].Visibility='Collapsed'}
    $map=@{'Visão geral'='Overview';'Atendimento'='Service';'Catálogo completo'='Catalog';'GPU CENTER'='Gpu';'Jogos / perfis'='Profiles';'Windows / preferências'='Actions';'Benchmarks'='Benchmarks';'Histórico / reversão'='History';'Documentação'='Documents'}
    if($map.ContainsKey($Page)){$c[$map[$Page]+'Page'].Visibility='Visible'}else{$c.DetailPage.Visibility='Visible'}
    $i=$a.Session.Inventory
    switch($Page){
        'Catálogo completo' {Update-GoatCatalogView}
        'Documentação' {Update-GoatDocumentsView}
        'Histórico / reversão' {Update-GoatHistoryView}
        'CPU / RAM' {$c.DetailIntro.Text='Topologia, memória e amostra de uso. Afinidade, prioridade e firmware exigem diagnóstico específico.';$c.DetailText.Text=Format-GoatHardwareView -Title 'CPU / RAM' -Value ([pscustomobject]@{CPU=$i.CPU;Memory=$i.Memory;Telemetry=$i.Telemetry})}
        'Rede / latência' {$c.DetailIntro.Text='RTT, jitter e perda são métricas de rede; não são FPS nem input lag. Nenhum adaptador é reconfigurado.';$c.DetailText.Text=Format-GoatHardwareView -Title 'Adaptadores de rede' -Value $i.Network}
        'Armazenamento' {$c.DetailIntro.Text='Saúde reportada pelo provedor, espaço e discos. Ausência de SMART é desconhecido. Nenhum benchmark de escrita automático.';$c.DetailText.Text=Format-GoatHardwareView -Title 'Armazenamento' -Value ([pscustomobject]@{Disks=$i.Disks;PhysicalDisks=$i.PhysicalDisks;StorageReliability=$i.StorageReliability})}
        'Inicialização / apps' {$c.DetailIntro.Text='Inventário somente leitura. Nenhum programa é encerrado e nenhuma entrada Run/RunOnce é apagada.';$c.DetailText.Text=Format-GoatHardwareView -Title 'Inicialização e aplicativos' -Value ([pscustomobject]@{Startup=$i.Startup;Apps=$i.Apps})}
        'Steam / Discord / OBS' {$c.DetailIntro.Text='Guias assistidos: confirme versão, preserve captura e compare uma variável. Configurações de apps não são alteradas nesta prévia.';$docs=@($a.Documents|Where-Object {$_.path -match '03_GUIAS_MANUAIS|04_STEAM_DISCORD'});$c.DetailText.Text=(@($i.Apps|ConvertTo-Json -Depth 5)+@($docs|ForEach-Object content)) -join "`r`n`r`n"}
        'Relatórios' {$c.DetailIntro.Text='Exportação HTML/JSON/CSV com dados pessoais minimizados e pacote privado de reversão. O botão Exportar permite escolher o destino.';$c.DetailText.Text=Get-GoatDisplayJson (Get-GoatPublicReport $a.Session)}
        'Laboratório / bloqueios' {$c.DetailIntro.Text='Laboratório fora do lote. Segurança, BIOS, OC, DDU automático, HPET/MSI/BCD e remoções disruptivas não possuem executores neste app.';$c.DetailText.Text=Get-GoatDisplayJson @($a.Catalog|Where-Object execution_class -in @('X_BLOCKED','D_LAB_ONLY')|Select-Object id,title,execution_class,risk,when_not_to_use)}
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
    $window.MaxHeight=[Windows.SystemParameters]::WorkArea.Height;$window.MaxWidth=[Windows.SystemParameters]::WorkArea.Width
    $controls=@{}
    foreach($match in [regex]::Matches($script:GoatXaml,'x:Name="([^"]+)"')){$controls[$match.Groups[1].Value]=$window.FindName($match.Groups[1].Value)}
    $session=$null
    if($SessionPath){
        $session=Get-Content -LiteralPath $SessionPath -Raw -Encoding UTF8|ConvertFrom-Json
        if($session.SchemaVersion -ne 1 -or $session.Id -notmatch '^[a-f0-9]{32}$'){throw 'Sessão inválida.'}
        $session.Root=Split-Path ([IO.Path]::GetFullPath($SessionPath)) -Parent
        if([bool]$session.Demo -ne [bool]$Demo){throw 'Use o mesmo modo Demo da sessão salva.'}
    }else{$session=New-GoatSession -Demo:$Demo -Root $DataRoot}
    $script:GoatApp=@{Window=$window;Controls=$controls;Session=$session;Worker=$null;Page='Visão geral';DataRoot=$DataRoot;Catalog=@(($script:GoatCatalogJson|ConvertFrom-Json).controls);Documents=@(($script:GoatDocumentsJson|ConvertFrom-Json).documents);Preview=@();LastExport=$null}
    $a=$script:GoatApp;$c=$controls
    $pages=@('Visão geral','Atendimento','Catálogo completo','Windows / preferências','CPU / RAM','GPU CENTER','Jogos / perfis','Steam / Discord / OBS','Rede / latência','Armazenamento','Inicialização / apps','Benchmarks','Histórico / reversão','Relatórios','Documentação','Laboratório / bloqueios')
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
    $c.SaveSessionButton.Add_Click({Invoke-GoatUiCommand {
        Assert-GoatOpenSession;$a=$script:GoatApp;$a.Session.Objective=[string]$a.Controls.ObjectiveBox.SelectedItem;$a.Session.Mode=[string]$a.Controls.ServiceModeBox.SelectedItem;$a.Session.Consent=[bool]$a.Controls.ConsentBox.IsChecked;Save-GoatSession $a.Session;Update-GoatSessionView;Update-GoatInventoryView;Set-GoatStatus 'Contexto salvo; revise o plano antes de qualquer ação.'
    }})
    $c.NewSessionButton.Add_Click({Invoke-GoatUiCommand {
        if($script:GoatApp.Worker){throw 'Aguarde o inventário.'}
        if(Confirm-GoatUi 'Abrir nova sessão? A sessão atual continuará salva para retomada.'){$a=$script:GoatApp;$a.Session=New-GoatSession -Demo:$a.Session.Demo -Root $a.DataRoot;Update-GoatSessionView;Start-GoatInventoryWorker}
    }})
    $c.ResumeButton.Add_Click({Invoke-GoatUiCommand {
        if($script:GoatApp.Worker){throw 'Aguarde o inventário.'}
        $path=Select-GoatFile 'Sessão GOAT|session.json';if(-not $path){return}
        $s=Get-Content -LiteralPath $path -Raw -Encoding UTF8|ConvertFrom-Json
        if($s.SchemaVersion -ne 1 -or $s.Id -notmatch '^[a-f0-9]{32}$'){throw 'Sessão inválida.'}
        if([bool]$s.Demo -ne [bool]$script:GoatApp.Session.Demo){throw 'Abra o aplicativo no mesmo modo Demo da sessão.'}
        $s.Root=Split-Path $path -Parent;$script:GoatApp.Session=$s;Update-GoatSessionView;Update-GoatInventoryView;Set-GoatPage 'Histórico / reversão';Set-GoatStatus 'Sessão recuperada; confira transações pendentes.'
    }})
    $c.CatalogSearch.Add_TextChanged({Update-GoatCatalogView});$c.CategoryBox.Add_SelectionChanged({Update-GoatCatalogView});$c.ClassBox.Add_SelectionChanged({Update-GoatCatalogView})
    $c.CatalogGrid.Add_SelectionChanged({$item=$script:GoatApp.Controls.CatalogGrid.SelectedItem;if($item){$script:GoatApp.Controls.CatalogDetail.Text=Format-GoatCatalogView $item}})
    $c.DocumentSearch.Add_TextChanged({Update-GoatDocumentsView})
    $c.DocumentsList.Add_SelectionChanged({$doc=$script:GoatApp.Controls.DocumentsList.SelectedItem;if($doc){$script:GoatApp.Controls.DocumentText.Text=('Fonte: '+$doc.path+"`r`nSHA256: "+$doc.sha256+"`r`nTipo: "+$doc.kind+"`r`n`r`n"+$doc.content)}})
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
        $a=$script:GoatApp;$ids=@($a.Controls.ActionsList.SelectedItems|ForEach-Object Id);$a.Preview=@(Get-GoatActionPreview $a.Session $ids ([string]$a.Controls.DirectionBox.SelectedItem) -InspectOnly);$a.Controls.ActionDetail.Text=Get-GoatDisplayJson $a.Preview
    }})
    $c.ApplyButton.Add_Click({Invoke-GoatUiCommand {
        Assert-GoatOpenSession;$a=$script:GoatApp;if(-not $a.Controls.ActionConsent.IsChecked){throw 'Revise a prévia e marque o consentimento.'}
        $ids=@($a.Controls.ActionsList.SelectedItems|ForEach-Object Id);if(-not $a.Preview.Count -or ($a.Preview.Id -join ',') -ne ($ids -join ',') -or @($a.Preview|Where-Object Direction -ne ([string]$a.Controls.DirectionBox.SelectedItem)).Count){throw 'Gere uma prévia para esta seleção e direção.'}
        $result=Invoke-GoatActionBatch $a.Session $ids ([string]$a.Controls.DirectionBox.SelectedItem) -Consent;$a.Controls.ActionDetail.Text=Get-GoatDisplayJson $result;$a.Preview=@();Set-GoatStatus $result.Message
    }})
    $c.ImportCaptureButton.Add_Click({Invoke-GoatUiCommand {
        Assert-GoatOpenSession;$a=$script:GoatApp;$conditionsObject=$a.Controls.ConditionsBox.Text|ConvertFrom-Json -ErrorAction Stop;$conditions=@{};foreach($property in $conditionsObject.PSObject.Properties){$conditions[$property.Name]=$property.Value}
        $path=Select-GoatFile 'Frametimes CSV|*.csv';if(-not $path){return}
        $label=[string]$a.Controls.ConditionLabelBox.SelectedItem;$pass=@($a.Session.Benchmarks|Where-Object ConditionLabel -eq $label).Count+1
        $capture=Import-GoatFrameCapture -Path $path -Conditions $conditions -ConditionLabel $label -PassNumber $pass
        $folder=Join-Path $a.Session.Root 'captures';[void][IO.Directory]::CreateDirectory($folder);Copy-Item -LiteralPath $path -Destination (Join-Path $folder ($capture.CaptureId+'.csv'))
        $a.Session.Benchmarks+=$capture;$a.Session.Comparison=$null;Save-GoatSession $a.Session
        $a.Controls.BenchmarkDetail.Text=Format-GoatBenchmarkView -Captures @($a.Session.Benchmarks);Set-GoatStatus 'Captura importada com hash e dados originais preservados.'
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
    Update-GoatSessionView;$c.Navigation.SelectedIndex=0
    [void]$window.ShowDialog()
}
