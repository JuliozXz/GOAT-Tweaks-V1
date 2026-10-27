#Requires -Version 5.1
[CmdletBinding()]
param([string]$ProjectRoot)

$ErrorActionPreference='Stop'
if (-not $ProjectRoot) { $ProjectRoot=Split-Path $PSScriptRoot -Parent }
$outputRoot = Join-Path $ProjectRoot 'dist'
[IO.Directory]::CreateDirectory($outputRoot) | Out-Null
$parts = New-Object System.Collections.Generic.List[string]
$parts.Add('#Requires -Version 5.1')
$parts.Add('[CmdletBinding()]')
$parts.Add('param([switch]$Demo, [switch]$ScanOnly)')
$parts.Add('$script:GoatRoot = $PSScriptRoot')
$parts.Add('$script:GoatLaunchPath = $PSCommandPath')
foreach ($source in @(
    @{Name='GoatCoreSource';File='src\Core.ps1'},
    @{Name='GoatScannerSource';File='src\Scanner.ps1'},
    @{Name='GoatAdvancedScannerSource';File='src\AdvancedScanner.ps1'},
    @{Name='GoatGpuCenterSource';File='src\GpuCenter.ps1'},
    @{Name='GoatRecommendationSource';File='src\Recommendations.ps1'},
    @{Name='GoatRecommendationJson';File='data\recommendations.json'},
    @{Name='GoatSelectionSource';File='src\Selection.ps1'},
    @{Name='GoatToolAdvisorSource';File='src\ToolAdvisor.ps1'},
    @{Name='GoatNativeOptionsJson';File='data\native-options.json'},
    @{Name='GoatToolRulesJson';File='data\tool-rules.json'},
    @{Name='GoatIntegrationSource';File='src\Integrations.ps1'},
    @{Name='GoatUiSource';File='src\UI.ps1'},
    @{Name='GoatXaml';File='src\UI.xaml'}
)) {
    $content=Get-Content -LiteralPath (Join-Path $ProjectRoot $source.File) -Raw -Encoding UTF8
    # Raw GitHub responses have no guaranteed charset. Keep the transport ASCII
    # and decode UTF-8 resources explicitly so Windows PowerShell 5.1 preserves
    # Portuguese text both in saved scripts and in irm | iex. Sources stay in src/.
    $encoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($content))
    $parts.Add(('$script:{0} = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String(' -f $source.Name) + "'" + $encoded + "'))")
}
$catalogBytes=[Text.Encoding]::UTF8.GetBytes((Get-Content -LiteralPath (Join-Path $ProjectRoot 'data\repositories.json') -Raw -Encoding UTF8))
$catalogMemory=New-Object IO.MemoryStream
$catalogGzip=New-Object IO.Compression.GZipStream($catalogMemory,[IO.Compression.CompressionMode]::Compress,$true)
try { $catalogGzip.Write($catalogBytes,0,$catalogBytes.Length) } finally { $catalogGzip.Dispose() }
$catalogEncoded=[Convert]::ToBase64String($catalogMemory.ToArray()); $catalogMemory.Dispose()
$parts.Add('$goatCatalogStream = [IO.MemoryStream]::new([Convert]::FromBase64String('''+$catalogEncoded+'''))')
$parts.Add('$goatCatalogReader = [IO.StreamReader]::new([IO.Compression.GZipStream]::new($goatCatalogStream,[IO.Compression.CompressionMode]::Decompress),[Text.Encoding]::UTF8)')
$parts.Add('try { $script:GoatCatalogJson = $goatCatalogReader.ReadToEnd() } finally { $goatCatalogReader.Dispose(); $goatCatalogStream.Dispose() }')
$logoEncoded=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $ProjectRoot 'assets\goat-logo.png')))
$parts.Add('$script:GoatLogoBase64 = '''+$logoEncoded+'''')
$entry=Get-Content -LiteralPath (Join-Path $ProjectRoot 'src\Entry.ps1') -Raw -Encoding UTF8
$entryEncoded=[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($entry))
$parts.Add(". ([scriptblock]::Create([Text.Encoding]::UTF8.GetString([Convert]::FromBase64String('" + $entryEncoded + "'))))")
$bundle = Join-Path $outputRoot 'GOAT-Tweaks.ps1'
[IO.File]::WriteAllText($bundle, ($parts -join "`r`n`r`n"), [Text.Encoding]::ASCII)
if (@([IO.File]::ReadAllBytes($bundle) | Where-Object { $_ -gt 127 }).Count -gt 0) { throw 'Bundle precisa ser ASCII sem BOM para execucao remota.' }
$parseErrors=$null; $tokens=$null
[Management.Automation.Language.Parser]::ParseFile($bundle,[ref]$tokens,[ref]$parseErrors) | Out-Null
if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
$hash=(Get-FileHash -LiteralPath $bundle -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText((Join-Path $outputRoot 'GOAT-Tweaks.sha256'), "$hash  GOAT-Tweaks.ps1`r`n", (New-Object Text.UTF8Encoding($false)))
$zip=Join-Path $outputRoot 'GOAT-Tweaks-v2.4.zip'
$packageRoot=Join-Path $outputRoot 'package'
$packageDocs=Join-Path $packageRoot 'docs'
[IO.Directory]::CreateDirectory($packageDocs) | Out-Null
Copy-Item -LiteralPath $bundle -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $ProjectRoot 'README.md') -Destination $packageRoot -Force
Copy-Item -LiteralPath (Join-Path $outputRoot 'GOAT-Tweaks.sha256') -Destination $packageRoot -Force
foreach ($document in @('REFERENCIAS.md','VALIDACAO.md','RECOMENDACOES.md','INTEGRACOES-WINUTIL-RYTUNEX.md','OPCOES.md')) { Copy-Item -LiteralPath (Join-Path $ProjectRoot "docs\$document") -Destination $packageDocs -Force }
Compress-Archive -LiteralPath @((Join-Path $packageRoot 'GOAT-Tweaks.ps1'),(Join-Path $packageRoot 'README.md'),$packageDocs,(Join-Path $packageRoot 'GOAT-Tweaks.sha256')) -DestinationPath $zip -Force
Write-Output "Build concluído: $bundle"
Write-Output "SHA256: $hash"
Write-Output "Pacote: $zip"
