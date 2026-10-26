#Requires -Version 5.1
[CmdletBinding()]
param([uri]$Uri)

$ErrorActionPreference = 'Stop'
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    throw 'Execute este teste no Windows PowerShell 5.1 x64: powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Remote.ps1'
}

# This harness never loads src/, mocks Windows APIs, or clicks mutation controls.
# It runs the bundle through Invoke-Expression, as irm <URL> | iex does.
$projectRoot = Split-Path $PSScriptRoot -Parent
$bundlePath = Join-Path $projectRoot 'dist\GOAT-Tweaks.ps1'
$checksumPath = Join-Path $projectRoot 'dist\GOAT-Tweaks.sha256'
$script:GoatRemoteQa = @{
    Passed = New-Object 'System.Collections.Generic.List[string]'
    Failure = ''
    Deadline = (Get-Date).AddSeconds(90)
    Screenshot = ''
    ProjectRoot = $projectRoot
    Source = 'local bundle text'
    Timer = $null
    Completed = $false
}

function Assert-GoatRemote {
    param([bool]$Condition, [string]$Name)
    if (-not $Condition) { throw "REMOTE assertion failed: $Name" }
    $script:GoatRemoteQa.Passed.Add($Name)
}

function Get-GoatRemoteHash {
    param([byte[]]$Bytes)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}

function Save-GoatRemoteCapture {
    param($Window)
    $artifactRoot = Join-Path $script:GoatRemoteQa.ProjectRoot 'artifacts'
    [IO.Directory]::CreateDirectory($artifactRoot) | Out-Null
    $Window.UpdateLayout()
    $width = [int][Math]::Ceiling($Window.ActualWidth)
    $height = [int][Math]::Ceiling($Window.ActualHeight)
    $bitmap = New-Object Windows.Media.Imaging.RenderTargetBitmap($width, $height, 96, 96, [Windows.Media.PixelFormats]::Pbgra32)
    $bitmap.Render($Window)
    $encoder = New-Object Windows.Media.Imaging.PngBitmapEncoder
    $encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($bitmap))
    $name = 'GOAT-Tweaks-inline-local.png'
    if ($Uri) { $name = 'GOAT-Tweaks-inline-remote.png' }
    $path = Join-Path $artifactRoot $name
    $stream = [IO.File]::Create($path)
    try { $encoder.Save($stream) } finally { $stream.Dispose() }
    $script:GoatRemoteQa.Screenshot = $path
}

