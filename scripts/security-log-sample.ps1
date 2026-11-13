<#
.SYNOPSIS
  Ítem 7.2 — Genera tráfico controlado SOLO contra localhost, extrae los eventos de seguridad reales
  del backend y verifica que no exponen datos sensibles (THR-06 / CTL-06).

.DESCRIPTION
  Requiere el stack de docker-compose.yml levantado (proyecto proyecto-seguridad).
  Salidas (con el SHA de HEAD):
    reports/security-events-sample-<sha>.jsonl   líneas reales de `docker compose logs backend`
    reports/security-traffic-<sha>.json          qué se envió, código HTTP y correlation_id devuelto
    reports/verify-security-logs-<sha>.txt       salida de scripts/verify-security-logs.py
  Las cabeceras Authorization/Cookie y X-Forwarded-For son valores FICTICIOS de prueba; el manifiesto
  no los guarda (solo indica que se enviaron) y el verificador comprueba que no llegaron a los logs.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/security-log-sample.ps1 -BackendUrl http://localhost:3001
#>
param(
    [string]$BackendUrl = "http://localhost:3001",
    [string]$FrontendUrl = "http://localhost:8080",
    [string]$Sha = ""
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Utf8 = New-Object System.Text.UTF8Encoding($false)

foreach ($u in @($BackendUrl, $FrontendUrl)) {
    if (([Uri]$u).Host -notin @("localhost", "127.0.0.1")) { throw "Solo se permite tráfico contra localhost: $u" }
}
if (-not $Sha) { $Sha = (git rev-parse HEAD).Trim() }
$dirty = @(git status --porcelain -- backend/src docker-compose.yml)
if ($dirty.Count) { Write-Host "[AVISO] backend/src o docker-compose.yml tienen cambios sin confirmar: la muestra no describe exactamente $Sha" -ForegroundColor Yellow }

# Valores ficticios de prueba (no son credenciales). Se pasan al verificador como "prohibidos".
$FakeAuth = "Bearer demo-authorization-ficticio"
$FakeCookie = "sesion=demo-cookie-ficticia"
$FakeXff = "203.0.113.77"          # TEST-NET-3 (RFC 5737), no enrutable
$Injection = "' OR 1=1--"
$ValidUuid = [guid]::NewGuid().ToString()

$requests = @(
    @{ id = "normal";            url = "$BackendUrl/api/cantones";                                    note = "petición normal (200, no genera evento)" },
    @{ id = "fecha-invalida";    url = "$BackendUrl/api/delitos?desde=fecha-invalida";                note = "fecha inválida + Authorization y Cookie ficticias"; extra = @("-H", "Authorization: $FakeAuth", "-H", "Cookie: $FakeCookie") },
    @{ id = "canton-inexistente"; url = "$BackendUrl/api/cantones/999999/panorama";                  note = "cantón inexistente + X-Correlation-Id UUID válido (debe conservarse)"; extra = @("-H", "X-Correlation-Id: $ValidUuid") },
    @{ id = "ruta-inexistente";  url = "$BackendUrl/api/ruta-inexistente";                            note = "ruta inexistente + X-Correlation-Id inválido (debe reemplazarse)"; extra = @("-H", "X-Correlation-Id: no-es-uuid<script>") },
    @{ id = "inyeccion-sql";     url = "$BackendUrl/api/delitos?canton=" + [Uri]::EscapeDataString($Injection); note = "intento ?canton=' OR 1=1-- + Authorization, Cookie y X-Forwarded-For ficticios"; extra = @("-H", "Authorization: $FakeAuth", "-H", "Cookie: $FakeCookie", "-H", "X-Forwarded-For: $FakeXff") },
    @{ id = "escritura";         url = "$BackendUrl/api/cantones";                                    note = "POST a la API de solo lectura (acceso denegado)"; extra = @("-X", "POST") },
    @{ id = "via-frontend";      url = "$FrontendUrl/api/cantones/999999/panorama";                   note = "mismo 404 pasando por nginx (X-Forwarded-For lo pone nginx)" }
)

# Pausa y marca con milisegundos: la muestra contiene solo los eventos de este tráfico.
Start-Sleep -Seconds 2
$since = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
$manifest = @()
foreach ($r in $requests) {
    $curlArgs = @("-s", "-o", "NUL", "-D", "-") + @($r.extra | Where-Object { $_ }) + @($r.url)
    $headers = & curl.exe @curlArgs
    $status = ($headers | Select-String '^HTTP/\S+\s+(\d{3})' | Select-Object -First 1).Matches.Groups[1].Value
    $corr = (($headers | Select-String '^X-Correlation-Id:\s*(\S+)' | Select-Object -First 1).Matches.Groups[1].Value)
    Write-Host ("  {0,-20} HTTP {1}  correlation_id={2}" -f $r.id, $status, $corr)
    $manifest += [ordered]@{ id = $r.id; note = $r.note; status = [int]$status; correlation_id = $corr }
}
Start-Sleep -Seconds 2

$events = @(docker compose logs backend --no-log-prefix --since $since | Where-Object { $_ -like '*"log_type":"security_event"*' })
$samplePath = "reports/security-events-sample-$Sha.jsonl"
[System.IO.File]::WriteAllText((Join-Path $Root $samplePath), (($events -join "`n") + "`n"), $Utf8)

# IPs que no deben aparecer: gateways de las redes del proyecto (origen real desde el host), loopback y el XFF ficticio.
$ips = @("127.0.0.1", $FakeXff)
foreach ($n in @("proyecto-seguridad_edge", "proyecto-seguridad_data")) {
    $gw = docker network inspect $n --format "{{range .IPAM.Config}}{{.Gateway}} {{end}}" 2>$null
    $ips += @("$gw".Split(" ") | Where-Object { $_ })
}
$ips += @(docker inspect proyecto-seguridad-frontend-1 --format "{{range .NetworkSettings.Networks}}{{.IPAddress}} {{end}}" 2>$null).Split(" ") | Where-Object { $_ }

$manifestDoc = [ordered]@{
    item = "7.2"; commit = $Sha; generated_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    target = "solo localhost"; requests = $manifest
    sensitive_inputs_sent = "Authorization y Cookie ficticias, X-Forwarded-For de TEST-NET-3 e inyección SQL (valores no se guardan aquí)"
    client_ips_checked = $ips.Count; sample = $samplePath; events_captured = $events.Count
}
[System.IO.File]::WriteAllText((Join-Path $Root "reports/security-traffic-$Sha.json"), ($manifestDoc | ConvertTo-Json -Depth 5), $Utf8)

$verifyArgs = @("scripts/verify-security-logs.py", $samplePath, "--output", "reports/verify-security-logs-$Sha.txt",
                "--expect-pattern", "sql_injection", "--expect-event", "validation_rejected", "--expect-event", "not_found",
                "--expect-event", "abuse_suspected", "--expect-event", "access_denied")
foreach ($ip in $ips) { $verifyArgs += @("--client-ip", $ip) }
foreach ($v in @($FakeAuth, $FakeCookie, $Injection, "fecha-invalida", "999999", "no-es-uuid", "demo-authorization-ficticio", "demo-cookie-ficticia")) { $verifyArgs += @("--forbidden-value", $v) }
Write-Host ""
& python @verifyArgs
exit $LASTEXITCODE
