[CmdletBinding()]
param([switch]$RequireActualRules)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
. (Join-Path $root 'src\ToolAdvisor.ps1')
$script:AdvisorPassed=0
$script:AdvisorFailures=New-Object 'System.Collections.Generic.List[string]'
function Assert-Advisor {param([bool]$Condition,[string]$Message)if(-not $Condition){throw ('ASSERTION FAILED: '+$Message)}}
function Invoke-AdvisorTest {
    param([string]$Name,[scriptblock]$Body)
    try{& $Body;$script:AdvisorPassed++;Write-Output ('PASS '+$Name)}
    catch{$script:AdvisorFailures.Add($Name+': '+$_.Exception.Message);Write-Output ('FAIL '+$Name+': '+$_.Exception.Message)}
}
function New-AdvisorItem {
    param([string]$Id,[string]$RepositoryId='ultimate',[bool]$CanRun=$true,[string]$Operation='ReleaseAsset')
    return [pscustomobject]@{Id=$Id;RepositoryId=$RepositoryId;Name=$Id;CanRun=$CanRun;Operation=$Operation;Group='Mock category'}
}
function New-AdvisorCatalog {
    param([object[]]$Items)
    $repositories=@(foreach($id in @('winutil','winsux','ultimate','rytunex')){[pscustomobject]@{Id=$id;Items=@($Items|Where-Object RepositoryId -eq $id)}})
    return (ConvertTo-Json -InputObject ([pscustomobject]@{SchemaVersion=1;Repositories=$repositories}) -Depth 7 -Compress)
}
function New-AdvisorRule {
    param([string]$Id,[string]$RepositoryId='ultimate',[string]$Hardware='Any',[string]$Architecture='x64',[string]$Role='Diagnostic',[string]$Requires='Any',[bool]$CanRecommend=$true,[string]$Family='',[int]$Priority=10)
    return [pscustomobject]@{RepositoryId=$RepositoryId;ItemId=$Id;Hardware=$Hardware;Architecture=$Architecture;Role=$Role;Requires=$Requires;CanRecommend=$CanRecommend;Family=$Family;Priority=$Priority;Alias=$Id;Category='Mock';Reason='Reviewed test rule.'}
}
function Set-AdvisorRules {
    param([object[]]$Rules)
    $script:GoatToolRulesJson=ConvertTo-Json -InputObject ([pscustomobject]@{SchemaVersion=1;Rules=@($Rules)}) -Depth 6 -Compress
}
function New-AdvisorScan {
    param([string[]]$GPU=@('NVIDIA GeForce Mock'),[string]$CPU='Intel Core Mock',[string]$Architecture='x64',[bool]$Supported=$true)
    return [pscustomobject]@{OS=[pscustomobject]@{Supported=$Supported};CPU=[pscustomobject]@{Name=$CPU};GPU=@($GPU|ForEach-Object{[pscustomobject]@{Name=$_}});AdvancedState=[pscustomobject]@{Readings=@{'cpu-architecture'=[pscustomobject]@{Available=(-not [string]::IsNullOrWhiteSpace($Architecture));Value=[pscustomobject]@{Name=$Architecture}}}}}
}
function Find-AdvisorResult {param($Results,[string]$Id)return @($Results|Where-Object ItemId -eq $Id)[0]}

Invoke-AdvisorTest 'Every catalog row remains visible; missing runnable rules require review' {
    $items=@((New-AdvisorItem source winutil $false RepositoryFile),(New-AdvisorItem unreviewed winsux),(New-AdvisorItem feature ultimate $false Feature),(New-AdvisorItem store rytunex $true OpenUri))
    Set-AdvisorRules @()
    $result=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan) -CatalogJson (New-AdvisorCatalog $items))
    Assert-Advisor ($result.Count-eq 4) 'Coverage must equal all four catalog rows.'
    Assert-Advisor ((Find-AdvisorResult $result source).Status-eq 'Referência') 'An unreviewed source file stays a source reference.'
    foreach($id in @('unreviewed','feature','store')){Assert-Advisor ((Find-AdvisorResult $result $id).Status-eq 'Revisão manual') ('Missing rule was silently endorsed: '+$id)}
}

