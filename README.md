# GOAT Tweaks — 7.4.1

Aplicativo de diagnóstico e atendimento técnico em **Windows PowerShell 5.1 e WPF**, com código, interface e motor próprios. A versão 7.4.1 incorpora a logo fornecida pelo usuário ao lado do nome e ao ícone da janela. Mantém a aplicação revisada de 16 preferências/políticas de Registro e a seleção de plano de energia existente. Abrir o app continua sendo uma operação de diagnóstico; mudanças dependem de seleção, prévia, elegibilidade e consentimento.

O arquivo **`dist/GOAT-Tweaks.ps1` é independente**: inclui interface, módulos, 344 registros de catálogo e 64 documentos. Funciona sem baixar módulos, ferramentas, drivers ou scripts. Requer Windows 10/11 x64; não requer administração para diagnóstico.

![Interface GOAT Tweaks — dados de demonstração](docs/images/overview-demo.png)

## Abrir

Abra a [release v7.4.1](https://github.com/JuliozXz/GOAT-Tweaks-V1/releases/tag/v7.4.1), copie a única linha de `Open-GOAT.txt` e cole no PowerShell. Ela baixa o app da versão fixa, confere o SHA256 antes de executar, abre em Windows PowerShell 5.1 STA e remove somente o arquivo temporário criado quando o app fecha. Não é necessário instalar Git, GitHub CLI, winget ou módulos para abrir o aplicativo.

O comando completo também fica em [dist/Open-GOAT.txt](dist/Open-GOAT.txt). O hash esperado está dentro da linha; divergência ou download interrompido bloqueiam a execução. A opção de execução usada pelo processo filho não altera a política de execução do Windows.

Baixe o arquivo `dist/GOAT-Tweaks.ps1` e o checksum correspondente da mesma revisão. Confira o SHA256 antes de executar:

```powershell
Get-FileHash -LiteralPath .\GOAT-Tweaks.ps1 -Algorithm SHA256
powershell.exe -NoProfile -STA -File .\GOAT-Tweaks.ps1
```

Se o Windows bloquear o arquivo baixado, revise a origem e o checksum antes de usar `Unblock-File -LiteralPath .\GOAT-Tweaks.ps1`. O programa não altera a política de execução do sistema.

```powershell
# Interface com dados explicitamente simulados e sem ajustes no Windows
powershell.exe -NoProfile -STA -File .\GOAT-Tweaks.ps1 -Demo

# Inventário JSON sem interface, sem criar uma sessão nem aplicar ajustes
powershell.exe -NoProfile -File .\GOAT-Tweaks.ps1 -ScanOnly

# Na árvore de desenvolvimento, os mesmos argumentos funcionam no launcher da raiz
powershell.exe -NoProfile -STA -File .\GOAT-Tweaks.ps1 -Demo
```

O PowerShell 7 relança o arquivo salvo usando Windows PowerShell 5.1. Para controlar o local das sessões: `-DataRoot 'D:\AtendimentosGOAT'`. Para retomar: `-SessionPath 'D:\AtendimentosGOAT\ID\session.json'` no mesmo modo Demo da sessão original.

## Recursos disponíveis

- 18 áreas navegáveis com tema preto/grafite/dourado e identidade GOAT original desta implementação.
- Inventário de Windows, CPU/RAM, discos, rede, inicialização, Steam/Discord/OBS, reinicialização e sinais de segurança, com origem e falhas explícitas.
- GPU Center NVIDIA/AMD/Intel, múltiplas GPUs, PCI IDs, driver instalado, assinatura quando reportada, OEM de notebook, identificação de monitores e motores de GPU quando disponíveis.
- Guias oficiais de driver e manutenção; DDU permanece manual e bloqueado em contexto remoto ou incerto. Nenhum instalador é executado pelo aplicativo.
- Perfis por jogo com identificação, caminho autorizado, GPU confirmada, resolução/Hz, objetivo, Reflex, VRR, V-Sync, limite FPS e preservação de captura. Mostra conflitos e salva hipóteses locais, sem escrever perfis privados de driver.
- Importação de frametimes CSV/PresentMon, FPS médio, 1% low com método declarado e p50/p95/p99. Comparação exige condições equivalentes e passes independentes. Input lag não é inferido dessas métricas.
- 16 executores nativos de Registro: sete preferências do Explorer, cinco de aparência, duas preferências de jogos do Windows 11, uma política de captura do Windows 10 e uma política de confirmação de exclusão. O motor verifica Windows/build, arquitetura, edição, elevação e contexto conforme cada ação; lote comum limitado a sete itens. As cinco mudanças `B_APPROVAL` exigem aprovação por ID e execução individual. Animações da barra de tarefas continuam disponíveis como guia manual.
- 50 procedimentos avançados correspondentes aos itens antes bloqueados, com pré-requisitos, fontes oficiais, recuperação e registro manual separado das transações verificadas. Controles dependentes de capacidade não confirmada mostram o motivo e o que falta confirmar; consulte [a lista integral](docs/ADVANCED-ACTIONS.md).
- Seleção de plano de energia já existente, com GUID original, prévia, revisão de consumo/calor, administração e console local confirmados, journal e restauração. O app não cria, exclui ou modifica planos.
- Sessão persistente, comparação da prévia com o estado atual, journal durável, read-back, rollback e recuperação por identidade do Windows/usuário. O inventário permanece em memória até autorizar seu registro local. Restaurar recupera o valor original, inclusive ausência, e preserva os snapshots se houver falha.
- Relatório HTML para cliente, JSON/CSV, minimização de dados pessoais e pacote privado de reversão com script independente. Finalização valida os arquivos e preserva a recuperação; pode ser repetida.
- Catálogo pesquisável com 344 requisitos e 64 documentos completos, fontes, hashes, riscos, classes, relações e textos originais, inclusive itens de laboratório e procedimentos manuais. **344 requisitos catalogados não significam 344 ajustes implementados.** Um registro pode apontar para um executor nativo específico; somente a lista de executores do código autoriza essa operação, com seus próprios limites.

Consulte [a matriz de funções](docs/FEATURE-MATRIX.md) e [a validação](docs/VALIDATION.md) para conhecer a cobertura real.

## Fluxo de atendimento

1. Abra uma sessão e informe objetivo, contexto local/remoto e autorização de registro.
2. Analise o PC e revise os dados indisponíveis e o plano contextual.
3. Registre um perfil por jogo e suas condições; consulte guias por fabricante/aplicativo.
4. Se houver uma mudança desejada, selecione a direção, leia o valor atual/proposto e os trade-offs, gere a prévia e confirme. Configuração persistida não comprova efeito em execução nem ganho de FPS. O modo Demo simula sem alterar essas preferências.
5. Para benchmark, importe CSV de uma única aplicação/swapchain. Use 3–5 passes distintos por condição e mude somente a variável estudada.
6. Revise histórico e relatório. Clique em **Revisar e finalizar serviço** e escolha o destino da exportação.

Os registros ficam em `%LOCALAPPDATA%\GOAT-Tweaks\Sessions\ID` por padrão. O pacote `private-recovery` contém identidade e snapshots privados: **não publique essa pasta**. Somente `report.html`, `report.json` e `transactions.csv` são projeções destinadas ao cliente, ainda sujeitas à revisão antes de compartilhar.

## Build e testes

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\Build.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\scripts\Test.ps1
```

Saídas: `dist/GOAT-Tweaks.ps1`, `GOAT-Tweaks.sha256`, `build-manifest.json`, `GOAT-Tweaks-7.4.1.zip`, `Open-GOAT.txt` e `launch.json`. A versão vem do arquivo `VERSION`. O bundle ASCII contém recursos UTF-8 comprimidos em GZip e Base64, decodificados localmente em memória. O código legível está em `src/`. Não há execução de texto do catálogo ou dos prompts.

Os testes de ações usam mocks para aplicação, falha, read-back e restauração de todos os executores, sem mudar preferências do Windows. `tests/Test-RegistryIntegration.ps1` também verifica a API real de Registro somente em uma chave própria e descartável `HKCU\Software\GOAT-Tweaks-Tests\GUID`, incluindo tipos binários, strings, arrays e ausência original. A UI usa Demo; energia é testada com fixtures, sem trocar o plano real. Há leituras reais de inventário nesta máquina. Esse escopo não certifica efeitos em outras versões do Windows, GPUs ou configurações de jogos.

Para regenerar os dados a partir do pacote original:

```powershell
powershell.exe -NoProfile -File .\scripts\Import-Specification.ps1 -SourceRoot 'D:\caminho\GOAT_TWEAKS_V7_3_PACOTE_MESTRE'
```

## Escopo da versão oficial

A liberação dos 16 executores confirma código e testes de armazenamento/reversão no escopo declarado em cada ação. **Não confirma efeito visual imediato, política efetivamente aplicada, ganho de desempenho ou segurança universal em todos os PCs.** A matriz física Windows 10/11 + NVIDIA/AMD/Intel e ensaios em VMs de preferências reais permanecem pendentes; o pacote não possui assinatura Authenticode de editor. Preferências podem exigir reabrir a interface ou iniciar nova sessão; o GOAT nunca encerra Explorer nem reinicia o PC automaticamente.

Modo de Jogo e atalho do controle para Game Bar têm executor somente no Windows 11. A política `AllowGameDVR` exige Windows 10 desktop, edição compatível, administração, console local e ausência de gerenciamento corporativo confirmado; no Windows 11 a captura permanece assistida. A Microsoft documenta essa limitação da política em [ApplicationManagement/AllowGameDVR](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-applicationmanagement#allowgamedvr). Temas e transparência são preferências de aparência, não otimizações de FPS.

Sensores de temperatura, hotspot, clocks, potência e VRAM ficam indisponíveis sem provedor validado. Captura ETW, overlay injetado, OC, undervolt, BIOS/UEFI, MSI/HPET/BCD, desativação de segurança e remoção automática de drivers não ganharam executores pelo fato de aparecerem no catálogo. Consulte [as mudanças e o escopo da 7.4.1](docs/RELEASE-7.4.1.md).

A revisão do pacote está em [docs/audit/RELEASE-REVIEW.md](docs/audit/RELEASE-REVIEW.md). A integridade da fonte documental não prova a eficácia de suas sugestões históricas. Correções e decisões atuais ficam registradas separadamente, preservando os documentos recebidos.

O app é portátil: não instala serviço, helper, tarefa agendada nem inicialização automática. Finalizar preserva relatórios e snapshots; não apaga logs do Windows, dados de terceiros ou ferramentas de acesso remoto. Remover o arquivo do aplicativo não desfaz preferências persistentes previamente aprovadas.
