# Matriz funcional desta entrega

Este app foi escrito do zero em PowerShell/WPF. A versao oficial 7.3.0 cobre os fluxos implementados: uma unica aplicacao integra inventario, GPU Center, catalogo, referencias, sessoes, analise de capturas e exportacao. A navegacao possui 16 paginas; isso nao significa 16 motores de otimizacao automaticos. Parte das paginas exibe dados estruturados e orientacoes.

## As 16 paginas

| Pagina | Disponivel no codigo | Limite atual |
| --- | --- | --- |
| Visao geral | Resumo de OS/CPU/GPU/RAM e hipoteses de diagnostico baseadas no inventario | Snapshot e hipoteses; nao mede FPS ou input lag |
| Atendimento | Sessao local persistida, objetivo, modo local/remoto e consentimento contextual | Sem CRM, identidade de cliente ou atendimento remoto embutido |
| Catalogo completo | Busca/filtros dos 344 registros, explicacoes, risco, classe, origem e conteudo fonte | Todos permanecem `SPEC_ONLY_NOT_YET_VERIFIED`; nenhum texto documental e executado |
| Windows / preferencias | Previa, simulacao e engine de transacao para mostrar extensoes e mostrar arquivos ocultos | Duas preferencias nativas, sem ganho de FPS alegado; ambas `IMPLEMENTED_NOT_VALIDATED`, `ReleaseEnabled=false` e aplicacao real bloqueada |
| CPU / RAM | Topologia, memoria e contadores disponiveis, com origem e indisponibilidade explicitas | Sem OC, undervolt, ajuste de afinidade/prioridade, limpeza de RAM ou diagnostico automatico conclusivo de gargalo |
| GPU CENTER | Inventario PCI/PnP e driver instalado, metadados de monitores, fontes oficiais e guias NVIDIA/AMD/Intel/OEM; motores GPU quando expostos | Sem instalacao/remocao de driver, consulta automatica de versao mais recente, VRAM deduzida de AdapterRAM ou temperatura inventada; capacidades nao confirmadas ficam `UNKNOWN` |
| Jogos / perfis | Perfil contextual por jogo, caminho autorizado, objetivo, GPU, resolucao/Hz e conflitos de Reflex/VRR/V-Sync/caps/captura; persistencia e importacao | Perfil e dados/recomendacoes; nao altera automaticamente painel de driver, arquivos do jogo ou argumentos do launcher |
| Steam / Discord / OBS | Versoes por metadados instalados e guias integrais de configuracao | Sem adaptadores de escrita de configuracao, controle de processos, leitura de tokens ou versao da interface presumida |
| Rede / latencia | Inventario de adaptadores e velocidade de link reportada | Sem ping/jitter/perda/bufferbloat/throughput medidos, troca DNS, MTU, IPv6 ou reset de adaptador |
| Armazenamento | Discos, espaco livre e metadados; API de confiabilidade somente quando o provedor fornecer | Nao garante SMART completo; sem benchmark de escrita, TRIM forcado ou alteracao de cache |
| Inicializacao / apps | Nomes de entradas e metadados Steam/Discord/OBS, sem comandos ou usuario | Sem remocao/desativacao de entradas, instalacao/atualizacao via winget ou encerramento de apps |
| Benchmarks | Importacao de CSV de captura com fonte/hash; FPS medio, 1% low pelo metodo declarado e percentis; comparacao com condicoes/repeticoes verificadas | Sem capturador ETW/PresentMon embutido, injecao, overlay ativo ou medicao de input lag; depende de capturas reais fornecidas |
| Historico / reversao | Eventos de sessao, diarios duraveis, estados de transacao e restauracao exata pelo executor autorizado | Drivers e guias manuais tem recuperacao separada. Acoes nativas reais continuam bloqueadas por validacao pendente |
| Relatorios | HTML/JSON/CSV, dados publicos minimizados, pacote privado de reversao, manifesto de hashes e verificacao de exportacao | Pacote privado pode conter identidade/caminhos necessarios a recuperacao; nao e publicacao automatica nem prova de ganho |
| Documentacao | Busca e leitura de 64 documentos completos, com origem/hash e prompts identificados como referencia | Texto somente leitura; comandos e prompts nao viram instrucoes executaveis |
| Laboratorio / bloqueios | Consulta dos itens `D_LAB_ONLY` e `X_BLOCKED`, riscos e motivos | Sem executores de BIOS/UEFI, OC/undervolt, HPET/MSI/BCD, DDU automatico, desativacao de seguranca ou remocoes disruptivas |

## Finalizar servico e recuperacao

O fluxo de finalizacao congela novas operacoes da sessao, verifica transacoes pendentes e exporta relatorio/pacote de reversao com manifesto validado. A finalizacao e idempotente e preserva a recuperacao se a exportacao falhar. Nesta versao o app e portatil; nao ha servico GOAT, agente persistente, desinstalador de terceiros nem limpeza universal do computador. Nenhum reinicio automatico ou apagamento de logs Windows/seguranca/cliente faz parte do fluxo.

## Cobertura da especificacao

- **344 IDs de especificacao**, com seus textos integrais, classe, fontes e estado original preservados: 246 do catalogo central + **73** complementos V7.3 + 25 do GPU Center. O texto de abertura dos complementos diz 66, mas seu array possui 73.
- Os 66 registros de `new_controls` ja estao nos 246 centrais e nao sao somados novamente. IDs diferentes com comportamentos relacionados conservam `related_ids`; a contagem nao equivale a 344 acoes independentes.
- **41 bloqueios originais** sao preservados, mais nove overrides normativos: **50 bloqueios efetivos**, com motivo/fonte/hash e texto original preservado. Os demais tambem nao ganham permissao de execucao pela importacao.
- **64 documentos completos** incorporados para consulta. Isso nao transforma exemplos historicos ou pseudocodigo em implementacao.
- **Duas preferencias nativas** possuem executores originais com preview, journal, read-back e rollback, ainda bloqueados para uso real ate concluir a matriz de validacao. Modo Demo simula sem alterar o Windows.

## Modulos ainda ausentes ou nao liberados

Nao estao implementados como automacao: captura ETW/PresentMon em tempo real, overlay ativo, sensores de temperatura/hotspot/potencia/clocks/VRAM por API validada, medicao fisica de input lag, stress tests, OC/undervolt/firmware, ajustes de seguranca, DDU/instalacao ou remocao de driver, configuracao de paineis NVIDIA/AMD/Intel, adaptadores de escrita Steam/Discord/OBS, descoberta completa de bibliotecas de jogos, alteracao de argumentos de launcher, afinidade/prioridade/leasing de processos, modificacao de inicializacao, ferramentas de rede, winget, RGB e Maker/serial. Os guias e registros correspondentes continuam consultaveis quando presentes na especificacao.

Nao ha pacote assinado/certificado, compatibilidade universal nem evidencia de ganho de FPS nesta entrega. Testes unitarios de fixtures, smoke de UI/demo e leituras na maquina disponivel cobrem somente os cenarios efetivamente executados. A liberacao de mutacoes exige matriz adicional em Windows 10/11 e sistemas descartaveis; a cobertura fisica NVIDIA/AMD/Intel e os sensores correspondentes devem ser registrada separadamente.

## Comandos de verificacao

Execute `scripts/Build.ps1` para produzir o aplicativo unico, conforme o README. Os testes ficam em `tests/`; `tests/Test-Inventory.ps1` verifica inventario e integracao GPU sem consultar hardware real. `scripts/Import-Specification.ps1 -SourceRoot <pasta>` reimporta a fonte, confere os 81 hashes do manifesto ativo e regenera os dados de consulta.
