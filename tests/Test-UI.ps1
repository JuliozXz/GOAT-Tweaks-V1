#Requires -Version 5.1
[CmdletBinding()]
param([switch]$RealReadOnly, [switch]$Bundle)

$ErrorActionPreference='Stop'
$script:GoatRoot=Split-Path $PSScriptRoot -Parent
$script:GoatScannerSource=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'src\Scanner.ps1') -Raw -Encoding UTF8
$script:GoatCoreSource=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'src\Core.ps1') -Raw -Encoding UTF8
$script:GoatAdvancedScannerSource=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'src\AdvancedScanner.ps1') -Raw -Encoding UTF8
$script:GoatRecommendationSource=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'src\Recommendations.ps1') -Raw -Encoding UTF8
$script:GoatRecommendationJson=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'data\recommendations.json') -Raw -Encoding UTF8
$script:GoatIntegrationSource=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'src\Integrations.ps1') -Raw -Encoding UTF8
$script:GoatCatalogJson=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'data\repositories.json') -Raw -Encoding UTF8
$script:GoatLogoBase64=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $script:GoatRoot 'assets\goat-logo.png')))
$script:GoatXaml=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'src\UI.xaml') -Raw -Encoding UTF8
if ($Bundle) {
    . (Join-Path $script:GoatRoot 'dist\GOAT-Tweaks.ps1') -ScanOnly -Demo | Out-Null
    # ScanOnly deliberately skips integrations. Validate the actual bundled module.
    . ([scriptblock]::Create($script:GoatIntegrationSource))
    . ([scriptblock]::Create($script:GoatAdvancedScannerSource))
    . ([scriptblock]::Create($script:GoatRecommendationSource))
    . ([scriptblock]::Create($script:GoatUiSource))
    $script:GoatRoot=Split-Path $PSScriptRoot -Parent
} else {
    . (Join-Path $script:GoatRoot 'src\Core.ps1')
    . (Join-Path $script:GoatRoot 'src\Scanner.ps1')
    . (Join-Path $script:GoatRoot 'src\Integrations.ps1')
    . (Join-Path $script:GoatRoot 'src\AdvancedScanner.ps1')
    . (Join-Path $script:GoatRoot 'src\Recommendations.ps1')
    . (Join-Path $script:GoatRoot 'src\UI.ps1')
}
$script:GoatQa=@{Phase=0;Passed=@();Failure='';Deadline=(Get-Date).AddSeconds(120);ReadOnly=[bool]$RealReadOnly;Screenshots=@();RepositoryCounts=@{};ExternalItemName=''}

function Assert-GoatUi {
    param([bool]$Condition,[string]$Name)
    if (-not $Condition) { throw "UI assertion failed: $Name" }
    $script:GoatQa.Passed += $Name
}

function Save-GoatUiCapture {
    param($Window,[string]$Name)
    $artifacts=Join-Path $script:GoatRoot 'artifacts'
    [IO.Directory]::CreateDirectory($artifacts) | Out-Null
    $Window.UpdateLayout()
    $width=[int][Math]::Ceiling($Window.ActualWidth)
    $height=[int][Math]::Ceiling($Window.ActualHeight)
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($Window)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    if (-not $Name) { $Name=if ($script:GoatQa.ReadOnly) {'GOAT-Tweaks-real.png'} else {'GOAT-Tweaks-demo.png'} }
    $path=Join-Path $artifacts $Name
    $stream=[IO.File]::Create($path)
    try { $encoder.Save($stream) } finally {$stream.Dispose()}
    $script:GoatQa.Screenshots += $path
}

