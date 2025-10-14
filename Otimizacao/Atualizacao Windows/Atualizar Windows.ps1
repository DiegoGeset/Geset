# ============================================================
# Script: Atualizar-Windows.ps1
# Função: Lista e instala atualizações do Windows de forma automática
# Autor: Diego Geset
# Compatibilidade: Windows 10, 11, Server 2016+
# ============================================================

# --- Garante execução como Administrador ---
function Ensure-RunAsAdministrator {
    $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host "Reiniciando como Administrador..." -ForegroundColor Yellow
        Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
        exit
    }
}
Ensure-RunAsAdministrator

# --- Instala o módulo PSWindowsUpdate, se necessário ---
if (-not (Get-Module -ListAvailable -Name PSWindowsUpdate)) {
    Write-Host "Instalando módulo PSWindowsUpdate..." -ForegroundColor Cyan
    Install-PackageProvider -Name NuGet -Force -Confirm:$false | Out-Null
    Install-Module -Name PSWindowsUpdate -Force -Confirm:$false
}

Import-Module PSWindowsUpdate

# --- Adiciona Microsoft Update (inclui Office, Defender etc.) ---
Add-WUServiceManager -MicrosoftUpdate -Confirm:$false | Out-Null

# --- Lista as atualizações disponíveis ---
Write-Host "`nVerificando atualizações disponíveis..." -ForegroundColor Cyan
$updates = Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot

if ($updates) {
    Write-Host "`nForam encontradas $($updates.Count) atualizações:" -ForegroundColor Yellow
    $updates | Select-Object -Property KB, Title | Format-Table -AutoSize

    Write-Host "`nIniciando a instalação das atualizações..." -ForegroundColor Cyan
    Install-WindowsUpdate -MicrosoftUpdate -AcceptAll -IgnoreReboot -Verbose

    Write-Host "`n✅ Atualizações instaladas com sucesso!" -ForegroundColor Green
    Write-Host "Reinicie o computador se necessário." -ForegroundColor Cyan
} else {
    Write-Host "`nNenhuma atualização encontrada. O sistema está atualizado!" -ForegroundColor Green
}

pause
