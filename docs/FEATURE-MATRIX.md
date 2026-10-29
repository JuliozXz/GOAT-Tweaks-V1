# Matriz funcional — GOAT Tweaks 7.4.1

O aplicativo reúne diagnóstico, catálogo, referências, perfis consultivos, medições importadas, transações e relatórios. As 18 páginas reúnem diagnóstico, execução e procedimentos assistidos. Há **16 executores de Registro**, **seleção de plano de energia existente** e um guia adicional de animações; cada operação declara seu escopo.

| Página | Disponível | Limite |
| --- | --- | --- |
| Visão geral | Windows/CPU/GPU/RAM e hipóteses com fonte | Inventário não mede FPS ou input lag |
| Atendimento | Sessão, objetivo, modo local/remoto, consentimento e retomada | Inventário fica em memória sem autorização de persistência |
| Catálogo completo | 344 registros, riscos, texto original e associações específicas a executores | Inclusão documental não autoriza comandos; somente executores fixos no código alteram o sistema |
| Windows / preferências | 16 preferências/políticas de Registro; prévia, aplicação e restauração | Gates de build, edição, elevação, contexto e gerenciamento; no máximo sete ações A por lote |
| Energia | Planos existentes, GUID ativo, prévia e seleção/reversão | Exige administração e contexto local para mudanças; não cria, exclui ou edita planos |
| Procedimentos avançados | Guias por capacidade e pré-requisitos; registro explicitamente manual | Não automatiza etapas; confirmação não comprova execução ou ganho |
| CPU / RAM | Topologia, memória e contadores; seleção de plano no fluxo correspondente | Sem OC, afinidade/prioridade universal ou limpeza de RAM |
| GPU CENTER | PCI/PnP, driver, OEM, monitores, guias e motores GPU disponíveis | Sem instalação/remoção de driver ou sensores inventados; AdapterRAM não comprova VRAM |
| Jogos / perfis | Jogo, caminho autorizado, GPU, resolução/Hz e conflitos Reflex/VRR/V-Sync/cap/captura | Hipóteses locais; não escreve perfis privados de driver ou arquivos dos jogos |
| Steam / Discord / OBS | Instalações detectadas e procedimentos assistidos | Sem adaptadores de escrita ou execução de instaladores |
| Rede / latência | Adaptadores e velocidade de link reportada | Sem RTT/jitter/perda/bufferbloat medidos ou mudanças DNS/MTU/IPv6 |
| Armazenamento | Espaço e metadados; confiabilidade quando disponível | Sem garantia de SMART completo, benchmark de escrita ou alteração de cache |
| Inicialização / apps | Entradas e metadados minimizados | Sem desativação em massa, winget ou encerramento de aplicativos |
| Benchmarks | CSV, snapshot/hash exato, FPS médio, 1% low, p50/p95/p99 e comparação | Captura externa; sem ETW/injeção/overlay ou inferência de input lag |
| Histórico / reversão | Eventos, journals e restauração por identidade, alvo e ordem | Drivers e guias manuais têm recuperação separada; divergência externa requer revisão |
| Relatórios | HTML/JSON/CSV, projeção minimizada e recuperação privada validada | Não publica dados nem comprova ganho; preservar a pasta privada |
| Documentação | 64 documentos completos, origem/hash e busca | Texto somente leitura, sem avaliar prompts ou comandos |
| Laboratório / procedimentos | Itens avançados, guias e razões de elegibilidade | Estar no catálogo não cria um executor de OC, BIOS, driver ou segurança |

## Executores de Registro

Todos usam alvo fixo, Registry64, snapshot exato, hash, journal anterior à escrita, read-back e rollback. On e Off são escolhas distintas; **Restaurar original** recupera o valor capturado, inclusive ausência. Valores já configurados geram no-op sem nova escrita.

| ID | Preferência/política | Plataforma e classe |
| --- | --- | --- |
| explorer-show-extensions | Mostrar extensões conhecidas | HKCU, Windows 10/11, A |
| explorer-show-hidden | Mostrar ocultos sem expor arquivos protegidos do sistema | HKCU, Windows 10/11, A |
| explorer-show-infotips | Dicas textuais | HKCU, Windows 10/11, A |
| explorer-color-compressed | Cor de arquivos compactados/criptografados | HKCU, Windows 10/11, A |
| explorer-folder-size-tips | Tamanho nas dicas de pastas | HKCU, Windows 10/11, A |
| explorer-full-title-path | Caminho no título do Explorer | HKCU, Windows 10/11, A |
| explorer-separate-process | Preferência de janelas em processo separado | HKCU, Windows 10/11, B individual; console local |
| ui-transparency | Preferência de transparência | HKCU, Windows 10/11, A |
| ui-apps-light-theme | Tema claro/escuro de aplicativos compatíveis | HKCU, Windows 10/11, A |
| ui-system-light-theme | Tema claro/escuro do Windows | HKCU, Windows 10/11, A |
| ui-titlebar-accent | Destaque em títulos/bordas | HKCU, Windows 10/11, A |
| ui-auto-accent | Escolha automática da cor | HKCU, Windows 10/11, A |
| gaming-game-mode | Preferência AutoGameModeEnabled | HKCU, Windows 11, B individual |
| gaming-controller-gamebar | Atalho do controle para Game Bar | HKCU, Windows 11, B individual |
| capture-recording-policy | Política AllowGameDVR | HKLM, Windows 10 desktop/build 19041–19045, edição compatível, administrador, B individual; console local e gerenciamento não detectado |
| explorer-confirm-delete | Confirmação ao enviar arquivos à Lixeira | HKCU, Windows 11, edição compatível, B individual; gerenciamento não detectado |

