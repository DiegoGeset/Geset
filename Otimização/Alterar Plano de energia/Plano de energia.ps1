# ================================================
#  SCRIPT DE CONFIGURAÇÃO DE PLANO DE ENERGIA
#  Layout aprimorado e compatível com qualquer ambiente
# ================================================

Clear-Host

# --- Cabeçalho visual
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║        CONFIGURAÇÃO DE PLANO DE ENERGIA          ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# --- Função utilitária
function Executar-Comando {
    param (
        [string]$Comando,
        [string]$Mensagem
    )

    Write-Host "➡ $Mensagem" -ForegroundColor Yellow
    Start-Sleep -Milliseconds 400
    try {
        Invoke-Expression $Comando | Out-Null
        Write-Host "   ✔ Concluído!" -ForegroundColor Green
    }
    catch {
        Write-Host "   ✖ Erro ao executar o comando!" -ForegroundColor Red
    }
    Write-Host ""
    Start-Sleep -Milliseconds 200
}

# --- Etapa 1: Configuração de energia
Write-Host "──────────────────────────────────────────────" -ForegroundColor DarkCyan
Write-Host " ETAPA 1 → APLICANDO CONFIGURAÇÕES DE ENERGIA " -ForegroundColor Cyan
Write-Host "──────────────────────────────────────────────" -ForegroundColor DarkCyan
Write-Host ""

Executar-Comando "powercfg -restoredefaultschemes"        "Restaurando plano de energia padrão"
Executar-Comando "powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c" "Ativando plano: Alto Desempenho"
Executar-Comando "powercfg /change standby-timeout-ac 0"  "Desativando suspensão (fonte)"
Executar-Comando "powercfg /change monitor-timeout-ac 0"  "Desativando desligamento do vídeo (fonte)"
Executar-Comando "powercfg /change disk-timeout-ac 0"     "Desativando desligamento do disco (fonte)"
Executar-Comando "powercfg /change disk-timeout-dc 0"     "Desativando desligamento do disco (bateria)"
Executar-Comando "powercfg /change standby-timeout-dc 0"  "Desativando suspensão (bateria)"
Executar-Comando "powercfg /change monitor-timeout-dc 0"  "Desativando desligamento do vídeo (bateria)"

# --- Finalização
Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host " ✔ TODAS AS CONFIGURAÇÕES FORAM APLICADAS     " -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Pressione ENTER para fechar..." -ForegroundColor Yellow

try {
    # Compatível com consoles e ambientes gráficos
    [void][System.Console]::ReadLine()
} catch {
    # Caso o ambiente não suporte interação
    Start-Sleep -Seconds 3
}
