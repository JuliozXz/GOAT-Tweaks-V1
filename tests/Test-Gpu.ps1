#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Gpu.ps1')
$script:GpuChecks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Gpu {param([bool]$Condition,[string]$Name) if(-not $Condition){throw "GPU assertion failed: $Name"};$script:GpuChecks.Add($Name)}
function Assert-GpuThrows {param([scriptblock]$Code,[string]$Name) $threw=$false;try{& $Code | Out-Null}catch{$threw=$true};Assert-Gpu $threw $Name}

$demo=Get-GoatGpuCenter -Demo
Assert-Gpu ($demo.ReadOnly -and $demo.Status -eq 'DEMO' -and @($demo.Devices).Count -eq 1) 'demo is explicit and read only'
Assert-Gpu ($null -eq $demo.Devices[0].AdapterRAMGB -and $demo.Telemetry.Status -eq 'UNAVAILABLE') 'demo has no invented VRAM or sensors'

# The real providers are replaced before inventory tests. No machine mutation/API occurs.
$script:GpuFixture='multi'
function Invoke-GoatGpuInventoryQuery {
    param([string]$ClassName,[string]$Namespace,[string]$Filter)
    if($script:GpuFixture -eq 'fail'){throw 'Fixture CIM unavailable'}
    switch($ClassName){
        'Win32_VideoController' {
            if($script:GpuFixture -eq 'basic') { [pscustomobject]@{Name='Microsoft Basic Display Adapter';PNPDeviceID='ROOT\BASICDISPLAY\0000';DriverVersion='10.0';DriverDate='invalid';AdapterRAM=4294967295;ConfigManagerErrorCode=31};return }
            [pscustomobject]@{Name='GeForce fixture';PNPDeviceID='PCI\VEN_10DE&DEV_2484\ONE';DriverVersion='31.0.1';DriverDate=[datetime]'2024-01-01';AdapterRAM=4294967295;CurrentHorizontalResolution=1920;CurrentVerticalResolution=1080;CurrentRefreshRate=144;ConfigManagerErrorCode=0}
            [pscustomobject]@{Name='Intel fixture';PNPDeviceID='PCI\VEN_8086&DEV_46A6\TWO';DriverVersion='30.0.2';DriverDate='invalid';AdapterRAM=1024;ConfigManagerErrorCode=0}
            [pscustomobject]@{Name='Radeon fixture';PNPDeviceID='PCI\VEN_1002&DEV_73BF\THREE';DriverVersion='old';DriverDate='20230101000000.000000+000';AdapterRAM=1024;ConfigManagerErrorCode=0}
        }
        'Win32_PnPSignedDriver' { [pscustomobject]@{DeviceID='PCI\VEN_10DE&DEV_2484\ONE';DriverProviderName='NVIDIA';IsSigned=$true;InfName='oem22.inf';DriverVersion='32.0.9';DriverDate=[datetime]'2025-03-01'} }
        'Win32_ComputerSystem' { [pscustomobject]@{Manufacturer='LENOVO';Model='Hybrid fixture';PCSystemType=2} }
        'Win32_SystemEnclosure' { [pscustomobject]@{ChassisTypes=@(10)} }
        'WmiMonitorID' { [pscustomobject]@{UserFriendlyName=@(70,105,120,116,117,114,101,0);ManufacturerName=@(76,69,78,0);InstanceName='DISPLAY\FIXTURE';Active=$true} }
        'Win32_PerfFormattedData_GPUPerformanceCounters_GPUEngine' {
            [pscustomobject]@{Name='pid_1_luid_2_engtype_3D';UtilizationPercentage=45}
            [pscustomobject]@{Name='pid_3_luid_2_engtype_Copy';UtilizationPercentage=20}
            [pscustomobject]@{Name='invalid';UtilizationPercentage=101}
        }
        default {throw "Unexpected query: $ClassName"}
    }
}
function Get-GoatGpuRemoteContext { [pscustomobject]@{State='LOCAL_CONSOLE';IsRemoteOrUncertain=$false;Indicators=@();Source='FIXTURE'} }
$scan=Get-GoatGpuCenter -IncludeTelemetry
Assert-Gpu ($scan.ReadOnly -and $scan.Status -eq 'READ_ONLY' -and $scan.Devices.Count -eq 3) 'all three vendors and multiple GPUs inventoried'
Assert-Gpu (($scan.Devices.Vendor -join ',') -eq 'NVIDIA,Intel,AMD') 'vendor uses PCI identity'
Assert-Gpu ($scan.Devices[0].VendorId -eq '10DE' -and $scan.Devices[0].DeviceId -eq '2484') 'PCI VEN and DEV retained'
Assert-Gpu ($scan.Devices[0].DriverSigned -eq $true -and $scan.Devices[0].DriverVersion -eq '32.0.9' -and $scan.Devices[0].DriverInf -eq 'oem22.inf') 'signed driver joins by exact PnP identifier'
Assert-Gpu ($null -eq $scan.Devices[1].DriverSigned -and $null -eq $scan.Devices[1].DriverDate) 'unknown driver metadata and invalid date remain unknown'
Assert-Gpu ($scan.Devices[2].DriverVersion -eq 'old' -and $scan.Devices[2].LatestDriverStatus -eq 'NOT_CHECKED') 'old version does not imply latest comparison'
Assert-Gpu (@($scan.Devices | Where-Object {$null -ne $_.AdapterRAMGB -or $_.GpuType -ne 'UNKNOWN'}).Count -eq 0) 'WMI RAM and topology are not inferred'
Assert-Gpu ($scan.System.IsNotebook -and $scan.System.OemDriverSource -eq 'https://support.lenovo.com/') 'notebook OEM guidance preserved'
Assert-Gpu ($scan.Monitors[0].Name -eq 'Fixture' -and $null -eq $scan.Monitors[0].RefreshRateHz -and $null -eq $scan.Monitors[0].SupportedModes) 'monitor EDID does not invent modes or frequency'
Assert-Gpu ($scan.Devices[0].CurrentControllerMode.RefreshRateHz -eq 144 -and $scan.Devices[0].CurrentControllerMode.MonitorAssociation -eq 'UNKNOWN') 'controller observation is not associated to arbitrary monitor'
Assert-Gpu ($scan.Telemetry.Status -eq 'PARTIAL' -and $scan.Telemetry.EngineLoads.Count -eq 2 -and $null -eq $scan.Telemetry.Metrics[0].Value) 'engine samples bounded and not summed as total'
foreach($vendor in @('NVIDIA','AMD','Intel')) { Assert-Gpu ((Get-GoatGpuOfficialDriverSource $vendor) -like 'https://*') ('official source '+$vendor) }

