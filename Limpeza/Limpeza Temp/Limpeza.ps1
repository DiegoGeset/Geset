# ============================================================
# Script: Execução Sequencial de Limpezas do Sistema (GitHub)
# Função: Baixa e executa utilitários de limpeza via repositório remoto
# Autor : Geset
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

# --- Repositório base (RAW)
$baseUrl = "https://raw.githubusercontent.com/DiegoGeset/Geset/main/Limpeza/Limpeza%20Temp"

# --- Caminho temporário para download
$tempDir = "$env:TEMP\GesetLimpeza"
if (-not (Test-Path $tempDir)) { New-Item -ItemType Directory -Path $tempDir | Out-Null }

# --- Função auxiliar para baixar e executar os arquivos
function Run-Tool($name, $file) {
    $remoteFile = "$baseUrl/$file"
    $localFile = Join-Path $tempDir $file

    Write-Host "[🔹] Baixando $name..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri $remoteFile -OutFile $localFile -UseBasicParsing -ErrorAction Stop
        Write-Host "[✔] Download concluído: $file" -ForegroundColor Green
    }
    catch {
        Write-Host "[❌] Falha ao baixar $file do GitHub" -ForegroundColor Red
        return
    }

    Write-Host "[🔹] Executando $name..." -ForegroundColor Yellow
    try {
        Start-Process -FilePath $localFile -Wait -ErrorAction Stop
        Write-Host "[✔] $name concluído com sucesso!" -ForegroundColor Green
    }
    catch {
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

# --- (Opcional) Limpeza dos arquivos baixados
# Remove-Item -Path $tempDir -Recurse -Force
