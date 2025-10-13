# ===============================
# GESET Launcher - Interface WPF (Tema Escuro + Ocultação e Elevação)
# Integrado com GitHub (RAW HTML parsing) - Mantém estrutura original
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
# Config / Paths / GitHub
# ===============================
# Mantém BasePath para compatibilidade com o seu código original, mas aponta para C:\Geset
$LocalCache = "C:\Geset"
$BasePath = $LocalCache

$LogPath = Join-Path $LocalCache "Logs"
$LogFile = Join-Path $LogPath "Launcher.log"

$RepoOwner = "DiegoGeset"
$RepoName = "Geset"
$Branch = "main"
$RepoHtmlRoot = "https://github.com/$RepoOwner/$RepoName/tree/$Branch"
$RawRoot = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"

# User-Agent para evitar problemas
# --- ADIÇÃO: Suporta autenticação via token (se existir em GITHUB_TOKEN) ---
# OPÇÃO A: Token visível/editável no início do script (você pediu)
# Substitua o valor abaixo pelo seu token pessoal do GitHub:
$GitHubToken = "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"

$Global:GitHubHeaders = @{
    'User-Agent' = 'GESET-Launcher'
    'Accept'     = 'application/vnd.github.v3+json'
}
if ($GitHubToken -and $GitHubToken -ne "") {
    $Global:GitHubHeaders['Authorization'] = "token $GitHubToken"
}
# FIM DA ADIÇÃO

# Garante pastas locais (cache e logs)
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
# Funções utilitárias GitHub / Download / URL encode
# ===============================

# Escape de segmentos (nome de pasta/arquivo)
function Encode-Segment {
    param([string]$s)
    if ($null -eq $s) { return "" }
    return [System.Uri]::EscapeDataString($s)
}

# Monta URL RAW com segmentos corretamente codificados
function Build-RawUrl {
    param(
        [string]$category,
        [string]$sub,
        [string]$fileName
    )
    $parts = @()
    if ($category) { $parts += (Encode-Segment $category) }
    if ($sub) { $parts += (Encode-Segment $sub) }
    if ($fileName) { $parts += (Encode-Segment $fileName) }
    return "$RawRoot/" + ($parts -join '/')
}

