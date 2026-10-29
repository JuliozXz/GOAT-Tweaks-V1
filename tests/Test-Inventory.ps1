#requires -Version 5.1
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot 'src/Inventory.ps1')
$checks=0
function Assert-Inventory {
    param([bool]$Condition,[string]$Message)
    if(-not $Condition){throw ('Inventory test failed: '+$Message)}
    $script:checks++
}
$deny={throw 'A real provider must not be called in this test.'}
$demo=Get-GoatInventory -Demo -IncludeGpu -QueryProvider $deny -RegistryProvider $deny -ProcessProvider $deny -AppProvider $deny
Assert-Inventory ($demo.Demo -and $demo.ReadOnly -and $demo.Status -eq 'DEMO') 'Demo must be explicitly simulated and read-only.'
Assert-Inventory ($null -eq $demo.Telemetry.CPU.TotalPercent -and $null -eq $demo.Telemetry.GpuTotalPercent) 'Demo must not invent measured telemetry.'
Assert-Inventory ($demo.RemoteContext.DriverMaintenanceBlocked) 'Demo does not authorize driver maintenance.'
$captured=New-Object 'System.Collections.Generic.List[object]'
$provider={
    param($ClassName,$Namespace,$Property,$Filter,$TimeoutSec)
    $captured.Add([pscustomobject]@{ClassName=$ClassName;Namespace=$Namespace;Property=$Property;Filter=$Filter;TimeoutSec=$TimeoutSec})
    switch($ClassName){
        'Win32_OperatingSystem' {[pscustomobject]@{Caption='Test Windows';Version='10.0';BuildNumber='19045';OperatingSystemSKU=48;OSArchitecture='64-bit';TotalVisibleMemorySize=1000000;FreePhysicalMemory=100000}}
        'Win32_Processor' {[pscustomobject]@{Name='Test CPU';NumberOfCores=6;NumberOfLogicalProcessors=12}}
        'Win32_PhysicalMemory' {[pscustomobject]@{Capacity=1024000000;Speed=3200;ConfiguredClockSpeed=2933}}
        'Win32_LogicalDisk' {[pscustomobject]@{DeviceID='C:';FileSystem='NTFS';Size=1000;FreeSpace=50;DriveType=3}}
        'Win32_DiskDrive' {[pscustomobject]@{Model='Test Disk';MediaType='Fixed';Size=1000;InterfaceType='SCSI';Status='OK'}}
        'MSFT_StorageReliabilityCounter' {throw [TimeoutException]::new('provider timeout')}
        'Win32_NetworkAdapter' {[pscustomobject]@{Name='Test NIC';NetConnectionID='Ethernet';Speed=1000000000;PhysicalAdapter=$true;NetEnabled=$true}}
        'Win32_StartupCommand' {[pscustomobject]@{Name='Test Startup';Location='HKCU/Run';Command='TOKEN_DO_NOT_COLLECT';User='PRIVATE_USER'}}
        'Win32_DeviceGuard' {[pscustomobject]@{VirtualizationBasedSecurityStatus=2;SecurityServicesConfigured=@(1,2);SecurityServicesRunning=@(1,2)}}
        'MSFT_MpComputerStatus' {[pscustomobject]@{AntivirusEnabled=$true;RealTimeProtectionEnabled=$true;AMServiceEnabled=$true}}
        'Win32_PerfFormattedData_PerfOS_Processor' {@([pscustomobject]@{Name='_Total';PercentProcessorTime=0},[pscustomobject]@{Name='0';PercentProcessorTime=10})}
        'Win32_PerfFormattedData_PerfOS_Memory' {[pscustomobject]@{CommittedBytes=500000;CommitLimit=2000000;AvailableBytes=102400000}}
        'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' {@([pscustomobject]@{Name='engine_3D';UtilizationPercentage=70},[pscustomobject]@{Name='engine_Copy';UtilizationPercentage=60},[pscustomobject]@{Name='engine_invalid';UtilizationPercentage='N/A'})}
        default {throw 'Unexpected provider class.'}
    }
}.GetNewClosure()
$registry={param($Hive,$Path,$Name,$KeyExists) if($KeyExists){return ($Path -match 'WindowsUpdate')};if($Name -eq 'EnableLUA' -or $Name -eq 'Enabled'){return 1};return $null}
$inventory=Get-GoatInventory -TimeoutSec 2 -QueryProvider $provider -RegistryProvider $registry -ProcessProvider {@('AnyDesk','private_unrelated_process')} -AppProvider {@([pscustomobject]@{Name='Steam';Version='test';Source='Test fixture'})}
Assert-Inventory ($inventory.Status -eq 'PARTIAL') 'A missing provider must produce a partial inventory.'
Assert-Inventory ($captured.Count -eq 13 -and @($captured | Where-Object TimeoutSec -ne 2).Count -eq 0) 'Every CIM query must carry the bounded operation timeout.'
Assert-Inventory ($inventory.OS.Build -eq '19045' -and $inventory.OS.Edition -eq 48) 'OS edition/build read from the provider.'
Assert-Inventory ($inventory.CPU.Cores -eq 6 -and $inventory.CPU.LogicalProcessors -eq 12) 'CPU counts remain provider-derived.'
Assert-Inventory ($inventory.Memory.TotalBytes -eq 1024000000 -and $inventory.Memory.UsedPercent -eq 90) 'Memory KiB conversion and used percent are correct.'
Assert-Inventory ($inventory.Disks[0].FreePercent -eq 5) 'Disk free-space percentage uses actual bytes.'
Assert-Inventory ($inventory.StorageReliability.Status -eq 'UNAVAILABLE' -and @($inventory.StorageReliability.Devices).Count -eq 0) 'Unavailable SMART metrics do not become healthy or zero.'
Assert-Inventory (@($inventory.SourceIssues | Where-Object Source -match 'StorageReliabilityCounter').Count -eq 1) 'Provider failures are explicit.'
Assert-Inventory ($inventory.Telemetry.CPU.TotalPercent -eq 0) 'A valid zero CPU reading must be preserved.'
Assert-Inventory (@($inventory.Telemetry.GpuEngines).Count -eq 2 -and $null -eq $inventory.Telemetry.GpuTotalPercent) 'Per-engine GPU values are validated and never summed into a total.'
Assert-Inventory ($inventory.RemoteContext.IsRemote -ne $false -and @($inventory.RemoteContext.RemoteProcessNames).Count -eq 1) 'Remote software presence must remain conservatively uncertain.'
Assert-Inventory ($inventory.Reboot.Pending -eq $true -and $inventory.Reboot.Reasons -contains 'Windows Update') 'Reboot flags are visible without restarting.'
$serialized=$inventory | ConvertTo-Json -Depth 20
Assert-Inventory ($serialized -notmatch 'TOKEN_DO_NOT_COLLECT|PRIVATE_USER|private_unrelated_process') 'Secrets, startup commands and unrelated process names are not collected.'
$advice=@(Get-GoatDiagnosis -Inventory $inventory -Objective Competitivo)
Assert-Inventory ($advice.Count -gt 0 -and $advice.Count -le 7) 'Diagnosis returns a bounded set of relevant suggestions.'
Assert-Inventory (@($advice | Where-Object {$_.Execution -ne 'GuideOnly' -or $_.PerformanceEvidence -ne 'Nao medido'}).Count -eq 0) 'Suggestions never authorize mutations or claim measured FPS.'
Assert-Inventory (@($advice | Where-Object Id -eq 'RAM-PRESSURE').Count -eq 1) 'Memory pressure leads to a contextual hypothesis.'
Assert-Inventory (@($advice | Where-Object Id -eq 'DISK-SPACE').Count -eq 1) 'Low free space leads to contextual advice.'
$failed=Get-GoatInventory -QueryProvider $deny -RegistryProvider $deny -ProcessProvider $deny -AppProvider $deny
Assert-Inventory ($null -eq $failed.OS.Build -and $null -eq $failed.Memory.TotalBytes -and $null -eq $failed.Telemetry.CPU.TotalPercent) 'Provider failure leaves values null rather than fabricated zero.'
Assert-Inventory ($failed.RemoteContext.DriverMaintenanceBlocked -and $null -eq $failed.Reboot.Pending) 'Uncertainty blocks driver work and keeps reboot state unknown.'
Assert-Inventory (@($failed.SourceIssues).Count -ge 13) 'Failures remain auditable.'
Set-StrictMode -Version Latest
$strict=Get-GoatInventory -QueryProvider { [pscustomobject]@{} } -RegistryProvider { $null } -ProcessProvider { @() } -AppProvider { @() }
Assert-Inventory ($null -eq $strict.Memory.UsedPercent -and $null -eq $strict.CPU.Cores) 'Missing CIM properties tolerate a strict caller and remain unknown.'
Set-StrictMode -Off
$savedInventory=(Get-Command Get-GoatInventory).ScriptBlock
$savedGpuCommand=Get-Command Get-GoatGpuCenter -ErrorAction SilentlyContinue
$savedGpu=if($savedGpuCommand){$savedGpuCommand.ScriptBlock}else{$null}
$wrapperBaseCalls=0;$wrapperGpuCalls=0;$wrapperCalls=New-Object 'System.Collections.Generic.List[object]'
try {
    function Get-GoatInventory {
        param([switch]$Demo,[switch]$SkipGpuTelemetry,[switch]$IncludeGpu)
        $script:wrapperBaseCalls++
        $wrapperCalls.Add([pscustomobject]@{Kind='base';Demo=[bool]$Demo;SkipGpuTelemetry=[bool]$SkipGpuTelemetry;IncludeGpu=[bool]$IncludeGpu})
        & $savedInventory -Demo:$Demo -SkipGpuTelemetry:$SkipGpuTelemetry -QueryProvider $provider -RegistryProvider $registry -ProcessProvider {@()} -AppProvider {@()}
    }
    function Get-GoatGpuCenter {
        param([switch]$Demo,[switch]$IncludeTelemetry)
        $script:wrapperGpuCalls++
        $wrapperCalls.Add([pscustomobject]@{Kind='gpu';Demo=[bool]$Demo;IncludeTelemetry=[bool]$IncludeTelemetry})
        [pscustomobject]@{Status=$(if($Demo){'DEMO'}else{'READ_ONLY'});Devices=@();Telemetry=[pscustomobject]@{EngineLoads=$(if($Demo){@()}else{@([pscustomobject]@{Instance='test_3D';Value=12;Source='Fixture'})})};RemoteContext=[pscustomobject]@{IsRemoteOrUncertain=$true};Capabilities=[pscustomobject]@{Vrr='UNKNOWN';Hags='UNKNOWN';ActiveGameGpu='UNKNOWN';DedicatedVram='UNKNOWN'}}
    }
    $countBeforeDemo=$captured.Count
    $completeDemo=Get-GoatCompleteInventory -Demo
    Assert-Inventory ($completeDemo.GpuCenter.Status -eq 'DEMO' -and $captured.Count -eq $countBeforeDemo) 'Complete demo forwards Demo to both modules and does not consult CIM.'
    Assert-Inventory ($wrapperBaseCalls -eq 1 -and $wrapperGpuCalls -eq 1) 'Complete demo invokes the base and GPU inventory exactly once.'
    $beforeReal=$captured.Count
    $completeReal=Get-GoatCompleteInventory
    Assert-Inventory (($captured.Count-$beforeReal) -eq 12) 'Complete inventory base skips the duplicate GPU engine query.'
    Assert-Inventory ($wrapperBaseCalls -eq 2 -and $wrapperGpuCalls -eq 2) 'Complete real fixture invokes each inventory module exactly once.'
    Assert-Inventory (@($wrapperCalls | Where-Object {$_.Kind -eq 'gpu' -and -not $_.IncludeTelemetry}).Count -eq 0) 'The complete GPU query includes telemetry.'
    Assert-Inventory ($completeReal.GpuCenter.Status -eq 'READ_ONLY' -and @($completeReal.Telemetry.GpuEngines).Count -eq 1 -and $null -eq $completeReal.Telemetry.GpuTotalPercent) 'Complete inventory forwards GPU source data without creating a total.'
    $gpuAdvice=@(Get-GoatDiagnosis -Inventory $completeReal -Objective Equilibrado)
    Assert-Inventory (@($gpuAdvice | Where-Object Id -eq 'GPU-CAPABILITIES').Count -eq 1) 'Unknown GPU capabilities produce explicit advice instead of inferred settings.'
    function Get-GoatGpuCenter {param([switch]$Demo,[switch]$IncludeTelemetry) throw 'fixture provider failure'}
    $completeFailure=Get-GoatCompleteInventory
    Assert-Inventory ($completeFailure.GpuCenter.Status -eq 'UNAVAILABLE' -and @($completeFailure.GpuCenter.Devices).Count -eq 0) 'Complete inventory preserves a visible GPU object on provider failure.'
    Assert-Inventory ($completeFailure.GpuCenter.Capabilities.Hags -eq 'UNKNOWN' -and $completeFailure.RemoteContext.DriverMaintenanceBlocked) 'GPU failure keeps dependent capabilities unknown and driver maintenance blocked.'
} finally {
    Set-Item function:Get-GoatInventory -Value $savedInventory
    if($savedGpu){Set-Item function:Get-GoatGpuCenter -Value $savedGpu}else{Remove-Item function:Get-GoatGpuCenter -ErrorAction SilentlyContinue}
}
$partialRebootRegistry={param($Hive,$Path,$Name,$KeyExists) if($Name -eq 'PendingFileRenameOperations'){throw 'read denied'};if($KeyExists){return $false};return $null}
$partialReboot=Get-GoatInventory -QueryProvider { @() } -RegistryProvider $partialRebootRegistry -ProcessProvider {@()} -AppProvider {@()}
Assert-Inventory ($null -eq $partialReboot.Reboot.Pending) 'A failed reboot flag read cannot become a confirmed no-reboot state.'
[pscustomobject]@{Suite='Inventory';Passed=$checks;Failed=0;DemoQueries=0;RealSystemQueries=0;Scope='Deterministic provider fixtures, not hardware compatibility certification'}
