<#
.SYNOPSIS
  Health checks y Smoke Tests posteriores al despliegue (Ítem 6.5).
  Comprueba disponibilidad de la API, conectividad PostGIS, cruce de las 4 fuentes OSINT,
  cabeceras de trazabilidad (X-Data-Source / X-Fetch-Date) y rechazos funcionales/seguridad esperados (400/404).
#>
param(
    [string]$BaseUrl = "http://localhost:3000",
    [string]$ReportPath = "reports/smoke-test-report.json"
)

$ErrorActionPreference = "Stop"
$Results = @()
$Failed = 0

function Add-CheckResult {
    param([string]$Name, [bool]$Passed, [int]$StatusCode, [string]$Detail)
    $script:Results += [PSCustomObject]@{
        check       = $Name
        passed      = $Passed
        status_code = $StatusCode
        detail      = $Detail
        timestamp   = (Get-Date).ToUniversalTime().ToString("o")
    }
    if ($Passed) {
        Write-Host "  [PASS] $Name (HTTP $StatusCode) - $Detail" -ForegroundColor Green
    } else {
        Write-Host "  [FAIL] $Name (HTTP $StatusCode) - $Detail" -ForegroundColor Red
        $script:Failed++
    }
}

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " Ejecutando Health Checks y Smoke Tests contra: $BaseUrl" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Health Check (/api/health)
try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/api/health" -Method GET -UseBasicParsing -TimeoutSec 10
    $body = $resp.Content | ConvertFrom-Json
    $hasHeaders = ($null -ne $resp.Headers["X-Data-Source"]) -and ($null -ne $resp.Headers["X-Fetch-Date"])
    $ok = ($resp.StatusCode -eq 200) -and ($body.status -eq "ok") -and ($body.database.status -eq "up") -and $hasHeaders
    Add-CheckResult -Name "1. Health Check (/api/health)" -Passed $ok -StatusCode $resp.StatusCode -Detail "DB=$($body.database.status), PostGIS=$($body.database.postgis_version)"
} catch {
    Add-CheckResult -Name "1. Health Check (/api/health)" -Passed $false -StatusCode 0 -Detail $_.Exception.Message
}

# 2. SNIT Cantones GeoJSON (/api/cantones)
try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/api/cantones" -Method GET -UseBasicParsing -TimeoutSec 15
    $body = $resp.Content | ConvertFrom-Json
    $count = $body.features.Count
    $ok = ($resp.StatusCode -eq 200) -and ($body.type -eq "FeatureCollection") -and ($count -gt 0)
    Add-CheckResult -Name "2. SNIT Cantones (/api/cantones)" -Passed $ok -StatusCode $resp.StatusCode -Detail "FeatureCollection con $count cantones"
} catch {
    Add-CheckResult -Name "2. SNIT Cantones (/api/cantones)" -Passed $false -StatusCode 0 -Detail $_.Exception.Message
}

# 3. OIJ Delitos Tipos (/api/delitos/tipos)
try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/api/delitos/tipos" -Method GET -UseBasicParsing -TimeoutSec 10
    $body = $resp.Content | ConvertFrom-Json
    $ok = ($resp.StatusCode -eq 200) -and ($null -ne $body)
    Add-CheckResult -Name "3. OIJ Tipos de Delito (/api/delitos/tipos)" -Passed $ok -StatusCode $resp.StatusCode -Detail "Tipos disponibles=$($body.Count)"
} catch {
    Add-CheckResult -Name "3. OIJ Tipos de Delito (/api/delitos/tipos)" -Passed $false -StatusCode 0 -Detail $_.Exception.Message
}

# 4. COSEVI Accidentes Tipos (/api/accidentes/tipos)
try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/api/accidentes/tipos" -Method GET -UseBasicParsing -TimeoutSec 10
    $body = $resp.Content | ConvertFrom-Json
    $ok = ($resp.StatusCode -eq 200) -and ($null -ne $body)
    Add-CheckResult -Name "4. COSEVI Tipos de Accidente (/api/accidentes/tipos)" -Passed $ok -StatusCode $resp.StatusCode -Detail "Tipos disponibles=$($body.Count)"
} catch {
    Add-CheckResult -Name "4. COSEVI Tipos de Accidente (/api/accidentes/tipos)" -Passed $false -StatusCode 0 -Detail $_.Exception.Message
}

