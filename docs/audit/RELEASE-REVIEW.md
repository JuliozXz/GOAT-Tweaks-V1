# Revisão documental e de release — GOAT Tweaks 7.3.0

> Registro histórico da versão 7.3.0. A ampliação autorizada pelo usuário está em [RELEASE-7.4.0-REVIEW.md](RELEASE-7.4.0-REVIEW.md); o escopo e os critérios atuais estão na matriz funcional e na validação da versão atual.

Data de referência: 28/10/2026. Esta revisão confronta o pacote documental original, o código do aplicativo e fontes técnicas primárias. Nenhum arquivo do pacote original foi alterado e nenhum script upstream foi executado.

## Parecer e significado da versão oficial

A versão **7.3.0** identifica a distribuição oficial das funcionalidades que existem neste aplicativo: diagnóstico somente leitura, GPU Center, guias, perfis locais de orientação, análise de capturas importadas, catálogo/documentação, relatórios e fluxo de atendimento. O pedido humano de retirar a indicação de prévia não transforma as propostas documentais em executores aprovados.

Permanecem obrigatórios: aplicação real das duas preferências nativas bloqueada; catálogo consultivo sem execução; dados desconhecidos explícitos; drivers/DDU somente assistidos; ausência de OC, BIOS/UEFI, mudanças de segurança, MSI/HPET/BCD, reinício ou instalação silenciosa. Os 344 IDs documentados continuam diferentes de 344 ajustes implementados.

O pacote original exige uma matriz física e assinatura antes da sua definição completa de release para atendimento em clientes. Essa definição completa continua **não concluída**. Publicar o escopo funcional atual como 7.3.0 exige informar essa diferença, as plataformas efetivamente observadas, a ausência de assinatura e os testes pendentes; não permite declarar certificação universal, segurança de drivers ou ganho de FPS. A matriz em `../FEATURE-MATRIX.md` e a validação em `../VALIDATION.md` devem acompanhar a distribuição.

## Profundidade da leitura e deduplicação

O inventário integral do corpus está em `specification-import.json` e `package-integrity.json`: 83 arquivos, 18 JSON, um CSV e 64 documentos/textos incorporados, com 81 entradas não circulares do manifesto verificadas. Leitura de bytes, parsing e hashes foram distinguidos da interpretação semântica.

Foram lidos semanticamente os documentos das pastas 14/17/09/10/11, entrada e mapas da pasta 00, os dois masters da pasta 01, auditorias/prompt histórico da pasta 02, guias da pasta 07, integração da pasta 12 e relatórios/índice da pasta 13. Os documentos de aceitação, legenda do catálogo, licenças e precedência complementaram essa leitura. A revisão integral da especificação detalhada foi dividida entre revisores; `HISTORICAL-DETAIL-REVIEW.md` registra os 180 controles, 153 tópicos, linhas e as comparações de campos com o JSON histórico. A revisão de catálogo e normalização de políticas está em `CATALOG-RELEASE-REVIEW.md`.

O master V4 tem 728.569 caracteres após normalizar CRLF para LF. Uma busca ordinal pelo texto integral, sem reescrever os originais, comprovou estas incorporações exatas:

| Arquivo repetido dentro do master V4 | Offset inicial de caractere, base zero | Caracteres incorporados |
|---|---:|---:|
| `02_ESPECIFICACAO_E_AUDITORIA/01_AUDITORIA_CONSOLIDADA_V4.md` | 628 | 51.579 |
| `02_ESPECIFICACAO_E_AUDITORIA/04_IMPLEMENTACAO_DETALHADA.md` | 63.138 | 265.099 |
| `02_ESPECIFICACAO_E_AUDITORIA/02_INTEGRACAO_ULTIMATE_WINSUX_EXM.md` | 328.295 | 18.841 |
| `02_ESPECIFICACAO_E_AUDITORIA/03_ANALISE_EXM_SEM_BIOS.md` | 347.180 | 40.960 |
| `03_CATALOGOS_E_INVENTARIOS/01_CATALOGO_TECNICO_HISTORICO.json` | 397.464 | 316.165 |
| `03_CATALOGOS_E_INVENTARIOS/04_INVENTARIO_UPSTREAM.json` | 713.697 | 14.867 |

