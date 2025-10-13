# ===============================
# GESET Launcher - Interface WPF (Tema Escuro + Ocultação e Elevação)
# + Execução sob-demanda via GitHub API
# - Baixa .ps1 somente ao clicar no botão
# - Mantém estrutura original e comportamento (nova janela para execução)
# - Log em C:\Geset\logs\Launcher.log
# Integrado com GitHub: cria estrutura em C:\Geset e baixa .ps1 sob demanda
# ===============================

# --- Oculta a janela do PowerShell ---
@@ -37,182 +34,200 @@ if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administra
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

# ===============================
# Configurações (cache local, GitHub)
# Configuração: cache local e GitHub
# ===============================
# Mantém BasePath para compatibilidade com o seu código original, mas aponta para C:\Geset
$LocalCache = "C:\Geset"
$LogPath = Join-Path $LocalCache "logs"
$BasePath = $LocalCache

$LogPath = Join-Path $LocalCache "Logs"
$LogFile = Join-Path $LogPath "Launcher.log"
$GitHubContentsBase = "https://api.github.com/repos/DiegoGeset/Geset/contents"
$GitHubRawBase = "https://raw.githubusercontent.com/DiegoGeset/Geset/main"

$RepoOwner = "DiegoGeset"
$RepoName = "Geset"
$Branch = "main"
$GitHubContentsBase = "https://api.github.com/repos/$RepoOwner/$RepoName/contents"
$GitHubRawBase = "https://raw.githubusercontent.com/$RepoOwner/$RepoName/$Branch"

$Global:GitHubHeaders = @{ 'User-Agent' = 'GESET-Launcher' }

# Garante diretórios locais
# Garante pastas locais
if (-not (Test-Path $LocalCache)) { New-Item -Path $LocalCache -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $LogPath))   { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }
if (-not (Test-Path $LogPath)) { New-Item -Path $LogPath -ItemType Directory -Force | Out-Null }

# Função de log simples (append)
# Função de log simples (silencioso)
function Write-Log {
    param([string]$Message)
    param([string]$msg)
    try {
        $time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        $line = "$time`t$Message"
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch {
        # não quebrar UI se log falhar
    }
        $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        "$t`t$msg" | Out-File -FilePath $LogFile -Append -Encoding UTF8
    } catch { }
}

Write-Log "Launcher iniciado."

# ===============================
# Funções de suporte GitHub / download
# Funções utilitárias GitHub / Download / URL encode
# ===============================
# Garante encoding correto de segmentos para URLs raw
function Encode-Segment {
    param([string]$s)
    if ($null -eq $s) { return "" }
    # Escape dois passos: EscapeDataString para segmentos
    return [System.Uri]::EscapeDataString($s)
}

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
# Constrói URL RAW com encoding
function Build-RawUrl {
    param([string]$category, [string]$sub, [string]$fileName)
    $parts = @()
    if ($category) { $parts += (Encode-Segment $category) }
    if ($sub) { $parts += (Encode-Segment $sub) }
    if ($fileName) { $parts += (Encode-Segment $fileName) }
    return "$GitHubRawBase/" + ($parts -join '/')
}

