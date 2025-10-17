# ===============================
# GESET Launcher - Interface WPF (Tema Escuro + Ocultação e Elevação)
# Usa JSON remoto (structure.json) como fonte da estrutura do repositório
# Monta URLs raw com EscapeDataString por segmento (corrige espaços e caracteres especiais)
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
    # Reinicia o próprio script com elevação e com bypass da política de execução,
    # sem exibir mensagem: o processo atual encerra depois de disparar a elevação.
    $psExe = (Get-Command powershell.exe).Source
    # Use $PSCommandPath se disponível; fallback para o arquivo em execução via MyInvocation
    if (-not $PSCommandPath) {
        $scriptPath = $MyInvocation.MyCommand.Definition
    } else {
        $scriptPath = $PSCommandPath
    }

    # Monta os argumentos: bypass de política, sem profile, janela oculta, e o caminho do arquivo
    $arg = "-ExecutionPolicy Bypass -NoProfile -WindowStyle Hidden -File `"$scriptPath`""

    # Inicia o PowerShell elevado (runas). Start-Process por padrão cria uma nova janela,
    # mas passamos WindowStyle Hidden no argumento para que o novo processo fique oculto.
    Start-Process -FilePath $psExe -ArgumentList $arg -Verb RunAs

    # Sai do processo atual para evitar execuções duplicadas
    exit
}

# Se chegou aqui, já está em modo Administrador (continua o restante do script...)

# ===============================
# Dependências principais
# ===============================
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ===============================
# Configuração: cache local e GitHub (raw)
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

# Função de log simples (silencioso)
function Write-Log {
    param([string]$msg)
    try {
        $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        "$t`t$msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    } catch { }
}

Write-Log "Launcher iniciado."

# ===============================
# Função: Atualiza/baixa structure.json do GitHub raw
# - Se falhar e local existir, usa local
# - Se falhar e não houver local, mostra erro e exit
# ===============================
function Update-StructureJson {
    $localJson = Join-Path $LocalCache "structure.json"
    $remoteJsonUrl = "$GitHubRawBase/structure.json"

    try {
        # baixa para temporário primeiro para evitar arquivos parcialmente escritos
        $tmp = Join-Path $LocalCache "structure_tmp.json"
        Invoke-WebRequest -Uri $remoteJsonUrl -Headers $Global:GitHubHeaders -OutFile $tmp -UseBasicParsing -ErrorAction Stop

        # se não existia ou diferente, substitui
        $replace = $true
        if (Test-Path $localJson) {
            try {
                $hashOld = (Get-FileHash $localJson -Algorithm MD5).Hash
                $hashNew = (Get-FileHash $tmp -Algorithm MD5).Hash
                if ($hashOld -eq $hashNew) { $replace = $false }
            } catch { $replace = $true }
        }

        if ($replace) {
            Copy-Item -Path $tmp -Destination $localJson -Force
            Write-Log "structure.json atualizado a partir do GitHub."
        } else {
            Write-Log "structure.json local já está atualizado."
        }

        Remove-Item $tmp -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Log "Falha ao atualizar JSON remoto: $($_.Exception.Message)"
        if (-not (Test-Path $localJson)) {
            Add-Type -AssemblyName PresentationFramework
            [System.Windows.MessageBox]::Show("Não foi possível obter o arquivo de estrutura JSON do GitHub e não existe arquivo local.", "Erro", "OK", "Error")
            exit
        } else {
            Write-Log "Continuando com structure.json local já existente."
        }
    }

    return $localJson
}

# ===============================
# Função: Lê estrutura do JSON local e normaliza objetos
# Formato esperado do JSON: array de objetos { categoria, subpasta, script, descricao }
# (mantemos compatibilidade com nomes de campos em português)
# ===============================
function Get-StructureFromJson {
    param([string]$jsonPath)

    try {
        $jsonContent = Get-Content $jsonPath -Raw | ConvertFrom-Json
        if ($null -eq $jsonContent) { return @() }
        $list = @()
        foreach ($item in $jsonContent) {
            # aceita tanto campos em português quanto em inglês (Category/Sub/ScriptName)
            $cat = $item.categoria
            if ($null -eq $cat) { $cat = $item.Category }
            $sub = $item.subpasta
            if ($null -eq $sub) { $sub = $item.Sub }
            $script = $item.script
            if ($null -eq $script) { $script = $item.ScriptName }
            $desc = $item.descricao
            if ($null -eq $desc) { $desc = $item.Description }

            $list += [PSCustomObject]@{ Category = $cat; Sub = $sub; ScriptName = $script; Description = $desc }
        }
        return $list
    } catch {
        Write-Log "Falha ao ler JSON ($jsonPath): $($_.Exception.Message)"
        return @()
    }
}

