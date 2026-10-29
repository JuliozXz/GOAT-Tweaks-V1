#requires -Version 5.1
<#.SYNOPSIS
Importa a especificacao local como dados de consulta, preservando proveniencia.
.DESCRIPTION
Nunca executa comandos contidos no pacote. Nenhum registro de catalogo vira
executor ou recebe status validado por causa da importacao.
#>
[CmdletBinding()]
param(
    [string]$SourceRoot,
    [string]$OutputRoot,
    [string]$AuditRoot
)
$ErrorActionPreference = 'Stop'
if (-not $SourceRoot) { $SourceRoot = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) 'GOAT_TWEAKS_V7_3_PACOTE_MESTRE' }
if (-not $OutputRoot) { $OutputRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'data' }
if (-not $AuditRoot) { $AuditRoot = Join-Path (Split-Path $PSScriptRoot -Parent) 'docs/audit' }
$sourceDirectory = (Resolve-Path -LiteralPath $SourceRoot).Path.TrimEnd('\','/')
$outputDirectory = [IO.Path]::GetFullPath($OutputRoot)
$auditDirectory = [IO.Path]::GetFullPath($AuditRoot)
if ($outputDirectory.StartsWith($sourceDirectory + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or $outputDirectory -eq $sourceDirectory) {
    throw 'OutputRoot deve estar fora do pacote fonte para preservar seus arquivos.'
}
foreach ($folder in @($outputDirectory,$auditDirectory)) { [IO.Directory]::CreateDirectory($folder) | Out-Null }
$encoding = New-Object System.Text.UTF8Encoding($false)
function Write-JsonData {
    param([string]$Path, $Value)
    $json = ConvertTo-Json -InputObject $Value -Depth 100
    [IO.File]::WriteAllText($Path, $json + [Environment]::NewLine, $encoding)
}
function Read-PackageJson {
    param([string]$RelativePath)
    Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $sourceDirectory $RelativePath) | ConvertFrom-Json
}
function First-Text {
    param([object[]]$Values)
    foreach ($value in $Values) {
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) {
            if ($value -is [Array]) { return ($value -join [Environment]::NewLine) }
            return [string]$value
        }
    }
    return ''
}
function Get-SourceHash {
    param([string]$RelativePath)
    (Get-FileHash -LiteralPath (Join-Path $sourceDirectory $RelativePath) -Algorithm SHA256).Hash.ToLowerInvariant()
}
$manifestPath='06_INTEGRIDADE/MANIFESTO_GOAT_TWEAKS.json'
$manifest = Read-PackageJson $manifestPath
$integrity = @(
    foreach ($entry in $manifest.files) {
        $filePath = [IO.Path]::GetFullPath((Join-Path $sourceDirectory $entry.path))
        if (-not $filePath.StartsWith($sourceDirectory + [IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Manifesto contem caminho fora da raiz.' }
        $exists = Test-Path -LiteralPath $filePath -PathType Leaf
        $actualHash = if ($exists) { (Get-FileHash -LiteralPath $filePath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
        $actualSize = if ($exists) { (Get-Item -LiteralPath $filePath).Length } else { $null }
        [pscustomobject][ordered]@{path=$entry.path;exists=$exists;expected_sha256=$entry.sha256;actual_sha256=$actualHash;hash_matches=($actualHash -eq $entry.sha256);expected_size=$entry.size_bytes;actual_size=$actualSize;size_matches=($actualSize -eq $entry.size_bytes)}
    }
)
$failures = @($integrity | Where-Object {-not ($_.exists -and $_.hash_matches -and $_.size_matches)})
Write-JsonData (Join-Path $auditDirectory 'package-integrity.json') ([ordered]@{manifest_path=$manifestPath;manifest_sha256=(Get-SourceHash $manifestPath);entries=$integrity.Count;passed=($integrity.Count-$failures.Count);files=$integrity})
if ($failures.Count -gt 0) { throw ('Integridade do pacote falhou em {0} arquivo(s); importacao interrompida.' -f $failures.Count) }
$centralPath = '08_CATALOGO_CONFIGURACOES_EXPLICADAS/01_CATALOGO_CENTRAL_V5.json'
$extensionPath = '15_CATALOGOS_EXTENSOES_V7_3/01_CATALOGOS_V7_3_COMPLEMENTOS.json'
$gpuPath = '17_ATUALIZACAO_GOAT_TWEAKS_GPU_CENTER/02_CATALOGO_FUNCOES_GPU.json'
$central = Read-PackageJson $centralPath
$extension = Read-PackageJson $extensionPath
$gpu = Read-PackageJson $gpuPath
$historical = Read-PackageJson '03_CATALOGOS_E_INVENTARIOS/01_CATALOGO_TECNICO_HISTORICO.json'
$semanticGroups = @(
    @{behavior='Game Mode';ids=@('WIN-GAMEMODE','WIN-GAME-MODE','WIN-001')},
    @{behavior='Game DVR/background capture';ids=@('WIN-CAPTURE','WIN-002')},
    @{behavior='HAGS';ids=@('WIN-HAGS','GPU-HAGS-AB-TEST','WIN-003','GPU-OPT-007')},
    @{behavior='Windowed game optimizations';ids=@('WIN-WINDOWED','WIN11-WINDOWED-OPT','WIN-004')},
    @{behavior='Windows per-app GPU preference';ids=@('WIN-GPU-PREF','WIN-GPU-APP-PREFERENCE','WIN-GRAPHICS-PER-APP','GPU-001')},
    @{behavior='Per-game frame cap';ids=@('GAME-FRAME-CAP','GAME-003','GPU-OPT-009')},
    @{behavior='GPU driver official lookup';ids=@('DRIVER-OFFICIAL-UPDATE-CHECK','GPU-006','DRV-002','GPU-DRV-001','GPU-DRV-002')},
    @{behavior='Driver clean reinstallation';ids=@('DRIVER-DDU-ESCALATION','DRV-003','GPU-DRV-003')},
    @{behavior='Overlay inventory';ids=@('WIN-OVERLAY','APP-OVERLAY-INVENTORY','OVR-001')},
    @{behavior='Power plan selection/comparison';ids=@('PWR-PLAN','POWER-PLAN-A_B','WIN-006','GAME-005')},
    @{behavior='RAM pressure';ids=@('MEM-PRESSURE','RAM-PRESSURE-PAGEFILE','RAM-001')},
    @{behavior='Storage health and free space';ids=@('STOR-HEALTH','STORAGE-HEALTH-TEMP-SPACE','DISK-001','DISK-002')},
    @{behavior='Per-game process priority';ids=@('CPU-PRIORITY','CPU-GAME-PRIORITY','CPU-003','GAME-006')},
    @{behavior='Per-game process affinity';ids=@('CPU-AFFINITY','CPU-PROCESS-AFFINITY-LEASE','CPU-004')},
    @{behavior='Benchmark frametime analysis';ids=@('BENCH-FRAMETIME','BENCH-001','BENCH-002','GPU-BENCH-002')}
)
$controls = New-Object 'System.Collections.Generic.List[object]'
$seenIds = @{}
foreach ($origin in @(@{path=$centralPath;items=$central.settings},@{path=$extensionPath;items=$extension.controls},@{path=$gpuPath;items=$gpu.controls})) {
    $sourceHash = Get-SourceHash $origin.path
    foreach ($record in $origin.items) {
        $id = [string]$record.id
        if ([string]::IsNullOrWhiteSpace($id)) { throw 'Registro sem ID.' }
        if ($seenIds.ContainsKey($id)) { throw ('ID repetido entre catalogos ativos: ' + $id) }
        $seenIds[$id]=$true
        $class=First-Text @($record.execution_class,$record.execution_class_proposed)
        $classSource=if ($class) {'source_explicit'}else{'conservative_import_classification'}
        if ($record.apply_mode -eq 'blocked' -or $class -eq 'X_BLOCKED') { $class='X_BLOCKED' }
        elseif (-not $class) { $class='C_MANUAL' }
        $related = @($semanticGroups | Where-Object { $id -in $_.ids } | ForEach-Object { $_.ids } | Where-Object { $_ -ne $id } | Sort-Object -Unique)
        $links = @($record.source) + @($record.sources)
        $links = @($links | Where-Object {$_ -is [string] -and $_ -match '^https?://'} | Sort-Object -Unique)
        $name=First-Text @($record.name,$record.title,$id)
        $controls.Add([pscustomobject][ordered]@{
            id=$id;name=$name;title=$name;category=(First-Text @($record.category,$record.area,'General'));
            short_explanation=(First-Text @($record.short_explanation,$record.preconditions,$record.title,$record.name));
            how_it_works=(First-Text @($record.how_it_works,$record.implementation,$record.application_and_rollback,$record.validation_or_safety));
            potential_benefit=(First-Text @($record.potential_benefit,$record.expected_benefit_and_tradeoffs));
            when_to_use=(First-Text @($record.when_to_use,$record.eligibility,$record.preconditions));
            when_not_to_use=(First-Text @($record.when_not_to_use,$record.blockers,$record.notes));
            risk=(First-Text @($record.risk,'Nao classificado na fonte; requer revisao'));
            evidence_level=(First-Text @($record.evidence_level,'Especificacao sem validacao de execucao'));
            eligibility=(First-Text @($record.eligibility,$record.preconditions,$record.blockers));
            verification=(First-Text @($record.verification,$record.validation,$record.validation_or_safety));
            rollback=(First-Text @($record.rollback,$record.rollback_policy,$record.application_and_rollback));
            apply_steps=(First-Text @($record.apply_steps,$record.implementation));
            reboot_required=(First-Text @($record.reboot_required,'Desconhecido; nao reiniciar automaticamente'));
            source_implementation_status=$record.implementation_status;implementation_status='SPEC_ONLY_NOT_YET_VERIFIED';
            execution_class=$class;execution_class_source=$classSource;automation_mode=$record.automation_mode;
            capability_kind=$record.capability_kind;apply_mode=$record.apply_mode;apply_allowed=$false;auto_apply_allowed=$false;
            source_path=$origin.path;source_sha256=$sourceHash;sources=$links;related_ids=$related;source_record=$record
        })
    }
}
$documents = New-Object 'System.Collections.Generic.List[object]'
$coverage = New-Object 'System.Collections.Generic.List[object]'
$jsonLeafCount=0
function Count-JsonLeaves {
    param($Node)
    if ($null -eq $Node) { return 1 }
    if ($Node -is [pscustomobject]) {
        $count=0
        foreach($property in $Node.PSObject.Properties) { $count += Count-JsonLeaves $property.Value }
        return $count
    }
    if ($Node -is [Array]) {
        $count=0
        foreach($child in $Node) { $count += Count-JsonLeaves $child }
        return $count
    }
    return 1
}
foreach ($file in (Get-ChildItem -LiteralPath $sourceDirectory -Recurse -File | Sort-Object FullName)) {
    $relative = $file.FullName.Substring($sourceDirectory.Length+1).Replace('\','/')
    $hash=(Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $content=[IO.File]::ReadAllText($file.FullName,[Text.Encoding]::UTF8)
    $entry=[ordered]@{path=$relative;sha256=$hash;size_bytes=$file.Length;characters_read=$content.Length;parse='text'}
    if ($file.Extension -eq '.json') {
        $parsed=ConvertFrom-Json -InputObject $content
        $entry.parse='json_ok';$entry.scalar_leaves_read=Count-JsonLeaves $parsed;$jsonLeafCount+=$entry.scalar_leaves_read
    } elseif($file.Extension -eq '.csv') {
        $rows=@(ConvertFrom-Csv -InputObject $content)
        $entry.parse='csv_ok';$entry.rows=$rows.Count;$entry.columns=@($rows[0].PSObject.Properties.Name)
    }
    $coverage.Add([pscustomobject]$entry)
    if($file.Extension -in '.md','.txt') {
        $kind=if($relative -match 'PROMPT'){'prompt_reference'}elseif($relative -match 'HISTORICO|HISTORIC|MASTER_V4'){'historical_reference'}elseif($relative -match 'INTEGRIDADE'){'integrity_reference'}else{'documentation'}
        $heading=@([regex]::Matches($content,'(?m)^#\s+(.+)$') | Select-Object -First 1)
        $title=if($heading.Count){$heading[0].Groups[1].Value.Trim()}else{$file.BaseName}
        $documents.Add([pscustomobject][ordered]@{id=$relative;path=$relative;title=$title;kind=$kind;sha256=$hash;size_bytes=$file.Length;content=$content;executable=$false})
    }
}
$stamp=[DateTime]::UtcNow.ToString('o')
$catalog=[ordered]@{schema_version='1.0.0';product='GOAT Tweaks';generated_utc=$stamp;record_count=$controls.Count;warning='Catalogo de especificacao. Importar texto nao valida implementacao nem autoriza execucao.';deduplication='central.new_controls is already included in central.settings; related_ids mark overlapping behavior without merging distinct scopes';controls=@($controls.ToArray())}
$documentSet=[ordered]@{schema_version='1.0.0';generated_utc=$stamp;document_count=$documents.Count;notice='Conteudo de referencia somente para leitura. Prompts e exemplos nao sao executados pelo app.';documents=@($documents.ToArray())}
$audit=[ordered]@{
    schema_version='1.0.0';generated_utc=$stamp;read_method='Every source file read completely; every JSON scalar traversed and every CSV cell parsed. No source command executed.';
    source_manifest_sha256=(Get-SourceHash $manifestPath);source_files_read=$coverage.Count;json_files=@($coverage | Where-Object parse -eq 'json_ok').Count;csv_files=@($coverage | Where-Object parse -eq 'csv_ok').Count;json_scalar_leaves_read=$jsonLeafCount;
    integrity_passed=$integrity.Count;integrity_failed=$failures.Count;
    counts=[ordered]@{historical_settings=@($historical.settings).Count;historical_topics=@($historical.topics).Count;central_settings=@($central.settings).Count;central_repeated_new_controls=@($central.new_controls).Count;central_repeated_new_controls_already_in_settings=@($central.new_controls | Where-Object id -in $central.settings.id).Count;v73_complements_actual=@($extension.controls).Count;v73_scope_note_claims_66_but_actual_is_73=$true;gpu_center=@($gpu.controls).Count;unique_active_catalog_ids=$controls.Count;embedded_documents=$documents.Count};
    states=@($controls | Group-Object implementation_status | ForEach-Object {[ordered]@{status=$_.Name;count=$_.Count}});
    execution_classes=@($controls | Group-Object execution_class | ForEach-Object {[ordered]@{class=$_.Name;count=$_.Count}});
    explicitly_blocked=@($controls | Where-Object execution_class -eq 'X_BLOCKED' | ForEach-Object {$_.id});
    source_inconsistencies=@('V7.3 complementary scope_note says 66 controls but controls has 73.','Several legacy apply_mode=blocked records carry conditional automation text. X_BLOCKED wins during import.','Central v6_execution_contract refers to implementation_status == Tested; normative V7.3 requires IMPLEMENTED_AND_TESTED and real evidence. Import preserves all records as SPEC_ONLY_NOT_YET_VERIFIED.','Historical prompt precedence text conflicts with the newer unified GPU package. Active unified prompt and V7.3 safety requirements take precedence.');
    semantic_overlap_groups=$semanticGroups;coverage=@($coverage.ToArray())
}
Write-JsonData (Join-Path $outputDirectory 'catalog.json') $catalog
Write-JsonData (Join-Path $outputDirectory 'documents.json') $documentSet
Write-JsonData (Join-Path $auditDirectory 'specification-import.json') $audit
[pscustomobject][ordered]@{CatalogPath=(Join-Path $outputDirectory 'catalog.json');DocumentPath=(Join-Path $outputDirectory 'documents.json');Controls=$controls.Count;Documents=$documents.Count;SourceFiles=$coverage.Count;IntegrityPassed=$integrity.Count;IntegrityFailed=$failures.Count}
