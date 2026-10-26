[CmdletBinding()]
param([switch]$RealReadOnly)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot 'src\Scanner.ps1')
. (Join-Path $projectRoot 'src\AdvancedScanner.ps1')
$passed=0
function Assert-Advanced {param([bool]$Condition,[string]$Message)if(-not $Condition){throw ('ASSERTION FAILED: '+$Message)}}
function Complete-Advanced {param([string]$Name)$script:passed++;Write-Output ('PASS '+$Name)}

if($RealReadOnly){
    $scan=Get-GoatHardwareScan
    $clock=[Diagnostics.Stopwatch]::StartNew()
    $advanced=Get-GoatAdvancedState -Scan $scan
    Assert-Advanced ($advanced.Readings.Count -eq 21) 'Real scanner must return all 21 keys even if APIs are unavailable.'
    foreach($key in $advanced.Readings.Keys){
        $reading=$advanced.Readings[$key]
        Assert-Advanced ($null -ne $reading.Text -and $null -ne $reading.Available) ('Invalid real reading: '+$key)
        if(-not $reading.Available){Assert-Advanced ($null -eq $reading.Value) ('Unavailable real reading fabricates a value: '+$key)}
    }
    Write-Output ('READONLY real scan: '+[math]::Round($clock.Elapsed.TotalSeconds,2)+'s; available='+@($advanced.Readings.Values|Where-Object Available).Count+'; errors='+$advanced.Errors.Count)
    foreach($key in @('core-parking','memory-compression','msi-storage','qos','adapter-power','windows-update','cache')){
        Write-Output ($key+': '+$advanced.Readings[$key].Text)
    }
}

$script:OriginalAdvancedCommand=(Get-Item Function:Invoke-GoatAdvancedReadCommand).ScriptBlock
$script:OriginalAdvancedNative=(Get-Item Function:Invoke-GoatAdvancedNativeRead).ScriptBlock
$script:OriginalTempObservation=(Get-Item Function:Get-GoatAdvancedTempObservation).ScriptBlock
$script:ProbeMode='blocked'
$script:ProbeCalls=0
function Invoke-GoatAdvancedReadCommand {
    param($Command,$Parameters=@{},$Properties=@(),$First=0,$TimeoutMilliseconds=2500)
    $script:ProbeCalls++
    if($script:ProbeMode -eq 'blocked'){throw 'SIMULATED: command provider unavailable'}
    switch($Command){
        'Get-MMAgent'{return [pscustomobject]@{MemoryCompression=$false}}
        'Get-CimInstance'{
            switch($Parameters.ClassName){
                'Win32_Processor'{return [pscustomobject]@{Architecture=9;NumberOfCores=6;NumberOfLogicalProcessors=12}}
                'Win32_SCSIController'{return [pscustomobject]@{Name='Mock NVMe';PNPDeviceID='PCI\MOCK'}}
                'Win32_IDEController'{return}
                'Win32_Service'{return @([pscustomobject]@{Name='wuauserv';DisplayName='Windows Update';StartMode='Manual';State='Stopped'},[pscustomobject]@{Name='BITS';DisplayName='BITS';StartMode='Manual';State='Running'},[pscustomobject]@{Name='SysMain';DisplayName='SysMain';StartMode='Auto';State='Running'})}
            }
        }
        'Get-NetTCPSetting'{Assert-Advanced ($Parameters.SettingName -eq 'Internet') 'Only the Internet TCP profile may be queried.';return [pscustomobject]@{AutoTuningLevelLocal='Normal'}}
        'Get-NetOffloadGlobalSetting'{return [pscustomobject]@{ReceiveSideScaling='Disabled'}}
        'Get-NetQosPolicy'{Assert-Advanced ($Parameters.PolicyStore -eq 'ActiveStore') 'QoS must inspect effective policies.';return}
        'Get-NetAdapterPowerManagement'{return [pscustomobject]@{Name='Mock NIC';SelectiveSuspend='Unsupported';AllowComputerToTurnOffDevice='Enabled'}}
        'Get-AppxPackage'{Assert-Advanced (-not $Parameters.ContainsKey('AllUsers')) 'Appx inventory must stay in the current-user scope.';return [pscustomobject]@{Name='Mock App';PackageFullName='Mock_1';Version='1.0';IsFramework=$false;NonRemovable=$false}}
    }
}
function Get-GoatAdvancedRegistryValue {
    param($Hive,$Path,$Name)
    $script:ProbeCalls++
    if($script:ProbeMode -eq 'blocked'){throw 'SIMULATED: registry access denied'}
    return [pscustomobject]@{Hive=$Hive;Path=$Path;Name=$Name;Exists=$false;Value=$null;Type=$null}
}
function Invoke-GoatAdvancedNativeRead {
    param($Command,$Arguments,$TimeoutMilliseconds=2500)
    $script:ProbeCalls++
    if($script:ProbeMode -eq 'blocked'){throw 'SIMULATED: native query timed out'}
    if($Command -eq 'bcdedit'){return "useplatformclock Yes`ndisabledynamictick No`n"}
    $ac='0000000a';$dc='00000003'
    if(($Arguments -join ' ') -match 'CPMAXCORES'){$ac='00000064';$dc='00000064'}
    return "GUID de plano: 381b4222-f694-41f0-9685-ff5bb260df2e`nMínimo possível: 0x00000000`nMáximo possível: 0x00000064`nIncremento: 0x00000001`nÍndice atual conectado: 0x$ac`nÍndice atual bateria: 0x$dc`n"
}
function Get-GoatInterruptConfiguration {param($PnpDeviceId,$Errors)return [pscustomobject]@{MsiEnabled=$null;InterruptPriority=$null}}
function Get-GoatAdvancedTempObservation {
    param($MaximumEntries=1000,$MaximumMilliseconds=750,$Path)
    $script:ProbeCalls++
    if($script:ProbeMode -eq 'blocked'){throw 'SIMULATED: TEMP not readable'}
    return [pscustomobject]@{Path='C:\MOCK\TEMP';BytesObserved=42;FilesObserved=1;DirectoriesVisited=1;Truncated=$true;Errors=@();DurationMs=1}
}

