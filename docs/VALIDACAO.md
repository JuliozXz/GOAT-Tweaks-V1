# Validação da versão 2.3

Data: 26 de outubro de 2026.

Ambiente disponível: Windows 10 x64, build 19045; execução dos testes no Windows PowerShell 5.1, STA para WPF.

| Verificação | Resultado |
| --- | --- |
| Engine, APIs de alteração substituídas por simuladores | 15 cenários aprovados, incluindo compressão de memória e restauração |
| Integrações externas, fronteiras simuladas | 18 grupos de cenários aprovados |
| Interface independente com dados demonstrativos | 215 verificações aprovadas |
| Interface independente com scanner e telemetria reais, somente leitura | 196 verificações aprovadas |
| Scanner avançado | 6 grupos de testes aprovados; 21 leituras, com 19 disponíveis no PC de validação |
| Matriz de recomendações | 20 efeitos canônicos, 56 referências verificadas, sete áreas |
| Motor de recomendações | 13 grupos de testes aprovados, incluindo deduplicação, conflitos e estados desconhecidos |
| Catálogo das quatro bibliotecas | 1.330 itens: Winutil 787, WinSux 24, Ultimate 167, RyTuneX 352 |
| Downloads oficiais sem execução | README WinSux, árvore completa Ultimate com 108 arquivos e release Winutil; hashes verificados |
| Diagnóstico JSON no script independente | Aprovado |
| Relançamento de script salvo via PowerShell 7 para Windows PowerShell 5.1 | Aprovado no diagnóstico |
| Sintaxe dos scripts e instanciação do XAML no PowerShell 5.1 | Aprovadas |
| SHA256 e transporte ASCII sem BOM do arquivo independente | Verificados; módulos/XAML UTF-8, catálogo GZip e logo incorporados |
| Inspeção visual do dashboard e biblioteca | Realizada, com logo original e tema preto/grafite/dourado |

A suíte da engine cobre: demonstração sem alterações; checkpoint malsucedido; persistência de originais antes de cada escrita; reversão de escrita interrompida; preservação de DWORD/String, valores e chaves ausentes; aplicação e reversão bem-sucedidas; recuperação de transação interrompida; bloqueio de lotes concorrentes/pendentes; identidade de Windows/usuário; rejeição de IDs desconhecidos; exigência de administrador; falha de log depois do commit; tipo original não reversível; seleção do backup da identidade correta.

A UI verifica todas as 13 páginas, alternância CPU/GPU/RAM, amostras no gráfico, execução assíncrona, modo demonstração, aplicação/restauração simuladas e nova análise. A área RAM exibe compressão e cache; as sete áreas apresentam estados, justificativas, divergências e links de evidência. As bibliotecas são verificadas com o catálogo real: contagens, busca, filtros por pasta/tipo, seleção dos programas oficiais, logo e tema. A opção Baixar fica desabilitada para a página da Microsoft Store. Abertura e download pela UI são simulados no modo demonstração.

O scanner avançado foi exercitado com consultas simuladas, estados ausentes, consultas indisponíveis, parsing de índices AC/DC em português e inglês e limite de observação de TEMP. A leitura real adicional completou em 6,16 segundos neste PC; ReBAR e C-States ficaram explicitamente não verificáveis. Esse tempo é uma observação local, não uma promessa de desempenho em outras máquinas.

A suíte de integrações verifica hashes SHA256 e Git blob, contenção dos caminhos e rejeição de junctions, árvore ZIP completa e arquivos adulterados, isolamento dos comandos PS1/CMD/EXE/MSI, exigência de administrador, checkpoint com data DMTF ou DateTime, rejeição de checkpoints antigos/de outros aplicativos, destino da Store e falha de log após um processo já iniciado. Esses testes substituem as fronteiras de rede, processos e restauração por simuladores.

Nenhum tweak, ponto de restauração, plano de energia ou ajuste de rede real foi aplicado durante esta validação. Nenhum script, instalador ou executável externo foi executado. Os downloads de conferência foram limitados à validação dos arquivos e hashes; isso não certifica o funcionamento interno dos programas externos.

Isso não certifica a criação real de checkpoints nem a reversão em todas as edições, hardwares ou políticas corporativas. Antes de distribuição comercial, valide o ciclo completo de aplicar/restaurar em máquinas de bancada representativas, sob a identidade correta, com Proteção do Sistema habilitada.
