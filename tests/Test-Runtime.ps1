#Requires -Version 5.1
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src/Runtime.ps1')
$checks=0
function Assert-Runtime {param([bool]$ok,[string]$name);if(-not $ok){throw $name};$script:checks++}
function Get-GoatActions {@([pscustomobject]@{Id='native';CatalogIds=@('WIN-001');ExecutorKind='RegistryValue';ReleaseEnabled=$true})}
function Get-GoatAdvancedSettingsAllowlist {@('ms-settings:windowsdefender')}
function Get-GoatAdvancedGuides {param($Catalog,$Inventory)@([pscustomobject]@{Id='SEC-001';Status='MANUAL_GUIDE';Title='Segurança';Risk='Alto';Reason='Procedimento assistido';Steps=@('Conferir estado');Recovery=@('Restaurar original');Prerequisites=@('Aprovação');Sources=@('https://learn.microsoft.com/')})}
$source=@([pscustomobject]@{id='WIN-001';execution_class='A_AUTO_SAFE'},[pscustomobject]@{id='SEC-001';execution_class='X_BLOCKED'},[pscustomobject]@{id='PWR-PLAN';execution_class='C_MANUAL'},[pscustomobject]@{id='OTHER';execution_class='C_MANUAL'})
$runtime=@(Get-GoatRuntimeCatalog -Catalog $source)
Assert-Runtime ($runtime.Count -eq 4) 'Every source record is represented'
Assert-Runtime ($runtime[0].RuntimeTarget -eq 'Native' -and $runtime[0].RuntimeActionIds[0] -eq 'native') 'Native entry links to a real action ID'
Assert-Runtime ($runtime[1].RuntimeTarget -eq 'Advanced' -and $runtime[1].SpecificationClass -eq 'X_BLOCKED' -and $runtime[1].execution_class -eq 'C_MANUAL') 'User-requested assisted path preserves the original restriction'
Assert-Runtime ($source[1].execution_class -eq 'X_BLOCKED') 'Runtime composition never modifies source catalog'
Assert-Runtime ($runtime[2].RuntimeTarget -eq 'Power' -and $runtime[3].RuntimeTarget -eq 'Reference') 'Power and unimplemented references remain distinguishable'
$script:Opened=@();function Start-Process {param($FilePath,$ErrorAction);$script:Opened+=$FilePath}
Open-GoatSettingsPage 'ms-settings:windowsdefender'
Assert-Runtime ($script:Opened.Count -eq 1) 'Only a supported settings page is opened'
foreach($uri in @('powershell.exe','ms-settings:unknown','https://example.com','ms-settings:windowsdefender;calc.exe')){$failed=$false;try{Open-GoatSettingsPage $uri}catch{$failed=$true};Assert-Runtime $failed 'Arbitrary catalog text cannot become a shell command'}
$session=[pscustomobject]@{State='Open';Events=@()}
function Add-GoatEvent {param($Session,$Kind,$Message);$Session.Events+= [pscustomobject]@{Kind=$Kind;Message=$Message}}
$guides=@(Get-GoatAdvancedGuides)
$failed=$false;try{Add-GoatManualRecord $session 'SEC-001' $guides}catch{$failed=$true};Assert-Runtime $failed 'Manual record requires operator confirmation'
$record=Add-GoatManualRecord $session 'SEC-001' $guides -Confirmed
Assert-Runtime ($record.State -eq 'REPORTED_MANUALLY' -and -not $record.AutomaticallyVerified -and $session.ManualRecords.Count -eq 1) 'Manual work is recorded without claiming verification'
$session.State='Finalized';$failed=$false;try{Add-GoatManualRecord $session 'SEC-001' $guides -Confirmed}catch{$failed=$true};Assert-Runtime $failed 'Finalized sessions cannot accept new manual work'
$view=Format-GoatAdvancedGuide $guides[0]
Assert-Runtime ($view -match 'RECUPERAÇÃO' -and $view -match 'FONTES' -and $view -match 'não é uma automação') 'Procedure explains its execution and recovery boundaries'
[pscustomobject]@{Module='Runtime';Passed=$checks;Scope='Isolated runtime composition, settings whitelist and manual-report contracts'}|ConvertTo-Json
