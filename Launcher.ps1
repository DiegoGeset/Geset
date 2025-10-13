# ===============================
# GESET Launcher - Interface WPF (Tema Escuro + Ocultação e Elevação)
# Usando JSON para estrutura remota
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

# ===============================
# Configuração: cache local e GitHub
# ===============================
$LocalCache = "C:\Geset"
$BasePath = $LocalCache
$LogPath = Join-Path $LocalCache "Logs"
$LogFile = Join-Path $LogPath "Launcher.log"

$RepoOwner = "DiegoGeset"
$RepoName = "Geset"
$Branch = "main"
$GitHubRawBase = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"

$Global:GitHubHeaders = @{ 'User-Agent' = 'GESET-Launcher' }

# Garante pastas locais
if (-not (Test-Path $LocalCache)) { New-Item -Path $LocalCache -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

# Função de log simples
function Write-Log { param([string]$msg) try { "$((Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))`t$msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8 } catch { } }
Write-Log "Launcher iniciado."

# ===============================
# Função: Download do JSON remoto
# ===============================
function Update-StructureJson {
    $localJson = Join-Path $LocalCache "structure.json"
    $remoteJsonUrl = "$GitHubRawBase/structure.json"

    try {
        Invoke-WebRequest -Uri $remoteJsonUrl -Headers $Global:GitHubHeaders -OutFile $localJson -UseBasicParsing -ErrorAction Stop
        Write-Log "Arquivo JSON atualizado: $localJson"
    } catch {
        Write-Log "Falha ao atualizar JSON remoto: $($_.Exception.Message)"
        if (-not (Test-Path $localJson)) {
            [System.Windows.MessageBox]::Show("Não foi possível obter o arquivo de estrutura JSON do GitHub.", "Erro", "OK", "Error")
            exit
        }
    }

    return $localJson
}

# ===============================
# Função: Lê estrutura do JSON local
# ===============================
function Get-StructureFromJson {
    param([string]$jsonPath)
    try {
        $jsonContent = Get-Content $jsonPath -Raw | ConvertFrom-Json
        return $jsonContent
    } catch {
        Write-Log "Falha ao ler JSON: $($_.Exception.Message)"
        return @()
    }
}
# ===============================
# Função: Cria estrutura local baseada no JSON
# ===============================
function Ensure-LocalStructure {
    param([array]$remoteList)
    foreach ($entry in $remoteList) {
        $cat = $entry.Category
        $sub = $entry.Sub
        if (-not $cat -or -not $sub) { continue }
        $localDir = Join-Path $LocalCache ($cat + "\" + $sub)
        if (-not (Test-Path $localDir)) {
            try { New-Item -Path $localDir -ItemType Directory -Force | Out-Null; Write-Log "Criada pasta local: $localDir" } catch { Write-Log "Falha ao criar pasta local: $localDir - $($_.Exception.Message)" }
        }
    }
}

# ===============================
# Função: Baixa script antes da execução
# ===============================
function Ensure-ScriptLocalAndExecute {
    param([string]$Category, [string]$Sub, [string]$ScriptName)
    $localDir = Join-Path $LocalCache ($Category + "\" + $Sub)
    if (-not (Test-Path $localDir)) { New-Item -Path $localDir -ItemType Directory -Force | Out-Null; Write-Log "Criada pasta forçada: $localDir" }

    $localScript = Join-Path $localDir $ScriptName
    $rawUrl = "$GitHubRawBase/$Category/$Sub/$ScriptName"

    $downloaded = $false
    try { $downloaded = Invoke-WebRequest -Uri $rawUrl -OutFile $localScript -UseBasicParsing -Headers $Global:GitHubHeaders -ErrorAction Stop; Write-Log "Baixado: $rawUrl -> $localScript"; $downloaded = $true } catch { $downloaded = $false }

    if (-not (Test-Path $localScript)) {
        Write-Log "Script não disponível localmente e download falhou: $localScript"
        [System.Windows.MessageBox]::Show("Não foi possível obter o script: $ScriptName`nVerifique sua conexão e tente novamente.", "Erro", "OK", "Error")
        return
    }

    try { Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$localScript`"" -Verb RunAs; Write-Log "Executado: $localScript" } catch { Write-Log "Falha ao executar: $localScript - $($_.Exception.Message)"; [System.Windows.MessageBox]::Show("Falha ao executar o script: $ScriptName", "Erro", "OK", "Error") }
}

# ===============================
# UI: Janela principal WPF
# ===============================
$window = New-Object System.Windows.Window
$window.Title = "GESET Launcher"
$window.Width = 780
$window.Height = 600
$window.WindowStartupLocation = 'CenterScreen'
$window.FontFamily = "Segoe UI"
$window.ResizeMode = "NoResize"

$mainGrid = New-Object System.Windows.Controls.Grid
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions.Add((New-Object System.Windows.Controls.RowDefinition))
$mainGrid.RowDefinitions[0].Height = "100"
$mainGrid.RowDefinitions[1].Height = "*"
$mainGrid.RowDefinitions[2].Height = "60"
$window.Content = $mainGrid

# ===============================
# Cabeçalho
# ===============================
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
$shadowEffect = New-Object System.Windows.Media.Effects.DropShadowEffect
$shadowEffect.Color = [System.Windows.Media.Colors]::LightBlue
$shadowEffect.BlurRadius = 10
$shadowEffect.ShadowDepth = 2
$titleText.Effect = $shadowEffect
$topPanel.Children.Add($titleText)
[System.Windows.Controls.Grid]::SetRow($topPanel, 0)
$mainGrid.Children.Add($topPanel)

# ===============================
# Tabs
# ===============================
$tabControl = New-Object System.Windows.Controls.TabControl
$tabControl.Margin = "15,0,15,0"
[System.Windows.Controls.Grid]::SetRow($tabControl, 1)
$mainGrid.Children.Add($tabControl)

# ===============================
# Botão arredondado estilo
# ===============================
$roundedStyle = @"
<Style xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' TargetType='Button'>
<Setter Property='Background' Value='#2E5D9F'/>
<Setter Property='Foreground' Value='White'/>
<Setter Property='FontWeight' Value='SemiBold'/>
<Setter Property='FontSize' Value='13'/>
<Setter Property='Margin' Value='5,5,5,5'/>
<Setter Property='Padding' Value='8,4'/>
<Setter Property='BorderThickness' Value='0'/>
<Setter Property='BorderBrush' Value='Transparent'/>
<Setter Property='Cursor' Value='Hand'/>
<Setter Property='Template'>
<Setter.Value>
<ControlTemplate TargetType='Button'>
<Border Background='{TemplateBinding Background}' CornerRadius='8' SnapsToDevicePixels='True'>
<ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center'/>
</Border>
<ControlTemplate.Triggers>
<Trigger Property='IsMouseOver' Value='True'><Setter Property='Background' Value='#3F7AE0'/></Trigger>
<Trigger Property='IsPressed' Value='True'><Setter Property='Background' Value='#2759B0'/></Trigger>
</ControlTemplate.Triggers>
</ControlTemplate>
</Setter.Value>
</Setter>
</Style>
"@
$styleReader = (New-Object System.Xml.XmlNodeReader ([xml]$roundedStyle))
$roundedButtonStyle = [Windows.Markup.XamlReader]::Load($styleReader)
# ===============================
# Função: Carrega abas e scripts
# ===============================
$ScriptCheckBoxes = @{}
function Load-Tabs {
    $tabControl.Items.Clear()
    $ScriptCheckBoxes.Clear()

    # Atualiza e lê JSON
    $jsonPath = Update-StructureJson
    $remote = Get-StructureFromJson -jsonPath $jsonPath
    Ensure-LocalStructure -remoteList $remote

    $categories = Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @("Logs") }

    foreach ($category in $categories) {
        $tab = New-Object System.Windows.Controls.TabItem
        $tab.Header = $category.Name

        $border = New-Object System.Windows.Controls.Border
        $border.BorderThickness = "1"
        $border.BorderBrush = "#3A6FB0"
        $border.Background = "#12294C"
        $border.CornerRadius = "10"
        $border.Margin = "10"
        $border.Padding = "10"
        $border.Effect = New-Object System.Windows.Media.Effects.DropShadowEffect
        $border.Effect.BlurRadius = 8
        $border.Effect.Opacity = 0.25
        $border.Effect.ShadowDepth = 3
        $border.Effect.Color = [System.Windows.Media.Colors]::Black

        $scrollViewer = New-Object System.Windows.Controls.ScrollViewer
        $scrollViewer.VerticalScrollBarVisibility = "Auto"
        $scrollViewer.Margin = "5"
        $panel = New-Object System.Windows.Controls.StackPanel
        $scrollViewer.Content = $panel
        $border.Child = $scrollViewer

        $subfolders = Get-ChildItem -Path $category.FullName -Directory -ErrorAction SilentlyContinue
        foreach ($sub in $subfolders) {
            $entry = $remote | Where-Object { $_.Category -eq $category.Name -and $_.Sub -eq $sub.Name } | Select-Object -First 1
            if (-not $entry -or -not $entry.ScriptName) { continue }

            $sp = New-Object System.Windows.Controls.StackPanel
            $sp.Orientation = "Horizontal"
            $sp.Margin = "0,0,0,8"
            $sp.VerticalAlignment = "Top"
            $sp.HorizontalAlignment = "Left"

            $innerGrid = New-Object System.Windows.Controls.Grid
            $innerGrid.Margin = "0"
            $innerGrid.VerticalAlignment = "Center"
            $innerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
            $innerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
            $innerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))

            # CheckBox
            $chk = New-Object System.Windows.Controls.CheckBox
            $chk.VerticalAlignment = "Center"
            $chk.Margin = "0,0,8,0"
            $localPathExpected = Join-Path $sub.FullName $entry.ScriptName
            $chk.Tag = $localPathExpected
            $ScriptCheckBoxes[$localPathExpected] = $chk
            [System.Windows.Controls.Grid]::SetColumn($chk, 0)

            # Botão principal
            $btn = New-Object System.Windows.Controls.Button
            $btn.Content = $sub.Name
            $btn.Width = 200
            $btn.Height = 32
            $btn.Style = $roundedButtonStyle
            $btn.Tag = [PSCustomObject]@{ Category = $category.Name; Sub = $sub.Name; ScriptName = $entry.ScriptName }
            $btn.VerticalAlignment = "Center"
            Add-HoverShadow $btn
            [System.Windows.Controls.Grid]::SetColumn($btn, 1)

            # Botão de info
            $infoBtn = New-Object System.Windows.Controls.Button
            $infoBtn.Content = "?"
            $infoBtn.Width = 28
            $infoBtn.Height = 28
            $infoBtn.Margin = "8,0,0,0"
            $infoBtn.Style = $roundedButtonStyle
            $infoBtn.Background = "#1E90FF"
            $infoBtn.Tag = $btn.Tag
            $infoBtn.VerticalAlignment = "Center"
            Add-HoverShadow $infoBtn
            [System.Windows.Controls.Grid]::SetColumn($infoBtn, 2)

            $innerGrid.Children.Add($chk)
            $innerGrid.Children.Add($btn)
            $innerGrid.Children.Add($infoBtn)
            $sp.Children.Add($innerGrid)
            $panel.Children.Add($sp)

            # Evento: clique no botão principal
            $btn.Add_Click({
                $meta = $this.Tag
                if ($meta -and $meta.Category -and $meta.Sub -and $meta.ScriptName) {
                    Ensure-ScriptLocalAndExecute -Category $meta.Category -Sub $meta.Sub -ScriptName $meta.ScriptName
                } else {
                    [System.Windows.MessageBox]::Show("Script não encontrado.", "Erro", "OK", "Error")
                }
            })

            # Evento: clique no botão de info
            $infoBtn.Add_Click({
                $meta = $this.Tag
                $infoText = "Nenhuma documentação encontrada para este script."
                try {
                    if ($meta -and $meta.Category -and $meta.Sub -and $meta.ScriptName) {
                        $rawTxtUrl = "$GitHubRawBase/$($meta.Category)/$($meta.Sub)/$([System.IO.Path]::ChangeExtension($meta.ScriptName, '.txt'))"
                        try { 
                            $content = Invoke-RestMethod -Uri $rawTxtUrl -Headers $Global:GitHubHeaders -ErrorAction Stop
                            if ($null -ne $content) { $infoText = $content.ToString() }
                        } catch { 
                            $candidateLocal = Join-Path $LocalCache ($meta.Category + "\" + $meta.Sub + "\" + [System.IO.Path]::ChangeExtension($meta.ScriptName, '.txt'))
                            if (Test-Path $candidateLocal) { $infoText = Get-Content $candidateLocal -Raw }
                        }
                    }
                } catch { }
                [System.Windows.MessageBox]::Show($infoText, "Informações do Script", "OK", "Information")
            })
        }

        $tab.Content = $border
        $tabControl.Items.Add($tab)
    }
}

# ===============================
# Função: Efeito hover para botões
# ===============================
function Add-HoverShadow {
    param($btn)
    $shadow = New-Object System.Windows.Media.Effects.DropShadowEffect
    $shadow.Color = [System.Windows.Media.Colors]::Black
    $shadow.Opacity = 0.3
    $shadow.BlurRadius = 6
    $shadow.ShadowDepth = 2
    $btn.Effect = $shadow
    $btn.Add_MouseEnter({ $btn.Effect.Opacity = 0.6 })
    $btn.Add_MouseLeave({ $btn.Effect.Opacity = 0.3 })
}
# ===============================
# Rodapé
# ===============================
$bottomPanel = New-Object System.Windows.Controls.StackPanel
$bottomPanel.Orientation = "Horizontal"
$bottomPanel.HorizontalAlignment = "Right"
$bottomPanel.VerticalAlignment = "Center"
$bottomPanel.Margin = "0,0,15,0"
[System.Windows.Controls.Grid]::SetRow($bottomPanel, 2)
$mainGrid.Children.Add($bottomPanel)

# Botão Refresh
$refreshBtn = New-Object System.Windows.Controls.Button
$refreshBtn.Content = "Refresh"
$refreshBtn.Width = 100
$refreshBtn.Height = 32
$refreshBtn.Style = $roundedButtonStyle
$refreshBtn.Add_Click({ Load-Tabs })
$bottomPanel.Children.Add($refreshBtn)

# Botão Exit
$exitBtn = New-Object System.Windows.Controls.Button
$exitBtn.Content = "Exit"
$exitBtn.Width = 100
$exitBtn.Height = 32
$exitBtn.Style = $roundedButtonStyle
$exitBtn.Margin = "10,0,0,0"
$exitBtn.Add_Click({ $window.Close() })
$bottomPanel.Children.Add($exitBtn)

# ===============================
# Inicialização
# ===============================
Load-Tabs
$window.Background = "#1B263B"
$window.ShowDialog() | Out-Null
