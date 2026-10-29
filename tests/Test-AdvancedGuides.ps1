#requires -Version 5.1
$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot 'src/AdvancedGuides.ps1')
$checks=0
function Assert-AdvancedGuide {param([bool]$Condition,[string]$Reason) if(-not $Condition){throw ('Advanced guide: '+$Reason)};$script:checks++}
function Get-CimInstance {throw 'Guides must not query CIM.'}
function Get-Process {throw 'Guides must not query processes.'}
function Get-MMAgent {throw 'Guides must not query the real memory configuration.'}
function Start-Process {throw 'Generating guides must never launch anything.'}
function Set-ItemProperty {throw 'Guides must never write registry preferences.'}
$catalogPath=Join-Path $projectRoot 'data/catalog.json'
$sourceHash=(Get-FileHash -LiteralPath $catalogPath).Hash
$catalog=Get-Content -Raw -Encoding UTF8 -LiteralPath $catalogPath|ConvertFrom-Json
$blocked=@($catalog.controls|Where-Object execution_class -eq 'X_BLOCKED')
$definitions=@(Get-GoatAdvancedGuideDefinitions)
Assert-AdvancedGuide ($definitions.Count -eq 50 -and @($definitions.Id|Sort-Object -Unique).Count -eq 50) '50 individual definitions without duplicate aliases.'
Assert-AdvancedGuide (@($blocked|Where-Object {$_.id -notin $definitions.Id}).Count -eq 0) 'Every historical/effective blocked ID has a procedure or honest unsupported explanation.'
$demo=[pscustomobject]@{Demo=$true;OS=[pscustomobject]@{Build='26100'};Memory=[pscustomobject]@{UsedPercent=72};Security=[pscustomobject]@{HvciConfigured=$false;DefenderRealTimeEnabled=$false};GpuCenter=[pscustomobject]@{Devices=@([pscustomobject]@{Vendor='NVIDIA'});Capabilities=[pscustomobject]@{NvidiaPowerLimitConfirmed='UNKNOWN'}}}
$guides=@(Get-GoatAdvancedGuides -Catalog $catalog.controls -Inventory $demo)
Assert-AdvancedGuide ($guides.Count -eq 50) 'Full catalog selects all 50 known mappings.'
foreach($guide in $guides){
    Assert-AdvancedGuide ($guide.Status -in @('MANUAL_GUIDE','UNSUPPORTED') -and $guide.Mode -eq 'C_MANUAL') ('Visible status/mode '+$guide.Id)
    Assert-AdvancedGuide (-not $guide.CanAutomate -and -not $guide.CanApply -and -not $guide.CanMutate) ('Never treated as automatic action '+$guide.Id)
    Assert-AdvancedGuide (@($guide.Steps).Count -ge 3 -and @($guide.Recovery).Count -gt 0) ('Before/procedure/after and recovery provided '+$guide.Id)
    Assert-AdvancedGuide (-not [string]::IsNullOrWhiteSpace($guide.Reason) -and -not [string]::IsNullOrWhiteSpace($guide.Risk)) ('Reason and risk explicit '+$guide.Id)
    Assert-AdvancedGuide (-not $guide.State.Known -and $guide.State.Status -eq 'DEMO_NOT_QUERIED') ('Demo never claims real known state '+$guide.Id)
    Assert-AdvancedGuide ($guide.AvailableManual -eq ($guide.Status -eq 'MANUAL_GUIDE')) ('Manual availability is honest '+$guide.Id)
    Assert-AdvancedGuide ($guide.SourceRecordPreserved -and $guide.OriginalExecutionClass -eq 'X_BLOCKED') ('Source class kept independently '+$guide.Id)
    if($guide.Status -eq 'UNSUPPORTED'){Assert-AdvancedGuide (-not $guide.CanOpenSettings) ('No misleading settings action for unsupported item '+$guide.Id)}
    foreach($url in $guide.Sources){Assert-AdvancedGuide (Test-GoatAdvancedSourceUrl $url) ('HTTPS official source '+$guide.Id)}
    if($guide.CanOpenSettings){Assert-AdvancedGuide (Test-GoatAdvancedSettingsUri $guide.SettingsUri) ('Exact allowlisted settings page '+$guide.Id)}
}
Assert-AdvancedGuide (@($guides|Where-Object {$_.Id -eq 'PWR-SLEEPSTUDY' -and $_.AvailableManual}).Count -eq 1) 'SleepStudy has an actual supported diagnostic procedure.'
Assert-AdvancedGuide (@($guides|Where-Object {$_.Id -eq 'MEM-COMPRESSION' -and $_.AvailableManual}).Count -eq 1) 'Compression has an official cmdlet procedure.'
Assert-AdvancedGuide (@($guides|Where-Object {$_.Id -in @('SEC-002','SEC-003','STOR-IOLATENCY','GPU-VSYNCIDLE') -and $_.Status -ne 'UNSUPPORTED'}).Count -eq 0) 'No bypass or invented private registry recipe.'
$real=[pscustomobject]@{Demo=$false;OS=[pscustomobject]@{Build='19045'};RemoteContext=[pscustomobject]@{IsRemote=$true;RemoteProcessNames=@('AnyDesk')};Memory=[pscustomobject]@{UsedPercent=0};Security=[pscustomobject]@{HvciConfigured=$false;DefenderRealTimeEnabled=$true};GpuCenter=[pscustomobject]@{Devices=@([pscustomobject]@{Vendor='NVIDIA'},[pscustomobject]@{Vendor='AMD'});Capabilities=[pscustomobject]@{NvidiaPowerLimitConfirmed=$true;NvidiaClockControlConfirmed=$true;AmdTuningConfirmed=$true;GpuTuningConfirmed=$true}};Capabilities=[pscustomobject]@{CpuTuningConfirmed=$true;StorageFirmwareConfirmed=$true;InputFirmwareConfirmed=$true}}
$realGuides=@(Get-GoatAdvancedGuides -Catalog $blocked -Inventory $real)
$hvci=@($realGuides|Where-Object Id -eq 'SEC-HVCI')[0]
Assert-AdvancedGuide ($hvci.State.Known -and $hvci.State.Value -eq $false) 'Known false HVCI state survives; configured is not claimed as effective.'
$standby=@($realGuides|Where-Object Id -eq 'MEM-STANDBY')[0]
Assert-AdvancedGuide ($standby.State.Known -and $standby.State.Value -eq 0) 'Known zero metric is preserved.'
$nv=@($realGuides|Where-Object Id -eq 'GPU-003')[0]
Assert-AdvancedGuide ($nv.AvailableManual -and -not $nv.Prerequisites.MaintenanceReady -and $nv.Prerequisites.RemoteOrUnknown) 'Supported vendor does not authorize remote maintenance.'
$confirmed=@(Get-GoatAdvancedGuides -Catalog $blocked -Inventory $real -LocalOperatorConfirmed -RecoveryPlanConfirmed)
Assert-AdvancedGuide (@($confirmed|Where-Object {$_.Id -eq 'GPU-003' -and $_.Prerequisites.MaintenanceReady -and -not $_.CanAutomate}).Count -eq 1) 'Local operator and recovery unlock only assisted readiness, never automation.'
$real.GpuCenter.Capabilities.NvidiaPowerLimitConfirmed='true'
Assert-AdvancedGuide (@(Get-GoatAdvancedGuides -Catalog $blocked -Inventory $real|Where-Object {$_.Id -eq 'GPU-003' -and $_.Status -eq 'UNSUPPORTED'}).Count -eq 1) 'Truthy strings do not prove capability.'
$real.GpuCenter.Devices=@([pscustomobject]@{Vendor='Intel'})
Assert-AdvancedGuide (@(Get-GoatAdvancedGuides -Catalog $blocked -Inventory $real|Where-Object {$_.Id -eq 'GPU-NV-HDCP' -and $_.Status -eq 'UNSUPPORTED'}).Count -eq 1) 'Wrong vendor is ineligible even when settings are generally available.'
$unknown=[pscustomobject]@{OS=[pscustomobject]@{Build='unknown'};RemoteContext=[pscustomobject]@{IsRemote=$null}}
$unknownGuides=@(Get-GoatAdvancedGuides -Catalog $blocked -Inventory $unknown)
Assert-AdvancedGuide (@($unknownGuides|Where-Object CanOpenSettings).Count -eq 0) 'Unknown Windows build does not claim settings eligibility.'
Assert-AdvancedGuide (@($unknownGuides|Where-Object {$_.State.Known}).Count -eq 0) 'Missing state remains unknown.'
Assert-AdvancedGuide (-not (Test-GoatAdvancedSettingsUri 'ms-settings:windowsdefender?run=powershell')) 'Settings URI arguments are rejected.'
Assert-AdvancedGuide (-not (Test-GoatAdvancedSettingsUri 'file:///C:/Windows/System32/cmd.exe')) 'Executable URI rejected.'
Assert-AdvancedGuide (-not (Test-GoatAdvancedSourceUrl 'https://microsoft.com.attacker.example/x')) 'Official-domain suffix spoof rejected.'
Assert-AdvancedGuide (-not (Test-GoatAdvancedSourceUrl 'https://user:secret@microsoft.com/x')) 'Source credentials rejected.'
Assert-AdvancedGuide (-not (Test-GoatAdvancedSourceUrl 'http://learn.microsoft.com/x')) 'Plain HTTP rejected.'
Assert-AdvancedGuide (@(Get-GoatAdvancedGuides -Catalog @() -Inventory $demo).Count -eq 0) 'Empty selection does not fabricate catalog records.'
Assert-AdvancedGuide (@(Get-GoatAdvancedGuides -Catalog @($catalog) -Inventory $demo).Count -eq 50) 'Catalog wrapper object is accepted.'
Assert-AdvancedGuide ((Get-FileHash -LiteralPath $catalogPath).Hash -eq $sourceHash) 'Generating manual guidance never modifies source data.'
$tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot 'src/AdvancedGuides.ps1'),[ref]$tokens,[ref]$errors)
Assert-AdvancedGuide (@($errors).Count -eq 0) 'PowerShell parser accepts the module.'
$commands=@($ast.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object {$_.GetCommandName()})
Assert-AdvancedGuide (@($commands|Where-Object {$_ -match '^(Invoke-Expression|Start-Process|Get-CimInstance|Set-ItemProperty|Remove-Item|Restart-Computer|Stop-Process|Disable-MMAgent|Enable-MMAgent|reg|bcdedit|powercfg)$'}).Count -eq 0) 'Documented commands are strings; no launch, mutation, reboot or sensor query occurs.'
[pscustomobject]@{Module='AdvancedGuides';Passed=$checks;GuideDefinitions=50;AvailableInDemo=@($guides|Where-Object AvailableManual).Count;UnsupportedInDemo=@($guides|Where-Object Status -eq UNSUPPORTED).Count;RealSystemQueries=0;Mutations=0}|ConvertTo-Json
