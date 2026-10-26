#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$nativeJson=Get-Content -LiteralPath (Join-Path $root 'data\native-options.json') -Raw -Encoding UTF8
$native=$nativeJson|ConvertFrom-Json
$toolJson=Get-Content -LiteralPath (Join-Path $root 'data\tool-rules.json') -Raw -Encoding UTF8
$tools=$toolJson|ConvertFrom-Json
$catalogJson=Get-Content -LiteralPath (Join-Path $root 'data\repositories.json') -Raw -Encoding UTF8
$catalog=$catalogJson|ConvertFrom-Json
$script:OptionDataPassed=0;$script:OptionDataSideEffects=0
function Assert-OptionData {param([bool]$Condition,[string]$Message)if(-not $Condition){throw ('ASSERTION FAILED: '+$Message)}}
function Pass-OptionData {param([string]$Name)$script:OptionDataPassed++;Write-Output ('PASS '+$Name)}
function Get-OptionDataKey {param($Target)return ($Target.Path+'|'+$Target.Name).ToLowerInvariant()}

Assert-OptionData ($native.SchemaVersion -eq 1 -and $native.Options.Count -eq 24) 'Reviewed native catalog must contain 24 individual options.'
Assert-OptionData (@($native.Options.Id|Select-Object -Unique).Count -eq 24) 'Native IDs must be unique.'
foreach($option in $native.Options){
    Assert-OptionData ($option.Id -match '^[a-z0-9-]+$' -and $option.Category -in @('Sistema','Rede')) 'Native option identity/category invalid.'
    Assert-OptionData ($option.Risk -in @('Baixo','Moderado','Alto') -and $option.RequiresRestart -is [bool]) 'Risk and session/restart requirement must be explicit.'
    Assert-OptionData ($option.SelectionPolicy -in @('Manual','LowMemory')) 'Unexpected automatic selection policy.'
    Assert-OptionData ($option.OnLabel -in @('Ativar','Aplicar') -and $option.OffLabel -in @('Desativar','Usar padrão')) 'Buttons need clear reviewed direction labels.'
    Assert-OptionData ($option.MinBuild -ge 19041 -and -not [string]::IsNullOrWhiteSpace($option.Title) -and -not [string]::IsNullOrWhiteSpace($option.Description) -and -not [string]::IsNullOrWhiteSpace($option.Benefit)) 'Native option must describe effect and supported platform.'
    if($option.MaxBuild){Assert-OptionData ($option.MaxBuild -ge $option.MinBuild) 'Build limits cannot be inverted.'}
}
Pass-OptionData '24 distinct native preferences have clear effects, directions, risks and platform limits'

$targetOwners=@{}
foreach($option in $native.Options){
    Assert-OptionData (@($option.OnTargets).Count -gt 0 -and @($option.OffTargets).Count -gt 0) 'Both directions must exist.'
    $onKeys=@{};$offKeys=@{}
    foreach($target in $option.OnTargets){
        $key=Get-OptionDataKey $target
        Assert-OptionData (-not $targetOwners.ContainsKey($key)) ('Duplicate native registry effect: '+$key)
        $targetOwners[$key]=$option.Id;$onKeys[$key]=$true
        Assert-OptionData $target.Exists 'Positive feature targets must explicitly define a value.'
    }
    foreach($target in $option.OffTargets){$offKeys[(Get-OptionDataKey $target)]=$true}
    Assert-OptionData (($onKeys.Keys|Sort-Object|ConvertTo-Json -Compress) -eq ($offKeys.Keys|Sort-Object|ConvertTo-Json -Compress)) 'Opposite direction must use exactly the same registry values.'
    Assert-OptionData (($option.OnTargets|ConvertTo-Json -Depth 6 -Compress) -ne ($option.OffTargets|ConvertTo-Json -Depth 6 -Compress)) 'On/off cannot describe identical states.'
    foreach($target in @($option.OnTargets)+@($option.OffTargets)){
        Assert-OptionData ($target.Path -match '^HK(CU|LM):\\' -and $target.Type -in @('DWord','String') -and $target.Exists -is [bool]) 'Native targets must be ordinary supported registry value operations.'
        Assert-OptionData ($target.Path -notmatch '(?i)Windows Defender|\\Services\\|WindowsUpdate|\\Control\\CI\\|DeviceGuard|\\Enum\\|\\Cryptography\\') 'Security, services, drivers and firmware are outside this preference expansion.'
        Assert-OptionData (-not [string]::IsNullOrWhiteSpace($target.Name)) 'Default values and unnamed command associations are not allowed.'
        if(-not $target.Exists){Assert-OptionData ($option.OffLabel -eq 'Usar padrão' -and $null -eq $target.Value) 'Removing a preference needs an explicit default label and null value.'}
    }
}
Assert-OptionData ($targetOwners.Count -eq 25) 'Expected 25 separate values: writing and typing are one coordinated pair.'
Pass-OptionData 'native targets are reversible value operations with no duplicate effects or security changes'

