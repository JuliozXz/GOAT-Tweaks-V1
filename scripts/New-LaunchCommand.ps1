#Requires -Version 5.1
[CmdletBinding()]
param([string]$ReleaseVersion,[string]$ExpectedSha256,[switch]$Demo,[switch]$ScanOnly)

function Get-GoatLaunchCommand {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Version,[Parameter(Mandatory)][string]$Sha256,[switch]$Demo,[switch]$ScanOnly)
    if($Version -notmatch '^\d+\.\d+\.\d+$'){throw 'Versao de release invalida.'}
    if($Sha256 -notmatch '^[a-fA-F0-9]{64}$'){throw 'SHA256 invalido.'}
    $flags=''
    if($Demo){$flags+=' -Demo'}
    if($ScanOnly){$flags+=' -ScanOnly'}
    # The expected digest is pinned in the command copied by the user. No remote
    # script runs until the complete downloaded file matches that exact digest.
    $line=@'
& { $p=Join-Path ([IO.Path]::GetTempPath()) ('GOAT-'+[guid]::NewGuid().ToString('N')+'.ps1'); try { Invoke-WebRequest -UseBasicParsing 'https://github.com/JuliozXz/GOAT-Tweaks-V1/releases/download/v__VERSION__/GOAT-Tweaks.ps1' -OutFile $p -ErrorAction Stop; if((Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash -ne '__SHA256__'){throw 'GOAT: SHA256 divergente'}; & powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File $p__FLAGS__; if($LASTEXITCODE -ne 0){throw 'GOAT: falha ao abrir aplicativo'} } finally { if(Test-Path -LiteralPath $p){Remove-Item -LiteralPath $p -Force} } }
'@
    $line.Replace('__VERSION__',$Version).Replace('__SHA256__',$Sha256.ToLowerInvariant()).Replace('__FLAGS__',$flags).Trim()
}
if($ReleaseVersion -or $ExpectedSha256){Get-GoatLaunchCommand -Version $ReleaseVersion -Sha256 $ExpectedSha256 -Demo:$Demo -ScanOnly:$ScanOnly}
