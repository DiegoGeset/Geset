# ============================================================
# Script: Execução Sequencial de Limpezas do Sistema
# Função: Executa utilitários de limpeza (Prefetch, Lixeira, Edge, Chrome)
# Autor: Geset
# Execução sempre visual
# ============================================================

# --- Caminho do diretório atual ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# --- Arquivo de log ---
$logFile = "$env:TEMP\LimpezaGeset.log"
function Write-Log { param($msg) Add-Content -Path $logFile -Value ("$(Get-Date -Format 'HH:mm:ss') - $msg"); Write-Host $msg }

# --- Configuração visual ---
$host.UI.RawUI.WindowTitle = "🧹 Utilitário de Limpeza do Sistema - Geset"
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "           🧹 UTILITÁRIO DE LIMPEZA DO SISTEMA              " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# --- Repositório no GitHub (RAW) ---
$baseURL = "https://raw.githubusercontent.com/DiegoGeset/Geset/main/Limpeza/Limpeza%20Temp"

# --- Lista de arquivos necessários ---
$arquivos = @(
    "LimpezaPrefetch.exe",
    "LimpezaLixeira.exe",
    "LimpezaEdge.exe",
    "LimpezaChrome.exe"
)

# --- Função: Verificar conexão com a internet ---
function Test-InternetConnection {
    try {
        $req = [System.Net.WebRequest]::Create("https://github.com")
        $req.Timeout = 3000
        $res = $req.GetResponse()
        $res.Close()
        return $true
    } catch {
        return $false
    }
}

# --- Função: Obter hash SHA256 de um arquivo ---
function Get-FileHashValue($filePath) {
    if (Test-Path $filePath) {
        return (Get-FileHash -Algorithm SHA256 -Path $filePath).Hash
    } else {
        return $null
    }
}

# --- Função: Obter hash remoto do GitHub ---
function Get-RemoteFileHash($url) {
    try {
        $bytes = (Invoke-WebRequest -Uri $url -UseBasicParsing).Content
        $stream = New-Object System.IO.MemoryStream
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Position = 0
        $hash = (Get-FileHash -Algorithm SHA256 -InputStream $stream).Hash
        $stream.Dispose()
        return $hash
    } catch {
        return $null
    }
}

# --- Verificação de conexão ---
$internetOk = Test-InternetConnection
if (-not $internetOk) {
    Write-Host "[⚠️] Sem conexão com a Internet. Verificação de atualização será ignorada." -ForegroundColor Yellow
} else {
    Write-Host "[🌐] Conexão com a Internet detectada." -ForegroundColor Cyan
}

# --- Baixa ou atualiza arquivos ---
foreach ($arquivo in $arquivos) {
    $caminhoLocal = Join-Path $scriptDir $arquivo
    $urlRemota = "$baseURL/" + [System.Uri]::EscapeDataString($arquivo)

    try {
        if (Test-Path $caminhoLocal) {
            Write-Host "[🔍] Verificando atualizações para $arquivo..." -ForegroundColor Yellow

            if ($internetOk) {
                $hashLocal = Get-FileHashValue $caminhoLocal
                $hashRemoto = Get-RemoteFileHash $urlRemota

                if ($hashRemoto -and $hashLocal -ne $hashRemoto) {
                    Write-Host "[⬆️] Atualização encontrada para $arquivo. Baixando nova versão..." -ForegroundColor Cyan
                    Invoke-WebRequest -Uri $urlRemota -OutFile $caminhoLocal -UseBasicParsing -ErrorAction Stop
                    Unblock-File -Path $caminhoLocal
                    Write-Host "[✔] $arquivo atualizado com sucesso!" -ForegroundColor Green
                } else {
                    Write-Host "[✔] $arquivo está atualizado." -ForegroundColor Green
                }
            } else {
                Write-Host "[⚠️] Sem internet. Não foi possível verificar atualização de $arquivo." -ForegroundColor Yellow
            }
        } else {
            Write-Host "[⬇️] Arquivo não encontrado localmente: $arquivo" -ForegroundColor Yellow
            if ($internetOk) {
                Write-Host "[🌐] Baixando de: $urlRemota" -ForegroundColor Cyan
                Invoke-WebRequest -Uri $urlRemota -OutFile $caminhoLocal -UseBasicParsing -ErrorAction Stop
                Unblock-File -Path $caminhoLocal
                Write-Host "[✔] $arquivo baixado com sucesso!" -ForegroundColor Green
            } else {
                Write-Host "[❌] Não foi possível baixar $arquivo sem conexão." -ForegroundColor Red
            }
        }
    } catch {
        Write-Host "[❌] Falha ao processar $arquivo. Detalhe:" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkGray
    }

    Start-Sleep -Milliseconds 500
}

# --- Garante que os arquivos estejam desbloqueados ---
Get-ChildItem $scriptDir -Filter "*.exe" | ForEach-Object {
    try { Unblock-File -Path $_.FullName } catch {}
}

# --- Função auxiliar para executar ferramentas .exe ---
function Run-Tool($name, $file) {
    Write-Host "[🔹] Executando $name..." -ForegroundColor Yellow
    try {
        $fullPath = Join-Path $scriptDir $file
        if (-not (Test-Path $fullPath)) {
            Write-Host "[❌] Arquivo não encontrado: $file" -ForegroundColor Red
            return
        }

        # Executa e aguarda término (garantido)
        $proc = Start-Process -FilePath $fullPath -Wait -PassThru -ErrorAction Stop
        if ($proc.ExitCode -eq 0) {
            Write-Host "[✔] $name concluído com sucesso!" -ForegroundColor Green
        } else {
            Write-Host "[⚠️] $name terminou com código $($proc.ExitCode)." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "[❌] Falha ao executar $name ($file)" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkGray
    }
    Start-Sleep -Seconds 1
}

# --- Execução das ferramentas ---
Run-Tool "Limpeza de Prefetch" "LimpezaPrefetch.exe"
Run-Tool "Limpeza da Lixeira" "LimpezaLixeira.exe"
Run-Tool "Limpeza do Edge" "LimpezaEdge.exe"
Run-Tool "Limpeza do Chrome" "LimpezaChrome.exe"

# --- Conclusão ---
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "🎉 Todas as limpezas foram concluídas com sucesso!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Pressione [ENTER] para fechar o utilitário..." -ForegroundColor Yellow
Read-Host
