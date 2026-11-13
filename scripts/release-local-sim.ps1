<#
.SYNOPSIS
  Ítem 5.5 — Simulación local de la publicación por SHA/digest (misma mecánica que release-deploy.yml),
  sin Docker Hub: usa un registro temporal registry:2 publicado solo en 127.0.0.1.

.DESCRIPTION
  1. Construye las imágenes UNA sola vez para el SHA (scripts/container-scan.ps1: build + Trivy + SBOM).
  2. Compuerta final por imagen: Trivy image (HIGH/CRITICAL corregibles) y Conftest (scripts/policy-check.ps1).
     Una imagen que no pasa NO se publica y queda registrada como bloqueada (caso negativo).
  3. Levanta un registro temporal (proyecto "proyecto-seguridad-release-sim", contenedor propio y etiquetado).
  4. Publica ESA imagen (re-etiquetado, sin reconstruir) como sha-<SHA>, obtiene el digest con la API del
     registro (y con `docker buildx imagetools inspect` si está disponible) y comprueba que el pull por digest
     devuelve exactamente la misma imagen (mismo image ID).
  5. Guarda <ReportDir>/release-local-sim-<sha>.json y ELIMINA el registro temporal y las etiquetas locales.

  Exit 0 si la mecánica se verificó (incluido el caso negativo esperado); exit 1 si algo de la mecánica falló.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/release-local-sim.ps1