Invoke-AdvisorTest 'NVIDIA and AMD GPU matches follow actual manufacturer evidence' {
    $catalog=New-AdvisorCatalog @((New-AdvisorItem nvidia),(New-AdvisorItem amd),(New-AdvisorItem intel))
    Set-AdvisorRules @((New-AdvisorRule nvidia -Hardware NVIDIA -Role Driver),(New-AdvisorRule amd -Hardware AMD-GPU -Role Driver),(New-AdvisorRule intel -Hardware Intel-GPU -Role Driver))
    $nvidia=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan) -CatalogJson $catalog)
    Assert-Advisor ((Find-AdvisorResult $nvidia nvidia).Status-eq 'Compatível' -and (Find-AdvisorResult $nvidia amd).Status-eq 'Não aplicável') 'NVIDIA system must not be endorsed for an AMD-only driver.'
    $amd=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan -GPU @('AMD Radeon Mock')) -CatalogJson $catalog)
    Assert-Advisor ((Find-AdvisorResult $amd amd).Status-eq 'Compatível' -and (Find-AdvisorResult $amd nvidia).Status-eq 'Não aplicável') 'AMD system must not be endorsed for an NVIDIA-only driver.'
    $mixed=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan -GPU @('AMD Radeon Mock','NVIDIA GeForce Mock')) -CatalogJson $catalog)
    Assert-Advisor ((Find-AdvisorResult $mixed amd).Status-eq 'Compatível' -and (Find-AdvisorResult $mixed nvidia).Status-eq 'Compatível') 'Mixed GPU systems must retain both confirmed manufacturers.'
}

Invoke-AdvisorTest 'Unknown and Basic GPU names remain manual rather than false manufacturer facts' {
    $catalog=New-AdvisorCatalog @((New-AdvisorItem nvidia))
    Set-AdvisorRules @((New-AdvisorRule nvidia -Hardware NVIDIA -Role Driver))
    foreach($gpu in @('Microsoft Basic Display Adapter','Unknown GPU','GPU desconhecida','')){
        $result=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan -GPU @($gpu)) -CatalogJson $catalog)
        Assert-Advisor ($result[0].Status-eq 'Revisão manual') ('Unknown GPU vendor was treated as a known incompatible vendor: '+$gpu)
    }
}

Invoke-AdvisorTest 'A Basic secondary adapter does not hide a confirmed NVIDIA device' {
    $catalog=New-AdvisorCatalog @((New-AdvisorItem nvidia))
    Set-AdvisorRules @((New-AdvisorRule nvidia -Hardware NVIDIA -Role Driver))
    $result=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan -GPU @('NVIDIA GeForce Mock','Microsoft Basic Display Adapter')) -CatalogJson $catalog)
    Assert-Advisor ($result[0].Status-eq 'Compatível') 'Confirmed NVIDIA GPU must remain applicable even when another adapter has an unknown vendor.'
}

Invoke-AdvisorTest 'Intel and AMD CPU rules do not infer vendor when the name is unknown' {
    $catalog=New-AdvisorCatalog @((New-AdvisorItem intelcpu),(New-AdvisorItem amdcpu))
    Set-AdvisorRules @((New-AdvisorRule intelcpu -Hardware Intel-CPU -Role Driver),(New-AdvisorRule amdcpu -Hardware AMD-CPU -Role Driver))
    foreach($cpu in @('Intel Core Mock','AMD Ryzen Mock')){
        $result=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan -CPU $cpu) -CatalogJson $catalog)
        $match=if($cpu-match '^Intel'){'intelcpu'}else{'amdcpu'}
        Assert-Advisor ((Find-AdvisorResult $result $match).Status-eq 'Compatível') ('Detected CPU vendor not matched: '+$cpu)
    }
    $unknown=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan -CPU '') -CatalogJson $catalog)
    Assert-Advisor (@($unknown|Where-Object Status -ne 'Revisão manual').Count-eq 0) 'Missing CPU vendor must stay manual.'
}

