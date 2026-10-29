#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'scripts/New-LaunchCommand.ps1')
$script:Checks=0;$script:Launches=0;$script:Downloads=@();$script:Corrupt=$false;$script:DownloadFailure=$false;$script:ChildExit=0
$script:Payload=[Text.Encoding]::UTF8.GetBytes('# harmless test fixture, never executed')
$sha=[Security.Cryptography.SHA256]::Create()
try{$digest=([BitConverter]::ToString($sha.ComputeHash($script:Payload))).Replace('-','').ToLowerInvariant()}finally{$sha.Dispose()}
function Assert-Launch {param([bool]$Value,[string]$Name);if(-not $Value){throw $Name};$script:Checks++}
function Invoke-WebRequest {
    param([switch]$UseBasicParsing,[string]$Uri,[string]$OutFile,[string]$ErrorAction)
    $script:Downloads+= $OutFile
    if($script:DownloadFailure){[IO.File]::WriteAllText($OutFile,'partial');throw 'simulated network failure'}
    Assert-Launch ($Uri -eq 'https://github.com/JuliozXz/GOAT-Tweaks-V1/releases/download/v7.3.0/GOAT-Tweaks.ps1') 'Download must use immutable official release URL'
    if($script:Corrupt){[IO.File]::WriteAllText($OutFile,'corrupt')}else{[IO.File]::WriteAllBytes($OutFile,$script:Payload)}
}
function powershell.exe {
    param([switch]$NoProfile,[switch]$STA,[string]$ExecutionPolicy,[string]$File,[switch]$Demo,[switch]$ScanOnly)
    $script:Launches++
    Assert-Launch ($NoProfile -and $STA -and $ExecutionPolicy -eq 'Bypass') 'Child invocation is isolated STA and changes only the process execution policy'
    Assert-Launch ((Get-FileHash -LiteralPath $File -Algorithm SHA256).Hash -eq $digest) 'Only verified bytes reach child process'
    $script:LastFlags=@{Demo=[bool]$Demo;ScanOnly=[bool]$ScanOnly}
    $global:LASTEXITCODE=$script:ChildExit
}
foreach($mode in @('Default','Demo','Scan')){
    $command=Get-GoatLaunchCommand -Version '7.3.0' -Sha256 $digest -Demo:($mode -eq 'Demo') -ScanOnly:($mode -eq 'Scan')
    Assert-Launch ($command -notmatch '[\r\n]') 'Launch command must fit one physical line'
    $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseInput($command,[ref]$tokens,[ref]$errors)
    Assert-Launch ($errors.Count -eq 0) 'Launch command parses on Windows PowerShell 5.1'
    $calls=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object GetCommandName)
    Assert-Launch (@($calls|Where-Object {$_ -in @('Invoke-Expression','iex','Set-ExecutionPolicy','Start-Process')}).Count -eq 0) 'No remote expression evaluation or global policy changes'
    & ([scriptblock]::Create($command))
    Assert-Launch ($script:LastFlags.Demo -eq ($mode -eq 'Demo') -and $script:LastFlags.ScanOnly -eq ($mode -eq 'Scan')) 'Requested diagnostic mode is forwarded'
    Assert-Launch (-not (Test-Path -LiteralPath $script:Downloads[-1])) 'Owned downloaded script is removed after child exits'
}
$before=$script:Launches;$script:Corrupt=$true;$failed=$false
try{& ([scriptblock]::Create((Get-GoatLaunchCommand -Version '7.3.0' -Sha256 $digest)))}catch{$failed=$true}
Assert-Launch ($failed -and $script:Launches -eq $before -and -not (Test-Path -LiteralPath $script:Downloads[-1])) 'Hash mismatch prevents execution and cleans only the owned download'
$script:Corrupt=$false;$script:DownloadFailure=$true;$failed=$false
try{& ([scriptblock]::Create((Get-GoatLaunchCommand -Version '7.3.0' -Sha256 $digest)))}catch{$failed=$true}
Assert-Launch ($failed -and $script:Launches -eq $before -and -not (Test-Path -LiteralPath $script:Downloads[-1])) 'Interrupted download never starts a child and preserves unrelated files'
$script:DownloadFailure=$false;$script:ChildExit=9;$failed=$false
try{& ([scriptblock]::Create((Get-GoatLaunchCommand -Version '7.3.0' -Sha256 $digest)))}catch{$failed=$true}
Assert-Launch ($failed -and -not (Test-Path -LiteralPath $script:Downloads[-1])) 'Nonzero child exit is reported and downloaded script is cleaned'
foreach($case in @(@{Version='main';Sha256=$digest},@{Version='7.3.0';Sha256='invalid'})){
    $failed=$false;try{Get-GoatLaunchCommand @case|Out-Null}catch{$failed=$true};Assert-Launch $failed 'Version and digest are validated before generating executable text'
}
[pscustomobject]@{Module='Launch';Passed=$script:Checks;Scope='Isolated download/process fixtures; no network or Windows settings changed'}|ConvertTo-Json
