#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Demo, [switch]$ScanOnly)

$script:GoatRoot = $PSScriptRoot
$script:GoatLaunchPath = $PSCommandPath
$script:GoatScannerSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\Scanner.ps1') -Raw -Encoding UTF8
$script:GoatCoreSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\Core.ps1') -Raw -Encoding UTF8
$script:GoatUiSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\UI.ps1') -Raw -Encoding UTF8
$script:GoatXaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\UI.xaml') -Raw -Encoding UTF8
. (Join-Path $PSScriptRoot 'src\Entry.ps1')