Invoke-AdvisorTest 'x64, x86, ARM64 and unknown architecture follow reviewed requirements' {
    $catalog=New-AdvisorCatalog @((New-AdvisorItem diag64),(New-AdvisorItem diag32),(New-AdvisorItem driver32))
    Set-AdvisorRules @((New-AdvisorRule diag64),(New-AdvisorRule diag32 -Architecture x86),(New-AdvisorRule driver32 -Architecture x86 -Role Driver))
    $x64=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan -Architecture x64) -CatalogJson $catalog)
    Assert-Advisor ((Find-AdvisorResult $x64 diag64).Status-eq 'Recomendado' -and (Find-AdvisorResult $x64 diag32).Status-eq 'Recomendado') 'x64 may run reviewed x64 and x86 user-mode diagnostics.'
    Assert-Advisor ((Find-AdvisorResult $x64 driver32).Status-eq 'Não aplicável') 'x86 driver is not an x64 driver.'
    $arm=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan -Architecture ARM64) -CatalogJson $catalog)
    Assert-Advisor (@($arm|Where-Object Status -ne 'Não aplicável').Count-eq 0) 'ARM64 emulation must not be assumed for x86/x64 packages.'
    $unknown=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan -Architecture '') -CatalogJson $catalog)
    Assert-Advisor (@($unknown|Where-Object Status -ne 'Revisão manual').Count-eq 0) 'Unknown architecture must remain manual.'
}

Invoke-AdvisorTest 'Unsupported Windows blocks reviewed tools' {
    $catalog=New-AdvisorCatalog @((New-AdvisorItem diagnostic),(New-AdvisorItem optimizer))
    Set-AdvisorRules @((New-AdvisorRule diagnostic),(New-AdvisorRule optimizer -Role Optimizer))
    $result=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan -Supported $false) -CatalogJson $catalog)
    Assert-Advisor (@($result|Where-Object Status -ne 'Não aplicável').Count-eq 0) 'No reviewed tool may be recommended on an unsupported OS.'
}

Invoke-AdvisorTest 'Only runnable diagnostic tools with Any procedure requirements may be recommended' {
    $catalog=New-AdvisorCatalog @((New-AdvisorItem diagnostic),(New-AdvisorItem optimizer),(New-AdvisorItem installer),(New-AdvisorItem manual),(New-AdvisorItem source -CanRun $false -Operation RepositoryFile),(New-AdvisorItem disabled),(New-AdvisorItem reference -CanRun $false -Operation RepositoryFile))
    Set-AdvisorRules @((New-AdvisorRule diagnostic),(New-AdvisorRule optimizer -Role Optimizer),(New-AdvisorRule installer -Role Installer),(New-AdvisorRule manual -Requires Manual),(New-AdvisorRule source),(New-AdvisorRule disabled -CanRecommend $false),(New-AdvisorRule reference -Role Reference -Architecture Any))
    $result=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan) -CatalogJson $catalog)
    $recommended=@($result|Where-Object Status -eq 'Recomendado')
    Assert-Advisor ($recommended.Count-eq 1 -and $recommended[0].ItemId-eq 'diagnostic') 'Optimizer/installer/manual/source/disabled recommendation flags may not bypass diagnostic-only policy.'
    Assert-Advisor ((Find-AdvisorResult $result reference).Status-eq 'Referência') 'An explicit reviewed reference must retain its non-executable role.'
}