$covered=@{}
foreach($option in $native.Options){
    Assert-OptionData (@($option.Sources).Count -gt 0) 'Every native preference needs audited source evidence.'
    foreach($source in $option.Sources){
        $repo=@($catalog.Repositories|Where-Object Id -eq $source.RepositoryId)
        Assert-OptionData ($repo.Count -eq 1) 'Source repository must be cataloged.'
        $item=@($repo[0].Items|Where-Object Id -eq $source.ItemId)
        Assert-OptionData ($item.Count -eq 1 -and $item[0].SourceUrl -eq $source.Url) ('Source must match exact reviewed item URL: '+$source.ItemId)
        Assert-OptionData (-not [string]::IsNullOrWhiteSpace($source.Note)) 'Source needs a statement about its actual effect.'
        $covered[$source.RepositoryId]=$true
    }
}
Assert-OptionData ($covered.Count -eq 4) 'Native preference evidence must retain all four original projects.'
Pass-OptionData 'every native option has exact source lineage across all four upstreams'

$automatic=@($native.Options|Where-Object SelectionPolicy -ne 'Manual')
Assert-OptionData ($automatic.Count -eq 1 -and $automatic[0].Id -eq 'taskbar-animations' -and $automatic[0].RecommendedDirection -eq 'Off' -and $automatic[0].MaxBuild -eq 19045) 'Only Windows 10 taskbar animations may suggest Off for LowMemory.'
foreach($id in @('explorer-compact-view','taskbar-centered','snap-layout-flyout','taskbar-end-task')){
    $option=@($native.Options|Where-Object Id -eq $id)[0]
    Assert-OptionData ($option.MinBuild -ge 22000) 'Windows 11-specific controls cannot be applied to Windows 10.'
}
Assert-OptionData (@($native.Options|Where-Object Id -eq 'taskbar-end-task')[0].MinBuild -ge 22631) 'End Task must be limited to supported newer Windows 11.'
Assert-OptionData (@($native.Options|Where-Object Id -eq 'desktop-peek')[0].MaxBuild -eq 19045) 'Legacy Peek is limited to Windows 10.'
Pass-OptionData 'automatic direction and Windows version gates are conservative and explicit'

. (Join-Path $root 'src\Core.ps1')
function Get-GoatRegistryState {$script:OptionDataSideEffects++;throw 'TEST GUARD: demo catalog cannot read live registry.'}
function Get-GoatMemoryCompression {$script:OptionDataSideEffects++;throw 'TEST GUARD: demo catalog cannot read live memory state.'}
function Invoke-GoatNative {$script:OptionDataSideEffects++;throw 'TEST GUARD: demo catalog cannot invoke a native executable.'}
function Start-Process {$script:OptionDataSideEffects++;throw 'TEST GUARD: data validation cannot launch a process.'}
$script:GoatNativeOptionsJson=''
$scan=[pscustomobject]@{IsDemo=$true;OS=[pscustomobject]@{Supported=$true;Build=19045};Power=[pscustomobject]@{IsLaptop=$false}}
$legacy=@(Get-GoatTweaks -Scan $scan)
Assert-OptionData ($legacy.Count -eq 9) 'Legacy catalog expected before adding 24 preferences.'
foreach($entry in $legacy){foreach($target in @($entry.Targets)){Assert-OptionData (-not $targetOwners.ContainsKey((Get-OptionDataKey $target))) ('New preference duplicates existing target: '+$entry.Id)}}
$script:GoatNativeOptionsJson=$nativeJson
Assert-OptionData (@(Get-GoatNativeOptionDefinitions).Count -eq 24) 'Production parser must accept actual data.'
$expanded=@(Get-GoatTweaks -Scan $scan)
Assert-OptionData ($expanded.Count -eq 33) 'Expanded native catalog must preserve all nine original options.'
Assert-OptionData ($script:OptionDataSideEffects -eq 0) 'Demo validation cannot touch live registry, memory, native commands or processes.'
Pass-OptionData 'new preferences do not overlap legacy targets and production demo parser loads 33 options safely'

