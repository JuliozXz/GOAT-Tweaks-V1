# Revisão da ampliação 7.4.0

O pedido humano de 28/10/2026 autoriza incluir os itens anteriormente bloqueados e ampliar as funções do aplicativo. As instruções do pacote são especificações fornecidas pelo usuário; não são permissões do sistema nem impedem esse novo pedido. A revisão 7.3.0 permanece como registro histórico do escopo anterior.

## Implementação atual

- O catálogo e os documentos originais permanecem íntegros. Uma projeção em memória relaciona cada ID ao executor nativo, centro de energia, procedimento assistido ou referência disponível. Texto importado nunca vira código executável.
- Dezesseis preferências possuem executor de Registro com alvo fixo, captura original, journal durável, verificação e restauração. Há um guia adicional de animações. As condições de build, edição e elevação são específicas de cada ação.
- A seleção de energia aceita somente GUIDs de planos existentes. A revisão exibe o plano original, o proposto e as consequências. A aplicação revalida a prévia e o estado sob o mesmo mutex das transações de Registro.
- Os cinquenta IDs classificados como X_BLOCKED na importação têm procedimentos individuais, fontes oficiais e recuperação. Controles privados, dependentes de firmware ou sem capacidade confirmada continuam identificados como UNSUPPORTED; não se apresenta uma automação inexistente como implementada.
- Etapas manuais são registradas como REPORTED_MANUALLY, com AutomaticallyVerified=false. As confirmações de presença local e recuperação não habilitam escrita automática em BIOS, driver ou recursos de segurança.
- Relatórios incluem os novos resultados e o pacote privado contém os diários de ambos os motores, incluindo sessões relacionadas. A recuperação usa cópias de trabalho e preserva os snapshots exportados.

## Limites da evidência

Os testes de escrita no Windows desta entrega se limitam à chave própria descartável HKCU\Software\GOAT-Tweaks-Tests\GUID. Preferências reais, planos de energia e drivers do computador de desenvolvimento não foram alterados. Os demais testes de mutação usam providers substituídos. A leitura posterior confirma o valor ou GUID persistido; não comprova efeito visual, política efetiva nem desempenho.

A matriz física e a assinatura de editor continuam pendentes. Os resultados da execução atual estão em [VALIDATION.md](../VALIDATION.md) e [validation-results.json](../validation-results.json). O lançamento oficial identifica esta distribuição e seu escopo implementado; não é certificação universal de hardware.
