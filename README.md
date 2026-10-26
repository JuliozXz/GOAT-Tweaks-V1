# GOAT Tweaks v2.4

Aplicativo desktop para a bancada técnica GOAT, escrito em Windows PowerShell 5.1 e WPF. Este projeto começa do zero, em pasta própria. A interface e o scanner funcionam sem instalar Node, Python, .NET adicional ou módulos da PowerShell Gallery.

## Abrir com um comando

Abra o **Windows PowerShell como administrador** e execute:

```powershell
irm 'https://raw.githubusercontent.com/JuliozXz/GOAT-Tweaks-V1/main/dist/GOAT-Tweaks.ps1' | iex
```

O comando abre a interface e analisa a máquina; as alterações só começam quando o técnico seleciona as opções e clica em aplicar. Sem elevação, o diagnóstico continua disponível. O repositório mantém o nome `GOAT-Tweaks-V1`, e o aplicativo publicado é a versão **2.4**.

## Abrir

Use **Windows PowerShell de 64 bits**. Para diagnóstico, elevação não é necessária. Para aplicar/restaurar, abra como administrador **na conta do usuário que receberá os ajustes**; se usar credenciais de outra conta, as preferências HKCU pertencerão àquela outra conta.

```powershell
# Na pasta deste projeto:
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\GOAT-Tweaks.ps1

# Interface com dados de exemplo, sem alterações do Windows:
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\GOAT-Tweaks.ps1 -Demo

# Apenas diagnóstico, saída JSON, sem interface:
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\GOAT-Tweaks.ps1 -ScanOnly
```

O executável de PowerShell 7 relança automaticamente o script salvo usando Windows PowerShell 5.1. Nenhum tweak é aplicado ao abrir o aplicativo. O botão de aplicar atua apenas na seleção visível da categoria atual.

## Recursos implementados

- Logo GOAT original no topo e tema preto/grafite com detalhes dourados.
- Quatro categorias visíveis de projetos: Winutil, WinSux, Ultimate e RyTuneX. O catálogo inclui **1.330 itens**, com busca, filtro por pasta/tipo, código-fonte, scripts, executáveis de releases e recursos dos aplicativos.
- Interface escura com navegação por categoria, estados de permissão e checklist revisável.
- Scanner em segundo plano: CPU, núcleos/threads, GPU, configuração MSI declarada pelo driver, prioridade declarada, RAM, placa-mãe, BIOS, Windows, rede, plano de energia e inventário de drivers.
- Histórico de utilização de CPU/GPU/RAM nos últimos 60 segundos, conforme disponibilidade dos provedores do Windows. GPU mostra o maior uso de motor 3D observado, não uma média entre motores. Ausência de dados aparece como indisponível.
- Detecção por nomes conhecidos de processos de jogos; a lista não é universal e não injeta nada no jogo.
- 33 opções integradas: as nove opções anteriores e 24 controles revisados de Explorer, interface, entrada, privacidade e distribuição de downloads. Trinta oferecem dois estados explícitos; o botão Restaurar continua recuperando o estado capturado antes da alteração.
- Perfil de uso Jogos/Equilibrado, preservação de gravação e pré-seleção explicada conforme RAM, disponibilidade, armazenamento, rede e energia. Preferências pessoais permanecem manuais; selecionar mais itens não equivale a mais desempenho.
- Análise cruzada em segundo plano por RAM, CPU, GPU, BIOS, rede, sistema e drivers. Uma matriz revisada associa as leituras do Windows às fontes dos quatro projetos, elimina recomendações duplicadas e identifica divergências.
- Links oficiais de ferramentas e drivers. O aplicativo abre a página; a instalação continua sob acompanhamento do técnico.
- Registro de comandos/valores alterados, backup dos valores e tipos originais, verificação após cada escrita, reversão em falha e retomada da restauração de operações interrompidas.

