#Requires -Version 5.1
[CmdletBinding()]
param([switch]$RealReadOnly, [switch]$Bundle)

$ErrorActionPreference='Stop'
$script:GoatRoot=Split-Path $PSScriptRoot -Parent
$script:GoatScannerSource=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'src\Scanner.ps1') -Raw -Encoding UTF8
$script:GoatCoreSource=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'src\Core.ps1') -Raw -Encoding UTF8
$script:GoatXaml=Get-Content -LiteralPath (Join-Path $script:GoatRoot 'src\UI.xaml') -Raw -Encoding UTF8
if ($Bundle) {
    . (Join-Path $script:GoatRoot 'dist\GOAT-Tweaks.ps1') -ScanOnly -Demo | Out-Null
    . ([scriptblock]::Create($script:GoatUiSource))
    $script:GoatRoot=Split-Path $PSScriptRoot -Parent
} else {
    . (Join-Path $script:GoatRoot 'src\Core.ps1')
    . (Join-Path $script:GoatRoot 'src\Scanner.ps1')
    . (Join-Path $script:GoatRoot 'src\UI.ps1')
}
$script:GoatQa=@{Phase=0;Passed=@();Failure='';Deadline=(Get-Date).AddSeconds(90);ReadOnly=[bool]$RealReadOnly}

function Assert-GoatUi {
    param([bool]$Condition,[string]$Name)
    if (-not $Condition) { throw "UI assertion failed: $Name" }
    $script:GoatQa.Passed += $Name
}

function Save-GoatUiCapture {
    param($Window)
    $artifacts=Join-Path $script:GoatRoot 'artifacts'
    [IO.Directory]::CreateDirectory($artifacts) | Out-Null
    $Window.UpdateLayout()
    $width=[int][Math]::Ceiling($Window.ActualWidth)
    $height=[int][Math]::Ceiling($Window.ActualHeight)
    $bitmap=New-Object Windows.Media.Imaging.RenderTargetBitmap($width,$height,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($Window)
    $encoder=New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $name='GOAT-Tweaks-demo.png'; if ($script:GoatQa.ReadOnly) { $name='GOAT-Tweaks-real.png' }
    $path=Join-Path $artifacts $name
    $stream=[IO.File]::Create($path)
    try { $encoder.Save($stream) } finally {$stream.Dispose()}
    $script:GoatQa.Screenshot=$path
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
                    Assert-GoatUi ($ui.Tweaks.Count -eq 8) 'scanner completed with catalog'
                    Assert-GoatUi ($ui.Scan.IsDemo -eq (-not $script:GoatQa.ReadOnly)) 'scan mode correctly identified'
                    Assert-GoatUi ($ui.Controls.DemoBadge.IsVisible -eq (-not $script:GoatQa.ReadOnly)) 'demo badge is accurate'
                    Assert-GoatUi ($ui.Window.ActualWidth -le [Windows.SystemParameters]::WorkArea.Width) 'window fits screen width'
                    foreach ($entry in @(@('NavCPU','CPU'),@('NavGPU','GPU'),@('NavBIOS','BIOS'),@('NavNetwork','Network'),@('NavSystem','System'),@('NavGame','Game'),@('NavDrivers','Drivers'),@('NavHome','Home'))) {
                        $ui.Controls[$entry[0]].IsChecked=$true
                        Assert-GoatUi ($ui.Page -eq $entry[1]) ("navigation $($entry[1])")
                    }
                    foreach ($entry in @(@('GpuTab','GPU'),@('RamTab','RAM'),@('CpuTab','CPU'))) {
                        $ui.Controls[$entry[0]].IsChecked=$true
                        Assert-GoatUi ($ui.Metric -eq $entry[1]) ("metric $($entry[1])")
                    }
                    $script:GoatQa.Phase=1
                }
                1 {
                    if ($ui.Samples.Count -lt 3) {return}
                    Assert-GoatUi ($ui.Controls.ChartLine.Points.Count -gt 0) 'chart contains telemetry samples'
                    Save-GoatUiCapture $ui.Window
                    if ($script:GoatQa.ReadOnly) { $script:GoatQa.Phase=4; return }
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
[pscustomobject]@{ Passed=$script:GoatQa.Passed.Count; Checks=$script:GoatQa.Passed; RealReadOnly=[bool]$RealReadOnly; Screenshot=$script:GoatQa.Screenshot } | ConvertTo-Json -Depth 4
