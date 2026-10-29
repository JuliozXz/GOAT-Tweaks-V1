# Fontes e avisos

O código desta aplicação foi escrito do zero para a solicitação atual. Nenhum executável, driver, asset, script ou módulo dos projetos Ultimate, WinSux, EXM, Winutil, RyTuneX ou RESET EXPLODE foi incorporado como executor. O aplicativo antigo GOAT-Tweaks-V1 e seu PR #1 foram consultados para entender a origem do pacote; seu código e logo não foram reutilizados.

`data/catalog.json` e `data/documents.json` reproduzem material do pacote fornecido pelo usuário como referência documental. Os avisos e referências originais permanecem na biblioteca do aplicativo, incluindo o documento `05_LICENCAS_E_TERCEIROS/THIRD_PARTY_NOTICES.md`. Hashes e proveniência ficam em `docs/audit/`. A importação não confirma a licença de projetos citados nem autoriza redistribuir seus binários.

Fontes técnicas oficiais usadas na implementação:

- [Microsoft RegistryKey.GetValue](https://learn.microsoft.com/en-us/dotnet/api/microsoft.win32.registrykey.getvalue): leitura exata, incluindo ExpandString sem expansão.
- [Microsoft Windows Settings URIs](https://learn.microsoft.com/en-us/windows/apps/develop/launch/launch-settings): localização de configurações assistidas.
- [NVIDIA Drivers](https://www.nvidia.com/en-us/drivers/), [AMD Drivers](https://www.amd.com/en/support/download/drivers.html), [Intel Download Center](https://www.intel.com/content/www/us/en/download-center/home.html): fontes de driver, sem consulta automática da última versão.
- [PresentMon](https://github.com/GameTechDev/PresentMon): ferramenta externa de captura de dados; não é baixada, instalada ou incluída pelo app.

O runtime usado é o Windows PowerShell/.NET/WPF fornecido pelo Windows. Não há dependência PowerShell Gallery, Python, Node ou biblioteca de sensor redistribuída. A assinatura digital do bundle e a política de licença do código novo cabem ao proprietário antes de uma distribuição comercial.