Esses seis conteúdos correspondem a 707.511 caracteres, ou 97,11% do master. Os 21.058 caracteres restantes foram lidos integralmente, incluindo as instruções V2/V3, perfis, exceções de segurança, entregáveis e licenças. A revisão dos anexos acima também cobre suas cópias no master; não se contou a repetição como uma segunda auditoria independente.

Os JSONs incorporados foram cruzados com os catálogos separados; os campos dos 180 controles e 153 tópicos da especificação detalhada não divergiram de seus correspondentes históricos. Os inventários de caminhos são metadados: revisar a lista de 108 arquivos Ultimate ou 135 entradas RESET EXPLODE não significa revisar ou executar o conteúdo de cada arquivo/binário upstream. Essa auditoria externa integral e testes de hardware não são alegados aqui. Prompts antigos preservados e checksums são referências; somente a precedência vigente pode orientar execução.

## Conflitos normativos resolvidos

| Tema | Conflito encontrado no histórico | Decisão vigente para o aplicativo |
|---|---|---|
| Fonte de instruções | Mapas/prompts antigos apresentam V4, V5, V6 ou V7.2 como ativos | Prompt unificado GPU + V7.3; pedido humano vigente prevalece para projeto novo e versão oficial |
| Security/Extreme Lab | V2–V4 admitiam desligar VBS/HVCI, Defender, UAC, firewall ou mitigações, mediante consentimento | O texto histórico não autoriza executores; controles de proteção permanecem bloqueados |
| OC/clock/power limit/firmware/MSI | Rótulos antigos `C_MANUAL`/`D_LAB_ONLY` podiam parecer uma permissão atual | Classe efetiva normalizada, com fonte e motivo; original preservado em `source_record` |
| Restauração | Alguns roteiros históricos falam em voltar para Normal, MTU/defaults ou reativar um recurso | Restaurar presença, tipo e dado originais; OFF não equivale a restaurar. As erratas por ID estão em `HISTORICAL-DETAIL-REVIEW.md` |
| Referência RESET EXPLODE | Reuso de `RestoreAll`, preferências por jogo e startup poderia descartar backups ou perder tipos | Motor próprio; não copiar limpeza de backup em falha, encerramento por nome ou purge de RAM como ganho |
| Contagens | 66 complementos declarados versus 73 registros reais; 66 centrais já repetidos em `settings` | 344 IDs únicos; não somar duplicatas como funções implementadas |
| Finalização | Remover o app poderia ser confundido com apagar rastros ou restaurar tudo | Exportar/verificar primeiro; conservar recuperação; não apagar Windows/terceiros nem desfazer silenciosamente ajustes persistentes |

Na normalização desta revisão há 41 bloqueios originais e 50 efetivos, com nove overrides rastreados. Todos os registros do catálogo mantêm `SPEC_ONLY_NOT_YET_VERIFIED`, `apply_allowed=false` e `auto_apply_allowed=false`. Nenhuma classificação documental cria um executor.

## Achados e correções desta revisão

### R1 — Captura analisada, hash e arquivo preservado podiam divergir

**Problema:** o importador lia o CSV para calcular métricas e abria novamente o caminho para calcular o hash; a UI copiava o arquivo numa terceira leitura. Se o produtor ainda gravasse ou substituísse a fonte, o relatório poderia ligar métricas de uma versão a bytes de outra.

**Correção implementada em `src/Benchmark.ps1`:** `Read-GoatFrameSource` abre a fonte uma vez, limita o tamanho pelo handle e usa `FileShare.Read`, recusando um escritor ativo. Texto, SHA-256 e snapshot derivam dos mesmos bytes. `Import-GoatFrameCapture -SnapshotPath` valida as amostras antes de persistir; grava um temporário próprio com handle exclusivo, executa `Flush(true)`, relê o hash pelo mesmo handle e só então move para o nome CSV final sem sobrescrever arquivos. Falha deixa um `.partial` identificado, sem declarar sucesso. A UI fornece o destino privado e não copia novamente a fonte. `Source.SnapshotFileName` contém somente o nome do snapshot.

