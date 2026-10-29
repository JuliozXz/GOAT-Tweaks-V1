# Validação e limites da prévia

Este projeto é uma prévia de desenvolvimento em Windows PowerShell 5.1 x64 e WPF. O bundle é um arquivo PowerShell com módulos, interface e dados incorporados. Não possui assinatura Authenticode de editor. O hash SHA-256 permite conferir integridade do arquivo distribuído; não identifica um editor nem certifica segurança ou compatibilidade universal.

## Verificações executadas

Em **28/10/2026**, o runner local passou nas **8 suítes (3.192 verificações, zero falhas)**. O fluxo de interface também passou em **71 verificações adicionais usando o bundle independente**. Inventário real somente leitura: Windows 10 build 19045, uma GPU NVIDIA e um monitor; confiabilidade SMART indisponível foi mantida como indisponível. O resumo público está em `validation-results.json`.

Os testes automatizados foram executados no Windows, em processos isolados de Windows PowerShell 5.1 STA. Cada execução registra o resultado de cada suíte e os logs em `artifacts/test-results/results.json` e arquivos adjacentes. As contagens presentes nesse relatório correspondem à execução realizada; alterações de código exigem nova execução.

| Área | Evidência e alcance |
|---|---|
| Catálogo/documentos | Contratos de IDs e status, bloqueios, gates de execução desabilitados, proveniência e reconstrução dos hashes dos textos incorporados |
| Transações/recuperação | Providers de Registro substituídos por fixtures; snapshots de ausência e tipos, journal durável, falha parcial, read-back, restauração, corrupção, identidade e ordenação |
| Inventário | Providers determinísticos para dados válidos, ausentes, falhos e Demo; ausência de valores inventados e nenhuma consulta real durante os testes com fixtures |
| GPU/perfis | Fixtures NVIDIA/AMD/Intel e multi-GPU, metadados incompletos, falha CIM, dados de sensores indisponíveis, guias e bloqueios remotos, perfis locais sem alterar Windows/driver |
| Benchmark | Capturas CSV conhecidas, rejeição de dados inválidos ou mistura de processos/swap chains, métodos explícitos de FPS/1% low/percentis, condições comparáveis, repetições, variação e estados inconclusivos |
| Relatórios/finalização | Arquivos temporários próprios, minimização de dados, HTML escapado, hashes, exportação incompleta/corrompida, reversão privada preservada e finalização idempotente |
| WPF Demo | Abertura real de janela, inventário Demo em segundo plano, navegação, catálogo e documentação pesquisáveis, simulação, perfil, importação/comparação de capturas, exportação e finalização; renders preservados em `artifacts/ui/` |
| Bundle | Build e parse em PowerShell 5.1, ScanOnly Demo como JSON e repetição do fluxo WPF Demo carregando o bundle; renders em `artifacts/ui-bundled/` |

As fixtures não modificam preferências reais do Windows. Os testes criam e removem somente arquivos temporários próprios. Renders são imagens da interface em Demo, sem inventário privado real. Logs e pacotes privados de recuperação não devem ser publicados como exemplos de atendimento.

Foi realizado inventário real **somente leitura** em Windows 10 com GPU NVIDIA no ambiente disponível. Isso comprova as leituras observadas nesse ambiente e não valida escrita de preferências, atualização de driver, recuperação de vídeo ou desempenho em jogos. Nenhum ganho de FPS foi estabelecido por esse inventário.

## Comandos reproduzíveis

Execute em Windows PowerShell 5.1 x64 a partir da raiz do projeto:

```powershell
# Build do aplicativo independente e do pacote com manifesto/hashes.
.\scripts\Build.ps1

# Todas as suítes em processos isolados; inclui janela WPF em modo Demo.
.\scripts\Test.ps1

# Execução sem a suíte de interface, quando não houver desktop disponível.
.\scripts\Test.ps1 -SkipUI

# Interface usando o bundle gerado, com amostras explícitas e arquivos temporários.
powershell.exe -NoProfile -STA -File .\tests\Test-UI.ps1 `
  -Bundle .\dist\GOAT-Tweaks.ps1 -ArtifactsRoot .\artifacts\ui-bundled

# Inventário Demo sem abrir janela e sem modificar o computador.
powershell.exe -NoProfile -STA -File .\dist\GOAT-Tweaks.ps1 -Demo -ScanOnly

# Inventário real somente leitura; preserve o resultado localmente.
powershell.exe -NoProfile -STA -File .\dist\GOAT-Tweaks.ps1 -ScanOnly

# Conferência do hash do bundle com o valor de dist/GOAT-Tweaks.sha256.
Get-FileHash -LiteralPath .\dist\GOAT-Tweaks.ps1 -Algorithm SHA256
```

O runner preserva logs mesmo quando uma suíte falha, impõe timeout e encerra somente o processo de teste que criou. `-SkipUI` registra explicitamente a omissão; não equivale a aprovação da interface. O workflow `windows.yml` executa build, testes de contrato/fixtures/WPF, ScanOnly Demo e WPF do bundle, preservando os resultados como artefatos.

## Matriz ainda pendente

| Plataforma/cenário | Situação |
|---|---|
| Windows 10 / NVIDIA | Inventário real somente leitura observado; validações de mutação/driver/desempenho pendentes |
| Windows 11 real | Pendente |
| Hardware AMD Radeon | Fixtures aprovadas; teste físico pendente |
| Hardware Intel iGPU/Arc | Fixtures aprovadas; teste físico pendente |
| eGPU, notebook híbrido, HDR/VRR e múltiplos monitores físicos | Pendente |
| Sessão remota real e perda/reconexão de vídeo/rede | Pendente; os guards são cobertos por fixtures |
| Acessibilidade com leitor de tela, diferentes escalas/DPI e troca de monitor | Inspeção da interface e navegação automatizada não substituem essa matriz; pendente |
| Atualização/remoção/rollback de driver | Sem executor automático; somente guia assistido/manual |
| Aplicação real das preferências nativas | Bloqueada na prévia até validação em ambiente descartável e hardware suportado |
| OC, BIOS/UEFI, HPET/MSI/BCD, desativação de proteções e alterações disruptivas | Sem executores neste aplicativo |
| Assinatura de editor e liberação para atendimento em clientes | Pendentes |

As classificações de catálogo descrevem requisitos documentais. Nenhum registro é liberado para aplicação somente por constar no JSON. Testes de fixtures, CI e renderização não substituem testes físicos, prova de rollback real ou medição comparável de desempenho.
