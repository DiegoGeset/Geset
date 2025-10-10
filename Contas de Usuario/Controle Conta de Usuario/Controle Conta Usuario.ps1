# ==========================================================
# Script: Gerenciador de Contas Locais
# Função: Permite habilitar ou desabilitar usuários locais
#         com menu interativo e verificação de privilégios.
# ==========================================================

# --- Garante que o script está sendo executado como administrador ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "`n⚠️  Este script requer privilégios de administrador." -ForegroundColor Yellow
    Write-Host "Reiniciando com privilégios elevados..." -ForegroundColor Cyan

    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile", "-ExecutionPolicy Bypass", "-File `"$($MyInvocation.MyCommand.Path)`""
    exit
}

# --- Função: Listar e desativar usuários ---
function Disable-User {
    $Users = Get-LocalUser | Where-Object { $_.Enabled -eq $true } | Sort-Object Name

    if ($Users.Count -eq 0) {
        Write-Host "`n✅ Nenhum usuário ativo encontrado." -ForegroundColor Green
        return
    }

    Write-Host "`n===== USUÁRIOS ATIVOS =====" -ForegroundColor Cyan
    for ($i = 0; $i -lt $Users.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $Users[$i].Name) -ForegroundColor Yellow
    }

    $choice = Read-Host "`nDigite o número do usuário que deseja desativar"
    if (-not ($choice -as [int]) -or $choice -lt 1 -or $choice -gt $Users.Count) {
        Write-Host "Opção inválida. Operação cancelada." -ForegroundColor Red
        return
    }

    $SelectedUser = $Users[$choice - 1]
    Write-Host "`nVocê selecionou o usuário: $($SelectedUser.Name)" -ForegroundColor Cyan
    $confirm = Read-Host "Deseja realmente desativar este usuário? (S/N)"

    if ($confirm -notin @('S', 's')) {
        Write-Host "Operação cancelada." -ForegroundColor Yellow
        return
    }

    try {
        Disable-LocalUser -Name $SelectedUser.Name
        Write-Host "`n✅ Usuário '$($SelectedUser.Name)' foi desativado com sucesso." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Erro ao desativar o usuário '$($SelectedUser.Name)': $_" -ForegroundColor Red
    }
}

# --- Função: Listar e habilitar usuários ---
function Enable-User {
    $DisabledUsers = Get-LocalUser | Where-Object { $_.Enabled -eq $false } | Sort-Object Name

    if ($DisabledUsers.Count -eq 0) {
        Write-Host "`n✅ Nenhum usuário desativado encontrado." -ForegroundColor Green
        return
    }

    Write-Host "`n===== USUÁRIOS DESATIVADOS =====" -ForegroundColor Cyan
    for ($i = 0; $i -lt $DisabledUsers.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $DisabledUsers[$i].Name) -ForegroundColor Yellow
    }

    $choice = Read-Host "`nDigite o número do usuário que deseja habilitar"
    if (-not ($choice -as [int]) -or $choice -lt 1 -or $choice -gt $DisabledUsers.Count) {
        Write-Host "Opção inválida. Operação cancelada." -ForegroundColor Red
        return
    }

    $SelectedUser = $DisabledUsers[$choice - 1]
    Write-Host "`nVocê selecionou o usuário: $($SelectedUser.Name)" -ForegroundColor Cyan
    $confirm = Read-Host "Deseja realmente habilitar este usuário? (S/N)"

    if ($confirm -notin @('S', 's')) {
        Write-Host "Operação cancelada." -ForegroundColor Yellow
        return
    }

    try {
        Enable-LocalUser -Name $SelectedUser.Name
        Write-Host "`n✅ Usuário '$($SelectedUser.Name)' foi habilitado com sucesso." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Erro ao habilitar o usuário '$($SelectedUser.Name)': $_" -ForegroundColor Red
    }
}

# --- Menu principal ---
do {
    Write-Host ""
    Write-Host "==========================================================" -ForegroundColor DarkGray
    Write-Host "        GERENCIADOR DE CONTAS LOCAIS - MENU PRINCIPAL" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor DarkGray
    Write-Host "[1] Desativar usuário" -ForegroundColor Yellow
    Write-Host "[2] Habilitar usuário" -ForegroundColor Yellow
    Write-Host "[0] Sair" -ForegroundColor Red
    Write-Host "----------------------------------------------------------" -ForegroundColor DarkGray

    $option = Read-Host "Selecione uma opção"

    switch ($option) {
        1 { Disable-User }
        2 { Enable-User }
        0 { Write-Host "`nSaindo..." -ForegroundColor Cyan }
        default { Write-Host "Opção inválida. Tente novamente." -ForegroundColor Red }
    }

} while ($option -ne 0)

Write-Host "`nEncerrado com sucesso." -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor DarkGray