**Evidência:** 66 verificações em PowerShell 5.1 e 7 para o módulo, incluindo fonte substituída imediatamente após a leitura, escritor ativo, colisão de destino, preservação de BOM, fonte inválida e falha de hash sem CSV final. O compartilhamento de handles é documentado em [FileShare](https://learn.microsoft.com/en-us/dotnet/api/system.io.fileshare?view=netframework-4.8.1); a descarga dos buffers em [FileStream.Flush](https://learn.microsoft.com/en-us/dotnet/api/system.io.filestream.flush?view=netframework-4.8.1). Esses mecanismos não substituem os testes de falha física de armazenamento pendentes.

### R2 — Recuperação exportada precisa continuar verificável depois do uso

**Problemas encontrados:** alterar o journal dentro da cópia exportada invalidaria seu manifesto; versões anteriores da finalização podiam exportar estado intermediário ou não retomar uma interrupção corretamente. A ordem entre transações de sessões diferentes também precisa sobreviver à remoção do app. Capturas copiadas precisam corresponder ao hash que fundamentou as métricas.

**Correções presentes no código revisado:** pacote exportado conserva snapshots imutáveis; o script de restauração usa journals de trabalho em `runtime`; sessões relacionadas mantêm seus IDs e ordenação; `Test-GoatExport` valida sessão/estado final, arquivos exigidos, tamanho e hashes; finalização persiste sua intenção antes da exportação e reconcilia a retomada. O destino de cada captura é relido e comparado ao SHA-256 registrado antes de aceitar a exportação. Exportação incompleta é preservada para diagnóstico, sem apagar a sessão original. Os testes específicos e o relatório de validação final devem permanecer junto do release.

### R3 — Classificação histórica não podia sugerir permissão vigente

**Problema:** alguns itens de OC, firmware, MSI ou proteção ainda exibiam classe manual/laboratório importada de uma geração antiga. O gate global já impedia sua execução, mas o texto efetivo era contraditório.

**Correção:** schema do catálogo separa a classe original da efetiva e registra `normative_reason`, fonte e hash dos overrides. `CATALOG-RELEASE-REVIEW.md` enumera os IDs. O conteúdo documental original continua íntegro e consultável.

### R4 — Zero, falso e totais parciais não podem substituir desconhecido

**Problema:** strings não binárias de segurança, campos CIM ausentes, sockets/módulos incompletos e falhas de providers poderiam produzir um estado excessivamente confiante.

**Correção:** leitura tipada conserva desconhecido/indisponível, marca o inventário como parcial e não soma motores como carga GPU total. `AdapterRAM` não vira VRAM confirmada: o campo WMI é `uint32`; a documentação também limita a confiabilidade de propriedades em hardware incompatível com WDDM. A conclusão sobre capacidade de memória decorre dessa limitação de representação, não de uma API que confirme VRAM. [Win32_VideoController](https://learn.microsoft.com/en-us/windows/win32/cimwin32prov/win32-videocontroller).

### R5 — Retirar o selo de prévia exige coerência de distribuição

**Critério de fechamento:** launcher, UI, relatórios, manifesto, ZIP e documentos de produto devem usar 7.3.0. Conteúdos históricos incorporados não devem sofrer substituição de texto para esconder referências antigas: isso alteraria o material original e sua proveniência. A lista funcional deve continuar separando execução, guia e requisito ainda não implementado. Hashes, testes e imagens precisam corresponder ao build final, e não ao bundle anterior.

**Assinatura:** o projeto não fornece certificado de editor nesta revisão. SHA-256 comprova correspondência do conteúdo com o digest esperado; não equivale a Authenticode, assinatura de editor ou certificação de segurança. [Get-FileHash](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.utility/get-filehash?view=powershell-5.1), [Get-AuthenticodeSignature](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.security/get-authenticodesignature?view=powershell-5.1).

### R6 — Persistência e retomada da sessão precisam respeitar autorização e estado

**Problemas encontrados:** salvar automaticamente o inventário visível antes de autorização contrariava a opção de registrar os dados localmente. Ler um `session.json` somente pelo ID/schema deixava contexto, coleções e finalização interrompida insuficientemente verificados.

**Correções presentes no código revisado:** `Save-GoatSession` persiste uma projeção sem `Inventory` enquanto `Consent` não for booleano verdadeiro, conservando a leitura apenas na memória da UI. `Import-GoatSession` limita tamanho, rejeita caminhos redirecionados, valida tipos/campos/contexto/modo, relê journals e usa o mutex de operações. Um estado `Finalizing` é reconciliado com o pacote exportado: finaliza somente com exportação válida ou reabre para revisão, preservando os arquivos. Exportação continua sendo uma ação explícita com destino escolhido, com projeção pública separada do pacote privado de recuperação.

## Abertura por uma linha PowerShell

`scripts/New-LaunchCommand.ps1` gera um comando com tag de versão e SHA-256 fixados no próprio texto. O download vai para um arquivo temporário único; o arquivo completo precisa conferir antes de `powershell.exe -STA -File` executá-lo. Não há `IWR|IEX`, avaliação de texto recebido pela rede ou alteração permanente da política de execução. O temporário é removido depois que o processo termina, preservando a pasta privada de sessões.

O `-ExecutionPolicy Bypass` usado no processo filho limita-se àquela invocação. Não deve ser convertido em `Set-ExecutionPolicy` global ou alegado como forma de contornar política corporativa: políticas de grupo têm precedência. Se a política efetiva impedir a execução, a falha deve permanecer visível. [about_Execution_Policies — Windows PowerShell 5.1](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies?view=powershell-5.1).

O comando público deve ser regenerado **depois** do build final. Trocar URL/tag/hash por `main` ou `latest` removeria a fixação desta versão. Não se deve publicar um comando cujo arquivo de release ainda não exista ou cujo digest pertença a outro build.

## Limites que permanecem explícitos

| Área | Situação e requisito restante |
|---|---|
| Preferências nativas | Gates reais continuam desabilitados. Antes de liberar: matriz descartável, aplicação/read-back/rollback reais, corrupção/interrupção e verificações de snapshot; fixtures não bastam |
| Windows/GPU físicos | Inventário observado em Windows 10/NVIDIA; Windows 11 e AMD/Intel físicos, híbridos/eGPU e matriz de monitor continuam pendentes |
| Métricas | Análise de CSV importado; não existe captura ETW/overlay ativo nem instrumento de input latency. O método de 1% low e percentis é declarado |
| Sensores | Temperatura/hotspot/potência/clocks/VRAM só quando existir provider validado; ausência não produz números fictícios |
| Benchmarks extensos | Importação e parsing executam em runspace separado, com cancelamento e prevenção de sobreposição testados na UI. A validação de carga com arquivos próximos ao limite de 100 MB continua pendente; nenhuma medição de carga foi inventada |
| Drivers e aplicativos externos | Sem instalador/DDU automático, escrita de perfis privados, adapters Steam/Discord/OBS ou instalação silenciosa |
| Auditoria e recuperação | Logs locais e hashes ajudam rastreabilidade; não são armazenamento inviolável contra o proprietário do Windows. Snapshots privados não devem ser publicados |
| Empacotamento | Release reproduzível por scripts, hash e origem versionada; assinatura de editor não fornecida |

As opções de timer/boot da documentação antiga não são otimizações universais. A Microsoft identifica opções relevantes de timer como depuração e alerta que mudanças de BCD podem impedir o funcionamento do sistema; o aplicativo não as executa. [BCDEdit /set](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set). O estado original de `REG_EXPAND_SZ` é lido sem expandir variáveis, conforme [RegistryValueOptions](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registryvalueoptions?view=netframework-4.8.1); restaurar deve preservar esse dado, não um default inferido.

## Fechamento da revisão

A revisão documental encontrou conflitos históricos e falhas concretas de integridade/recuperação; as correções acima não ampliam permissões de mutação. A oficialização do escopo atual depende da rodada final de build/testes, conferência do SHA-256/manifesto, revisão das notas e publicação do arquivo que o comando fixado referencia. Resultados finais devem ficar em `../validation-results.json` e `../VALIDATION.md`, sem somar a contagem de requisitos a testes ou funções implementadas.