function Test-GoatUiRepositoryPage {
    param([string]$ControlName,[string]$Page,[string]$RepositoryId)
    $ui=$script:GoatUi
    $repository=@((Get-GoatRepositoryCatalog).Repositories | Where-Object Id -eq $RepositoryId)[0]
    $ui.Controls[$ControlName].IsChecked=$true
    Assert-GoatUi ($ui.Page -eq $Page) ("navigation $Page")
    Assert-GoatUi ($ui.CurrentRepository.Id -eq $RepositoryId) ("repository $RepositoryId selected")
    Assert-GoatUi ($ui.Controls.CatalogSection.Visibility -eq 'Visible') ("library $RepositoryId visible")
    Assert-GoatUi ($ui.Controls.CatalogGrid.Items.Count -eq @($repository.Items).Count) ("all $RepositoryId catalog items visible")
    Assert-GoatUi ($ui.Controls.CatalogCount.Text -like ('*de '+@($repository.Items).Count+' itens*')) ("count $RepositoryId matches catalog")
    Assert-GoatUi ($ui.Controls.CatalogGrid.EnableRowVirtualization) ("virtualization $RepositoryId enabled")
    $script:GoatQa.RepositoryCounts[$RepositoryId]=@($repository.Items).Count
    $expectedPrimary=@($repository.Items | Where-Object Id -eq $repository.PrimaryItemId)
    if ($expectedPrimary.Count -gt 0) {
        Assert-GoatUi ($ui.PrimaryItem.Id -eq $expectedPrimary[0].Id) ("official primary $RepositoryId selected")
        Assert-GoatUi ($ui.Controls.CatalogPrimaryButton.Content -like ($expectedPrimary[0].RunLabel+'*')) ("official primary $RepositoryId labeled")
        if ($expectedPrimary[0].LaunchType -eq 'uri') {
            $ui.Controls.CatalogGrid.SelectedItem=$ui.PrimaryItem
            Assert-GoatUi (-not $ui.Controls.CatalogDownloadButton.IsEnabled) 'Store primary has no file download'
            Assert-GoatUi ($ui.Controls.CatalogRunButton.IsEnabled) 'Store page can open without executable privileges'
        } elseif (-not $script:GoatQa.ReadOnly) {
            Assert-GoatUi $ui.Controls.CatalogPrimaryButton.IsEnabled ("demo primary $RepositoryId enabled")
        }
    } else { Assert-GoatUi ($null -eq $ui.PrimaryItem) ("no invented primary for $RepositoryId") }
    $group=@($repository.Items | Group-Object Group | Where-Object {$_.Count -gt 0 -and $_.Count -lt @($repository.Items).Count} | Select-Object -First 1)[0]
    if ($group) {
        $ui.Controls.CatalogGroupFilter.SelectedItem=$group.Name
        Assert-GoatUi ($ui.Controls.CatalogGrid.Items.Count -eq $group.Count) ("folder filter $RepositoryId")
        $ui.Controls.CatalogGroupFilter.SelectedIndex=0
    }
    $type=@($repository.Items | Group-Object Kind | Select-Object -First 1)[0]
    $ui.Controls.CatalogKindFilter.SelectedItem=$type.Name
    Assert-GoatUi ($ui.Controls.CatalogGrid.Items.Count -eq $type.Count) ("type filter $RepositoryId")
    $ui.Controls.CatalogKindFilter.SelectedIndex=0
    $query=[string]$repository.Items[0].Path
    $expected=@($repository.Items | Where-Object { ('{0} {1} {2} {3} {4}' -f $_.Name,$_.Path,$_.Group,$_.Kind,$_.Description).IndexOf($query,[StringComparison]::OrdinalIgnoreCase) -ge 0 }).Count
    $ui.Controls.CatalogSearchBox.Text=$query
    Assert-GoatUi ($ui.Controls.CatalogGrid.Items.Count -eq $expected -and $expected -gt 0) ("search $RepositoryId")
    $ui.Controls.CatalogSearchBox.Text='GOAT-QA-NO-MATCH-'+[Guid]::NewGuid().ToString('N')
    Assert-GoatUi ($ui.Controls.CatalogGrid.Items.Count -eq 0) ("empty search $RepositoryId")
    Assert-GoatUi (-not $ui.Controls.CatalogRunButton.IsEnabled) ("no selected execution $RepositoryId")
    $ui.Controls.CatalogSearchBox.Text=''
    Assert-GoatUi ($ui.Controls.CatalogGrid.Items.Count -eq @($repository.Items).Count) ("reset reveals entire $RepositoryId")
    $item=$ui.Controls.CatalogGrid.SelectedItem
    Assert-GoatUi ($ui.Controls.CatalogItemPath.Text -eq $item.Path) ("exact path $RepositoryId")
    if ($item.Warning) { Assert-GoatUi ($ui.Controls.CatalogItemWarning.Text -eq $item.Warning) ("exact warning $RepositoryId") }
}

