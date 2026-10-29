# GOAT Tweaks 7.4.0

Esta versão amplia as operações implementadas sem transformar o catálogo documental em autorização de execução. O app continua portátil, em um arquivo PowerShell independente, e abrir a interface não aplica ajustes.

## Mudanças

- **16 executores de Registro:** sete preferências do Explorer, cinco de aparência, duas preferências de jogos do Windows 11 e duas políticas específicas de captura/confirmação de exclusão. A lista exata está na [matriz funcional](FEATURE-MATRIX.md).
- Prévia com estado original/proposto e elegibilidade; a interface compara a prévia revisada novamente sob o mutex. Divergência aborta antes da primeira escrita.
- Lotes de até sete preferências A; as cinco ações B exigem aprovação do ID exato e execução individual. Edição, build, arquitetura, elevação, gerenciamento e contexto remoto são verificados conforme a ação.
- Seleção de **plano de energia existente**, com GUID original, journal, confirmação de aplicação e recuperação. Não cria, remove ou edita planos.
- Itens avançados e anteriormente bloqueados ficam acessíveis para consulta, com procedimentos e limites. Sua presença não cria executores de driver, BIOS, segurança, OC ou rede.
- Animações da barra de tarefas têm **guia manual**; nenhuma chave privada é apresentada como API universal.

## Integridade e reversão

O motor preserva ausência, hive/view, tipo e dados anteriores. Snapshot clonado e SHA256 são gravados antes da primeira escrita; read-back confirma a preferência persistida. Configuração já desejada gera no-op. Uma escrita negada antes de alterar o valor não força rollback desnecessário; falha na reversão preserva os snapshots.

Uma transação aplicada cujo valor foi alterado externamente exige revisão antes de restaurar. Pendências de energia e Registro bloqueiam novas aplicações no outro motor. Journals e snapshots DWORD da 7.3.0 continuam aceitos pelos alvos exatos, sem depender dos novos metadados.

## Escopo dos testes

Fixtures PowerShell 5.1 verificam todos os executores nas duas direções, leitura posterior, restauração de tipos originais e recuperação de falhas. A integração da API real fica **somente** na chave própria descartável HKCU\Software\GOAT-Tweaks-Tests\GUID: DWord/QWord, String/ExpandString, MultiString/Binary vazios e unitários e ausência original. Nenhuma preferência real do Windows foi aplicada nos testes desta entrega.

IMPLEMENTED_AND_TESTED significa executor e armazenamento/reversão testados, conforme ValidationScope. Efeito visual imediato, política efetivamente aplicada, desempenho em jogos e todos os builds/edições exigem validação específica. **Uma escrita verificada não equivale a ganho de FPS.**

Game Mode e o atalho do controle têm executor limitado ao Windows 11. AllowGameDVR fica limitado ao Windows 10 desktop suportado, edição compatível, administração, console local e ausência de gerenciamento detectado; a [documentação Microsoft](https://learn.microsoft.com/en-us/windows/client-management/mdm/policy-csp-applicationmanagement#allowgamedvr) restringe seu efeito. No Windows 11, captura permanece assistida.

## Distribuição

A release inclui GOAT-Tweaks.ps1, checksum, ZIP, manifesto e Open-GOAT.txt. A linha de abertura usa a URL da versão 7.4.0 e confere o hash esperado antes de iniciar o aplicativo. Não instala dependências nem altera a política global de execução. Relatórios e recuperação permanecem locais; a pasta private-recovery não deve ser publicada.

Não há assinatura Authenticode de editor. A matriz física completa Windows 10/11 e NVIDIA/AMD/Intel, assim como ensaios adicionais das preferências reais em VMs, permanece pendente e deve ser documentada separadamente.
