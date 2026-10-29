#Requires -Version 5.1
[CmdletBinding()]
param([string]$ProjectRoot)
$ErrorActionPreference='Stop'
if(-not $ProjectRoot){$ProjectRoot=Split-Path $PSScriptRoot -Parent}
$root=[IO.Path]::GetFullPath($ProjectRoot);$dist=Join-Path $root 'dist';[void][IO.Directory]::CreateDirectory($dist)
$version=(Get-Content -LiteralPath (Join-Path $root 'VERSION') -Raw -Encoding UTF8).Trim()
if($version -notmatch '^\d+\.\d+\.\d+$'){throw 'VERSION precisa conter uma versao oficial SemVer.'}
$utf8=[Text.UTF8Encoding]::new($false)
function ConvertTo-GoatPackedResource([string]$Content){
    $memory=[IO.MemoryStream]::new();$gzip=[IO.Compression.GZipStream]::new($memory,[IO.Compression.CompressionMode]::Compress,$true)
    try{$bytes=[Text.Encoding]::UTF8.GetBytes($Content);$gzip.Write($bytes,0,$bytes.Length)}finally{$gzip.Dispose()}
    $result=[Convert]::ToBase64String($memory.ToArray());$memory.Dispose();return $result
}
$parts=[Collections.Generic.List[string]]::new()
$parts.Add(@'
#Requires -Version 5.1
# GOAT Tweaks __VERSION__. Original application built from the supplied specification.
# Self-contained, offline resources. No network bootstrap and no automatic tweaks.
[CmdletBinding()]
param([switch]$Demo,[switch]$ScanOnly,[string]$DataRoot,[string]$SessionPath)
$script:GoatLaunchPath=$PSCommandPath
$script:GoatVersion='__VERSION__'
function Read-GoatPackedResource([string]$Value){
    $memory=[IO.MemoryStream]::new([Convert]::FromBase64String($Value))
    $gzip=[IO.Compression.GZipStream]::new($memory,[IO.Compression.CompressionMode]::Decompress)
    $reader=[IO.StreamReader]::new($gzip,[Text.Encoding]::UTF8)
    try{$reader.ReadToEnd()}finally{$reader.Dispose();$gzip.Dispose();$memory.Dispose()}
}
$script:GoatSources=@{}
'@.Replace('__VERSION__',$version))
$manifest=@()
foreach($name in @('Core','Gpu','Inventory','AdvancedGuides','Power','Runtime','Benchmark','Reports','Presentation','App')){
    $file=Join-Path $root ('src\'+$name+'.ps1');$source=Get-Content -LiteralPath $file -Raw -Encoding UTF8
    $errors=$null;$tokens=$null;[void][Management.Automation.Language.Parser]::ParseInput($source,[ref]$tokens,[ref]$errors)
    if($errors.Count){throw ($errors|Out-String)}
    $parts.Add("`$script:GoatSources['$name']=Read-GoatPackedResource '"+(ConvertTo-GoatPackedResource $source)+"'")
    $manifest+=[pscustomobject]@{Path='src/'+$name+'.ps1';Sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
}
foreach($resource in @(@{Name='GoatXaml';Path='src/UI.xaml'},@{Name='GoatCatalogJson';Path='data/catalog.json'},@{Name='GoatDocumentsJson';Path='data/documents.json'})){
    $file=Join-Path $root $resource.Path;$content=Get-Content -LiteralPath $file -Raw -Encoding UTF8
    $parts.Add('$script:'+$resource.Name+"=Read-GoatPackedResource '"+(ConvertTo-GoatPackedResource $content)+"'")
    $manifest+=[pscustomobject]@{Path=$resource.Path;Sha256=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash}
}
$entry=Get-Content -LiteralPath (Join-Path $root 'src/Entry.ps1') -Raw -Encoding UTF8
$parts.Add(". ([scriptblock]::Create((Read-GoatPackedResource '"+(ConvertTo-GoatPackedResource $entry)+"')))")
$bundle=Join-Path $dist 'GOAT-Tweaks.ps1';[IO.File]::WriteAllText($bundle,($parts -join "`r`n`r`n"),[Text.Encoding]::ASCII)
$errors=$null;$tokens=$null;[void][Management.Automation.Language.Parser]::ParseFile($bundle,[ref]$tokens,[ref]$errors)
if($errors.Count){throw ($errors|Out-String)}
$hash=(Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $dist 'GOAT-Tweaks.sha256'),$hash+'  GOAT-Tweaks.ps1'+"`r`n",$utf8)
$manifest+=[pscustomobject]@{Path='src/Entry.ps1';Sha256=(Get-FileHash -LiteralPath (Join-Path $root 'src/Entry.ps1') -Algorithm SHA256).Hash}
foreach($supportFile in @('VERSION','scripts/Build.ps1','scripts/New-LaunchCommand.ps1')){$manifest+=[pscustomobject]@{Path=$supportFile;Sha256=(Get-FileHash -LiteralPath (Join-Path $root $supportFile) -Algorithm SHA256).Hash}}
[IO.File]::WriteAllText((Join-Path $dist 'build-manifest.json'),([pscustomobject]@{Version=$version;Channel='Official';BundleSha256=$hash;Sources=$manifest}|ConvertTo-Json -Depth 6),$utf8)
. (Join-Path $root 'scripts/New-LaunchCommand.ps1')
$command=Get-GoatLaunchCommand -Version $version -Sha256 $hash
[IO.File]::WriteAllText((Join-Path $dist 'Open-GOAT.txt'),$command+"`r`n",$utf8)
$launch=[pscustomobject]@{Version=$version;Sha256=$hash;DownloadUrl=('https://github.com/JuliozXz/GOAT-Tweaks-V1/releases/download/v'+$version+'/GOAT-Tweaks.ps1');Command=$command;DemoCommand=(Get-GoatLaunchCommand -Version $version -Sha256 $hash -Demo);ScanCommand=(Get-GoatLaunchCommand -Version $version -Sha256 $hash -Demo -ScanOnly)}
[IO.File]::WriteAllText((Join-Path $dist 'launch.json'),($launch|ConvertTo-Json -Depth 4),$utf8)
$packageRoot=Join-Path $dist ('package/'+[guid]::NewGuid().ToString('N'));[void][IO.Directory]::CreateDirectory($packageRoot)
$files=@()
foreach($file in @($bundle,(Join-Path $dist 'GOAT-Tweaks.sha256'),(Join-Path $dist 'build-manifest.json'),(Join-Path $dist 'Open-GOAT.txt'),(Join-Path $dist 'launch.json'),(Join-Path $root 'README.md'),(Join-Path $root 'VERSION'))){$target=Join-Path $packageRoot ([IO.Path]::GetFileName($file));Copy-Item -LiteralPath $file -Destination $target -Force;$files+=$target}
Copy-Item -LiteralPath (Join-Path $root 'docs') -Destination $packageRoot -Recurse -Force
$files+=Join-Path $packageRoot 'docs'
Add-Type -AssemblyName System.IO.Compression,System.IO.Compression.FileSystem
$zipPath=Join-Path $dist ('GOAT-Tweaks-'+$version+'.zip')
$zipStream=[IO.File]::Open($zipPath,[IO.FileMode]::Create,[IO.FileAccess]::ReadWrite,[IO.FileShare]::None)
$archive=[IO.Compression.ZipArchive]::new($zipStream,[IO.Compression.ZipArchiveMode]::Create,$false)
try{foreach($file in @(Get-ChildItem -LiteralPath $packageRoot -Recurse -File)){$entry=$file.FullName.Substring($packageRoot.Length+1).Replace('\','/');[void][IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,$file.FullName,$entry,[IO.Compression.CompressionLevel]::Optimal)}}finally{$archive.Dispose();$zipStream.Dispose()}
$catalogData=Get-Content (Join-Path $root 'data/catalog.json') -Raw -Encoding UTF8|ConvertFrom-Json
[pscustomobject]@{Version=$version;Bundle=$bundle;Sha256=$hash;CatalogRecords=$catalogData.record_count;Package=(Join-Path $dist ('GOAT-Tweaks-'+$version+'.zip'));LaunchCommand=(Join-Path $dist 'Open-GOAT.txt')}
