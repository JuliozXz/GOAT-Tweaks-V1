# Revisao semantica do detalhamento historico e da integracao V2

Revisao em 28/10/2026. Os dois documentos abaixo foram preservados sem alteracao. As erratas deste relatorio complementam sua leitura historica; os prompts atuais, as politicas V7.3 e o contrato do GPU Center prevalecem.

| Documento original em `02_ESPECIFICACAO_E_AUDITORIA/` | Bytes | SHA-256 |
| --- | ---: | --- |
| `04_IMPLEMENTACAO_DETALHADA.md` | 271548 | `e04bc0fa3b2e162ed66c16cc947845202efc2ccdf6b7451b2855df7565e9462e` |
| `02_INTEGRACAO_ULTIMATE_WINSUX_EXM.md` | 19350 | `e4c712d5612e8688552c03596e091cb789d2d26fccae764975b247503ed3b4a8` |

## Metodo e cobertura

`04_IMPLEMENTACAO_DETALHADA.md` foi lido em blocos que cobrem seus requisitos iniciais, todos os **180 controles concretos**, todas as **153 descricoes de topicos**, criterios de evidencia, blueprint, prompt historico e apendice V2. Para cada controle foram examinados implementacao, risco/modo, notas, beneficio, elegibilidade, rollback e verificacao. As relacoes dos topicos foram conferidas mecanicamente contra a fonte estruturada.

Uma comparacao campo a campo com `03_CATALOGOS_E_INVENTARIOS/01_CATALOGO_TECNICO_HISTORICO.json` confirmou **2.340 campos de controles** sem diferenca: nome, categoria, implementacao, padrao, beneficio, risco, evidencia, modo, elegibilidade, rollback, validacao, notas e fontes para cada um dos 180 IDs. Para os 153 topicos, **459 comparacoes** de titulo, descricao e IDs relacionados tambem nao apresentaram diferenca. O texto comum que exige estado real, compatibilidade, risco, medicao e rollback foi considerado como regra repetida, sem tratar suas repeticoes como requisitos novos.

Mapa do detalhamento, com linhas do original:

- 1-46: objetivo, limite factual sobre EXM, fail-closed, snapshots, privacidade, transacoes, interfaces suportadas e schema.
- 47-3874: os 180 controles Windows, energia/CPU, RAM, armazenamento, GPU, rede, timers, entrada/audio, seguranca, jogos e ferramentas.
- 3875-5256: os 153 topicos de cobertura, com descricoes e mapeamento para controles reais; nao sao 153 internals confirmados de EXM.
- 5257-5287: propostas historicas de alto risco e ressalvas.
- 5288-5344: arquitetura, diagnostico, metodologia, testes e fontes.
- 5345-5389: prompt historico e apendice de integracao; nao sao prompts ativos nesta versao.

`02_INTEGRACAO_ULTIMATE_WINSUX_EXM.md` tambem foi lido integralmente: fontes/licencas, os oito grupos Ultimate, os seis componentes WinSux destacados, a cobertura EXM, contratos de transacao/reversao, niveis Standard/Advanced/Extreme Lab, tabela de seguranca, metricas, testes e entrega. Os commits mencionados sao referencias historicas do documento; esta revisao nao reexecutou ou auditou todos os scripts originais nesses commits.

## Conteudo que permanece aplicavel

As partes mais consistentes exigem elegibilidade por build/dispositivo, estado desconhecido explicito, interfaces oficiais, perfil por jogo, preservacao de captura e dependencias, mudanca minima, read-back e restauracao. O documento distingue corretamente privacidade/aparencia de FPS, I/O de renderizacao, RTT de input lag e polling de latencia total. Ele rejeita presets destrutivos, exclusao opaca de hosts, importacao integral de Registry, bootstrap remoto, TrustedInstaller hijack, limpeza de RAM como ganho universal e apagamento de logs.

Os topicos repetidos, como Direct Flip 82/88, Miracast 83/89, Energy Driver 84/90/129 e Network Priority 14/130, nao foram contados como executores independentes. As secoes de NVIDIA/AMD/Intel, VRR/V-Sync, shader cache e limites de FPS continuam hipoteses dependentes de jogo/driver/monitor. Campos sem fonte confiavel permanecem indisponiveis, mesmo quando a descricao historica sugere sensores ou capacidades que o app atual ainda nao le.

## Erratas atuais, mantendo o original

