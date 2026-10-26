# Referências técnicas e critérios de implementação

Consulta: 26 de outubro de 2026. Implementação própria em PowerShell/WPF. Além das funções nativas do GOAT, a versão 2.3 apresenta quatro bibliotecas com arquivos, recursos e releases dos projetos abaixo. Downloads e abertura de aplicativos ocorrem somente após ação do usuário, a partir da origem oficial e com verificação de integridade. Os programas externos executam em processos próprios; suas alterações não são cobertas pelo diário de reversão nativo do GOAT.

## Projetos citados na especificação

| Projeto | Referência aproveitada | Licença consultada |
| --- | --- | --- |
| [Chris Titus Tech Winutil](https://github.com/ChrisTitusTech/winutil) | Separação de ajustes, ferramentas, reparos e opções de reversão. | [MIT](https://github.com/ChrisTitusTech/winutil/blob/main/LICENSE) |
| [FR33THY WinSux](https://github.com/FR33THYFR33THY/WinSux) | Fluxo de atendimento técnico e organização das tarefas de Windows. | [MIT e avisos do autor](https://github.com/FR33THYFR33THY/WinSux/blob/main/LICENSE) |
| [FR33THY Ultimate](https://github.com/FR33THYFR33THY/Ultimate) | Separação entre verificação, instalação, GPU, hardware e ajustes avançados. | [MIT](https://github.com/FR33THYFR33THY/Ultimate/blob/main/LICENSE) |
| [RyTuneX](https://github.com/rayenghanmi/RyTuneX) | Classificação de riscos, diagnóstico por categoria e ajustes acompanhados de reversão. | [AGPL-3.0](https://github.com/rayenghanmi/RyTuneX/blob/main/LICENSE.md) |

Uma funcionalidade existir em outro otimizador não constitui evidência de melhoria universal de desempenho. A seleção dos ajustes precisa considerar suporte, estado atual e possibilidade de restaurar a configuração original.

## Fontes primárias para comportamento do Windows

| Tema | Evidência e decisão |
| --- | --- |
| Ponto de restauração | [Checkpoint-Computer](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/checkpoint-computer?view=powershell-5.1) não retorna objeto e, desde Windows 8, limita a criação a um ponto a cada 24 horas. Antes de um lote novo, consultar os pontos antes/depois e exigir novo número de sequência com descrição única. Sem comprovação, interromper a aplicação. Não modificar a política de frequência para contornar essa exigência. |
| Reversão | [System Restore](https://learn.microsoft.com/en-us/windows/win32/sr/restore-points) recupera estado do sistema e pode remover pontos antigos conforme o espaço disponível. Na reversão da mesma transação, o aplicativo verifica se o ponto original ainda existe e o reutiliza; se ausente, exige novo ponto confirmado. Isso mantém o desfazer disponível durante o limite de 24 horas. O diário também guarda valores/tipos originais de Registro, existência dos valores e configuração original dos comandos. Restaurar a última transação recupera esse estado capturado, não um conjunto suposto de “padrões do Windows”. |
| MSI | [Enabling Message-Signaled Interrupts](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/enabling-message-signaled-interrupts-in-the-registry) documenta a configuração pelo INF do driver e o valor `MSISupported`. Ler esse valor informa a configuração de Registro; não comprova quais interrupções o dispositivo efetivamente alocou em execução. Não forçar MSI em todo hardware a partir da marca/modelo. |
| Afinidade e prioridade | [Interrupt Affinity](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/interrupt-affinity-and-priority) recomenda a política padrão quando aplicável. Afinidade fixa e prioridade alta não devem ser recomendações universais. O valor ausente deve aparecer como indefinido, sem tratá-lo como defeito. |
| HAGS | [Hardware Accelerated GPU Scheduling](https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/) depende de GPU e driver que exponham o recurso. O número da versão do Windows, isoladamente, não prova suporte. A decisão exige validação do técnico e comparação da mesma carga antes/depois. |
| TCP | [TCP/IP performance known issues](https://learn.microsoft.com/en-us/troubleshoot/windows-server/networking/tcpip-performance-known-issues) documenta o nível Normal para habilitar a negociação de janela. O aplicativo usa [Set-NetTCPSetting](https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-nettcpsetting?view=windowsserver2025-ps) com `-SettingName Internet -AutoTuningLevelLocal`, limitando alteração e captura ao mesmo perfil. Isso preserva configurações diferentes nos outros perfis e não garante redução de latência de jogos. |
| Offloads de rede | [Network adapter performance tuning](https://learn.microsoft.com/en-us/windows-server/networking/technologies/network-subsystem/net-sub-performance-tuning-nics) explica que checksum offload, LSO e RSS normalmente são benéficos e dependem da carga e do adaptador. Essa documentação trata de Windows Server; não extrapolar seus ajustes específicos para todos os desktops. Offload e economia de energia são conceitos distintos. |
| CPU e energia | [Powercfg](https://learn.microsoft.com/en-us/windows-hardware/design/device-experiences/powercfg-command-line-options) fornece comandos para listar e ativar planos. Só ativar um plano existente e guardar seu GUID anterior. O nome do processador não comprova a configuração de C-states do firmware; a própria Microsoft explica que os estados expostos [podem variar conforme o fabricante](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/xperf/cpu-idle-states). |
| HPET e timers | [BCDEdit /set](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set) identifica opções como `useplatformclock`, `useplatformtick` e `disabledynamictick` como recursos de depuração. Não alterar o boot automaticamente para prometer FPS ou menor input lag. |
| Gravação de jogos | [AllowGameDVR](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-applicationmanagement#allowgamedvr) documenta a política de gravação/transmissão e sua aplicabilidade por edição. Desabilitá-la também remove uma função usada pelo cliente; apresentar essa consequência. Preferências HKCU difundidas em scripts comunitários não equivalem a uma API pública estável. |
| Modo Jogo | A documentação de [Game Mode](https://learn.microsoft.com/en-us/previous-versions/windows/desktop/gamemode/game-mode-portal) descreve integração do Windows e dos jogos. Detectar um processo conhecido não demonstra que esse jogo recebe tratamento especial do sistema. Exibir separadamente configuração, processo detectado e medições. |

## Critérios para revisão técnica

- Não deduzir gargalo, temperatura, DPC, latência de entrada, suporte a Resizable BAR ou configuração de BIOS a partir de nomes de componentes ou de uma única amostra de uso.
- Registrar falhas de consulta e apresentar “indisponível” quando o Windows ou o driver não fornecerem o dado.
- Pré-selecionar somente ajustes aplicáveis com efeito conhecido e reversão registrada. Ajustes que exigem validação manual devem permanecer desmarcados ou apenas informativos.
- Não remover automaticamente drivers, pacotes do sistema, serviços de segurança ou Windows Update. Limpeza de arquivos não deve prometer reversão por um diário de Registro.
- Não oferecer pontuação de desempenho ou ganho estimado sem metodologia, carga de teste e amostras reproduzíveis.
- O modo demonstração deve identificar dados simulados e não modificar configurações do computador.
- Preferências em `HKCU` pertencem à identidade que executa o PowerShell. Se o técnico elevar com credenciais de outra conta, essas preferências afetam essa outra conta. O diário identifica o SID e deve ser restaurado com a mesma identidade.

Esses critérios são decisões de engenharia do GOAT Tweaks, derivadas das fontes acima. Não representam certificação da Microsoft nem validação de bancada de todos os modelos de hardware.