A interface começa no perfil Jogos, preservando gravação e clipes. Compressão desativada só é pré-selecionada quando há até 8 GB de RAM ou pouca RAM disponível na amostra. Em máquinas sem essa condição, ela fica manual. Preferências já configuradas e leituras desconhecidas não viram novas alterações. O técnico pode trocar de perfil, ajustar cada direção e usar **Selecionar recomendados** para reaplicar a seleção calculada. Escolhas manuais são preservadas ao trocar de perfil.

As 24 opções novas incluem preferências de interface e privacidade; não são 24 otimizações de FPS. A origem, o efeito e os dois estados estão descritos em [Opções integradas](docs/OPCOES.md). **Usar padrão** remove uma preferência específica; **Restaurar** recupera o valor anterior registrado, que pode ser diferente do padrão.

## Comparação dos scripts e executáveis para cada PC

Cada análise percorre os **1.330 itens** das quatro bibliotecas. A versão 2.4 possui **44 regras individuais revisadas** para scripts e ferramentas. O resultado aparece na lista e no detalhe como **Recomendado**, **Compatível**, **Revisão manual**, **Não aplicável** ou **Referência**, com filtro próprio e justificativa para a máquina detectada.

Regras de fabricante usam a GPU ou CPU correspondente: um processador AMD não implica uma placa de vídeo AMD. Múltiplas GPUs e drivers genéricos são tratados sem converter falta de informação em incompatibilidade. Arquitetura desconhecida permanece para revisão. Ferramentas equivalentes são agrupadas para evitar sugerir diagnósticos repetidos.

As sugestões automáticas externas são limitadas a três launchers revisados de diagnóstico de GPU, CPU/RAM e armazenamento. Otimizadores amplos, instaladores, drivers e itens sem regra individual não são declarados “os melhores” pelo nome. Eles permanecem acessíveis para revisão. Assim, **comparar todos os registros não significa que todos os scripts foram certificados, convertidos em botões nativos ou medidos em todos os PCs**.

