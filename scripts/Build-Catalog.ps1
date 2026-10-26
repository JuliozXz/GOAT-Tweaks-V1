[CmdletBinding()]
param(
    [string]$SnapshotDirectory = '',
    [string]$OutputPath = ''
)

$ErrorActionPreference = 'Stop'
if (-not $SnapshotDirectory) { $SnapshotDirectory=Join-Path $PSScriptRoot '..\artifacts' }
if (-not $OutputPath) { $OutputPath=Join-Path $PSScriptRoot '..\data\repositories.json' }

# Offline, reproducible projection of reviewed GitHub snapshots into the UI
# contract. Refresh the upstream-*.json provenance snapshots separately; this
# script never accesses the network, downloads installers or executes upstream.
function Get-CatalogProperty {
    param($Object, [string]$Name, $Default=$null)
    if ($null -ne $Object -and $Object.PSObject.Properties[$Name]) { return $Object.PSObject.Properties[$Name].Value }
    return $Default
}

function ConvertTo-CatalogUrlPath {
    param([string]$Path)
    return (($Path -split '/' | ForEach-Object { [Uri]::EscapeDataString($_) }) -join '/')
}

function Get-CatalogDate {
    param($Value)
    if ($Value) {
        try { return ([DateTime]::Parse([string]$Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::RoundtripKind)).ToUniversalTime().ToString('o') }
        catch { throw "Data inválida no snapshot: $Value" }
    }
    throw 'Snapshot sem data de consulta.'
}

function New-CatalogItem {
    param([string]$Id,[string]$Name,[string]$Path,[string]$Group,[string]$Kind,[string]$SourceUrl,[string]$DownloadUrl='', $Size=$null,
        [bool]$CanRun=$false,[string]$RunLabel='',[string]$Description='',[string]$Warning='',[string]$LaunchType='none',
        [string]$RelativePath='',[string]$Sha='',[string]$Sha256='',[string]$ReleaseTag='',[string]$Operation='RepositoryFile',[string]$Mode='')
    return [pscustomobject][ordered]@{
        Id=$Id;Name=$Name;Path=$Path;Group=$Group;Kind=$Kind;SourceUrl=$SourceUrl;DownloadUrl=$DownloadUrl;Size=$Size
        CanRun=$CanRun;RunLabel=$RunLabel;Description=$Description;Warning=$Warning;LaunchType=$LaunchType
        RelativePath=$RelativePath;Sha=$Sha;Sha256=$Sha256;ReleaseTag=$ReleaseTag;Operation=$Operation;Mode=$Mode
    }
}

function Get-CatalogRiskWarning {
    param([string]$Path,[string]$RepositoryId,[bool]$CanRun)
    $notes = New-Object 'System.Collections.Generic.List[string]'
    if ($CanRun) {
        $notes.Add('Código externo em processo separado. Suas alterações não fazem parte do desfazer transacional GOAT; downloads internos podem apontar a versões mutáveis.')
    }
    if ($RepositoryId -eq 'winsux' -and $Path -match '(?i)winsux\.ps1$') {
        $notes.Add('FLUXO COMPLETO: instala runtimes, navegador e 7-Zip; remove aplicativos; agenda etapas via RunOnce; ativa Safe Boot/modo de segurança; altera proteções; usa DDU para remover drivers de GPU/áudio e reinicia automaticamente, inclusive após cinco segundos. As etapas posteriores também alteram serviços/tarefas, importam Registro e instalam serviço de timer. Feche o trabalho aberto e revise todo o fluxo antes de iniciar.')
    }
    if ($Path -match '(?i)AllowScripts\.cmd|IWR\.ps1') {
        $notes.Add('Este bootstrap pode alterar a política de execução do PowerShell e baixar/iniciar outros scripts. Não é necessário para iniciar um ajuste individual pela biblioteca GOAT.')
    }
    if ($Path -match '(?i)Defender|Firewall|Spectre|Meltdown|Execution Prevention|\bDEP\b|UAC|Core Isolation|Security|Secure Boot|Whql') {
        $notes.Add('Contém opções ligadas a proteções do sistema. Leia a fonte e as consequências antes de escolher qualquer alteração.')
    }
    if ($Path -match '(?i)Driver Clean|Bios Check|To Bios|Factory Reset|Reinstall|Refresh') {
        $notes.Add('Pode interromper a sessão, reiniciar, alterar inicialização ou remover drivers. Um nome de verificação não garante operação somente de leitura.')
    }
    if ($Path -match '(?i)Bloatware|Debloat|Cleanup|RemoveEdge|Edge & WebView') {
        $notes.Add('Pode remover aplicativos, componentes ou arquivos; o diário de ajustes GOAT não recupera essas remoções.')
    }
    if ($Path -match '(?i)Timer Resolution|Services|ReBar|Smt Ht|Core 1 Thread|Msi Mode|Priority') {
        $notes.Add('Ajuste avançado dependente de hardware/carga; pode alterar serviços, interrupções, boot ou afinidade. Não há garantia universal de ganho.')
    }
    return ($notes.ToArray() -join ' ')
}

