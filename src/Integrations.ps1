# Original upstream catalog / isolated launch support. Windows PowerShell 5.1.
# This module never runs a tool while loading, scanning or browsing its catalog.

function Get-GoatRepositoryCatalog {
    if (-not $script:GoatRepositoryCatalogCache) {
        if (-not $script:GoatCatalogJson) { throw 'Catálogo de projetos não foi incluído no aplicativo.' }
        $catalog=$script:GoatCatalogJson | ConvertFrom-Json -ErrorAction Stop
        if ($catalog.SchemaVersion -ne 1 -or @($catalog.Repositories).Count -ne 4) { throw 'Formato de catálogo inválido.' }
        $script:GoatRepositoryCatalogCache=$catalog
    }
    return $script:GoatRepositoryCatalogCache
}

function Get-GoatExternalSelection {
    param([string]$RepositoryId,[string]$ItemId)
    $repositories=@((Get-GoatRepositoryCatalog).Repositories | Where-Object { $_.Id -eq $RepositoryId })
    if ($repositories.Count -ne 1) { throw 'Projeto não encontrado no catálogo.' }
    $items=@($repositories[0].Items | Where-Object { $_.Id -eq $ItemId })
    if ($items.Count -ne 1) { throw 'Item não encontrado no catálogo.' }
    return [pscustomobject]@{Repository=$repositories[0];Item=$items[0]}
}

