# ============================================================
# Script: GESET Launcher - Limpeza e Otimização do Sistema
# Autor: Diego Geset
# Função: Executa utilitários de limpeza, atualizações e scripts de otimização
# ============================================================

# --- Verifica se está em modo Administrador ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("O Launcher precisa ser executado como Administrador.`nEle será reiniciado com permissões elevadas.", "Permissão necessária", "OK", "Warning")
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "powershell.exe"
    $psi.Arguments = "-ExecutionPolicy Bypass -File `"$PSCommandPath`""
    $psi.Verb = "runas"
    [System.Diagnostics.Process]::Start($psi) | Out-Null
    exit
}

# --- Configuração visual ---
$host.UI.RawUI.WindowTitle = "🧹 GESET Launcher - Limpeza e Otimização"
Clear-Host
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "           🧹 GESET LAUNCHER - SISTEMA                      " -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# --- Diretórios locais e log ---
$LocalCache = "C:\Geset"
$LogPath = Join-Path $LocalCache "Logs"
$LogFile = Join-Path $LogPath "Launcher.log"

if (-not (Test-Path $LocalCache)) { New-Item -Path $LocalCache -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

function Write-Log { param([string]$msg) "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`t$msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8 }

Write-Log "Launcher iniciado."

# --- Repositório GitHub ---
$RepoOwner = "DiegoGeset"
$RepoName = "Geset"
$Branch = "main"
$GitHubRawBase = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"
$Global:GitHubHeaders = @{ 'User-Agent' = 'GESET-Launcher' }

# --- Função: Testa conexão com a Internet ---
function Test-InternetConnection {
    try {
        $req = [System.Net.WebRequest]::Create("https://github.com")
        $req.Timeout = 3000
        $res = $req.GetResponse()
        $res.Close()
        return $true
    } catch { return $false }
}

# --- Função: Obtém hash SHA256 de arquivo local ---
function Get-FileHashValue($filePath) {
    if (Test-Path $filePath) {
        return (Get-FileHash -Algorithm SHA256 -Path $filePath).Hash
    } else { return $null }
}

# --- Função: Obtém hash SHA256 de arquivo remoto ---
function Get-RemoteFileHash($url) {
    try {
        $bytes = (Invoke-WebRequest -Uri $url -UseBasicParsing -Headers $Global:GitHubHeaders).Content
        $stream = New-Object System.IO.MemoryStream
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Position = 0
        $hash = (Get-FileHash -Algorithm SHA256 -InputStream $stream).Hash
        $stream.Dispose()
        return $hash
    } catch { return $null }
}

# --- Atualiza JSON de estrutura ---
$StructureJsonLocal = Join-Path $LocalCache "structure.json"
$StructureJsonRemote = "$GitHubRawBase/structure.json"
try {
    Invoke-WebRequest -Uri $StructureJsonRemote -OutFile $StructureJsonLocal -UseBasicParsing -Headers $Global:GitHubHeaders -ErrorAction Stop
    Write-Log "JSON atualizado com sucesso."
} catch {
    Write-Log "Falha ao baixar JSON: $($_.Exception.Message)"
    if (-not (Test-Path $StructureJsonLocal)) {
        [System.Windows.MessageBox]::Show("Não foi possível obter o arquivo JSON do GitHub.", "Erro", "OK", "Error")
        exit
    }
}

# --- Lê JSON ---
try { $StructureList = Get-Content $StructureJsonLocal -Raw | ConvertFrom-Json } catch { $StructureList = @() }

# --- Garante estrutura local ---
foreach ($entry in $StructureList) {
    $localDir = Join-Path $LocalCache ($entry.categoria + "\" + $entry.subpasta)
    if (-not (Test-Path $localDir)) { New-Item -Path $localDir -ItemType Directory -Force | Out-Null }
}

# --- Função: Baixa ou atualiza scripts/executáveis ---
function Ensure-File($LocalPath, $RemoteUrl) {
    if (Test-Path $LocalPath) {
        $localHash = Get-FileHashValue $LocalPath
        $remoteHash = Get-RemoteFileHash $RemoteUrl
        if ($remoteHash -and $localHash -ne $remoteHash) {
            try {
                Invoke-WebRequest -Uri $RemoteUrl -OutFile $LocalPath -UseBasicParsing -Headers $Global:GitHubHeaders
                Unblock-File -Path $LocalPath
                Write-Log "Atualizado: $LocalPath"
            } catch { Write-Log "Falha ao atualizar: $LocalPath" }
        }
    } else {
        try {
            Invoke-WebRequest -Uri $RemoteUrl -OutFile $LocalPath -UseBasicParsing -Headers $Global:GitHubHeaders
            Unblock-File -Path $LocalPath
            Write-Log "Baixado: $LocalPath"
        } catch { Write-Log "Falha ao baixar: $LocalPath" }
    }
}

# --- Lista de utilitários de limpeza ---
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$Executaveis = @(
    "LimpezaPrefetch.exe",
    "LimpezaLixeira.exe",
    "LimpezaEdge.exe",
    "LimpezaChrome.exe"
)
$BaseURL = "$GitHubRawBase/Limpeza/Limpeza%20Temp"

# --- Baixa e garante arquivos ---
foreach ($exe in $Executaveis) {
    $localExe = Join-Path $ScriptDir $exe
    $remoteExe = "$BaseURL/$exe"
    Ensure-File -LocalPath $localExe -RemoteUrl $remoteExe
}

# --- Função: Executa ferramentas .exe ---
function Run-Tool($name, $file) {
    Write-Host "[🔹] Executando $name..." -ForegroundColor Yellow
    try {
        $fullPath = Join-Path $ScriptDir $file
        if (-not (Test-Path $fullPath)) {
            Write-Host "[❌] Arquivo não encontrado: $file" -ForegroundColor Red
            return
        }
        Unblock-File -Path $fullPath
        $proc = Start-Process -FilePath $fullPath -PassThru -ErrorAction Stop
        $proc.WaitForExit()
        Write-Host "[✔] $name concluído!" -ForegroundColor Green
    } catch {
        Write-Host "[❌] Falha ao executar $name" -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor DarkGray
    }
    Start-Sleep -Seconds 1
}

# --- Execução das limpezas ---
Run-Tool "Limpeza de Prefetch" "LimpezaPrefetch.exe"
Run-Tool "Limpeza da Lixeira" "LimpezaLixeira.exe"
Run-Tool "Limpeza do Edge" "LimpezaEdge.exe"
Run-Tool "Limpeza do Chrome" "LimpezaChrome.exe"

# --- Conclusão ---
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "🎉 Todas as limpezas foram concluídas com sucesso!" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan

# --- Aguarda Enter sem reiniciar script ---
Write-Host ""
Write-Host "Pressione [ENTER] para sair..."
[void][System.Console]::ReadLine()