# Chama a API /contents e retorna JSON ou $null
function Get-GitHubContents {
    param([string]$RelativePath)
# Tenta chamar API /contents para um caminho (escape segmentos)
function Get-GitHubApiContents {
    param([string]$relativePath)
    try {
        $url = Build-GitHubApiUrl -RelativePath $RelativePath
        if ([string]::IsNullOrEmpty($relativePath)) {
            $url = $GitHubContentsBase
        } else {
            $segments = $relativePath -split '/'
            $escaped = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
            $url = "$GitHubContentsBase/" + ($escaped -join '/')
        }
        return Invoke-RestMethod -Uri $url -Headers $Global:GitHubHeaders -ErrorAction Stop
    } catch {
        # registro debug opcional no log
        Write-Log "Get-GitHubContents falhou para '$RelativePath': $($_.Exception.Message)"
        Write-Log "Get-GitHubApiContents falhou para '$relativePath': $($_.Exception.Message)"
        return $null
    }
}

# Calcula git-blob SHA1 de arquivo local (compatível com API sha)
function Get-LocalGitBlobSha1 {
    param([string]$FilePath)
    if (-not (Test-Path $FilePath)) { return $null }
# Fallback: tenta extrair subpastas usando o HTML do GitHub (quando API bloqueada)
function Parse-GitHubHtmlTree {
    param([string]$relativePath)
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
        if ([string]::IsNullOrEmpty($relativePath)) {
            $url = "https://github.com/$RepoOwner/$RepoName/tree/$Branch"
        } else {
            $segments = $relativePath -split '/'
            $escaped = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
            $url = "https://github.com/$RepoOwner/$RepoName/tree/$Branch/" + ($escaped -join '/')
        }
    } else {
        Write-Log "Arquivo já está atualizado: $LocalPath"
        $resp = Invoke-WebRequest -Uri $url -UseBasicParsing -ErrorAction Stop
        # Filtra links que apontam para tree/main/<relativePath>/...
        $links = $resp.Links | Where-Object { $_.href -and $_.href -match "/$RepoOwner/$RepoName/tree/$Branch/" }
        $items = $links | ForEach-Object {
            $href = $_.href
            # pegar o segmento após /tree/main/
            $parts = $href.Split('/') 
            # a parte após branch começa na posição index do branch +1
            $idx = [Array]::IndexOf($parts, $Branch)
            if ($idx -ge 0 -and $parts.Length -gt ($idx+1)) {
                # retorna os segmentos depois do branch
                $remaining = $parts[($idx+1)..($parts.Length-1)] -join '/'
                return $remaining
            }
            return $null
        } | Where-Object { $_ -ne $null } | Sort-Object -Unique
        return $items
    } catch {
        Write-Log "Parse-GitHubHtmlTree falhou para '$relativePath': $($_.Exception.Message)"
        return @()
    }

    return $LocalPath
}

# ===============================
# Função para ler descrição (.txt) do GitHub raw (sem baixar)
# ===============================
function Get-InfoTextFromGitHub {
    param([string]$Category, [string]$Sub, [string]$ScriptFileName)
# Baixa um arquivo RAW para local (sempre substitui silenciosamente)
function Download-RawFile {
    param([string]$rawUrl, [string]$localPath)
    try {
        $txtRel = "$Category/$Sub/$([System.IO.Path]::ChangeExtension($ScriptFileName, '.txt'))"
        $segments = $txtRel -split '/'
        $escaped = $segments | ForEach-Object { [System.Uri]::EscapeDataString($_) }
        $rawUrl = "$GitHubRawBase/$($escaped -join '/')"
        $content = Invoke-RestMethod -Uri $rawUrl -Headers $Global:GitHubHeaders -ErrorAction Stop
        if ($null -ne $content) { return $content.ToString() }
        $folder = Split-Path $localPath -Parent
        if (-not (Test-Path $folder)) { New-Item -Path $folder -ItemType Directory -Force | Out-Null }
        Invoke-WebRequest -Uri $rawUrl -OutFile $localPath -UseBasicParsing -Headers $Global:GitHubHeaders -ErrorAction Stop
        Write-Log "Baixado: $rawUrl -> $localPath"
        return $true
    } catch {
        # fallback será tentar local
        Write-Log "Get-InfoTextFromGitHub falhou para $Category/$Sub/$ScriptFileName"
        Write-Log "Falha no Download-RawFile: $rawUrl -> $localPath : $($_.Exception.Message)"
        return $false
    }
    return $null
}

# ===============================
# Função: Montar lista de scripts (sem baixar) a partir da API
# Retorna objeto = @{ Category=..., Sub=..., ScriptName=..., DownloadUrl=..., Sha=... }
# Função: Obter lista de categorias/subpastas/arquivo principal (.ps1) no repositório
# Resultado: array de objetos @{Category=..; Sub=..; ScriptName=..}
# Estratégia:
# - Tenta API para raiz; para cada categoria (dir), lista subdirs; para cada sub, pega primeiro *.ps1
# - Se API falhar, usa HTML fallback para descobrir subpastas e depois tenta API individual para obter arquivos
# ===============================
function Get-RemoteScriptsList {
function Get-RemoteStructure {
    $result = @()

    $root = Get-GitHubContents -RelativePath ""
    if (-not $root) {
        Write-Log "API root vazia ou inacessível. Usando cache local."
    # 1) tenta API raiz
    $root = Get-GitHubApiContents -relativePath ""
    if ($root) {
        $categories = $root | Where-Object { $_.type -eq 'dir' } | ForEach-Object { $_.name }
        foreach ($cat in $categories) {
            # obter conteudo do category
            $catJson = Get-GitHubApiContents -relativePath $cat
            if (-not $catJson) { continue }
            $subdirs = $catJson | Where-Object { $_.type -eq 'dir' } | ForEach-Object { $_.name }
            foreach ($sub in $subdirs) {
                $subRel = "$cat/$sub"
                $subJson = Get-GitHubApiContents -relativePath $subRel
                if (-not $subJson) { 
                    # criar pasta local mesmo que vazio
                    $result += [PSCustomObject]@{ Category = $cat; Sub = $sub; ScriptName = $null }
                    continue
                }
                # procura por ps1
                $ps1 = $subJson | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ps1$' } | Select-Object -First 1
                if ($ps1) {
                    $result += [PSCustomObject]@{ Category = $cat; Sub = $sub; ScriptName = $ps1.name }
                } else {
                    # se não tem ps1, adiciona null (a pasta será criada)
                    $result += [PSCustomObject]@{ Category = $cat; Sub = $sub; ScriptName = $null }
                }
            }
        }
        return $result
    }

    $categories = $root | Where-Object { $_.type -eq "dir" } | ForEach-Object { $_.name }

    foreach ($category in $categories) {
        $catJson = Get-GitHubContents -RelativePath $category
        if (-not $catJson) { continue }
        $subfolders = $catJson | Where-Object { $_.type -eq "dir" } | ForEach-Object { $_.name }
    Write-Log "API root vazia / inacessível - usando fallback HTML."
    # Fallback HTML: lista categorias via página tree, depois tenta API por sub para obter arquivos
    $categoriesHtml = Parse-GitHubHtmlTree -relativePath ""
    if (-not $categoriesHtml -or $categoriesHtml.Count -eq 0) {
        Write-Log "Fallback HTML não encontrou categorias."
        return $result
    }

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
    # categoriesHtml terá caminhos 'Category' ou 'Category/Sub...' - precisamos extrair top-level uniques
    $topCategories = $categoriesHtml | ForEach-Object { ($_ -split '/')[0] } | Sort-Object -Unique
    foreach ($cat in $topCategories) {
        # tenta obter subpastas via API individual; se falhar, usa HTML
        $catJson = Get-GitHubApiContents -relativePath $cat
        if ($catJson) {
            $subdirs = $catJson | Where-Object { $_.type -eq 'dir' } | ForEach-Object { $_.name }
        } else {
            # HTML parsing: pegar itens que iniciam com 'cat/'
            $subsFromHtml = $categoriesHtml | Where-Object { $_ -match ("^" + [regex]::Escape($cat) + "/") } | ForEach-Object { ($_ -split '/')[1] } | Sort-Object -Unique
            $subdirs = $subsFromHtml
        }

            foreach ($fileItem in $chosen) {
                $obj = [PSCustomObject]@{
                    Category    = $category
                    Sub         = $sub
                    ScriptName  = $fileItem.name
                    DownloadUrl = $fileItem.download_url
                    Sha         = $fileItem.sha
        foreach ($sub in $subdirs) {
            $subRel = "$cat/$sub"
            $subJson = Get-GitHubApiContents -relativePath $subRel
            if ($subJson) {
                $ps1 = $subJson | Where-Object { $_.type -eq 'file' -and $_.name -match '\.ps1$' } | Select-Object -First 1
                if ($ps1) {
                    $result += [PSCustomObject]@{ Category = $cat; Sub = $sub; ScriptName = $ps1.name }
                } else {
                    $result += [PSCustomObject]@{ Category = $cat; Sub = $sub; ScriptName = $null }
                }
                $result += $obj
            } else {
                # sem json, ainda cria a pasta
                $result += [PSCustomObject]@{ Category = $cat; Sub = $sub; ScriptName = $null }
            }
        }
    }
@@ -221,45 +236,87 @@ function Get-RemoteScriptsList {
}

# ===============================
# Função: Quando clicar no botão — baixar (se necessário) e executar em nova janela
# Recebe objeto Tag com propriedades: Category, Sub, ScriptName, DownloadUrl, Sha
# Função: Cria estrutura local (pastas) conforme lista remota.
# Não baixa scripts agora — apenas cria pastas e deixa pronto.
# ===============================
function On-ScriptButtonClick {
    param([object]$tagObj)
function Ensure-LocalStructure {
    param([array]$remoteList)

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
        Write-Log "On-ScriptButtonClick falhou: $($_.Exception.Message)"
        Write-Log "Falha ao executar: $localScript - $($_.Exception.Message)"
        [System.Windows.MessageBox]::Show("Falha ao executar o script: $ScriptName", "Erro", "OK", "Error")
    }
}

# ===============================
# Funções de UI originais (mantidas)
# Funções utilitárias originais mantidas
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
            # porém scriptName pode conter subpastas se existentes - tratamos apenas a primeira três níveis conforme estrutura padrão
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
@@ -268,7 +325,7 @@ function Run-ScriptElevated($scriptPath) {
}

function Get-InfoText($scriptPath) {
    # Tenta extrair Category/Sub/script a partir do localPath para solicitar raw .txt
    # tenta ler .txt do raw do github se o script estiver dentro do cache (montado), caso contrário lê local
    try {
        if ($scriptPath -and ($scriptPath.StartsWith($LocalCache))) {
            $rel = $scriptPath.Substring($LocalCache.Length).TrimStart('\','/')
@@ -283,7 +340,7 @@ function Get-InfoText($scriptPath) {
                # fallback local
            }
        }
    } catch {}
    } catch { }

    $txtFile = [System.IO.Path]::ChangeExtension($scriptPath, ".txt")
    if (Test-Path $txtFile) { Get-Content $txtFile -Raw }
@@ -482,47 +539,34 @@ $titleText.Foreground = "#FFFFFF"
$shadowEffect.Color = [System.Windows.Media.Colors]::LightBlue

# ===============================
# Função para carregar categorias e scripts (API-driven, sem baixar)
# Função para carregar categorias e scripts
# (mantida a lógica do original, mas agora a pasta base é C:\Geset)
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
    # Primeiro, tenta obter estrutura remota e criar pastas locais (silencioso)
    $remote = @()
    try {
        $remote = Get-RemoteStructure
    } catch {
        Write-Log "Get-RemoteStructure falhou: $($_.Exception.Message)"
    }

    # Agrupar por categoria
    $grouped = $remoteList | Group-Object -Property Category
    if ($remote -and $remote.Count -gt 0) {
        Ensure-LocalStructure -remoteList $remote
    } else {
        Write-Log "Remote vazio - mantendo estrutura local existente."
    }

    foreach ($grp in $grouped) {
        $category = $grp.Name
    # Carrega categorias a partir de C:\Geset (como no código original lendo $BasePath)
    $categories = Get-ChildItem -Path $BasePath -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -notin @("Logs") }

    foreach ($category in $categories) {
        $tab = New-Object System.Windows.Controls.TabItem
        $tab.Header = $category
        $tab.Header = $category.Name

        $border = New-Object System.Windows.Controls.Border
        $border.BorderThickness = "1"
@@ -544,23 +588,29 @@ function Load-Tabs {
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
                    # se remoto não informar scriptName, tentamos não adicionar botão (ou adiciona botão sem executar)
                    # para garantir compatibilidade com seu fluxo, vamos continuar apenas se existir ps1 ou remote entry was with script name
                    # se não existir scriptFile, pule
                    continue
                }
            }

            # Build UI only if scriptName exists
            if ($scriptName) {
            if ($scriptFile) {
                # --- UI build (igual ao original) ---
                $sp = New-Object System.Windows.Controls.StackPanel
                $sp.Orientation = "Horizontal"
                $sp.Margin = "0,0,0,8"
@@ -577,19 +627,24 @@ function Load-Tabs {
                $chk = New-Object System.Windows.Controls.CheckBox
                $chk.VerticalAlignment = "Center"
                $chk.Margin = "0,0,8,0"
                # Tag only local path not known yet; store later if downloaded. For multi-select execution, we'll use ScriptCheckBoxes keys as local path placeholder = remote path string
                $remotePlaceholder = "$($category)/$($sub)/$($scriptName)"
                $chk.Tag = $remotePlaceholder
                $ScriptCheckBoxes[$remotePlaceholder] = $chk

                # Tag para checkbox: use o caminho local esperado (mesmo que ainda não exista)
                $localPathExpected = $scriptFile.FullName
                $chk.Tag = $localPathExpected
                $ScriptCheckBoxes[$localPathExpected] = $chk
                [System.Windows.Controls.Grid]::SetColumn($chk, 0)

                $btn = New-Object System.Windows.Controls.Button
                $btn.Content = $sub
                $btn.Content = $sub.Name
                $btn.Width = 200
                $btn.Height = 32
                $btn.Style = $roundedButtonStyle
                # store tag metadata object
                $btn.Tag = $tagObj
                # Tag do botão: armazena metadata (Category, Sub, ScriptName)
                $btn.Tag = [PSCustomObject]@{
                    Category = $category.Name
                    Sub = $sub.Name
                    ScriptName = [System.IO.Path]::GetFileName($localPathExpected)
                }
                $btn.VerticalAlignment = "Center"
                Add-HoverShadow $btn
                [System.Windows.Controls.Grid]::SetColumn($btn, 1)
@@ -601,7 +656,7 @@ function Load-Tabs {
                $infoBtn.Margin = "8,0,0,0"
                $infoBtn.Style = $roundedButtonStyle
                $infoBtn.Background = "#1E90FF"
                $infoBtn.Tag = $tagObj
                $infoBtn.Tag = $btn.Tag
                $infoBtn.VerticalAlignment = "Center"
                Add-HoverShadow $infoBtn
                [System.Windows.Controls.Grid]::SetColumn($infoBtn, 2)
@@ -612,28 +667,35 @@ function Load-Tabs {
                $sp.Children.Add($innerGrid)
                $panel.Children.Add($sp)

                # Click: baixar se necessário e executar
                # Ao clicar: garante download do script e executa (mantendo execução em nova janela)
                $btn.Add_Click({
                    $t = $this.Tag
                    On-ScriptButtonClick -tagObj $t
                    $meta = $this.Tag
                    if ($meta -and $meta.Category -and $meta.Sub -and $meta.ScriptName) {
                        Ensure-ScriptLocalAndExecute -Category $meta.Category -Sub $meta.Sub -ScriptName $meta.ScriptName
                    } else {
                        [System.Windows.MessageBox]::Show("Script não encontrado.", "Erro", "OK", "Error")
                    }
                })

                # Info click: tenta buscar .txt do raw, se não, tenta local
                # Info button: tenta mostrar .txt do raw, se não local
                $infoBtn.Add_Click({
                    $t = $this.Tag
                    # tenta obter info do raw (sem download)
                    $info = $null
                    $meta = $this.Tag
                    $infoText = "Nenhuma documentação encontrada para este script."
                    try {
                        $info = Get-InfoTextFromGitHub -Category $t.Category -Sub $t.Sub -ScriptFileName $t.ScriptName
                        if ($meta -and $meta.Category -and $meta.Sub -and $meta.ScriptName) {
                            # tenta raw .txt
                            $rawTxtUrl = Build-RawUrl -category $meta.Category -sub $meta.Sub -fileName ([System.IO.Path]::ChangeExtension($meta.ScriptName, ".txt"))
                            try {
                                $content = Invoke-RestMethod -Uri $rawTxtUrl -Headers $Global:GitHubHeaders -ErrorAction Stop
                                if ($null -ne $content) { $infoText = $content.ToString() }
                            } catch {
                                # fallback para local
                                $candidateLocal = Join-Path $LocalCache ($meta.Category + "\" + $meta.Sub + "\" + [System.IO.Path]::ChangeExtension($meta.ScriptName, ".txt"))
                                if (Test-Path $candidateLocal) { $infoText = Get-Content $candidateLocal -Raw }
                            }
                        }
                    } catch {}
                    if (-not $info) {
                        # se o arquivo local existir, use-o
                        $localCandidate = Join-Path $LocalCache ($t.Category + "\" + $t.Sub + "\" + $t.ScriptName)
                        $txtLocal = [System.IO.Path]::ChangeExtension($localCandidate, ".txt")
                        if (Test-Path $txtLocal) { $info = Get-Content $txtLocal -Raw }
                    }
                    if (-not $info) { $info = "Nenhuma documentação encontrada para este script." }
                    Show-InfoWindow -title $t.Sub -content $info
                    Show-InfoWindow -title $sub.Name -content $infoText
                })
            }
        }
@@ -708,55 +770,36 @@ $timer.Start()
$mainGrid.Children.Add($footerGrid)

# ===============================
# Ações dos botões
# Ações dos botões (mantidas)
# ===============================
$BtnExec.Add_Click({
    # Executa todos os scripts marcados (multi-select)
    $selectedKeys = $ScriptCheckBoxes.GetEnumerator() | Where-Object { $_.Value.IsChecked -eq $true } | ForEach-Object { $_.Key }
    if ($selectedKeys.Count -eq 0) {
    $selected = $ScriptCheckBoxes.GetEnumerator() | Where-Object { $_.Value.IsChecked -eq $true } | ForEach-Object { $_.Key }
    if ($selected.Count -eq 0) {
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
    foreach ($script in $selected) {
        # '$script' é o caminho local esperado (Category/Sub/Script)
        if (Test-Path $script) {
            Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$script`"" -Verb RunAs -Wait
        } else {
            # fallback: tentar executar arquivo local (se existir)
            $localCandidate = Join-Path $LocalCache ($category + "\" + $sub + "\" + $scriptName)
            if (Test-Path $localCandidate) {
                Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File `"$localCandidate`"" -Verb RunAs
                Write-Log "Executado (fallback local): $localCandidate"
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
                Write-Log "Não foi possível localizar $key no remote nem local."
                Write-Log "Execução em lote: caminho inválido $script"
            }
        }
    }

    [System.Windows.MessageBox]::Show("Execução concluída.", "GESET Launcher", "OK", "Information")
})

# Botão Atualizar: reconsulta a API e recarrega abas
$BtnRefresh.Add_Click({
    Write-Log "Atualização solicitada pelo usuário."
    Load-Tabs
@@ -766,9 +809,18 @@ $BtnExit.Add_Click({ $window.Close() })

# ===============================
# Inicialização
# - obtém estrutura remota (tenta API), cria pastas locais e carrega as abas
# ===============================
# Carrega abas a partir da API (sem baixar scripts). Se API indisponível, usa cache local.
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
