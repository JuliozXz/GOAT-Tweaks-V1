$ErrorActionPreference='Stop'
if($env:OS -ne 'Windows_NT'){throw 'GOAT Tweaks requer Windows 10/11 x64.'}
if($PSVersionTable.PSEdition -ne 'Desktop' -or -not [Environment]::Is64BitProcess -or (-not $ScanOnly -and [Threading.Thread]::CurrentThread.ApartmentState -ne 'STA')){
    if(-not $script:GoatLaunchPath){throw 'Salve o arquivo e execute com Windows PowerShell 5.1 x64 em modo STA.'}
    $hostPath=Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if(-not [Environment]::Is64BitProcess){$hostPath=Join-Path $env:WINDIR 'Sysnative\WindowsPowerShell\v1.0\powershell.exe'}
    $launch=@('-NoProfile','-STA','-File',$script:GoatLaunchPath)
    if($Demo){$launch+='-Demo'};if($ScanOnly){$launch+='-ScanOnly'}
    if($DataRoot){$launch+=@('-DataRoot',$DataRoot)};if($SessionPath){$launch+=@('-SessionPath',$SessionPath)}
    & $hostPath @launch
    if($LASTEXITCODE -ne 0){throw ('Falha ao iniciar Windows PowerShell: '+$LASTEXITCODE)}
    return
}
foreach($name in @('Core','Gpu','Inventory','AdvancedGuides','Power','Runtime','Benchmark','Reports','Presentation')){. ([scriptblock]::Create($script:GoatSources[$name]))}
$script:GoatCoreSource=$script:GoatSources.Core
$script:GoatPowerSource=$script:GoatSources.Power
if($ScanOnly){Get-GoatCompleteInventory -Demo:$Demo|ConvertTo-Json -Depth 24;return}
. ([scriptblock]::Create($script:GoatSources.App))
Show-GoatApp -Demo:$Demo -DataRoot $DataRoot -SessionPath $SessionPath
