# Antarcticom Installer Build Script
# Usage: .\build.ps1
# Requirements: Flutter SDK, Inno Setup 6

param(
    [string]$InnoSetupPath = ""
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
$ClientDir = Join-Path $Root "client"
$InstallerDir = $PSScriptRoot

Write-Host ""
Write-Host "=== Antarcticom Installer Build ===" -ForegroundColor Cyan
Write-Host ""

# --- Step 1: Build Flutter client ---
Write-Host "[1/3] Building Flutter client (release)..." -ForegroundColor Yellow
Push-Location $ClientDir
try {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) {
        throw "Flutter build failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
Write-Host "  Flutter build complete." -ForegroundColor Green

# --- Step 2: Locate Inno Setup compiler ---
Write-Host "[2/3] Locating Inno Setup compiler..." -ForegroundColor Yellow

$ISCC = ""
if ($InnoSetupPath -and (Test-Path $InnoSetupPath)) {
    $ISCC = $InnoSetupPath
} else {
    # Common install locations
    $candidates = @(
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles}\Inno Setup 6\ISCC.exe",
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
    )
    foreach ($c in $candidates) {
        if (Test-Path $c) {
            $ISCC = $c
            break
        }
    }
}

if (-not $ISCC) {
    Write-Host ""
    Write-Host "ERROR: Inno Setup 6 not found." -ForegroundColor Red
    Write-Host "  Install from: https://jrsoftware.org/isinfo.php" -ForegroundColor Red
    Write-Host "  Or pass -InnoSetupPath 'C:\path\to\ISCC.exe'" -ForegroundColor Red
    exit 1
}

Write-Host "  Found: $ISCC" -ForegroundColor Green

# --- Step 3: Compile installer ---
Write-Host "[3/3] Compiling installer..." -ForegroundColor Yellow

$IssFile = Join-Path $InstallerDir "antarcticom.iss"
& $ISCC $IssFile
if ($LASTEXITCODE -ne 0) {
    throw "Inno Setup compilation failed with exit code $LASTEXITCODE"
}

Write-Host ""
Write-Host "=== Build Complete ===" -ForegroundColor Green

$OutputDir = Join-Path $InstallerDir "Output"
$OutputFile = Get-ChildItem -Path $OutputDir -Filter "AntarcticomSetup-*.exe" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
if ($OutputFile) {
    Write-Host "  Installer: $($OutputFile.FullName)" -ForegroundColor Cyan
    Write-Host "  Size: $([math]::Round($OutputFile.Length / 1MB, 1)) MB" -ForegroundColor Cyan
} else {
    Write-Host "  Output directory: $OutputDir" -ForegroundColor Cyan
}

Write-Host ""
