# Procedimentos avancados assistidos

Por solicitacao expressa do operador, os **50 IDs classificados como X_BLOCKED no catalogo documental** agora possuem mapeamento individual em `src/AdvancedGuides.ps1`. Eles permanecem visiveis como guia manual ou como procedimento nao suportado, com o motivo concreto. O JSON original e o `source_record` nao foram alterados.

`MANUAL_GUIDE` significa que o app implementa um roteiro de atendimento: identificar o estado, consultar a fonte, abrir uma pagina permitida quando disponivel, revisar o procedimento e registrar verificacao/recuperacao. Nao significa que o app aplicou o tweak. `UNSUPPORTED` significa que o parametro, capacidade ou procedimento solicitado nao foi confirmado, ou que seria bypass. Nesses casos nao ha botao de configuracao enganoso.

Todos os objetos retornam `CanAutomate=false`, `CanApply=false` e `CanMutate=false`. Nenhuma funcao deste modulo executa comandos de sistema, inicia utilitarios, consulta CIM, baixa arquivos ou grava configuracoes. Comandos presentes nos passos sao texto para execucao consciente e manual fora desse modulo. O fluxo nao oferece bypass de assinatura, TrustedInstaller hijack ou execucao irrestrita.

## Contrato para a interface

```powershell
$guides = Get-GoatAdvancedGuides -Catalog $catalog.controls -Inventory $inventory

# As duas confirmacoes apenas indicam prontidao assistida em contexto remoto.
# Nao habilitam aplicacao automatica ou iniciam manutencao.
$guides = Get-GoatAdvancedGuides -Catalog $catalog.controls -Inventory $inventory `
    -LocalOperatorConfirmed -RecoveryPlanConfirmed
