# Catálogos oficiais de Winutil e RyTuneX

Consulta feita em 26 de outubro de 2026 pelo conector GitHub, somente leitura. Nenhum código dos projetos foi executado. As árvores recursivas retornaram `truncated=false`; as contagens abaixo incluem todos os objetos de arquivo da revisão consultada, não apenas scripts executáveis.

| Projeto | Revisão da branch principal | Arquivos | Diretórios | Última release |
| --- | --- | ---: | ---: | --- |
| Winutil | [`2f0bdc8fca52e1ebe31a8d98216428061d3f8956`](https://github.com/ChrisTitusTech/winutil/commit/2f0bdc8fca52e1ebe31a8d98216428061d3f8956) | 389 | 39 | [26.10.07](https://github.com/ChrisTitusTech/winutil/releases/tag/26.10.07), com um asset PowerShell |
| RyTuneX | [`957885f53beaacfa7322581cafdb9eba5df5726a`](https://github.com/rayenghanmi/RyTuneX/commit/957885f53beaacfa7322581cafdb9eba5df5726a) | 200 | 34 | [v1.8.0](https://github.com/rayenghanmi/RyTuneX/releases/tag/v1.8.0), sem assets de download |

As revisões de `main` e da última release são referências diferentes. O catálogo obtido de `main` não comprova que toda opção esteja presente no aplicativo da última release estável.

## Winutil

O [README oficial](https://github.com/ChrisTitusTech/winutil/blob/2f0bdc8fca52e1ebe31a8d98216428061d3f8956/README.md) aponta `https://christitus.com/win` para a aplicação estável e `https://christitus.com/windev` para desenvolvimento. A release estável consultada oferece [winutil.ps1](https://github.com/ChrisTitusTech/winutil/releases/download/26.10.07/winutil.ps1), com 927.798 bytes e digest SHA-256 `eeae69922fbe6354ea4e2a37f705eaa17bdaf45cc7889618a313178a513b13ee` informado pelo GitHub.

| Catálogo oficial | Entradas | Grupos |
| --- | ---: | --- |
| [applications.json](https://github.com/ChrisTitusTech/winutil/blob/2f0bdc8fca52e1ebe31a8d98216428061d3f8956/config/applications.json) | 239 | Utilities 53; Document 17; Pro Tools 24; Multimedia Tools 21; Microsoft Tools 19; Games 17; Browsers 15; Development 43; Communications 18; Selfhosted Tools 12 |
| [tweaks.json](https://github.com/ChrisTitusTech/winutil/blob/2f0bdc8fca52e1ebe31a8d98216428061d3f8956/config/tweaks.json) | 68 | Essential Tweaks 18; Advanced Tweaks — CAUTION 23; Customize Preferences 25; Performance Plans 2 |
| [feature.json](https://github.com/ChrisTitusTech/winutil/blob/2f0bdc8fca52e1ebe31a8d98216428061d3f8956/config/feature.json) | 33 | Features 10; Fixes 6; Legacy Windows Panels 14; PowerShell 7+ Profiles 2; Remote Access 1 |
| [appx.json](https://github.com/ChrisTitusTech/winutil/blob/2f0bdc8fca52e1ebe31a8d98216428061d3f8956/config/appx.json) | 34 | Microsoft Apps 5; Utilities & Productivity 14; Bing & Web Services 5; Developer Tools 2; Microsoft Ecosystem 2; Xbox & Gaming 6 |
| [dns.json](https://github.com/ChrisTitusTech/winutil/blob/2f0bdc8fca52e1ebe31a8d98216428061d3f8956/config/dns.json) | 8 | Provedores de DNS |
| [preset.json](https://github.com/ChrisTitusTech/winutil/blob/2f0bdc8fca52e1ebe31a8d98216428061d3f8956/config/preset.json) | 4 | Standard, Minimal, Advanced e AppxDefault |
| [appnavigation.json](https://github.com/ChrisTitusTech/winutil/blob/2f0bdc8fca52e1ebe31a8d98216428061d3f8956/config/appnavigation.json) | 11 | Ações da interface e seleção |

As seis entradas classificadas como Fixes são configuração de NTP, AutoLogon, reset do Windows Update, reset de rede, verificação de corrupção e reinstalação do WinGet. As 33 entradas de `feature.json` incluem botões de interface e painéis; não representam 33 recursos instaláveis distintos.

Na biblioteca GOAT, o botão de iniciar deve abrir a aplicação Winutil completa pelo entrypoint estável. Cada item de catálogo pode mostrar seu título, descrição, grupo e arquivo de origem. Arquivos em `functions/private`, `functions/public`, `scripts`, `config`, `xaml`, testes e ferramentas devem oferecer inspeção de fonte; muitos dependem do contexto montado pela aplicação. Sua extensão `.ps1` não os transforma em ajustes independentes prontos para iniciar.

## RyTuneX

O [README oficial](https://github.com/rayenghanmi/RyTuneX/blob/957885f53beaacfa7322581cafdb9eba5df5726a/README.md) oferece instalação pela [Microsoft Store](https://apps.microsoft.com/detail/9PDH8M7HF2SQ), produto `9PDH8M7HF2SQ`, ou pelo WinGet com esse mesmo ID. O autor informa que já não fornece pacotes para instalação lateral. A última release consultada não contém `.exe`, `.msix` nem outros assets; o arquivo de projeto `Package.appinstaller` contém placeholders e não é um instalador distribuído.

As 15 páginas da navegação oficial são Home, Optimize, Services, Processes, Startup Apps, Repair, Debloat, Packages, Privacy, Features, Networking, Security, Policies, Device e Stress Test. Settings é uma página adicional de configuração; Shell é o contêiner de navegação.

| Página inspecionada | Alternadores na fonte XAML | Seções oficiais |
| --- | ---: | --- |
| [Optimize](https://github.com/rayenghanmi/RyTuneX/blob/957885f53beaacfa7322581cafdb9eba5df5726a/Views/OptimizeSystemPage.xaml) | 40 | Energia; entrada e resposta; timers e latência; memória; jogos e GPU; disco e arquivos; serviços e sistema; componentes do Windows |
| [Features](https://github.com/rayenghanmi/RyTuneX/blob/957885f53beaacfa7322581cafdb9eba5df5726a/Views/FeaturesPage.xaml) | 40 | Aparência; serviços; entrada e acessibilidade; Explorer; notificações; interface Windows 11; IA e Edge; menu de contexto |
| [Privacy](https://github.com/rayenghanmi/RyTuneX/blob/957885f53beaacfa7322581cafdb9eba5df5726a/Views/PrivacyPage.xaml) | 34 | Publicidade; telemetria; coleta e entrada; sincronização; localização e segurança; reforço de privacidade |
| [Networking](https://github.com/rayenghanmi/RyTuneX/blob/957885f53beaacfa7322581cafdb9eba5df5726a/Views/NetworkPage.xaml) | 9 | Adaptador; DNS atual; DNS personalizado; ferramentas; otimização de rede |

Esses 123 alternadores são controles de interface identificados nas quatro páginas; a contagem não inclui botões, seletores, listas dinâmicas ou operações de outras páginas. O catálogo detalhado nos artefatos guarda títulos e descrições extraídos dos recursos em inglês, com a seção e o arquivo de origem.

RyTuneX é uma aplicação C#/WinUI compilada. Na biblioteca GOAT, o botão de iniciar/instalar deve abrir a aplicação ou sua página oficial da Store. As páginas e controles podem oferecer inspeção da fonte e acesso à aplicação completa. Nenhum mecanismo oficial de navegação direta para uma página específica foi verificado. Os 83 arquivos `.cs`, os 24 `.xaml` e o helper `Assets/RemoveEdge.ps1` não são executáveis independentes da aplicação.

## Artefatos para integração

`artifacts/upstream-winutil.json` e `artifacts/upstream-rytunex.json` preservam metadados do repositório, revisão, árvore recursiva completa, última release, entrypoints, catálogos e contagens. Os campos `tree.tree` permitem listar todos os arquivos com links fixados à revisão; os catálogos fornecem o agrupamento funcional. `entrypoints` e `actionPolicy` distinguem iniciar a aplicação, instalar pela Store e inspecionar um arquivo de fonte.
