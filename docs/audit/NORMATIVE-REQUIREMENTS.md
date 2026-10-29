# Auditoria de requisitos do pacote documental

Data de referência: 28/10/2026. O pacote fornecido contém 83 arquivos; não contém uma implementação completa. `document-reading-evidence.json` registra caminho, tamanho, hash, linhas e profundidade de leitura. Ler bytes e calcular hashes não equivale a uma revisão semântica de cada linha histórica. Foram lidos semanticamente os 47 documentos normativos/operacionais indicados no manifesto; os JSONs são objeto da auditoria de catálogo separada. As grandes consolidações históricas V4 foram inventariadas e inspecionadas parcialmente, sem alegação de revisão integral linha a linha.

## Precedência

1. Pedido humano vigente: um projeto PowerShell novo, reunido num app e publicado no GitHub. A orientação documental de continuar exclusivamente o repositório anterior foi substituída por esse pedido explícito.
2. `00_COMECE_AQUI_GOAT_TWEAKS.md` e `04_PROMPT_PARA_IA/PROMPT_ATIVO_GOAT_TWEAKS.txt`: marca GOAT Tweaks, integração GPU CENTER, políticas de capacidades e honestidade de estados.
3. Prompt/master V7.3, contratos técnicos da pasta 14, automação/finalização da pasta 09, doutrina da pasta 10, evidência/benchmark da pasta 11.
4. Catálogos e complementos descrevem cobertura; não autorizam execução. Prompts V4–V7.2 e auditorias antigas são contexto.

As cópias de `00_MASTER_TECNICO_V7_3.md` nas pastas 01 e 14 têm o mesmo SHA-256: `60148fe27ef87d6d790bb80487ca6f0cc722751539546e17016cb97a7498ba27`.

## Requisitos concretos por módulo

| Módulo | Comportamento requerido | Limite para habilitar |
|---|---|---|
| Inicialização e sessão | Windows PowerShell 5.1 STA/WPF; tema preto/grafite/dourado; sessão aleatória; modo Demo e ScanOnly sem mutações; estado e consentimento persistidos | Falha de journal torna escrita indisponível; não exigir admin para leitura |
| Inventário | Windows/build, CPU/RAM, todas as GPUs/PCI/PnP/driver, armazenamento/rede/monitor quando confiável; origem, horário, confiança e erros | Desconhecido não é zero; nome de GPU não prova capacidade; AdapterRAM não confirma VRAM |
| Diagnóstico e plano | Objetivo/jogo selecionados; regras explícitas; confiança baseada em mais de um sinal; plano de até 3–7 ações relevantes | Não inventar quantidade nem concluir gargalo por uma leitura isolada |
| Catálogo | IDs estáveis e deduplicados; status, risco, descrição, condições e motivos; busca/filtros; guias para ações manuais | SPEC_ONLY_NOT_YET_VERIFIED não recebe botão de aplicar |
| Transação | Preflight, elegibilidade, estado exato, journal durável antes de qualquer mutação, snapshot validado, aplicação mínima, read-back, pós-condição e resultado | Preservar ausência/tipo/dados/hive/view. Não apagar chave pai. OFF e restaurar original são diferentes |
| Recuperação | Reconciliar operações incompletas antes de nova escrita; rollback individual/sessão e verificação | RESTORE_FAILED preserva cópia/journal e bloqueia ações conflitantes |
| GPU CENTER | Áreas de visão geral, drivers assistidos, perfis contextuais, monitoramento, benchmark, histórico e restauração | Nenhum driver uninstall/OC/reboot automático; tecnologias por capacidades reais |
| Drivers | Fontes NVIDIA/AMD/Intel oficiais e OEM; versão instalada separada de última versão; checklist e plano de recuperação | DDU guia manual excepcional; bloqueado remoto sem operador local/canal de recuperação; nenhum mirror arbitrário |
| Perfis de jogos | Identidade inequívoca do jogo/exe/GPU/monitor/objetivo; competitivo/equilibrado/qualidade como hipóteses; conflitos Reflex/VRR/VSync/cap/captura | Sem alteração global por padrão; preferência externa não equivale a rollback automático |
| Telemetria | Fonte, unidade, timestamp, validade e motivo de ausência; temperatura/potência/hotspot somente com fonte compatível | Sensores indisponíveis não geram valores simulados fora do Demo |
| Benchmark | Dados brutos, fonte e método; FPS médio, 1% low declarado, p50/p95/p99; comparação mesma cena/build/driver/resolução/preset/API/cap; 3–5 passes e variabilidade | Sem limiar percentual universal. Passagem isolada/ruído/condições diferentes ficam inconclusivos; telemetria não mede input lag |
| Aplicativos | Steam/Discord/OBS/overlays: detecção de versão, trade-offs e guia; adapters somente com parser/fixtures/backup/merge/read-back | Não matar por nome, não editar configuração privada desconhecida, não impor launch args universais |
| Rede/armazenamento/startup | Diagnóstico separado de FPS; startup item a item; saúde disponível; consentimento para banda/escrita | Não alterar IPv6/MTU/DNS/firewall/NIC automaticamente; não escrever benchmark em disco suspeito; não limpar Run/RunOnce em massa |
| Relatório e privacidade | Resumo cliente/anexo técnico local; inventário, ações, verificação, evidência, limitações e recuperação; redigir dados pessoais; hash e reabertura | Exportação com destino e consentimento; sem senhas/tokens/cookies/serial completo/nomes de cliente desnecessários |
| Finalizar serviço | Idempotente; congelar novas ações; reconciliar operações; resolver temporários; exportar e verificar relatório/reversão; ajustes nativos aprovados persistem | Export falho conserva única cópia; limpeza só de arquivos/serviços cujo ownership GOAT está provado; nunca logs de Windows/terceiros ou ferramentas remotas |

