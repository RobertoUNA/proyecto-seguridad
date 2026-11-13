<#
.SYNOPSIS
  Ítem 7.4 — Genera tráfico controlado SOLO contra localhost para activar la señal SIG-01
  (scripts/security-alert-check.py) y tener algo que investigar.

.DESCRIPTION
  Patrón tipo escaneo mezclado con tráfico normal:
    1. tráfico normal (consultas válidas, 200)
    2. escaneo: rutas inexistentes típicas de escáneres, parámetros con inyección SQL / path traversal / XSS,
       fechas inválidas y métodos de escritura (POST/PUT/DELETE) sobre la API de solo lectura
    3. tráfico normal otra vez
  Parte del escaneo pasa por nginx (:8080) y parte directo al backend (:3001).
  No envía cabeceras con valores reales (solo un User-Agent descriptivo de la demo).

  -LogsOut <ruta>: al terminar extrae de `docker compose logs backend` SOLO los eventos de seguridad
  generados desde el inicio de esta ejecución y los guarda en esa ruta (.jsonl).

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/generate-security-traffic.ps1 -LogsOut reports/security-alert-logs-<sha>.jsonl
#>
param(
    [string]$BackendUrl = "http://localhost:3001",
    [string]$FrontendUrl = "http://localhost:8080",
    [int]$DelayMs = 150,
    [string]$LogsOut = ""
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

foreach ($u in @($BackendUrl, $FrontendUrl)) {
    if (([Uri]$u).Host -notin @("localhost", "127.0.0.1")) { throw "Solo se permite tráfico contra localhost: $u" }
}
$UA = "proyecto-seguridad-demo-7.4/1.0 (trafico controlado local)"
function E([string]$s) { [Uri]::EscapeDataString($s) }

$normal = @(
    @("GET", "$BackendUrl/api/cantones"),
    @("GET", "$BackendUrl/api/delitos/tipos"),
    @("GET", "$FrontendUrl/api/cantones/1001/panorama"),
    @("GET", "$BackendUrl/api/delitos?desde=2023-01-01&hasta=2023-12-31"),
    @("GET", "$FrontendUrl/api/accidentes/tipos")
)
# Nota: las URL concatenadas van entre paréntesis; en PowerShell la coma tiene más precedencia que "+".
$scan = @(
    # rutas inexistentes típicas de escáneres
    @("GET", "$BackendUrl/api/admin"),
    @("GET", "$BackendUrl/api/.env"),
    @("GET", "$BackendUrl/api/config.json"),
    @("GET", "$FrontendUrl/api/wp-login.php"),
    @("GET", "$BackendUrl/api/users"),
    @("GET", "$FrontendUrl/api/swagger"),
    @("GET", "$BackendUrl/api/actuator/health"),
    # inyección y manipulación de parámetros (THR-01)
    @("GET", ("$BackendUrl/api/delitos?canton=" + (E "' OR 1=1--"))),
    @("GET", ("$FrontendUrl/api/accidentes?canton=" + (E "1' UNION SELECT usename FROM pg_user--"))),
    @("GET", ("$BackendUrl/api/cantones/" + (E "101' OR '1'='1") + "/panorama")),
    @("GET", ("$BackendUrl/api/delitos?tipo=" + (E "x'; DROP TABLE delito;--"))),
    @("GET", ("$FrontendUrl/api/delitos?canton=" + (E "../../etc/passwd"))),
    @("GET", ("$BackendUrl/api/accidentes?canton=" + (E "<script>alert(1)</script>"))),
    # fechas y rangos inválidos (THR-02)
    @("GET", "$BackendUrl/api/delitos?desde=no-es-fecha"),
    @("GET", "$FrontendUrl/api/delitos?desde=2025-13-45"),
    @("GET", "$BackendUrl/api/accidentes?anio=99999"),
    # intentos de escritura sobre la API de solo lectura
    @("POST", "$BackendUrl/api/cantones"),
    @("PUT", "$BackendUrl/api/delitos"),
    @("DELETE", "$FrontendUrl/api/cantones/1001")
)

$plan = @($normal | ForEach-Object { , ($_ + "normal") }) + @($scan | ForEach-Object { , ($_ + "escaneo") }) + @($normal | ForEach-Object { , ($_ + "normal") })
$since = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
Write-Host "Inicio (UTC): $since  |  peticiones: $($plan.Count)  |  pausa: $DelayMs ms"
$summary = @{}
foreach ($p in $plan) {
    $code = & curl.exe -s -o NUL -w "%{http_code}" -X $p[0] -A $UA $p[1]
    $key = "$($p[2]) HTTP $code"
    $summary[$key] = 1 + [int]$summary[$key]
    Start-Sleep -Milliseconds $DelayMs
}
$summary.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host ("  {0,-22} x{1}" -f $_.Name, $_.Value) }

if ($LogsOut) {
    Start-Sleep -Seconds 2
    $events = @(docker compose logs backend --no-log-prefix --since $since | Where-Object { $_ -like '*"log_type":"security_event"*' })
    $full = if ([System.IO.Path]::IsPathRooted($LogsOut)) { $LogsOut } else { Join-Path $Root $LogsOut }
    $dir = Split-Path -Parent $full
    if ($dir) { New-Item -ItemType Directory -Force $dir | Out-Null }
    [System.IO.File]::WriteAllText($full, (($events -join "`n") + "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Eventos de seguridad extraídos: $($events.Count) -> $LogsOut"
}
