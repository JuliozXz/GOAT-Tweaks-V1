# Centro de energia — planos existentes do Windows

O módulo `src/Power.ps1` permite consultar planos de energia e ativar um plano **já existente**, mediante revisão e consentimento. A implementação usa a interface pública `powercfg.exe` do Windows, com GUID completo, código de saída e confirmação independente do estado ativo.

Não são criados, duplicados, importados, excluídos, renomeados ou editados planos. O módulo não escreve Registro privado, configura drivers, desativa proteções ou reinicia o computador. A seleção aplica as políticas que o próprio plano já contém; isso pode modificar consumo, suspensão e gerenciamento de energia de dispositivos. Por esse motivo, mudanças ficam bloqueadas em atendimento remoto ou quando o contexto local é incerto.

## Operação

1. Consultar a lista de planos e o GUID ativo. Informações indisponíveis permanecem desconhecidas.
2. Selecionar um GUID que apareça na lista atual, incluindo planos personalizados/OEM.
3. Pré-visualizar GUID original e proposto, nome, requisitos e efeitos possíveis. A prévia é somente leitura.
4. Revisar energia, suspensão, uso de bateria e condições térmicas. Confirmar a seleção individualmente; não faz parte do lote automático.
5. Aplicar. Antes do comando, o módulo relê a seleção, confirma o plano com `/query`, grava e relê o journal durável e verifica novamente o contexto.
6. Confirmar o GUID efetivamente ativo por uma nova consulta. Um código de saída zero sem a mudança esperada resulta em falha e recuperação.
7. Para desfazer, selecionar a transação e confirmar a restauração. O alvo é o GUID original daquela transação, sem assumir um plano padrão.

O plano escolhido permanece no Windows depois de fechar ou remover o aplicativo, sem serviço GOAT necessário. Em notebook, autonomia, temperatura, ruído e desempenho podem variar. Não há promessa universal de FPS; a validação de desempenho exige medições comparáveis.

## Privilégios e proteção remota

As consultas `/list` e `/getactivescheme` não dependem do gate administrativo do aplicativo. Erros de acesso do Windows são informados, sem adivinhar a lista ou o plano ativo.

A implementação adota **administrador como requisito conservador para mutações**. A permissão real também depende das políticas e descritores de segurança do Windows; nem uma conta administrativa contorna uma negativa de política. Não há elevação silenciosa nem alteração desses descritores.

Para ativar ou restaurar um plano, o modo do atendimento precisa ser Local, o ambiente precisa identificar o console e não pode haver sinal de software remoto ou contexto incerto. O contexto é consultado novamente antes da mudança, inclusive antes de uma reversão que precisaria executar `/setactive`. A presença de software remoto é tratada de forma conservadora; ausência de processo conhecido não constitui prova universal de presença física.

Se o plano já está ativo, a operação devolve `NoOp`, confirma novamente o estado e não executa `/setactive`. Esse caso não exige elevar privilégios ou modificar uma sessão remota. O modo Demo usa planos explicitamente simulados e não executa nenhum comando `powercfg`, nem mesmo de leitura.

## Contrato das APIs

Carregar `Core.ps1` antes de `Power.ps1`. Os exemplos de consulta abaixo pressupõem uma sessão GOAT já aberta:

```powershell
Get-GoatPowerPlans                    # leitura real
Get-GoatPowerPlans -Demo              # exemplos; nenhum comando nativo
Get-GoatPowerPreview -Session $session -SchemeGuid $guid
Get-GoatPowerTransactions -Session $session
Get-GoatPowerTransactions -Session $session -IncludeRelated
```

| API | Contrato |
|---|---|
| `Get-GoatPowerPlans [-Demo]` | `Status`, `ReadOnly`, `ActiveSchemeGuid`, `Plans` com `Guid/Name/IsActive`, `Errors` e fonte |
| `Get-GoatPowerPreview -Session -SchemeGuid` | `SessionId`, `OriginalSchemeGuid`, `CurrentSchemeGuid`, `ProposedSchemeGuid`, `ProposedName`, `Changed`, `ExecutionAllowed`, `RequiresAdmin`, `RemoteOrUnknown`, `IsNotebook`, `Reasons`, `Tradeoffs`; sem mutação |
| `Invoke-GoatPowerChange -Session -SchemeGuid -Consent [-ReviewedPreview]` | Troca individual consentida; retorna `Applied`, `NoOp` ou `DEMO`; falhas são exceções e preservam o journal |
| `Restore-GoatPowerChange -Session -TransactionId -Consent` | Verifica identidade, ordem, existência do plano e estado atual antes de restaurar; permite recuperar uma sessão encerrada |
| `Get-GoatPowerTransactions -Session [-IncludeRelated] [-Identity]` | Journals tipados da sessão; opção de incluir sessões irmãs e grupos do pacote de recuperação |
| `Get-GoatPowerPendingTransactions -Session [-Identity]` | Pendentes em `Prepared`, `Applying`, `Restoring`, `RestoreFailed` ou `Conflict` |

