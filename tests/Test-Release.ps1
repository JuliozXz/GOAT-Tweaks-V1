#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$checks=0
function Assert-Release {param([bool]$Condition,[string]$Name);if(-not $Condition){throw $Name};$script:checks++}
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw -Encoding UTF8).Trim()
$bundle=Join-Path $root 'dist/GOAT-Tweaks.ps1'
$manifest=Get-Content -LiteralPath (Join-Path $root 'dist/build-manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$launch=Get-Content -LiteralPath (Join-Path $root 'dist/launch.json') -Raw -Encoding UTF8|ConvertFrom-Json
$hash=(Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
Assert-Release ($version -match '^\d+\.\d+\.\d+$' -and $manifest.Version -eq $version -and $manifest.Channel -eq 'Official') 'Published version and channel match VERSION'
Assert-Release ($hash -eq $manifest.BundleSha256 -and $hash -eq $launch.Sha256) 'Build and launch metadata pin the exact same bundle'
Assert-Release ((Get-Content -LiteralPath (Join-Path $root 'dist/GOAT-Tweaks.sha256')).Split(' ')[0] -eq $hash) 'Distribution checksum matches app bytes'
Assert-Release (@([IO.File]::ReadAllBytes($bundle)|Where-Object {$_ -gt 127}).Count -eq 0) 'Self-contained transport remains ASCII for PowerShell 5.1'
foreach($source in $manifest.Sources){Assert-Release ((Get-FileHash -LiteralPath (Join-Path $root $source.Path) -Algorithm SHA256).Hash -eq $source.Sha256) ('Build provenance: '+$source.Path)}
. $bundle -Demo -ScanOnly|Out-Null
Assert-Release ($script:GoatVersion -eq $version) 'Executable bundle reports official version'
foreach($name in @('Core','Gpu','Inventory','AdvancedGuides','Power','Runtime','Benchmark','Reports','Presentation','App')){
    Assert-Release ($script:GoatSources[$name] -ceq (Get-Content -LiteralPath (Join-Path $root ('src/'+$name+'.ps1')) -Raw -Encoding UTF8)) ('Packed module equals reviewed source: '+$name)
}
Assert-Release ($script:GoatXaml -ceq (Get-Content -LiteralPath (Join-Path $root 'src/UI.xaml') -Raw -Encoding UTF8)) 'Packed WPF equals reviewed XAML'
Assert-Release ($script:GoatCatalogJson -ceq (Get-Content -LiteralPath (Join-Path $root 'data/catalog.json') -Raw -Encoding UTF8)) 'Packed catalog equals current normative import'
Assert-Release ($script:GoatDocumentsJson -ceq (Get-Content -LiteralPath (Join-Path $root 'data/documents.json') -Raw -Encoding UTF8)) 'Packed documents preserve imported corpus'
$released=@(Get-GoatActions|Where-Object ReleaseEnabled)
Assert-Release ($released.Count -eq 16 -and @($released|Where-Object {$_.ExecutorKind -ne 'RegistryValue' -or $_.Status -ne 'IMPLEMENTED_AND_TESTED' -or -not $_.ValidationScope -or -not $_.Sources.Count}).Count -eq 0) 'Released native actions have explicit executors, validation scope and primary sources'
Assert-Release (@(Get-GoatAdvancedGuides -Catalog (($script:GoatCatalogJson|ConvertFrom-Json).controls)).Count -eq 50) 'All previously blocked catalog procedures are included'
Assert-Release ($script:GoatSources.App -notmatch 'PRÉVIA DE ENGENHARIA' -and $script:GoatXaml -notmatch 'PRÉVIA DE ENGENHARIA') 'Runtime interface no longer carries product preview status'
. (Join-Path $root 'scripts/New-LaunchCommand.ps1')
Assert-Release ($launch.Command -ceq (Get-GoatLaunchCommand -Version $version -Sha256 $hash)) 'Published one-line command is generated from reviewed launcher'
Assert-Release ((Get-Content -LiteralPath (Join-Path $root 'dist/Open-GOAT.txt') -Raw -Encoding UTF8).Trim() -ceq $launch.Command) 'Copy-and-paste command is consistent with metadata'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::OpenRead((Join-Path $root ('dist/GOAT-Tweaks-'+$version+'.zip')))
try{
    $names=@($archive.Entries|ForEach-Object FullName)
    Assert-Release (@($names|Select-Object -Unique).Count -eq $names.Count) 'Release ZIP contains no duplicate entries'
    foreach($name in @('GOAT-Tweaks.ps1','GOAT-Tweaks.sha256','build-manifest.json','Open-GOAT.txt','launch.json','VERSION','README.md','docs/FEATURE-MATRIX.md','docs/VALIDATION.md','docs/THIRD-PARTY-NOTICES.md',('docs/RELEASE-'+$version+'.md'),'docs/ADVANCED-ACTIONS.md','docs/POWER-ACTIONS.md','docs/audit/RELEASE-REVIEW.md')){Assert-Release ($names -contains $name) ('Release archive contains '+$name)}
    $stream=($archive.Entries|Where-Object FullName -eq 'GOAT-Tweaks.ps1').Open();$sha=[Security.Cryptography.SHA256]::Create()
    try{$zipHash=([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','').ToLowerInvariant()}finally{$stream.Dispose();$sha.Dispose()}
    Assert-Release ($zipHash -eq $hash) 'ZIP app and individually distributed app are byte-identical'
}finally{$archive.Dispose()}
[pscustomobject]@{Module='Release';Passed=$checks;Version=$version;BundleSha256=$hash;Scope='Distribution contracts and packed-source equality; no Windows changes'}|ConvertTo-Json