#>
param(
    [string]$Sha = "",
    [int]$Port = 5055,
    [string]$ReportDir = ""
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root
$Utf8 = New-Object System.Text.UTF8Encoding($false)

$Project = "proyecto-seguridad-release-sim"
$RegName = "$Project-registry"
$RegImage = "registry:2.8.3@sha256:a3d8aaa63ed8681a604f1dea0aa03f100d5895b6a58ace528858a7b332415373"
$Registry = "localhost:$Port"
$Components = @("backend", "frontend")
$Accept = "application/vnd.oci.image.index.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.v2+json"

function Step($m) { Write-Host "`n=== $m" -ForegroundColor Cyan }
function Native([string]$Exe, [string[]]$A) { $o = & $Exe @A 2>&1 | ForEach-Object { "$_" }; return @{ exit = $LASTEXITCODE; text = ($o -join "`n") } }

if (-not $Sha) { $Sha = (git rev-parse HEAD).Trim() }
if ($Sha -notmatch '^[0-9a-f]{7,40}$') { throw "SHA inválido: $Sha" }
if (-not $ReportDir) { $ReportDir = Join-Path $Root "reports" }
New-Item -ItemType Directory -Force $ReportDir | Out-Null
$dirty = @(git status --porcelain -- backend frontend policy docker-compose.yml scripts)
if ($dirty.Count) { Write-Host "[AVISO] Hay cambios sin confirmar: la simulación no describe exactamente $Sha" -ForegroundColor Yellow }

# Puerto libre y sin restos de una ejecución anterior (solo se toca el contenedor propio de este script).
if (netstat -ano | Select-String "LISTENING" | Select-String ":$Port\s") { throw "El puerto 127.0.0.1:$Port está ocupado; use -Port" }
if (docker ps -a --filter "name=^${RegName}$" --format "{{.Names}}") { docker rm -f -v $RegName | Out-Null }

$work = Join-Path ([System.IO.Path]::GetTempPath()) ("release-sim-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Force (Join-Path $work "scan"), (Join-Path $work "policy") | Out-Null
$mechanicsOk = $true
$results = @()

try {
    # -------------------------------------------------------------- 1-2. build único + compuerta
    Step "1/4 Build único + Trivy (scripts/container-scan.ps1)"
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts/container-scan.ps1") -Sha $Sha -ReportDir (Join-Path $work "scan") 2>&1 | ForEach-Object { "$_" } | Select-String "^===|Trivy (config|image)" | ForEach-Object { Write-Host "  $_" }
    $scanFile = Join-Path $work "scan/container-scan-$Sha.json"
    if (-not (Test-Path $scanFile)) { throw "container-scan no generó su resumen: compuerta INCOMPLETE" }
    $scan = [System.IO.File]::ReadAllText($scanFile) | ConvertFrom-Json

    Step "2/4 Conftest (scripts/policy-check.ps1)"
    powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "scripts/policy-check.ps1") -Sha $Sha -ReportDir (Join-Path $work "policy") 2>&1 | ForEach-Object { "$_" } | Select-String "\[PASS\]|\[FAIL|Resultado" | ForEach-Object { Write-Host "  $_" }
    $polFile = Join-Path $work "policy/conftest-$Sha.json"
    if (-not (Test-Path $polFile)) { throw "policy-check no generó su resumen: compuerta INCOMPLETE" }
    $pol = [System.IO.File]::ReadAllText($polFile) | ConvertFrom-Json
    $polFiles = @($pol.allowed.files | ForEach-Object { $_ })

    # -------------------------------------------------------------- 3. registro temporal
    Step "3/4 Registro temporal $Registry ($RegName)"
    $r = Native "docker" @("run", "-d", "--name", $RegName, "--label", "com.docker.compose.project=$Project", "--label", "proyecto-seguridad.purpose=release-local-sim", "-p", "127.0.0.1:${Port}:5000", $RegImage)
    if ($r.exit -ne 0) { throw "No se pudo iniciar el registro temporal: $($r.text)" }
    $ready = $false
    for ($i = 0; $i -lt 30 -and -not $ready; $i++) { Start-Sleep -Milliseconds 500; $ready = ((curl.exe -s -o NUL -w "%{http_code}" "http://127.0.0.1:$Port/v2/") -eq "200") }
    if (-not $ready) { throw "El registro temporal no respondió" }

    # -------------------------------------------------------------- 4. publicar lo que pasa la compuerta
    Step "4/4 Publicación por SHA y verificación del digest"
    foreach ($c in $Components) {
        $local = "proyecto-seguridad-${c}:sha-$Sha"
        $img = @($scan.images | Where-Object { $_.component -eq $c })[0]
        $dockerfile = @($polFiles | Where-Object { $_.file -eq "$c/Dockerfile" })[0]
        $compose = @($polFiles | Where-Object { $_.file -eq "docker-compose.yml" })[0]
        $gate = [ordered]@{
            trivy_image = $img.image_scan
            trivy_vulnerabilities = $img.vulnerabilities
            conftest_dockerfile = $dockerfile.result
            conftest_compose = $compose.result
            conftest_verify = $pol.verify.result
        }
        $entry = [ordered]@{ component = $c; local_image = $local; image_id_before = $img.image_id; config_digest = $img.config_digest; gate = $gate }
        $passed = ($img.image_scan -eq "PASS" -and $dockerfile.result -eq "PASS" -and $compose.result -eq "PASS" -and $pol.verify.result -eq "PASS")
        if (-not $passed) {
            $entry.status = "BLOCKED"
            $entry.reason = "Una comprobación obligatoria falló (Trivy image: $($img.image_scan); Conftest Dockerfile: $($dockerfile.result)); no se publica"
            Write-Host "  [BLOQUEADA] $c -> $($entry.reason)" -ForegroundColor Yellow
            $results += $entry; continue
        }

        $remote = "$Registry/proyecto-seguridad-${c}:sha-$Sha"
        $idBefore = (docker image inspect --format "{{.Id}}" $local).Trim()
        docker tag $local $remote
        $push = Native "docker" @("push", $remote)
        if ($push.exit -ne 0) { $entry.status = "ERROR"; $entry.reason = "push falló"; $mechanicsOk = $false; $results += $entry; continue }
        $idTagged = (docker image inspect --format "{{.Id}}" $remote).Trim()

        # Digest real según el registro (cabecera Docker-Content-Digest).
        $hdr = curl.exe -s -I -H "Accept: $Accept" "http://127.0.0.1:$Port/v2/proyecto-seguridad-$c/manifests/sha-$Sha"
        $digest = (($hdr | Select-String -Pattern '^Docker-Content-Digest:\s*(\S+)').Matches.Groups[1].Value)
        $it = Native "docker" @("buildx", "imagetools", "inspect", $remote, "--format", "{{json .Manifest}}")
        $itDigest = $null; try { $itDigest = ($it.text | ConvertFrom-Json).digest } catch { }

        # Pull por digest: se quita la etiqueta del registro y se pide la imagen SOLO por su digest.
        docker rmi $remote | Out-Null
        $byDigest = "$Registry/proyecto-seguridad-$c@$digest"
        $pull = Native "docker" @("pull", $byDigest)
        $idPulled = if ($pull.exit -eq 0) { (docker image inspect --format "{{.Id}}" $byDigest).Trim() } else { $null }

        $same = ($idBefore -eq $idTagged) -and ($idPulled -eq $idBefore)
        if (-not $same -or -not $digest) { $mechanicsOk = $false }
        $entry.status = "PUBLISHED"
        $entry.published_ref = $remote
        $entry.image_ref_by_digest = $byDigest
        $entry.registry_digest = $digest
        $entry.imagetools_digest = $itDigest
        $entry.image_id_after_tag = $idTagged
        $entry.image_id_after_pull_by_digest = $idPulled
        $entry.same_image = $same
        $entry.digest_equals_local_image_id = ($digest -eq $idBefore)
        Write-Host ("  [PUBLICADA] {0} -> {1}`n              mismo image ID antes/después/pull por digest: {2}" -f $c, $byDigest, $same) -ForegroundColor Green
        $results += $entry
    }
}
catch {
    $mechanicsOk = $false
    Write-Host "[ERROR] $_" -ForegroundColor Red
    $results += [ordered]@{ status = "ERROR"; reason = "$_" }
}
finally {
    # Limpieza: registro temporal (con su volumen) y etiquetas locales que apuntan a él.
    docker rm -f -v $RegName 2>$null | Out-Null
    docker image ls --format "{{.Repository}}:{{.Tag}}@{{.Digest}}" | Where-Object { $_ -like "$Registry/*" } | ForEach-Object {
        $repoTag = $_.Split("@")[0]; if ($repoTag -notlike "*:<none>") { docker rmi $repoTag 2>$null | Out-Null }
    }
    docker image ls --digests --format "{{.Repository}}@{{.Digest}}" | Where-Object { $_ -like "$Registry/*" -and $_ -notlike "*@<none>" } | ForEach-Object { docker rmi $_ 2>$null | Out-Null }
    $registryRemoved = -not (docker ps -a --filter "name=^${RegName}$" --format "{{.Names}}")
    Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
}

$published = @($results | Where-Object { $_.status -eq "PUBLISHED" } | ForEach-Object { $_.component })
$blocked = @($results | Where-Object { $_.status -eq "BLOCKED" } | ForEach-Object { $_.component })
$report = [ordered]@{
    item = "5.5"; commit = $Sha; worktree_clean = ($dirty.Count -eq 0)
    executed_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    mode = "simulación local (registro temporal registry:2.8.3 en 127.0.0.1:$Port, sin Docker Hub)"
    registry_image = $RegImage
    gate_rule = "Se publica una imagen solo si Trivy image (HIGH/CRITICAL corregibles), Conftest del Dockerfile y de docker-compose.yml y conftest verify están en PASS"
    images = $results
    published = $published; blocked = $blocked
    negative_case = $(if ($blocked.Count) { "Una comprobación obligatoria fallida impide publicar: " + ($blocked -join ", ") } else { $null })
    mechanics_verified = $mechanicsOk
    registry_removed = $registryRemoved
}
$out = Join-Path $ReportDir "release-local-sim-$Sha.json"
[System.IO.File]::WriteAllText($out, ($report | ConvertTo-Json -Depth 8), $Utf8)
Write-Host "`n=== Publicadas: $($published -join ', ')  |  Bloqueadas: $($blocked -join ', ')  |  mecánica verificada: $mechanicsOk  |  registro eliminado: $registryRemoved"
Write-Host "    -> $out"
if (-not $mechanicsOk) { exit 1 }
exit 0
