<#
.SYNOPSIS
  Ejecuta los análisis de seguridad locales de la Etapa 2 (Ítem 2.3):
  1) Análisis estático de código (SAST) con Semgrep CE (.semgrep.yml)
  2) Detección de secretos expuestos con Gitleaks (.gitleaks.toml)
#>
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root

try {
    Write-Host "==========================================================" -ForegroundColor Cyan
    Write-Host " 1/2 Ejecutando SAST (Semgrep CE / .semgrep.yml)" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    python scripts/sast-check.py
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[FALLO] El análisis SAST detectó defectos de seguridad." -ForegroundColor Red
        exit 1
    }

    Write-Host "`n==========================================================" -ForegroundColor Cyan
    Write-Host " 2/2 Ejecutando Detección de Secretos (Gitleaks)" -ForegroundColor Cyan
    Write-Host "==========================================================" -ForegroundColor Cyan
    if (Get-Command gitleaks -ErrorAction SilentlyContinue) {
        gitleaks dir . --config .gitleaks.toml --verbose
        if ($LASTEXITCODE -ne 0) { exit 1 }
    } elseif (Get-Command docker -ErrorAction SilentlyContinue) {
        docker run --rm -v "${Root}:/src" zricethezav/gitleaks:v8.21.2 dir /src --config /src/.gitleaks.toml --verbose
        if ($LASTEXITCODE -ne 0) { exit 1 }
    } else {
        Write-Host "[AVISO] Instala gitleaks o inicia Docker Desktop para ejecutar el binario de Gitleaks." -ForegroundColor Yellow
        exit 1
    }

    Write-Host "`n[OK] Todos los controles de seguridad locales (Ítem 2.3) aprobaron." -ForegroundColor Green
    exit 0
} finally {
    Pop-Location
}
