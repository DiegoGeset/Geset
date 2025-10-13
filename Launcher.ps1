# ===============================
# GESET Launcher - Interface WPF (Tema Escuro + Ocultação e Elevação)
# Atualizado para conexão automática com GitHub (Raw + Fallback)
# ===============================

# --- Oculta a janela do PowerShell ---
$signature = @"
[DllImport("kernel32.dll")]
public static extern IntPtr GetConsoleWindow();
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
"@
Add-Type -MemberDefinition $signature -Name "Win32" -Namespace "PInvoke"
$consolePtr = [PInvoke.Win32]::GetConsoleWindow()
[PInvoke.Win32]::ShowWindow($consolePtr, 0)

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

# ===============================
# Dependências principais
# ===============================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$BasePath = "C:\Geset"
$RepoRoot = "https://github.com/DiegoGeset/Geset"
$RawRoot  = "https://raw.githubusercontent.com/DiegoGeset/Geset/main"
$LogPath = Join-Path $BasePath "Logs\Launcher.log"
if (!(Test-Path (Split-Path $LogPath))) { New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null }

function Write-Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') `t $msg"
    Add-Content -Path $LogPath -Value $line
}

Write-Log "Launcher iniciado."

# ===============================
# Funções GitHub
# ===============================
function Get-GitHubHtmlFolders {
    param($url)
    try {
        $html = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        $folders = ($html.Links | Where-Object { $_.href -match "/tree/main/" }) |
                   ForEach-Object { ($_ -split "/tree/main/")[1] } |
                   Where-Object { $_ -and ($_ -notmatch "Logs") } |
                   Sort-Object -Unique
        return $folders
    } catch {
        Write-Log "Falha ao obter HTML: $_"
        return @()
    }
}

function Ensure-LocalStructure {
    $remoteFolders = Get-GitHubHtmlFolders "$RepoRoot/tree/main"
    if ($remoteFolders.Count -eq 0) {
        Write-Log "Não foi possível obter a estrutura remota — mantendo local."
        return
    }

    foreach ($folder in $remoteFolders) {
        $localFolder = Join-Path $BasePath $folder
        if (!(Test-Path $localFolder)) {
            New-Item -ItemType Directory -Force -Path $localFolder | Out-Null
            Write-Log "Criado diretório: $localFolder"
        }
    }
}

function Download-IfNeeded($remoteSubPath, $localPath) {
    $url = "$RawRoot/$remoteSubPath"
    try {
        Invoke-WebRequest -Uri $url -OutFile $localPath -UseBasicParsing -ErrorAction Stop
        Write-Log "Baixado: $url -> $localPath"
    } catch {
        Write-Log "Erro ao baixar $url : $_"
    }
}

# ===============================
# Inicialização remota (auto-update)
# ===============================
Ensure-LocalStructure

# ===============================
# Funções utilitárias (originais)
# ===============================
function Run-ScriptElevated($scriptPath, $remotePath) {
    if (-not (Test-Path $scriptPath)) {
        Download-IfNeeded $remotePath $scriptPath
    }
    if (-not (Test-Path $scriptPath)) {
        [System.Windows.MessageBox]::Show("Arquivo não encontrado: $scriptPath", "Erro", "OK", "Error")
        return
    }
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
    Write-Log "Executado: $scriptPath"
}

function Get-InfoText($scriptPath) {
    $txtFile = [System.IO.Path]::ChangeExtension($scriptPath, ".txt")
    if (Test-Path $txtFile) { Get-Content $txtFile -Raw }
    else { "Nenhuma documentação encontrada para este script." }
}

function Show-InfoWindow($title, $content) {
    $window = New-Object System.Windows.Window
    $window.Title = "Informações - $title"
    $window.Width = 600
    $window.Height = 400
    $window.WindowStartupLocation = 'CenterScreen'
    $window.Background = "#1E1E1E"
    $window.FontFamily = "Segoe UI"
    $window.Foreground = "White"

    $textBox = New-Object System.Windows.Controls.TextBox
    $textBox.Text = $content
    $textBox.Margin = 15
    $textBox.TextWrapping = "Wrap"
    $textBox.VerticalScrollBarVisibility = "Auto"
    $textBox.IsReadOnly = $true
    $textBox.FontSize = 14

    $window.Content = $textBox
    $window.ShowDialog() | Out-Null
}

function Add-HoverShadow($button) {
    $button.Add_MouseEnter({
        $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
        $shadow.Color = [System.Windows.Media.Colors]::Black
        $shadow.Opacity = 0.4
        $shadow.BlurRadius = 15
        $shadow.Direction = 320
        $shadow.ShadowDepth = 4
        $this.Effect = $shadow
    })
    $button.Add_MouseLeave({ $this.Effect = $null })
}

# ===============================
# Janela principal (mantida idêntica)
# ===============================
$window = New-Object System.Windows.Window
$window.Title = "GESET Launcher"
$window.Width = 780
$window.Height = 600
$window.WindowStartupLocation = 'CenterScreen'
$window.FontFamily = "Segoe UI"
$window.ResizeMode = "NoResize"
$window.Background = "#0A1A33"

$mainGrid = New-Object System.Windows.Controls.Grid
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions[0].Height = "100"
$mainGrid.RowDefinitions[1].Height = "*"
$mainGrid.RowDefinitions[2].Height = "60"
$window.Content = $mainGrid

# --- Cabeçalho ---
$topPanel = New-Object System.Windows.Controls.StackPanel
$topPanel.Orientation = "Horizontal"
$topPanel.HorizontalAlignment = "Center"
$topPanel.VerticalAlignment = "Center"
$topPanel.Margin = "0,15,0,15"