Invoke-AdvisorTest 'Duplicate diagnostic families keep the highest priority single suggestion' {
    $catalog=New-AdvisorCatalog @((New-AdvisorItem first winutil),(New-AdvisorItem second ultimate),(New-AdvisorItem third rytunex))
    Set-AdvisorRules @((New-AdvisorRule first winutil -Family monitor -Priority 10),(New-AdvisorRule second ultimate -Family monitor -Priority 90),(New-AdvisorRule third rytunex -Family monitor -Priority 20))
    $result=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan) -CatalogJson $catalog)
    $recommended=@($result|Where-Object Status -eq 'Recomendado')
    Assert-Advisor ($recommended.Count-eq 1 -and $recommended[0].ItemId-eq 'second') 'Only the highest reviewed priority may be suggested for one diagnostic family.'
    Assert-Advisor (@($result|Where-Object Status -eq 'Compatível').Count-eq 2) 'Equivalent alternatives must remain visible and compatible.'
}

Invoke-AdvisorTest 'Invalid, duplicate and absent catalog rule IDs are rejected' {
    $catalog=New-AdvisorCatalog @((New-AdvisorItem present))
    foreach($rules in @(
        @((New-AdvisorRule missing)),
        @((New-AdvisorRule present),(New-AdvisorRule present)),
        @((New-AdvisorRule ''))
    )){
        Set-AdvisorRules $rules
        $rejected=$false;try{Get-GoatToolRecommendations -Scan (New-AdvisorScan) -CatalogJson $catalog|Out-Null}catch{$rejected=$true}
        Assert-Advisor $rejected 'A missing/empty/duplicate item rule was accepted.'
    }
}

Invoke-AdvisorTest 'JSON round-trip retains architecture evidence and result coverage' {
    $scan=New-AdvisorScan|ConvertTo-Json -Depth 8|ConvertFrom-Json
    $catalog=New-AdvisorCatalog @((New-AdvisorItem diagnostic))
    Set-AdvisorRules @((New-AdvisorRule diagnostic))
    $result=@(Get-GoatToolRecommendations -Scan $scan -CatalogJson $catalog)
    Assert-Advisor ($result.Count-eq 1 -and $result[0].Status-eq 'Recomendado') 'PSCustomObject reading maps must retain architecture evidence.'
}

$actualRules=Join-Path $root 'data\tool-rules.json'
if(Test-Path -LiteralPath $actualRules){
    Invoke-AdvisorTest 'Actual repository inventory has complete result coverage and no dangling rules' {
        $script:GoatToolRulesJson=Get-Content -LiteralPath $actualRules -Raw -Encoding UTF8
        $catalogJson=Get-Content -LiteralPath (Join-Path $root 'data\repositories.json') -Raw -Encoding UTF8
        $catalog=$catalogJson|ConvertFrom-Json
        $expected=0;foreach($repository in $catalog.Repositories){$expected+=@($repository.Items).Count}
        $result=@(Get-GoatToolRecommendations -Scan (New-AdvisorScan) -CatalogJson $catalogJson)
        Assert-Advisor ($expected-eq 1330 -and $result.Count-eq $expected) 'Actual catalog must cover all 1,330 rows.'
        Assert-Advisor (@($result|Group-Object RepositoryId,ItemId|Where-Object Count -ne 1).Count-eq 0) 'Every catalog row must have exactly one assessment.'
        $byKey=@{};foreach($assessment in $result){$byKey[$assessment.RepositoryId+'|'+$assessment.ItemId]=$assessment}
        foreach($repository in $catalog.Repositories){foreach($item in $repository.Items){
            if(-not $item.CanRun -and $item.Operation-ne 'OpenUri'){
                $assessment=$byKey[$repository.Id+'|'+$item.Id]
                Assert-Advisor ($assessment.Status-ne 'Recomendado') 'Source/feature/download-only row cannot become an executable recommendation.'
            }
        }}
    }
}elseif($RequireActualRules){$script:AdvisorFailures.Add('Actual tool-rules.json is required but not available.')}
else{Write-Output 'SKIP actual inventory rules: data/tool-rules.json is not present yet.'}

if($script:AdvisorFailures.Count-gt 0){throw ($script:AdvisorFailures.ToArray()-join [Environment]::NewLine)}
Write-Output "PASS: $script:AdvisorPassed tool-advisor tests; no downloads or external executions."