$previousProtocol = [Net.ServicePointManager]::SecurityProtocol
try {
    if ($Uri) {
        Assert-GoatRemote ($Uri.IsAbsoluteUri -and $Uri.Scheme -eq 'https') 'remote URI uses HTTPS'
        [Net.ServicePointManager]::SecurityProtocol = $previousProtocol -bor [Net.SecurityProtocolType]::Tls12
        $client = New-Object Net.WebClient
        try { $bundleBytes = $client.DownloadData($Uri) } finally { $client.Dispose() }
        # Preserve Invoke-RestMethod's actual response decoding. ASCII bytes make
        # this independent of an HTTP server's UTF-8 charset declaration.
        $bundleText = Invoke-RestMethod -Uri $Uri.AbsoluteUri -Method Get -ErrorAction Stop
        Assert-GoatRemote ($bundleText -is [string]) 'Invoke-RestMethod returned script text'
        $script:GoatRemoteQa.Source = $Uri.AbsoluteUri
    } else {
        $bundleBytes = [IO.File]::ReadAllBytes($bundlePath)
        $bundleText = [Text.Encoding]::ASCII.GetString($bundleBytes)
    }

    Assert-GoatRemote ($bundleBytes.Length -gt 1000) 'bundle is present'
    $hasBom = $bundleBytes.Length -ge 3 -and $bundleBytes[0] -eq 239 -and $bundleBytes[1] -eq 187 -and $bundleBytes[2] -eq 191
    Assert-GoatRemote (-not $hasBom) 'bundle has no UTF-8 BOM for inline execution'
    $nonAscii = @($bundleBytes | Where-Object { $_ -gt 127 }).Count
    Assert-GoatRemote ($nonAscii -eq 0) 'bundle is ASCII and HTTP charset independent'
    $hash = Get-GoatRemoteHash $bundleBytes
    $checksum = [IO.File]::ReadAllText($checksumPath)
    Assert-GoatRemote ($checksum -match '^([0-9a-fA-F]{64})\s+GOAT-Tweaks\.ps1') 'local checksum manifest has expected format'
    $expectedHash = $Matches[1].ToLowerInvariant()
    Assert-GoatRemote ($hash -eq $expectedHash) 'exact bundle bytes match local SHA256 manifest'
    $inlineHash = Get-GoatRemoteHash ([Text.Encoding]::ASCII.GetBytes([string]$bundleText))
    Assert-GoatRemote ($inlineHash -eq $hash) 'inline text exactly matches verified bundle bytes'
    $tokens = $null; $parseErrors = $null
    [Management.Automation.Language.Parser]::ParseInput([string]$bundleText, [ref]$tokens, [ref]$parseErrors) | Out-Null
    Assert-GoatRemote ($parseErrors.Count -eq 0) 'inline bundle parses on Windows PowerShell 5.1'

    $script:GoatUiTestHook = {
        param($window)
        $qaTimer = New-Object Windows.Threading.DispatcherTimer
        $qaTimer.Interval = [TimeSpan]::FromMilliseconds(400)
        $script:GoatRemoteQa.Timer = $qaTimer
        $qaTimer.Add_Tick({
            try {
                $ui = $script:GoatUi
                if ((Get-Date) -gt $script:GoatRemoteQa.Deadline) { throw 'Timeout aguardando diagnóstico e telemetria reais.' }
                if ($ui.Worker -and $ui.Worker.Kind -ne 'Scan') { throw 'O teste remoto permite apenas consulta de hardware.' }
                if ($ui.Worker -or -not $ui.Scan -or $ui.Samples.Count -lt 2) { return }
                Assert-GoatRemote (-not $ui.Demo -and -not $ui.Scan.IsDemo) 'production UI uses real read-only hardware scan'
                Assert-GoatRemote (-not $ui.Controls.DemoBadge.IsVisible) 'production UI is not labeled demonstration'
                Assert-GoatRemote ($ui.Tweaks.Count -eq 33) 'embedded engine returned all 33 reviewed native options'
                Assert-GoatRemote (-not [string]::IsNullOrWhiteSpace([string]$ui.Scan.OS.Caption)) 'real operating system data reached UI'
                Assert-GoatRemote (-not [string]::IsNullOrWhiteSpace([string]$ui.Scan.CPU.Name)) 'real CPU data reached UI'
                $measured = @($ui.Samples | Where-Object { $null -ne $_.CPU -or $null -ne $_.RAM -or $null -ne $_.GPU })
                Assert-GoatRemote ($measured.Count -ge 2) 'live telemetry samples contain available measurements'
                Assert-GoatRemote ($ui.Controls.ChartLine.Points.Count -gt 0) 'live telemetry chart rendered'
                Assert-GoatRemote ($script:GoatXaml.Contains('Visão geral')) 'embedded UTF-8 interface text decoded correctly'
                Assert-GoatRemote ($ui.Repositories.Count -eq 4) 'four embedded original repositories loaded'
                $externalCount=0
                foreach ($repository in $ui.Repositories.Values) { $externalCount+=@($repository.Items).Count }
                Assert-GoatRemote ($externalCount -eq 1330) 'all 1330 embedded original items loaded'
                Assert-GoatRemote ($null -ne $ui.Controls.GoatLogo.Source) 'embedded original logo rendered'
                Assert-GoatRemote (@($ui.Scan.Recommendations).Count -ge 20) 'cross-reference recommendations reached production UI'
                Assert-GoatRemote ($null -ne $ui.Scan.AdvancedState.Readings['memory-compression']) 'RAM compression probe reached production UI'
                Assert-GoatRemote (@($ui.Scan.ToolRecommendations).Count -eq 1330) 'all original library entries compared for this machine'
                Assert-GoatRemote ($null -ne $ui.Scan.AdvancedState.Readings['storage'] -and $null -ne $ui.Scan.AdvancedState.Readings['battery']) 'storage and power context reached production UI'
                Save-GoatRemoteCapture $window
                $script:GoatRemoteQa.Completed = $true
                $script:GoatRemoteQa.Timer.Stop()
                $window.Close()
            } catch {
                $script:GoatRemoteQa.Failure = $_.Exception.Message
                $script:GoatRemoteQa.Timer.Stop()
                if ($script:GoatUi.Window) { $script:GoatUi.Window.Close() }
            }
        })
        $qaTimer.Start()
    }

    # Do not invoke a ScriptBlock or saved file here: the intended entry is IEX.
    # PSScriptRoot points at tests/, which has no src/ tree. The full interface
    # and workers must therefore come from the downloaded embedded payloads.
    Invoke-Expression $bundleText
    if ($script:GoatRemoteQa.Failure) { throw $script:GoatRemoteQa.Failure }
    Assert-GoatRemote $script:GoatRemoteQa.Completed 'inline UI completed, captured and closed automatically'
    [pscustomobject]@{
        Passed = $script:GoatRemoteQa.Passed.Count
        Source = $script:GoatRemoteQa.Source
        SHA256 = $hash
        RealReadOnly = $true
        Screenshot = $script:GoatRemoteQa.Screenshot
    } | ConvertTo-Json -Depth 3
} finally {
    [Net.ServicePointManager]::SecurityProtocol = $previousProtocol
    if ($script:GoatRemoteQa.Timer) { $script:GoatRemoteQa.Timer.Stop() }
    $script:GoatUiTestHook = $null
}
