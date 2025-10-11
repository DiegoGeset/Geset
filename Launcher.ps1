# ===============================
# GESET Launcher - Interface WPF (Tema Escuro + Ocultação e Elevação)
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
# 0 = Esconde, 5 = Mostra
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

# Caminho base (GitHub)
$GitHubBaseUrl = "https://raw.githubusercontent.com/DiegoGeset/Geset/main"
# Caminho local temporário
$BasePath = "C:\Geset"
if (-not (Test-Path $BasePath)) { New-Item -Path $BasePath -ItemType Directory | Out-Null }

# ===============================
# Funções utilitárias
# ===============================
function Download-FromGitHub {
    param(
        [string]$RelativePath
    )
    $url = "$GitHubBaseUrl/$RelativePath"
    $localPath = Join-Path $BasePath $RelativePath

    $folder = Split-Path $localPath -Parent
    if (-not (Test-Path $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }

    if (-not (Test-Path $localPath)) {
        try {
            Invoke-WebRequest -Uri $url -OutFile $localPath -UseBasicParsing -ErrorAction Stop
        } catch {
            Write-Host "Falha ao baixar $url"
        }
    }

    return $localPath
}

function Run-ScriptElevated($scriptPath) {
    if (-not (Test-Path $scriptPath)) {
        [System.Windows.MessageBox]::Show("Arquivo não encontrado: $scriptPath", "Erro", "OK", "Error")
        return
    }
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
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
# Janela principal
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
# Tabs - Categorias
# ===============================
$tabControl = New-Object System.Windows.Controls.TabControl
$tabControl.Margin = "15,0,15,0"

$tabStyleXaml = @"
<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
                    xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>
    <Style TargetType='TabControl'>
        <Setter Property='BorderThickness' Value='0'/>
        <Setter Property='Background' Value='#102A4D'/>
    </Style>
    <Style TargetType='TabItem'>
        <Setter Property='Background' Value='#163B70'/>
        <Setter Property='Foreground' Value='White'/>
        <Setter Property='FontWeight' Value='Bold'/>
        <Setter Property='Padding' Value='14,7'/>
        <Setter Property='Margin' Value='2,2,2,0'/>
        <Setter Property='Template'>
            <Setter.Value>
                <ControlTemplate TargetType='TabItem'>
                    <Border x:Name='Bd' Background='{TemplateBinding Background}' CornerRadius='12,12,0,0' Padding='{TemplateBinding Padding}' SnapsToDevicePixels='True' BorderThickness='0' Margin='1,0,1,0'>
                        <Border.Effect>
                            <DropShadowEffect BlurRadius='8' ShadowDepth='3' Opacity='0.35' Color='#000000'/>
                        </Border.Effect>
                        <ContentPresenter x:Name='Content' ContentSource='Header' HorizontalAlignment='Center' VerticalAlignment='Center'/>
                    </Border>
                    <ControlTemplate.Triggers>
                        <Trigger Property='IsSelected' Value='True'>
                            <Setter TargetName='Bd' Property='Background' Value='#1E90FF'/>
                            <Setter TargetName='Bd' Property='Effect'>
                                <Setter.Value>
                                    <DropShadowEffect BlurRadius='12' ShadowDepth='3' Opacity='0.55' Color='#1E90FF'/>
                                </Setter.Value>
                            </Setter>
                            <Setter Property='Panel.ZIndex' Value='10'/>
                        </Trigger>
                        <Trigger Property='IsMouseOver' Value='True'>
                            <Setter TargetName='Bd' Property='Background' Value='#2B579A'/>
                        </Trigger>
                    </ControlTemplate.Triggers>
                </ControlTemplate>
            </Setter.Value>
        </Setter>
    </Style>
</ResourceDictionary>
"@

$tabXml = [xml]$tabStyleXaml
$tabReader = New-Object System.Xml.XmlNodeReader($tabXml)
$tabControl.Resources = [Windows.Markup.XamlReader]::Load($tabReader)

[System.Windows.Controls.Grid]::SetRow($tabControl, 1)
$mainGrid.Children.Add($tabControl)

# ===============================
# Estilo arredondado dos botões
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
                    <Trigger Property='IsMouseOver' Value='True'>
                        <Setter Property='Background' Value='#3F7AE0'/>
                    </Trigger>
                    <Trigger Property='IsPressed' Value='True'>
                        <Setter Property='Background' Value='#2759B0'/>
                    </Trigger>
                </ControlTemplate.Triggers>
            </ControlTemplate>
        </Setter.Value>
    </Setter>
</Style>
"@
$styleReader = (New-Object System.Xml.XmlNodeReader ([xml]$roundedStyle))
$roundedButtonStyle = [Windows.Markup.XamlReader]::Load($styleReader)

# ===============================
# Tema escuro padrão
# ===============================
$window.Background = "#0A1A33"
$tabControl.Background = "#102A4D"
$titleText.Foreground = "#FFFFFF"
$shadowEffect.Color = [System.Windows.Media.Colors]::LightBlue
# ===============================
# Função para carregar categorias e scripts do GitHub
# ===============================
$ScriptCheckBoxes = @{}
function Load-Tabs {
    $tabControl.Items.Clear()
    $ScriptCheckBoxes.Clear()

    # Estrutura fixa de categorias conforme o repositório
    $categories = @("Contas de Usuario", "Limpeza", "Otimizacao", "Rede", "Seguranca", "Atualizacoes")

    foreach ($category in $categories) {
        $tab = New-Object System.Windows.Controls.TabItem
        $tab.Header = $category

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

        # Subpastas dentro de cada categoria
        $subfoldersUrl = "$GitHubBaseUrl/$category"
        try {
            # Busca lista de subpastas via API HTML simples
            $html = Invoke-WebRequest -Uri $subfoldersUrl -UseBasicParsing
            $matches = ($html.Links | Where-Object { $_.href -match "/DiegoGeset/Geset/tree/main/$category/" }).href
            $subs = $matches | ForEach-Object { ($_ -split '/')[-1] } | Sort-Object -Unique
        } catch { $subs = @() }

        foreach ($sub in $subs) {
            $ps1Path = "$category/$sub/$sub.ps1"
            $localScript = Download-FromGitHub $ps1Path

            if (Test-Path $localScript) {
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

                $chk = New-Object System.Windows.Controls.CheckBox
                $chk.VerticalAlignment = "Center"
                $chk.Margin = "0,0,8,0"
                $chk.Tag = $localScript
                $ScriptCheckBoxes[$localScript] = $chk
                [System.Windows.Controls.Grid]::SetColumn($chk, 0)

                $btn = New-Object System.Windows.Controls.Button
                $btn.Content = $sub
                $btn.Width = 200
                $btn.Height = 32
                $btn.Style = $roundedButtonStyle
                $btn.Tag = $localScript
                $btn.VerticalAlignment = "Center"
                Add-HoverShadow $btn
                [System.Windows.Controls.Grid]::SetColumn($btn, 1)

                $infoBtn = New-Object System.Windows.Controls.Button
                $infoBtn.Content = "?"
                $infoBtn.Width = 28
                $infoBtn.Height = 28
                $infoBtn.Margin = "8,0,0,0"
                $infoBtn.Style = $roundedButtonStyle
                $infoBtn.Background = "#1E90FF"
                $infoBtn.Tag = $localScript
                $infoBtn.VerticalAlignment = "Center"
                Add-HoverShadow $infoBtn
                [System.Windows.Controls.Grid]::SetColumn($infoBtn, 2)

                $innerGrid.Children.Add($chk)
                $innerGrid.Children.Add($btn)
                $innerGrid.Children.Add($infoBtn)
                $sp.Children.Add($innerGrid)
                $panel.Children.Add($sp)

                $btn.Add_Click({ Run-ScriptElevated $this.Tag })
                $infoBtn.Add_Click({
                    $infoText = Get-InfoText $this.Tag
                    Show-InfoWindow -title $sub -content $infoText
                })
            }
        }

        $tab.Content = $border
        $tabControl.Items.Add($tab)
    }
}

# ===============================
# Rodapé
# ===============================
$footerGrid = New-Object System.Windows.Controls.Grid
$footerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$footerGrid.ColumnDefinitions.Add((New-Object System.Windows.Controls.ColumnDefinition))
$footerGrid.Margin = "15,0,15,10"

$footerPanel = New-Object System.Windows.Controls.StackPanel
$footerPanel.Orientation = "Horizontal"
$footerPanel.HorizontalAlignment = "Left"

$BtnExec = New-Object System.Windows.Controls.Button
$BtnExec.Content = "▶ Executar"
$BtnExec.Width = 110
$BtnExec.Height = 35
$BtnExec.Style = $roundedButtonStyle
$BtnExec.Background = "#1E90FF"
Add-HoverShadow $BtnExec

$BtnRefresh = New-Object System.Windows.Controls.Button
$BtnRefresh.Content = "🔄 Atualizar"
$BtnRefresh.Width = 110
$BtnRefresh.Height = 35
$BtnRefresh.Style = $roundedButtonStyle
$BtnRefresh.Background = "#E0E6ED"
$BtnRefresh.Foreground = "#0057A8"
Add-HoverShadow $BtnRefresh

$BtnExit = New-Object System.Windows.Controls.Button
$BtnExit.Content = "❌ Sair"
$BtnExit.Width = 90
$BtnExit.Height = 35
$BtnExit.Style = $roundedButtonStyle
$BtnExit.Background = "#FF5C5C"
$BtnExit.Foreground = "White"
Add-HoverShadow $BtnExit

$footerPanel.Children.Add($BtnExec)
$footerPanel.Children.Add($BtnRefresh)
$footerPanel.Children.Add($BtnExit)
[System.Windows.Controls.Grid]::SetColumn($footerPanel, 0)
$footerGrid.Children.Add($footerPanel)

# --- Informações do sistema ---
$infoText = New-Object System.Windows.Controls.TextBlock
$infoText.HorizontalAlignment = "Right"
$infoText.VerticalAlignment = "Center"
$infoText.Foreground = "White"
$infoText.FontSize = 12
[System.Windows.Controls.Grid]::SetColumn($infoText, 1)
$footerGrid.Children.Add($infoText)

# Atualiza data/hora e nome do PC dinamicamente
$timer = New-Object System.Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromSeconds(1)
$timer.Add_Tick({
    $infoText.Text = "$(Get-Date -Format 'dd/MM/yyyy HH:mm:ss')  |  $env:COMPUTERNAME"
})
$timer.Start()

[System.Windows.Controls.Grid]::SetRow($footerGrid, 2)
$mainGrid.Children.Add($footerGrid)

# ===============================
# Ações dos botões
# ===============================
$BtnExec.Add_Click({
    $selected = $ScriptCheckBoxes.GetEnumerator() | Where-Object { $_.Value.IsChecked -eq $true } | ForEach-Object { $_.Key }
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Nenhum script selecionado.", "Aviso", "OK", "Warning") | Out-Null
        return
    }
    foreach ($script in $selected) {
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$script`"" -Verb RunAs -Wait
    }
    [System.Windows.MessageBox]::Show("Execução concluída.", "GESET Launcher", "OK", "Information")
})

$BtnRefresh.Add_Click({ Load-Tabs })
$BtnExit.Add_Click({ $window.Close() })
# ===============================
# Inicialização
# ===============================
Load-Tabs
$window.ShowDialog() | Out-Null
