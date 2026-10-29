#Requires -Version 5.1
[CmdletBinding()]
param([switch]$Demo,[switch]$ScanOnly,[string]$DataRoot,[string]$SessionPath)
$script:GoatLaunchPath=$PSCommandPath
$script:GoatSources=@{}
foreach($name in @('Core','Gpu','Inventory','Benchmark','Reports','Presentation','App')){
    $script:GoatSources[$name]=Get-Content -LiteralPath (Join-Path $PSScriptRoot ('src\'+$name+'.ps1')) -Raw -Encoding UTF8
}
$script:GoatXaml=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'src\UI.xaml') -Raw -Encoding UTF8
$script:GoatCatalogJson=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'data\catalog.json') -Raw -Encoding UTF8
$script:GoatDocumentsJson=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'data\documents.json') -Raw -Encoding UTF8
. (Join-Path $PSScriptRoot 'src\Entry.ps1')
