# ===============================
# GESET Launcher - Interface WPF (Tema Escuro + Ocultação e Elevação)
# + Execução sob-demanda via GitHub API
# - Baixa .ps1 somente ao clicar no botão
# - Mantém estrutura original e comportamento (nova janela para execução)
# - Log em C:\Geset\logs\Launcher.log
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

# ===============================
# Configurações (cache local, GitHub)
# ===============================
$LocalCache = "C:\Geset"
$LogPath = Join-Path $LocalCache "logs"
$LogFile = Join-Path $LogPath "Launcher.log"
$GitHubContentsBase = "https://api.github.com/repos/DiegoGeset/Geset/contents"
$GitHubRawBase = "https://raw.githubusercontent.com/DiegoGeset/Geset/main"
$Global:GitHubHeaders = @{ 'User-Agent' = 'GESET-Launcher' }

# Garante diretórios locais
if (-not (Test-Path $LocalCache)) { New-Item -Path $LocalCache -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $LogPath))   { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

# Função de log simples (append)
function Write-Log {
    param([string]$Message)
    try {
        $time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $line = "$time`t$Message"
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch {
        # não quebrar UI se log falhar
    }
}

Write-Log "Launcher iniciado."

# ===============================
# Funções de suporte GitHub / download
# ===============================

# Escapa cada segmento de caminho (para lidar com espaços / acentos)
function Build-GitHubApiUrl {
    param([string]$RelativePath)
    if ([string]::IsNullOrEmpty($RelativePath)) {
        return $GitHubContentsBase
    } else {
        $segments = $RelativePath -split '/'
        $escaped = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
        return "$GitHubContentsBase/" + ($escaped -join '/')
    }
}

# Chama a API /contents e retorna JSON ou $null
function Get-GitHubContents {
    param([string]$RelativePath)
    try {
        $url = Build-GitHubApiUrl -RelativePath $RelativePath
        return Invoke-RestMethod -Uri $url -Headers $Global:GitHubHeaders -ErrorAction Stop
    } catch {
        # registro debug opcional no log
        Write-Log "Get-GitHubContents falhou para '$RelativePath': $($_.Exception.Message)"
        return $null
    }
}

# Calcula git-blob SHA1 de arquivo local (compatível com API sha)
function Get-LocalGitBlobSha1 {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $null }
    try {
        $bytes = [System.IO.File]::ReadAllBytes($FilePath)
        $len = $bytes.Length
        $header = [System.Text.Encoding]::ASCII.GetBytes("blob $len`0")
        $combined = New-Object byte[] ($header.Length + $bytes.Length)
        [Array]::Copy($header, 0, $combined, 0, $header.Length)
        [Array]::Copy($bytes, 0, $combined, $header.Length, $bytes.Length)
        $sha1 = [System.Security.Cryptography.SHA1]::Create()
        $hash = $sha1.ComputeHash($combined)
        $hex = ($hash | ForEach-Object { $_.ToString("x2") }) -join ''
        return $hex
    } catch {
        return $null
    }
}

# Faz download silencioso se necessário: compara SHA se fornecido; salva em LocalPath
function Download-FromUrlIfNeeded {
    param(
        [string]$DownloadUrl,
        [string]$LocalPath,
        [string]$ExpectedSha = $null
    )
    $folder = Split-Path $LocalPath -Parent
    if (-not (Test-Path $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }

    $needDownload = $false
    if (-not (Test-Path $LocalPath)) {
        $needDownload = $true
    } elseif ($ExpectedSha) {
        try {
            $localSha = Get-LocalGitBlobSha1 -FilePath $LocalPath
            if ($localSha -ne $ExpectedSha) { $needDownload = $true }
        } catch {
            $needDownload = $true
        }
    }

    if ($needDownload) {
        try {
            Invoke-WebRequest -Uri $DownloadUrl -OutFile $LocalPath -Headers $Global:GitHubHeaders -UseBasicParsing -ErrorAction Stop
            Write-Log "Baixado: $LocalPath"
        } catch {
            Write-Log "Falha ao baixar $DownloadUrl -> $LocalPath : $($_.Exception.Message)"
        }
    } else {
        Write-Log "Arquivo já está atualizado: $LocalPath"
    }

    return $LocalPath
}

# ===============================
# Função para ler descrição (.txt) do GitHub raw (sem baixar)
# ===============================
function Get-InfoTextFromGitHub {
    param([string]$Category, [string]$Sub, [string]$ScriptFileName)
    try {
        $txtRel = "$Category/$Sub/$([System.IO.Path]::ChangeExtension($ScriptFileName, '.txt'))"
        $segments = $txtRel -split '/'
        $escaped = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
        $rawUrl = "$GitHubRawBase/$($escaped -join '/')"
        $content = Invoke-RestMethod -Uri $rawUrl -Headers $Global:GitHubHeaders -ErrorAction Stop
        if ($null -ne $content) { return $content.ToString() }
    } catch {
        # fallback será tentar local
        Write-Log "Get-InfoTextFromGitHub falhou para $Category/$Sub/$ScriptFileName"
    }
    return $null
}

# ===============================
# Função: Montar lista de scripts (sem baixar) a partir da API
# Retorna objeto = @{ Category=..., Sub=..., ScriptName=..., DownloadUrl=..., Sha=... }
# ===============================
function Get-RemoteScriptsList {
    $result = @()

    $root = Get-GitHubContents -RelativePath ""
    if (-not $root) {
        Write-Log "API root vazia ou inacessível. Usando cache local."
        return $result
    }

    $categories = $root | Where-Object { $_.type -eq "dir" } | ForEach-Object { $_.name }

    foreach ($category in $categories) {
        $catJson = Get-GitHubContents -RelativePath $category
        if (-not $catJson) { continue }
        $subfolders = $catJson | Where-Object { $_.type -eq "dir" } | ForEach-Object { $_.name }

        foreach ($sub in $subfolders) {
            $subRel = "$category/$sub"
            $subJson = Get-GitHubContents -RelativePath $subRel
            if (-not $subJson) { continue }

            # procura por arquivos .ps1 primeiro (todos), se não houver, aceita .exe
            $psFiles = $subJson | Where-Object { $_.type -eq "file" -and $_.name -match '\.ps1$' }
            $exeFiles = $subJson | Where-Object { $_.type -eq "file" -and $_.name -match '\.exe$' }

            $chosen = @()
            if ($psFiles.Count -gt 0) {
                $chosen = $psFiles
            } elseif ($exeFiles.Count -gt 0) {
                $chosen = $exeFiles
            }

            foreach ($fileItem in $chosen) {
                $obj = [PSCustomObject]@{
                    Category    = $category
                    Sub         = $sub
                    ScriptName  = $fileItem.name
                    DownloadUrl = $fileItem.download_url
                    Sha         = $fileItem.sha
                }
                $result += $obj
            }
        }
    }

    return $result
}

# ===============================
# Função: Quando clicar no botão — baixar (se necessário) e executar em nova janela
# Recebe objeto Tag com propriedades: Category, Sub, ScriptName, DownloadUrl, Sha
# ===============================
function On-ScriptButtonClick {
    param([object]$tagObj)

    try {
        $category = $tagObj.Category
        $sub = $tagObj.Sub
        $scriptName = $tagObj.ScriptName
        $downloadUrl = $tagObj.DownloadUrl
        $remoteSha = $tagObj.Sha

        $localDir = Join-Path $LocalCache ($category + "\" + $sub)
        if (-not (Test-Path $localDir)) { New-Item -Path $localDir -ItemType Directory -Force | Out-Null; Write-Log "Criada pasta: $localDir" }

        $localScript = Join-Path $localDir $scriptName

        # Download/substituição silenciosa se necessário
        Download-FromUrlIfNeeded -DownloadUrl $downloadUrl -LocalPath $localScript -ExpectedSha $remoteSha

        # Executa em nova janela do PowerShell com elevação (como comportamento original)
        try {
            Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$localScript`"" -Verb RunAs
            Write-Log "Executado: $localScript"
        } catch {
            Write-Log "Falha ao executar $localScript : $($_.Exception.Message)"
            [System.Windows.MessageBox]::Show("Falha ao executar o script: $scriptName", "Erro", "OK", "Error")
        }

    } catch {
        Write-Log "On-ScriptButtonClick falhou: $($_.Exception.Message)"
    }
}

# ===============================
# Funções de UI originais (mantidas)
# ===============================
function Run-ScriptElevated($scriptPath) {
    if (-not (Test-Path $scriptPath)) {
        [System.Windows.MessageBox]::Show("Arquivo não encontrado: $scriptPath", "Erro", "OK", "Error")
        return
    }
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
}

function Get-InfoText($scriptPath) {
    # Tenta extrair Category/Sub/script a partir do localPath para solicitar raw .txt
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
    } catch {}

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
# Janela principal (mantida idêntica ao original)
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
# Função para carregar categorias e scripts (API-driven, sem baixar)
# ===============================
$ScriptCheckBoxes = @{}

function Load-Tabs {
    $tabControl.Items.Clear()
    $ScriptCheckBoxes.Clear()

    # Obtem lista remota (estrutura)
    $remoteList = Get-RemoteScriptsList

    # Se remoto estiver vazio (API falhou), tenta montar a partir do cache local
    if (-not $remoteList -or $remoteList.Count -eq 0) {
        Write-Log "Remote list vazia — gerando a partir de C:\Geset"
        $remoteList = @()
        $cats = Get-ChildItem -Path $LocalCache -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @("logs","Logs") }
        foreach ($c in $cats) {
            $subs = Get-ChildItem -Path $c.FullName -Directory -ErrorAction SilentlyContinue
            foreach ($s in $subs) {
                $ps = Get-ChildItem -Path $s.FullName -Filter *.ps1 -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($ps) {
                    $obj = [PSCustomObject]@{
                        Category    = $c.Name
                        Sub         = $s.Name
                        ScriptName  = $ps.Name
                        DownloadUrl = "$GitHubRawBase/$([System.Uri]::EscapeDataString($c.Name))/ $([System.Uri]::EscapeDataString($s.Name))/ $([System.Uri]::EscapeDataString($ps.Name))".Trim()
                        Sha         = Get-LocalGitBlobSha1 -FilePath $ps.FullName
                    }
                    $remoteList += $obj
                }
            }
        }
    }

    # Agrupar por categoria
    $grouped = $remoteList | Group-Object -Property Category

    foreach ($grp in $grouped) {
        $category = $grp.Name
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

        foreach ($entry in $grp.Group) {
            $sub = $entry.Sub
            $scriptName = $entry.ScriptName
            $downloadUrl = $entry.DownloadUrl
            $sha = $entry.Sha

            # Tag object to keep metadata for on-click
            $tagObj = [PSCustomObject]@{
                Category    = $category
                Sub         = $sub
                ScriptName  = $scriptName
                DownloadUrl = $downloadUrl
                Sha         = $sha
            }

            # Build UI only if scriptName exists
            if ($scriptName) {
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
                # Tag only local path not known yet; store later if downloaded. For multi-select execution, we'll use ScriptCheckBoxes keys as local path placeholder = remote path string
                $remotePlaceholder = "$($category)/$($sub)/$($scriptName)"
                $chk.Tag = $remotePlaceholder
                $ScriptCheckBoxes[$remotePlaceholder] = $chk
                [System.Windows.Controls.Grid]::SetColumn($chk, 0)

                $btn = New-Object System.Windows.Controls.Button
                $btn.Content = $sub
                $btn.Width = 200
                $btn.Height = 32
                $btn.Style = $roundedButtonStyle
                # store tag metadata object
                $btn.Tag = $tagObj
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
                $infoBtn.Tag = $tagObj
                $infoBtn.VerticalAlignment = "Center"
                Add-HoverShadow $infoBtn
                [System.Windows.Controls.Grid]::SetColumn($infoBtn, 2)

                $innerGrid.Children.Add($chk)
                $innerGrid.Children.Add($btn)
                $innerGrid.Children.Add($infoBtn)
                $sp.Children.Add($innerGrid)
                $panel.Children.Add($sp)

                # Click: baixar se necessário e executar
                $btn.Add_Click({
                    $t = $this.Tag
                    On-ScriptButtonClick -tagObj $t
                })

                # Info click: tenta buscar .txt do raw, se não, tenta local
                $infoBtn.Add_Click({
                    $t = $this.Tag
                    # tenta obter info do raw (sem download)
                    $info = $null
                    try {
                        $info = Get-InfoTextFromGitHub -Category $t.Category -Sub $t.Sub -ScriptFileName $t.ScriptName
                    } catch {}
                    if (-not $info) {
                        # se o arquivo local existir, use-o
                        $localCandidate = Join-Path $LocalCache ($t.Category + "\" + $t.Sub + "\" + $t.ScriptName)
                        $txtLocal = [System.IO.Path]::ChangeExtension($localCandidate, ".txt")
                        if (Test-Path $txtLocal) { $info = Get-Content $txtLocal -Raw }
                    }
                    if (-not $info) { $info = "Nenhuma documentação encontrada para este script." }
                    Show-InfoWindow -title $t.Sub -content $info
                })
            }
        }

        $tab.Content = $border
        $tabControl.Items.Add($tab)
    }
}

# ===============================
# Rodapé (idêntico ao original)
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
    # Executa todos os scripts marcados (multi-select)
    $selectedKeys = $ScriptCheckBoxes.GetEnumerator() | Where-Object { $_.Value.IsChecked -eq $true } | ForEach-Object { $_.Key }
    if ($selectedKeys.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Nenhum script selecionado.", "Aviso", "OK", "Warning") | Out-Null
        return
    }

    foreach ($key in $selectedKeys) {
        # key = "Category/Sub/ScriptName"
        $parts = $key -split '/'
        if ($parts.Count -lt 3) { continue }
        $category = $parts[0]
        $sub = $parts[1]
        $scriptName = $parts[2]
        # Consultar API para obter download_url e sha (sempre atual)
        $subJson = Get-GitHubContents -RelativePath "$category/$sub"
        if ($subJson) {
            $fileItem = $subJson | Where-Object { $_.type -eq "file" -and $_.name -eq $scriptName } | Select-Object -First 1
            if ($fileItem) {
                $tagObj = [PSCustomObject]@{
                    Category = $category
                    Sub = $sub
                    ScriptName = $fileItem.name
                    DownloadUrl = $fileItem.download_url
                    Sha = $fileItem.sha
                }
                On-ScriptButtonClick -tagObj $tagObj
            } else {
                Write-Log "Arquivo selecionado não encontrado no remote: $key"
            }
        } else {
            # fallback: tentar executar arquivo local (se existir)
            $localCandidate = Join-Path $LocalCache ($category + "\" + $sub + "\" + $scriptName)
            if (Test-Path $localCandidate) {
                Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$localCandidate`"" -Verb RunAs
                Write-Log "Executado (fallback local): $localCandidate"
            } else {
                Write-Log "Não foi possível localizar $key no remote nem local."
            }
        }
    }

    [System.Windows.MessageBox]::Show("Execução concluída.", "GESET Launcher", "OK", "Information")
})

# Botão Atualizar: reconsulta a API e recarrega abas
$BtnRefresh.Add_Click({
    Write-Log "Atualização solicitada pelo usuário."
    Load-Tabs
})

$BtnExit.Add_Click({ $window.Close() })

# ===============================
# Inicialização
# ===============================
# Carrega abas a partir da API (sem baixar scripts). Se API indisponível, usa cache local.
Load-Tabs
$window.ShowDialog() | Out-Null

Write-Log "Launcher finalizado."
