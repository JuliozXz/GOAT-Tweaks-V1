#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot 'src\Core.ps1')
. (Join-Path $projectRoot 'src\Integrations.ps1')
$script:OriginalIntegrationLog=(Get-Item Function:Write-GoatLog).ScriptBlock
$script:GoatCatalogJson = Get-Content -LiteralPath (Join-Path $projectRoot 'data\repositories.json') -Raw -Encoding UTF8
$script:GoatRepositoryCatalogCache = $null
$script:OriginalCatalog = Get-GoatRepositoryCatalog
$script:Passed = 0
$script:SandboxParent = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$script:Sandbox = Join-Path $script:SandboxParent ('GOAT-IntegrationTests-' + [Guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($script:Sandbox) | Out-Null
Add-Type -AssemblyName System.IO.Compression, System.IO.Compression.FileSystem

function Assert-Integration {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}

function Assert-IntegrationThrows {
    param([scriptblock]$Operation, [string]$Message)
    $threw = $false
    try { & $Operation | Out-Null } catch { $threw = $true }
    Assert-Integration $threw $Message
}

function Complete-IntegrationTest {
    param([string]$Name)
    $script:Passed++
    Write-Output "PASS $Name"
}

function New-IntegrationFixtureItem {
    param([string]$Id='source', [string]$Path='app/main.ps1', [string]$Operation='RepositoryFile', [string]$LaunchType='ps1', [bool]$CanRun=$true)
    $name = $Path.Split('/')[-1]
    $item = [pscustomobject]@{
        Id=$Id;Name=$name;Path=$Path;RelativePath=$Path;Group='Fixtures';Kind='Script'
        Operation=$Operation;LaunchType=$LaunchType;CanRun=$CanRun;Mode='100644';ReleaseTag='fixture'
        Size=6;Sha='ce013625030ba8dba906f756967f9e9ca394464a';Sha256=''
        SourceUrl='https://github.com/fixture/Repository';DownloadUrl='https://raw.githubusercontent.com/fixture/Repository/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/'+$Path
    }
    if ($Operation -eq 'ReleaseAsset') {
        $item.Sha='';$item.Sha256='5891b5b522d5df086d0ff0b110fbd9d21bb4fc7163af34d08286a2e846f6be03'
        $item.DownloadUrl='https://github.com/fixture/Repository/releases/download/fixture/'+$name
    }
    return $item
}

function Reset-IntegrationScenario {
    param([string]$Name)
    $script:TestStorage=Join-Path $script:Sandbox $Name
    $script:StorageCalls=0;$script:ReceiveCalls=0;$script:CheckpointCalls=0
    $script:Admin=$true;$script:CheckpointFails=$false;$script:ReceiveMode='Good';$script:Points=@()
    $script:FailPostLaunchLog=$false
    $script:Processes=New-Object 'System.Collections.Generic.List[object]'
    $script:ExpectedBytes=[Text.Encoding]::ASCII.GetBytes("hello`n")
    $script:ArchiveFixture=''
    $script:FixtureRepo=[pscustomobject]@{
        Id='ultimate';Name='Fixture Repository';Owner='fixture';Repository='Repository';Commit=('a'*40)
        Items=@((New-IntegrationFixtureItem))
    }
    $store=New-IntegrationFixtureItem -Id 'store:rytunex' -Path 'store' -Operation 'OpenUri' -LaunchType 'uri'
    $store.DownloadUrl='ms-windows-store://pdp/?ProductId=9PDH8M7HF2SQ'
    $script:FixtureStore=$store
    $script:GoatRepositoryCatalogCache=[pscustomobject]@{SchemaVersion=1;Repositories=@(
        $script:FixtureRepo,
        [pscustomobject]@{Id='rytunex';Name='RyTuneX';Owner='fixture';Repository='RyTuneX';Commit=('b'*40);Items=@($store)},
        [pscustomobject]@{Id='winutil';Name='Winutil';Owner='fixture';Repository='Winutil';Commit=('c'*40);Items=@()},
        [pscustomobject]@{Id='winsux';Name='WinSux';Owner='fixture';Repository='WinSux';Commit=('d'*40);Items=@()}
    )}
}

function New-IntegrationFixtureArchive {
    param([string]$Name, [object[]]$Entries)
    $archivePath=Join-Path $script:Sandbox ($Name+'.zip')
    $archive=[IO.Compression.ZipFile]::Open($archivePath,[IO.Compression.ZipArchiveMode]::Create)
    try {
        foreach ($entry in $Entries) {
            $zipEntry=$archive.CreateEntry([string]$entry.Path)
            $stream=$zipEntry.Open()
            try { $stream.Write($entry.Bytes,0,$entry.Bytes.Length) } finally { $stream.Dispose() }
        }
    } finally { $archive.Dispose() }
    return $archivePath
}

# All operating-system mutation, networking, checkpoint and process boundaries
# below are replaced. Production path validation, catalog selection, extraction,
# hashing, logging and launch argument construction remain under test.
function Get-GoatStorageRoot { $script:StorageCalls++;return $script:TestStorage }
function Test-GoatAdministrator { return $script:Admin }
function Write-GoatLog {
    param([string]$Path,[string]$Message,[string]$Level='INFO')
    if ($script:FailPostLaunchLog -and $Message -like 'STARTED PID=*') { throw 'FIXTURE post-launch log failure' }
    & $script:OriginalIntegrationLog $Path $Message $Level
}
function New-GoatRestorePoint {
    param([string]$TransactionId,[string]$LogPath)
    $script:CheckpointCalls++
    if ($script:CheckpointFails) { throw 'FIXTURE checkpoint failure' }
    Write-GoatLog $LogPath 'FIXTURE verified checkpoint 42'
    return 42
}
function Get-CimInstance {
    [CmdletBinding()]
    param([string]$Namespace,[string]$ClassName,[int]$OperationTimeoutSec)
    if ($Namespace -ne 'root/default' -or $ClassName -ne 'SystemRestore') { throw 'TEST GUARD: unexpected CIM call.' }
    return $script:Points
}
function Receive-GoatExternalFile {
    param([uri]$Uri,[string]$Path,[Nullable[long]]$ExpectedSize,[scriptblock]$ProgressCallback)
    Assert-GoatDownloadUri $Uri
    $script:ReceiveCalls++
    [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($Path)) | Out-Null
    if ($Uri.DnsSafeHost -eq 'codeload.github.com') {
        if (-not $script:ArchiveFixture) { throw 'TEST GUARD: no fixture ZIP configured.' }
        [IO.File]::Copy($script:ArchiveFixture,$Path,$true)
        return
    }
    $bytes=$script:ExpectedBytes
    if ($script:ReceiveMode -eq 'Partial') { $bytes=[byte[]]@($bytes[0..2]) }
    if ($script:ReceiveMode -eq 'Corrupt') { $bytes=[Text.Encoding]::ASCII.GetBytes("HELLO`n") }
    [IO.File]::WriteAllBytes($Path,$bytes)
    if ($script:ReceiveMode -eq 'Throw') { throw 'FIXTURE interrupted download' }
}
function Start-Process {
    [CmdletBinding()]
    param([string]$FilePath,[object[]]$ArgumentList,[string]$WorkingDirectory,[switch]$PassThru)
    $script:Processes.Add([pscustomobject]@{FilePath=$FilePath;Arguments=@($ArgumentList);WorkingDirectory=$WorkingDirectory;PassThru=[bool]$PassThru})
    if ($PassThru) { return [pscustomobject]@{Id=4242} }
}

try {
    Assert-Integration (@($script:OriginalCatalog.Repositories).Count -eq 4) 'Four original repositories must be present.'
    $expected=@{
        winutil=@{Files=389;Assets=1;Features=397;Uris=0;Total=787}
        winsux=@{Files=8;Assets=16;Features=0;Uris=0;Total=24}
        ultimate=@{Files=108;Assets=59;Features=0;Uris=0;Total=167}
        rytunex=@{Files=200;Assets=0;Features=151;Uris=1;Total=352}
    }
    foreach ($repo in $script:OriginalCatalog.Repositories) {
        Assert-Integration ($expected.ContainsKey([string]$repo.Id)) 'Unexpected repository identity.'
        Assert-Integration ($repo.Commit -match '^[0-9a-f]{40}$') 'Repository revision must be frozen.'
        Assert-Integration ($repo.Items.Count -eq $expected[$repo.Id].Total) ('Catalog completeness: '+$repo.Id)
        Assert-Integration (@($repo.Items|Where-Object Operation -eq 'RepositoryFile').Count -eq $expected[$repo.Id].Files) ('Full source tree: '+$repo.Id)
        Assert-Integration (@($repo.Items|Where-Object Operation -eq 'ReleaseAsset').Count -eq $expected[$repo.Id].Assets) ('Full release inventory: '+$repo.Id)
        Assert-Integration (@($repo.Items|Where-Object Operation -eq 'Feature').Count -eq $expected[$repo.Id].Features) ('Full feature inventory: '+$repo.Id)
        Assert-Integration (@($repo.Items|Where-Object Operation -eq 'OpenUri').Count -eq $expected[$repo.Id].Uris) ('Native app entrypoint: '+$repo.Id)
        Assert-Integration (@($repo.Items.Id|Select-Object -Unique).Count -eq $repo.Items.Count) ('Unique item IDs: '+$repo.Id)
        foreach ($item in $repo.Items) {
            if ($item.Operation -eq 'Feature') { Assert-Integration (-not $item.CanRun -and $item.LaunchType -eq 'none') 'Native features are not standalone launchers.' }
            if ($item.Operation -eq 'RepositoryFile') {
                Assert-Integration ($item.Sha -match '^[0-9a-f]{40}$') 'Every tree file must have its Git blob hash.'
                Assert-Integration ($item.DownloadUrl.Contains('/'+$repo.Commit+'/')) 'Tree download must target frozen commit.'
            }
            if ($item.CanRun -and $item.Operation -ne 'OpenUri') {
                Assert-Integration ($item.Sha -match '^[0-9a-f]{40}$' -or $item.Sha256 -match '^[0-9a-f]{64}$') 'Runnable item requires digest.'
                Assert-Integration (-not [string]::IsNullOrWhiteSpace($item.Warning)) 'External execution requires review warning.'
            }
        }
    }
    $winsux=@($script:OriginalCatalog.Repositories|Where-Object Id -eq 'winsux')[0]
    foreach ($path in @('WinSux/stepone.ps1','WinSux/steptwo.ps1','WinSux/reg.reg','WinSux/settimerresolutionservice.cs','WinSux/start2.txt')) {
        $dependency=@($winsux.Items|Where-Object RelativePath -eq $path)
        Assert-Integration ($dependency.Count -eq 1 -and -not $dependency[0].CanRun) ('WinSux dependency cannot run alone: '+$path)
    }
    $winutil=@($script:OriginalCatalog.Repositories|Where-Object Id -eq 'winutil')[0]
    Assert-Integration (@($winutil.Items|Where-Object { $_.Operation -eq 'RepositoryFile' -and $_.CanRun }).Count -eq 0) 'Winutil library/build scripts are not app entrypoints.'
    Complete-IntegrationTest 'four complete upstream catalogs and safe classification'

    Reset-IntegrationScenario 'demo'
    $result=Invoke-GoatExternalItem ultimate source -Action Run -Demo
    Assert-Integration ($result.Success -and -not $result.Started) 'Demo run must simulate only.'
    $result=Invoke-GoatExternalItem ultimate source -Action Download -Demo
    Assert-Integration ($result.Success -and $script:StorageCalls -eq 0 -and $script:ReceiveCalls -eq 0 -and $script:CheckpointCalls -eq 0 -and $script:Processes.Count -eq 0) 'Demo must not touch storage, networking, checkpoints or processes.'
    Complete-IntegrationTest 'demonstration has zero external side effects'

    Reset-IntegrationScenario 'selection'
    $script:FixtureRepo.Items+=New-IntegrationFixtureItem -Id 'feature' -Path 'native-feature' -Operation Feature -LaunchType none -CanRun $false
    foreach ($selection in @(@('ultimate','feature'),@('unknown','source'),@('ultimate','unknown'))) {
        $result=Invoke-GoatExternalItem $selection[0] $selection[1] -Action Run
        Assert-Integration (-not $result.Success -and -not $result.Started) 'Feature/unknown selection must fail closed.'
    }
    Assert-Integration ($script:StorageCalls -eq 0 -and $script:Processes.Count -eq 0) 'Rejected selections must not reach side effects.'
    Complete-IntegrationTest 'unknown and nonrunnable items are blocked'

    Reset-IntegrationScenario 'missing-action'
    Assert-IntegrationThrows { Invoke-GoatExternalItem ultimate source -Action '' } 'Empty action must fail parameter validation.'
    Assert-Integration ($script:ReceiveCalls -eq 0 -and $script:CheckpointCalls -eq 0 -and $script:Processes.Count -eq 0) 'Empty action must be rejected before side effects.'
    $actionParameter=(Get-Command Invoke-GoatExternalItem).Parameters['Action']
    $actionMandatory=@($actionParameter.Attributes|Where-Object { $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count -gt 0
    if (-not $actionMandatory) {
        $result=Invoke-GoatExternalItem ultimate source
        Assert-Integration ($result.Success -and -not $result.Started -and $script:CheckpointCalls -eq 0 -and $script:Processes.Count -eq 0) 'Missing action must default to download only.'
    }
    Complete-IntegrationTest 'missing or empty action cannot bypass run guards'

    Reset-IntegrationScenario 'nonadmin'
    $script:Admin=$false
    $result=Invoke-GoatExternalItem ultimate source -Action Run
    Assert-Integration (-not $result.Success -and $script:StorageCalls -eq 0 -and $script:ReceiveCalls -eq 0 -and $script:Processes.Count -eq 0) 'Nonadmin run must fail before download or launch.'
    Complete-IntegrationTest 'administrator required for external maintenance execution'

    Reset-IntegrationScenario 'hashes'
    [IO.Directory]::CreateDirectory($script:TestStorage)|Out-Null
    $hashPath=Join-Path $script:TestStorage 'hello.fixture'
    [IO.File]::WriteAllBytes($hashPath,$script:ExpectedBytes)
    $sourceItem=$script:FixtureRepo.Items[0]
    $assetItem=New-IntegrationFixtureItem -Id asset -Path tool.exe -Operation ReleaseAsset -LaunchType exe
    Assert-Integration ((Get-GoatGitBlobHash $hashPath) -eq 'ce013625030ba8dba906f756967f9e9ca394464a') 'Known Git blob digest must match.'
    Assert-Integration (Test-GoatExternalFile $hashPath $sourceItem) 'Valid Git blob file must pass.'
    Assert-Integration (Test-GoatExternalFile $hashPath $assetItem) 'Valid SHA256 file must pass.'
    [IO.File]::WriteAllBytes($hashPath,[Text.Encoding]::ASCII.GetBytes("HELLO`n"))
    Assert-Integration (-not (Test-GoatExternalFile $hashPath $sourceItem) -and -not (Test-GoatExternalFile $hashPath $assetItem)) 'Same-size digest corruption must be rejected.'
    [IO.File]::WriteAllBytes($hashPath,[byte[]]@(1,2))
    Assert-Integration (-not (Test-GoatExternalFile $hashPath $assetItem)) 'Truncated file must fail.'
    Complete-IntegrationTest 'known Git SHA1 and SHA256 digests plus size verification'

    Reset-IntegrationScenario 'paths'
    foreach ($relative in @('../escape.ps1','/root.ps1','C:/escape.ps1','folder\file.ps1','file:stream','dir//file','dir/./file','dir/../file','CON.txt','dir/NUL','name.','name ','a|b','a?b')) {
        Assert-IntegrationThrows { Resolve-GoatExternalPath $script:TestStorage $relative } ('Unsafe relative path must fail: '+$relative)
    }
    $valid=Resolve-GoatExternalPath $script:TestStorage 'folder/name with spaces & plus+.ps1'
    Assert-Integration ($valid.StartsWith([IO.Path]::GetFullPath($script:TestStorage)+'\',[StringComparison]::OrdinalIgnoreCase)) 'Normal filename must stay inside cache.'
    $junction='C:\Documents and Settings'
    if ([IO.Directory]::Exists($junction) -and (([IO.File]::GetAttributes($junction) -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        Assert-IntegrationThrows { Resolve-GoatExternalPath 'C:\' 'Documents and Settings/GOAT-never-created/file.ps1' } 'Existing Windows compatibility junction must be blocked without creating any junction.'
    } else { throw 'Reparse guard fixture unavailable: expected existing C:\Documents and Settings compatibility junction.' }
    Complete-IntegrationTest 'traversal, device names, alternate streams and existing reparse point blocked'

    foreach ($uri in @('http://github.com/a','https://example.com/a','https://github.com.evil.test/a','https://user:pass@github.com/a','https://github.com:8443/a')) {
        Assert-IntegrationThrows { Assert-GoatDownloadUri ([uri]$uri) } ('Unsafe download URI: '+$uri)
    }
    foreach ($uri in @('https://github.com/a','https://raw.githubusercontent.com/a','https://codeload.github.com/a')) { Assert-GoatDownloadUri ([uri]$uri) }
    Complete-IntegrationTest 'download origins require standard HTTPS GitHub hosts'

    foreach ($mode in @('Partial','Corrupt','Throw','NoDigest')) {
        Reset-IntegrationScenario ('rejected-download-'+$mode)
        $asset=New-IntegrationFixtureItem -Id asset -Path tool.exe -Operation ReleaseAsset -LaunchType exe
        if ($mode -eq 'NoDigest') { $asset.Sha256='' } else { $script:ReceiveMode=$mode }
        $script:FixtureRepo.Items=@($asset)
        $result=Invoke-GoatExternalItem ultimate asset -Action Run
        Assert-Integration (-not $result.Success -and -not $result.Started -and $script:Processes.Count -eq 0 -and $script:CheckpointCalls -eq 0) ('Unverified download must not launch: '+$mode)
    }
    Complete-IntegrationTest 'partial, corrupt, interrupted and digestless downloads never launch'

    Reset-IntegrationScenario 'download-only'
    $asset=New-IntegrationFixtureItem -Id asset -Path tool.exe -Operation ReleaseAsset -LaunchType exe
    $script:FixtureRepo.Items=@($asset)
    $result=Invoke-GoatExternalItem ultimate asset -Action Download
    Assert-Integration ($result.Success -and -not $result.Started -and [IO.File]::Exists($result.LocalPath)) 'Download must return validated local file.'
    Assert-Integration ($script:CheckpointCalls -eq 0 -and $script:Processes.Count -eq 0) 'Download must not create a checkpoint or start a process.'
    Complete-IntegrationTest 'download action validates without launching'

    Reset-IntegrationScenario 'checkpoint-failure'
    $asset=New-IntegrationFixtureItem -Id asset -Path tool.exe -Operation ReleaseAsset -LaunchType exe
    $script:FixtureRepo.Items=@($asset);$script:CheckpointFails=$true
    $result=Invoke-GoatExternalItem ultimate asset -Action Run
    Assert-Integration (-not $result.Success -and $script:CheckpointCalls -eq 1 -and $script:Processes.Count -eq 0) 'Failed checkpoint must block external launch.'
    Complete-IntegrationTest 'checkpoint failure prevents launch after verified download'

    Reset-IntegrationScenario 'isolated-script'
    $prefix='Repository-'+$script:FixtureRepo.Commit+'/'
    $support=New-IntegrationFixtureItem -Id support -Path 'assets/resource.txt' -LaunchType none -CanRun $false
    $license=New-IntegrationFixtureItem -Id license -Path 'LICENSE' -LaunchType none -CanRun $false
    $script:FixtureRepo.Items+=@($support,$license)
    $script:ArchiveFixture=New-IntegrationFixtureArchive -Name 'complete-source' -Entries @(
        @{Path=$prefix+'app/main.ps1';Bytes=$script:ExpectedBytes},
        @{Path=$prefix+'assets/resource.txt';Bytes=$script:ExpectedBytes},
        @{Path=$prefix+'LICENSE';Bytes=$script:ExpectedBytes}
    )
    $result=Invoke-GoatExternalItem ultimate source -Action Run
    Assert-Integration ($result.Success -and $result.Started -and $script:CheckpointCalls -eq 1 -and $script:Processes.Count -eq 1) ('Valid source snapshot must launch once after checkpoint: '+$result.Message)
    $process=$script:Processes[0]
    Assert-Integration ($process.FilePath -eq "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe") 'Script must launch in separate Windows PowerShell process.'
    Assert-Integration (($process.Arguments -join ' ') -match '-NoProfile -STA -ExecutionPolicy Bypass -File') 'Launcher must use saved file and process-scoped execution policy.'
    Assert-Integration ($process.WorkingDirectory -eq (Split-Path $result.LocalPath -Parent)) 'Launcher working directory must preserve script directory.'
    Assert-Integration ([IO.File]::Exists((Join-Path (Split-Path $process.WorkingDirectory -Parent) 'assets\resource.txt'))) 'Snapshot must retain supporting directories.'
    $log=Get-Content -LiteralPath $result.LogPath -Raw -Encoding UTF8
    Assert-Integration ($log -match 'RestorePoint=42' -and $log -match 'STARTED PID=4242' -and $log -match 'DOWNLOAD VERIFIED') 'Launch log must identify integrity, protection and external PID.'
    Complete-IntegrationTest 'complete snapshot, checkpoint, log and isolated PS1 launcher'

    Reset-IntegrationScenario 'isolated-formats'
    foreach ($format in @('exe','msi','cmd')) {
        $path=Join-Path $script:Sandbox ('Folder with spaces\original.'+$format)
        Start-GoatExternalProcess -Path $path -LaunchType $format | Out-Null
        $process=$script:Processes[$script:Processes.Count-1]
        Assert-Integration ($process.WorkingDirectory -eq (Split-Path $path -Parent)) ('Isolated working directory: '+$format)
        if ($format -eq 'exe') { Assert-Integration ($process.FilePath -eq $path -and $process.Arguments.Count -eq 0) 'Original EXE must run interactively without silent install switches.' }
        if ($format -eq 'msi') { Assert-Integration ($process.FilePath.EndsWith('msiexec.exe') -and $process.Arguments[0] -eq '/i') 'MSI uses Windows Installer interactively.' }
        if ($format -eq 'cmd') { Assert-Integration ($process.FilePath.EndsWith('cmd.exe') -and ($process.Arguments -join ' ') -match '^/d /s /k ') 'CMD launches separately with autorun disabled.' }
    }
    $before=$script:Processes.Count
    Assert-IntegrationThrows { Start-GoatExternalProcess -Path (Join-Path $script:Sandbox 'original.zip') -LaunchType none } 'Resource archive must not execute.'
    Assert-IntegrationThrows { Start-GoatExternalProcess -Path (Join-Path $script:Sandbox 'unsafe%NAME%.cmd') -LaunchType cmd } 'CMD environment expansion in path must fail closed.'
    Assert-Integration ($script:Processes.Count -eq $before) 'Unsupported formats cannot start a process.'
    Complete-IntegrationTest 'EXE, MSI and CMD use isolated interactive launchers'

    foreach ($case in @('Traversal','Unexpected','Missing','Corrupt')) {
        Reset-IntegrationScenario ('archive-'+$case)
        $prefix='Repository-'+$script:FixtureRepo.Commit+'/'
        $entries=@(@{Path=$prefix+'app/main.ps1';Bytes=$script:ExpectedBytes})
        if ($case -eq 'Traversal') { $entries+=@{Path=$prefix+'../escape.ps1';Bytes=$script:ExpectedBytes} }
        if ($case -eq 'Unexpected') { $entries+=@{Path=$prefix+'extra.ps1';Bytes=$script:ExpectedBytes} }
        if ($case -eq 'Missing') { $script:FixtureRepo.Items+=New-IntegrationFixtureItem -Id missing -Path 'missing.ps1' }
        if ($case -eq 'Corrupt') { $entries=@(@{Path=$prefix+'app/main.ps1';Bytes=[Text.Encoding]::ASCII.GetBytes("HELLO`n")}) }
        $script:ArchiveFixture=New-IntegrationFixtureArchive -Name ('bad-source-'+$case) -Entries $entries
        $result=Invoke-GoatExternalItem ultimate source -Action Run
        Assert-Integration (-not $result.Success -and $script:CheckpointCalls -eq 0 -and $script:Processes.Count -eq 0) ('Bad archive must fail before launch: '+$case)
        Assert-Integration (-not [IO.File]::Exists((Join-Path $script:TestStorage 'escape.ps1'))) 'ZIP traversal cannot create an escaped file.'
    }
    Complete-IntegrationTest 'ZIP traversal, unexpected, missing and corrupt source entries blocked'

    Reset-IntegrationScenario 'recent-protection'
    $asset=New-IntegrationFixtureItem -Id asset -Path tool.exe -Operation ReleaseAsset -LaunchType exe
    $script:FixtureRepo.Items=@($asset)
    $script:Points=@([pscustomobject]@{Description='GOAT v2.2 fixture';SequenceNumber=77;CreationTime=[Management.ManagementDateTimeConverter]::ToDmtfDateTime((Get-Date).AddMinutes(-10))})
    $result=Invoke-GoatExternalItem ultimate asset -Action Run
    Assert-Integration ($result.Success -and $script:CheckpointCalls -eq 0 -and $script:Processes.Count -eq 1) 'Verified recent GOAT point must be reusable inside Windows frequency limit.'
    Complete-IntegrationTest 'existing recent verified GOAT point protects external launch'

    foreach ($case in @('DateTime','Stale','Foreign','Future')) {
        Reset-IntegrationScenario ('protection-'+$case)
        $asset=New-IntegrationFixtureItem -Id asset -Path tool.exe -Operation ReleaseAsset -LaunchType exe
        $script:FixtureRepo.Items=@($asset)
        $created=(Get-Date).AddMinutes(-10);$description='GOAT v2.2 fixture'
        if ($case -eq 'Stale') { $created=(Get-Date).AddHours(-25) }
        if ($case -eq 'Future') { $created=(Get-Date).AddHours(1) }
        if ($case -eq 'Foreign') { $description='Other application restore point' }
        $script:Points=@([pscustomobject]@{Description=$description;SequenceNumber=77;CreationTime=$created})
        $result=Invoke-GoatExternalItem ultimate asset -Action Run
        $expectedCalls=1;if ($case -eq 'DateTime') {$expectedCalls=0}
        Assert-Integration ($result.Success -and $script:CheckpointCalls -eq $expectedCalls -and $script:Processes.Count -eq 1) ('Checkpoint DateTime/age handling: '+$case)
    }
    Complete-IntegrationTest 'DateTime checkpoints work and old, foreign or future points are not reused'

    Reset-IntegrationScenario 'postlaunch-log'
    $asset=New-IntegrationFixtureItem -Id asset -Path tool.exe -Operation ReleaseAsset -LaunchType exe
    $script:FixtureRepo.Items=@($asset);$script:FailPostLaunchLog=$true
    $result=Invoke-GoatExternalItem ultimate asset -Action Run
    Assert-Integration ($script:Processes.Count -eq 1 -and $result.Started) 'A post-launch logging failure must report that the external process already started.'
    Complete-IntegrationTest 'post-launch log failure never reports a running tool as not started'

    Reset-IntegrationScenario 'store'
    $script:Admin=$false
    $result=Invoke-GoatExternalItem rytunex 'store:rytunex' -Action Run
    Assert-Integration ($result.Success -and $result.Started -and $script:Processes.Count -eq 1) 'Official Store navigation must work without administrator.'
    Assert-Integration ($script:Processes[0].FilePath -eq 'ms-windows-store://pdp/?ProductId=9PDH8M7HF2SQ') 'Only exact official product URI may open.'
    Assert-Integration ($script:StorageCalls -eq 0 -and $script:ReceiveCalls -eq 0 -and $script:CheckpointCalls -eq 0) 'Store navigation cannot download or mutate system protection.'
    $script:FixtureStore.DownloadUrl='ms-windows-store://pdp/?ProductId=OTHER'
    $result=Invoke-GoatExternalItem rytunex 'store:rytunex' -Action Run
    Assert-Integration (-not $result.Success -and $script:Processes.Count -eq 1) 'Different Store product must be blocked.'
    $script:FixtureStore.DownloadUrl='https://example.com/'
    $result=Invoke-GoatExternalItem rytunex 'store:rytunex' -Action Run
    Assert-Integration (-not $result.Success -and $script:Processes.Count -eq 1) 'Arbitrary URI must be blocked.'
    Complete-IntegrationTest 'only allowlisted RyTuneX Store navigation is started'

    [pscustomobject]@{Passed=$script:Passed;Mode='Isolated fixtures: no network, checkpoints or external processes executed'}|ConvertTo-Json -Compress
} finally {
    $script:GoatRepositoryCatalogCache=$script:OriginalCatalog
    $resolved=[IO.Path]::GetFullPath($script:Sandbox)
    if ($resolved.StartsWith($script:SandboxParent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolved -Leaf) -match '^GOAT-IntegrationTests-[0-9a-f]{32}$') {
        Remove-Item -LiteralPath $resolved -Recurse -Force -ErrorAction SilentlyContinue
    }
}