$script:GpuFixture='basic';$basic=Get-GoatGpuCenter
Assert-Gpu ($basic.Devices[0].Vendor -eq 'Desconhecido' -and $null -eq $basic.Devices[0].DriverSource -and $basic.Devices[0].Status -eq 'DEVICE_ERROR') 'basic display does not become vendor-capable GPU'
$script:GpuFixture='fail';$fail=Get-GoatGpuCenter -IncludeTelemetry
Assert-Gpu ($fail.Status -eq 'UNAVAILABLE' -and $fail.Devices.Count -eq 0 -and $fail.Warnings.Count -ge 5) 'CIM failures expose unavailable inventory and causes'
Assert-Gpu ($fail.Telemetry.Status -eq 'UNAVAILABLE') 'sensor error remains unavailable'

$remote=[pscustomobject]@{State='REMOTE_OR_POSSIBLE_REMOTE'}
$ddu=@(Get-GoatGpuGuides -Vendor NVIDIA -RemoteContext $remote -LocalOperatorConfirmed -RecoveryPlanConfirmed | Where-Object Id -eq 'gpu-ddu')[0]
Assert-Gpu ($ddu.Status -eq 'BLOCKED' -and -not $ddu.CanExecute) 'DDU remains blocked during remote context'
$unknown=@(Get-GoatGpuGuides -RemoteContext ([pscustomobject]@{State='UNKNOWN'}) | Where-Object Id -eq 'gpu-ddu')[0]
Assert-Gpu ($unknown.Status -eq 'BLOCKED') 'DDU blocks unknown context'
$local=@(Get-GoatGpuGuides -Vendor AMD -RemoteContext ([pscustomobject]@{State='LOCAL_CONSOLE'}) -LocalOperatorConfirmed -RecoveryPlanConfirmed | Where-Object Id -eq 'gpu-ddu')[0]
Assert-Gpu ($local.Status -eq 'MANUAL_GUIDE' -and -not $local.CanExecute) 'DDU is still manual after prerequisites'

