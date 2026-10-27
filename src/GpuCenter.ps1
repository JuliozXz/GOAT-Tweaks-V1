# Goat two X V1 - GPU Center (fase 1: diagnóstico, sem mutações).
# Compatível com Windows PowerShell 5.1; não instala drivers nem executa DDU.
function Get-GoatGpuCenter {
    [CmdletBinding()]
    param([switch]$Demo)
    if ($Demo) {
        return [pscustomobject]@{
            Status = 'DEMO'; ReadOnly = $true
            Devices = @([pscustomobject]@{ Name='NVIDIA GeForce RTX 4070 SUPER (exemplo)'; Vendor='NVIDIA'; DriverVersion='Exemplo'; DriverDate=$null; PnpDeviceId='DEMO'; AdapterRAMGB=$null; DriverSource='https://www.nvidia.com/Download/index.aspx' })
            Recommendations = @('Conferir driver oficial e comparar FPS/frametime em cenário idêntico.')
            Warnings = @('Amostra demonstrativa; sem instalação nem telemetria real.')
        }
    }
    $warnings = New-Object 'System.Collections.Generic.List[string]'
    $devices = @()
    try {
        $controllers = @(Get-CimInstance -ClassName Win32_VideoController -OperationTimeoutSec 8 -ErrorAction Stop)
    } catch {
        $controllers = @()
        $warnings.Add(('Inventário de GPU indisponível: {0}' -f $_.Exception.Message))
    }
    foreach ($gpu in $controllers) {
        $vendor = 'Desconhecido'
        $url = $null
        $pnp = [string]$gpu.PNPDeviceID
        if ($pnp -match 'VEN_10DE' -or $gpu.Name -match 'NVIDIA') {
            $vendor = 'NVIDIA'; $url = 'https://www.nvidia.com/Download/index.aspx'
        } elseif ($pnp -match 'VEN_1002' -or $gpu.Name -match 'AMD|Radeon') {
            $vendor = 'AMD'; $url = 'https://www.amd.com/en/support/download/drivers.html'
        } elseif ($pnp -match 'VEN_8086' -or $gpu.Name -match 'Intel') {
            $vendor = 'Intel'; $url = 'https://www.intel.com/content/www/us/en/download-center/home.html'
        }
        $ram = $null
        if ($gpu.AdapterRAM -and [uint64]$gpu.AdapterRAM -gt 0) {
            # Win32_VideoController.AdapterRAM pode truncar em GPUs modernas.
            $warnings.Add(('VRAM WMI de {0} não é uma medida confiável para GPUs modernas.' -f $gpu.Name))
        }
        $devices += [pscustomobject]@{
            Name = [string]$gpu.Name
            Vendor = $vendor
            DriverVersion = [string]$gpu.DriverVersion
            DriverDate = [string]$gpu.DriverDate
            PnpDeviceId = $pnp
            AdapterRAMGB = $ram
            DriverSource = $url
        }
    }
    if ($devices.Count -eq 0) { $warnings.Add('Nenhuma GPU foi identificada com confiança.') }
    return [pscustomobject]@{
        Status = if ($devices.Count -gt 0) { 'INVENTORY_ONLY' } else { 'UNAVAILABLE' }
        ReadOnly = $true
        Devices = @($devices)
        Recommendations = @(
            'Baixe drivers somente da fonte oficial e confirme modelo e versão manualmente.',
            'Reinstalação limpa/DDU requer backup, consentimento e plano de recuperação local; nunca no lote automático.',
            'Perfis de baixa latência, sincronização, HAGS e VRR dependem do jogo, monitor, driver e evidência de benchmark.'
        )
        Warnings = @($warnings.ToArray())
    }
}
