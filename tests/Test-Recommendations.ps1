#Requires -Version 5.1
[CmdletBinding()]
param()

$ErrorActionPreference='Stop'
$projectRoot=Split-Path $PSScriptRoot -Parent
. (Join-Path $projectRoot 'src\Recommendations.ps1')
$script:OriginalRecommendationJson=Get-Content -LiteralPath (Join-Path $projectRoot 'data\recommendations.json') -Raw -Encoding UTF8
$script:GoatRecommendationJson=$script:OriginalRecommendationJson
$catalog=Get-Content -LiteralPath (Join-Path $projectRoot 'data\repositories.json') -Raw -Encoding UTF8|ConvertFrom-Json
$script:Passed=0
$script:RuntimeSideEffects=0
$script:ScanCalls=0;$script:AdvancedCalls=0

function Assert-Recommendation {
    param([bool]$Condition,[string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
}
function Assert-RecommendationThrows {
    param([scriptblock]$Operation,[string]$Message)
    $threw=$false
    try { & $Operation|Out-Null } catch {$threw=$true}
    Assert-Recommendation $threw $Message
}
function Complete-RecommendationTest {
    param([string]$Name)
    $script:Passed++;Write-Output "PASS $Name"
}
function Copy-RecommendationObject {
    param($Object)
    return ($Object|ConvertTo-Json -Depth 20|ConvertFrom-Json)
}
function Set-RecommendationFixture {
    param([object[]]$Rules)
    $script:GoatRecommendationJson=[pscustomobject]@{SchemaVersion=1;ReviewedAt='2026-10-26';Rules=$Rules}|ConvertTo-Json -Depth 20
}
function New-RecommendationReading {
    param($Value,[bool]$Available=$true,[string]$Text='Estado informado pelo provedor de teste')
    return [pscustomobject]@{Available=$Available;Value=$Value;Text=$Text}
}
function New-RecommendationState {
    param([switch]$Configured)
    $readings=@{}
    foreach ($rule in $script:OriginalMatrix.Rules) { $readings[$rule.ProbeKey]=New-RecommendationReading -Value 'Revisão requerida' }
    $readings['memory-compression']=New-RecommendationReading -Value ([bool]$Configured)
    $readings['network-autotuning']=New-RecommendationReading -Value $(if($Configured){'NORMAL'}else{'restricted'})
    $readings['rss']=New-RecommendationReading -Value $(if($Configured){'enabled'}else{'Disabled'})
    return [pscustomobject]@{Readings=$readings}
}

# These are guards, not simulated optimizations. Recommendation evaluation must
# never query the network, create protection, mutate settings or launch tools.
function Invoke-RestMethod {$script:RuntimeSideEffects++;throw 'TEST GUARD: no runtime web access.'}
function Invoke-WebRequest {$script:RuntimeSideEffects++;throw 'TEST GUARD: no runtime download.'}
function Start-Process {$script:RuntimeSideEffects++;throw 'TEST GUARD: no external tool execution.'}
function Enable-MMAgent {$script:RuntimeSideEffects++;throw 'TEST GUARD: no memory mutation.'}
function Disable-MMAgent {$script:RuntimeSideEffects++;throw 'TEST GUARD: no memory mutation.'}
function Set-NetTCPSetting {$script:RuntimeSideEffects++;throw 'TEST GUARD: no TCP mutation.'}
function Set-NetOffloadGlobalSetting {$script:RuntimeSideEffects++;throw 'TEST GUARD: no RSS mutation.'}
function Checkpoint-Computer {$script:RuntimeSideEffects++;throw 'TEST GUARD: no checkpoint.'}
function Invoke-GoatApply {$script:RuntimeSideEffects++;throw 'TEST GUARD: no apply.'}

try {
    $script:OriginalMatrix=Get-GoatRecommendationMatrix
    $script:FixtureScan=[pscustomobject]@{OS=[pscustomobject]@{Supported=$true};IsDemo=$false;ComputerName='TEST-ONLY'}
    $canonical=@('memory-compression','system-cache','core-parking','process-scheduling','msi-gpu','msi-storage','hags','rebar','cstates','timers','network-autotuning','rss','qos','adapter-power','windows-update','services','appx','cache','explorer','drivers')
    Assert-Recommendation ($script:OriginalMatrix.Rules.Count -eq $canonical.Count) 'Every requested canonical effect must exist once.'
    Assert-Recommendation (@($script:OriginalMatrix.Rules.ProbeKey|Select-Object -Unique).Count -eq $canonical.Count) 'Effects must not be duplicated in reviewed matrix.'
    $repoCoverage=@{}
    foreach ($rule in $script:OriginalMatrix.Rules) {
        Assert-Recommendation ($rule.ProbeKey -in $canonical -and $rule.Id -eq $rule.ProbeKey) 'Rule IDs must match canonical effect.'
        Assert-Recommendation ($rule.Category -in @('RAM','CPU','GPU','BIOS','Rede','Sistema','Drivers')) 'Category must be a visible diagnostic area.'
        Assert-Recommendation ($rule.Risk -in @('Baixo','Moderado','Alto') -and -not [string]::IsNullOrWhiteSpace($rule.Recommendation)) 'Each effect requires risk and reviewed explanation.'
        Assert-Recommendation (@($rule.Sources).Count -gt 0) 'Each effect needs actual evidence or explicit coverage limitation.'
        foreach ($source in $rule.Sources) {
            Assert-Recommendation ($source.Stance -in @('Enable','Disable','Reference','Review')) 'Source stance must be normalized.'
            Assert-Recommendation (-not [string]::IsNullOrWhiteSpace($source.Note)) 'Source must identify what it supports.'
            if ($source.RepositoryId -eq 'microsoft') {
                $uri=[uri]$source.Url
                Assert-Recommendation ($uri.DnsSafeHost -in @('learn.microsoft.com','devblogs.microsoft.com')) 'External evidence must use primary official documentation.'
                Assert-Recommendation (-not $source.ItemId) 'Official documentation must not invent a repository item.'
            } else {
                $repo=@($catalog.Repositories|Where-Object Id -eq $source.RepositoryId)
                Assert-Recommendation ($repo.Count -eq 1) 'Evidence must identify a cataloged project.'
                $item=@($repo[0].Items|Where-Object Id -eq $source.ItemId)
                Assert-Recommendation ($item.Count -eq 1) ('Evidence item must really exist: '+$source.ItemId)
                Assert-Recommendation ($source.Url -eq $item[0].SourceUrl) 'Source URL must match the reviewed catalog revision.'
                $repoCoverage[$source.RepositoryId]=$true
            }
        }
    }
    Assert-Recommendation (@($repoCoverage.Keys).Count -eq 4) 'All four projects need useful verified coverage.'
    $actions=@($script:OriginalMatrix.Rules|Where-Object ActionId)
    Assert-Recommendation ($actions.Count -eq 3 -and @($actions.ActionId|Sort-Object -Unique).Count -eq 3) 'Exactly three distinct native actions may be mapped.'
    foreach ($action in $actions) {
        $expected=@{'memory-compression'='memory-compression';'network-autotuning'='tcp-normal';rss='rss-on'}
        Assert-Recommendation ($expected[$action.ProbeKey] -eq $action.ActionId) 'Native action must match the canonical effect.'
    }
    Complete-RecommendationTest 'reviewed matrix covers 20 effects with real sources from all four repositories'

    $state=New-RecommendationState
    $result=@(Get-GoatRecommendations -Scan $script:FixtureScan -AdvancedState $state)
    Assert-Recommendation ($result.Count -eq 20) 'Evaluation must return one result per effect.'
    $recommended=@($result|Where-Object Status -eq 'Recomendado')
    Assert-Recommendation ($recommended.Count -eq 3 -and @($recommended|Where-Object ActionId).Count -eq 3) 'Known differing native states should offer the three reviewed actions.'
    foreach ($entry in @($result|Where-Object { $_.ProbeKey -notin @('memory-compression','network-autotuning','rss') })) {
        Assert-Recommendation ($entry.Status -eq 'Revisão manual' -and -not $entry.ActionId) 'Hardware/firmware and bulk maintenance choices stay manual.'
    }
    Complete-RecommendationTest 'known differences yield only reviewed native actions'

    $configured=New-RecommendationState -Configured
    $first=@(Get-GoatRecommendations -Scan $script:FixtureScan -AdvancedState $configured)
    $second=@(Get-GoatRecommendations -Scan $script:FixtureScan -AdvancedState $configured)
    Assert-Recommendation (@($first|Where-Object Status -eq 'Configurado').Count -eq 3) 'True/Normal/Enabled states must be configured.'
    Assert-Recommendation (@($first|Where-Object ActionId).Count -eq 0 -and @($second|Where-Object ActionId).Count -eq 0) 'Repeated scan must not propose already configured changes.'
    Assert-Recommendation (($first|Select-Object ProbeKey,Status,ActionId|ConvertTo-Json -Compress) -eq ($second|Select-Object ProbeKey,Status,ActionId|ConvertTo-Json -Compress)) 'Evaluation must be deterministic.'
    Complete-RecommendationTest 'configured states are idempotent and comparisons ignore value casing'

    foreach ($mode in @('Missing','Unavailable','Null','BooleanAsString')) {
        $state=New-RecommendationState
        if ($mode -eq 'Missing') {$state.Readings=@{}}
        if ($mode -eq 'Unavailable') {foreach($key in @($state.Readings.Keys)){$state.Readings[$key]=New-RecommendationReading -Value $false -Available $false}}
        if ($mode -eq 'Null') {foreach($key in @($state.Readings.Keys)){$state.Readings[$key]=New-RecommendationReading -Value $null}}
        if ($mode -eq 'BooleanAsString') {$state.Readings['memory-compression']=New-RecommendationReading -Value 'False'}
        $result=@(Get-GoatRecommendations -Scan $script:FixtureScan -AdvancedState $state)
        if ($mode -in @('Missing','Unavailable')) {Assert-Recommendation (@($result|Where-Object Status -ne 'Indisponível').Count -eq 0) 'Unknown/unavailable readings must remain explicitly unavailable.'}
        $target=@($result|Where-Object ProbeKey -eq 'memory-compression')[0]
        Assert-Recommendation ($target.Status -eq 'Indisponível' -and -not $target.ActionId) ('Missing/null/untyped boolean cannot recommend mutation: '+$mode)
        if($mode -eq 'Null'){Assert-Recommendation (@($result|Where-Object ActionId).Count -eq 0) 'Null native values must never offer mutations.'}
    }
    Complete-RecommendationTest 'missing, unavailable, null and string false are not real boolean false'

    $state=New-RecommendationState
    $result=@(Get-GoatRecommendations -Scan $script:FixtureScan -AdvancedState $state)
    $target=@($result|Where-Object ProbeKey -eq 'memory-compression')[0]
    Assert-Recommendation ($target.Status -eq 'Recomendado' -and $target.ActionId -eq 'memory-compression') 'Typed false must remain actionable, not be mistaken for missing data.'
    Assert-Recommendation ($target.Conflict -and $target.Detail -match 'divergem') 'Compression preference disagreement must be visible.'
    Complete-RecommendationTest 'typed false is preserved and upstream compression disagreement is shown'

    $state=New-RecommendationState
    $state.Readings=[pscustomobject]$state.Readings
    $result=@(Get-GoatRecommendations -Scan $script:FixtureScan -AdvancedState $state)
    Assert-Recommendation (@($result|Where-Object ActionId).Count -eq 3) 'JSON-like PSCustomObject readings must work as dictionaries do.'
    Complete-RecommendationTest 'both dictionary and JSON object reading containers are supported'

    $scan=Copy-RecommendationObject $script:FixtureScan;$scan.OS.Supported=$false
    $result=@(Get-GoatRecommendations -Scan $scan -AdvancedState (New-RecommendationState))
    Assert-Recommendation (@($result|Where-Object ActionId).Count -eq 0 -and @($result|Where-Object Status -eq 'Recomendado').Count -eq 0) 'Unsupported operating system must not receive executable recommendations.'
    Complete-RecommendationTest 'unsupported Windows retains review information without native actions'

    $memory=Copy-RecommendationObject @($script:OriginalMatrix.Rules|Where-Object ProbeKey -eq 'memory-compression')[0]
    $copy=Copy-RecommendationObject $memory;$copy.Id='memory-compression-reference-copy'
    $copy.Sources+= [pscustomobject]@{RepositoryId='microsoft';ItemId='';Url='https://learn.microsoft.com/en-us/powershell/module/mmagent/get-mmagent';Stance='Reference';Note='API de consulta do estado.'}
    Set-RecommendationFixture @($memory,$copy)
    $result=@(Get-GoatRecommendations -Scan $script:FixtureScan -AdvancedState (New-RecommendationState))
    Assert-Recommendation ($result.Count -eq 1 -and $result[0].Sources.Count -eq ($memory.Sources.Count+1)) 'Canonical deduplication must merge distinct sources and remove duplicate source triples.'
    Assert-Recommendation ($result[0].ActionId -eq 'memory-compression') 'Same effect/target cannot stack actions.'
    Complete-RecommendationTest 'canonical duplicates merge their evidence without stacking mutations'

    $copy=Copy-RecommendationObject $memory;$copy.Id='conflicting-memory-policy';$copy.Desired=$false
    Set-RecommendationFixture @($memory,$copy)
    $result=@(Get-GoatRecommendations -Scan $script:FixtureScan -AdvancedState (New-RecommendationState))
    Assert-Recommendation ($result.Count -eq 1 -and $result[0].Conflict -and $result[0].Status -eq 'Revisão manual' -and -not $result[0].ActionId) 'Incompatible duplicate target must be manual with no chosen action.'
    $result=@(Get-GoatRecommendations -Scan $script:FixtureScan -AdvancedState ([pscustomobject]@{Readings=@{}}))
    Assert-Recommendation ($result[0].Status -eq 'Indisponível' -and -not $result[0].ActionId) 'Unknown reading stays unavailable even when matrix rules conflict.'
    Complete-RecommendationTest 'conflicting duplicate targets cannot choose an action or invent a reading'

    foreach($value in @(@('normal','restricted'),@{Value='normal'},[pscustomobject]@{Value='normal'})) {
        $tcp=Copy-RecommendationObject @($script:OriginalMatrix.Rules|Where-Object ProbeKey -eq 'network-autotuning')[0]
        Set-RecommendationFixture @($tcp)
        $result=@(Get-GoatRecommendations -Scan $script:FixtureScan -AdvancedState ([pscustomobject]@{Readings=@{'network-autotuning'=(New-RecommendationReading -Value $value)}}))
        Assert-Recommendation ($result[0].Status -eq 'Indisponível' -and -not $result[0].ActionId) 'Structured values cannot masquerade as known scalar TCP state.'
    }
    Complete-RecommendationTest 'arrays and structured values are not interpreted as scalar configuration'

    foreach($case in @('Schema','Id','Evaluation','Action','Http','Credentials','Port','InvalidUri')) {
        $rule=Copy-RecommendationObject $memory
        if($case -eq 'Id'){$rule.Id='bad identifier'}
        if($case -eq 'Evaluation'){$rule.Evaluation='ExecuteScript'}
        if($case -eq 'Action'){$rule.ActionId='run-upstream-script'}
        if($case -eq 'Http'){$rule.Sources[0].Url='http://github.com/fixture/repository'}
        if($case -eq 'Credentials'){$rule.Sources[0].Url='https://user:password@github.com/fixture/repository'}
        if($case -eq 'Port'){$rule.Sources[0].Url='https://github.com:8443/fixture/repository'}
        if($case -eq 'InvalidUri'){$rule.Sources[0].Url='not a URL'}
        Set-RecommendationFixture @($rule)
        if($case -eq 'Schema'){$invalid=$script:GoatRecommendationJson|ConvertFrom-Json;$invalid.SchemaVersion=2;$script:GoatRecommendationJson=$invalid|ConvertTo-Json -Depth 20}
        Assert-RecommendationThrows {Get-GoatRecommendationMatrix} ('Malformed matrix must fail closed: '+$case)
    }
    Complete-RecommendationTest 'unknown evaluations/actions and malformed source URLs are rejected'

    $script:GoatRecommendationJson=$script:OriginalRecommendationJson
    function Get-GoatHardwareScan {
        param([switch]$Demo)
        $script:ScanCalls++;$script:LastScanDemo=[bool]$Demo
        return [pscustomobject]@{OS=[pscustomobject]@{Supported=$true};IsDemo=[bool]$Demo;ComputerName='TEST-ONLY'}
    }
    function Get-GoatAdvancedState {
        param([switch]$Demo,$Scan)
        $script:AdvancedCalls++;$script:LastAdvancedDemo=[bool]$Demo
        return New-RecommendationState
    }
    $combined=Get-GoatUnifiedScan -Demo
    Assert-Recommendation ($script:ScanCalls -eq 1 -and $script:AdvancedCalls -eq 1 -and $script:LastScanDemo -and $script:LastAdvancedDemo) 'Unified scan forwards demo mode once to each read-only provider.'
    Assert-Recommendation ($combined.AdvancedState -and @($combined.Recommendations).Count -eq 20) 'Combined result must include hardware, advanced readings and all recommendations.'
    Assert-Recommendation ($script:RuntimeSideEffects -eq 0) 'No recommendations test may invoke mutation, web access, checkpoints or external execution.'
    Complete-RecommendationTest 'unified scan combines providers and deterministic matrix without runtime side effects'

    # Actual demo providers must satisfy the same schema without reading this PC.
    . (Join-Path $projectRoot 'src\Core.ps1')
    . (Join-Path $projectRoot 'src\Scanner.ps1')
    . (Join-Path $projectRoot 'src\AdvancedScanner.ps1')
    function Get-CimInstance {$script:RuntimeSideEffects++;throw 'TEST GUARD: demo cannot query real CIM.'}
    function Get-ItemProperty {$script:RuntimeSideEffects++;throw 'TEST GUARD: demo cannot query real registry.'}
    function Get-MMAgent {$script:RuntimeSideEffects++;throw 'TEST GUARD: demo cannot query real memory state.'}
    $demo=Get-GoatUnifiedScan -Demo
    Assert-Recommendation ($demo.IsDemo -and $demo.AdvancedState.IsDemo) 'Both actual providers must identify simulated data.'
    foreach($key in $canonical){Assert-Recommendation ($demo.AdvancedState.Readings.ContainsKey($key)) ('Actual demo must cover matrix probe: '+$key)}
    Assert-Recommendation (@($demo.Recommendations).Count -eq 20) 'Actual demo must produce all canonical effects.'
    Assert-Recommendation (@($demo.Recommendations|Where-Object {$_.ProbeKey -in @('network-autotuning','rss') -and $_.Status -eq 'Configurado'}).Count -eq 2) 'Demo TCP/RSS examples must appear configured, not falsely recommend fixes.'
    $demoTweaks=@(Get-GoatTweaks -Scan $demo)
    Assert-Recommendation (@($demoTweaks|Where-Object {$_.Id -in @('tcp-normal','rss-on') -and $_.State -eq 'Aplicado'}).Count -eq 2) 'Core demo catalog must agree with recommendation state.'
    $demo.AdvancedState=Copy-RecommendationObject $demo.AdvancedState
    $objectTweaks=@(Get-GoatTweaks -Scan $demo)
    Assert-Recommendation (@($objectTweaks|Where-Object {$_.Id -in @('tcp-normal','rss-on') -and $_.State -eq 'Aplicado'}).Count -eq 2) 'Core demo must handle deserialized PSCustomObject readings.'
    Assert-Recommendation ($script:RuntimeSideEffects -eq 0) 'Actual demo providers cannot reach live read/write/network/process APIs.'
    Complete-RecommendationTest 'actual demo schema and core catalog agree without accessing live machine state'

    [pscustomobject]@{Passed=$script:Passed;Rules=$script:OriginalMatrix.Rules.Count;Mode='Read-only evaluation with controlled state fixtures; no operating-system changes'}|ConvertTo-Json -Compress
} finally {$script:GoatRecommendationJson=$script:OriginalRecommendationJson}
