[CmdletBinding()]
param([switch]$RealReadOnly)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\Selection.ps1')
$script:Passed=0
function Assert-Selection {param([bool]$Condition,[string]$Message)if(-not $Condition){throw ('ASSERTION FAILED: '+$Message)}}
function Complete-Selection {param([string]$Name)$script:Passed++;Write-Output ('PASS '+$Name)}
function New-SelectionScan {
    param($RAM=4,$Free=2,[string]$Media='HDD',$OnBattery=$false,[bool]$Laptop=$false,[string]$Tcp='restricted',[string]$Rss='Disabled',[bool]$Connected=$true,$Threads=4)
    return [pscustomobject]@{
        OS=[pscustomobject]@{Supported=$true};Memory=[pscustomobject]@{TotalGB=$RAM;AvailableGB=$Free};CPU=[pscustomobject]@{Threads=$Threads;Cores=2}
        Power=[pscustomobject]@{IsLaptop=$Laptop};Network=@([pscustomobject]@{Status=$(if($Connected){'Up'}else{'Desconectado'})});Errors=@()
        AdvancedState=[pscustomobject]@{Readings=@{
            'memory-compression'=[pscustomobject]@{Available=$true;Value=$false}
            'network-autotuning'=[pscustomobject]@{Available=$true;Value=$Tcp}
            'rss'=[pscustomobject]@{Available=$true;Value=$Rss}
            'storage'=[pscustomobject]@{Available=$true;Value=[pscustomobject]@{Disks=@([pscustomobject]@{Name='Model with NVMe SSD words';MediaType=$Media;MediaTypeKnown=($Media-in @('HDD','SSD','SCM'));BusType='NVMe'})}}
            'battery'=[pscustomobject]@{Available=$true;Value=[pscustomobject]@{OnBattery=$OnBattery;OnAC=$(if($OnBattery-is [bool]){-not $OnBattery}else{$null})}}
        }}
    }
}
function New-SelectionTweaks {
    $items=@(
        @{Id='game-mode';Title='Game Mode';Target=$true},@{Id='capture-off';Title='Captura off';Target=$true},@{Id='memory-compression';Title='Compressão';Target=$true},
        @{Id='visual-effects';Title='Efeitos reduzidos';Target=$true},@{Id='power-high';Title='Alto desempenho';Target='HIGH';SelectionPolicy='Gaming'},
        @{Id='tcp-normal';Title='TCP normal';Target='normal'},@{Id='rss-on';Title='RSS';Target='Enabled'},@{Id='mouse-linear';Title='Mouse';Target=$true;SelectionPolicy='Manual'},
        @{Id='background-apps';Title='Background';Target=$true;SelectionPolicy='Manual'}
    )
    foreach($definition in $items){
        $data=[ordered]@{Available=$true;State='Disponível';Recommended=$true;CanDisable=$true;OnState=$false;OffState=$true}
        foreach($key in $definition.Keys){$data[$key]=$definition[$key]}
        [pscustomobject]$data
    }
    [pscustomobject]@{Id='taskbar-animations';Title='Animações';Available=$true;State='Aplicado';OnState=$true;OffState=$false;CanDisable=$true;Recommended=$true;SelectionPolicy='LowMemory';RecommendedDirection='Off';Target=$true}
}
function Find-Selection {param($Items,[string]$Id)return @($Items|Where-Object Id -eq $Id)[0]}

$tweaks=@(New-SelectionTweaks)
$weak=New-SelectionScan
$weakProfile=Get-GoatMachineProfile -Scan $weak
$weakSelection=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $weak)
Assert-Selection ($weakProfile.LowMemory -eq $true -and $weakProfile.SlowStorage -eq $true) '4 GB/HDD must be identified by declared evidence.'
Assert-Selection ((Find-Selection $weakSelection 'memory-compression').Recommended) 'Low RAM with confirmed disabled compression must suggest considering enable.'
Assert-Selection ((Find-Selection $weakSelection 'taskbar-animations').Recommended -and (Find-Selection $weakSelection 'taskbar-animations').DesiredState -eq 'Off') 'Low RAM must target Off for positive animation settings.'
Assert-Selection (-not (Find-Selection $weakSelection 'visual-effects').Recommended -and -not (Find-Selection $weakSelection 'capture-off').Recommended) 'Equilibrado must preserve appearance and capture preferences.'
Assert-Selection (@($tweaks|Where-Object{-not $_.Recommended}).Count -eq 0) 'Selection must not mutate the caller tweak objects.'
Complete-Selection '4 GB/HDD receives context-specific choices while preserving caller data and preferences'