$expected=@('memory-compression','system-cache','cpu-architecture','core-parking','process-scheduling','msi-gpu','msi-storage','hags','rebar','cstates','timers','network-autotuning','rss','qos','adapter-power','windows-update','services','appx','cache','explorer','drivers')
$fixtureScan=[pscustomobject]@{GPU=@([pscustomobject]@{Name='Mock GPU';PnpDeviceId='PCI\GPU';MsiEnabled=$null;InterruptPriority=$null});Drivers=@([pscustomobject]@{DeviceName='Mock';DriverVersion='1';DriverDate=$null;Manufacturer='Mock'});Errors=@()}

$demo=Get-GoatAdvancedState -Demo
$demoAgain=Get-GoatAdvancedState -Demo
Assert-Advanced ($script:ProbeCalls -eq 0) 'Demo may not query any Windows provider.'
Assert-Advanced ($demo.Readings.Count -eq $expected.Count -and $demo.IsDemo) 'Demo must expose the full advanced schema.'
Assert-Advanced ($demo.Readings['memory-compression'].Available -and $demo.Readings['memory-compression'].Value -eq $false) 'Demo memory compression must match the actionable disabled-state example.'
Assert-Advanced ((ConvertTo-Json $demo -Depth 10 -Compress) -eq (ConvertTo-Json $demoAgain -Depth 10 -Compress)) 'Demo fixture must be deterministic.'
Complete-Advanced 'Demo is deterministic and never queries Windows'

$localized="Plano: 381b4222-f694-41f0-9685-ff5bb260df2e`nMinimum possible setting: 0x00000000`nMaximum possible setting: 0x00000064`nCurrent AC Power Setting Index: 0x00000019`nÍndice de configuração DC: 0x0000000f`n"
$parsed=ConvertFrom-GoatParkingQuery $localized
Assert-Advanced ($parsed.AC -eq 25 -and $parsed.DC -eq 15) 'Core parking parser must read the final AC/DC values across locales.'
$rejected=$false;try{ConvertFrom-GoatParkingQuery 'Unreadable output'|Out-Null}catch{$rejected=$true}
Assert-Advanced $rejected 'Malformed powercfg output must not be interpreted as zero.'
Complete-Advanced 'Core parking parses hex values independently of translated labels'

