#Requires -Version 5.1
[CmdletBinding()]
param([string]$Bundle,[string]$ArtifactsRoot,[switch]$RealReadOnly)
$ErrorActionPreference='Stop'
if([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA'){throw 'Run this WPF test with powershell.exe -STA.'}
$projectRoot=Split-Path $PSScriptRoot -Parent
if(-not $ArtifactsRoot){$ArtifactsRoot=Join-Path $projectRoot 'artifacts/ui'}
$ArtifactsRoot=[IO.Path]::GetFullPath($ArtifactsRoot)
[void][IO.Directory]::CreateDirectory($ArtifactsRoot)
$script:UiFixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('GOAT-UI-Test-'+[guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($script:UiFixtureRoot)
$script:UiCheckNames=New-Object 'System.Collections.Generic.List[string]'
$script:UiFailure=$null
$script:UiStep=0
$script:UiNavigationIndex=0
$script:UiResetPhase=0
$script:UiPages=@()
$script:UiStarted=[DateTime]::UtcNow
$script:UiCancelStarted=$false;$script:UiCancelCompleted=$false;$script:UiOriginalInventorySource=$null
$script:UiFileQueue=New-Object 'System.Collections.Generic.Queue[string]'
$script:UiOpenedTargets=New-Object 'System.Collections.Generic.List[string]'
$script:UiArtifactRoot=$ArtifactsRoot
$script:UiSourceMode=if($Bundle){'BUNDLED'}else{'SOURCE'}
$launchPath=if($Bundle){[IO.Path]::GetFullPath($Bundle)}else{Join-Path $projectRoot 'GOAT-Tweaks.ps1'}
function Assert-Ui {param([bool]$Condition,[string]$Name);if(-not $Condition){throw ('UI assertion: '+$Name)};$script:UiCheckNames.Add($Name)}
function Invoke-UiClick {param([string]$Name);$button=$script:GoatApp.Controls[$Name];if(-not $button){throw ('Missing button: '+$Name)};$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
function Set-UiReviewedFixtures {
    $a=$script:GoatApp;$c=$a.Controls
    $c.Navigation.SelectedItem='Windows / preferências';$c.ActionsList.SelectedIndex=0;Invoke-UiClick 'PreviewButton';$c.ActionConsent.IsChecked=$true
    $c.Navigation.SelectedItem='Energia';$c.PowerPlanBox.SelectedIndex=1;Invoke-UiClick 'PowerPreviewButton';$c.PowerConsent.IsChecked=$true
    $c.LocalOperatorCheck.IsChecked=$true;$c.RecoveryPlanCheck.IsChecked=$true;$c.ManualDoneCheck.IsChecked=$true
    Assert-Ui ($a.Preview.Count -eq 1 -and $null -ne $a.PowerPreview -and $c.ActionConsent.IsChecked -and $c.PowerConsent.IsChecked) 'regression fixture contains actual reviewed Demo previews before context/session change'
}
function Assert-UiReviewCleared {
    param([string]$Context)
    $a=$script:GoatApp;$c=$a.Controls
    Assert-Ui ($a.Preview.Count -eq 0 -and $null -eq $a.PowerPreview) ($Context+': native and power previews cleared')
    Assert-Ui (-not $c.ActionConsent.IsChecked -and -not $c.PowerConsent.IsChecked -and -not $c.ManualDoneCheck.IsChecked) ($Context+': action and manual acknowledgements cleared')
    Assert-Ui (-not $c.LocalOperatorCheck.IsChecked -and -not $c.RecoveryPlanCheck.IsChecked) ($Context+': local recovery prerequisites are not inherited')
    Assert-Ui (-not $c.ApplyButton.IsEnabled -and -not $c.PowerApplyButton.IsEnabled -and -not $c.ManualRecordButton.IsEnabled) ($Context+': application and report buttons require new review')
}
function Save-UiRender {
    param([string]$Name)
    $visual=$script:GoatApp.Window.Content
    $visual.UpdateLayout()
    $width=[int][Math]::Ceiling($visual.ActualWidth);$height=[int][Math]::Ceiling($visual.ActualHeight)
    if($width -le 0 -or $height -le 0){throw 'Window has no measured layout.'}
    $bitmap=[Windows.Media.Imaging.RenderTargetBitmap]::new($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($visual)
    $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $output=Join-Path $script:UiArtifactRoot ($Name+'.png')
    $stream=[IO.File]::Open($output,[IO.FileMode]::Create,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try{$encoder.Save($stream)}finally{$stream.Dispose()}
    Assert-Ui ((Get-Item -LiteralPath $output).Length -gt 1000) ('WPF rendered: '+$Name)
}
try {
    # Demo ScanOnly loads the exact launcher's packed/source modules without hardware queries.
    . $launchPath -Demo -ScanOnly | Out-Null
    . ([scriptblock]::Create($script:GoatSources.App))
    $script:GoatUiAutoConfirm=$true # The application honors this flag only in Demo.
    # Test the real URL/URI validation and click handlers without opening apps/websites.
    function Start-Process {[CmdletBinding()]param([string]$FilePath,[string[]]$ArgumentList);$script:UiOpenedTargets.Add($FilePath)}
    function Write-GoatRegistry {throw 'UI tests must never write a real registry preference.'}
    if(-not $RealReadOnly){function Invoke-GoatPowerCfg {throw 'Demo UI tests must never execute powercfg.'}}
    function Select-GoatExportDirectory {Join-Path $script:UiFixtureRoot 'exports'}
    function Select-GoatFile {param([string]$Filter);if($script:UiFileQueue.Count -gt 0){return $script:UiFileQueue.Dequeue()};return $null}
    $conditions=@{Game='UI fixture';GameBuild='1';Scene='repeatable scene';Resolution='1920x1080';Preset='High';Api='DX12';Driver='fixture';OsBuild='26100';FrameCap='off';VSync='off';CaptureTool='Fixture CSV';CaptureVersion='1'}
    $script:UiConditionJson=$conditions|ConvertTo-Json -Compress
    foreach($condition in @('Baseline','After')){
        foreach($pass in 1..3){
            $path=Join-Path $script:UiFixtureRoot ($condition+'-'+$pass+'.csv')
            $interval=if($condition -eq 'Baseline'){10.0+$pass/1000.0}else{9.0+$pass/1000.0}
            $value=$interval.ToString('R',[Globalization.CultureInfo]::InvariantCulture)
            [IO.File]::WriteAllLines($path,[string[]](@('FrameTimeMs')+@(1..100|ForEach-Object{$value})))
        }
    }
    $script:GoatUiTestHook={
        param($Window)
        $script:UiTimer=[Windows.Threading.DispatcherTimer]::new()
        $script:UiTimer.Interval=[TimeSpan]::FromMilliseconds(160)
        $script:UiTimer.Add_Tick({
            try {
                if(([DateTime]::UtcNow-$script:UiStarted).TotalSeconds -gt 70){throw 'UI test exceeded 70 seconds.'}
                $a=$script:GoatApp;$c=$a.Controls
                if($a.Worker){return}
                if(-not $a.Session.Inventory){throw ('Inventory failed: '+$c.StatusText.Text)}
                if($RealReadOnly){
                    Assert-Ui (-not $a.Session.Demo -and -not $a.Session.Inventory.Demo -and $a.Session.Inventory.ReadOnly) 'physical inventory is real and explicitly read-only'
                    Assert-Ui ($c.ModeLabel.Text -match [regex]::Escape($script:GoatVersion) -and $c.ModeLabel.Text -notmatch 'PRÉVIA|preview') 'current official version is shown in the real interface'
                    $saved=Get-Content -LiteralPath (Join-Path $a.Session.Root 'session.json') -Raw -Encoding UTF8|ConvertFrom-Json
                    Assert-Ui ($saved.Consent -eq $false -and $null -eq $saved.Inventory -and $null -ne $a.Session.Inventory) 'real inventory remains in memory until local recording consent'
                    $script:UiPages=@($c.Navigation.ItemsSource)
                    foreach($page in $script:UiPages){$c.Navigation.SelectedItem=$page;Assert-Ui ($a.Page -eq $page) ('real read-only navigation: '+$page)}
                    $c.Navigation.SelectedItem='Windows / preferências';$c.ActionsList.SelectedIndex=0;Invoke-UiClick 'PreviewButton'
                    Assert-Ui ($a.Preview.Count -eq 1 -and $a.Preview[0].Action.Name -eq 'HideFileExt' -and -not $c.ApplyButton.IsEnabled) 'native preview reads actual state while consent is unchecked and no write occurs'
                    Assert-Ui (@(Get-GoatTransactions $a.Session).Count -eq 0) 'real UI scan creates no registry mutation journal'
                    $c.Navigation.SelectedItem='Visão geral';Save-UiRender '08-real-readonly'
                    $script:UiStep=10;$script:UiTimer.Stop();$a.Window.Close();return
                }
                if($script:UiStep -eq 0 -and -not $script:UiCancelCompleted){
                    if(-not $script:UiCancelStarted){
                        $script:UiOriginalInventorySource=$script:GoatSources.Inventory
                        $script:GoatSources.Inventory+="`r`nfunction Get-GoatCompleteInventory { param([switch]`$Demo) Start-Sleep -Seconds 5; throw 'fixture should be cancelled' }"
                        $script:UiPreviousInventory=$a.Session.Inventory
                        Start-GoatInventoryWorker;Assert-Ui ($null -ne $a.Worker) 'cancel fixture runs in an owned background read worker'
                        Invoke-UiClick 'CancelReadButton';Assert-Ui $a.Worker.CancelRequested 'cancel button requests asynchronous stop'
                        $script:UiCancelStarted=$true;return
                    }
                    $script:GoatSources.Inventory=$script:UiOriginalInventorySource
                    Assert-Ui ($c.StatusText.Text -match 'cancelada' -and [object]::ReferenceEquals($script:UiPreviousInventory,$a.Session.Inventory)) 'cancel preserves previous inventory and reports cancellation'
                    Assert-Ui ($c.RefreshButton.IsEnabled -and $c.CancelReadButton.Visibility -eq 'Collapsed') 'cancelled worker releases controls for another scan'
                    $script:UiCancelCompleted=$true
                    Set-GoatStatus 'Demonstração: inventário de exemplo disponível. Nenhum ajuste foi aplicado.'
                }
                switch($script:UiStep){
                    0 {
                        Assert-Ui ($a.Session.Demo -and $a.Session.Inventory.Demo -and $a.Session.Inventory.ReadOnly) 'Demo inventory is explicitly simulated/read-only'
                        Assert-Ui ($a.Session.Inventory.GpuCenter.Devices.Count -eq 1) 'GPU inventory reaches real WPF view'
                        Assert-Ui ($c.CpuSummary.Text.Length -gt 0 -and $c.GpuSummary.Text -match 'exemplo') 'hardware cards populated from Demo data'
                        Assert-Ui ($c.DiagnosisPanel.Children.Count -gt 0) 'diagnosis cards populate'
                        Assert-Ui ($c.Navigation.Items.Count -eq 18) 'all 18 application pages are navigable'
                        Assert-Ui ($c.ActionsList.Items.Count -eq @(Get-GoatActions).Count) 'native and manual preference registry reaches the UI'
                        Assert-Ui ($a.Guides.Count -eq 50 -and $c.AdvancedList.Items.Count -eq 50) 'all 50 advanced catalog IDs reach real WPF controls'
                        $script:UiPages=@($c.Navigation.ItemsSource)
                        Save-UiRender '01-overview'
                        $script:UiStep++
                    }
                    1 {
                        if($script:UiNavigationIndex -lt $script:UiPages.Count){
                            $page=$script:UiPages[$script:UiNavigationIndex]
                            $c.Navigation.SelectedItem=$page
                            Assert-Ui ($a.Page -eq $page -and $c.PageTitle.Text -eq $page) ('navigation: '+$page)
                            $visible=@('Overview','Service','Catalog','Gpu','Profiles','Actions','Advanced','Power','Benchmarks','History','Documents','Detail'|Where-Object{$c[$_+'Page'].Visibility -eq 'Visible'})
                            Assert-Ui ($visible.Count -eq 1) ('one content surface visible: '+$page)
                            if($page -eq 'GPU CENTER'){Save-UiRender '02-gpu-center'}
                            $script:UiNavigationIndex++
                        }else{$script:UiStep++}
                    }
                    2 {
                        $c.Navigation.SelectedItem='Catálogo completo'
                        Assert-Ui ($c.CatalogGrid.Items.Count -eq 344) 'catalog renders every documented ID'
                        $c.ClassBox.SelectedItem='X_BLOCKED'
                        Assert-Ui ($c.CatalogGrid.Items.Count -eq @($a.Catalog|Where-Object execution_class -eq 'X_BLOCKED').Count) 'class filter uses effective runtime classification'
                        Assert-Ui (@($a.SourceCatalog|Where-Object execution_class -eq 'X_BLOCKED').Count -ge 50) 'source catalog retains reviewed historical and normative blocks'
                        Assert-Ui (@($a.Catalog|Where-Object {$_.SpecificationClass -eq 'X_BLOCKED' -and $_.RuntimeTarget -eq 'Advanced' -and $_.execution_class -eq 'C_MANUAL'}).Count -eq 50) 'runtime procedures expose all 50 blocked references while preserving their source class'
                        $c.ClassBox.SelectedIndex=0;$c.CatalogSearch.Text='WIN-GAMEMODE'
                        Assert-Ui ($c.CatalogGrid.Items.Count -eq 1) 'catalog ID search works'
                        $c.CatalogGrid.SelectedIndex=0
                        Assert-Ui ($c.CatalogDetail.Text -match 'SPEC_ONLY_NOT_YET_VERIFIED' -and $c.CatalogDetail.Text -match 'SHA256:' -and $c.CatalogDetail.Text -match 'NATIVE_EXECUTOR') 'catalog detail separates documentary status, provenance and actual native executor'
                        Assert-Ui ($c.CatalogOpenButton.IsEnabled) 'mapped native resource can be opened from the catalog'
                        Invoke-UiClick 'CatalogOpenButton'
                        Assert-Ui ($a.Page -eq 'Windows / preferências' -and @($c.ActionsList.SelectedItems|Where-Object Id -eq 'gaming-game-mode').Count -eq 1) 'catalog native link selects the actual executor'
                        $c.Navigation.SelectedItem='Catálogo completo';$c.CatalogSearch.Text='SEC-HVCI';$c.CatalogGrid.SelectedIndex=0;Invoke-UiClick 'CatalogOpenButton'
                        Assert-Ui ($a.Page -eq 'Procedimentos avançados' -and $c.AdvancedList.SelectedItem.Id -eq 'SEC-HVCI') 'catalog advanced link selects the corresponding individual procedure'
                        $c.Navigation.SelectedItem='Catálogo completo';$c.CatalogSearch.Text='WIN-GAMEMODE';$c.CatalogGrid.SelectedIndex=0
                        Save-UiRender '03-catalog-filter'
                        $c.CatalogSearch.Text='';$script:UiStep++
                    }
                    3 {
                        $c.Navigation.SelectedItem='Documentação'
                        Assert-Ui ($c.DocumentsList.Items.Count -eq 64) 'full document library renders'
                        $c.DocumentSearch.Text='PROMPT_ATIVO_GOAT_TWEAKS'
                        Assert-Ui ($c.DocumentsList.Items.Count -gt 0 -and $c.DocumentsList.Items.Count -lt 64) 'document text search filters references'
                        $c.DocumentsList.SelectedIndex=0
                        Assert-Ui ($c.DocumentText.Text -match 'SHA256:' -and $c.DocumentText.IsReadOnly) 'documents show provenance and remain read-only'
                        Save-UiRender '04-documentation'
                        $c.DocumentSearch.Text='';$script:UiStep++
                    }
                    4 {
                        if($script:UiResetPhase -eq 0){
                            Set-UiReviewedFixtures
                            $script:UiOriginalSessionId=$a.Session.Id;$script:UiOriginalSessionPath=Join-Path $a.Session.Root 'session.json'
                            Invoke-UiClick 'NewSessionButton'
                            Assert-Ui ($a.Session.Id -ne $script:UiOriginalSessionId -and $null -eq $a.Session.Inventory -and $null -ne $a.Worker) 'new session starts its own inventory without inheriting the previous scan'
                            Assert-UiReviewCleared 'New session before inventory'
                            $script:UiResetPhase=1;return
                        }
                        if($script:UiResetPhase -eq 1){
                            Set-UiReviewedFixtures
                            $script:UiFileQueue.Enqueue($script:UiOriginalSessionPath);Invoke-UiClick 'ResumeButton'
                            Assert-Ui ($a.Session.Id -eq $script:UiOriginalSessionId -and $null -eq $a.Session.Inventory) 'resume loads a consent-free saved session whose inventory is null'
                            Assert-UiReviewCleared 'Resume with null inventory'
                            Assert-Ui ($c.PowerPlanBox.Items.Count -eq 0 -and $null -eq $a.PowerPlans) 'resume cannot reuse a previous session power-plan cache'
                            Start-GoatInventoryWorker;$script:UiResetPhase=2;return
                        }
                        Set-UiReviewedFixtures
                        $a.Session.Inventory.RemoteContext=[pscustomobject]@{IsRemote=$false;RemoteProcessNames=@();Confidence='LOCAL SNAPSHOT FIXTURE';DriverMaintenanceBlocked=$true}
                        $c.Navigation.SelectedItem='Atendimento'
                        $c.ObjectiveBox.SelectedItem='Competitivo';$c.ServiceModeBox.SelectedItem='Remoto';$c.ConsentBox.IsChecked=$true
                        $beforeUnsavedApply=@($a.Session.Events|Where-Object Kind -eq 'DEMO').Count
                        $c.ActionConsent.IsChecked=$false;$c.ActionConsent.IsChecked=$true
                        Assert-Ui ($c.ServiceModeBox.SelectedItem -eq 'Remoto' -and $a.Session.Mode -eq 'Local') 'action-consent callbacks preserve an unsaved remote mode selection'
                        Invoke-UiClick 'ApplyButton'
                        Assert-Ui ($c.StatusText.Text -match 'Salve o contexto' -and @($a.Session.Events|Where-Object Kind -eq 'DEMO').Count -eq $beforeUnsavedApply) 'applying with an unsaved remote context is rejected before even a Demo action event'
                        Invoke-UiClick 'PreviewButton'
                        Assert-Ui ($c.StatusText.Text -match 'Salve o contexto') 'unsaved local-to-remote change blocks action review before any write'
                        Invoke-UiClick 'SaveSessionButton'
                        Assert-Ui ($a.Session.Objective -eq 'Competitivo' -and $a.Session.Mode -eq 'Remoto' -and $a.Session.Consent) 'service context persists from controls'
                        Assert-UiReviewCleared 'Saved remote context'
                        $remoteDriver=@($a.Guides|Where-Object Id -eq 'STOR-NVME-DRIVER')[0]
                        Assert-Ui ($a.Session.Inventory.RemoteContext.IsRemote -eq $false -and $remoteDriver.Prerequisites.RemoteOrUnknown -and -not $remoteDriver.Prerequisites.MaintenanceReady) 'saved remote service context overrides a stale local snapshot without mutating inventory'
                        $c.Navigation.SelectedItem='GPU CENTER';Invoke-UiClick 'GpuGuideButton'
                        Assert-Ui ($c.GpuDetail.Text -match 'BLOCKED' -and $c.GpuDetail.Text -match 'gpu-ddu') 'remote DDU guide remains blocked in UI'
                        $script:UiStep++
                    }
                    5 {
                        $c.Navigation.SelectedItem='Windows / preferências'
                        $c.ActionsList.SelectedIndex=0;Invoke-UiClick 'PreviewButton'
                        Assert-Ui ($a.Preview.Count -eq 1 -and $a.Preview[0].Action.Name -eq 'HideFileExt' -and $c.ActionDetail.Text -match 'Estado original e proposta') 'Demo preview shows human explanation and exact state snapshots'
                        Assert-Ui (-not $c.ApplyButton.IsEnabled -and -not $c.ActionConsent.IsChecked) 'native preview requires new contextual consent'
                        $c.DirectionBox.SelectedItem='Off'
                        Assert-Ui ($a.Preview.Count -eq 0 -and -not $c.ApplyButton.IsEnabled) 'changing direction invalidates the reviewed native preview'
                        $c.DirectionBox.SelectedItem='On';Invoke-UiClick 'PreviewButton'
                        $c.ActionConsent.IsChecked=$true;Invoke-UiClick 'ApplyButton'
                        Assert-Ui (@($a.Session.Events|Where-Object Kind -eq 'DEMO').Count -eq 1) 'Demo click records simulation'
                        Assert-Ui (@(Get-GoatTransactions $a.Session).Count -eq 0) 'Demo action creates no real mutation journal'
                        Assert-Ui ($c.ActionDetail.Text -match 'DEMO' -and $a.Preview.Count -eq 0) 'Demo success is visibly simulated and consumes preview'
                        Save-UiRender '05-demo-actions'
                        $manualPreference=@($c.ActionsList.Items|Where-Object ExecutorKind -eq 'ManualGuide')[0];$c.ActionsList.SelectedItem=$manualPreference;Invoke-UiClick 'PreviewButton';$c.ActionConsent.IsChecked=$true
                        Assert-Ui ($a.Preview.Count -eq 1 -and -not $a.Preview[0].ExecutionAllowed -and -not $c.ApplyButton.IsEnabled) 'documented manual preference cannot masquerade as an executable native toggle'
                        $c.Navigation.SelectedItem='Procedimentos avançados'
                        $unsupported=@($a.Guides|Where-Object Id -eq 'SEC-002')[0];$c.AdvancedList.SelectedItem=$unsupported
                        Assert-Ui ($c.AdvancedDetail.Text -match 'UNSUPPORTED' -and -not $c.AdvancedSettingsButton.IsEnabled) 'unsupported signing bypass has a visible reason and no misleading settings action'
                        $c.ManualDoneCheck.IsChecked=$true
                        Assert-Ui (-not $c.ManualRecordButton.IsEnabled) 'unsupported procedure cannot be recorded as performed'
                        $guide=@($a.Guides|Where-Object Id -eq 'SEC-HVCI')[0];$c.AdvancedList.SelectedItem=$guide
                        Assert-Ui ($c.AdvancedDetail.Text -match 'MANUAL_GUIDE' -and $c.AdvancedDetail.Text -match 'RECUPERAÇÃO' -and $c.AdvancedDetail.Text -match 'FONTES') 'manual guide shows procedure, recovery and sources in human text'
                        Assert-Ui ($c.AdvancedSettingsButton.IsEnabled -and $c.AdvancedSourceButton.IsEnabled -and -not $c.ManualRecordButton.IsEnabled) 'manual settings/source require separate acknowledgement before a reported step'
                        $opened=$script:UiOpenedTargets.Count;Invoke-UiClick 'AdvancedSettingsButton';Invoke-UiClick 'AdvancedSourceButton'
                        Assert-Ui ($script:UiOpenedTargets.Count -eq ($opened+2) -and $script:UiOpenedTargets[$opened] -eq 'ms-settings:windowsdefender') 'manual settings handler requests the exact allowlisted Windows URI without launching it in tests'
                        Assert-Ui (Test-GoatAdvancedSourceUrl $script:UiOpenedTargets[$opened+1]) 'manual source handler requests an official HTTPS document'
                        $blockedUri=$false;try{Open-GoatSettingsPage 'ms-settings:windowsdefender?run=cmd'}catch{$blockedUri=$true}
                        $blockedUrl=$false;try{Open-GoatOfficialLink 'https://microsoft.com.attacker.invalid/test'}catch{$blockedUrl=$true}
                        Assert-Ui ($blockedUri -and $blockedUrl -and $script:UiOpenedTargets.Count -eq ($opened+2)) 'unsafe URI arguments and spoofed official URLs are blocked before launch'
                        $manualCount=@($a.Session.ManualRecords|Where-Object {$null -ne $_}).Count;$c.ManualDoneCheck.IsChecked=$true;Invoke-UiClick 'ManualRecordButton'
                        Assert-Ui (@($a.Session.ManualRecords).Count -eq ($manualCount+1) -and $a.Session.ManualRecords[-1].State -eq 'REPORTED_MANUALLY' -and -not $a.Session.ManualRecords[-1].AutomaticallyVerified) 'Demo manual acknowledgement is recorded as a report, never automatically verified'
                        $driver=@($a.Guides|Where-Object Id -eq 'STOR-NVME-DRIVER')[0];$c.AdvancedList.SelectedItem=$driver;$c.ManualDoneCheck.IsChecked=$true
                        Assert-Ui (-not $c.ManualRecordButton.IsEnabled -and -not $driver.Prerequisites.MaintenanceReady) 'remote driver maintenance cannot be acknowledged without local recovery prerequisites'
                        $c.LocalOperatorCheck.IsChecked=$true;$c.RecoveryPlanCheck.IsChecked=$true;$c.ManualDoneCheck.IsChecked=$true
                        Assert-Ui ($c.AdvancedList.SelectedItem.Id -eq 'STOR-NVME-DRIVER' -and $c.ManualRecordButton.IsEnabled) 'local operator and recovery confirmation unlock only the selected manual report'
                        $c.LocalOperatorCheck.IsChecked=$false;$c.RecoveryPlanCheck.IsChecked=$false
                        Save-UiRender '09-advanced-guides'
                        $c.Navigation.SelectedItem='Energia'
                        Assert-Ui ($c.PowerPlanBox.Items.Count -eq 3 -and -not $c.PowerApplyButton.IsEnabled) 'power page shows existing Demo plans and starts without apply consent'
                        $c.PowerPlanBox.SelectedIndex=1;Invoke-UiClick 'PowerPreviewButton'
                        Assert-Ui ($a.PowerPreview.ProposedSchemeGuid -eq $c.PowerPlanBox.SelectedItem.Guid -and -not $c.PowerApplyButton.IsEnabled) 'power preview records the selected existing GUID and requires consent'
                        $c.PowerPlanBox.SelectedIndex=2
                        Assert-Ui ($null -eq $a.PowerPreview -and -not $c.PowerConsent.IsChecked -and -not $c.PowerApplyButton.IsEnabled) 'changing plans invalidates prior preview and approval'
                        Invoke-UiClick 'PowerPreviewButton';$c.PowerConsent.IsChecked=$true
                        Assert-Ui $c.PowerApplyButton.IsEnabled 'reviewed Demo plan enables the simulation button'
                        $activeBefore=$a.PowerPlans.ActiveSchemeGuid;Invoke-UiClick 'PowerApplyButton'
                        Assert-Ui ($c.PowerDetail.Text -match 'DEMO' -and $a.PowerPlans.ActiveSchemeGuid -eq $activeBefore) 'Demo power action reports simulation and leaves the real/native plan untouched'
                        Assert-Ui (@(Get-GoatPowerTransactions $a.Session).Count -eq 0 -and @($a.Session.Events|Where-Object Kind -eq 'DEMO').Count -eq 2) 'power Demo records an event without mutation journals'
                        Assert-Ui ($null -eq $a.PowerPreview -and -not $c.PowerApplyButton.IsEnabled) 'power simulation consumes the preview and approval'
                        Save-UiRender '10-power-plan';$script:UiStep++
                    }
                    6 {
                        $c.Navigation.SelectedItem='Jogos / perfis'
                        $c.GameIdBox.Text='fixture:123';$c.GameNameBox.Text='UI fixture game';$c.ResolutionBox.Text='1920x1080';$c.HzBox.Text='144';$c.FpsBox.Text='200'
                        $c.ProfileGoalBox.SelectedIndex=0;$c.ReflexBox.SelectedItem='Enabled';$c.VrrBox.SelectedItem='Enabled';$c.VSyncBox.SelectedItem='Enabled';$c.CaptureBox.IsChecked=$true
                        Invoke-UiClick 'ProfilePreviewButton'
                        Assert-Ui ($c.ProfileDetail.Text -match 'GUIDANCE_ONLY' -and $c.ProfileDetail.Text -match 'Reflex') 'game profile previews advice and conflicts'
                        Save-UiRender '06-game-profile'
                        Invoke-UiClick 'ProfileSaveButton'
                        Assert-Ui ($a.Session.Profiles.Count -eq 1 -and -not $a.Session.Profiles[0].WindowsSettingsChanged) 'profile saved locally without writing Windows settings'
                        Assert-Ui (@(Get-ChildItem -LiteralPath (Join-Path $a.Session.Root 'profiles') -Filter '*.goat-profile.json').Count -eq 1) 'profile file generated'
                        $script:UiStep++
                    }
                    7 {
                        $c.Navigation.SelectedItem='Benchmarks';$c.ConditionsBox.Text=$script:UiConditionJson
                        if($a.Session.Benchmarks.Count -lt 6){
                            $count=$a.Session.Benchmarks.Count;$condition=if($count -lt 3){'Baseline'}else{'After'};$pass=($count%3)+1
                            $c.ConditionLabelBox.SelectedItem=$condition
                            $script:UiFileQueue.Enqueue((Join-Path $script:UiFixtureRoot ($condition+'-'+$pass+'.csv')));Invoke-UiClick 'ImportCaptureButton'
                            Assert-Ui ($null -ne $a.Worker -and $a.Worker.Kind -eq 'FrameCapture' -and -not $c.ImportCaptureButton.IsEnabled) 'frame import runs outside WPF thread and prevents overlapping imports'
                            return
                        }
                        Assert-Ui ($a.Session.Benchmarks.Count -eq 6) 'six original benchmark captures imported through UI'
                        Invoke-UiClick 'CompareButton'
                        Assert-Ui ($a.Session.Comparison.Status -eq 'INCONCLUSIVE') 'UI does not confirm benefit without stability verification'
                        Assert-Ui ($a.Session.Comparison.Metrics.Count -eq 5) 'comparison renders five supplied frame metrics'
                        Save-UiRender '07-benchmark';$script:UiStep++
                    }
                    8 {
                        $c.Navigation.SelectedItem='Histórico / reversão'
                        Assert-Ui ($c.HistoryDetail.Text -match 'DEMO' -and $c.HistoryDetail.Text -match 'REPORTED_MANUALLY' -and $c.TransactionBox.Items.Count -eq 0) 'history distinguishes Demo and unverified manual reports from native transactions'
                        Invoke-UiClick 'ExportButton'
                        Assert-Ui (-not [string]::IsNullOrWhiteSpace($a.LastExport) -and (Test-GoatExport $a.LastExport)) 'UI export produces verified report and recovery package'
                        Assert-Ui ([IO.File]::Exists((Join-Path $a.LastExport 'report.html'))) 'client report exists'
                        $script:UiStep++
                    }
                    9 {
                        $c.Navigation.SelectedItem='Atendimento';Invoke-UiClick 'FinishButton'
                        Assert-Ui ($a.Session.State -eq 'Finalized' -and (Test-GoatExport $a.Session.FinalExport)) 'finish button validates export before marking finalized'
                        Assert-Ui (-not $c.ApplyButton.IsEnabled) 'finalized session cannot apply preferences'
                        $exportCount=$a.Session.Exports.Count;Invoke-UiClick 'FinishButton'
                        Assert-Ui ($a.Session.Exports.Count -eq $exportCount) 'repeated finalization is idempotent'
                        Assert-Ui ([IO.File]::Exists((Join-Path $a.Session.Root 'session.json'))) 'finalization preserves the owned recovery session'
                        $script:UiTimer.Stop();$a.Window.Close();$script:UiStep++
                    }
                }
            }catch{
                $script:UiFailure=($_|Out-String)+"`nUI status: "+$script:GoatApp.Controls.StatusText.Text+"`nPage: "+$script:GoatApp.Page+"`nNavigation: "+$script:GoatApp.Controls.Navigation.SelectedItem+"`nEvents: "+($script:GoatApp.Session.Events|ConvertTo-Json -Depth 5)+"`nHistory: "+$script:GoatApp.Controls.HistoryDetail.Text
                $script:UiTimer.Stop();$script:GoatApp.Window.Close()
            }
        })
        $script:UiTimer.Start()
    }
    Show-GoatApp -Demo:(-not $RealReadOnly) -DataRoot (Join-Path $script:UiFixtureRoot 'sessions')
    if($script:UiFailure){throw $script:UiFailure}
    Assert-Ui ($script:UiStep -eq 10) 'UI workflow completed every stage'
    [pscustomobject]@{Module='UI';Mode=$script:UiSourceMode;RealReadOnly=[bool]$RealReadOnly;LaunchSha256=(Get-FileHash -LiteralPath $launchPath -Algorithm SHA256).Hash.ToLowerInvariant();Passed=$script:UiCheckNames.Count;NavigationPages=$script:UiPages.Count;Checks=$script:UiCheckNames.ToArray();Renders=$ArtifactsRoot;Scope=$(if($RealReadOnly){'Physical read-only UI; no real preference mutation'}else{'WPF Demo workflow with isolated providers; no real preference mutation'})}|ConvertTo-Json -Depth 5
}finally{
    if($script:UiTimer){$script:UiTimer.Stop()}
    $resolved=[IO.Path]::GetFullPath($script:UiFixtureRoot)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'GOAT-UI-Test-*'){throw 'Refusing cleanup outside owned UI fixture directory.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
