# Recomendações cruzadas e revisão técnica

A matriz [recommendations.json](../data/recommendations.json) contém **20 efeitos canônicos** e **56 referências** revisadas em 26 de outubro de 2026. Ela relaciona a leitura deste PC ao comportamento documentado dos projetos, sem executar seus scripts durante o diagnóstico. Não é uma votação entre otimizadores nem uma promessa de FPS, input lag ou compatibilidade universal.

As revisões correspondem ao catálogo local: Winutil `2f0bdc8f`, WinSux `91adbfd6`, Ultimate `a0a33a57` e RyTuneX `957885f5`. Cada referência de projeto aponta a um `ItemId` real e a um arquivo dessa revisão. Referências externas são documentação primária da Microsoft. Uma funcionalidade existir na interface não comprova benefício para o hardware detectado.

## Como interpretar o resultado

| Resultado | Significado |
| --- | --- |
| Configurado | A leitura conhecida corresponde ao alvo revisado. Não significa que o PC atingiu desempenho máximo. |
| Recomendado | Há um estado conhecido que difere do alvo e permite considerar uma ação específica. O técnico precisa revisar a justificativa e a carga. |
| Revisão manual | O efeito depende de firmware, driver, política, aplicação ou medição. Não existe um valor universal escolhido pelo scanner. |
| Indisponível | A consulta falhou, o dado não existe ou o Windows não permite comprová-lo. Ausência de dado não vira “desativado” nem autorização para corrigir. |

`ProbeKey` identifica o efeito. Referências repetidas são agrupadas nesse mesmo efeito para evitar aplicar o mesmo ajuste várias vezes. A matriz destaca divergências; duas regras com alvos incompatíveis devem perder a ação automática e exigir revisão. O estado é consultado novamente antes de uma alteração transacional.

Somente três ações nativas podem ser associadas pela matriz: compressão de memória, auto-tuning TCP do perfil Internet e RSS global. As demais áreas oferecem diagnóstico, justificativa e acesso à origem. A recomendação não executa automaticamente um programa externo nem transforma seus comandos em ações do GOAT.

## Evidência por área