. (Join-Path $root 'src\ToolAdvisor.ps1')
$script:GoatToolRulesJson=$toolJson
$rules=@(Get-GoatToolRules)
Assert-OptionData ($tools.SchemaVersion -eq 1 -and $rules.Count -eq 44) 'Expected 44 reviewed tool metadata rules.'
$seen=@{};$toolRepos=@{}
foreach($rule in $rules){
    $key=$rule.RepositoryId+'|'+$rule.ItemId
    Assert-OptionData (-not $seen.ContainsKey($key)) 'Tool compatibility rules must be unique per actual item.';$seen[$key]=$true
    $repo=@($catalog.Repositories|Where-Object Id -eq $rule.RepositoryId)
    $item=@($repo[0].Items|Where-Object Id -eq $rule.ItemId)
    Assert-OptionData ($repo.Count -eq 1 -and $item.Count -eq 1) ('Reviewed tool item must exist: '+$key)
    Assert-OptionData ($rule.Risk -in @('Baixo','Moderado','Alto') -and -not [string]::IsNullOrWhiteSpace($rule.Alias) -and -not [string]::IsNullOrWhiteSpace($rule.Reason)) 'Tools need clear names, risks and factual reasons.'
    $toolRepos[$rule.RepositoryId]=$true
}
Assert-OptionData ($toolRepos.Count -eq 4) 'Reviewed tool metadata must include the four original projects.'
Pass-OptionData '44 individual tool rules identify real items, unique roles and honest compatibility evidence'

$diagnostics=@($rules|Where-Object CanRecommend)
Assert-OptionData ($diagnostics.Count -eq 3 -and @($diagnostics.Family|Sort-Object -Unique).Count -eq 3) 'Only three distinct reviewed diagnostic launchers may be suggested.'
foreach($rule in $diagnostics){Assert-OptionData ($rule.Role -eq 'Diagnostic' -and $rule.Requires -eq 'Any' -and $rule.ItemId -like 'file:1 Check/*.ps1' -and $rule.Risk -ne 'Alto') 'No optimizer, stress test, driver or installer can be auto-suggested.'}
foreach($name in @('cpuz.exe','gpuz.exe')){
    $rule=@($rules|Where-Object {$_.RepositoryId -eq 'ultimate' -and $_.ItemId -eq ('release:Files/'+$name)})[0]
    Assert-OptionData ($rule.Architecture -eq 'Unknown' -and -not $rule.CanRecommend) 'Direct diagnostic binary architecture must remain unknown until verified.'
}
$amd=@($rules|Where-Object ItemId -eq 'file:5 Graphics/6 Amd Settings.ps1')[0]
$nvidia=@($rules|Where-Object ItemId -eq 'file:5 Graphics/5 Nvidia Settings.ps1')[0]
Assert-OptionData ($amd.Hardware -eq 'AMD-GPU' -and $nvidia.Hardware -eq 'NVIDIA' -and -not $amd.CanRecommend -and -not $nvidia.CanRecommend) 'GPU vendor profiles must not infer applicability from CPU brand or auto-apply.'
Pass-OptionData 'only diagnostic launchers are candidates; unknown binaries and manufacturer profiles stay manual'

[pscustomobject]@{Passed=$script:OptionDataPassed;NativeOptions=24;ExpandedNativeOptions=33;ReviewedTools=44;Mode='Data and demo-only validation; no operating-system changes or external execution'}|ConvertTo-Json -Compress
