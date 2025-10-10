# ======================================================
# Script: Limpeza Completa de Cache DNS
# Função: Garante execução como Administrador e realiza
#         limpeza via ipconfig + Clear-DnsClientCache
# Autor: Diego Geset
# ======================================================

# --- Função: Garantir execução como Administrador
function Ensure-RunAsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Reiniciando script como Administrador..." -ForegroundColor Yellow
        Start-Process powershell -Verb RunAs -ArgumentList ('-ExecutionPolicy Bypass -File "' + $MyInvocation.MyCommand.Definition + '"')
        exit
    }
}

# --- Garante privilégios administrativos
Ensure-RunAsAdministrator

# --- Cabeçalho visual
Clear-Host
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host "      LIMPEZA COMPLETA DE CACHE DNS       " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host ""

# --- Limpeza via ipconfig /flushdns
try {
    Write-Host "Executando limpeza via CMD (ipconfig /flushdns)..." -ForegroundColor Yellow
    ipconfig /flushdns | Out-Null
    Write-Host "✅ Limpeza via ipconfig concluída com sucesso!" -ForegroundColor Green
} catch {
    Write-Host "❌ Falha ao executar ipconfig /flushdns:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

Write-Host ""

# --- Limpeza via PowerShell (Clear-DnsClientCache)
try {
    Write-Host "Executando limpeza via PowerShell (Clear-DnsClientCache)..." -ForegroundColor Yellow
    Clear-DnsClientCache
    Write-Host "✅ Limpeza via Clear-DnsClientCache concluída com sucesso!" -ForegroundColor Green
} catch {
    Write-Host "❌ Falha ao executar Clear-DnsClientCache:" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}

# --- Finalização
Write-Host ""
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host " Todas as etapas de limpeza foram concluídas " -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor DarkCyan
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
exit