# Faz download silencioso de uma URL RAW para o caminho local desejado (substitui)
function Download-RawFile {
    param(
        [string]$rawUrl,
        [string]$localPath
    )
    try {
        $folder = Split-Path $localPath -Parent
        if (-not (Test-Path $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
        # RAW endpoint não aceita Authorization header; mas não faz mal enviar User-Agent/Accept
        Invoke-WebRequest -Uri $rawUrl -OutFile $localPath -UseBasicParsing -Headers @{ 'User-Agent' = $Global:GitHubHeaders['User-Agent']; 'Accept' = $Global:GitHubHeaders['Accept'] } -ErrorAction Stop
        Write-Log "Baixado: $rawUrl -> $localPath"
        return $true
    } catch {
        Write-Log "Falha no Download-RawFile: $rawUrl -> $localPath : $($_.Exception.Message)"
        return $false
    }
}

# Parseia página HTML do GitHub e retorna links relevantes com /tree/main/ ou /blob/main/
# Retorna coleção de strings (os caminhos relativos depois do branch)
# Mantive a função para compatibilidade, mas não é mais utilizada pelo Get-RemoteStructure.
function Parse-GitHubHtmlPaths {
    param([string]$relativePath)
    try {
        if ([string]::IsNullOrEmpty($relativePath)) {
            $url = $RepoHtmlRoot
        } else {
            $segments = $relativePath -split '/'
            $escaped = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
            $url = "$RepoHtmlRoot/" + ($escaped -join '/')
        }

        # IMPORTANTE: para HTML parsing do github.com usamos requisição ANÔNIMA (sem Authorization)
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop

        # coletar links que contenham /tree/main/ (pastas) e /blob/main/ (arquivos)
        $links = $resp.Links | Where-Object { $_.href -and ($_.href -match "/$RepoOwner/$RepoName/(tree|blob)/$Branch/") }

        $items = $links | ForEach-Object {
            $href = $_.href
            # extrai tudo após /<branch>/
            $parts = $href.Split('/')
            $idx = [Array]::IndexOf($parts, $Branch)
            if ($idx -ge 0 -and $parts.Length -gt ($idx+1)) {
                $remaining = $parts[($idx+1)..($parts.Length-1)] -join '/'
                return $remaining
            }
            return $null
        } | Where-Object { $_ -ne $null } | Sort-Object -Unique

        return $items
    } catch {
        Write-Log "Parse-GitHubHtmlPaths falhou para '$relativePath': $($_.Exception.Message)"
        return @()
    }
}

# ===============================
# Get-RemoteStructure (ATUALIZADA para usar a API do GitHub autenticada)
# Mantém assinatura e formato de retorno originais:
# Retorna array de objetos @{Category=..; Sub=..; ScriptName=..}
# ===============================
function Get-RemoteStructure {
    $result = @()

    Write-Log "Get-RemoteStructure iniciada (API parsing)."

    try {
        # 1) listar itens na raiz do repositório via API
        $apiRoot = "https://api.github.com/repos/$RepoOwner/$RepoName/contents?ref=$Branch"
        $rootItems = Invoke-RestMethod -Uri $apiRoot -Headers $Global:GitHubHeaders -ErrorAction Stop

        # filtra apenas diretórios top-level
        $topDirs = $rootItems | Where-Object { $_.type -eq 'dir' }

        if (-not $topDirs -or $topDirs.Count -eq 0) {
            Write-Log "Nenhuma pasta detectada na raiz via API."
            return $result
        }

        foreach ($dir in $topDirs) {
            $cat = $dir.name

            # obter conteúdo da categoria (lista subpastas e arquivos)
            $apiCat = "https://api.github.com/repos/$RepoOwner/$RepoName/contents/$($dir.path)?ref=$Branch"
            $catItems = @()
            try {
                $catItems = Invoke-RestMethod -Uri $apiCat -Headers $Global:GitHubHeaders -ErrorAction Stop
            } catch {
                Write-Log "Falha ao obter categoria $cat via API: $($_.Exception.Message)"
                $catItems = @()
            }

            # subpastas: itens do tipo dir dentro da categoria
            $subdirs = $catItems | Where-Object { $_.type -eq 'dir' } | Sort-Object -Property name

            if (-not $subdirs -or $subdirs.Count -eq 0) {
                # Caso não haja subdiretórios, mas haja arquivos .ps1 diretamente na categoria,
                # tratamos como Sub vazio ou único.
                $psFiles = $catItems | Where-Object { $_.type -eq 'file' -and $_.name -like "*.ps1" } | Sort-Object -Property name
                if ($psFiles -and $psFiles.Count -gt 0) {
                    # usamos uma sub "root" com nome do próprio category para compatibilidade
                    $subName = $cat
                    $scriptName = $psFiles[0].name
                    $result += [PSCustomObject]@{ Category = $cat; Sub = $subName; ScriptName = $scriptName }
                    Write-Log "Remoto: $cat / $subName -> $scriptName"
                } else {
                    # nenhuma informação - cria entrada sem script para manter estrutura
                    $result += [PSCustomObject]@{ Category = $cat; Sub = $null; ScriptName = $null }
                    Write-Log "Remoto (sem sub/ps1): $cat"
                }
            } else {
                foreach ($subdir in $subdirs) {
                    $sub = $subdir.name
                    # listar conteúdo do subdir
                    $apiSub = "https://api.github.com/repos/$RepoOwner/$RepoName/contents/$($subdir.path)?ref=$Branch"
                    $subItems = @()
                    try {
                        $subItems = Invoke-RestMethod -Uri $apiSub -Headers $Global:GitHubHeaders -ErrorAction Stop
                    } catch {
                        Write-Log "Falha ao obter subdir $sub do cat $cat via API: $($_.Exception.Message)"
                        $subItems = @()
                    }

                    # procurar arquivos que terminam com .ps1 (caso existam)
                    $ps1 = $subItems | Where-Object { $_.type -eq 'file' -and ($_.name -match "\.ps1$") } | Sort-Object -Property name

                    if ($ps1 -and $ps1.Count -gt 0) {
                        # Usa o primeiro .ps1 encontrado (comportamento original)
                        $scriptName = $ps1[0].name
                        $result += [PSCustomObject]@{ Category = $cat; Sub = $sub; ScriptName = $scriptName }
                        Write-Log "Remoto: $cat / $sub -> $scriptName"
                    } else {
                        # não tem .ps1 conhecido (mas queremos criar a pasta local para manter estrutura)
                        $result += [PSCustomObject]@{ Category = $cat; Sub = $sub; ScriptName = $null }
                        Write-Log "Remoto (sem ps1): $cat / $sub"
                    }
                }
            }
        }

    } catch {
        Write-Log "Get-RemoteStructure falhou (API): $($_.Exception.Message)"
    }

    return $result
}

# ===============================
# Função: Cria estrutura local (pastas) conforme lista remota.
# Não baixa scripts agora — apenas cria pastas e deixa pronto.
# ===============================
function Ensure-LocalStructure {
    param([array]$remoteList)

    # Se nenhum remoteList foi fornecido, obtenha internamente
    if (-not $remoteList) {
        try {
            $remoteList = Get-RemoteStructure
        } catch {
            Write-Log "Ensure-LocalStructure: Get-RemoteStructure falhou: $($_.Exception.Message)"
            $remoteList = @()
        }
    }

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
# Função: Baixa script .ps1 antes da execução (sempre tenta baixar - substitui local)
# Se falhar (sem internet), tenta usar arquivo local existente.
# ===============================
function Ensure-ScriptLocalAndExecute {
    param([string]$Category, [string]$Sub, [string]$ScriptName)

    if (-not $ScriptName) {
        Write-Log "Ensure-ScriptLocalAndExecute chamado sem ScriptName para $Category / $Sub"
        [System.Windows.MessageBox]::Show("Script não encontrado no repositório: $Category / $Sub", "Erro", "OK", "Error")
        return
    }

    $localDir = Join-Path $LocalCache ($Category + "\" + $Sub)
    if (-not (Test-Path $localDir)) { New-Item -Path $localDir -ItemType Directory -Force | Out-Null; Write-Log "Criada pasta forçada: $localDir" }

    $localScript = Join-Path $localDir $ScriptName
    $rawUrl = Build-RawUrl -category $Category -sub $Sub -fileName $ScriptName

    # tenta baixar e substituir silenciosamente
    $downloaded = $false
    try {
        $downloaded = Download-RawFile -rawUrl $rawUrl -localPath $localScript
    } catch {
        $downloaded = $false
    }

    if (-not (Test-Path $localScript)) {
        Write-Log "Script não disponível localmente e download falhou: $localScript"
        [System.Windows.MessageBox]::Show("Não foi possível obter o script: $ScriptName`nVerifique sua conexão e tente novamente.", "Erro", "OK", "Error")
        return
    }

    # Executa em nova janela com elevação (mantendo comportamento original)
    try {
        Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$localScript`"" -Verb RunAs
        Write-Log "Executado: $localScript"
    } catch {
        Write-Log "Falha ao executar: $localScript - $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Falha ao executar o script: $ScriptName", "Erro", "OK", "Error")
    }
}

# ===============================
# Funções utilitárias originais mantidas (conforme seu código)
# ===============================
function Run-ScriptElevated($scriptPath) {
    # Antes de executar, se o arquivo for esperado dentro do cache e não existir, tenta baixar do raw automaticamente.
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
            [System.Windows.MessageBox]::Show("Arquivo não encontrado: $scriptPath", "Erro", "OK", "Error")
            return
        }
    }

    if (-not (Test-Path $scriptPath)) {
        [System.Windows.MessageBox]::Show("Arquivo não encontrado: $scriptPath", "Erro", "OK", "Error")
        return
    }
    Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`"" -Verb RunAs
}

function Get-InfoText($scriptPath) {
    # tenta ler .txt do raw do github se o script estiver dentro do cache (montado), caso contrário lê local
    try {
        if ($scriptPath -and ($scriptPath.StartsWith($LocalCache))) {
            $rel = $scriptPath.Substring($LocalCache.Length).TrimStart('\','/')
            $txtRel = [System.IO.Path]::ChangeExtension($rel, ".txt")
            $segments = $txtRel -split '[\\/]'
            $escaped = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
            $rawUrl = "$RawRoot/$($escaped -join '/')"
            try {
                # RAW não precisa de Authorization; usamos apenas User-Agent/Accept
                $content = Invoke-RestMethod -Uri $rawUrl -Headers @{ 'User-Agent' = $Global:GitHubHeaders['User-Agent']; 'Accept' = $Global:GitHubHeaders['Accept'] } -ErrorAction Stop
                if ($null -ne $content) { return $content.ToString() }
            } catch {
                # fallback local
            }
        }
    } catch { }

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
# Função para carregar categorias e scripts (mantida a lógica do original, base local C:\Geset)
# ===============================
$ScriptCheckBoxes = @{}
function Load-Tabs {
    $tabControl.Items.Clear()
    $ScriptCheckBoxes.Clear()

    # Primeiro, tenta obter estrutura remota e criar pastas locais (silencioso)
    $remote = @()
    try {
        $remote = Get-RemoteStructure
    } catch {
        Write-Log "Get-RemoteStructure falhou: $($_.Exception.Message)"
    }

    if ($remote -and $remote.Count -gt 0) {
        Ensure-LocalStructure -remoteList $remote
    } else {
        Write-Log "Remote vazio - mantendo estrutura local existente."
    }

    # Carrega categorias a partir de C:\Geset (como no código original lendo $BasePath)
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
            # aqui: procuramos o .ps1 local (caso já exista no cache)
            $scriptFile = Get-ChildItem -Path $sub.FullName -Filter *.ps1 -File -ErrorAction SilentlyContinue | Select-Object -First 1

            # Se não existir local, determinamos o nome do script a partir da lista remota (se disponível)
            if (-not $scriptFile) {
                # tenta buscar no $remote que pegamos antes
                $entry = $remote | Where-Object { $_.Category -eq $category.Name -and $_.Sub -eq $sub.Name } | Select-Object -First 1
                if ($entry -and $entry.ScriptName) {
                    # define o caminho local esperado (ainda não baixado)
                    $expectedLocal = Join-Path $sub.FullName $entry.ScriptName
                    $scriptFile = New-Object System.IO.FileInfo($expectedLocal)
                } else {
                    # se remoto não informar scriptName, pule (mantendo o comportamento seguro)
                    continue
                }
            }

            if ($scriptFile) {
                # --- UI build (igual ao original) ---
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

                # Tag para checkbox: use o caminho local esperado (mesmo que ainda não exista)
                $localPathExpected = $scriptFile.FullName
                $chk.Tag = $localPathExpected
                $ScriptCheckBoxes[$localPathExpected] = $chk
                [System.Windows.Controls.Grid]::SetColumn($chk, 0)

                $btn = New-Object System.Windows.Controls.Button
                $btn.Content = $sub.Name
                $btn.Width = 200
                $btn.Height = 32
                $btn.Style = $roundedButtonStyle
                # Tag do botão: armazena metadata (Category, Sub, ScriptName)
                $btn.Tag = [PSCustomObject]@{
                    Category = $category.Name
                    Sub = $sub.Name
                    ScriptName = [System.IO.Path]::GetFileName($localPathExpected)
                }
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
                $infoBtn.Tag = $btn.Tag
                $infoBtn.VerticalAlignment = "Center"
                Add-HoverShadow $infoBtn
                [System.Windows.Controls.Grid]::SetColumn($infoBtn, 2)

                $innerGrid.Children.Add($chk)
                $innerGrid.Children.Add($btn)
                $innerGrid.Children.Add($infoBtn)
                $sp.Children.Add($innerGrid)
                $panel.Children.Add($sp)

                # Ao clicar: garante download do script e executa (mantendo execução em nova janela)
                $btn.Add_Click({
                    $meta = $this.Tag
                    if ($meta -and $meta.Category -and $meta.Sub -and $meta.ScriptName) {
                        Ensure-ScriptLocalAndExecute -Category $meta.Category -Sub $meta.Sub -ScriptName $meta.ScriptName
                    } else {
                        [System.Windows.MessageBox]::Show("Script não encontrado.", "Erro", "OK", "Error")
                    }
                })

                # Info button: tenta mostrar .txt do raw, se não local
                $infoBtn.Add_Click({
                    $meta = $this.Tag
                    $infoText = "Nenhuma documentação encontrada para este script."
                    try {
                        if ($meta -and $meta.Category -and $meta.Sub -and $meta.ScriptName) {
                            # tenta raw .txt
                            $rawTxtUrl = Build-RawUrl -category $meta.Category -sub $meta.Sub -fileName ([System.IO.Path]::ChangeExtension($meta.ScriptName, ".txt"))
                            try {
                                # Use headers for REST where applicable, RAW endpoint uses User-Agent/Accept
                                $content = Invoke-RestMethod -Uri $rawTxtUrl -Headers @{ 'User-Agent' = $Global:GitHubHeaders['User-Agent']; 'Accept' = $Global:GitHubHeaders['Accept'] } -ErrorAction Stop
                                if ($null -ne $content) { $infoText = $content.ToString() }
                            } catch {
                                # fallback para local
                                $candidateLocal = Join-Path $LocalCache ($meta.Category + "\" + $meta.Sub + "\" + [System.IO.Path]::ChangeExtension($meta.ScriptName, ".txt"))
                                if (Test-Path $candidateLocal) { $infoText = Get-Content $candidateLocal -Raw }
                            }
                        }
                    } catch {}
                    Show-InfoWindow -title $sub.Name -content $infoText
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
# Ações dos botões (mantidas)
# ===============================
$BtnExec.Add_Click({
    $selected = $ScriptCheckBoxes.GetEnumerator() | Where-Object { $_.Value.IsChecked -eq $true } | ForEach-Object { $_.Key }
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show("Nenhum script selecionado.", "Aviso", "OK", "Warning") | Out-Null
        return
    }
    foreach ($script in $selected) {
        # '$script' é o caminho local esperado (Category/Sub/Script)
        if (Test-Path $script) {
            Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$script`"" -Verb RunAs -Wait
        } else {
            # tenta baixar/executar usando partes do caminho
            $rel = $script.Substring($LocalCache.Length).TrimStart('\','/')
            $parts = $rel -split '[\\/]'
            if ($parts.Count -ge 3) {
                $category = $parts[0]
                $sub = $parts[1]
                # recompor scriptName (em caso de nomes com \)
                $scriptName = $parts[2..($parts.Count-1)] -join '\'
                Ensure-ScriptLocalAndExecute -Category $category -Sub $sub -ScriptName $scriptName
            } else {
                Write-Log "Execução em lote: caminho inválido $script"
            }
        }
    }
    [System.Windows.MessageBox]::Show("Execução concluída.", "GESET Launcher", "OK", "Information")
})

$BtnRefresh.Add_Click({
    Write-Log "Atualização solicitada pelo usuário."
    try {
        $remoteList = Get-RemoteStructure
        Ensure-LocalStructure -remoteList $remoteList
    } catch {
        Write-Log "Erro ao atualizar manualmente: $($_.Exception.Message)"
    }
    Load-Tabs
})

$BtnExit.Add_Click({ $window.Close() })

# ===============================
# Inicialização
# - obtém estrutura remota (via API), cria pastas locais e carrega as abas
# ===============================
try {
    $remoteList = Get-RemoteStructure
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
