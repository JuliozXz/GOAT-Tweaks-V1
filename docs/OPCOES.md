# Opções nativas e comparação dos programas originais

O arquivo [native-options.json](../data/native-options.json) acrescenta **24 preferências específicas** às opções já implementadas. Os alvos foram extraídos das revisões fixadas de Winutil, WinSux, Ultimate e RyTuneX, isolando cada efeito. Não são funções upstream copiadas nem uma aplicação integral de seus presets.

Os nomes indicam o efeito ligado: por exemplo, **Extensões de arquivos** ativa a exibição de extensões, embora o Windows represente isso por `HideFileExt=0`. **Identificador de publicidade** ligado permite a preferência publicitária; desligado a restringe. Preferências de privacidade ficam sob decisão do cliente e não são pré-selecionadas como supostas melhorias de desempenho.

## Preferências disponíveis

| Opção | Ativar/aplicar | Desativar/padrão |
| --- | --- | --- |
| Extensões de arquivos no Explorer | Mostrar `.exe`, `.png`, etc. | Ocultar extensões conhecidas. |
| Arquivos ocultos no Explorer | Mostrar arquivos ocultos. | Ocultá-los; arquivos protegidos do sistema não são alterados. |
| Explorer abre em Este Computador | Definir esse destino inicial. | Remover a preferência e usar a escolha padrão do Windows. |
| Visualização compacta | Reduzir espaçamento no Explorer do Windows 11. | Usar o espaçamento normal. |
| Arquivos recentes | Mostrar a lista na página inicial do Explorer. | Ocultar a lista, sem apagar documentos. |
| Pastas frequentes | Mostrar a lista na página inicial do Explorer. | Ocultar a lista, sem remover pastas. |
| Detalhes na transferência | Preferir diálogo detalhado de cópia/movimentação. | Preferir diálogo simplificado. |
| Animações da barra de tarefas | Habilitar animações compatíveis no Windows 10. | Simplificar essa parte da interface. |
| Conteúdo da janela no arraste | Mostrar conteúdo enquanto arrasta. | Preferir contorno quando o aplicativo/compositor respeitar a opção. |
| Seleção translúcida | Exibir retângulo translúcido em áreas compatíveis. | Preferir seleção simples. |
| Sombras nos nomes dos ícones | Mostrar sombras nos rótulos da Área de Trabalho. | Remover essa preferência visual. |
| Abertura mais rápida dos menus | Usar 200 ms para menus clássicos. | Usar 400 ms, conforme o par revisado. |
| Espera para repetição do teclado | Usar o menor atraso de repetição do Windows. | Usar o outro valor revisado. Não altera o primeiro pressionamento. |
| Peek | Preferir prévia da Área de Trabalho no Windows 10. | Desativar a preferência de prévia. |
| Ícones centralizados | Centralizar a barra no Windows 11. | Alinhar à esquerda. |
| Sugestões de encaixe | Mostrar layouts ao passar sobre maximizar no Windows 11. | Ocultar esse painel. |
| Encerrar tarefa na barra | Mostrar o comando no Windows 11 23H2 ou superior. | Ocultar o comando. Habilitar não encerra nenhum processo. |
| Identificador publicitário | Permitir a preferência publicitária do usuário. | Restringir esse identificador. Não elimina todos os anúncios ou diagnósticos. |
| Experiências personalizadas | Permitir sugestões apoiadas em dados de diagnóstico. | Desativar somente essa preferência. |
| Histórico de inicialização de apps | Permitir personalização de listas a partir das inicializações. | Restringir essa preferência, sem bloquear apps. |
| Fala online | Permitir a preferência de reconhecimento online. | Restringi-la, podendo limitar recursos de voz. |
| Personalização de escrita/digitação | Permitir coleta implícita para aprendizado/sugestões. | Restringir a coleta correspondente. |
| P2P local de atualizações | Preferir modo LAN, valor 1. | Preferir HTTP sem pares, valor 0; Windows Update continua disponível. |
| Redução de sugestões de configuração | Suprimir convites para concluir a configuração. | Remover essa preferência e usar o padrão do Windows. |

As opções exclusivas do Windows 11 possuem limites mínimos de build. Peek e animações da barra estão limitados ao Windows 10 na matriz revisada. Isso evita apresentar preferências legadas como ajustes garantidos para a barra nova. Nenhuma dessas opções depende de suposição sobre marca de CPU/GPU, HPET, MSI, firmware ou versão do driver.

## Fontes e limites

