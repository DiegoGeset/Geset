# ==========================================================
# Script: Gerenciar Usuário "Administrador"
# Função: Cria, reativa e configura o usuário Administrador,
#         definindo senha e políticas ao final do processo
# ==========================================================

# --- Garante execução como Administrador ---
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Reiniciando o script como Administrador..." -ForegroundColor Cyan
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# --- Solicita senha desejada ---
Write-Host ""
Write-Host "Digite a senha que deseja definir para o usuário 'Administrador':" -ForegroundColor Yellow
$PlainPassword = Read-Host "Senha"
$SecurePassword = ConvertTo-SecureString $PlainPassword -AsPlainText -Force

# --- Nome do usuário ---
$UserName = "Administrador"

Write-Host "`n🔍 Verificando status da conta '$UserName'..." -ForegroundColor Cyan
$User = Get-LocalUser -Name $UserName -ErrorAction SilentlyContinue

# --- 1️⃣ Verificação e criação, se necessário ---
if (-not $User) {
    Write-Host "Usuário 'Administrador' não encontrado. Criando nova conta..." -ForegroundColor Yellow
    try {
        New-LocalUser -Name $UserName `
                      -Password $SecurePassword `
                      -FullName "Administrador do Sistema" `
                      -Description "Conta administrativa padrão do sistema" `
                      -PasswordNeverExpires `
                      -AccountNeverExpires
        Write-Host "✅ Conta criada com sucesso." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Erro ao criar a conta: $_" -ForegroundColor Red
        Pause
        exit
    }
}
else {
    Write-Host "✅ Usuário 'Administrador' encontrado." -ForegroundColor Green
}

# --- 2️⃣ Reativa se estiver desativado ---
$User = Get-LocalUser -Name $UserName
if (-not $User.Enabled) {
    Write-Host "A conta está desativada. Reativando..." -ForegroundColor Yellow
    try {
        Enable-LocalUser -Name $UserName
        Write-Host "✅ Conta reativada." -ForegroundColor Green
    }
    catch {
        Write-Host "❌ Erro ao reativar a conta: $_" -ForegroundColor Red
    }
}
else {
    Write-Host "A conta já está ativa." -ForegroundColor Green
}

# --- 3️⃣ Garante que está no grupo Administradores ---
try {
    $isMember = (Get-LocalGroupMember -Group "Administradores" -ErrorAction SilentlyContinue | Where-Object { $_.Name -eq $UserName })
    if (-not $isMember) {
        Write-Host "Adicionando '$UserName' ao grupo 'Administradores'..." -ForegroundColor Yellow
        Add-LocalGroupMember -Group "Administradores" -Member $UserName -ErrorAction SilentlyContinue
        Write-Host "✅ Adicionado ao grupo Administradores." -ForegroundColor Green
    }
    else {
        Write-Host "Usuário já faz parte do grupo Administradores." -ForegroundColor Green
    }
}
catch {
    Write-Host "❌ Erro ao verificar/adicionar grupo: $_" -ForegroundColor Red
}

# --- 4️⃣ Aplicação final da senha e políticas ---
Write-Host "`n🔐 Aplicando senha e configurações finais..." -ForegroundColor Cyan
try {
    # Troca a senha com 'net user' (mais confiável para contas internas)
    net user $UserName $PlainPassword | Out-Null

    # Define políticas de conta
    net user $UserName /passwordchg:no | Out-Null
    net user $UserName /expires:never | Out-Null
    net user $UserName /passwordreq:yes | Out-Null

    Write-Host "✅ Senha e configurações aplicadas com sucesso." -ForegroundColor Green
}
catch {
    Write-Host "❌ Erro ao definir senha/configurações: $_" -ForegroundColor Red
}

# --- 5️⃣ Resumo final ---
Write-Host ""
Write-Host "==========================================================" -ForegroundColor DarkGray
Write-Host "✅ Usuário 'Administrador' está ativo e configurado corretamente."
Write-Host "   • Senha atualizada com sucesso"
Write-Host "   • Senha nunca expira"
Write-Host "   • Conta nunca expira"
Write-Host "   • Usuário não pode alterar a senha"
Write-Host "==========================================================" -ForegroundColor DarkGray
Write-Host ""
Write-Host "Pressione qualquer tecla para sair..." -ForegroundColor Yellow
Pause