$logoPath = Join-Path $BasePath "logo.png"
if (Test-Path $logoPath) {
    $logo = New-Object System.Windows.Controls.Image
    $logo.Source = New-Object System.Windows.Media.Imaging.BitmapImage([Uri]$logoPath)
    $logo.Width = 60
    $logo.Height = 60
    $logo.Margin = "0,0,10,0"
    $topPanel.Children.Add($logo)
}

$titleText = New-Object System.Windows.Controls.TextBlock
$titleText.Text = "GESET"
$titleText.FontSize = 38
$titleText.FontWeight = "Bold"
$titleText.Foreground = "#FFFFFF"
$titleText.VerticalAlignment = "Center"
$topPanel.Children.Add($titleText)
[System.Windows.Controls.Grid]::SetRow($topPanel, 0)
$mainGrid.Children.Add($topPanel)

# ===============================
# Carrega tabs e scripts (mantido)
# ===============================
$tabControl = New-Object System.Windows.Controls.TabControl
$tabControl.Margin = "15,0,15,0"
[System.Windows.Controls.Grid]::SetRow($tabControl, 1)
$mainGrid.Children.Add($tabControl)
$ScriptCheckBoxes = @{}

function Load-Tabs {
    $tabControl.Items.Clear()
    $categories = Get-ChildItem -Path $BasePath -Directory | Where-Object { $_.Name -notin @("Logs") }
    foreach ($category in $categories) {
        $tab = New-Object System.Windows.Controls.TabItem
        $tab.Header = $category.Name
        $border = New-Object System.Windows.Controls.Border
        $border.Background = "#12294C"
        $border.CornerRadius = "10"
        $border.Margin = "10"
        $border.Padding = "10"

        $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
        $scrollViewer.VerticalScrollBarVisibility = "Auto"
        $panel = New-Object System.Windows.Controls.StackPanel
        $scrollViewer.Content = $panel
        $border.Child = $scrollViewer

        $subfolders = Get-ChildItem -Path $category.FullName -Directory
        foreach ($sub in $subfolders) {
            $scriptName = "$($category.Name)/$($sub.Name)/$($sub.Name).ps1"
            $localScript = Join-Path $sub.FullName "$($sub.Name).ps1"

            $grid = New-Object System.Windows.Controls.Grid
            $grid.Margin = "0,0,0,8"
            $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
            $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
            $grid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))

            $chk = New-Object System.Windows.Controls.CheckBox
            $chk.VerticalAlignment = "Center"
            $chk.Tag = $localScript
            $ScriptCheckBoxes[$localScript] = $chk
            [System.Windows.Controls.Grid]::SetColumn($chk, 0)

            $btn = New-Object System.Windows.Controls.Button
            $btn.Content = $sub.Name
            $btn.Width = 200
            $btn.Height = 32
            $btn.Tag = @{Local=$localScript; Remote=$scriptName}
            $btn.Background = "#2E5D9F"
            Add-HoverShadow $btn
            $btn.Add_Click({
                $info = $this.Tag
                Run-ScriptElevated $info.Local $info.Remote
            })
            [System.Windows.Controls.Grid]::SetColumn($btn, 1)

            $grid.Children.Add($chk)
            $grid.Children.Add($btn)
            $panel.Children.Add($grid)
        }
        $tab.Content = $border
        $tabControl.Items.Add($tab)
    }
}

# --- Rodapé ---
$footer = New-Object System.Windows.Controls.StackPanel
$footer.Orientation = "Horizontal"
$footer.HorizontalAlignment = "Center"
$footer.Margin = "0,0,0,10"

$BtnExec = New-Object System.Windows.Controls.Button
$BtnExec.Content = "▶ Executar"
$BtnExec.Width = 110
$BtnExec.Height = 35
$BtnExec.Background = "#1E90FF"
Add-HoverShadow $BtnExec

$BtnRefresh = New-Object System.Windows.Controls.Button
$BtnRefresh.Content = "🔄 Atualizar"
$BtnRefresh.Width = 110
$BtnRefresh.Height = 35
$BtnRefresh.Add_Click({
    Write-Log "Atualização solicitada pelo usuário."
    Ensure-LocalStructure
    Load-Tabs
})
Add-HoverShadow $BtnRefresh

$BtnExit = New-Object System.Windows.Controls.Button
$BtnExit.Content = "❌ Sair"
$BtnExit.Width = 90
$BtnExit.Height = 35
$BtnExit.Add_Click({ $window.Close() })
Add-HoverShadow $BtnExit

$footer.Children.Add($BtnExec)
$footer.Children.Add($BtnRefresh)
$footer.Children.Add($BtnExit)
[System.Windows.Controls.Grid]::SetRow($footer, 2)
$mainGrid.Children.Add($footer)

# --- Execução ---
$BtnExec.Add_Click({
    $selected = $ScriptCheckBoxes.GetEnumerator() | Where-Object { $_.Value.IsChecked -eq $true } | ForEach-Object { $_.Key }
    foreach ($script in $selected) {
        $rel = $script.Replace("$BasePath\", "").Replace("\", "/")
        Run-ScriptElevated $script $rel
    }
    [System.Windows.MessageBox]::Show("Execução concluída.", "GESET Launcher", "OK", "Information")
})

# ===============================
# Inicialização final
# ===============================
Load-Tabs
$window.ShowDialog() | Out-Null
Write-Log "Launcher finalizado."