- [Winutil: config/tweaks.json](https://github.com/ChrisTitusTech/winutil/blob/2f0bdc8fca52e1ebe31a8d98216428061d3f8956/config/tweaks.json): pares revisados de extensões, efeitos, menus, teclado, Peek e preferências individuais de privacidade.
- [RyTuneX: OptimizeSystemHelper.cs](https://github.com/rayenghanmi/RyTuneX/blob/957885f53beaacfa7322581cafdb9eba5df5726a/Helpers/OptimizeSystemHelper.cs): estados de Explorer, compactação visual, alinhamento, layouts, encerramento de tarefas e preferências do usuário.
- [WinSux: reg.reg](https://github.com/FR33THYFR33THY/WinSux/blob/91adbfd63b7ed2eb5fcf0821fd53405a3cf63573/WinSux/reg.reg): referência de desativação de animações; o arquivo inteiro não é importado.
- [Ultimate: Control Panel Settings](https://github.com/FR33THYFR33THY/Ultimate/blob/a0a33a57078434201f582b0db5107dcbb502292a/6%20Windows/22%20Control%20Panel%20Settings.ps1): pares de restrição de personalização de escrita e texto; outras alterações do script não são incorporadas.
- A documentação Microsoft de [Delivery Optimization](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-deliveryoptimization#dodownloadmode) define os modos HTTP/LAN. O GOAT usa a preferência local presente no helper revisado e não aplica um perfil de bloqueio de atualizações. Políticas de organização podem prevalecer.

Não foram adicionados bloqueios gerais de diagnósticos, segurança, atualizações ou serviços apenas para aumentar a contagem. Widgets, pesquisa web e outras preferências variáveis sem um par suficientemente delimitado nesta revisão permanecem nas interfaces originais para avaliação explícita. MinAnimate e transparência já pertencem à opção visual existente e não foram repetidos nestas 24 entradas.

## Seleção e reversão

Somente **animações da barra de tarefas** possui política automática nova: o scanner pode sugerir **desativar** em máquinas com pouca RAM, dentro da faixa de Windows 10 suportada. É uma simplificação visual, sem previsão de FPS. As outras 23 preferências são manuais; requisitos de privacidade, aparência e acessibilidade não devem ser decididos apenas pelo hardware.

O estado desligado é um valor revisado ou a remoção explícita da preferência quando o botão diz **Usar padrão**. Ele não significa recuperar o valor personalizado anterior do cliente. Para isso, use a restauração da transação, que guarda existência, tipo e valor originais antes da escrita. Uma preferência ausente ou personalizada pode aparecer como padrão/estado personalizado, sem inventar que está ligada ou desligada.

As mudanças podem exigir nova sessão, reinício ou um aplicativo compatível que respeite a preferência. Verificar o valor no Registro confirma a gravação, não substitui conferir o efeito visível e as políticas efetivas. O aplicativo não reinicia automaticamente a sessão para aplicar essas opções.

O catálogo dos programas originais continua separado. A comparação de ferramentas usa regras revisadas por item e não transforma todos os scripts, instaladores ou recursos internos em ajustes reversíveis do GOAT. Compatibilidade de fabricante/arquitetura não autoriza executar automaticamente presets amplos, DDU, mudanças de segurança, serviços ou boot.

## Comparação das ferramentas por PC

[tool-rules.json](../data/tool-rules.json) fornece **44 regras individuais** sobre itens reais dos quatro projetos. O comparador continua cobrindo todas as 1.330 linhas do catálogo: itens sem regra individual permanecem como referência ou revisão manual. Essa cobertura de listagem não equivale a certificação de todos os scripts e binários.

NVIDIA, Radeon/AMD e Intel gráfico são requisitos de GPU, separados da marca da CPU. Um processador Ryzen pode conviver com GPU NVIDIA; isso não torna a ferramenta NVIDIA inadequada por causa da CPU. Arquitetura explícita no nome/origem pode ser utilizada, mas ausência de metadados fica como **Unknown**, sem adivinhar pelo tamanho do arquivo ou fabricante.

As únicas sugestões automáticas novas de ferramentas são três launchers de diagnóstico revisados do Ultimate: consulta de espaço das unidades, conferência de RAM com CPU-Z e conferência de GPU com GPU-Z. O primeiro consulta volumes; os dois últimos baixam e abrem os programas de diagnóstico originais. Nenhum deles ativa perfis de memória, ReBAR ou ajustes de drivers. Recomendar um launcher não comprova todas as capacidades que o programa interno consegue inspecionar, nem autoriza iniciar testes de stress.

CPU-Z/GPU-Z oferecidos diretamente como binários permanecem em revisão quando sua arquitetura exata não foi comprovada. `Architecture=Any` nos launchers PowerShell descreve o script executado no host Windows atendido pelo GOAT, sem declarar a arquitetura PE desses downloads internos. Famílias de diagnóstico evitam sugerir equivalentes simultaneamente quando houver mais de uma alternativa validada.

Instaladores, perfis amplos, alterações de GPU, DDU, serviços, timers e overclock permanecem manuais. Mesmo uma ferramenta recomendada só abre após ação explícita do técnico e passa pelas verificações de integridade/proteção do fluxo externo. Não existe execução automática dos programas durante o scanner.
