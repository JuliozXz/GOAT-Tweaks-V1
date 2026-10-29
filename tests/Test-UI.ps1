#Requires -Version 5.1
[CmdletBinding()]
param([string]$Bundle,[string]$ArtifactsRoot)
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
$script:UiPages=@()
$script:UiStarted=[DateTime]::UtcNow
$script:UiFileQueue=New-Object 'System.Collections.Generic.Queue[string]'
$script:UiArtifactRoot=$ArtifactsRoot
$script:UiSourceMode=if($Bundle){'BUNDLED'}else{'SOURCE'}
$launchPath=if($Bundle){[IO.Path]::GetFullPath($Bundle)}else{Join-Path $projectRoot 'GOAT-Tweaks.ps1'}
function Assert-Ui {param([bool]$Condition,[string]$Name);if(-not $Condition){throw ('UI assertion: '+$Name)};$script:UiCheckNames.Add($Name)}
function Invoke-UiClick {param([string]$Name);$button=$script:GoatApp.Controls[$Name];if(-not $button){throw ('Missing button: '+$Name)};$button.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
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
                switch($script:UiStep){
                    0 {
                        Assert-Ui ($a.Session.Demo -and $a.Session.Inventory.Demo -and $a.Session.Inventory.ReadOnly) 'Demo inventory is explicitly simulated/read-only'
                        Assert-Ui ($a.Session.Inventory.GpuCenter.Devices.Count -eq 1) 'GPU inventory reaches real WPF view'
                        Assert-Ui ($c.CpuSummary.Text.Length -gt 0 -and $c.GpuSummary.Text -match 'exemplo') 'hardware cards populated from Demo data'
                        Assert-Ui ($c.DiagnosisPanel.Children.Count -gt 0) 'diagnosis cards populate'
                        Assert-Ui ($c.Navigation.Items.Count -ge 15) 'complete application navigation available'
                        $script:UiPages=@($c.Navigation.ItemsSource)
                        Save-UiRender '01-overview'
                        $script:UiStep++
                    }
                    1 {
                        if($script:UiNavigationIndex -lt $script:UiPages.Count){
                            $page=$script:UiPages[$script:UiNavigationIndex]
                            $c.Navigation.SelectedItem=$page
                            Assert-Ui ($a.Page -eq $page -and $c.PageTitle.Text -eq $page) ('navigation: '+$page)
                            $visible=@('Overview','Service','Catalog','Gpu','Profiles','Actions','Benchmarks','History','Documents','Detail'|Where-Object{$c[$_+'Page'].Visibility -eq 'Visible'})
                            Assert-Ui ($visible.Count -eq 1) ('one content surface visible: '+$page)
                            if($page -eq 'GPU CENTER'){Save-UiRender '02-gpu-center'}
                            $script:UiNavigationIndex++
                        }else{$script:UiStep++}
                    }
                    2 {
                        $c.Navigation.SelectedItem='Catálogo completo'
                        Assert-Ui ($c.CatalogGrid.Items.Count -eq 344) 'catalog renders every documented ID'
                        $c.ClassBox.SelectedItem='X_BLOCKED'
                        Assert-Ui ($c.CatalogGrid.Items.Count -eq 41) 'blocked class filter is accurate'
                        $c.ClassBox.SelectedIndex=0;$c.CatalogSearch.Text='WIN-GAMEMODE'
                        Assert-Ui ($c.CatalogGrid.Items.Count -eq 1) 'catalog ID search works'
                        $c.CatalogGrid.SelectedIndex=0
                        Assert-Ui ($c.CatalogDetail.Text -match 'SPEC_ONLY_NOT_YET_VERIFIED' -and $c.CatalogDetail.Text -match 'apply_allowed') 'catalog detail exposes inactive implementation gate'
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
                        $c.Navigation.SelectedItem='Atendimento'
                        $c.ObjectiveBox.SelectedItem='Competitivo';$c.ServiceModeBox.SelectedItem='Remoto';$c.ConsentBox.IsChecked=$true
                        Invoke-UiClick 'SaveSessionButton'
                        Assert-Ui ($a.Session.Objective -eq 'Competitivo' -and $a.Session.Mode -eq 'Remoto' -and $a.Session.Consent) 'service context persists from controls'
                        $c.Navigation.SelectedItem='GPU CENTER';Invoke-UiClick 'GpuGuideButton'
                        Assert-Ui ($c.GpuDetail.Text -match 'BLOCKED' -and $c.GpuDetail.Text -match 'gpu-ddu') 'remote DDU guide remains blocked in UI'
                        $script:UiStep++
                    }
                    5 {
                        $c.Navigation.SelectedItem='Windows / preferências'
                        $c.ActionsList.SelectedIndex=0;Invoke-UiClick 'PreviewButton'
                        Assert-Ui ($a.Preview.Count -eq 1 -and $c.ActionDetail.Text -match 'HideFileExt') 'Demo action preview contains exact preference'
                        $c.ActionConsent.IsChecked=$true;Invoke-UiClick 'ApplyButton'
                        Assert-Ui (@($a.Session.Events|Where-Object Kind -eq 'DEMO').Count -eq 1) 'Demo click records simulation'
                        Assert-Ui (@(Get-GoatTransactions $a.Session).Count -eq 0) 'Demo action creates no real mutation journal'
                        Assert-Ui ($c.ActionDetail.Text -match 'DEMO' -and $a.Preview.Count -eq 0) 'Demo success is visibly simulated and consumes preview'
                        Save-UiRender '05-demo-actions';$script:UiStep++
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
                        foreach($condition in @('Baseline','After')){
                            $c.ConditionLabelBox.SelectedItem=$condition
                            foreach($pass in 1..3){$script:UiFileQueue.Enqueue((Join-Path $script:UiFixtureRoot ($condition+'-'+$pass+'.csv')));Invoke-UiClick 'ImportCaptureButton'}
                        }
                        Assert-Ui ($a.Session.Benchmarks.Count -eq 6) 'six original benchmark captures imported through UI'
                        Invoke-UiClick 'CompareButton'
                        Assert-Ui ($a.Session.Comparison.Status -eq 'INCONCLUSIVE') 'UI does not confirm benefit without stability verification'
                        Assert-Ui ($a.Session.Comparison.Metrics.Count -eq 5) 'comparison renders five supplied frame metrics'
                        Save-UiRender '07-benchmark';$script:UiStep++
                    }
                    8 {
                        $c.Navigation.SelectedItem='Histórico / reversão'
                        Assert-Ui ($c.HistoryDetail.Text -match 'DEMO' -and $c.TransactionBox.Items.Count -eq 0) 'history distinguishes Demo event from native transaction'
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
    Show-GoatApp -Demo -DataRoot (Join-Path $script:UiFixtureRoot 'sessions')
    if($script:UiFailure){throw $script:UiFailure}
    Assert-Ui ($script:UiStep -eq 10) 'UI workflow completed every stage'
    [pscustomobject]@{Module='UI';Mode=$script:UiSourceMode;LaunchSha256=(Get-FileHash -LiteralPath $launchPath -Algorithm SHA256).Hash.ToLowerInvariant();Passed=$script:UiCheckNames.Count;NavigationPages=$script:UiPages.Count;Checks=$script:UiCheckNames.ToArray();Renders=$ArtifactsRoot;Scope='WPF Demo smoke workflow; no physical hardware or real preference mutation'}|ConvertTo-Json -Depth 5
}finally{
    if($script:UiTimer){$script:UiTimer.Stop()}
    $resolved=[IO.Path]::GetFullPath($script:UiFixtureRoot)
    $tempRoot=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar
    if(-not $resolved.StartsWith($tempRoot,[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'GOAT-UI-Test-*'){throw 'Refusing cleanup outside owned UI fixture directory.'}
    Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
}