**A:** preferência de baixo risco, selecionada e consentida; lote de até sete. **B:** mudança com trade-off, aprovada pelo ID exato e executada sozinha. Máquinas gerenciadas ou edições desconhecidas não passam pelo gate das duas políticas. Windows Server, arquitetura/processo incompatíveis e build desconhecido não passam pelo gate de aplicação real. Esses gates não certificam hardware.

Os alvos do Explorer têm referência em [MS-GPPREF](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-gppref/3c837e92-016e-4148-86e5-b4f0381a757f). A referência de [configurações comuns](https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-common#personalization---colors) identifica o armazenamento de temas e transparência; a de [Windows 11](https://learn.microsoft.com/en-us/windows/apps/develop/settings/settings-windows-11#gaming-game-bar-game-mode-gaming-shortcuts) identifica as preferências de jogos. Confirmação de exclusão está mapeada em [ADMX_WindowsExplorer](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-admx-windowsexplorer#confirmfiledelete).

**Read-back confirma a preferência persistida, não o estado efetivo do recurso.** O Windows pode exigir nova sessão, reabertura ou ter política sobreposta. Nenhum processo é encerrado e nenhum reinício é imposto. A Microsoft limita o efeito documentado de [AllowGameDVR](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-applicationmanagement#allowgamedvr) ao Windows 10 desktop; no Windows 11 a captura fica assistida. O atalho do controle não equivale a desativar captura.

ui-taskbar-animations-guide é **manual**, inclusive em Demo. A opção é explicada pela [interface de efeitos visuais](https://support.microsoft.com/en-us/accessibility/windows/make-it-easier-to-focus-on-tasks); nenhuma chave privada TaskbarAnimations é escrita como API universal.

## Energia e recuperação

power-select-existing inventaria planos e GUID ativo com powercfg; só ativa um GUID existente após prévia e consentimento. Exige administração e console local para mudanças, informa trade-offs de bateria/calor e verifica o GUID após o comando. Não cria, exclui nem edita planos. Falhas/conflitos preservam o journal; a restauração exige o GUID original existente e estado compatível. Demo não chama powercfg /setactive.

Pendências de Registro e energia impedem novas aplicações no outro motor. Finalização revisa pendências, exporta e valida a recuperação antes de encerrar a sessão. O pacote preserva snapshots originais e usa journals de trabalho separados na recuperação, mantendo a ordem entre sessões. Dados pessoais necessários à recuperação ficam no pacote privado.

## Cobertura e validação

- 344 IDs documentais: 246 centrais + 73 complementos + 25 GPU. Os 66 registros de new_controls já estão nos 246 e não são somados novamente.
- Estados, motivos e textos originais são preservados como proveniência. Associação a executor cobre somente a operação específica listada; não valida todas as instruções do registro.
- Os 16 executores passaram por fixtures de aplicação, falha, read-back e restauração. A API real de tipos foi testada somente em HKCU\Software\GOAT-Tweaks-Tests\GUID, chave própria descartável; preferências reais do Windows não foram alteradas nesses testes.
- Energia usa fixtures de powercfg. A UI usa Demo; inventário real é somente leitura. Isso não equivale a ensaios completos em VM, validação de todos os builds/edições ou cobertura física NVIDIA/AMD/Intel.
- IMPLEMENTED_AND_TESTED nos executores é acompanhado de ValidationScope. Nenhum ganho de FPS ou estado efetivo é deduzido do sucesso de uma escrita.

Continuam sem executor automático: OC/undervolt/firmware, HPET/MSI/BCD, remoção de driver/DDU, desativação de proteções, stress, ETW/overlay, sensores sem provedor e escrita privada de painéis GPU/Steam/Discord/OBS. Registros e guias continuam consultáveis. O pacote não tem assinatura Authenticode de editor nem certificação universal.