$script:GoatUiTestHook={
    param($window)
    $qaTimer=New-Object Windows.Threading.DispatcherTimer
    $qaTimer.Interval=[TimeSpan]::FromMilliseconds(400)
    $script:GoatQa.Timer=$qaTimer
    $qaTimer.Add_Tick({
        try {
            $ui=$script:GoatUi
            if ((Get-Date) -gt $script:GoatQa.Deadline) { throw 'Timeout aguardando scanner/interface.' }
            if ($ui.Worker -or -not $ui.Scan) { return }
            switch ($script:GoatQa.Phase) {
                0 {
                    Assert-GoatUi ($ui.Tweaks.Count -eq 9) 'scanner completed with nine native tweaks including RAM'
                    Assert-GoatUi ($null -ne $ui.Scan.AdvancedState) 'advanced scanner state attached to hardware scan'
                    Assert-GoatUi (@($ui.Scan.Recommendations).Count -gt 0) 'cross-reference recommendations attached to hardware scan'
                    Assert-GoatUi (@($ui.Controls.GetEnumerator() | Where-Object {$_.Key -like 'Nav*' -and $_.Value -is [Windows.Controls.RadioButton]}).Count -eq 13) 'thirteen sidebar areas available'
                    Assert-GoatUi (@($ui.Scan.Recommendations | Where-Object Category -eq 'RAM').Count -gt 0) 'RAM has cross-reference recommendations'
                    foreach ($recommendation in @($ui.Scan.Recommendations)) {
                        Assert-GoatUi ($recommendation.Status -in @('Recomendado','Configurado','Revisão manual','Indisponível')) ('recommendation status '+$recommendation.Id)
                        Assert-GoatUi (-not [string]::IsNullOrWhiteSpace([string]$recommendation.CurrentState)) ('current state '+$recommendation.Id)
                        foreach ($source in @($recommendation.Sources)) {
                            Assert-GoatUi (Test-GoatRecommendationSourceUrl -Url $source.Url) ('HTTPS original evidence '+$recommendation.Id+'/'+$source.RepositoryId)
                        }
                    }
                    Assert-GoatUi ($ui.Scan.IsDemo -eq (-not $script:GoatQa.ReadOnly)) 'scan mode correctly identified'
                    Assert-GoatUi ($ui.Controls.DemoBadge.IsVisible -eq (-not $script:GoatQa.ReadOnly)) 'demo badge is accurate'
                    Assert-GoatUi ($ui.Window.ActualWidth -le [Windows.SystemParameters]::WorkArea.Width) 'window fits screen width'
                    Assert-GoatUi ($ui.Window.ActualHeight -le [Windows.SystemParameters]::WorkArea.Height) 'window fits screen height'
                    Assert-GoatUi ($null -ne $ui.Controls.GoatLogo.Source) 'original logo loaded'
                    Assert-GoatUi ($ui.Window.Background.Color.ToString() -eq '#FF090909') 'black main theme'
                    Assert-GoatUi ($ui.Controls.ApplyButton.Background.Color.ToString() -eq '#FFE4B95B') 'gold action theme'
                    Assert-GoatUi ($ui.Repositories.Count -eq 4) 'four original catalogs loaded'
                    foreach ($entry in @(@('NavCPU','CPU'),@('NavGPU','GPU'),@('NavRAM','RAM'),@('NavBIOS','BIOS'),@('NavNetwork','Network'),@('NavSystem','System'),@('NavGame','Game'),@('NavDrivers','Drivers'),@('NavHome','Home'))) {
                        $ui.Controls[$entry[0]].IsChecked=$true
                        Assert-GoatUi ($ui.Page -eq $entry[1]) ("navigation $($entry[1])")
                        if ($entry[1] -eq 'RAM') {
                            Assert-GoatUi ($ui.Filter -eq 'RAM') 'RAM page filters native actions and recommendations'
                            Assert-GoatUi (@($ui.Checkboxes | Where-Object Tag -eq 'memory-compression').Count -eq 1) 'RAM compression uses existing native checklist'
                            $expectedRam=@($ui.Scan.Recommendations | Where-Object Category -eq 'RAM').Count
                            Assert-GoatUi ($ui.VisibleRecommendations.Count -eq $expectedRam) 'RAM recommendation cards match scanner analysis'
                            Assert-GoatUi ($ui.Controls.RecommendationsPanel.Children.Count -eq $expectedRam) 'RAM recommendation cards rendered'
                        }
                        if ($entry[1] -eq 'Drivers') {
                            Assert-GoatUi ($ui.Controls.CategorySection.Visibility -eq 'Visible') 'Drivers page retains cross-reference analysis'
                            Assert-GoatUi ($ui.VisibleRecommendations.Count -eq @($ui.Scan.Recommendations | Where-Object Category -eq 'Drivers').Count) 'Drivers recommendation cards match scanner analysis'
                        }
                        if ($entry[1] -eq 'CPU') {
                            $architectureText=[string]$ui.Scan.AdvancedState.Readings['cpu-architecture'].Text
                            $renderedCpu=@($ui.Controls.FindingsPanel.Children[0].Child.Children | ForEach-Object Text) -join ' '
                            Assert-GoatUi ($architectureText -and $renderedCpu.Contains($architectureText)) 'CPU findings render reported architecture'
                        }
                    }
                    foreach ($entry in @(@('GpuTab','GPU'),@('RamTab','RAM'),@('CpuTab','CPU'))) {
                        $ui.Controls[$entry[0]].IsChecked=$true
                        Assert-GoatUi ($ui.Metric -eq $entry[1]) ("metric $($entry[1])")
                    }
                    foreach ($entry in @(@('NavWinutil','Winutil','winutil'),@('NavWinSux','WinSux','winsux'),@('NavUltimate','Ultimate','ultimate'),@('NavRyTuneX','RyTuneX','rytunex'))) {
                        Test-GoatUiRepositoryPage -ControlName $entry[0] -Page $entry[1] -RepositoryId $entry[2]
                    }
                    $ui.Controls.NavHome.IsChecked=$true
                    $script:GoatQa.Phase=1
                }
                1 {
                    if ($ui.Samples.Count -lt 3) {return}
                    Assert-GoatUi ($ui.Controls.ChartLine.Points.Count -gt 0) 'chart contains telemetry samples'
                    Save-GoatUiCapture $ui.Window
                    if ($script:GoatQa.ReadOnly) { $script:GoatQa.Phase=7; return }
                    Assert-GoatUi ($ui.Demo -eq $true) 'mutating test actions limited to Demo'
                    Assert-GoatUi ($ui.Controls.ApplyButton.IsEnabled) 'demo apply button enabled for recommendations'
                    $ui.Controls.ApplyButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                    Assert-GoatUi ($ui.Worker.Kind -eq 'Apply') 'apply dispatched off UI thread'
                    $script:GoatQa.Phase=2
                }
                2 {
                    Assert-GoatUi ($ui.Controls.StatusText.Text -match 'Simula') 'demo apply completed'
                    $ui.Controls.RestoreButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                    Assert-GoatUi ($ui.Worker.Kind -eq 'Restore') 'restore dispatched off UI thread'
                    $script:GoatQa.Phase=3
                }
                3 {
                    Assert-GoatUi ($ui.Controls.StatusText.Text -match 'Simula') 'demo restore completed'
                    $ui.Controls.RescanButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                    Assert-GoatUi ($ui.Worker.Kind -eq 'Scan') 'rescan dispatched off UI thread'
                    $script:GoatQa.Phase=4
                }
                4 {
                    Assert-GoatUi ($ui.Controls.ScannerBadge.Text -match 'CONCLU|PRONTO|ANALISADO') 'scan status rendered'
                    Assert-GoatUi ($ui.Demo -eq $true) 'external execution test limited to Demo'
                    $ui.Controls.NavWinutil.IsChecked=$true
                    $script:GoatQa.ExternalItemName=[string]$ui.PrimaryItem.Name
                    $ui.Controls.CatalogPrimaryButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                    Assert-GoatUi ($ui.Worker.Kind -eq 'Integration' -and $ui.Worker.ExternalAction -eq 'Run') 'external Run dispatched off UI thread in Demo'
                    Assert-GoatUi (-not $ui.Controls.CatalogRunButton.IsEnabled -and -not $ui.Controls.CatalogDownloadButton.IsEnabled) 'external actions disabled while worker is busy'
                    $script:GoatQa.Phase=5
                }
                5 {
                    Assert-GoatUi ($ui.Controls.CatalogOperationStatus.Text -match 'Demonstração: Run' -and $ui.Controls.CatalogOperationStatus.Text.Contains($script:GoatQa.ExternalItemName)) 'external Run completed in Demo only'
                    Assert-GoatUi ($ui.Controls.CatalogOpenFolderButton.Visibility -eq 'Collapsed') 'demo Run created no downloaded path'
                    $item=@($ui.CurrentRepository.Items | Where-Object {$_.Operation -in @('RepositoryFile','ReleaseAsset') -and $_.DownloadUrl} | Select-Object -First 1)[0]
                    $ui.Controls.CatalogGrid.SelectedItem=$item
                    $script:GoatQa.ExternalItemName=[string]$item.Name
                    Assert-GoatUi $ui.Controls.CatalogDownloadButton.IsEnabled 'original file can be downloaded'
                    $ui.Controls.CatalogDownloadButton.RaiseEvent((New-Object Windows.RoutedEventArgs([Windows.Controls.Button]::ClickEvent)))
                    Assert-GoatUi ($ui.Worker.Kind -eq 'Integration' -and $ui.Worker.ExternalAction -eq 'Download') 'external Download dispatched off UI thread in Demo'
                    $script:GoatQa.Phase=6
                }
                6 {
                    Assert-GoatUi ($ui.Controls.CatalogOperationStatus.Text -match 'Demonstração: Download' -and $ui.Controls.CatalogOperationStatus.Text.Contains($script:GoatQa.ExternalItemName)) 'external Download completed in Demo only'
                    Assert-GoatUi ($ui.Controls.CatalogOpenFolderButton.Visibility -eq 'Collapsed') 'demo Download created no downloaded path'
                    $script:GoatQa.Phase=7
                }
                7 {
                    $ui.Controls.NavWinutil.IsChecked=$true
                    $ui.Controls.CatalogGrid.SelectedItem=$ui.PrimaryItem
                    $ui.Controls.CatalogGrid.ScrollIntoView($ui.PrimaryItem)
                    $ui.Window.UpdateLayout()
                    $columnWidths=@($ui.Controls.CatalogGrid.Columns | ForEach-Object ActualWidth)
                    Assert-GoatUi ($columnWidths[1] -ge 80) 'catalog type column remains visible after filtering and navigation'
                    Assert-GoatUi (($columnWidths | Measure-Object -Sum).Sum -ge ($ui.Controls.CatalogGrid.ActualWidth-24)) 'catalog columns fill table viewport'
                    foreach ($buttonName in @('CatalogViewSourceButton','CatalogDownloadButton','CatalogRunButton')) {
                        Assert-GoatUi (-not $ui.Controls[$buttonName].IsDescendantOf($ui.Controls.CatalogDetailsScroll)) ("fixed detail action $buttonName")
                    }
                    Save-GoatUiCapture -Window $ui.Window -Name 'GOAT-Tweaks-library.png'
                    $ui.Controls.NavRAM.IsChecked=$true
                    Save-GoatUiCapture -Window $ui.Window -Name 'GOAT-Tweaks-RAM-page.png'
                    $script:GoatQa.Phase=8
                }
                8 {
                    $ui.Window.UpdateLayout()
                    $categoryTop=$ui.Controls.CategorySection.TranslatePoint((New-Object Windows.Point 0,0),$ui.Controls.MainScroll.Content).Y
                    $ui.Controls.MainScroll.ScrollToVerticalOffset($categoryTop)
                    $script:GoatQa.Phase=9
                }
                9 {
                    Save-GoatUiCapture -Window $ui.Window -Name 'GOAT-Tweaks-RAM-analysis.png'
                    $script:GoatQa.Timer.Stop()
                    $ui.Window.Close()
                }
            }
        } catch {
            $script:GoatQa.Failure=$_.Exception.Message
            $script:GoatQa.Timer.Stop()
            # Tests only ever launch demo mutations; never interrupt a real operation.
            $script:GoatUi.Window.Close()
        }
    })
    $qaTimer.Start()
}

Show-GoatWindow -Demo:(-not $RealReadOnly)
if ($script:GoatQa.Failure) { throw $script:GoatQa.Failure }
[pscustomobject]@{ Passed=$script:GoatQa.Passed.Count; Checks=$script:GoatQa.Passed; RealReadOnly=[bool]$RealReadOnly; Bundle=[bool]$Bundle; RepositoryCounts=$script:GoatQa.RepositoryCounts; Screenshots=$script:GoatQa.Screenshots } | ConvertTo-Json -Depth 4
