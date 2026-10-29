#Requires -Version 5.1
$ErrorActionPreference='Stop'
$project=Split-Path $PSScriptRoot -Parent
. ([scriptblock]::Create((Get-Content -LiteralPath (Join-Path $project 'src\Presentation.ps1') -Raw -Encoding UTF8)))
. ([scriptblock]::Create((Get-Content -LiteralPath (Join-Path $project 'src\Gpu.ps1') -Raw -Encoding UTF8)))
$checks=New-Object 'System.Collections.Generic.List[string]'
function Assert-Presentation {param([bool]$Condition,[string]$Name)if(-not $Condition){throw "Presentation assertion: $Name"};$checks.Add($Name)}
$demo=Get-GoatGpuCenter -Demo
$gpu=Format-GoatGpuView $demo
Assert-Presentation ($gpu -match 'GPU CENTER' -and $gpu -match 'DEMO' -and $gpu -match 'NVIDIA' -and $gpu -match 'Driver instalado: Exemplo') 'GPU view uses real model fields and labels'
Assert-Presentation ($gpu -match 'N/D' -and $gpu -match 'VRAM dedicada: N/D' -and $gpu -match 'não foram medidos') 'GPU absent sensors remain unavailable without FPS claims'
Assert-Presentation ($gpu -match 'OEM / NOTEBOOK' -and $gpu -match 'MONITORES' -and $gpu -notmatch '^\s*\{') 'GPU view is organized human text without JSON object'
$partial=Format-GoatGpuView ([pscustomobject]@{Status='UNAVAILABLE';Devices=@();Monitors=@();Warnings=@('Fixture source error');Telemetry=$null})
Assert-Presentation ($partial -match 'Nenhuma GPU identificada' -and $partial -match 'Fixture source error' -and $partial -match 'indisponível') 'partial GPU inventory exposes source errors'
Assert-Presentation ((Format-GoatGpuView $null) -match 'ainda indisponível') 'missing GPU inventory stays unavailable'
$guides=Get-GoatGpuGuides -Vendor NVIDIA -RemoteContext ([pscustomobject]@{State='REMOTE_OR_POSSIBLE_REMOTE'})
$guideText=Format-GoatGpuGuides $guides
Assert-Presentation ($guideText -match 'gpu-ddu' -and $guideText -match 'BLOCKED' -and $guideText -match 'BLOQUEIO') 'guide IDs and remote blocked status preserved'
Assert-Presentation ($guideText -match '1\.' -and $guideText -match 'Recuperação:' -and $guideText -match 'https://www.nvidia.com') 'manual guide steps recovery and sources readable'
Assert-Presentation ((Format-GoatGpuGuides @()) -match 'Nenhum guia') 'empty guide collection readable'
$profile=New-GoatGpuGameProfile -GameId fixture -Reflex Enabled -Vrr Enabled -FpsCap 200 -RefreshRateHz 144 -Goal Competitivo
$profileText=Format-GoatProfileView (Get-GoatGpuProfileAdvice $profile)
Assert-Presentation ($profileText -match 'GUIDANCE_ONLY' -and $profileText -match 'Reflex' -and $profileText -match 'CONFLITOS') 'profile shows guidance state Reflex and conflicts'
Assert-Presentation ($profileText -match 'NOT_MEASURED' -and $profileText -match 'nenhuma configuração') 'profile never presents an applied tweak or measured benefit'
$item=[pscustomobject]@{id='WIN-TEST';title='Fixture preference';category='Windows';short_explanation='Explained text';how_it_works='Fixture behavior';potential_benefit='No measured FPS';risk='Baixo';implementation_status='SPEC_ONLY_NOT_YET_VERIFIED';execution_class='C_MANUAL';rollback='Restore exact original';source_path='fixture.md';source_sha256=('a'*64);sources=@('https://example.com/official');apply_allowed=$true;apply_steps='throw "THIS MUST NEVER EXECUTE"'}
$catalog=Format-GoatCatalogView $item
Assert-Presentation ($catalog -match 'SPEC_ONLY_NOT_YET_VERIFIED' -and $catalog -match 'RECURSO DISPONÍVEL' -and $catalog -match 'somente os executores' -and $catalog -match 'WIN-TEST') 'catalog distinguishes source documentation from runtime executors'
Assert-Presentation ($catalog -match 'Explained text' -and $catalog -match 'Restore exact original' -and $catalog -match 'fixture.md' -and $catalog -match ('a'*64)) 'catalog explanation rollback and provenance visible'
Assert-Presentation ($catalog -notmatch 'THIS MUST NEVER EXECUTE' -and $catalog -notmatch 'source_record') 'catalog raw instructions are not exposed as executable controls'
$emptyBenchmark=Format-GoatBenchmarkView -Captures @()
Assert-Presentation ($emptyBenchmark -match 'não medidos' -and $emptyBenchmark -match 'Capturas disponíveis: 0') 'empty benchmark does not fabricate zero FPS'
$capture=[pscustomobject]@{ConditionLabel='Baseline';PassNumber=1;Metrics=[pscustomobject]@{AverageFps=60.25;OnePercentLowFps=45.5;FrameTimeP50Ms=16.1;FrameTimeP95Ms=20.5;FrameTimeP99Ms=25;SampleCount=1000;DurationSeconds=20;OnePercentLowMethod='slowest 1 percent';PercentileMethod='R7 interpolation'};Source=[pscustomobject]@{Sha256=('b'*64);Column='FrameTimeMs';Units='ms'};Conditions=[pscustomobject]@{Game='Fixture';Scene='Same scene';Resolution='1920x1080';Api='DX12';Preset='High';Driver='1'}}
$comparison=[pscustomobject]@{Status='INCONCLUSIVE';Reason='Not enough passes';BaselinePassCount=1;AfterPassCount=1;Metrics=@([pscustomobject]@{Name='AverageFps';Units='FPS';Before=[pscustomobject]@{Median=60.25};After=[pscustomobject]@{Median=60.35};RelativeDeltaPercent=$null});ConditionsIssues=@('Need repeatable scene');Method='Median and observed ranges'}
$benchmark=Format-GoatBenchmarkView -Captures @($capture) -Comparison $comparison
Assert-Presentation ($benchmark -match 'FPS médio: 60,25 FPS' -and $benchmark -match '1% low: 45,5 FPS') 'benchmark prints actual FPS and 1 percent low with locale'
Assert-Presentation ($benchmark -match 'p50: 16,1 ms' -and $benchmark -match 'p95: 20,5 ms' -and $benchmark -match 'p99: 25 ms') 'benchmark prints each measured frametime percentile with units'
Assert-Presentation ($benchmark -match ('b'*64) -and $benchmark -match 'R7 interpolation' -and $benchmark -match 'slowest 1 percent') 'benchmark records method and source hash'
Assert-Presentation ($benchmark -match 'INCONCLUSIVE' -and $benchmark -match 'Not enough passes' -and $benchmark -notmatch 'Diferença observada:') 'comparison retains inconclusive state and omits uncomputed percent'
$history=Format-GoatHistoryView -Session ([pscustomobject]@{Id='fixture';State='Open';Root='C:\fixture';Events=@([pscustomobject]@{Utc='2026-01-01';Kind='DEMO';Message='Simulation only'})}) -Transactions @()
Assert-Presentation ($history -match 'DEMO' -and $history -match 'Simulation only' -and $history -match 'Nenhuma transação') 'history distinguishes demo event from native transaction'
$hardware=Format-GoatHardwareView -Title 'CPU e RAM' -Value ([pscustomobject]@{Name='Fixture';Cores=8;Memory=[pscustomobject]@{AvailableGB=0;TotalGB=16};Unknown=$null;Rows=@()})
Assert-Presentation ($hardware -match 'CPU E RAM' -and $hardware -match 'Núcleos: 8' -and $hardware -match 'Disponível \(GiB\): 0' -and $hardware -match 'N/D') 'hardware keys translated and actual zero retained'
Assert-Presentation ($hardware -notmatch 'ANEXO TÉCNICO' -and $hardware -notmatch '^\s*\{') 'hardware JSON is optional and off by default'
Assert-Presentation ((Format-GoatHardwareView -Title fixture -Value @{Count=1} -IncludeTechnicalJson) -match 'ANEXO TÉCNICO') 'explicit technical annex remains available'
Assert-Presentation ((Format-GoatViewValue ([double]::NaN)) -match 'N/D' -and (Format-GoatViewValue ([double]::PositiveInfinity)) -match 'N/D') 'invalid numeric metrics are not presented as measurements'
[pscustomobject]@{Module='Presentation';Passed=$checks.Count;Checks=@($checks.ToArray());Scope='Pure formatting; no Windows mutation or command execution'}|ConvertTo-Json -Depth 4
