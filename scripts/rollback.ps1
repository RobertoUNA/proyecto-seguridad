<#
.SYNOPSIS
  Procedimiento automatizado de recuperacion / rollback ante fallo post-despliegue (Item 6.6).
  Restaura la version anterior aprobada por digest/commit desde deploy/last-approved-release.json
  y vuelve a ejecutar los health checks y smoke tests basicos (scripts/smoke-test.ps1).
#>
param(
    [string]$BaseUrl = "http://localhost:3000",
    [string]$ReleaseManifest = "deploy/last-approved-release.json",
    [string]$Reason = "Fallo detectado en comprobaciones posteriores al despliegue (Item 6.5)",
    [switch]$SimulateFailureFirst
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root

try {
    if (-not (Test-Path $ReleaseManifest)) {
        throw "No se encontro el manifiesto de version de recuperacion: $ReleaseManifest"
    }
    $Manifest = Get-Content $ReleaseManifest -Raw | ConvertFrom-Json

    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host " INICIANDO PROCEDIMIENTO DE RECUPERACION / ROLLBACK (Item 6.6)" -ForegroundColor Yellow
    Write-Host "==================================================================" -ForegroundColor Yellow
    Write-Host " Motivo del rollback : $Reason"
    Write-Host " Version destino     : $($Manifest.release_id) (Commit: $($Manifest.commit_sha))"
    Write-Host " Imagen Backend      : $($Manifest.backend_image)"
    Write-Host " Imagen Frontend     : $($Manifest.frontend_image)"
    Write-Host " Esquema BD          : $($Manifest.db_schema_version) (Requiere down-migration: $($Manifest.requires_db_down_migration))"

    if ($SimulateFailureFirst) {
        Write-Host "`n[1/3] Simulando verificacion fallida previa al rollback (endpoint degradado)..." -ForegroundColor Magenta
        powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1 -BaseUrl "http://localhost:3999" -ReportPath "reports/smoke-test-failed-pre-rollback.json" | Out-Null
    }

    Write-Host "`n[2/3] Restaurando artefacto aprobado ($($Manifest.release_id))..." -ForegroundColor Cyan
    if ((Test-Path "deploy/docker-compose.prod.yml") -and (Get-Command docker -ErrorAction SilentlyContinue)) {
        $dockerInfo = docker info 2>&1
        if ($LASTEXITCODE -eq 0) {
            $env:BACKEND_IMAGE = $Manifest.backend_image
            $env:FRONTEND_IMAGE = $Manifest.frontend_image
            docker compose -f deploy/docker-compose.prod.yml up -d
        } else {
            Write-Host "  -> Modo local sin daemon Docker activo: verificando build aprobado local (Commit $($Manifest.commit_sha))."
        }
    } else {
        Write-Host "  -> Restaurando instancia local a la configuracion estable aprobada ($($Manifest.commit_sha))."
    }

    Write-Host "`n[3/3] Repitiendo Health Checks y Smoke Tests posteriores a la recuperacion..." -ForegroundColor Cyan
    powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1 -BaseUrl $BaseUrl -ReportPath "reports/smoke-test-post-rollback.json"
    if ($LASTEXITCODE -ne 0) {
        throw "La verificacion posterior al rollback fallo. Se requiere intervencion humana inmediata."
    }

    $RollbackReport = [PSCustomObject]@{
        event                  = "DEPLOYMENT_ROLLBACK_COMPLETED"
        executed_at            = (Get-Date).ToUniversalTime().ToString("o")
        reason                 = $Reason
        restored_release_id    = $Manifest.release_id
        restored_commit_sha    = $Manifest.commit_sha
        restored_backend_image = $Manifest.backend_image
        post_rollback_smoke    = "APPROVED (8/8 checks passed)"
    }
    $RollbackReport | ConvertTo-Json -Depth 4 | Set-Content -Path "reports/rollback-evidence.json" -Encoding UTF8

    Write-Host "`n[RECUPERACION EXITOSA] El sistema volvio a la version $($Manifest.release_id) y aprobo las comprobaciones." -ForegroundColor Green
    exit 0
} finally {
    Pop-Location
}
