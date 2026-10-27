#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Demo, [switch]$ScanOnly)

$script:GoatRoot = $PSScriptRoot
$script:GoatLaunchPath = $PSCommandPath
$script:GoatScannerSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\Scanner.ps1') -Raw -Encoding UTF8
$script:GoatGpuCenterSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\GpuCenter.ps1') -Raw -Encoding UTF8
$script:GoatAdvancedScannerSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\AdvancedScanner.ps1') -Raw -Encoding UTF8
$script:GoatRecommendationSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\Recommendations.ps1') -Raw -Encoding UTF8
$script:GoatRecommendationJson = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'data\recommendations.json') -Raw -Encoding UTF8
$script:GoatSelectionSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\Selection.ps1') -Raw -Encoding UTF8
$script:GoatToolAdvisorSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\ToolAdvisor.ps1') -Raw -Encoding UTF8
$script:GoatNativeOptionsJson = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'data\native-options.json') -Raw -Encoding UTF8
$script:GoatToolRulesJson = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'data\tool-rules.json') -Raw -Encoding UTF8
$script:GoatCoreSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\Core.ps1') -Raw -Encoding UTF8
$script:GoatUiSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\UI.ps1') -Raw -Encoding UTF8
$script:GoatXaml = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\UI.xaml') -Raw -Encoding UTF8
$script:GoatIntegrationSource = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\Integrations.ps1') -Raw -Encoding UTF8
$script:GoatCatalogJson = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'data\repositories.json') -Raw -Encoding UTF8
$script:GoatLogoBase64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'assets\goat-logo.png')))
. (Join-Path $PSScriptRoot 'src\Entry.ps1')
