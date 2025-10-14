# ================================================
# Script: Verificar e (opcionalmente) Desinstalar Aplicativo
# Uso: Execute pelo run-elevado.bat para garantir elevação
# Observação: Resposta para desinstalar deve ser S ou N (aceita maiúscula/minúscula)
# ================================================

# -------------------------
# CONFIGURÁVEL: nome do app
# -------------------------
# Você pode usar partes do nome, por exemplo "OneDrive" ou "Microsoft.OneDrive"
$appName = "OneDrive"

Write-Host ""
Write-Host "🔍 Verificando se o aplicativo '$appName' está instalado..." -ForegroundColor Cyan
Write-Host "-----------------------------------------------------------"

# --------------------------------------
# 1) Procura por AppxPackage (Microsoft Store / UWP)
# --------------------------------------
$appx = Get-AppxPackage -Name "*$appName*" -ErrorAction SilentlyContinue

# --------------------------------------
# 2) Procura por programas instalados via "Programas e Recursos" (registro)
#    Pesquisa em HKLM (64-bit e 32-bit) e HKCU
# --------------------------------------
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
    "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
)

$regMatches = @()
foreach ($path in $regPaths) {
    try {
        $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
                 Where-Object { $_.DisplayName -and ($_.DisplayName -like "*$appName*") }
        if ($items) {
            $regMatches += $items
        }
    }
    catch { }
}

# Remove duplicatas (por segurança)
if ($regMatches.Count -gt 1) {
    $regMatches = $regMatches | Sort-Object DisplayName -Unique
}

# --------------------------------------
# Decisão: app encontrado?
# --------------------------------------
if ($appx -or $regMatches.Count -gt 0) {
    Write-Host "`n✅ Aplicativo encontrado:" -ForegroundColor Green

    if ($appx) {
        foreach ($a in $appx) {
            Write-Host " - Appx: $($a.Name)  (PackageFullName: $($a.PackageFullName))"
        }
    }

    if ($regMatches.Count -gt 0) {
        foreach ($r in $regMatches) {
            Write-Host " - Registro: $($r.DisplayName)  (UninstallString: $($r.UninstallString))"
        }
    }

    Write-Host "-----------------------------------------------------------"

    # Validação da escolha: só aceita S ou N (maiúsculo/minúsculo)
    do {
        $escolha = Read-Host "Deseja desinstalar o(s) item(s) encontrado(s)? (S/N)"
        if (-not ($escolha -match '^[sSnN]$')) {
            Write-Host "Entrada inválida. Digite 'S' para SIM ou 'N' para NÃO." -ForegroundColor Yellow
        }
    } until ($escolha -match '^[sSnN]$')

    if ($escolha -match '^[sS]$') {
        # Desinstala Appx (cada pacote encontrado)
        if ($appx) {
            foreach ($a in $appx) {
                Write-Host "`n🔧 Desinstalando AppxPackage: $($a.Name)" -ForegroundColor Yellow
                try {
                    Remove-AppxPackage -Package $a.PackageFullName -ErrorAction Stop
                    Write-Host "✅ Removido: $($a.Name)" -ForegroundColor Green
                }
                catch {
                    Write-Host "❌ Falha ao remover AppxPackage: $($a.Name)" -ForegroundColor Red
                    Write-Host $_.Exception.Message
                }
            }
        }

        # Desinstala por UninstallString (registro)
        if ($regMatches.Count -gt 0) {
            foreach ($r in $regMatches) {
                $display = $r.DisplayName
                $uninstallString = $r.UninstallString

                if (-not $uninstallString) {
                    Write-Host "⚠️  Não foi encontrada UninstallString para $display. Pulei." -ForegroundColor Yellow
                    continue
                }

                Write-Host "`n🔧 Tentando desinstalar: $display" -ForegroundColor Yellow
                Write-Host "Comando: $uninstallString"

                try {
                    # Alguns UninstallString já são completos (ex.: "MsiExec.exe /X{GUID} /qn")
                    # Vamos executar via cmd /c para aceitar formatos variados.
                    Start-Process -FilePath "cmd.exe" -ArgumentList "/c", $uninstallString -Wait -NoNewWindow
                    Write-Host "✅ Execução do uninstall para '$display' finalizada." -ForegroundColor Green
                }
                catch {
                    Write-Host "❌ Erro ao executar uninstall para '$display'." -ForegroundColor Red
                    Write-Host $_.Exception.Message
                }
            }
        }

        Write-Host "`n✅ Processo de desinstalação finalizado (verifique logs/saídas acima)." -ForegroundColor Green
    }
    else {
        Write-Host "`nℹ Aplicativo será mantido no sistema." -ForegroundColor Cyan
    }
}
else {
    Write-Host "`n❌ O aplicativo '$appName' não foi encontrado neste sistema." -ForegroundColor Red
    Write-Host "Verifique o nome em \$appName no topo do script ou confirme se o programa está instalado."
}

Write-Host "-----------------------------------------------------------"
Read-Host "`nPressione Enter para encerrar..."