$eight=New-SelectionScan -RAM 8 -Free 4 -Media SSD
$eightProfile=Get-GoatMachineProfile -Scan $eight
Assert-Selection ($eightProfile.LowMemory -eq $true -and $eightProfile.SlowStorage -eq $false) '8 GB/SSD must not be classified as HDD.'
$eightSelection=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $eight -Profile Jogos)
Assert-Selection ((Find-Selection $eightSelection 'game-mode').Recommended -and (Find-Selection $eightSelection 'visual-effects').Recommended) 'Jogos explicitly permits game/appearance preferences on low-memory PCs.'
Assert-Selection (-not (Find-Selection $eightSelection 'capture-off').Recommended) 'Capture must remain preserved by default even in Jogos.'
Complete-Selection '8 GB/SSD honors explicit Jogos without disabling recordings'

$strong=New-SelectionScan -RAM 32 -Free 20 -Media SSD -Tcp normal -Rss Enabled -Threads 16
$strongSelection=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $strong)
Assert-Selection (@($strongSelection|Where-Object Recommended).Count -eq 0) '32 GB/SSD with healthy sampled headroom and configured network must not receive blanket tweaks.'
Assert-Selection (-not (Find-Selection $strongSelection 'memory-compression').Recommended) 'Disabled compression alone must not be labeled a fault on a PC with headroom.'
Complete-Selection '32 GB/NVMe-style inventory differs from a constrained machine'

$pressure=New-SelectionScan -RAM 32 -Free 0.8 -Media SSD -Tcp normal -Rss Enabled
$pressureProfile=Get-GoatMachineProfile -Scan $pressure
$pressureSelection=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $pressure)
Assert-Selection ($pressureProfile.LowMemory -eq $false -and $pressureProfile.MemoryPressure -eq $true) 'Low available RAM must be distinguished from small installed RAM.'
Assert-Selection ((Find-Selection $pressureSelection 'memory-compression').Recommended) 'Observed low headroom may suggest compression even with 32 GB installed.'
Assert-Selection (-not (Find-Selection $pressureSelection 'taskbar-animations').Recommended) 'A pressure sample alone must not masquerade as low installed RAM.'
Complete-Selection 'Observed memory headroom changes selection independently of installed capacity'

foreach($onBattery in @($true,$false)){
    $portable=New-SelectionScan -RAM 16 -Free 8 -Media SSD -Laptop $true -OnBattery $onBattery
    $selection=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $portable -Profile Jogos)
    Assert-Selection (-not (Find-Selection $selection 'power-high').Recommended) 'High performance must remain manual on battery and AC.'
    $profile=Get-GoatMachineProfile $portable
    Assert-Selection ($profile.KnownPower -and $profile.OnBattery -eq $onBattery) 'Confirmed AC/battery context must be preserved exactly.'
}
Complete-Selection 'Battery and AC are distinct; high consumption is never selected automatically'

$unknown=New-SelectionScan -RAM $null -Free $null -Media Unknown -OnBattery $null -Threads $null
foreach($key in @('memory-compression','network-autotuning','rss','storage','battery')){$unknown.AdvancedState.Readings[$key].Available=$false;$unknown.AdvancedState.Readings[$key].Value=$null}
$unknownSelection=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $unknown)
$unknownProfile=Get-GoatMachineProfile $unknown
Assert-Selection ($null -eq $unknownProfile.MemoryGB -and $null -eq $unknownProfile.LowMemory -and $null -eq $unknownProfile.SlowStorage -and $null -eq $unknownProfile.OnBattery) 'Unknown probes must not become false/zero hardware facts.'
Assert-Selection (@($unknownSelection|Where-Object Recommended).Count -eq 0) 'Unknown context must block evidence-dependent preselection.'
Complete-Selection 'Unknown memory, storage and energy remain null and do not authorize changes'

$configured=@(New-SelectionTweaks)
foreach($tweak in $configured){$tweak.State='Aplicado';$tweak.OnState=$true}
($configured|Where-Object Id -eq 'taskbar-animations').OffState=$true
$configuredSelection=@(Set-GoatTweakRecommendations -Tweaks $configured -Scan $weak -Profile Jogos -PreserveCapture:$false)
Assert-Selection (@($configuredSelection|Where-Object Recommended).Count -eq 0) 'Already configured On and Off targets must never be preselected.'
$captureSelection=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $strong -Profile Jogos -PreserveCapture:$false)
Assert-Selection ((Find-Selection $captureSelection 'capture-off').Recommended) 'An explicit Jogos/capture-off preference must be respected.'
Complete-Selection 'Already configured targets are skipped; recording changes require explicit preference'

$noLink=New-SelectionScan -Connected $false
$singleCPU=New-SelectionScan -Threads 1
$noLinkSelection=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $noLink)
$singleSelection=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $singleCPU)
Assert-Selection (-not (Find-Selection $noLinkSelection 'tcp-normal').Recommended -and -not (Find-Selection $noLinkSelection 'rss-on').Recommended) 'Network repairs require a confirmed connected adapter.'
Assert-Selection (-not (Find-Selection $singleSelection 'rss-on').Recommended) 'RSS preselection requires at least two logical processors.'
Complete-Selection 'Network recommendations require current connection and eligible topology'

