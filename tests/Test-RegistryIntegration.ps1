#Requires -Version 5.1
# Real registry API integration, strictly confined to an owned disposable HKCU key.
# No Windows preference, policy, service, device or production action is changed.
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\Core.ps1')
$script:RegistryChecks=New-Object 'System.Collections.Generic.List[string]'
function Assert-RegistryIntegration {param([bool]$Condition,[string]$Name)if(-not $Condition){throw "Registry integration assertion: $Name"};$script:RegistryChecks.Add($Name)}
$testId=[guid]::NewGuid().ToString('N')
$ownedPath='Software\GOAT-Tweaks-Tests\'+$testId
if($ownedPath -notmatch '^Software\\GOAT-Tweaks-Tests\\[a-f0-9]{32}$'){throw 'Invalid disposable registry path'}
$base=[Microsoft.Win32.RegistryKey]::OpenBaseKey([Microsoft.Win32.RegistryHive]::CurrentUser,[Microsoft.Win32.RegistryView]::Registry64)
function Assert-OwnedRegistryTarget {
    param($Target)
    if($Target.Hive -cne 'CurrentUser' -or $Target.View -cne 'Registry64' -or ($Target.Path -cne $ownedPath -and -not $Target.Path.StartsWith($ownedPath+'\',[StringComparison]::Ordinal))){throw 'Registry test target escaped owned disposable key'}
}
try {
    $root=$base.CreateSubKey($ownedPath);$root.Dispose()
    $cases=@(
        @{Name='DWord';Kind='DWord';Data=[int]42},@{Name='DWordSigned';Kind='DWord';Data=[int]::MinValue},
        @{Name='QWord';Kind='QWord';Data=[long]4294967296},@{Name='QWordMaximum';Kind='QWord';Data=[long]::MaxValue},
        @{Name='String';Kind='String';Data='text fixture'},@{Name='StringEmpty';Kind='String';Data=''},
        @{Name='ExpandString';Kind='ExpandString';Data='%USERPROFILE%\literal-unexpanded'},
        @{Name='MultiString';Kind='MultiString';Data=[string[]]@('first','second')},@{Name='MultiStringOne';Kind='MultiString';Data=[string[]]@('one')},@{Name='MultiStringEmpty';Kind='MultiString';Data=[string[]]@()},
        @{Name='Binary';Kind='Binary';Data=[byte[]]@(0,128,255)},@{Name='BinaryOne';Kind='Binary';Data=[byte[]]@(255)},@{Name='BinaryEmpty';Kind='Binary';Data=[byte[]]@()}
    )
    foreach($case in $cases){
        $target=[pscustomobject]@{Hive='CurrentUser';View='Registry64';Path=$ownedPath;Name=$case.Name}
        Assert-OwnedRegistryTarget $target
        $original=Read-GoatRegistry $target
        Assert-RegistryIntegration (-not $original.Exists) ('initial absence '+$case.Name)
        $desired=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind=$case.Kind;Data=$case.Data}
        Assert-GoatRegistrySnapshot $desired
        Write-GoatRegistry $target $desired
        $actual=Read-GoatRegistry $target
        Assert-RegistryIntegration (Test-GoatStateEqual $desired $actual) ('real typed write/read-back '+$case.Name)
        $replacement=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='DWord';Data=7}
        Write-GoatRegistry $target $replacement
        Write-GoatRegistry $target $actual
        Assert-RegistryIntegration (Test-GoatStateEqual (Read-GoatRegistry $target) $desired) ('restore exact original kind/data '+$case.Name)
        Write-GoatRegistry $target $original
        Assert-RegistryIntegration (-not (Read-GoatRegistry $target).Exists) ('restore original absence '+$case.Name)
    }
    $target=[pscustomobject]@{Hive='CurrentUser';View='Registry64';Path=($ownedPath+'\NewChild');Name='ValueOnly'}
    Assert-OwnedRegistryTarget $target
    $absent=Read-GoatRegistry $target
    Write-GoatRegistry $target ([pscustomobject]@{KeyExists=$true;Exists=$true;Kind='DWord';Data=1})
    Write-GoatRegistry $target $absent
    $restored=Read-GoatRegistry $target
    Assert-RegistryIntegration (-not $restored.Exists -and $restored.KeyExists) 'restore absence never deletes a parent registry key'
    $target.Path=$ownedPath;$target.Name='FailureValue'
    $before=[pscustomobject]@{KeyExists=$true;Exists=$true;Kind='String';Data='keep exact fixture'}
    Write-GoatRegistry $target $before
    $failed=$false;try{Write-GoatRegistry $target ([pscustomobject]@{KeyExists=$true;Exists=$true;Kind='UnknownKind';Data='invalid'})}catch{$failed=$true}
    Assert-RegistryIntegration ($failed -and (Test-GoatStateEqual (Read-GoatRegistry $target) $before)) 'unsupported kind fails without overwriting prior value'
} finally {
    # Explicitly validate the exact named registry scope before recursive cleanup.
    if($ownedPath -cne ('Software\GOAT-Tweaks-Tests\'+$testId) -or $testId -notmatch '^[a-f0-9]{32}$'){throw 'Refusing registry cleanup outside the owned test GUID'}
    try{$base.DeleteSubKeyTree($ownedPath,$false)}finally{$base.Dispose()}
}
[pscustomobject]@{Module='RegistryIntegration';Passed=$script:RegistryChecks.Count;Checks=@($script:RegistryChecks.ToArray());Scope='Real .NET registry API only inside disposable HKCU\Software\GOAT-Tweaks-Tests\GUID. No Windows setting changed; no hardware certification.'}|ConvertTo-Json -Depth 4
