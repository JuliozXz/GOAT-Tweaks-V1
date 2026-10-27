# Goat two X V1 — integração da V7.3 + GPU Center

**Estado desta branch:** atualização incremental inicial. O projeto base é o aplicativo WPF/Windows PowerShell já existente no repositório. O ZIP GOAT TWEAKS V7.3 é uma **especificação**, não código compilável. Nenhum registro SPEC_ONLY_NOT_YET_VERIFIED deve virar ajuste automático.

## Entregue nesta primeira etapa
- Provedor `Get-GoatGpuCenter` com inventário de GPU via WMI/CIM, detecção conservadora de NVIDIA/AMD/Intel e indicação dos canais oficiais para drivers.
- Modo Demo e diagnóstico **somente leitura**; não há downloads, execução de instaladores, DDU ou escrita no Registro.
- Integração da coleta ao modo `-ScanOnly` com o campo `GpuCenter` (sem alterar o schema de `Get-GoatUnifiedScan`).
- Teste de contrato básico. O app visual anterior e suas rotinas de rollback permanecem intactos.

## Plano completo da atualização Goat two X V1
1. Ingestão validada dos catálogos V7.3, com IDs estáveis, deduplicação, proveniência, riscos, estados `SPEC_ONLY_NOT_YET_VERIFIED` e testes por ação.
2. Interface GPU Center: inventário, versão de driver, links oficiais, explicações, perfis por jogo e abas de diagnóstico/manutenção/benchmarks.
3. Fluxo de atualização e reinstalação **assistidos**, sem instalação silenciosa. DDU exige confirmação presencial, backup, instruções de modo de segurança, advertência de tela preta e bloqueio em atendimento remoto sem recuperação local.
4. Recomendações específicas para GPU/jogo por capacidades detectadas, com baixa latência, limite de FPS, V-Sync, VRR, HAGS, potência e presets com trade-offs claros; não prometer ganho universal.
5. Métricas reais de clocks, temperatura, hotspot, potência, VRAM e throttling **somente** mediante fornecedor/API confiável; mostrar 'indisponível' quando não mensurável.
6. Benchmark antes/depois com mesmo jogo, cenário e configurações; registrar FPS mediano, 1% low, p95/p99 de frametime, variância e nível de confiança; nunca inventar resultados.
7. Diário transacional para opções nativas reversíveis. Drivers não podem ter rollback garantido pelo journal de valores do Registro: recuperação separada, instruções e estado auditável.
8. Testes de bancada em GPUs NVIDIA/AMD/Intel, múltiplas GPUs, GPU integrada, driver genérico, hardware sem sensores, Windows 10/11, sem privilégios, falha CIM, modo remoto e sessão interrompida.
9. Relatório de atendimento e limpeza segura sem remover backups/diagnósticos necessários à recuperação.

## Restrições
- Não alterar MSI, HPET/BCD, clocks, voltagem, drivers, BIOS, serviços críticos ou firmware automaticamente.
- Nunca baixar/executar binários de terceiros sem revisar versão, origem, hash, licença e consentimento.
- Não modificar a UI principal ou gerar `dist/` sem compilar e testar no Windows. A distribuição pública atual continua inalterada.

## Comando de inspeção (checkout da branch)
```powershell
. .\src\GpuCenter.ps1
Get-GoatGpuCenter | ConvertTo-Json -Depth 6
```