## Conflitos históricos resolvidos

O histórico `02_INTEGRACAO_ULTIMATE_WINSUX_EXM.md` admitia certos controles de segurança em Extreme Lab. O master V7.3, a doutrina atual e o prompt GPU os restringem: não portar desativação de Defender/VBS/HVCI/UAC/firewall/Update, bypass de assinatura, TrustedInstaller hijack, ExecutionPolicy Unrestricted, IWR|IEX, BIOS/UEFI, thermal-protection disable ou automação disruptiva de drivers/rede. Rotular uma operação como LAB não satisfaz os requisitos atuais.

RESET EXPLODE é referência seletiva no commit `ce1d9b30518bbe75bb5e6cb792d1b1e365aaddd6`, sem importar seu EXE, drivers ou assets. O inventário de 135 entradas não significa auditoria semântica de todas as linhas upstream. A licença MIT do repositório não abrange automaticamente binários/SDKs de fabricantes. Adoção de código exigiria copyright/licença correspondentes e revisão das dependências.

## Cobertura viável e critérios de pronto

1. P0: aplicação executável, sessão, inventário read-only, catálogo com gates, consentimento, transação/recuperação e relatório local.
2. P1/P2: importação e análise de capturas reais, perfis contextuais, fontes e guias; sensores só quando provider suportado estiver disponível.
3. P3: liberar cada ação de escrita separadamente após testes positivos/negativos, idempotência, falha parcial, crash, permissão insuficiente, read-back e rollback exato em Windows descartável.
4. P4/P5: adapters versionados e manutenção/laboratório opt-in, sempre fora do lote expresso quando houver risco.
5. P6: finalização idempotente, exportação validada, ownership, compatibilidade, hashes e assinatura de distribuição quando disponível.

Antes de considerar pronto para atendimento em clientes: testes reais em Windows 10/11 x64, hardware NVIDIA/AMD/Intel, sem sensor, multi-GPU/híbrido, drivers antigos/básicos/OEM, falha/timeout CIM, sem admin, modo Demo, ScanOnly, sessão remota, monitor trocado, captura/acessibilidade, corrupção de journal, export inacessível, rollback falho e UI com teclado/DPI/thread correto. Hardware não disponível permanece **não testado**. CI e testes estáticos isolados não comprovam segurança de driver nem ganho de FPS.

Uma publicação de desenvolvimento deve indicar precisamente o que funciona e o que permanece pendente. Não anunciar contagens de catálogo como tweaks implementados, “101% funcional”, segurança universal ou ganho garantido.

## Benchmark entregue neste projeto

`src/Benchmark.ps1` fornece `Get-GoatFrameMetrics`, `Import-GoatFrameCapture` e `Compare-GoatBenchmarkRuns`. O importador lê CSV de intervalos em ms, conserva amostras e hash, rejeita NaN/infinito/zero, mistura de processos e swap chains. A comparação exige condições e origem compatíveis, passes independentes e estabilidade explicitamente verificada para confirmar benefício. O método usa mediana e faixa observada por condição; não se apresenta como intervalo de confiança estatístico nem como medição de input lag. `tests/Test-Benchmark.ps1` executa fixtures sem alterar configurações do computador.