O scanner não mede FPS nem executa jogos/benchmarks automaticamente. Para afirmar melhoria, compare a mesma cena, jogo, resolução e configurações antes/depois, incluindo tempos de quadro; ferramentas como [PresentMon](https://github.com/GameTechDev/PresentMon/blob/main/README.md) fornecem medições para essa validação. Nenhuma regra garante ganho em todo hardware.

## Análise cruzada por área

O scanner apresenta **Recomendado**, **Configurado**, **Revisão manual** ou **Indisponível**, acompanhado do estado atual, motivo e links das fontes. Uma consulta que falha não equivale a recurso desativado. O diagnóstico usa uma matriz revisada distribuída com o aplicativo; não executa scripts baixados nem faz pesquisa automática na internet enquanto analisa o cliente.

| Área | Leituras e decisão |
| --- | --- |
| RAM | Compressão pelo MMAgent e preferência de cache. Ativação da compressão disponível com proteção, verificação e restauração do valor anterior. |
| CPU | Arquitetura, núcleos/threads, estacionamento no plano ativo e prioridade configurada. C-States dependem de firmware; não são inferidos pelo nome do processador. |
| GPU | MSI e prioridade declarados pelo driver, preferência HAGS e revisão de ReBAR. Preferência de Registro não prova suporte nem estado efetivo em execução. |
| Placa-mãe/BIOS | Controladores, MSI declarado e flags de timers no boot. Nenhum ajuste universal de HPET ou latência DPC é aplicado. |
| Rede | TCP Internet, RSS, políticas QoS e energia do adaptador. TCP Normal e RSS têm ações nativas revisáveis; buffers e energia exigem compatibilidade e comparação de carga. |
| Sistema/drivers | Windows Update, serviços, UWP do usuário, inventário limitado de TEMP, preferências do Explorer e drivers. Limpeza e remoções seguem procedimentos revisados dos aplicativos originais. |

A mesma configuração aparece uma vez, com todas as fontes correspondentes. Quando os projetos divergem, o aplicativo informa o conflito. Veja [a matriz e os critérios de recomendação](docs/RECOMENDACOES.md). A melhor configuração depende do hardware, da carga e da medição; o scanner não inventa ganhos de FPS, DPC ou input lag.

## Projetos originais visíveis

| Categoria | Conteúdo no catálogo |
| --- | --- |
| Winutil | 389 arquivos, 1 launcher oficial de release e 397 itens dos catálogos de aplicações, ajustes, recursos, DNS e predefinições. |
| WinSux | 8 arquivos, incluindo o fluxo principal e seus auxiliares, mais 16 executáveis publicados pelo autor. |
| Ultimate | 108 arquivos preservados nas pastas originais, incluindo 105 scripts PowerShell, e 59 executáveis/pacotes de releases. |
| RyTuneX | 200 arquivos, 151 recursos/páginas identificados no projeto e acesso oficial pela Microsoft Store. |

Cada item informa sua origem e oferece as ações compatíveis com seu formato: **Ver origem**, **Baixar** e **Executar**. Funções internas, arquivos C#/XAML e recursos dependentes do aplicativo permanecem visíveis para consulta. Eles são usados dentro do programa original; o catálogo não os apresenta como scripts independentes. WinSux deve começar pelo fluxo principal, pois seus auxiliares dependem das etapas anteriores. ZIP e APPX podem ser baixados para o procedimento original de instalação.

A execução de scripts e instaladores exige administração, revisão do item escolhido e um ponto GOAT confirmado nas últimas 24 horas; se não houver, o aplicativo tenta criar e verificar um. Falha na proteção bloqueia a execução. A Microsoft Store abre diretamente sua página oficial e não inicia uma instalação silenciosa.

Arquivos são obtidos dos repositórios/releases oficiais, com verificação de Git blob SHA ou SHA256. Para executar scripts do repositório, o GOAT prepara a árvore completa do commit catalogado e verifica todos os arquivos. Scripts, executáveis e instaladores abrem em processos separados, com as pastas originais e sem parâmetros de instalação silenciosa. Downloads ficam em `D:\GoatTweaks\tools\` ou `%ProgramData%\GoatTweaks\tools\`, separados por projeto e versão.

**As alterações feitas pelos programas externos não pertencem ao diário de reversão do GOAT.** Cada programa mantém seu próprio comportamento; alguns fazem downloads adicionais, alteram proteções ou reiniciam o Windows. A tela de revisão apresenta os avisos do item. Fixar o launcher por commit/hash não fixa os downloads que o próprio launcher faz depois.

O catálogo representa as revisões verificadas em 26/10/2026. Os snapshots de desenvolvimento ficam em `artifacts/` e não são publicados. `scripts/Build-Catalog.ps1` regenera o catálogo a partir desses snapshots revisados; o aplicativo não executa nem atualiza scripts externos ao iniciar.

## Proteção e reversão

Antes de um lote, o aplicativo exige administração, compatibilidade do Windows e um **ponto de restauração novo e confirmado** por descrição única e SequenceNumber. Falha na criação bloqueia o lote antes de qualquer tweak. A proteção do sistema deve estar habilitada. O Windows pode limitar a criação a um ponto a cada 24 horas; o aplicativo não remove esse limite nem habilita a proteção silenciosamente.

Os valores anteriores são capturados antes da primeira escrita e salvos em um diário com substituição atômica de arquivo. Cada etapa em andamento é registrada antes de alterar o sistema. Uma segunda sessão não pode aplicar/restaurar simultaneamente. Operação interrompida bloqueia novos lotes até recuperação.

**Restaurar configuração anterior** desfaz a transação mais recente ainda aplicada ou interrompida para o mesmo Windows e SID, em ordem inversa. Repetir permite desfazer lotes anteriores. O ponto de restauração originalmente confirmado protege a operação e sua reversão; se ele tiver sido removido, a reversão exige criar outro. Preferências visuais e de entrada podem exigir nova sessão/reinício. O aplicativo nunca reinicia o computador automaticamente.

```text
D:\GoatTweaks\logs\       comandos e resultados
D:\GoatTweaks\backups\    diários JSON dos valores originais
```

Se D: não existir, usa `%ProgramData%\GoatTweaks`. Se D: existir mas estiver sem permissão/espaço, a ação falha e informa o motivo. Preserve os diários JSON; não os copie para outro PC nem os edite. A restauração usa os valores capturados do cliente, não uma lista presumida de padrões do Windows.

## Limites técnicos

O alvo de execução é Windows 10/11 cliente x64, build 19041 ou superior. A verificação de build não equivale a certificação em todas as edições, drivers e configurações. Esta entrega foi validada em uma máquina Windows 10, com testes isolados de transações e interface em demonstração. Validação de bancada em máquinas representativas ainda é necessária antes de distribuição comercial.

C-States, afinidade universal, ReBAR, MSI/HAGS, HPET, BCD e timers aparecem como diagnóstico/orientação quando aplicável. Suporte do driver, configuração de firmware e latência DPC não podem ser provados por fabricante, uma chave de Registro ou utilização instantânea. Não existe pontuação fictícia de otimização nem promessa de FPS/input lag. Não há alteração automática dessas opções.

O módulo nativo Sistema oferece restrição reversível de atividade UWP. Desinstalação em massa de apps, exclusão de caches, bloqueio de Windows Update, desativação indiscriminada de serviços e offloads não são ajustes nativos do GOAT: não possuem reversão equivalente por um backup de Registro. Esses procedimentos podem existir nos projetos externos e seguem as regras e etapas desses aplicativos. Windows Update permanece acessível pela área de ferramentas.

O código do GOAT é próprio. As quatro categorias mantêm a origem e a licença de cada projeto; arquivos de terceiros são obtidos diretamente da publicação original quando o técnico solicita. Consulte [as decisões e fontes técnicas](docs/REFERENCIAS.md). Não há autenticação de técnicos: o perfil “Técnico GOAT” é identidade visual, e a autorização efetiva vem da sessão local do Windows.

## Build e distribuição

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
```

Saídas: `dist\GOAT-Tweaks.ps1` independente, `dist\GOAT-Tweaks.sha256` e `dist\GOAT-Tweaks-v2.4.zip`. O arquivo independente inclui scanner, engine, XAML, logo e catálogo. O transporte gerado é ASCII sem BOM, com recursos UTF-8 codificados em Base64 e catálogo comprimido em GZip, decodificados em memória. Isso preserva os textos em português no `irm | iex` do PowerShell 5.1 mesmo quando o servidor não envia charset. O código legível de cada módulo está em `src/`.

O endereço publicado aponta diretamente para **o arquivo gerado**, que não depende dos arquivos locais de `src/`:

```powershell
irm 'https://raw.githubusercontent.com/JuliozXz/GOAT-Tweaks-V1/main/dist/GOAT-Tweaks.ps1' | iex
```

Execute esse comando no Windows PowerShell 5.1 x64. O endereço `main` acompanha futuras atualizações. Para uma distribuição auditável, use um commit específico no endereço e preserve o SHA256. O checksum acompanha o arquivo em `dist/GOAT-Tweaks.sha256`; a forma `irm | iex` não verifica o checksum automaticamente.

## Verificar sem aplicar tweaks

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-UI.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Integrations.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-AdvancedScanner.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Recommendations.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Selection.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-OptionData.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-ToolAdvisor.ps1 -RequireActualRules
```

Os testes da engine substituem as APIs de alteração e os checkpoints por simuladores em memória. O teste de UI usa demonstração para verificar navegação, gráfico, aplicação simulada e restauração simulada, e gera capturas em `artifacts\`. Testes não aplicam tweaks reais. O parâmetro `-RealReadOnly` verifica a UI com consultas reais, e `-Bundle` verifica a versão independente. Consulte [o relatório de validação](docs/VALIDACAO.md).
