# GOAT Tweaks v2.2

Aplicativo desktop para a bancada técnica GOAT, escrito em Windows PowerShell 5.1 e WPF. Este projeto começa do zero, em pasta própria. A interface e o scanner funcionam sem instalar Node, Python, .NET adicional ou módulos da PowerShell Gallery.

## Abrir com um comando

Abra o **Windows PowerShell como administrador** e execute:

```powershell
irm 'https://raw.githubusercontent.com/JuliozXz/GOAT-Tweaks-V1/main/dist/GOAT-Tweaks.ps1' | iex
```

O comando abre a interface e analisa a máquina; as alterações só começam quando o técnico seleciona as opções e clica em aplicar. Sem elevação, o diagnóstico continua disponível. O repositório mantém o nome `GOAT-Tweaks-V1`, e o aplicativo publicado é a versão **2.2**.

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

- Interface escura com navegação por categoria, estados de permissão e checklist revisável.
- Scanner em segundo plano: CPU, núcleos/threads, GPU, configuração MSI declarada pelo driver, prioridade declarada, RAM, placa-mãe, BIOS, Windows, rede, plano de energia e inventário de drivers.
- Histórico de utilização de CPU/GPU/RAM nos últimos 60 segundos, conforme disponibilidade dos provedores do Windows. GPU mostra o maior uso de motor 3D observado, não uma média entre motores. Ausência de dados aparece como indisponível.
- Detecção por nomes conhecidos de processos de jogos; a lista não é universal e não injeta nada no jogo.
- Oito opções transacionais: Modo de Jogo, captura em segundo plano, efeitos visuais, aceleração do ponteiro, apps UWP em segundo plano, plano Alto Desempenho existente, auto-tuning TCP do perfil Internet e RSS global.
- Links oficiais de ferramentas e drivers. O aplicativo abre a página; a instalação continua sob acompanhamento do técnico.
- Registro de comandos/valores alterados, backup dos valores e tipos originais, verificação após cada escrita, reversão em falha e retomada da restauração de operações interrompidas.

As duas sugestões iniciais de preferências de jogos só são selecionadas quando seus valores ainda não estão configurados. Revise a captura caso o cliente use gravação de clipes. Não são uma previsão de ganho de FPS. Os demais ajustes ficam desmarcados.

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

O módulo Sistema oferece restrição reversível de atividade UWP. Desinstalação em massa de apps, exclusão de caches, bloqueio de Windows Update, desativação indiscriminada de serviços e offloads não estão implementados: não possuem reversão equivalente por um backup de Registro e exigem fluxos específicos. Windows Update permanece acessível pela área de ferramentas.

As referências foram estudadas, sem incorporar código de terceiros. Consulte [as decisões e fontes técnicas](docs/REFERENCIAS.md). Não há autenticação de técnicos: o perfil “Técnico GOAT” é identidade visual, e a autorização efetiva vem da sessão local do Windows.

## Build e distribuição

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Build.ps1
```

Saídas: `dist\GOAT-Tweaks.ps1` independente, `dist\GOAT-Tweaks.sha256` e `dist\GOAT-Tweaks-v2.2.zip`. O arquivo independente inclui scanner, engine e XAML, sem baixar dependências ou executar utilitários de terceiros. O transporte gerado é ASCII sem BOM, com recursos UTF-8 codificados em Base64 e decodificados em memória. Isso preserva os textos em português no `irm | iex` do PowerShell 5.1 mesmo quando o servidor não envia charset. O código legível de cada módulo está em `src/`.

O endereço publicado aponta diretamente para **o arquivo gerado**, que não depende dos arquivos locais de `src/`:

```powershell
irm 'https://raw.githubusercontent.com/JuliozXz/GOAT-Tweaks-V1/main/dist/GOAT-Tweaks.ps1' | iex
```

Execute esse comando no Windows PowerShell 5.1 x64. O endereço `main` acompanha futuras atualizações. Para uma distribuição auditável, use um commit específico no endereço e preserve o SHA256. O checksum acompanha o arquivo em `dist/GOAT-Tweaks.sha256`; a forma `irm | iex` não verifica o checksum automaticamente.

## Verificar sem aplicar tweaks

```powershell
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Core.ps1
powershell.exe -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-UI.ps1
```

Os testes da engine substituem as APIs de alteração e os checkpoints por simuladores em memória. O teste de UI usa demonstração para verificar navegação, gráfico, aplicação simulada e restauração simulada, e gera capturas em `artifacts\`. Testes não aplicam tweaks reais. O parâmetro `-RealReadOnly` verifica a UI com consultas reais, e `-Bundle` verifica a versão independente. Consulte [o relatório de validação](docs/VALIDACAO.md).
