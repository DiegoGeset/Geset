# ================================================
# Script: Remover-Impressoras.ps1
# Descrição: Lista, remove ou recupera impressoras (incluindo virtuais)
# Execução: Sempre como Administrador
# ================================================

# --- Garante execução como administrador ---
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Reiniciando como administrador..." -ForegroundColor Yellow
    Start-Process powershell "-ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

# --- Garante serviço de spooler ativo ---
$spooler = Get-Service -Name Spooler -ErrorAction SilentlyContinue
if ($spooler.Status -ne 'Running') {
    Write-Host "Iniciando serviço de spooler..." -ForegroundColor Yellow
    Start-Service Spooler
    Start-Sleep -Seconds 2
}

# --- Função: Recuperar impressora PDF ---
function Restore-PDFPrinter {
    Write-Host "`nVerificando recurso 'Microsoft Print to PDF'..." -ForegroundColor Cyan
    try {
        $pdfPrinter = Get-Printer -Name "Microsoft Print to PDF" -ErrorAction SilentlyContinue
        if ($pdfPrinter) {
            Write-Host "✔ O recurso 'Microsoft Print to PDF' já está instalado." -ForegroundColor Green
        } else {
            Write-Host "Tentando adicionar o recurso 'Microsoft Print to PDF'..." -ForegroundColor Yellow
            Add-WindowsFeature Printing-PrintToPDFServices-Features -ErrorAction SilentlyContinue
            Write-Host "✔ Recurso adicionado. Reinicie o spooler se necessário." -ForegroundColor Green
        }
    } catch {
        Write-Host "❌ Não foi possível adicionar o recurso 'Microsoft Print to PDF'." -ForegroundColor Red
    }
}

# --- Função: obtém todas as impressoras ---
function Get-AllPrinters {
    Write-Host "`nObtendo lista de impressoras..." -ForegroundColor Cyan
    $impressoras = @()

    try { $impressoras += Get-Printer -ErrorAction SilentlyContinue } catch {}
    try {
        $impressoras += Get-CimInstance -ClassName Win32_Printer -ErrorAction SilentlyContinue
        $impressoras += Get-WmiObject -Class Win32_Printer -ErrorAction SilentlyContinue
    } catch {}

    $virtuals = @(
        "Microsoft Print to PDF",
        "Microsoft XPS Document Writer",
        "Fax",
        "OneNote for Windows 10",
        "Enviar para o OneNote 16",
        "Enviar para o OneNote",
        "Microsoft OneNote"
    )

    foreach ($v in $virtuals) {
        if (-not ($impressoras | Where-Object { $_.Name -eq $v })) {
            $obj = [PSCustomObject]@{
                Name        = $v
                PortName    = "N/A"
                WorkOffline = $false
                Source      = "Recurso do Windows"
            }
            $impressoras += $obj
        }
    }

    $impressoras = $impressoras | Where-Object { $_.Name -ne $null } | Sort-Object Name -Unique
    return $impressoras
}

# --- Função principal ---
function Main {
    while ($true) {
        Clear-Host
        Write-Host "============================================"
        Write-Host "   GERENCIAR IMPRESSORAS INSTALADAS"
        Write-Host "============================================" -ForegroundColor Cyan

        $impressoras = Get-AllPrinters

        if (-not $impressoras -or $impressoras.Count -eq 0) {
            Write-Host "`nNenhuma impressora foi encontrada no sistema." -ForegroundColor Yellow
            Read-Host "`nPressione ENTER para tentar novamente..."
            continue
        }

        for ($i = 0; $i -lt $impressoras.Count; $i++) {
            $status = if ($impressoras[$i].WorkOffline) { " (Offline)" } else { "" }
            $port = if ($impressoras[$i].PortName) { $impressoras[$i].PortName } else { "-" }
            $src = if ($impressoras[$i].Source) { "[$($impressoras[$i].Source)]" } else { "" }
            Write-Host ("[{0}] {1}{2}  | Porta: {3} {4}" -f ($i + 1), $impressoras[$i].Name, $status, $port, $src)
        }

        Write-Host "============================================"
        Write-Host "[R] Recarregar lista"
        Write-Host "[P] Recuperar 'Microsoft Print to PDF'"
        Write-Host "[ENTER] Cancelar e sair"
        Write-Host "============================================`n"

        $entrada = Read-Host "Digite o número(s) da(s) impressora(s) para remover (ex: 1,3,5), R para recarregar ou P para recuperar PDF"

        if ([string]::IsNullOrWhiteSpace($entrada)) {
            Write-Host "`nNenhuma ação foi realizada. Saindo..." -ForegroundColor Yellow
            Pause
            break
        }

        if ($entrada.ToUpper() -eq 'R') {
            Write-Host "`nRecarregando lista de impressoras..." -ForegroundColor Cyan
            Start-Sleep -Seconds 1
            continue
        }

        if ($entrada.ToUpper() -eq 'P') {
            Restore-PDFPrinter
            Read-Host "`nPressione ENTER para retornar ao menu..."
            continue
        }

        $indicesSelecionados = $entrada -split "," | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' }

        if ($indicesSelecionados.Count -eq 0) {
            Write-Host "`nNenhum número válido foi informado. Operação cancelada." -ForegroundColor Red
            Read-Host "`nPressione ENTER para retornar ao menu..."
            continue
        }

        Write-Host "`nVocê selecionou as seguintes impressoras para remoção:" -ForegroundColor Yellow
        foreach ($indice in $indicesSelecionados) {
            $nome = $impressoras[$indice - 1].Name
            Write-Host " - $nome"
        }

        $confirmar = Read-Host "`nDeseja realmente remover essas impressoras? (S/N)"
        if ($confirmar.ToUpper() -ne 'S') {
            Write-Host "`nOperação cancelada pelo usuário." -ForegroundColor Yellow
            Read-Host "`nPressione ENTER para retornar ao menu..."
            continue
        }

        foreach ($indice in $indicesSelecionados) {
            $indiceInt = [int]$indice - 1
            if ($indiceInt -ge 0 -and $indiceInt -lt $impressoras.Count) {
                $nomeImpressora = $impressoras[$indiceInt].Name
                try {
                    Remove-Printer -Name $nomeImpressora -ErrorAction Stop
                    Write-Host "✔ Impressora '$nomeImpressora' removida com sucesso." -ForegroundColor Green
                } catch {
                    Write-Host "❌ Erro ao remover a impressora '$nomeImpressora': $_" -ForegroundColor Red
                }
            }
        }

        Write-Host "`nProcesso concluído." -ForegroundColor Cyan
        Read-Host "`nPressione ENTER para retornar ao menu..."
    }
}

# --- Executa ---
Main
