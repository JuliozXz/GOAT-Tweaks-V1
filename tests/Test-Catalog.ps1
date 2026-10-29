#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
Set-StrictMode -Version 2
$projectRoot=Split-Path $PSScriptRoot -Parent
$script:catalogAssertions=0
function Assert-Catalog { param([bool]$Condition,[string]$Reason);$script:catalogAssertions++;if(-not $Condition){throw ('Catalog contract: '+$Reason)} }
function Get-TextSha256 {
    param([string]$Text)
    $algorithm=[Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $algorithm.Dispose() }
}
$catalog=Get-Content -LiteralPath (Join-Path $projectRoot 'data/catalog.json') -Raw -Encoding UTF8|ConvertFrom-Json
$documents=Get-Content -LiteralPath (Join-Path $projectRoot 'data/documents.json') -Raw -Encoding UTF8|ConvertFrom-Json
$audit=Get-Content -LiteralPath (Join-Path $projectRoot 'docs/audit/specification-import.json') -Raw -Encoding UTF8|ConvertFrom-Json
$integrity=Get-Content -LiteralPath (Join-Path $projectRoot 'docs/audit/package-integrity.json') -Raw -Encoding UTF8|ConvertFrom-Json
Assert-Catalog ($catalog.schema_version -eq '1.0.0') 'catalog schema version is explicit'
Assert-Catalog ($catalog.product -eq 'GOAT Tweaks') 'product identity'
Assert-Catalog ($catalog.record_count -eq 344 -and @($catalog.controls).Count -eq 344) '344 documented controls, never a claim of implemented tweaks'
Assert-Catalog (@($catalog.controls.id|Select-Object -Unique).Count -eq 344) 'catalog IDs are unique'
Assert-Catalog (@($catalog.controls|Where-Object implementation_status -ne 'SPEC_ONLY_NOT_YET_VERIFIED').Count -eq 0) 'import never promotes implementation status'
Assert-Catalog (@($catalog.controls|Where-Object {$_.apply_allowed -ne $false -or $_.auto_apply_allowed -ne $false}).Count -eq 0) 'all imported execution gates are disabled'
Assert-Catalog (@($catalog.controls|Where-Object execution_class -eq 'X_BLOCKED').Count -eq 41) '41 explicit blocked controls retained'
Assert-Catalog (@($catalog.controls|Where-Object {$_.execution_class -notin @('A_AUTO_SAFE','B_APPROVAL','C_MANUAL','D_LAB_ONLY','X_BLOCKED')}).Count -eq 0) 'recognized execution classes only'
Assert-Catalog ($documents.document_count -eq 64 -and @($documents.documents).Count -eq 64) '64 embedded reference documents'
Assert-Catalog (@($documents.documents.id|Select-Object -Unique).Count -eq 64) 'document IDs are unique'
Assert-Catalog ($audit.source_files_read -eq 83 -and @($audit.coverage).Count -eq 83) 'all 83 package files inventoried'
Assert-Catalog ($audit.integrity_failed -eq 0 -and $integrity.passed -eq 81 -and $integrity.entries -eq 81) 'all 81 non-circular manifest entries matched source bytes'
Assert-Catalog ($audit.counts.central_settings -eq 246 -and $audit.counts.v73_complements_actual -eq 73 -and $audit.counts.gpu_center -eq 25) 'catalog sources retain their actual counts'
Assert-Catalog ($audit.counts.central_repeated_new_controls_already_in_settings -eq 66) '66 repeated central records are not imported twice'
Assert-Catalog (@($audit.explicitly_blocked|Select-Object -Unique).Count -eq 41) 'blocked ID audit is unique'
$sourceHashes=@{}
foreach($source in $audit.coverage){
    Assert-Catalog ($source.sha256 -match '^[a-f0-9]{64}$') ('valid source hash: '+$source.path)
    Assert-Catalog (-not $sourceHashes.ContainsKey($source.path)) ('unique source path: '+$source.path)
    $sourceHashes[$source.path]=$source.sha256
}
$ids=@($catalog.controls.id)
foreach($control in $catalog.controls){
    Assert-Catalog (-not [string]::IsNullOrWhiteSpace($control.id)) 'nonempty control ID'
    Assert-Catalog (-not [string]::IsNullOrWhiteSpace($control.title)) ('title: '+$control.id)
    Assert-Catalog (-not [string]::IsNullOrWhiteSpace($control.category)) ('category: '+$control.id)
    Assert-Catalog (-not [string]::IsNullOrWhiteSpace($control.risk)) ('risk: '+$control.id)
    Assert-Catalog ($sourceHashes.ContainsKey($control.source_path) -and $sourceHashes[$control.source_path] -eq $control.source_sha256) ('provenance: '+$control.id)
    Assert-Catalog ($null -ne $control.source_record -and $control.source_record.id -eq $control.id) ('original record retained: '+$control.id)
    if($control.source_record.PSObject.Properties.Name -contains 'apply_mode' -and $control.source_record.apply_mode -eq 'blocked'){
        Assert-Catalog ($control.execution_class -eq 'X_BLOCKED') ('legacy blocked wins over conditional automation: '+$control.id)
    }
    if($control.execution_class -eq 'X_BLOCKED'){
        Assert-Catalog ($control.id -in $audit.explicitly_blocked -and -not $control.apply_allowed) ('blocked record cannot apply: '+$control.id)
    }
    foreach($related in $control.related_ids){
        Assert-Catalog ($related -in $ids -and $related -ne $control.id) ('related behavior references an existing distinct ID: '+$control.id)
    }
    foreach($sourceUrl in $control.sources){
        $uri=$null
        Assert-Catalog ([Uri]::TryCreate($sourceUrl,[UriKind]::Absolute,[ref]$uri) -and $uri.Scheme -in @('http','https')) ('reference is a web URL, never an execution command: '+$control.id)
    }
}
foreach($document in $documents.documents){
    Assert-Catalog ($document.executable -eq $false) ('reference text is never executable: '+$document.id)
    Assert-Catalog ($document.path -eq $document.id -and $document.path -notmatch '(^/|^[A-Za-z]:|(^|/)\.\.(/|$))') ('bounded document identity: '+$document.id)
    Assert-Catalog ($document.kind -in @('documentation','historical_reference','prompt_reference','integrity_reference')) ('recognized reference type: '+$document.id)
    Assert-Catalog ((Get-TextSha256 $document.content) -eq $document.sha256) ('embedded text reproduces original UTF8 SHA256: '+$document.id)
    Assert-Catalog ([Text.Encoding]::UTF8.GetByteCount($document.content) -eq $document.size_bytes) ('embedded UTF8 length: '+$document.id)
    Assert-Catalog ($sourceHashes.ContainsKey($document.path) -and $sourceHashes[$document.path] -eq $document.sha256) ('document provenance: '+$document.id)
}
[pscustomobject]@{Module='Catalog';Passed=$script:catalogAssertions;Controls=344;Blocked=41;Documents=64;Mutation='None; data files read and hashes calculated only'}|ConvertTo-Json