$script:ProbeMode='success'
$state=Get-GoatAdvancedState -Scan $fixtureScan
foreach($key in $expected){Assert-Advanced ($state.Readings.ContainsKey($key)) ('Missing reading '+$key)}
Assert-Advanced ($state.Readings['memory-compression'].Available -and $state.Readings['memory-compression'].Value -eq $false) 'A confirmed disabled state must remain available/false.'
Assert-Advanced ($state.Readings['core-parking'].Value.MinimumAC -eq 10 -and $state.Readings['core-parking'].Value.MaximumDC -eq 100) 'Power-plan bounds were not retained.'
Assert-Advanced ($state.Readings['cpu-architecture'].Value.Name -eq 'x64') 'CIM architecture must be used without model-name inference.'
Assert-Advanced ($state.Readings['hags'].Available -and $null -eq $state.Readings['hags'].Value -and $state.Readings['hags'].Text -match 'ausente') 'Absent HAGS override means default, not disabled.'
Assert-Advanced ($state.Readings['system-cache'].Available -and $null -eq $state.Readings['system-cache'].Value) 'Absent cache override must remain default/null.'
Assert-Advanced ($null -eq $state.Readings['msi-gpu'].Value[0].MsiEnabled -and $null -eq $state.Readings['msi-storage'].Value[0].MsiEnabled) 'Absent MSI declarations must remain unknown.'
Assert-Advanced ($state.Readings['rss'].Value -eq 'Disabled') 'Actual RSS state must be retained.'
Assert-Advanced ($state.Readings['timers'].Value.useplatformclock -eq 'Yes' -and $null -eq $state.Readings['timers'].Value.useplatformtick) 'BCD flags must retain raw values and absent markers.'
Assert-Advanced ($state.Readings['qos'].Value.Policies.Count -eq 0 -and -not $state.Readings['qos'].Value.NonBestEffortLimit.Exists) 'Successful empty QoS query must be distinct from an unavailable provider.'
Assert-Advanced ($state.Readings['windows-update'].Value.Services.Count -eq 2 -and $state.Readings['services'].Value.Count -eq 3) 'Service snapshot must be reused without inventing disabled status.'
Assert-Advanced (-not $state.Readings['rebar'].Available -and -not $state.Readings['cstates'].Available) 'Firmware features must remain explicitly unverified.'
Complete-Advanced 'Successful probes preserve false, absent/default, raw flags and scoped inventories'

$script:ProbeMode='blocked'
$failed=Get-GoatAdvancedState -Scan $fixtureScan
foreach($key in @('memory-compression','system-cache','cpu-architecture','core-parking','process-scheduling','msi-storage','hags','timers','network-autotuning','rss','qos','adapter-power','windows-update','services','appx','cache','explorer')){
    Assert-Advanced (-not $failed.Readings[$key].Available -and $null -eq $failed.Readings[$key].Value -and $failed.Readings[$key].Error) ('Failure fabricated a state: '+$key)
}
Assert-Advanced ($failed.Readings['drivers'].Available -and $failed.Readings['msi-gpu'].Available) 'One failed provider must not discard existing hardware-scan facts.'
Assert-Advanced ($failed.Errors.Count -ge 16) 'Provider failures must be recorded.'
Complete-Advanced 'Provider failures remain unavailable/null and do not erase independent facts'

foreach($mutation in @('Set-MMAgent','Set-NetTCPSetting','Remove-AppxPackage')){
    $rejected=$false;try{& $script:OriginalAdvancedCommand -Command $mutation|Out-Null}catch{$rejected=$true}
    Assert-Advanced $rejected ('Mutation command was accepted: '+$mutation)
}
$rejected=$false;try{& $script:OriginalAdvancedNative -Command powercfg -Arguments @('/setactive','SCHEME_CURRENT')|Out-Null}catch{$rejected=$true}
Assert-Advanced $rejected 'Native write command must be rejected before process creation.'
Complete-Advanced 'Command helpers accept only read operations'

$testParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$testRoot=Join-Path $testParent ('GOAT-AdvancedScannerTests-'+[Guid]::NewGuid().ToString('N'))
try{
    [IO.Directory]::CreateDirectory((Join-Path $testRoot 'nested'))|Out-Null
    [IO.File]::WriteAllBytes((Join-Path $testRoot 'one.bin'),[byte[]](1,2,3,4,5))
    [IO.File]::WriteAllBytes((Join-Path $testRoot 'nested\two.bin'),[byte[]](1,2,3,4,5,6,7))
    $observed=& $script:OriginalTempObservation -Path $testRoot
    Assert-Advanced ($observed.BytesObserved -eq 12 -and $observed.FilesObserved -eq 2 -and -not $observed.Truncated) 'TEMP observation must count actual fixture bytes without deleting them.'
    $limited=& $script:OriginalTempObservation -Path $testRoot -MaximumEntries 1
    Assert-Advanced ($limited.Truncated -and $limited.FilesObserved -le 1) 'Entry limit must mark a partial cache observation.'
    Assert-Advanced ((Get-Item -LiteralPath (Join-Path $testRoot 'one.bin')).Length -eq 5) 'Cache observation modified a file.'
    Complete-Advanced 'Cache inspection counts bounded observations without modifying files'
}
finally{
    $resolved=[IO.Path]::GetFullPath($testRoot)
    $prefix=$testParent.TrimEnd('\')+'\GOAT-AdvancedScannerTests-'
    if(-not $resolved.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw 'Unsafe advanced test cleanup path rejected.'}
    if(Test-Path -LiteralPath $resolved){Remove-Item -LiteralPath $resolved -Recurse -Force}
}
Write-Output "PASS: $passed advanced scanner tests; no Windows settings changed."
