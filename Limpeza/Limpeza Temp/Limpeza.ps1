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

# --- Caminho do diretório atual
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# --- Repositório no GitHub (RAW)
$baseURL = "https://raw.githubusercontent.com/DiegoGeset/Geset/refs/heads/main/Limpeza/Limpeza%20Temp"

# --- Lista de arquivos necessários
$arquivos = @(
    "LimpezaPrefetch.exe",
    "LimpezaLixeira.exe",
    "LimpezaEdge.exe",
    "LimpezaChrome.exe"
)

# --- Verifica e baixa arquivos ausentes
foreach ($arquivo in $arquivos) {
    $caminhoLocal = Join-Path $scriptDir $arquivo
    if (-not (Test-Path $caminhoLocal)) {
        Write-Host "[⬇️] Arquivo não encontrado: $arquivo" -ForegroundColor Yellow
        Write-Host "[🌐] Baixando de: $baseURL/$arquivo" -ForegroundColor Cyan
        try {
            Invoke-WebRequest -Uri "$baseURL/$arquivo" -OutFile $caminhoLocal -UseBasicParsing
            Write-Host "[✔] $arquivo baixado com sucesso!" -ForegroundColor Green
        } catch {
            Write-Host "[❌] Falha ao baixar $arquivo. Verifique o link no GitHub." -ForegroundColor Red
        }
    } else {
        Write-Host "[✔] $arquivo já existe localmente." -ForegroundColor Green
    }
}

Write-Host ""
Start-Sleep -Seconds 1

# --- Função auxiliar para executar ferramentas
function Run-Tool($name, $file) {
    Write-Host "[🔹] Executando $name..." -ForegroundColor Yellow
    try {
        Start-Process -FilePath "$scriptDir\$file" -Wait -ErrorAction Stop
        Write-Host "[✔] $name concluído com sucesso!" -ForegroundColor Green
    } catch {
        Write-Host "[❌] Falha ao executar $name ($file)" -ForegroundColor Red
    }
    Write-Host ""
    Start-Sleep -Seconds 1
}

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
