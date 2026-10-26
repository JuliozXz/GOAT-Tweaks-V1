# Shared entry for source tree and self-contained build.
if ($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess -or [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    if (-not $script:GoatLaunchPath -or -not (Test-Path -LiteralPath $script:GoatLaunchPath)) {
        throw 'Execute o comando remoto no Windows PowerShell 5.1 de 64 bits (powershell.exe), em modo STA. Para PowerShell 7, salve o arquivo e execute: powershell.exe -NoProfile -STA -File .\GOAT-Tweaks.ps1'
    }
    $hostPath = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not [Environment]::Is64BitProcess) { $hostPath = Join-Path $env:SystemRoot 'Sysnative\WindowsPowerShell\v1.0\powershell.exe' }
    $launchArgs = @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',$script:GoatLaunchPath)
    if ($Demo) { $launchArgs += '-Demo' }
    if ($ScanOnly) { $launchArgs += '-ScanOnly' }
    & $hostPath @launchArgs
    return
}

. ([scriptblock]::Create($script:GoatCoreSource))
. ([scriptblock]::Create($script:GoatScannerSource))
. ([scriptblock]::Create($script:GoatAdvancedScannerSource))
. ([scriptblock]::Create($script:GoatRecommendationSource))
if ($ScanOnly) {
    Get-GoatUnifiedScan -Demo:$Demo | ConvertTo-Json -Depth 16
    return
}
. ([scriptblock]::Create($script:GoatIntegrationSource))
. ([scriptblock]::Create($script:GoatUiSource))
Show-GoatWindow -Demo:$Demo