function Get-CatalogFileDescription {
    param([string]$Path,[string]$RepositoryId,[bool]$CanRun)
    $extension = [IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($RepositoryId -eq 'winsux' -and $Path -match '(?i)winsux\.ps1$') { return 'Início do fluxo WinSux original em várias etapas. Inclui instalações, remoções, modo de segurança e reinícios automáticos.' }
    if ($RepositoryId -eq 'winsux' -and $Path -match '(?i)stepone|steptwo|reg\.reg|settimerresolutionservice') { return 'Dependência de uma etapa do fluxo WinSux. Disponível para inspeção e download; inicie o fluxo por winsux.ps1.' }
    if ($RepositoryId -eq 'winutil' -and $Path -match '^functions/') { return 'Definição de função do Winutil; depende da aplicação, de seus controles e estado compartilhado. Abra a fonte ou baixe para desenvolvimento.' }
    if ($RepositoryId -eq 'winutil' -and $Path -match '^config/') { return 'Catálogo/configuração original do Winutil. Seus recursos são apresentados também nas linhas de Recursos e executados pela aplicação completa.' }
    if ($RepositoryId -eq 'rytunex' -and $extension -in @('.cs','.xaml','.csproj','.sln','.ps1')) { return 'Fonte ou recurso da aplicação nativa RyTuneX. Este arquivo não é um launcher independente; use a aplicação da Microsoft Store.' }
    if ($CanRun -and $extension -eq '.ps1') {
        $topic = 'rotina original'
        if ($Path -match '^1 Check/') { $topic='verificação e benchmarks (algumas rotinas também alteram configurações)' }
        elseif ($Path -match '^2 Refresh/') { $topic='recuperação e reinstalação do Windows' }
        elseif ($Path -match '^3 Setup/') { $topic='configuração inicial do Windows' }
        elseif ($Path -match '^4 Installers/') { $topic='instalação de ferramentas e programas' }
        elseif ($Path -match '^5 Graphics/') { $topic='GPU, drivers e gráficos' }
        elseif ($Path -match '^6 Windows/') { $topic='preferências e componentes do Windows' }
        elseif ($Path -match '^7 Hardware/') { $topic='hardware, periféricos e testes' }
        elseif ($Path -match '^8 Advanced/') { $topic='configuração avançada do sistema' }
        return "Script original de $topic. A execução abre um processo separado e preserva a estrutura de arquivos da revisão."
    }
    if ($extension -in @('.md','.mdx','.txt')) { return 'Documentação ou recurso textual original, disponível para consulta e download.' }
    if ($extension -in @('.png','.jpg','.jpeg','.svg','.ico')) { return 'Imagem ou recurso visual original do projeto.' }
    if ($extension -eq '.ps1') { return 'Fonte PowerShell de desenvolvimento, teste ou suporte; não foi classificada como launcher independente.' }
    if ($extension -in @('.cmd','.bat')) { return 'Arquivo de comandos original. Revise sua finalidade e a política de execução antes de usar.' }
    return 'Arquivo original do repositório, preservado na revisão indicada para consulta e download.'
}

function Add-CatalogFeature {
    param($Items,[string]$Id,[string]$Name,[string]$Path,[string]$Section,[string]$SourceUrl,[string]$Description,[string]$RepositoryName,[string]$Warning='')
    $detail = [string]$Description
    if ($detail) { $detail = ($detail -replace '\s+',' ').Trim() + ' ' }
    $detail += "Recurso da aplicação $RepositoryName original; esta linha mostra a opção e sua fonte. A operação individual é feita na aplicação completa."
    $Items.Add((New-CatalogItem -Id $Id -Name $Name -Path $Path -Group ('Recursos / ' + $Section) -Kind 'Recurso' -SourceUrl $SourceUrl -Description $detail -Warning $Warning -Operation 'Feature'))
}

$repositories = New-Object 'System.Collections.Generic.List[object]'
$dates = New-Object 'System.Collections.Generic.List[string]'
foreach ($repositoryId in @('winutil','winsux','ultimate','rytunex')) {
    $snapshotPath = Join-Path $SnapshotDirectory ('upstream-' + $repositoryId + '.json')
    if (-not (Test-Path -LiteralPath $snapshotPath -PathType Leaf)) { throw "Snapshot ausente: $snapshotPath. Atualize a proveniência antes de gerar o catálogo." }
    $snapshot = Get-Content -LiteralPath $snapshotPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $modern = $snapshot.repository -isnot [string]
    if ($modern) {
        $metadata=$snapshot.repository; $fullName=[string]$metadata.full_name; $commit=[string]$snapshot.head.sha
        $tree=@($snapshot.tree.tree); $truncated=[bool]$snapshot.tree.truncated; $updated=Get-CatalogDate $snapshot.retrievedAtUtc
        $assets=@($snapshot.latestRelease.assets | ForEach-Object {
            [pscustomobject]@{name=$_.name;size=$_.size;url=$_.browser_download_url;digest=$_.digest;tag=$snapshot.latestRelease.tag_name;releaseUrl=$snapshot.latestRelease.html_url}
        })
    }
    else {
        $metadata=$snapshot.metadata; $fullName=[string]$snapshot.repository; $commit=[string]$snapshot.commit
        $tree=@($snapshot.tree); $truncated=[bool]$snapshot.truncated; $updated=Get-CatalogDate $snapshot.fetchedAt
        $assets=@($snapshot.releaseAssets | ForEach-Object {
            [pscustomobject]@{name=$_.name;size=$_.size;url=$_.url;digest=$_.digest;tag=$_.tag;releaseUrl=($snapshot.repositoryUrl + '/releases/tag/' + [Uri]::EscapeDataString($_.tag))}
        })
    }
    if ($truncated) { throw "Árvore truncada em $repositoryId; impossível publicar como inventário completo." }
    if ($commit -notmatch '^[0-9a-fA-F]{40}$' -or $fullName -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$') { throw 'Identidade ou revisão inválida no snapshot.' }
    $owner,$repository = $fullName -split '/',2
    $repositoryUrl = 'https://github.com/' + $fullName
    $items = New-Object 'System.Collections.Generic.List[object]'
    foreach ($file in @($tree | Where-Object { $_.type -eq 'blob' } | Sort-Object path)) {
        $path=[string]$file.path
        if (-not $path -or $path.StartsWith('/') -or $path.Contains('\') -or @($path -split '/' | Where-Object { $_ -eq '..' -or $_ -eq '.' }).Count -gt 0) { throw "Caminho inválido na árvore: $path" }
        if ([string]$file.sha -notmatch '^[0-9a-fA-F]{40}$') { throw "Blob inválido: $path" }
        $encodedPath=ConvertTo-CatalogUrlPath $path
        $sourceUrl="$repositoryUrl/blob/$commit/$encodedPath"
        $downloadUrl="https://raw.githubusercontent.com/$fullName/$commit/$encodedPath"
        $extension=[IO.Path]::GetExtension($path).ToLowerInvariant()
        $kind='Arquivo'; $launchType='none'; $canRun=$false; $runLabel=''
        if ($extension -in @('.ps1','.cmd','.bat')) { $kind='Script' }
        elseif ($extension -eq '.exe') { $kind='Executável' }
        elseif ($extension -in @('.msi','.appx','.msix','.appxbundle','.msixbundle')) { $kind='Instalador' }
        elseif ($extension -in @('.cs','.xaml','.json','.xml','.csproj','.sln','.resw','.psm1','.psd1','.cpp','.h','.py','.ts','.mjs','.astro','.css','.yaml','.yml','.toml')) { $kind='Código-fonte' }
        if ($repositoryId -eq 'ultimate' -and $extension -eq '.ps1') { $canRun=$true; $launchType='ps1' }
        elseif ($repositoryId -eq 'ultimate' -and $path -eq 'AllowScripts.cmd') { $canRun=$true; $launchType='cmd' }
        elseif ($repositoryId -eq 'winsux' -and $path -eq 'WinSux/winsux.ps1') { $canRun=$true; $launchType='ps1' }
        elseif ($repositoryId -eq 'winutil' -and $path -eq 'winutil.ps1') { $canRun=$true; $launchType='ps1' }
        if ([string]$file.mode -ne '100644' -and [string]$file.mode -ne '100755') { $canRun=$false; $launchType='none' }
        if ($canRun) { $runLabel='Executar original' }
        $group='Raiz'; $separator=$path.LastIndexOf('/'); if ($separator -ge 0) { $group=$path.Substring(0,$separator) }
        $items.Add((New-CatalogItem -Id ('file:'+$path) -Name ([IO.Path]::GetFileName($path)) -Path $path -Group $group -Kind $kind -SourceUrl $sourceUrl -DownloadUrl $downloadUrl -Size $file.size -CanRun $canRun -RunLabel $runLabel -Description (Get-CatalogFileDescription $path $repositoryId $canRun) -Warning (Get-CatalogRiskWarning $path $repositoryId $canRun) -LaunchType $launchType -RelativePath $path -Sha $file.sha -Mode $file.mode))
    }

    foreach ($asset in $assets) {
        $extension=[IO.Path]::GetExtension($asset.name).ToLowerInvariant()
        $sha256=''; if ([string]$asset.digest -match '^sha256:([0-9a-fA-F]{64})$') { $sha256=$Matches[1].ToLowerInvariant() }
        $kind='Arquivo'; $launchType='none'; $canRun=$false
        switch ($extension) {
            '.ps1' { $kind='Script'; $launchType='ps1' }
            '.cmd' { $kind='Script'; $launchType='cmd' }
            '.exe' { $kind='Executável'; $launchType='exe' }
            '.msi' { $kind='Instalador'; $launchType='msi' }
            '.appx' { $kind='Instalador' }
            '.msix' { $kind='Instalador' }
            '.appxbundle' { $kind='Instalador' }
            '.msixbundle' { $kind='Instalador' }
        }
        if ($sha256 -and $launchType -ne 'none') { $canRun=$true }
        else { $launchType='none' }
        $description='Asset original publicado na release; download verificado pelo SHA-256 registrado quando disponível.'
        if ($repositoryId -eq 'winutil' -and $asset.name -eq 'winutil.ps1') { $description='Aplicação Winutil completa da release estável. Abre a interface original para instalações, ajustes, recursos, correções e Windows Update. O catálogo de main pode conter diferenças em relação a esta release.' }
        elseif ($extension -in @('.appx','.msix','.appxbundle','.msixbundle')) { $description += ' Pacote disponível para baixar; instale pelo fluxo do Windows indicado pelo fornecedor. Não há execução direta deste formato no GOAT.' }
        elseif ($extension -eq '.zip') { $description += ' Arquivo compactado disponível para baixar e inspecionar; não é iniciado automaticamente.' }
        $warning=Get-CatalogRiskWarning $asset.name $repositoryId $canRun
        if (-not $sha256) { $warning=($warning+' O snapshot não contém SHA-256 deste asset; execução direta indisponível.').Trim() }
        $runLabel=''; if ($canRun) { $runLabel='Abrir original'; if ($extension -eq '.msi') {$runLabel='Instalar original'} }
        $items.Add((New-CatalogItem -Id ('release:'+$asset.tag+'/'+$asset.name) -Name $asset.name -Path ('Releases/'+$asset.tag+'/'+$asset.name) -Group ('Releases / '+$asset.tag) -Kind $kind -SourceUrl $asset.releaseUrl -DownloadUrl $asset.url -Size $asset.size -CanRun $canRun -RunLabel $runLabel -Description $description -Warning $warning -LaunchType $launchType -Sha256 $sha256 -ReleaseTag $asset.tag -Operation 'ReleaseAsset'))
    }

    $primaryItemId=''
    if ($repositoryId -eq 'winutil') {
        $primary=@($items | Where-Object { $_.Operation -eq 'ReleaseAsset' -and $_.Name -eq 'winutil.ps1' -and $_.CanRun }) | Select-Object -First 1
        if ($primary) { $primaryItemId=$primary.Id }
        foreach ($catalogName in @('applications','tweaks','feature','appx','dns','preset','appnavigation')) {
            $catalog=Get-CatalogProperty $snapshot.catalogs $catalogName
            if (-not $catalog) { throw "Catálogo Winutil ausente: $catalogName" }
            $catalogPath='config/'+$catalogName+'.json'
            $sourceUrl="$repositoryUrl/blob/$commit/$catalogPath"
            foreach ($property in @($catalog.PSObject.Properties | Sort-Object Name)) {
                $definition=$property.Value
                $name=[string](Get-CatalogProperty $definition 'Content' $property.Name)
                $category=[string](Get-CatalogProperty $definition 'Category' '')
                $description=[string](Get-CatalogProperty $definition 'Description' '')
                switch ($catalogName) {
                    'applications' { $section='Aplicativos / '+$category }
                    'tweaks' { $section='Tweaks / '+$category }
                    'feature' { $section='Configuração / '+$category }
                    'appx' { $section='Appx / '+$category }
                    'dns' {
                        $section='DNS'; $name=$property.Name
                        $description='Perfil DNS do catálogo original. IPv4 primário: '+[string](Get-CatalogProperty $definition 'Primary' '')+'.'
                    }
                    'preset' { $section='Predefinições'; $name=$property.Name; $description=('Perfil com {0} entradas do catálogo original.' -f @($definition).Count) }
                    'appnavigation' { $section='Ações da interface / '+$category }
                }
                Add-CatalogFeature -Items $items -Id ('feature:'+$catalogName+'/'+$property.Name) -Name $name -Path ($catalogPath+'#'+$property.Name) -Section $section -SourceUrl $sourceUrl -Description $description -RepositoryName 'Winutil' -Warning (Get-CatalogRiskWarning ($name+' '+$category) $repositoryId $false)
            }
        }
    }
    elseif ($repositoryId -eq 'winsux') { $primaryItemId='file:WinSux/winsux.ps1' }
    elseif ($repositoryId -eq 'rytunex') {
        $primaryItemId='store:rytunex'
        $items.Add((New-CatalogItem -Id $primaryItemId -Name 'RyTuneX — Microsoft Store' -Path 'Microsoft Store / 9PDH8M7HF2SQ' -Group 'Aplicativo oficial' -Kind 'Aplicativo' -SourceUrl 'https://apps.microsoft.com/detail/9PDH8M7HF2SQ' -DownloadUrl 'ms-windows-store://pdp/?ProductId=9PDH8M7HF2SQ' -CanRun $true -RunLabel 'Abrir Microsoft Store' -Description 'Abre a página oficial para instalar ou abrir o RyTuneX. A versão atual é distribuída pela Microsoft Store; não há executável lateral na última release.' -LaunchType 'uri' -Operation 'OpenUri'))
        foreach ($navigation in @($snapshot.catalogs.navigation)) {
            $sourceUrl="$repositoryUrl/blob/$commit/"+(ConvertTo-CatalogUrlPath $navigation.path)
            Add-CatalogFeature -Items $items -Id ('feature:navigation/'+$navigation.id) -Name $navigation.name -Path $navigation.path -Section 'Navegação' -SourceUrl $sourceUrl -Description 'Página da navegação oficial do RyTuneX.' -RepositoryName 'RyTuneX'
        }
        foreach ($page in @($snapshot.catalogs.pages)) {
            $pageName=[IO.Path]::GetFileNameWithoutExtension($page.path)
            $navigation=@($snapshot.catalogs.navigation | Where-Object { $_.path -eq $page.path } | Select-Object -First 1)
            if ($navigation.Count -gt 0) { $pageName=$navigation[0].name }
            foreach ($card in @($page.cards)) {
                $sourceUrl="$repositoryUrl/blob/$commit/"+(ConvertTo-CatalogUrlPath $page.path)
                Add-CatalogFeature -Items $items -Id ('feature:page/'+$pageName+'/'+$card.id) -Name $card.title -Path ($page.path+'#'+$card.id) -Section ($pageName+' / '+$card.section) -SourceUrl $sourceUrl -Description $card.description -RepositoryName 'RyTuneX' -Warning (Get-CatalogRiskWarning ($card.title+' '+$card.section) $repositoryId $false)
            }
        }
    }

    $seen=New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($item in $items) {
        if (-not $seen.Add($item.Id)) { throw "ID duplicado em $repositoryId : $($item.Id)" }
    }
    if ($primaryItemId -and @($items | Where-Object { $_.Id -eq $primaryItemId -and $_.CanRun }).Count -ne 1) { throw "Launcher principal inválido em $repositoryId" }
    $name=$repository
    $description=''
    switch ($repositoryId) {
        'winutil' { $name='Winutil'; $description='Aplicativos, ajustes, recursos, correções e Windows Update no utilitário original de Chris Titus Tech.' }
        'winsux' { $name='WinSux'; $description='Fluxo FR33THY em várias etapas com instalações, remoções, modo de segurança e reinícios. Revise os efeitos completos antes de executar.' }
        'ultimate' { $name='Ultimate'; $description='Biblioteca FR33THY organizada em verificação, recuperação, setup, instaladores, gráficos, Windows, hardware e ajustes avançados. Escolha cada script pela finalidade.' }
        'rytunex' { $name='RyTuneX'; $description='Aplicação nativa WinUI da Microsoft Store, com catálogo de páginas e controles e acesso ao código-fonte original.' }
    }
    $licenseName='LICENSE'; if ($repositoryId -eq 'rytunex') {$licenseName='LICENSE.md'}
    $repositories.Add([pscustomobject][ordered]@{
        Id=$repositoryId;Name=$name;Owner=$owner;Repository=$repository;Description=$description;RepositoryUrl=$repositoryUrl
        Commit=$commit;CommitShort=$commit.Substring(0,8);LicenseUrl="$repositoryUrl/blob/$commit/$licenseName";UpdatedAt=$updated
        PrimaryItemId=$primaryItemId;ArchiveUrl="https://codeload.github.com/$fullName/zip/$commit"
        FileCount=@($items | Where-Object Operation -eq 'RepositoryFile').Count
        AssetCount=@($items | Where-Object Operation -eq 'ReleaseAsset').Count
        FeatureCount=@($items | Where-Object Operation -eq 'Feature').Count
        Items=@($items.ToArray())
    })
    $dates.Add($updated)
}

$updatedAt=@($dates.ToArray() | Sort-Object -Descending)[0]
$catalog=[pscustomobject][ordered]@{ SchemaVersion=1;UpdatedAt=$updatedAt;Repositories=@($repositories.ToArray()) }
$outputFullPath=[IO.Path]::GetFullPath($OutputPath)
[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($outputFullPath)) | Out-Null
$json=ConvertTo-Json -InputObject $catalog -Depth 16 -Compress
[IO.File]::WriteAllText($outputFullPath,$json,(New-Object Text.UTF8Encoding($true)))
Write-Output "Catálogo gerado a partir dos snapshots locais: $outputFullPath"
$repositories | Select-Object Id,FileCount,AssetCount,FeatureCount,PrimaryItemId,@{Name='Total';Expression={$_.Items.Count}}