```

Cada item contem `Id`, `Title`, `Status`, `Risk`, `Mode`, `Reason`, `Steps`, `Recovery`, `Sources`, `SettingsUri`, `CanOpenSettings`, `AvailableManual`, `State`, `Before`, `ExpectedEffect` e `Prerequisites`. A classe original continua em `OriginalExecutionClass`/`SourceExecutionClass`; o modo efetivo do procedimento assistido e `C_MANUAL`. Esse modo nao altera os gates da engine nativa.

`State.Known` so fica verdadeiro quando existe valor no inventario real; false e zero validos sao preservados. Em Demo o estado e `DEMO_NOT_QUERIED`, mesmo se houver valores de exemplo. Para HVCI, o campo indicado e estado **configurado**, nao comprovacao de que a protecao ja esteja efetiva depois do reinicio.

Compatibilidade de fabricante nao e inferida apenas pelo titulo do controle. Um procedimento NVIDIA exige GPU NVIDIA identificada; AMD e Intel seguem a mesma regra. Procedimentos de tuning/firmware ainda exigem uma capacidade explicitamente confirmada como booleano verdadeiro em `Inventory.Capabilities` ou `Inventory.GpuCenter.Capabilities`. Ausencia, `UNKNOWN` e a string `true` nao comprovam suporte.

O indicador `Prerequisites.MaintenanceReady` permanece falso em remoto/incerto sem pessoa local e plano de recuperacao confirmados. O roteiro pode continuar disponivel para leitura documental, mas a interface deve mostrar essa condicao antes de manutencao de video, driver, input, boot ou rede. Backup, energia, elevacao e reinicio sao pre-requisitos especificados; nunca acoes automaticas deste modulo. DDU/driver grafico continua no fluxo assistido do GPU Center, sem DDU em lote ou reinicio automatico.

## Cobertura individual

| ID | Procedimento concreto e limite |
| --- | --- |
| WIN-EXPERIMENTAL | Identificar feature, namespace/build e documentacao. Rotulo indefinido permanece nao suportado. |
| WIN-HUNG | Identificar app travado, trabalho nao salvo e evento; fechamento/reabertura manual, sem reduzir timeouts como ganho de desempenho. |
| CPU-SMT | Conferir manual OEM e opcao SMT/HT do modelo; sem controle de firmware confirmado fica nao suportado. |
| CPU-CSTATES | Revisar consumo/energia e documentacao OEM; nao criar chave Windows para C-states de firmware. |
| CPU-PBO-OC | Conferir suporte Ryzen Master/Intel XTU, perfil original e recuperacao; ajuste externo so com capacidade confirmada. |
| PWR-MODERN | Consultar manualmente `powercfg /a`, revisar suspensao e OEM; nao converter S0/S3 por receita de Registry. |
| PWR-SLEEPSTUDY | Confirmar Modern Standby e gerar relatorio SleepStudy manualmente em pasta autorizada; nao desativar diagnostico. |
| MEM-COMPRESSION | Ler `Get-MMAgent`; consultar os parametros oficiais antes de eventual teste manual de MemoryCompression e restaurar o estado original. |
| MEM-STANDBY | Observar commit/cache por Gerenciador de Tarefas/RAMMap; cache purgado nao tem rollback exato. |
| MEM-RAM-ERROR | Executar Diagnostico de Memoria apenas no reinicio combinado e consultar resultados; manter evidencias. |
| MEM-SVCHOST | Identificar servicos/consumo e revisar service-host grouping; nao fixar threshold global para reduzir contagem de processos. |
| STOR-SSD-FIRMWARE | Identificar modelo/revisao/imagem OEM, energia, backup e recuperacao; sem suporte confirmado nao ha procedimento aplicavel de flash. |
| STOR-NVME-DRIVER | Conferir controlador/driver no Gerenciador de Dispositivos e pacote OEM; manutencao local e recuperacao de boot separadas. |
| STOR-IOLATENCY | Identificar parametro/documentacao exatos; IoLatencyCap generico permanece nao suportado. |
| GPU-NV-HDCP | Consultar View HDCP Status no painel NVIDIA para o monitor correto, quando a pagina existir. |
| GPU-NV-DMA | Revisar protecao DMA no Windows, sem interpretar nome ambiguo como chave NVIDIA privada. |
| GPU-NV-THERMAL | Diagnosticar sensores/refrigeracao e parar carga instavel; nao remover protecao termica. |
| GPU-NV-PERFLIMIT | Separar diagnostico PerfCap de power-limit; exige suporte confirmado antes de roteiro de tuning externo. |
| GPU-AMD-POWERGATE | Revisar campos documentados do Adrenalin; nao forcar tensao/gating privado. |
| GPU-AMD-SPREAD | Consultar OEM para significado e suporte; sem controle publico confirmado fica nao suportado. |
| GPU-INTEL-ENERGY | Identificar driver/OEM e opcoes reais; MC6/energy-driver generico nao e receita aplicavel. |
| GPU-OC-UV | Conferir GPU e ferramenta suportada, perfil original e limites; nao existe offset universal ou flash pelo app. |
| GPU-DMA | Registrar estado Kernel DMA Protection reportado; corrigir incompatibilidade com OEM. |
| NET-NAGLE | Confirmar TCP e opcao documentada por aplicativo; nao aplicar TcpAckFrequency a todos os adaptadores. |
| NET-NODELAY | Revisar TCP_NODELAY do aplicativo/socket real; sem chave inventada por nome de jogo. |
| NET-IPV6 | Diagnosticar interfaces/rotas e dependencia VPN; preservar conectividade e seguir caso documentado. |
| NET-NEIGHBOR | Consultar interfaces/vizinhos e topologia multihomed; administrador revisa weak-host apenas para problema especifico. |
| NET-QOS-RESERVED | Conferir politica aplicada e gargalo; zero de largura reservavel nao cria banda contratada. |
| TIMER-BCDEDIT | Consultar BCD e documentacao de depuracao; sem `/set`, reinicio ou defaults supostos pelo app. |
| TIMER-HPET | Revisar dispositivo/flags e metodologia; sem toggle HPET ou equivalencia timer/input lag. |
| INPUT-FIRMWARE | Identificar periferico/revisao, utilitario OEM e input alternativo; nenhum flash universal. |
| MSI-MODE | Confirmar hardware ID/driver e suporte INF do fabricante; exemplo de driver nao autoriza escrever MSISupported em massa. |
| SEC-HVCI | Abrir Seguranca do dispositivo/Isolamento do nucleo, registrar escolha e verificar apos reinicio combinado. |
| SEC-DEFENDER | Revisar protecao/historico e configuracoes oficiais; sem exclusao ampla ou bypass de Tamper Protection. |
| SEC-FIREWALL | Revisar perfil e regra estreita de aplicativo identificado; preservar perfis e acesso remoto. |
| SEC-DMA | Consultar protecao DMA reportada e compatibilidade; nao desativar como preset. |
| SEC-BOOT | Revisar Secure Boot/driver assinado e recuperacao privada; nenhum bypass de boot. |
| TOOL-ISLC | Avaliar pressao/cache com RAMMap; nao instalar purga periodica/timer persistente. |
| WIN-POWERTHROTTLE | Revisar modo de energia e processo alvo; nao gravar PowerThrottlingOff global. |
| WIN-MMCSS | Revisar tarefa multimidia/documentacao e sintoma; nao tratar SystemResponsiveness=0 como escolha universal. |
| WIN-DATA-HOSTS | Usar privacidade oficial e revisar linhas especificas de hosts com backup local; sem lista opaca. |
| WIN-INVENTORY | Revisar Diagnostico e comentarios; identificar tarefa/publisher antes de qualquer manutencao externa. |
| GPU-VSYNCIDLE | Revisar sincronizacao oficial por jogo; VSyncIdleTimeout privado sem documentacao permanece nao suportado. |
| GPU-INTEL-ENERGY-BLOCK | Conferir driver/OEM e controle exposto; nao desligar driver ou inventar MC6. |
| GPU-003 | Revisar power-limit apenas em modelo/ferramenta com capacidade confirmada e perfil salvo. |
| GPU-004 | Revisar suporte de clock lock no modelo exato; nao presumir suporte GeForce. |
| DISK-004 | Inspecionar politica de cache do disco, backup e protecao de energia; nao desativar flush por promessa de FPS. |
| SEC-001 | Quatro revisoes separadas: Defender, HVCI, UAC e Update; sem desativacao em lote. |
| SEC-002 | Obter driver compativel assinado; bypass de assinatura permanece nao suportado. |
| SEC-003 | Usar elevacao/permissao normal e pacote confiavel; hijack/execucao irrestrita nao sao implementados. |

## Fontes e limites de verificacao

As URIs se limitam a uma lista exata de paginas `ms-settings:` documentadas pela [Microsoft](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings). Parametros, URLs de executaveis e esquemas arbitrarios sao rejeitados. Solicitar uma pagina nao comprova que a opcao esta exposta nessa build/hardware/politica.

O roteiro SleepStudy segue a ferramenta oficial de [diagnostico de Modern Standby](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/modern-standby-sleepstudy). Compressao usa as referencias [Enable-MMAgent](https://learn.microsoft.com/en-us/powershell/module/mmagent/enable-mmagent) e [Disable-MMAgent](https://learn.microsoft.com/en-us/powershell/module/mmagent/disable-mmagent?view=windowsserver2025-ps); a consulta e eventual mudanca sao manuais e limitadas ao campo escolhido.

HVCI, firewall e UAC usam os fluxos de [Seguranca do dispositivo](https://support.microsoft.com/en-us/windows/security/windows-security/device-security-in-the-windows-security-app), [firewall](https://support.microsoft.com/en-us/windows/security/windows-security/firewall-and-network-protection-in-the-windows-security-app) e [UAC](https://support.microsoft.com/en-gb/windows/security/user-account-control-settings). Nenhuma reducao de protecao e descrita como ganho de FPS. A referencia de [IPv6](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/configure-ipv6-in-windows) recomenda conservar seus componentes; o guia prioriza diagnostico e reconexao.

Tuning depende de opcoes realmente expostas e modelo suportado, conforme [AMD](https://www.amd.com/en/resources/support-articles/faqs/DH3-020.html), [Intel XTU](https://www.intel.com/content/www/us/en/support/articles/000006636.html) e [NVIDIA](https://www.nvidia.com/content/Control-Panel-Help/vLatest/en-us/mergedProjects/3D%20Settings/Manage_3D_Settings_%28reference%29.htm). O procedimento [HDCP NVIDIA](https://www.nvidia.com/content/Control-Panel-Help/vLatest/en-us/mergedProjects/Display/To_verify_if_your_system_is_HDCP-capable.htm) confirma capacidade do monitor, nao oferece remover DRM. Firmware exige imagem especifica OEM e suporte proprio de recuperacao, como explica a [documentacao Microsoft](https://learn.microsoft.com/en-us/windows-server/storage/update-firmware).

As fontes foram consultadas em 28/10/2026. O procedimento nao comprova ganhos, estabilidade de tuning ou rollback fisico. Um relatorio de Registry nao restaura driver, firmware, dados nao salvos ou cache descartado. Dump, relatorio SleepStudy e enderecos internos devem permanecer no destino privado autorizado.

`tests/Test-AdvancedGuides.ps1` passou em PowerShell 5.1 e 7 com **472 verificacoes**: todos os 50 IDs, fontes HTTPS oficiais, URI allowlist, gates de capacidade/fabricante/remoto, estado false/zero, Demo sem consultas, fonte preservada e ausencia de launch/escrita/reinicio. Na fixture Demo NVIDIA sao **32 guias disponiveis e 18 nao suportados**; disponibilidade real varia com inventario e capacidade confirmada. Nao foram aplicadas alteracoes no computador para criar ou testar este modulo.