$mixed=New-SelectionScan -RAM 16 -Free 8 -Media SSD
$mixed.AdvancedState.Readings.storage.Value.Disks+=@([pscustomobject]@{Name='Second disk';MediaType='HDD';MediaTypeKnown=$true})
$mixedProfile=Get-GoatMachineProfile $mixed
Assert-Selection ($mixedProfile.KnownStorage -and -not $mixedProfile.KnownSlowStorage -and $null -eq $mixedProfile.SlowStorage) 'Mixed media without system-volume mapping cannot identify the Windows/game storage as slow.'
$jsonScan=$weak|ConvertTo-Json -Depth 12|ConvertFrom-Json
$jsonSelection=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $jsonScan)
Assert-Selection ((Find-Selection $jsonSelection 'memory-compression').Recommended -and (Get-GoatMachineProfile $jsonScan).LowMemory) 'JSON PSCustomObject reading maps must preserve hardware selection.'
Complete-Selection 'Mixed disks stay unclassified for performance; JSON round-trip retains facts'

$conflicts=@(
    [pscustomobject]@{Id='effect-a';Title='A';Available=$true;State='Disponível';OnState=$false;OffState=$false;CanDisable=$true;SelectionPolicy='Gaming';DesiredState='On';ConflictGroup='one-effect';Target=$true},
    [pscustomobject]@{Id='effect-b';Title='B';Available=$true;State='Disponível';OnState=$false;OffState=$false;CanDisable=$true;SelectionPolicy='Gaming';DesiredState='Off';ConflictGroup='one-effect';Target=$true}
)
$conflictSelection=@(Set-GoatTweakRecommendations -Tweaks $conflicts -Scan $weak -Profile Jogos)
Assert-Selection (@($conflictSelection|Where-Object Recommended).Count -eq 0) 'Contradictory states in the same group need manual review.'
$duplicates=@($tweaks[0],$tweaks[0])
$dedup=@(Set-GoatTweakRecommendations -Tweaks $duplicates -Scan $weak -Profile Jogos)
Assert-Selection (@($dedup|Where-Object Recommended).Count -eq 1) 'Duplicate actions must have at most one automatic selection.'
Complete-Selection 'Conflicting goals are not stacked; repeated actions have one canonical selection'

. (Join-Path $root 'src\AdvancedScanner.ps1')
$originalReadCommand=(Get-Item Function:Invoke-GoatAdvancedReadCommand).ScriptBlock
$script:StorageMode='unknown-primary'
function Invoke-GoatAdvancedReadCommand {
    param($Command,$Parameters=@{},$Properties=@(),$First=0,$TimeoutMilliseconds=2500)
    if($Command-eq 'Get-PhysicalDisk'){
        if($script:StorageMode-eq 'fallback'){throw 'SIMULATED: storage provider unavailable'}
        return [pscustomobject]@{FriendlyName='NVMe SSD fast model';MediaType='Unspecified';BusType='NVMe';Size=512GB}
    }
    if($Command-eq 'Get-CimInstance' -and $Parameters.ClassName-eq 'Win32_DiskDrive'){
        return [pscustomobject]@{Model='NVMe SSD model';InterfaceType='SCSI';MediaType='Fixed hard disk media';Size=512GB}
    }
    throw 'Unexpected storage query in test.'
}
try{
    $storage=Get-GoatAdvancedStorageContext
    Assert-Selection ($storage.Disks[0].MediaType-eq 'Unknown' -and -not $storage.Disks[0].MediaTypeKnown) 'Unspecified media must not be guessed from NVMe/SSD model or bus text.'
    $script:StorageMode='fallback'
    $storage=Get-GoatAdvancedStorageContext
    Assert-Selection ($storage.Fallback -and $storage.Disks[0].MediaType-eq 'Unknown' -and $storage.PrimaryError) 'CIM fixed disk fallback must retain unknown HDD/SSD type and primary error.'
    Complete-Selection 'Storage normalization never guesses SSD from a model name or fixed-disk label'
}
finally{Set-Item -Path Function:Invoke-GoatAdvancedReadCommand -Value $originalReadCommand}

if($RealReadOnly){
    . (Join-Path $root 'src\Scanner.ps1')
    . (Join-Path $root 'src\AdvancedScanner.ps1')
    $scan=Get-GoatHardwareScan
    $advanced=Get-GoatAdvancedState -Scan $scan
    Add-Member -InputObject $scan -NotePropertyName AdvancedState -NotePropertyValue $advanced
    $profile=Get-GoatMachineProfile $scan
    $selected=@(Set-GoatTweakRecommendations -Tweaks $tweaks -Scan $scan)
    Write-Output ('READONLY profile: '+$profile.Summary)
    Write-Output ('READONLY selected candidates: '+(@($selected|Where-Object Recommended|Select-Object -ExpandProperty Id)-join ', '))
}
Write-Output "PASS: $script:Passed selection tests; no Windows settings changed."
