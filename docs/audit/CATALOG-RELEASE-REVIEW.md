# Revisao do corpus e inventario para GOAT Tweaks 7.3.0

Data da revisao: 28/10/2026. A versao oficial identifica o escopo funcional atual do aplicativo; nao declara implementacao de todos os itens propostos no ZIP nem libera mutacoes sem validacao. Nenhum arquivo original do pacote de requisitos foi modificado.

## Cobertura revalidada

O importador leu integralmente os **83 arquivos**: **18 JSON**, **1 CSV** com **135 linhas e 945 celulas**, e **64 documentos Markdown/texto**. A revisao combina leitura automatizada completa para estrutura/proveniencia e revisao dirigida das politicas vigentes, contratos e conflitos dos catalogos. Isso nao equivale a executar os exemplos do pacote ou revisar binarios upstream.

Os **81 arquivos** cobertos pelo manifesto ativo conferem em tamanho e SHA-256. O manifesto e seu checksum permanecem fora da propria lista para evitar circularidade. `package-integrity.json` registra os resultados por arquivo; `specification-import.json` registra a cobertura. Arquivos adicionais nao manifestados agora interrompem a importacao em vez de serem incorporados silenciosamente.

Foram preservados **344 IDs distintos**: 246 centrais + **73 complementos reais** V7.3 + 25 GPU Center. Os 66 `new_controls` centrais sao repetidos dentro dos 246 e nao sao contados novamente. O texto de abertura dos complementos fala em 66, mas seu array possui 73. Todos os 180 controles historicos estao representados no catalogo central.

Os **64 documentos** continuam completos, com os mesmos hashes e bytes UTF-8 reconstruidos nos testes. Os prompts permanecem referencias nao executaveis. Quinze grupos conhecidos de comportamentos relacionados conservam `related_ids`; alguns abrangem escopos diferentes, portanto essa relacao nao e uma fusao automatica ou contagem de acoes independentes.

## Precedencia normativa corrigida

O catalogo gerado usa **schema 1.1.0**. `source_record` preserva o registro original, `source_execution_class` preserva a classificacao anterior a esta correcao, e `execution_class` passa a representar a classe efetiva apos as politicas vigentes. `normative_reason`, `normative_source` e `normative_source_sha256` explicam e rastreiam cada override.

Existem **41 bloqueios explicitos originais** e **50 bloqueios efetivos**. Nove classificacoes historicas foram revogadas por requisitos mais recentes:

| ID | Classe importada anterior | Classe efetiva | Motivo |
| --- | --- | --- | --- |
| CPU-PBO-OC | C_MANUAL | X_BLOCKED | OC, undervolt e alteracao de tensao fora do escopo de executores |
| GPU-OC-UV | C_MANUAL | X_BLOCKED | OC/undervolt de GPU proibidos pelo contrato atual |
| GPU-NV-PERFLIMIT | C_MANUAL | X_BLOCKED | Alias de power-limit/OC; diagnostico original permanece em referencia |
| STOR-SSD-FIRMWARE | C_MANUAL | X_BLOCKED | Escrita/flash de firmware sem executor e reversao permitidos |
| INPUT-FIRMWARE | C_MANUAL | X_BLOCKED | Escrita/flash de firmware fora dos executores |
| MSI-MODE | C_MANUAL | X_BLOCKED | Alteracoes MSI/IRQ bloqueadas |
| SEC-HVCI | C_MANUAL | X_BLOCKED | Desativacao de VBS/HVCI revogada; apenas diagnostico permitido |
| GPU-003 | D_LAB_ONLY | X_BLOCKED | Alteracao de power limit/limites termicos fora dos executores |
| GPU-004 | D_LAB_ONLY | X_BLOCKED | Clock lock/OC fora dos executores |

As fontes normativas sao `10_MODO_AVANCADO_SEGURO/01_MATRIZ_POLITICAS_AVANCADAS_SEGURAS.json` e `04_PROMPT_PARA_IA/PROMPT_ATIVO_GOAT_TWEAKS.txt`, com hashes registrados nos nove itens. A regra foi aplicada por IDs revisados, sem busca generica por palavras: por exemplo, `TOOL-AFTERBURNER` descreve monitoramento, `MEM-XMP` descreve status somente leitura e `SECURITY-VBS-STATUS-ONLY` permanece diagnostico. Referencias historicas foram preservadas, sem autorizar seus procedimentos revogados.

