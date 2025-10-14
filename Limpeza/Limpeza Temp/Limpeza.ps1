# ============================================================
# Script: Execução Sequencial de Limpezas do Sistema
# Função: Executa utilitários de limpeza (Prefetch, Lixeira, Edge, Chrome)
# Autor: Geset
# Execução sempre visível
# ============================================================

# --- Caminho do diretório atual ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition

# --- Arquivo de log ---
$logFile = "$env:TEMP\LimpezaGeset.log"
function Write-Log { param($msg) Add-Content -Path $logFile -Value ("$(Get-Date -Format 'HH:mm:ss') - $msg"); Write-Host $msg }

# --- Verifica se está rodando como administrador ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "[⚙️] Elevando permissões para Administrador..."
    # Sempre abrir visível
    Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -NoExit -File `"$PSCommandPath`"" -Verb RunAs
    exit
} else {
    Write-Log "[✔] Já executando como Administrador."
}

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

# --- Função: Obter hash remoto do GitHub (binário) ---
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
if (-not (Test-InternetConnection)) {
    Write-Host "[⚠️] Sem conexão com a Internet. Verificação de atualização será ignorada." -ForegroundColor Yellow
} else {
    Write-Host "[🌐] Conexão com a Internet detectada." -ForegroundColor Cyan
}

# --- Verifica e baixa/atualiza arquivos necessários ---
foreach ($arquivo in $arquivos) {
    $caminhoLocal = Join-Path $scriptDir $arquivo
    $urlRemota = "$baseURL/" + [System.Uri]::EscapeDataString($arquivo)

    if (Test-Path $caminhoLocal) {
        Write-Host "[🔍] Verificando atualizações para $arquivo..." -ForegroundColor Yellow

        if (Test-InternetConnection) {
            $hashLocal = Get-FileHashValue $caminhoLocal
            $hashRemoto = Get-RemoteFileHash $urlRemota

            if ($hashRemoto -and $hashLocal -ne $hashRemoto) {
                Write-Host "[⬆️] Atualização encontrada para $arquivo. Baixando nova versão..." -ForegroundColor Cyan
                try {
                    Invoke-WebRequest -Uri $urlRemota -OutFile $caminhoLocal -UseBasicParsing
                    Unblock-File -Path $caminhoLocal
                    Write-Host "[✔] $arquivo atualizado com sucesso!" -ForegroundColor Green
                } catch {
                    Write-Host "[❌] Falha ao atualizar $arquivo." -ForegroundColor Red
                }
            } else {
                Write-Host "[✔] $arquivo está atualizado." -ForegroundColor Green
            }
        } else {
            Write-Host "[⚠️] Sem internet. Não foi possível verificar atualização de $arquivo." -ForegroundColor Yellow
        }
    } else {
        Write-Host "[⬇️] Arquivo não encontrado: $arquivo" -ForegroundColor Yellow
        if (Test-InternetConnection) {
            Write-Host "[🌐] Baixando de: $urlRemota" -ForegroundColor Cyan
            try {
                Invoke-WebRequest -Uri $urlRemota -OutFile $caminhoLocal -UseBasicParsing
                Unblock-File -Path $caminhoLocal
                Write-Host "[✔] $arquivo baixado com sucesso!" -ForegroundColor Green
            } catch {
                Write-Host "[❌] Falha ao baixar $arquivo. Verifique o link no GitHub." -ForegroundColor Red
            }
        } else {
            Write-Host "[❌] Não foi possível baixar $arquivo sem conexão com a Internet." -ForegroundColor Red
        }
    }

    Start-Sleep -Milliseconds 500
}

# --- Desbloqueia todos os executáveis ---
Get-ChildItem $scriptDir\*.exe | ForEach-Object { Unblock-File -Path $_.FullName }

# --- Função auxiliar para executar ferramentas .exe ---
function Run-Tool($name, $file) {
    Write-Host "[🔹] Executando $name..." -ForegroundColor Yellow
    try {
        $fullPath = Join-Path $scriptDir $file
        if (-not (Test-Path $fullPath)) {
            Write-Host "[❌] Arquivo não encontrado: $file" -ForegroundColor Red
            return
        }

        # Executa o programa e aguarda término
        $process = Start-Process -FilePath $fullPath -PassThru -ErrorAction Stop
        $process.WaitForExit()

        Write-Host "[✔] $name concluído com sucesso!" -ForegroundColor Green
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
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "🎉 Todas as limpezas foram concluídas com sucesso!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

# --- Mantém a janela aberta ---
Write-Host ""
Write-Host "Pressione [ENTER] para fechar o utilitário..." -ForegroundColor Yellow
Read-Host
