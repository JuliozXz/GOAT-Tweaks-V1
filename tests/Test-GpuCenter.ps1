# Teste de contrato somente leitura para Windows PowerShell 5.1
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\GpuCenter.ps1')
$demo = Get-GoatGpuCenter -Demo
if (-not $demo.ReadOnly -or $demo.Status -ne 'DEMO') { throw 'Modo demo inseguro' }
if (@($demo.Devices).Count -ne 1) { throw 'Inventário demo incompleto' }
if (-not @($demo.Devices)[0].DriverSource.StartsWith('https://www.nvidia.com/')) { throw 'Fonte demo não oficial' }
Write-Output 'GPU Center: contrato de demonstração validado.'
