$ErrorActionPreference = "Stop"

$BundleName = "g5ibkj7vdwf2g67g_assets_all_df231fe1e06c36a5cb63c87a08cd9257.bundle"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$PoPath = Join-Path $ScriptDir "my_translation.po"
$PatchScript = Join-Path $ScriptDir "po_to_bundle.py"
$Requirements = Join-Path $ScriptDir "requirements.txt"

function Write-Step($Text) {
    Write-Host ""
    Write-Host "==> $Text" -ForegroundColor Cyan
}

function Find-Python {
    $commands = @(
        @{ File = "py"; Prefix = @("-3") },
        @{ File = "python"; Prefix = @() },
        @{ File = "python3"; Prefix = @() }
    )

    foreach ($cmd in $commands) {
        try {
            $testArgs = @($cmd.Prefix) + @("-c", "import sys, encodings; print(sys.version)")
            $null = & $cmd.File @testArgs 2>$null
            if ($LASTEXITCODE -eq 0) {
                return @{
                    File = $cmd.File
                    Prefix = $cmd.Prefix
                }
            }
        } catch {
        }
    }

    return $null
}

function Install-Python-With-Winget {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $winget) {
        return $false
    }

    Write-Host "Python 3 nao foi encontrado. Tentando instalar automaticamente via winget..."
    & winget install --id Python.Python.3.12 --exact --silent --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) {
        return $false
    }

    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    return $true
}

function Invoke-Python($PythonInfo, [string[]]$ArgsList) {
    $allArgs = @($PythonInfo.Prefix) + $ArgsList
    & $PythonInfo.File @allArgs
}

function Get-SteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]

    $registryPaths = @(
        "HKCU:\Software\Valve\Steam",
        "HKLM:\Software\WOW6432Node\Valve\Steam",
        "HKLM:\Software\Valve\Steam"
    )

    foreach ($regPath in $registryPaths) {
        try {
            $props = Get-ItemProperty -Path $regPath -ErrorAction Stop
            foreach ($name in @("SteamPath", "InstallPath")) {
                if ($props.$name -and (Test-Path -LiteralPath $props.$name)) {
                    $roots.Add($props.$name)
                }
            }
        } catch {
        }
    }

    foreach ($fallback in @(
        "C:\Program Files (x86)\Steam",
        "C:\Program Files\Steam",
        "D:\SteamLibrary",
        "D:\Steam"
    )) {
        if (Test-Path -LiteralPath $fallback) {
            $roots.Add($fallback)
        }
    }

    return $roots | Select-Object -Unique
}

function Get-SteamLibraries {
    $libraries = New-Object System.Collections.Generic.List[string]

    foreach ($root in Get-SteamRoots) {
        if (Test-Path -LiteralPath (Join-Path $root "steamapps")) {
            $libraries.Add($root)
        }

        $libraryFolders = Join-Path $root "steamapps\libraryfolders.vdf"
        if (Test-Path -LiteralPath $libraryFolders) {
            $content = Get-Content -LiteralPath $libraryFolders -Raw
            foreach ($match in [regex]::Matches($content, '"path"\s+"([^"]+)"')) {
                $path = $match.Groups[1].Value -replace "\\\\", "\"
                if (Test-Path -LiteralPath $path) {
                    $libraries.Add($path)
                }
            }
        }
    }

    return $libraries | Select-Object -Unique
}

function Find-ZeroParadesBundle {
    $relative = "steamapps\common\Zero Parades\ZeroParades_Data\StreamingAssets\aa\StandaloneWindows64\$BundleName"

    foreach ($library in Get-SteamLibraries) {
        $candidate = Join-Path $library $relative
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    return $null
}

Write-Host "Zero Parades - Instalador da traducao PT-BR" -ForegroundColor Green

foreach ($required in @($PoPath, $PatchScript, $Requirements, (Join-Path $ScriptDir "language_codes.py"))) {
    if (-not (Test-Path -LiteralPath $required)) {
        throw "Arquivo obrigatorio nao encontrado: $required"
    }
}

Write-Step "Procurando Python"
$python = Find-Python
if (-not $python) {
    if (Install-Python-With-Winget) {
        $python = Find-Python
    }
}

if (-not $python) {
    Write-Host "Python 3 nao foi encontrado e nao consegui instalar automaticamente." -ForegroundColor Red
    Write-Host "Instale em https://www.python.org/downloads/ e marque 'Add python.exe to PATH'."
    Write-Host "Depois execute Instalar_PTBR.bat novamente."
    exit 1
}
Write-Host "Python encontrado: $($python.File) $($python.Prefix -join ' ')"

Write-Step "Instalando dependencias"
Invoke-Python $python @("-m", "pip", "install", "-r", $Requirements)
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao instalar dependencias Python."
}

Write-Step "Procurando Zero Parades na Steam"
$bundle = Find-ZeroParadesBundle
if (-not $bundle) {
    Write-Host "Nao consegui achar o bundle automaticamente." -ForegroundColor Yellow
    Write-Host "Cole o caminho completo do arquivo $BundleName"
    $bundle = Read-Host "Caminho"
    $bundle = $bundle.Trim('"')
}

if (-not (Test-Path -LiteralPath $bundle)) {
    throw "Bundle nao encontrado: $bundle"
}

Write-Host "Bundle encontrado:"
Write-Host $bundle

Write-Step "Aplicando traducao"
Invoke-Python $python @($PatchScript, "--bundle", $bundle, "--po", $PoPath, "--lang-name", "pt")
if ($LASTEXITCODE -ne 0) {
    throw "Falha ao aplicar a traducao."
}

Write-Host ""
Write-Host "Traducao instalada com sucesso." -ForegroundColor Green
Write-Host "Abra o jogo e selecione Deutsch/Alemao em Settings -> Language."
Write-Host "Se uma atualizacao da Steam desfizer a traducao, execute este instalador novamente."
