# ==========================================================
# Script: Desativar IPv6 (interativo e visual)
# Função: Lista adaptadores de rede e permite selecionar
#         quais terão o IPv6 desativado.
# ==========================================================

# --- Limpar tela e título ---
Clear-Host
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "     GERENCIADOR DE ADAPTADORES IPv6    " -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# --- Obter adaptadores de rede físicos e virtuais ---
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' -or $_.Status -eq 'Disabled' }

if (-not $adapters) {
    Write-Host "[ERRO] Nenhum adaptador de rede encontrado!" -ForegroundColor Red
    exit
}

# --- Exibir lista de adaptadores ---
Write-Host ("Foram encontrados {0} adaptadores de rede:" -f $adapters.Count) -ForegroundColor Cyan
Write-Host ""

$index = 1
foreach ($adapter in $adapters) {
    Write-Host ("[{0}] {1}  (Status: {2})" -f $index, $adapter.Name, $adapter.Status) -ForegroundColor White
    $index++
}

Write-Host ""
Write-Host "[A] Selecionar TODOS os adaptadores" -ForegroundColor Yellow
Write-Host ""

# --- Solicitar escolha ---
$escolha = Read-Host "Digite o número dos adaptadores (ex: 1,3,5) ou 'A' para todos"

# --- Validar e determinar adaptadores selecionados ---
if ($escolha -match '^[Aa]$') {
    $selecionados = $adapters
    Write-Host "`nSelecionado: TODOS os adaptadores." -ForegroundColor Yellow
}
else {
    $indices = $escolha -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }
    $selecionados = foreach ($i in $indices) { $adapters[$i - 1] }
}

if (-not $selecionados) {
    Write-Host "`n[AVISO] Nenhum adaptador selecionado. Operação cancelada." -ForegroundColor Red
    exit
}

# --- Confirmar operação ---
Write-Host ""
Write-Host "Você selecionou os seguintes adaptadores para desativar o IPv6:" -ForegroundColor Cyan
$selecionados | ForEach-Object { Write-Host (" - {0}" -f $_.Name) -ForegroundColor White }
Write-Host ""

$confirmar = Read-Host "Deseja continuar? (S/N)"

if ($confirmar -notin @('S','s','Sim','sim')) {
    Write-Host "`nOperação cancelada pelo usuário." -ForegroundColor Red
    exit
}

# --- Desativar IPv6 nos adaptadores selecionados ---
foreach ($adapter in $selecionados) {
    try {
        Disable-NetAdapterBinding -Name $adapter.Name -ComponentID ms_tcpip6 -ErrorAction Stop
        Write-Host ("[OK] IPv6 desativado no adaptador: {0}" -f $adapter.Name) -ForegroundColor Green
    }
    catch {
        Write-Host ("[ERRO] Falha ao desativar IPv6 no adaptador: {0}" -f $adapter.Name) -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "[INFO] Operação concluída com sucesso." -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
