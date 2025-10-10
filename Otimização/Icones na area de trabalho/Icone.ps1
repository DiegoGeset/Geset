<#
===========================================================
 Script: PadronizacaoIconesAreaDeTrabalho.ps1
 Descrição: Permite escolher quais ícones padrão da área
            de trabalho serão exibidos para todos os usuários
===========================================================
#>

# --- Define codificação UTF-8 apenas se o console existir ---
if ($Host.Name -eq 'ConsoleHost') {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

# --- Verifica privilégios de administrador ---
if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator
)) {
    Write-Host "Reiniciando o script com privilégios de administrador..." -ForegroundColor Yellow
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

Write-Host "`n=== Configuração dos ícones da Área de Trabalho ===`n" -ForegroundColor Cyan

# --- Lista de ícones conhecidos ---
$icones = @(
    @{Nome = "Este Computador"; GUID = '{20d04fe0-3aea-1069-a2d8-08002b30309d}'},
    @{Nome = "Pasta do Usuário"; GUID = '{59031a47-3f72-44a7-89c5-5595fe6b30ee}'},
    @{Nome = "Lixeira"; GUID = '{645ff040-5081-101b-9f08-00aa002f954e}'},
    @{Nome = "Painel de Controle"; GUID = '{5399e694-6ce5-4d6c-8fce-1d8870fdcba0}'},
    @{Nome = "Rede"; GUID = '{f02c1a0d-be21-4350-88b0-7367fc96ef3c}'},
    @{Nome = "Documentos"; GUID = '{a8cdff1c-4878-43be-b5fd-f8091c1c60d0}'},
    @{Nome = "Downloads"; GUID = '{374de290-123f-4565-9164-39c4925e467b}'},
    @{Nome = "Músicas"; GUID = '{1cf1260c-4dd0-4ebb-811f-33c572699fde}'},
    @{Nome = "Imagens"; GUID = '{3add1653-eb32-4cb0-bbd7-dfa0abb5acca}'},
    @{Nome = "Vídeos"; GUID = '{e88865ea-0e1c-4e20-9aa6-edcd0212c87c}'},
    @{Nome = "Favoritos"; GUID = '{f874310e-b6b7-47dc-bc84-b9e6b38f5903}'},
    @{Nome = "Dispositivos e Impressoras"; GUID = '{a0953c92-50dc-43bf-be83-3742fed03c9c}'}
)

# --- Exibe menu para o usuário ---
Write-Host "Selecione os ícones que deseja manter visíveis:" -ForegroundColor Yellow
for ($i = 0; $i -lt $icones.Count; $i++) {
    Write-Host "[$($i+1)] $($icones[$i].Nome)"
}
Write-Host ""

$inputSelecionado = Read-Host "Digite os números separados por vírgula (ex: 1,3,5)"
$indices = $inputSelecionado -split ',' | ForEach-Object { ($_ -as [int]) - 1 }

$mostrar = @()
foreach ($i in $indices) {
    if ($i -ge 0 -and $i -lt $icones.Count) {
        $mostrar += $icones[$i].GUID
    }
}

if ($mostrar.Count -eq 0) {
    Write-Host "`nNenhum ícone selecionado. Operação cancelada." -ForegroundColor Red
    exit
}

# --- Define os GUIDs a ocultar (todos os demais) ---
$ocultar = $icones.GUID | Where-Object { $mostrar -notcontains $_ }

# --- Monta lista de caminhos de registro ---
$paths = @(
    # Padrão (novos usuários)
    'Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu',
    'Registry::HKEY_USERS\.DEFAULT\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel'
)

# Inclui todos os usuários existentes
$usuarios = Get-ChildItem 'Registry::HKEY_USERS' | Where-Object {
    $_.Name -notmatch '\\(Classes|_Classes)$' -and
    $_.Name -notmatch '\\.DEFAULT$' -and
    $_.Name -match '^HKEY_USERS\\S-\d-\d+'
}

foreach ($u in $usuarios) {
    $sid = ($u.Name -split '\\')[-1]
    $paths += @(
        "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu",
        "Registry::HKEY_USERS\$sid\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    )
}

# Inclui também o usuário atual (garantia)
$paths += @(
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\ClassicStartMenu",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
)

# --- Aplicar configurações ---
foreach ($path in $paths | Sort-Object -Unique) {
    Write-Host "`nAplicando em: $path" -ForegroundColor DarkCyan
    try {
        New-Item -Path $path -Force -ErrorAction Stop | Out-Null
        foreach ($guid in $ocultar) {
            Set-ItemProperty -Path $path -Name $guid -Value 1 -Type DWord -ErrorAction SilentlyContinue
        }
        foreach ($guid in $mostrar) {
            Set-ItemProperty -Path $path -Name $guid -Value 0 -Type DWord -ErrorAction SilentlyContinue
        }
    }
    catch {
        Write-Host "⚠️ Erro ao aplicar em: $path" -ForegroundColor Red
    }
}

# --- Reinicia Explorer ---
Write-Host "`n🔄 Reiniciando o Windows Explorer para aplicar as alterações..." -ForegroundColor Yellow
Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
Start-Process explorer.exe

# --- Conclusão ---
$nomesMostrar = $icones | Where-Object { $mostrar -contains $_.GUID } | Select-Object -ExpandProperty Nome
Write-Host "`n✅ Configuração concluída com sucesso!" -ForegroundColor Green
Write-Host "Ícones visíveis: $($nomesMostrar -join ', ')" -ForegroundColor Yellow
Write-Host "Aplicado a todos os usuários e definido como padrão para novos perfis." -ForegroundColor Cyan
Write-Host "============================================================`n"