# ===============================
# Função: Cria estrutura local (pastas) conforme lista do JSON
# ===============================
function Ensure-LocalStructure {
    param([array]$remoteList)

    foreach ($entry in $remoteList) {
        $cat = $entry.Category
        $sub = $entry.Sub
        if (-not $cat -or -not $sub) { continue }
        $localDir = Join-Path $LocalCache ($cat + "\" + $sub)
        if (-not (Test-Path $localDir)) {
            try {
                New-Item -Path $localDir -ItemType Directory -Force | Out-Null
                Write-Log "Criada pasta local: $localDir"
            } catch {
                Write-Log "Falha ao criar pasta local: $localDir - $($_.Exception.Message)"
            }
        }
    }
}

# ===============================
# Função: Baixa script .ps1 (raw) para cache local e executa em nova janela elevada
# - Sempre monta o rawUrl por segmento com EscapeDataString (evita links "bugados")
# ===============================
function Ensure-ScriptLocalAndExecute {
    param([string]$Category, [string]$Sub, [string]$ScriptName)

    $localDir = Join-Path $LocalCache ($Category + "\" + $Sub)
    if (-not (Test-Path $localDir)) {
        New-Item -Path $localDir -ItemType Directory -Force | Out-Null
        Write-Log "Criada pasta forçada: $localDir"
    }

    $localScript = Join-Path $localDir $ScriptName

    # Monta raw URL com escape para cada segmento
    $catEsc = [System.Uri]::EscapeDataString($Category)
    $subEsc = [System.Uri]::EscapeDataString($Sub)
    $scriptEsc = [System.Uri]::EscapeDataString($ScriptName)
    $rawUrl = "$GitHubRawBase/$catEsc/$subEsc/$scriptEsc"

    $downloaded = $false
    try {
        Invoke-WebRequest -Uri $rawUrl -OutFile $localScript -UseBasicParsing -Headers $Global:GitHubHeaders -ErrorAction Stop
        Write-Log "Baixado: $rawUrl -> $localScript"
        $downloaded = $true
    } catch {
        Write-Log "Falha no download do script: $rawUrl - $($_.Exception.Message)"
        $downloaded = $false
    }

    if (-not (Test-Path $localScript)) {
        Write-Log "Script não disponível localmente e download falhou: $localScript"
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Não foi possível obter o script: $ScriptName`nVerifique sua conexão e tente novamente.", "Erro", "OK", "Error")
        return
    }

    try {
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$localScript`"" -Verb RunAs
        Write-Log "Executado: $localScript"
    } catch {
        Write-Log "Falha ao executar: $localScript - $($_.Exception.Message)"
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Falha ao executar o script: $ScriptName", "Erro", "OK", "Error")
    }
}

# ===============================
# Funções utilitárias originais mantidas
# ===============================
function Run-ScriptElevated($scriptPath) {
    if ($scriptPath -and $scriptPath.StartsWith($LocalCache) -and -not (Test-Path $scriptPath)) {
        # transformar localPath em Category/Sub/Script
        $rel = $scriptPath.Substring($LocalCache.Length).TrimStart('\','/')
        $parts = $rel -split '[\\/]'
        if ($parts.Count -ge 3) {
            $category = $parts[0]
            $sub = $parts[1]
            $scriptName = $parts[2..($parts.Count-1)] -join '\'
            Ensure-ScriptLocalAndExecute -Category $category -Sub $sub -ScriptName $scriptName
            return
        } else {
            Add-Type -AssemblyName PresentationFramework
            [System.Windows.MessageBox]::Show("Arquivo não encontrado: $scriptPath", "Erro", "OK", "Error")
            return
        }
    }

    if (-not (Test-Path $scriptPath)) {
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Arquivo não encontrado: $scriptPath", "Erro", "OK", "Error")
        return
    }
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
}

function Get-InfoText($scriptPath) {
    try {
        if ($scriptPath -and ($scriptPath.StartsWith($LocalCache))) {
            $rel = $scriptPath.Substring($LocalCache.Length).TrimStart('\','/')
            $txtRel = [System.IO.Path]::ChangeExtension($rel, ".txt")
            $segments = $txtRel -split '[\\/]'
            $escaped = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
            $rawUrl = "$GitHubRawBase/$($escaped -join '/')"
            try {
                $content = Invoke-RestMethod -Uri $rawUrl -Headers $Global:GitHubHeaders -ErrorAction Stop
                if ($null -ne $content) { return $content.ToString() }
            } catch {
                # fallback local
            }
        }
    } catch { }

    $txtFile = [System.IO.Path]::ChangeExtension($scriptPath, ".txt")
    if (Test-Path $txtFile) { return (Get-Content $txtFile -Raw) }
    else { return "Nenhuma documentação encontrada para este script." }
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

# ===============================
# Função: Efeito hover para botões (mantida)
# ===============================
function Add-HoverShadow {
    param($button)
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
# Janela principal (WPF) - estrutura visual idêntica ao original
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

# Cabeçalho
$topPanel = New-Object System.Windows.Controls.StackPanel
$topPanel.Orientation = "Horizontal"
$topPanel.HorizontalAlignment = "Center"
$topPanel.VerticalAlignment = "Center"
$topPanel.Margin = "0,15,0,15"

$logoPath = Join-Path $BasePath "Logo.png"
if (Test-Path $logoPath) {
    $logo = New-Object System.Windows.Controls.Image
    $logo.Source = New-Object System.Windows.Media.Imaging.BitmapImage([Uri]"file:///$logoPath")
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

# Tabs - Categorias
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

# Estilo arredondado dos botões
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

# Tema escuro padrão
$window.Background = "#0A1A33"
$tabControl.Background = "#102A4D"
$titleText.Foreground = "#FFFFFF"
$shadowEffect.Color = [System.Windows.Media.Colors]::LightBlue

# ===============================
# Função para carregar categorias e scripts (mantendo lógica original)
# ===============================
$ScriptCheckBoxes = @{}
function Load-Tabs {
    $tabControl.Items.Clear()
    $ScriptCheckBoxes.Clear()

    # Atualiza JSON e obtém estrutura
    $jsonPath = Update-StructureJson
    $remote = Get-StructureFromJson -jsonPath $jsonPath

    if ($remote -and $remote.Count -gt 0) {
        Ensure-LocalStructure -remoteList $remote
    } else {
        Write-Log "Remote vazio - mantendo estrutura local existente."
    }

    # Carrega categorias a partir de C:\Geset (assim como antes)
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
            # procura entrada no JSON para esse category/sub
            $entry = $remote | Where-Object { $_.Category -eq $category.Name -and $_.Sub -eq $sub.Name } | Select-Object -First 1
            if ($entry -and $entry.ScriptName) {
                $scriptName = $entry.ScriptName
            } else {
                # se não houver entry, tenta detectar localmente um *.ps1
                $localPs1 = Get-ChildItem -Path $sub.FullName -Filter *.ps1 -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($localPs1) { $scriptName = $localPs1.Name } else { continue }
            }

            # --- UI build para cada subfolder ---
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

            # checkbox
            $chk = New-Object System.Windows.Controls.CheckBox
            $chk.VerticalAlignment = "Center"
            $chk.Margin = "0,0,8,0"

            $localPathExpected = Join-Path $sub.FullName $scriptName
            $chk.Tag = $localPathExpected
            $ScriptCheckBoxes[$localPathExpected] = $chk
            [System.Windows.Controls.Grid]::SetColumn($chk, 0)

            # botão principal
            $btn = New-Object System.Windows.Controls.Button
            $btn.Content = $sub.Name
            $btn.Width = 200
            $btn.Height = 32
            $btn.Style = $roundedButtonStyle
            $btn.Tag = [PSCustomObject]@{
                Category = $category.Name
                Sub = $sub.Name
                ScriptName = $scriptName
            }
            $btn.VerticalAlignment = "Center"
            Add-HoverShadow $btn
            [System.Windows.Controls.Grid]::SetColumn($btn, 1)

            # botão info
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

            # Ao clicar: garante download e executa
            $btn.Add_Click({
                $meta = $this.Tag
                if ($meta -and $meta.Category -and $meta.Sub -and $meta.ScriptName) {
                    Ensure-ScriptLocalAndExecute -Category $meta.Category -Sub $meta.Sub -ScriptName $meta.ScriptName
                } else {
                    Add-Type -AssemblyName PresentationFramework
                    [System.Windows.MessageBox]::Show("Script não encontrado.", "Erro", "OK", "Error")
                }
            })

            # Info button: tenta mostrar .txt do raw, se não local
            $infoBtn.Add_Click({
                $meta = $this.Tag
                $infoText = "Nenhuma documentação encontrada para este script."
                try {
                    if ($meta -and $meta.Category -and $meta.Sub -and $meta.ScriptName) {
                        # monta URL do txt com escape por segmento
                        $catEsc = [System.Uri]::EscapeDataString($meta.Category)
                        $subEsc = [System.Uri]::EscapeDataString($meta.Sub)
                        $txtName = [System.IO.Path]::ChangeExtension($meta.ScriptName, '.txt')
                        $txtEsc = [System.Uri]::EscapeDataString($txtName)
                        $rawTxtUrl = "$GitHubRawBase/$catEsc/$subEsc/$txtEsc"
                        try {
                            $content = Invoke-RestMethod -Uri $rawTxtUrl -Headers $Global:GitHubHeaders -ErrorAction Stop
                            if ($null -ne $content) { $infoText = $content.ToString() }
                        } catch {
                            $candidateLocal = Join-Path $LocalCache ($meta.Category + "\" + $meta.Sub + "\" + [System.IO.Path]::ChangeExtension($meta.ScriptName, ".txt"))
                            if (Test-Path $candidateLocal) { $infoText = Get-Content $candidateLocal -Raw }
                        }
                    }
                } catch {}
                Show-InfoWindow -title $meta.Sub -content $infoText
            })
        }

        $tab.Content = $border
        $tabControl.Items.Add($tab)
    }
}

# ===============================
# Rodapé (sem alterações funcionais)
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

# Informações do sistema (direita)
$infoText = New-Object System.Windows.Controls.TextBlock
$infoText.HorizontalAlignment = "Right"
$infoText.VerticalAlignment = "Center"
$infoText.Foreground = "White"
$infoText.FontSize = 12
[System.Windows.Controls.Grid]::SetColumn($infoText, 1)
$footerGrid.Children.Add($infoText)

# Atualiza data/hora e nome do PC dinamicamente (timer)
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
        Add-Type -AssemblyName PresentationFramework
        [System.Windows.MessageBox]::Show("Nenhum script selecionado.", "Aviso", "OK", "Warning") | Out-Null
        return
    }
    foreach ($script in $selected) {
        # se arquivo existe localmente, executa
        if (Test-Path $script) {
            Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$script`"" -Verb RunAs -Wait
        } else {
            # tenta deduzir category/sub/script do caminho esperado e baixar/rodar
            $rel = $script.Substring($LocalCache.Length).TrimStart('\','/')
            $parts = $rel -split '[\\/]'
            if ($parts.Count -ge 3) {
                $category = $parts[0]
                $sub = $parts[1]
                $scriptName = $parts[2..($parts.Count-1)] -join '\'
                Ensure-ScriptLocalAndExecute -Category $category -Sub $sub -ScriptName $scriptName
            } else {
                Write-Log "Execução em lote: caminho inválido $script"
            }
        }
    }
    Add-Type -AssemblyName PresentationFramework
    [System.Windows.MessageBox]::Show("Execução concluída.", "GESET Launcher", "OK", "Information")
})

$BtnRefresh.Add_Click({
    Write-Log "Atualização solicitada pelo usuário."
    Load-Tabs
})

$BtnExit.Add_Click({ $window.Close() })

# ===============================
# Inicialização
# - obtém structure.json, cria pastas locais e carrega as abas
# ===============================
try {
    $jsonPath = Update-StructureJson
    $remoteList = Get-StructureFromJson -jsonPath $jsonPath
    if ($remoteList -and $remoteList.Count -gt 0) {
        Ensure-LocalStructure -remoteList $remoteList
    }
} catch {
    Write-Log "Erro na sincronização inicial: $($_.Exception.Message)"
}
Load-Tabs
$window.ShowDialog() | Out-Null

Write-Log "Launcher finalizado."
# ===============================
