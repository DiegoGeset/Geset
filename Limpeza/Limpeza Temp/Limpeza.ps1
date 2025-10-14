# ============================================================
# Script: Execução Sequencial de Limpezas do Sistema
# Função: Executa utilitários de limpeza (Prefetch, Lixeira, Edge, Chrome)
# Autor: Geset
# ============================================================

# --- Verifica se está rodando como administrador
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n[⚙️] Elevando permissões para Administrador..." -ForegroundColor Yellow
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# --- Configuração visual
$host.UI.RawUI.WindowTitle = "🧹 Utilitário de Limpeza do Sistema - Geset"
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "           🧹 UTILITÁRIO DE LIMPEZA DO SISTEMA              " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# --- Caminho do diretório atual (onde o script está)
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# --- Função auxiliar para exibir status
function Run-Tool($name, $file) {
    Write-Host "[🔹] Executando $name..." -ForegroundColor Yellow
    try {
        Start-Process -FilePath "$scriptDir\$file" -Wait -ErrorAction Stop
        Write-Host "[✔] $name concluído com sucesso!" -ForegroundColor Green
    }
    catch {
        Write-Host "[❌] Falha ao executar $name ($file)" -ForegroundColor Red
    }
    Write-Host ""
    Start-Sleep -Seconds 1
} # <--- Aqui fecha corretamente a função (nenhum '}' a mais depois disso!)

# --- Execução das ferramentas
Run-Tool "Limpeza de Prefetch" "LimpezaPrefetch.exe"
Run-Tool "Limpeza da Lixeira" "LimpezaLixeira.exe"
Run-Tool "Limpeza do Edge" "LimpezaEdge.exe"
Run-Tool "Limpeza do Chrome" "LimpezaChrome.exe"

# --- Conclusão
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "🎉 Todas as limpezas foram concluídas com sucesso!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "Pressione [ENTER] para sair"