| Efeito | Evidência revisada e decisão GOAT |
| --- | --- |
| Compressão de memória | O [Ultimate](https://github.com/FR33THYFR33THY/Ultimate/blob/a0a33a57078434201f582b0db5107dcbb502292a/3%20Setup/2%20Memory%20Compression.ps1) recomenda Off e oferece Enable; a [etapa dois do WinSux](https://github.com/FR33THYFR33THY/WinSux/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/steptwo.ps1) desativa a compressão. O GOAT permite considerar reativação quando `Get-MMAgent` comprova `False`, observando RAM, paginação e custo de CPU. Essa é uma decisão de engenharia, diferente da preferência desses autores. A [API Microsoft](https://learn.microsoft.com/en-us/powershell/module/mmagent/enable-mmagent) documenta o parâmetro; não garante ganho em jogos. |
| Cache de sistema/prefetch | O [RyTuneX](https://github.com/rayenghanmi/RyTuneX/blob/957885f53beaacfa7322581cafdb9eba5df5726a/Helpers/OptimizeSystemHelper.cs) oferece `LargeSystemCache=1` e desativação de prefetch. Não confundir esses recursos com compressão de RAM, cache de shaders ou compactação do sistema operacional. Revisão manual, sem recomendar valores apenas pelo tamanho da RAM. |
| Core parking | O [plano do Ultimate](https://github.com/FR33THYFR33THY/Ultimate/blob/a0a33a57078434201f582b0db5107dcbb502292a/6%20Windows/29%20Power%20Plan.ps1) usa disponibilidade de núcleos em 100%. A Microsoft documenta [CPMinCores](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/options-for-core-parking-cpmincores) e classes de eficiência. O valor lido é informação de política, não prova de gargalo. |
| Agendamento, afinidade e prioridade | Ultimate expõe escolhas por processo. WinSux usa `Win32PrioritySeparation=0x26`, enquanto RyTuneX oferece 42 e reversão para 2. Não escolher um “melhor” por popularidade: comparar frametimes e comportamento das outras aplicações. Prioridade Tempo real e afinidade fixa permanecem manuais. |
| MSI de GPU | O [Ultimate](https://github.com/FR33THYFR33THY/Ultimate/blob/a0a33a57078434201f582b0db5107dcbb502292a/5%20Graphics/10%20Msi%20Mode.ps1) escreve o valor para GPUs; a [documentação Microsoft](https://learn.microsoft.com/en-us/windows-hardware/drivers/kernel/enabling-message-signaled-interrupts-in-the-registry) descreve habilitação pelo driver. Ler `MSISupported` não comprova interrupção alocada em execução nem autoriza forçar MSI/High universalmente. |
| MSI de armazenamento | Cobertura limitada: o script MSI acima trata GPUs. Não foi atribuída aos projetos uma rotina universal que valide controladores NVMe/SATA. A referência Microsoft explica o mecanismo, sem substituir documentação do driver do controlador. |
| HAGS | RyTuneX e WinSux alteram `HwSchMode`; Ultimate abre as configurações gráficas. A [Microsoft](https://devblogs.microsoft.com/directx/hardware-accelerated-gpu-scheduling/) exige hardware e driver compatíveis. A chave e a build isoladas não comprovam suporte nem ganho. |
| ReBAR | O Ultimate oferece forçar perfis. [ReBAR](https://learn.microsoft.com/en-us/windows-hardware/drivers/display/resizable-bar-support) envolve firmware, GPU e driver. Sem consulta universal confiável neste scanner, mostrar limite de cobertura e orientar verificação no fabricante. |
| C-States | O guia de BIOS do Ultimate sugere mudanças condicionadas ao hardware; não lê o estado efetivo do firmware. Não deduzir C-States por nome de CPU ou plano de energia. |
| Timers/HPET/BCD | Ultimate e WinSux instalam serviço de timer; RyTuneX oferece opções de timer e BCD. A documentação de [BCDEdit](https://learn.microsoft.com/en-us/windows-hardware/drivers/devtest/bcdedit--set) classifica opções de clock/tick como depuração. Sem aplicação nativa automática. |
| Auto-tuning TCP | O alvo Normal vem de [documentação Microsoft](https://learn.microsoft.com/en-us/powershell/module/nettcpip/set-nettcpsetting), com alteração limitada ao perfil Internet. Não foi inventado apoio específico dos quatro projetos para esse mesmo efeito. Janela TCP/throughput não equivale a ping de jogo. |
| RSS | O [RyTuneX](https://github.com/rayenghanmi/RyTuneX/blob/957885f53beaacfa7322581cafdb9eba5df5726a/Views/NetworkPage.xaml.cs) oferece habilitação/desabilitação global. O GOAT considera habilitar se o estado conhecido for Disabled, com revisão de compatibilidade. Estado global não comprova uso por cada NIC. |
| QoS | Cobertura limitada para um ajuste uniforme entre os projetos. [Políticas QoS](https://learn.microsoft.com/en-us/windows-server/networking/technologies/qos/qos-policy-top) podem classificar e limitar tráfego; não justificam prometer uma porcentagem fixa de Internet “liberada”. QoS de rede e prioridade de CPU são conceitos distintos. |
| Energia do adaptador | O Ultimate escreve várias propriedades de energia/wake por Registro. A [orientação NDIS](https://learn.microsoft.com/en-us/windows-hardware/drivers/network/avoiding-ndis-power-management-problems) alerta para dependência do driver. EEE, Wake-on-LAN e offloads são recursos diferentes. Revisão por NIC; preservar bateria e Modern Standby. |
| Windows Update | Winutil contém rotinas de retorno ao padrão e de bloqueio; RyTuneX tem perfis Default/SecurityOnly/Manually/Disabled; Ultimate oferece bloqueios e pausas. A divergência fica explícita. Preservar segurança e planejar manutenção, sem bloqueio global para prometer FPS. |
| Serviços | Winutil seleciona serviços para Manual; outros fluxos desativam conjuntos maiores. O estado Running não comprova desperdício. Analisar função, dependências e uso pelo cliente antes de qualquer alteração. |
| AppX/UWP | Winutil e RyTuneX oferecem seleção; WinSux remove em massa com exceções. Pacote instalado não é prova de gargalo. Remoção exige recuperação própria; não cabe no desfazer de valores de Registro. |
| Limpeza de cache | Winutil apaga TEMP; RyTuneX possui categorias de limpeza; o Cleanup do Ultimate também pode apagar Windows.old e XboxGames. O técnico deve revisar escopo e dados. Limpeza pode forçar reconstrução de caches e não é melhoria permanente. |
| Explorer | Winutil oferece `FolderType=NotSpecified`; RyTuneX contém preferências e limpezas que reiniciam a shell. Relacionar ao sintoma de navegação, sem apresentar preferências cosméticas como ganho em jogos. |
| Drivers | Há utilitários, download de pacotes e fluxos DDU. Inventário não comprova que o driver esteja desatualizado ou defeituoso. Conferir dispositivo, versão, assinatura e origem; DDU/reinstalação pode reiniciar e não integra o desfazer GOAT. |

## Limites da comparação

Não há obrigação de atribuir todos os efeitos aos quatro projetos. Em particular, compressão de RAM não foi atribuída ao RyTuneX apenas porque ele contém cache/CompactOS; MSI de armazenamento e QoS receberam indicação de cobertura limitada. As fontes ligadas a uma regra demonstram o comportamento citado, não aprovação integral do projeto nem validação em todo hardware.

A matriz é embarcada e determinística. Um novo scan consulta apenas o computador; não baixa páginas, não consulta modelos externos e não executa código dos repositórios. Para incorporar alterações upstream, revise conteúdo, IDs, alvos e conflitos e publique uma nova matriz.

Aplicar uma das três ações nativas exige o fluxo normal do GOAT: administração, leitura confiável, proteção do sistema confirmada, diário dos valores anteriores e verificação após escrita. As demais ações dos programas originais continuam separadas e podem ter efeitos fora da reversão do GOAT. Nenhum dado desconhecido deve ser convertido em uma recomendação de mudança.