function Resolve-GoatExternalPath {
    param([Parameter(Mandatory=$true)][string]$Root,[Parameter(Mandatory=$true)][string]$RelativePath)
    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath -match '[\\:<>"|?*\x00-\x1f]') { throw 'Caminho externo inválido.' }
    foreach ($component in $RelativePath.Split('/')) {
        if (-not $component -or $component -in @('.','..') -or $component -match '[. ]$' -or $component -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)') { throw 'Componente de caminho externo inválido.' }
    }
    $base=[IO.Path]::GetFullPath($Root).TrimEnd('\')
    $resolved=[IO.Path]::GetFullPath((Join-Path $base $RelativePath.Replace('/','\')))
    if (-not $resolved.StartsWith($base+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Arquivo fora da pasta de ferramentas.' }
    # Reject redirection through junctions/symlinks in any existing ancestor.
    $ancestor=$resolved
    while ($ancestor) {
        if ([IO.File]::Exists($ancestor) -or [IO.Directory]::Exists($ancestor)) {
            if (([IO.File]::GetAttributes($ancestor) -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Links de sistema de arquivos não são aceitos no cache.' }
        }
        $parent=[IO.Path]::GetDirectoryName($ancestor)
        if ($parent -eq $ancestor) { break }; $ancestor=$parent
    }
    return $resolved
}

function Get-GoatGitBlobHash {
    param([string]$Path)
    $stream=[IO.File]::OpenRead($Path); $algorithm=[Security.Cryptography.SHA1]::Create()
    try {
        $prefix=[Text.Encoding]::ASCII.GetBytes(('blob '+$stream.Length+[char]0))
        [void]$algorithm.TransformBlock($prefix,0,$prefix.Length,$prefix,0)
        $buffer=New-Object byte[] 65536
        while (($read=$stream.Read($buffer,0,$buffer.Length)) -gt 0) { [void]$algorithm.TransformBlock($buffer,0,$read,$buffer,0) }
        [void]$algorithm.TransformFinalBlock((New-Object byte[] 0),0,0)
        return ([BitConverter]::ToString($algorithm.Hash)).Replace('-','').ToLowerInvariant()
    } finally { $stream.Dispose(); $algorithm.Dispose() }
}

function Test-GoatExternalFile {
    param([string]$Path,$Item)
    if (-not [IO.File]::Exists($Path)) { return $false }
    if ($null -ne $Item.Size -and [long]$Item.Size -ge 0 -and (Get-Item -LiteralPath $Path -ErrorAction Stop).Length -ne [long]$Item.Size) { return $false }
    if ($Item.Sha256 -match '^[0-9a-fA-F]{64}$') { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash -eq $Item.Sha256 }
    if ($Item.Sha -match '^[0-9a-fA-F]{40}$') { return (Get-GoatGitBlobHash $Path) -eq $Item.Sha }
    return $false
}

function Assert-GoatDownloadUri {
    param([uri]$Uri)
    if (-not $Uri.IsAbsoluteUri -or $Uri.Scheme -ne 'https' -or $Uri.UserInfo -or -not $Uri.IsDefaultPort) { throw 'Download exige HTTPS padrão sem credenciais.' }
    if ($Uri.DnsSafeHost -notin @('github.com','raw.githubusercontent.com','codeload.github.com')) { throw 'Origem fora dos servidores GitHub permitidos.' }
}

function Receive-GoatExternalFile {
    param([uri]$Uri,[string]$Path,[Nullable[long]]$ExpectedSize,[scriptblock]$ProgressCallback)
    Assert-GoatDownloadUri $Uri
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    $temporary=$Path+'.download-'+[Guid]::NewGuid().ToString('N')
    $response=$null; $inputStream=$null; $outputStream=$null
    $oldProtocol=[Net.ServicePointManager]::SecurityProtocol
    try {
        [Net.ServicePointManager]::SecurityProtocol=$oldProtocol -bor [Net.SecurityProtocolType]::Tls12
        $request=[Net.HttpWebRequest]::Create($Uri)
        $request.UserAgent='GOAT-Tweaks/2.3'; $request.Timeout=60000; $request.ReadWriteTimeout=30000
        $response=$request.GetResponse()
        $finalHost=$response.ResponseUri.DnsSafeHost
        if ($response.ResponseUri.Scheme -ne 'https' -or ($finalHost -notin @('github.com','codeload.github.com') -and $finalHost -notmatch '(^|\.)githubusercontent\.com$')) { throw 'Redirecionamento de download não reconhecido.' }
        $inputStream=$response.GetResponseStream()
        $outputStream=New-Object IO.FileStream($temporary,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
        $buffer=New-Object byte[] 65536; [long]$total=0; $lastProgress=[DateTime]::UtcNow
        [long]$limit=1073741824
        if ($null -ne $ExpectedSize -and $ExpectedSize -ge 0) { $limit=[long]$ExpectedSize }
        while (($read=$inputStream.Read($buffer,0,$buffer.Length)) -gt 0) {
            $total+=$read
            if ($total -gt $limit) { throw 'Download excedeu o tamanho esperado.' }
            $outputStream.Write($buffer,0,$read)
            if (([DateTime]::UtcNow-$lastProgress).TotalSeconds -ge 1) {
                Send-GoatProgress $ProgressCallback ('Baixando arquivo original: {0:N1} MB' -f ($total/1MB)); $lastProgress=[DateTime]::UtcNow
            }
        }
        $outputStream.Flush($true); $outputStream.Dispose(); $outputStream=$null
        if ($null -ne $ExpectedSize -and $ExpectedSize -ge 0 -and $total -ne $ExpectedSize) { throw 'Download incompleto: tamanho diferente do catálogo.' }
        Move-Item -LiteralPath $temporary -Destination $Path -Force -ErrorAction Stop
    } finally {
        if ($outputStream) {$outputStream.Dispose()}; if ($inputStream) {$inputStream.Dispose()}; if ($response) {$response.Dispose()}
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
        [Net.ServicePointManager]::SecurityProtocol=$oldProtocol
    }
}

function Save-GoatExternalItem {
    param($Repository,$Item,[string]$CacheRoot,[scriptblock]$ProgressCallback)
    if (-not $Item.DownloadUrl) { throw 'Este item não oferece download de arquivo.' }
    if ($Item.Operation -eq 'RepositoryFile') {
        if ($Item.Mode -and $Item.Mode -notin @('100644','100755')) { throw 'Somente arquivos regulares podem ser baixados.' }
        $relative=$Repository.Id+'/'+$Repository.Commit+'/repository/'+$Item.RelativePath
    } elseif ($Item.Operation -eq 'ReleaseAsset') {
        $releaseKey=([string]$Item.ReleaseTag -replace '[^a-zA-Z0-9._-]','_')
        $relative=$Repository.Id+'/releases/'+$releaseKey+'/'+$Item.Name
    } else { throw 'Tipo de download não reconhecido.' }
    $destination=Resolve-GoatExternalPath $CacheRoot $relative
    if (-not (Test-GoatExternalFile $destination $Item)) {
        Send-GoatProgress $ProgressCallback ('Baixando '+$Item.Name+'...')
        Receive-GoatExternalFile -Uri $Item.DownloadUrl -Path $destination -ExpectedSize $Item.Size -ProgressCallback $ProgressCallback
        if (-not (Test-GoatExternalFile $destination $Item)) { throw 'Integridade não confirmada. O arquivo não será executado; atualize o catálogo ou confira a origem.' }
    }
    return $destination
}

function Save-GoatRepositorySnapshot {
    param($Repository,[string]$CacheRoot,[scriptblock]$ProgressCallback)
    $files=@($Repository.Items | Where-Object { $_.Operation -eq 'RepositoryFile' })
    if ($files.Count -eq 0) { throw 'Catálogo sem inventário de arquivos.' }
    $destinationRoot=Resolve-GoatExternalPath $CacheRoot ($Repository.Id+'/'+$Repository.Commit+'/repository')
    $complete=$true
    foreach ($file in $files) {
        $path=Resolve-GoatExternalPath $destinationRoot $file.RelativePath
        if (-not (Test-GoatExternalFile $path $file)) { $complete=$false; break }
    }
    if ($complete) { return $destinationRoot }
    $archivePath=Resolve-GoatExternalPath $CacheRoot ('.archives/'+$Repository.Id+'-'+$Repository.Commit+'.zip')
    Send-GoatProgress $ProgressCallback ('Preparando pastas originais de '+$Repository.Name+'...')
    Receive-GoatExternalFile -Uri ('https://codeload.github.com/'+$Repository.Owner+'/'+$Repository.Repository+'/zip/'+$Repository.Commit) -Path $archivePath -ProgressCallback $ProgressCallback
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive=[IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $prefix=$Repository.Repository+'-'+$Repository.Commit+'/'
        $expected=@{}
        foreach ($file in $files) {
            if ($expected.ContainsKey([string]$file.RelativePath)) { throw 'Caminhos duplicados no catálogo.' }
            if ($file.Mode -and $file.Mode -notin @('100644','100755')) { throw 'Repositório contém link simbólico não suportado para execução.' }
            $expected[[string]$file.RelativePath]=$file
        }
        $seen=@{}
        foreach ($entry in $archive.Entries) {
            if ($entry.FullName.EndsWith('/')) { continue }
            if (-not $entry.FullName.StartsWith($prefix,[StringComparison]::Ordinal)) { throw 'Estrutura do pacote diverge do commit esperado.' }
            $relative=$entry.FullName.Substring($prefix.Length)
            if (-not $expected.ContainsKey($relative) -or $seen.ContainsKey($relative)) { throw 'Arquivo inesperado ou duplicado no pacote.' }
            $expectedItem=$expected[$relative]
            if ($entry.Length -ne [long]$expectedItem.Size) { throw 'Tamanho divergente no pacote.' }
            $target=Resolve-GoatExternalPath $destinationRoot $relative
            [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
            [IO.Compression.ZipFileExtensions]::ExtractToFile($entry,$target,$true)
            if (-not (Test-GoatExternalFile $target $expectedItem)) { throw ('Integridade divergente em '+$relative) }
            $seen[$relative]=$true
        }
        if ($seen.Count -ne $files.Count) { throw 'O pacote não contém todos os arquivos do catálogo.' }
    } finally { $archive.Dispose() }
    return $destinationRoot
}

function Get-GoatExternalProtection {
    param([string]$OperationId,[string]$LogPath)
    # A verified GOAT restore point from the last 24 hours also protects launch
    # of additional external tools; respect Windows checkpoint frequency.
    $points=@(Get-CimInstance -Namespace 'root/default' -ClassName SystemRestore -OperationTimeoutSec 20 -ErrorAction Stop)
    foreach ($point in @($points | Sort-Object SequenceNumber -Descending)) {
        if ($point.Description -notlike 'GOAT v2.2 *') { continue }
        try {
            $created=if ($point.CreationTime -is [DateTime]) { $point.CreationTime.ToUniversalTime() } else { [Management.ManagementDateTimeConverter]::ToDateTime([string]$point.CreationTime).ToUniversalTime() }
            $age=([DateTime]::UtcNow-$created).TotalHours
            if ($age -ge 0 -and $age -lt 24) {
                Write-GoatLog $LogPath ('RestorePoint existente confirmado: '+$point.SequenceNumber)
                return [long]$point.SequenceNumber
            }
        } catch { continue }
    }
    return New-GoatRestorePoint $OperationId $LogPath
}

function Start-GoatExternalProcess {
    param([string]$Path,[string]$LaunchType)
    if ($LaunchType -eq 'cmd' -and $Path -match '[%!\r\n]') { throw 'Nome incompatível com execução segura de arquivo CMD.' }
    $workingDirectory=Split-Path -Path $Path -Parent
    switch ($LaunchType) {
        'ps1' { return Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-STA','-ExecutionPolicy','Bypass','-File',('"'+$Path+'"')) -WorkingDirectory $workingDirectory -PassThru -ErrorAction Stop }
        'cmd' { return Start-Process -FilePath "$env:SystemRoot\System32\cmd.exe" -ArgumentList @('/d','/s','/k',('""'+$Path+'""')) -WorkingDirectory $workingDirectory -PassThru -ErrorAction Stop }
        'exe' { return Start-Process -FilePath $Path -WorkingDirectory $workingDirectory -PassThru -ErrorAction Stop }
        'msi' { return Start-Process -FilePath "$env:SystemRoot\System32\msiexec.exe" -ArgumentList @('/i',('"'+$Path+'"')) -WorkingDirectory $workingDirectory -PassThru -ErrorAction Stop }
        default { throw 'Este formato não pode ser executado diretamente.' }
    }
}

function Invoke-GoatExternalItem {
    [CmdletBinding()]
    param([Parameter(Mandatory=$true)][string]$RepositoryId,[Parameter(Mandatory=$true)][string]$ItemId,
        [ValidateSet('Download','Run')][string]$Action='Download',[switch]$Demo,[scriptblock]$ProgressCallback)
    $logPath=''; $localPath=''; $mutex=$null; $locked=$false; $started=$false; $startedProcessId=$null
    try {
        $selection=Get-GoatExternalSelection $RepositoryId $ItemId
        $repo=$selection.Repository; $item=$selection.Item
        if ($Action -eq 'Run' -and -not $item.CanRun) { throw 'Este item é um recurso/arquivo auxiliar. Use o aplicativo original ou consulte a origem.' }
        if ($Demo) { return [pscustomobject]@{Success=$true;Message=('Demonstração: '+$Action+' de '+$item.Name+' simulado.');LocalPath='';LogPath='';Started=$false} }
        if ($Action -eq 'Run' -and $item.LaunchType -eq 'uri') {
            if ($repo.Id -ne 'rytunex' -or $item.DownloadUrl -ne 'ms-windows-store://pdp/?ProductId=9PDH8M7HF2SQ') { throw 'Destino de aplicativo não permitido.' }
            Start-Process -FilePath $item.DownloadUrl -ErrorAction Stop | Out-Null
            return [pscustomobject]@{Success=$true;Message='Página oficial do RyTuneX aberta na Microsoft Store.';LocalPath='';LogPath='';Started=$true}
        }
        if ($Action -eq 'Run' -and -not (Test-GoatAdministrator)) { throw 'Abra o GOAT como administrador para iniciar scripts ou executáveis de manutenção.' }
        if ($Action -eq 'Run' -and -not [Environment]::Is64BitProcess) { throw 'Use o Windows PowerShell de 64 bits.' }
        $mutex=New-Object Threading.Mutex($false,'Global\GOAT-Tweaks-v2.2-Mutation')
        try {$locked=$mutex.WaitOne(0)} catch [Threading.AbandonedMutexException] {$locked=$true}
        if (-not $locked) { throw 'Há outra operação GOAT em andamento.' }
        $storage=Get-GoatStorageRoot
        $cacheRoot=Join-Path $storage 'tools'
        [IO.Directory]::CreateDirectory((Join-Path $storage 'logs')) | Out-Null
        $operationId='external-'+[DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')+'-'+[Guid]::NewGuid().ToString('N').Substring(0,8)
        $logPath=Join-Path $storage ('logs\'+$operationId+'.log')
        Write-GoatLog $logPath ('EXTERNAL '+($item | Select-Object Id,Name,SourceUrl,DownloadUrl,Sha,Sha256,LaunchType | ConvertTo-Json -Compress))
        if ($Action -eq 'Run' -and $item.Operation -eq 'RepositoryFile') {
            $snapshot=Save-GoatRepositorySnapshot -Repository $repo -CacheRoot $cacheRoot -ProgressCallback $ProgressCallback
            $localPath=Resolve-GoatExternalPath $snapshot $item.RelativePath
        } else { $localPath=Save-GoatExternalItem -Repository $repo -Item $item -CacheRoot $cacheRoot -ProgressCallback $ProgressCallback }
        Write-GoatLog $logPath ('DOWNLOAD VERIFIED '+$localPath)
        if ($Action -eq 'Download') {
            return [pscustomobject]@{Success=$true;Message=('Arquivo original baixado e verificado: '+$localPath);LocalPath=$localPath;LogPath=$logPath;Started=$false}
        }
        Send-GoatProgress $ProgressCallback 'Verificando ponto de restauração antes de iniciar o projeto externo...'
        $protection=Get-GoatExternalProtection $operationId $logPath
        if (-not (Test-GoatExternalFile $localPath $item)) { throw 'O arquivo mudou após a verificação; execução interrompida.' }
        Write-GoatLog $logPath ('COMMAND LaunchType='+$item.LaunchType+' Path='+$localPath+' RestorePoint='+$protection)
        $process=Start-GoatExternalProcess -Path $localPath -LaunchType $item.LaunchType
        $started=$true; $startedProcessId=$process.Id
        Write-GoatLog $logPath ('STARTED PID='+$process.Id+'; alterações pertencem ao projeto externo, fora do diário de reversão GOAT.')
        return [pscustomobject]@{Success=$true;Message=($item.Name+' iniciado em uma janela própria. Acompanhe o programa original; suas alterações não fazem parte do desfazer do GOAT.');LocalPath=$localPath;LogPath=$logPath;Started=$true}
    } catch {
        $message=$_.Exception.Message
        if ($logPath) { try {Write-GoatLog $logPath $message 'ERROR'} catch {} }
        if ($started) {
            return [pscustomobject]@{Success=$true;Message=($item.Name+' já foi iniciado (PID '+$startedProcessId+'), mas o registro final do log falhou: '+$message+'. Acompanhe a janela aberta; não é necessário iniciar novamente.');LocalPath=$localPath;LogPath=$logPath;Started=$true}
        }
        return [pscustomobject]@{Success=$false;Message=$message;LocalPath=$localPath;LogPath=$logPath;Started=$false}
    } finally { if ($locked -and $mutex) {$mutex.ReleaseMutex()}; if ($mutex) {$mutex.Dispose()} }
}