Todos os **344 registros** continuam `SPEC_ONLY_NOT_YET_VERIFIED`, `apply_allowed=false` e `auto_apply_allowed=false`. Nenhuma classe de catalogo cria um executor ou libera uma mutacao. Os 41 bloqueios originais continuam em `explicitly_blocked`/`original_explicitly_blocked`; os 50 efetivos ficam em `effective_blocked`, e os nove overrides em `normative_overrides` no JSON de auditoria.

## Correcoes concretas no importador

- `AuditRoot`, assim como `OutputRoot`, deve ficar fora do pacote fonte; o caminho de auditoria antes podia sobrescrever a fonte.
- Caminhos absolutos/traversal e entradas duplicadas no manifesto sao rejeitados. Arquivos nao manifestados nao entram no corpus incorporado.
- Falha de hash interrompe a geracao do catalogo. O diagnostico de integridade e preservado separadamente.
- As geracoes diferentes de catalogo continuam aceitando campos opcionais ausentes, inclusive quando o chamador usa strict mode.

## Correcoes concretas no inventario

- Valores de seguranca nao binarios deixam de virar `true` por conversao de string: ficam desconhecidos. O app continua somente leitura.
- Nucleos/threads e memoria instalada nao exibem um total parcial como se cobrisse todos os sockets/modulos quando faltam capacidades.
- Contadores invalidos de CPU por thread, commit e telemetria de armazenamento permanecem desconhecidos. Zero valido continua zero; NaN e infinito nao viram medidas.
- Um valor vazio de operacoes de renomeacao nao cria um falso reinicio pendente. Falha de leitura de flags conhecidas continua conservando estado desconhecido.
- Um provedor CIM que devolve objetos sem os campos solicitados e identificado como parcial. Excecoes sao registradas por tipo, sem publicar a mensagem bruta que poderia conter caminhos/dados privados.
- GPU retornando `UNAVAILABLE` sem lancar excecao tambem torna o inventario completo parcial. Nao se soma motores de GPU em carga total; manutencao de driver continua bloqueada por padrao.

O inventario nao coleta comandos de inicializacao/processos, credenciais, serial, MAC, IP ou identificacao de cliente. A verificacao real desta revisao publicou somente contagens/estados; nao foi gravado inventario pessoal no repositorio.

## Evidencia executada

`tests/Test-Catalog.ps1` passou com **3.322 verificacoes**, e `tests/Test-Inventory.ps1` com **45 verificacoes**, em Windows PowerShell 5.1 e PowerShell 7. Os testes novos abrangem precedencia normativa, preservacao de classes/fontes, protecao do pacote fonte, manifestos adulterados/duplicados, arquivos nao manifestados, flags invalidas, totais incompletos, campos CIM ausentes e GPU sem resultado confiavel. Os testes usam fixtures e arquivos temporarios proprios; nao alteram preferencias reais do Windows.

O importador foi executado novamente em Windows PowerShell 5.1 com **83/81/344/64** confirmados. Um smoke real somente leitura concluiu com **12 consultas base**, GPU identificada, memoria e motores GPU disponiveis; SMART permaneceu indisponivel. O contador CPU esteve indisponivel em uma passagem e disponivel na consulta seguinte, demonstrando por que uma falha transitoria deve continuar como desconhecida. O total GPU permaneceu nulo. Nenhuma preferencia, driver ou configuracao de sistema foi alterada.

Testes de fixtures e a leitura observada nao certificam toda combinacao Windows/GPU, sensores, ganhos em jogos ou rollback real. Windows 11, AMD/Intel fisicos e mutacoes em sistemas descartaveis exigem validacao separada antes de liberar esses recursos. Os bloqueios normativos sao intencionais e nao constituem pendencia a ser removida para chamar esta versao de oficial.
