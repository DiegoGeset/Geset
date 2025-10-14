# ================================================
# Script: Verificação de Integridade do Sistema
# Função: Executar "sfc /scannow" como administrador
# ================================================

# --- Função para garantir execução como Administrador
function Ensure-RunAsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Reiniciando o script como Administrador..." -ForegroundColor Yellow
        Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}

# --- Chamar função para garantir privilégios administrativos
Ensure-RunAsAdministrator

# --- Exibir título
Clear-Host
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host "   VERIFICAÇÃO DE INTEGRIDADE DO SISTEMA (SFC)" -ForegroundColor Green
Write-Host "===============================================" -ForegroundColor Cyan
Write-Host ""

# --- Executar o comando SFC /scannow
Write-Host "Iniciando a verificação do sistema..." -ForegroundColor Yellow
Start-Sleep -Seconds 2

# Executar o comando e capturar a saída
$sfcProcess = Start-Process cmd.exe -ArgumentList "/c sfc /scannow" -Wait -NoNewWindow -PassThru

Write-Host ""
Write-Host "-----------------------------------------------"
Write-Host "Verificação concluída." -ForegroundColor Green
Write-Host "-----------------------------------------------"

# --- Exibir mensagem final
Write-Host ""
Write-Host "Caso erros tenham sido encontrados e corrigidos," -ForegroundColor Yellow
Write-Host "recomenda-se reiniciar o computador." -ForegroundColor Yellow
Write-Host ""
Pause