A UI deve passar o objeto exibido em `-ReviewedPreview`: sob o mutex, sessão/original/proposto/delta precisam coincidir com a leitura nova. Uma prévia obsoleta ou de outra sessão exige nova revisão, mesmo se os GUIDs forem idênticos. Chamadores sem esse argumento continuam sujeitos a consentimento, leitura atual, contexto e demais gates.

## Journal e reversão

Os arquivos ficam em `Session.Root/power-transactions/ID.json`, separados dos journals de Registro. O schema 1 usa `Type=POWER_SCHEME`, ID da transação/sessão, identidade Machine/SID, horário, sequência, GUID original/proposto, SHA-256 do snapshot, estado, verificação e código de saída mais recente. Esses dados são privados e não devem ser publicados.

O SHA-256 protege a consistência do snapshot contra alterações detectáveis; não é assinatura de editor nem armazenamento inviolável contra o proprietário dos arquivos. `Write-GoatJson` grava de forma durável; o módulo reabre e valida o journal antes do primeiro comando de mudança.

Estados: `Prepared -> Applying -> Applied`; reversão: `Restoring -> Restored`. Falha de restauração fica `RestoreFailed`; interferência de outro plano pode ficar `Conflict`. Novas ações são bloqueadas enquanto houver estado pendente da mesma identidade. Uma transação nativa de Registro pendente também impede iniciar uma troca de energia.

Uma sequência monotônica calculada sob `Local\GOAT-Tweaks-Actions` preserva a ordem entre sessões irmãs e sessões relacionadas incluídas no pacote. O restaurador exige desfazer a mais recente antes da anterior. `RecoveryGroupRoot` e `related-sessions` permitem aplicar a mesma regra no pacote independente; o integrador de relatórios deve incluir os journals de energia e o módulo de restauração correspondente.

Se o estado já coincide com o GUID original, a reversão verifica a existência do plano e conclui sem outra ativação. Se o original foi removido, o aplicativo conserva o journal e informa a falha: não recria o plano, não escolhe outro GUID e não apaga evidências. Se o estado atual corresponde a um terceiro plano, a reversão não o sobrescreve; é necessária revisão manual. `RestoreFailed` pode ser tentado novamente quando o plano e um contexto local seguro estiverem disponíveis.

O mutex coordena operações GOAT na sessão Windows; não bloqueia Configurações do Windows, utilitários OEM ou outros programas. Há releituras antes/depois e proteção contra um terceiro estado observado. A interface pública não oferece comparação-e-troca atômica do plano ativo, portanto uma concorrência externa na pequena janela entre leitura e comando não é eliminada universalmente. Sessões em diretórios-raiz independentes, não incluídas no grupo conhecido, também não constituem um histórico global de todo o computador. Mantenha alterações de energia sob um único atendimento e preserve os journals.

## Validação e limites

`tests/Test-Power.ps1` substitui o provider nativo e a identidade por fixtures. Os testes abrangem lista localizada, GUID ativo/customizado/desconhecido, argumento inválido, prévia obsoleta, consentimento, administrador, contexto remoto, no-op, Demo, journal anterior à escrita, falha parcial, timeout, saída zero sem mudança, reversão falha, remoção do original, interferência externa, ordem entre sessões, recuperação de interrupção, identidade/tamper e falha de gravação.

`tests/Test-ReportsPower.ps1` exporta os journals e executa o restaurador incorporado em processos Windows PowerShell 5.1 separados, com provedores simulados persistidos somente em arquivos temporários. Valida a cadeia entre sessões, recusa da ordem incorreta, SID diferente, journals de trabalho ausentes, corrupção do manifesto e finalização com pendências. Confirma que as cópias originais do pacote, seu script e os journals da aplicação permanecem imutáveis. A restauração de trabalho fica apenas em `private-recovery/runtime`; a listagem não cria essa área. Ambos os testes também foram executados a partir do PowerShell 7, mantendo o restaurador independente no PS5.1.

Nenhum `/setactive` real foi executado para esses testes. Isso deve permanecer explícito na matriz de validação: fixtures de falha não certificam todas as combinações de hardware/OEM, suspensão, políticas corporativas ou o custo térmico de um plano. A leitura real e qualquer validação futura de aplicação devem registrar ambiente e resultado separadamente.

## Fontes primárias

Microsoft documenta `/list`, `/getactivescheme`, `/query` e `/setactive` na [referência de opções powercfg](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options). As opções de criação/exclusão não fazem parte da allow-list desta implementação; a escolha de um plano é uma operação distinta de editar seus valores.

A [referência PowerSetActiveScheme](https://learn.microsoft.com/en-us/windows/win32/api/powersetting/nf-powersetting-powersetactivescheme) descreve a ativação para o usuário atual e o retorno de sucesso/falha. A aplicação usa a CLI pública e confirma seu efeito com nova leitura, conservando erros de política em vez de contorná-los. O controle de acesso a ações como `ActionSetActive` consta na mesma documentação `powercfg`.