| Local no original | Clausula historica | Leitura/errata vigente |
| --- | --- | --- |
| Detalhamento:23, 2823-2843, 5259 e 5375; Integracao:116, 123-139 e 169 | Seguranca critica como fluxo manual/Extreme Lab, inclusive HVCI, Defender, firewall, UAC, mitigações e signing | Consentimento ou laboratorio nao revogam bloqueios atuais. Nao oferecer executores de desativacao de protecoes, bypass de assinatura ou boot. Diagnostico permanece disponivel. |
| Detalhamento:5352 | Chave privada de driver admitida se houver fonte/matriz/rollback | O contrato atual prioriza API oficialmente suportada ou guia manual. Pesquisa/benchmark nao convertem chave privada em API universal autorizada. |
| Detalhamento:1663-1683, topico 85 e Integracao:50-52 | `GPU-NV-PERFLIMIT` mistura diagnostico PerfCap com slider de power limit/OC | Alias identificado nesta revisao e reclassificado como `X_BLOCKED` para alteracao. O texto e a possibilidade de diagnostico somente leitura continuam preservados; `GPU-THERMAL` e inventario nao viram controles de OC. |
| Detalhamento:790, 1210, 2007, 2718 e 2781; apendice:5372-5376 | OC, firmware e MSI por dispositivo/manual | Prevalecem os bloqueios de mutacao atuais por IDs revisados. Nem rotulo manual nem risco aceito habilitam execucao. Fontes historicas nao sao apagadas. |
| Detalhamento:277, 720 e 1394 | Restaurar Windows-decide, prioridade Normal ou driver-default/off | Restaurar original exige o valor efetivamente capturado, inclusive ausencia. Defaults/Off/Normal sao propostas distintas e nunca substituem um original customizado. |
| Detalhamento:2126 e 2285 | Voltar autotuning a Normal e todos os endpoints a MTU padrao | Capturar e restaurar exatamente cada estado anterior, inclusive configuracao customizada. Nao executar procedimentos que possam interromper acesso remoto sem o fluxo permitido de manutencao. |
| Detalhamento:2623 | Restaurar defaults de BCD em guia controlado | BCD/HPET/MSI continuam sem executor no app. Uma recuperacao externa exige snapshot original e procedimento proprio; default nao e restauracao exata. |
| Detalhamento:1256 | `STOR-HIPM-DIPM` menciona `Get-Net? actually use PnP...` | Trecho e rascunho, nao especificacao executavel. Nao inventar cmdlet de rede para SATA; manter sem executor ate API/propriedade oficial e matriz real. |
| Detalhamento:3032 | Se rollback falhar, reverter automaticamente e parar perfis | Se a restauracao falhou, nao declarar sucesso ou assumir outra reversao. Preservar journal/snapshot, bloquear novas mutacoes e sinalizar falha para recuperacao assistida. |
| Detalhamento:353 | `WIN-CLEAN` usa a expressao ambigua excluir caches/Prefetch/pastas de jogo | Interpretar como exclusao dessas categorias da limpeza padrao. O restante do documento proibe purga rotineira de shader cache e Prefetch. Nenhum limpador executavel foi criado a partir da frase. |
| Detalhamento:1419 | `GPU-NV-REFLEX` inclui sensacao/sensibilidade em validacao | Feedback subjetivo pode ser anotado, mas nao comprova reducao numerica de input lag. Exigir metodo instrumentado para essa afirmacao e separar de FPS/frametime. |
| Detalhamento:5307-5318 | Linha 1% low refere-se genericamente a percentil/frametime | Declarar o estimador exato. Media dos piores 1% e reciproco de p99 sao medidas diferentes; o app nao deve intercambia-las sem metodo explicito. |
| Detalhamento:17, 3014-3034; Integracao:78 e 113-117 | Servico/watchdog e leases para timer, prioridade, afinidade e servicos | Arquitetura proposta para funcoes temporarias futuras. O app atual e portatil e nao instala servico/watchdog; nao habilitar leases sem ciclo de vida e recuperacao testados. |
| Integracao:48-52, 61-69 e 119-139 | P0/DisableDynamicPstate, MSI e varios riscos como Advanced/Extreme Lab | Politicas atuais e gates prevalecem. Nao portar chaves, drivers ou scripts apenas porque aparecem na referencia upstream. |
| Integracao:139 | Write-cache flushing off manual em certos dispositivos | Bloqueio atual prevalece: `DISK-004` e demais registros explicitamente bloqueados nao executam. |
| Integracao:13-17, 72-78 e 174-176 | Licenca MIT dos repositorios e caminhos para utilitarios | Nao concede redistribuicao automatica de DDU, Afterburner, CRU, drivers, runtimes ou outros binarios. A entrega nao os incorporou por essa referencia. |

O texto historico sobre limpeza/instalacao de driver tambem precisa ser lido com o GPU Center atual: manutencao assistida, confirmacao local, recuperacao separada e bloqueio remoto/incerto. Ponto de restauracao ou snapshot de Registry nao garantem desfazer driver/firmware.

## Resultado integrado ao catalogo

A revisao encontrou um alias concreto adicional (`GPU-NV-PERFLIMIT`) para o bloqueio de power-limit/OC. Com a correcao autorizada, o catalogo permanece com **344 IDs e 64 documentos**, contendo **41 bloqueios originais e 50 efetivos**, dos quais **nove** sao overrides normativos rastreados. Todos os gates de execucao documental permanecem falsos. `source_record`, fontes, hashes e textos originais foram mantidos; apenas a classificacao efetiva e sua justificativa foram acrescentadas.

`Test-Catalog.ps1` passou com **3.322 verificacoes** em Windows PowerShell 5.1 apos a incorporacao do alias; a mesma suite passou em PowerShell 7. O importador confirmou novamente 83 arquivos e 81 hashes validos. As demais erratas deste documento se referem a especificacoes historicas, nao a executores atualmente liberados.

Esta conclusao cobre o pacote documental e suas contradicoes semanticas observadas. Nao certifica os 108 arquivos upstream citados, executaveis/drivers de terceiros, efeitos de ajustes em hardware ou todas as combinacoes Windows/GPU. A classificacao oficial 7.3.0 continua limitada ao escopo funcional entregue e documentado.
