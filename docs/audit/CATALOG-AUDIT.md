# Auditoria dos dados da especificacao

O importador leu os 83 arquivos do pacote fonte por inteiro. Os 18 JSON foram analisados, com travessia das 22.875 folhas escalares, e as 135 linhas/945 celulas do CSV foram lidas. Os 81 arquivos cobertos pelo manifesto ativo conferem tanto em SHA-256 quanto em tamanho. O proprio manifesto ativo e seu checksum ficam fora desse escopo para evitar referencia circular.

O catalogo central contem 246 registros: 180 historicos mais 66 complementares. A propriedade `new_controls` repete esses mesmos 66 registros e nao foi somada outra vez. Todos os 180 IDs historicos estao no catalogo central. O catalogo complementar V7.3 declara 66 no texto introdutorio, mas seu array contem **73 registros reais**. O GPU Center acrescenta 25 registros. O catalogo importado preserva **344 IDs distintos**, todos em `SPEC_ONLY_NOT_YET_VERIFIED` e com `apply_allowed=false`.

Existem sobreposicoes semanticas com IDs diferentes: Game Mode, HAGS, captura, overlays, preferencia GPU por aplicativo, plano de energia, prioridade/afinidade de processo, diagnostico de RAM, saude de disco e benchmark. Quinze grupos conhecidos estao registrados em `specification-import.json`; os controles mantem `related_ids`, a origem e o registro fonte completo. Esses grupos nao sao uma contagem de acoes independentes nem uma certificacao de equivalencia exata: alguns tem escopos diferentes.

Quarenta e um registros possuem bloqueio explicito por `apply_mode=blocked` ou `execution_class=X_BLOCKED`. O bloqueio prevalece sobre rotulos historicos de automacao condicional. Os 246 registros do catalogo central nao fornecem a classe normativa V7.3; a importacao lhes atribui classificacao conservadora `C_MANUAL`, exceto os bloqueados, sem habilitar execucao. Os demais mantem a classe de projeto declarada, ainda sem permissao de aplicar.

Os 64 arquivos Markdown/texto foram incorporados integralmente em `data/documents.json`. Prompts recebem `kind=prompt_reference` e `executable=false`. O app consulta seu conteudo como referencia; nao interpreta instrucoes ou trechos de comandos como codigo.

O importador passou em PowerShell 7 e Windows PowerShell 5.1. A integridade da fonte, os textos completos e os hashes constam dos JSON de auditoria. Isso valida importacao e rastreabilidade, nao implementacao de todos os controles nem compatibilidade de hardware.

## Adaptacao para um unico app PowerShell

- Empacotar os dados como recursos de consulta junto do codigo original do app; nunca executar `source_record`, `content`, `apply_steps` ou textos de prompt.
- Manter executores reais numa lista explicita independente. Um item somente pode mudar de status com testes de elegibilidade, leitura do estado, journal duravel, leitura posterior e reversao.
- Preservar guias, referencias e bloqueios no catalogo. Ausencia de API oficialmente suportada nao autoriza escrever chaves privadas de driver.
- Drivers/DDU devem permanecer manutencao manual com presenca local e recuperacao separada; snapshot de Registry nao restaura um driver.
- Permitir consulta e diagnostico sem administrador. Sensores sem fonte ficam indisponiveis, motores GPU nao sao somados em carga total, e resultados de benchmark nao medidos permanecem sem valor.

## Inventario implementado e verificacao

`src/Inventory.ps1` implementa inventario somente leitura com consultas CIM limitadas por `OperationTimeoutSec`, fontes e falhas explicitas. Inclui Windows/CPU/RAM/discos, contadores de confiabilidade quando expostos, adaptadores de rede, nomes de entradas de inicializacao, metadados Steam/Discord/OBS, contexto remoto conservador, estado de seguranca e indicadores conhecidos de reinicio. Nao coleta linhas de comando, credenciais, serial, MAC, IP ou nome de cliente.

Telemetria de CPU/RAM e motores GPU e um snapshot, sem alegacao de FPS ou input lag. O diagnostico produz ate sete hipoteses/guias conforme evidencias disponiveis e objetivo. Nao altera o Windows.

`tests/Test-Inventory.ps1` passou com **24 verificacoes** em PowerShell 7 e Windows PowerShell 5.1. Abrange demo sem consultar providers, falhas/timeout CIM, campos ausentes com caller em strict mode, leitura zero valida, valores GPU invalidos, ausencia de total GPU sintetico, protecao remota, ausencia de segredos, calculos RAM/disco e limite/semantica do diagnostico. Os testes usam fixtures e nao certificam todos os fabricantes ou builds.

Um smoke de leitura real em Windows 10 Pro build 19045 concluiu em aproximadamente 1,55 segundo: metadados OS/CPU/RAM/discos/apps e contadores foram lidos; o provedor de confiabilidade de armazenamento retornou vazio e foi sinalizado como indisponivel. Nao foram feitas alteracoes de sistema. Windows 11 e outras combinacoes fisicas continuam pendentes.