$profile=New-GoatGpuGameProfile -GameId 'steam:730' -GameName 'Fixture' -Goal Competitivo -GpuPnpId 'PCI\FIXTURE' -Resolution '1920x1080' -RefreshRateHz 144 -Reflex Enabled -Vrr Enabled -VSync Enabled -FpsCap 200 -CaptureRequired
$preview=Get-GoatGpuProfileAdvice $profile
Assert-Gpu ($preview.Status -eq 'GUIDANCE_ONLY' -and -not $preview.CanApply -and $preview.MeasuredBenefit -eq 'NOT_MEASURED') 'profile preview never writes settings or claims gain'
Assert-Gpu ($preview.Conflicts.Count -gt 0 -and ($preview.Recommendations -join ' ') -match 'Reflex' -and ($preview.Recommendations -join ' ') -match 'captura') 'Reflex VRR cap and capture coexistence explained'
Assert-GpuThrows {New-GoatGpuGameProfile -GameId x -ExecutablePath 'C:\game.exe'} 'path requires authorization'
Assert-GpuThrows {New-GoatGpuGameProfile -GameId x -ExecutablePath 'relative.exe' -AuthorizedPath} 'relative executable rejected'
Assert-GpuThrows {New-GoatGpuGameProfile -GameId x -Resolution 'invalid'} 'invalid resolution rejected'

$taskDir=Join-Path ([IO.Path]::GetTempPath()) ('GOAT-GPU-Test-'+[guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($taskDir)|Out-Null
try {
    $exe=Join-Path $taskDir 'fixture.exe';[IO.File]::WriteAllText($exe,'NOT AN EXECUTABLE; test path only')
    $pathProfile=New-GoatGpuGameProfile -GameId fixture -ExecutablePath $exe -AuthorizedPath
    Assert-Gpu ($pathProfile.ExecutablePath -eq $exe -and -not $pathProfile.WindowsSettingsChanged) 'authorized executable only records local path'
    $path=Join-Path $taskDir 'fixture.goat-profile.json'
    $saved=Save-GoatGpuGameProfile -Profile $profile -Path $path
    $loaded=Import-GoatGpuGameProfile -Path $path
    Assert-Gpu ($saved.Status -eq 'SAVED_LOCAL_PROFILE' -and $loaded.GameId -eq $profile.GameId -and $saved.Sha256.Length -eq 64) 'local profile roundtrip with SHA256'
    Assert-GpuThrows {Save-GoatGpuGameProfile -Profile $profile -Path $path} 'profile export never overwrites existing file'
    Assert-GpuThrows {Save-GoatGpuGameProfile -Profile $profile -Path (Join-Path $taskDir 'wrong.json')} 'profile extension restricted'
    $loaded.WindowsSettingsChanged=$true;$loaded|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $path -Encoding UTF8
    Assert-GpuThrows {Import-GoatGpuGameProfile -Path $path} 'tampered profile claiming Windows mutation rejected'
} finally {
    # This path was created by this test and is verified under the task temp root.
    $resolved=[IO.Path]::GetFullPath($taskDir)
    if(-not $resolved.StartsWith([IO.Path]::GetFullPath([IO.Path]::GetTempPath()),[StringComparison]::OrdinalIgnoreCase) -or (Split-Path $resolved -Leaf) -notlike 'GOAT-GPU-Test-*'){throw 'Unsafe test cleanup path'}
    Remove-Item -LiteralPath $resolved -Recurse -Force
}
[pscustomobject]@{Module='Gpu';Passed=$script:GpuChecks.Count;Checks=@($script:GpuChecks.ToArray());Mutation='Fixture only; no system setting changed'}|ConvertTo-Json -Depth 4
