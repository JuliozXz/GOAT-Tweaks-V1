# GOAT Tweaks 7.3.0

Distribuição oficial dos fluxos implementados de diagnóstico/atendimento em PowerShell 5.1/WPF. Inclui GPU Center, perfis locais consultivos, importação e comparação de frametimes, catálogo/documentação, sessões, relatórios e infraestrutura de recuperação. O aplicativo independente funciona sem winget, GitHub CLI ou módulos adicionais.

## Abrir em uma linha

Copie o conteúdo de `Open-GOAT.txt` desta release e cole no PowerShell. O comando baixa o arquivo da tag fixa v7.3.0, verifica o SHA256 esperado antes de executar, abre o app em STA e remove somente o temporário criado quando o app termina. Os relatórios e as sessões privadas permanecem na pasta do usuário.

## Revisão realizada

- Fonte documental preservada: 83 arquivos, 81 hashes válidos, 344 IDs e 64 documentos completos.
- Classificações corrigidas: 41 bloqueios originais mais nove decisões normativas, totalizando 50 efetivos. O texto original e a justificativa das correções ficam rastreáveis.
- Captura CSV lida uma vez sob bloqueio de escrita, com métricas, SHA256 e cópia preservada a partir dos mesmos bytes. Importação em segundo plano com cancelamento.
- Recuperação independente respeita a ordem entre sessões, preserva snapshots e valida identidade, estado e conteúdo antes de restaurar.
- Inventário fica em memória antes de consentir seu registro; retomada de sessão valida schema e reconcilia finalizações interrompidas.
- Interface e distribuição usam versão oficial 7.3.0 e build com manifesto de fontes.

## Validação

10 suítes, 3.753 verificações, zero falhas em Windows PowerShell 5.1. Mais 81 verificações de UI no bundle e 23 verificações de UI real somente leitura em Windows 10/NVIDIA. Nenhuma preferência real do Windows foi alterada. Hash e resultados exatos constam dos arquivos desta release e de `docs/validation-results.json` no código.

## Escopo e limitações

Esta publicação não declara 344 ajustes automáticos nem a conclusão de todos os módulos propostos no pacote. Preferências nativas continuam sem liberação real enquanto faltam testes de mutação/rollback em sistemas descartáveis. Sensores completos, captura ETW/overlay, integrações de escrita em jogos/apps, Windows 11 e AMD/Intel físicos e assinatura Authenticode permanecem fora da validação entregue. Drivers/DDU são guias assistidos; BIOS/OC, alterações de proteção e operações disruptivas não possuem executores.

O SHA256 verifica o conteúdo esperado, sem substituir assinatura de editor ou certificação de hardware. A matriz funcional, a revisão completa e os testes estão em `docs/FEATURE-MATRIX.md`, `docs/VALIDATION.md` e `docs/audit/RELEASE-REVIEW.md`.
