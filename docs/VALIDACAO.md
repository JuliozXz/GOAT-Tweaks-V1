# Validação desta entrega

Data: 26 de outubro de 2026.

Ambiente disponível: Windows 10 x64, build 19045; execução dos testes no Windows PowerShell 5.1, STA para WPF.

| Verificação | Resultado |
| --- | --- |
| Engine, APIs de alteração substituídas por simuladores | 11 cenários aprovados |
| Interface com dados demonstrativos | 23 verificações aprovadas |
| Interface com scanner e telemetria reais, somente leitura | 17 verificações aprovadas |
| Interface carregada do script independente gerado | 23 verificações aprovadas |
| Diagnóstico JSON no script independente | Aprovado |
| Relançamento de script salvo via PowerShell 7 para Windows PowerShell 5.1 | Aprovado no diagnóstico |
| Sintaxe dos scripts e instanciação do XAML no PowerShell 5.1 | Aprovadas |
| SHA256 e transporte ASCII sem BOM do arquivo independente | Verificados; módulos e XAML decodificados como UTF-8 |
| Inspeção visual do dashboard renderizado | Realizada, com revisão das barras de rolagem, ações e gráfico |

A suíte da engine cobre: demonstração sem alterações; checkpoint malsucedido; persistência de originais antes de cada escrita; reversão de escrita interrompida; preservação de DWORD/String, valores e chaves ausentes; aplicação e reversão bem-sucedidas; recuperação de transação interrompida; bloqueio de lotes concorrentes/pendentes; identidade de Windows/usuário; rejeição de IDs desconhecidos; exigência de administrador; falha de log depois do commit; tipo original não reversível; seleção do backup da identidade correta.

A UI verifica todas as oito páginas, alternância CPU/GPU/RAM, amostras no gráfico, execução assíncrona, modo demonstração, aplicação/restauração simuladas e nova análise. Foi também conferido o layout reduzido em 1050 × 650.

Nenhum tweak, ponto de restauração, plano de energia ou ajuste de rede real foi aplicado durante esta validação. Checkpoints, falhas de escrita e restauração de configurações foram exercitados por simulação das fronteiras do Windows.

Isso não certifica a criação real de checkpoints nem a reversão em todas as edições, hardwares ou políticas corporativas. Antes de distribuição comercial, valide o ciclo completo de aplicar/restaurar em máquinas de bancada representativas, sob a identidade correta, com Proteção do Sistema habilitada.