# 5. OSM Infraestructura por Cantón (/api/infraestructura/por-canton)
try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/api/infraestructura/por-canton" -Method GET -UseBasicParsing -TimeoutSec 15
    $body = $resp.Content | ConvertFrom-Json
    $ok = ($resp.StatusCode -eq 200) -and ($body.type -eq "FeatureCollection")
    Add-CheckResult -Name "5. OSM Infraestructura (/api/infraestructura/por-canton)" -Passed $ok -StatusCode $resp.StatusCode -Detail "FeatureCollection recibida correctamente"
} catch {
    Add-CheckResult -Name "5. OSM Infraestructura (/api/infraestructura/por-canton)" -Passed $false -StatusCode 0 -Detail $_.Exception.Message
}

# 6. Flujo Crítico FLOW-01: Cruce Panorama Cantonal (/api/cantones/1001/panorama)
try {
    $resp = Invoke-WebRequest -Uri "$BaseUrl/api/cantones/1001/panorama" -Method GET -UseBasicParsing -TimeoutSec 15
    $body = $resp.Content | ConvertFrom-Json
    $ic = $body.properties.indice_cobertura
    $ok = ($resp.StatusCode -eq 200) -and ($body.type -eq "Feature") -and ($ic -ge 0) -and ($ic -le 100)
    Add-CheckResult -Name "6. Cruce 4 Fuentes (/api/cantones/1001/panorama)" -Passed $ok -StatusCode $resp.StatusCode -Detail "Cantón=$($body.properties.nombre), indice_cobertura=$ic"
} catch {
    Add-CheckResult -Name "6. Cruce 4 Fuentes (/api/cantones/1001/panorama)" -Passed $false -StatusCode 0 -Detail $_.Exception.Message
}

# 7. Rechazo esperado: Cantón inexistente debe devolver 404 Not Found
try {
    Invoke-WebRequest -Uri "$BaseUrl/api/cantones/999999/panorama" -Method GET -UseBasicParsing -TimeoutSec 10 | Out-Null
    Add-CheckResult -Name "7. Rechazo Cantón Inexistente (404 esperado)" -Passed $false -StatusCode 200 -Detail "Devolvió 200 en vez de 404"
} catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    $ok = ($code -eq 404)
    Add-CheckResult -Name "7. Rechazo Cantón Inexistente (404 esperado)" -Passed $ok -StatusCode $code -Detail "Rechazo controlado verificado (HTTP $code)"
}

# 8. Rechazo de seguridad/validación: Fecha malformada debe devolver 400 Bad Request
try {
    Invoke-WebRequest -Uri "$BaseUrl/api/delitos?desde=fecha-invalida" -Method GET -UseBasicParsing -TimeoutSec 10 | Out-Null
    Add-CheckResult -Name "8. Rechazo Filtro Fecha Inválida (400 esperado)" -Passed $false -StatusCode 200 -Detail "Devolvió 200 en vez de 400"
} catch {
    $code = 0
    if ($_.Exception.Response) { $code = [int]$_.Exception.Response.StatusCode }
    $ok = ($code -eq 400)
    Add-CheckResult -Name "8. Rechazo Filtro Fecha Inválida (400 esperado)" -Passed $ok -StatusCode $code -Detail "Validación de entrada activa (HTTP $code)"
}

$ReportDir = Split-Path -Parent $ReportPath
if ($ReportDir -and -not (Test-Path $ReportDir)) {
    New-Item -ItemType Directory -Force -Path $ReportDir | Out-Null
}

$Summary = [PSCustomObject]@{
    base_url     = $BaseUrl
    executed_at  = (Get-Date).ToUniversalTime().ToString("o")
    total_checks = $Results.Count
    passed       = ($Results | Where-Object { $_.passed }).Count
    failed       = $Failed
    status       = $(if ($Failed -eq 0) { "APPROVED" } else { "FAILED" })
    checks       = $Results
}
$Summary | ConvertTo-Json -Depth 5 | Set-Content -Path $ReportPath -Encoding UTF8

Write-Host "------------------------------------------------------------------"
Write-Host " Reporte guardado en: $ReportPath"
if ($Failed -gt 0) {
    Write-Host " [RESULTADO] FALLO ($Failed comprobaciones fallaron). Se requiere rollback." -ForegroundColor Red
    exit 1
}
Write-Host " [RESULTADO] APROBADO (Todas las $($Results.Count) comprobaciones pasaron)." -ForegroundColor Green
exit 0
