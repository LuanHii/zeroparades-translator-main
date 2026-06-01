$ErrorActionPreference = "Stop"

$BundleName = "g5ibkj7vdwf2g67g_assets_all_df231fe1e06c36a5cb63c87a08cd9257.bundle"
$BundlePattern = "*_assets_all_*.bundle"
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

    foreach ($drive in [System.IO.DriveInfo]::GetDrives()) {
        if (-not $drive.IsReady) {
            continue
        }

        $root = $drive.RootDirectory.FullName
        foreach ($fallback in @(
            "SteamLibrary",
            "Steam",
            "Program Files (x86)\Steam",
            "Program Files\Steam"
        )) {
            $candidate = Join-Path $root $fallback
            if (Test-Path -LiteralPath $candidate) {
                $roots.Add($candidate)
            }
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

function Find-BundleInDirectory($Directory) {
    if (-not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return $null
    }

    $exact = Join-Path $Directory $BundleName
    if (Test-Path -LiteralPath $exact -PathType Leaf) {
        return $exact
    }

    $matches = @(Get-ChildItem -LiteralPath $Directory -Filter $BundlePattern -File -ErrorAction SilentlyContinue | Sort-Object Name)
    if ($matches.Count -eq 0) {
        return $null
    }

    $preferred = $matches | Where-Object { $_.Name -like "g5ibkj7vdwf2g67g_assets_all_*.bundle" } | Select-Object -First 1
    if ($preferred) {
        return $preferred.FullName
    }

    return $matches[0].FullName
}

function Find-ZeroParadesBundle {
    foreach ($library in Get-SteamLibraries) {
        $common = Join-Path $library "steamapps\common"

        foreach ($gameDir in @("Zero Parades", "ZeroParades", "Zero Parades For Dead Spies")) {
            $bundleDir = Join-Path $common "$gameDir\ZeroParades_Data\StreamingAssets\aa\StandaloneWindows64"
            $candidate = Find-BundleInDirectory $bundleDir
            if ($candidate) {
                return $candidate
            }
        }

        $expectedGameDir = Join-Path $common "Zero Parades"
        if (Test-Path -LiteralPath $expectedGameDir -PathType Container) {
            $match = Get-ChildItem -LiteralPath $expectedGameDir -Recurse -Filter $BundlePattern -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -First 1
            if ($match) {
                return $match.FullName
            }
        }
    }

    return $null
}

function Resolve-BundlePath($Path) {
    $resolved = $Path.Trim('"')

    if ((Test-Path -LiteralPath $resolved -PathType Container)) {
        $found = Find-BundleInDirectory $resolved
        if (-not $found) {
            throw "Nenhum bundle $BundlePattern foi encontrado na pasta: $resolved"
        }
        $resolved = $found
    }

    if (-not (Test-Path -LiteralPath $resolved -PathType Leaf)) {
        throw "Bundle nao encontrado: $resolved"
    }

    if ([System.IO.Path]::GetFileName($resolved) -notlike $BundlePattern) {
        throw "O caminho precisa apontar para um arquivo $BundlePattern"
    }

    return $resolved
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
    Write-Host "Cole o caminho completo do arquivo $BundleName ou outro *_assets_all_*.bundle"
    Write-Host "Tambem aceito a pasta StandaloneWindows64 que contem esse arquivo."
    $bundle = Read-Host "Caminho"
}

$bundle = Resolve-BundlePath $bundle

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
