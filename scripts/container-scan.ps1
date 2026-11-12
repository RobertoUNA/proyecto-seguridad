<#
.SYNOPSIS
  Ítem 3.3 — Construye las imágenes candidatas y las analiza con Trivy (THR-05 / CTL-05).

.DESCRIPTION
  Para un SHA de commit (por defecto `git rev-parse HEAD`):
    1. Construye proyecto-seguridad-backend:sha-<SHA> y proyecto-seguridad-frontend:sha-<SHA>
       (etiqueta OCI org.opencontainers.image.revision=<SHA>).
    2. Trivy `config` sobre backend/Dockerfile, frontend/Dockerfile y docker-compose.yml.
       Bloquea si hay configuraciones HIGH/CRITICAL fallidas.
    3. Trivy `image` sobre cada imagen (HIGH,CRITICAL, --ignore-unfixed, --exit-code 1).
    4. SBOM CycloneDX de cada imagen.
    5. reports/container-scan-<SHA>.json con commit, imágenes, IDs, fecha, versión de Trivy y resultado.
  Trivy se ejecuta con su imagen oficial fijada por digest; no se instala en el sistema.
  Las imágenes se le entregan como tar (`docker save`): Trivy NO recibe el socket de Docker.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/container-scan.ps1
  powershell -ExecutionPolicy Bypass -File scripts/container-scan.ps1 -Sha 0123abcd...
#>
param(
    [string]$Sha = "",
    # Carpeta alternativa de reportes (la usa scripts/agent-verify para no sobrescribir la evidencia de reports/).
    [string]$ReportDir = $env:REPORT_DIR
)

# "Continue": los comandos nativos (docker) escriben progreso en stderr; el resultado
# de cada paso se decide por $LASTEXITCODE, nunca por la salida de error.
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root

$TrivyVersion = "0.76.2"
$TrivyImage = "aquasec/trivy:${TrivyVersion}@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb"
$CacheVolume = "proyecto-seguridad-trivy-cache"
$Components = @("backend", "frontend")

function Write-Step($msg) { Write-Host "`n=== $msg" -ForegroundColor Cyan }

$work = $null
try {
    if (-not $Sha) { $Sha = (git rev-parse HEAD).Trim() }
    if ($Sha -notmatch '^[0-9a-f]{7,40}$') { throw "SHA inválido: '$Sha'" }

    # Trazabilidad: si lo analizado tiene cambios sin confirmar, el SHA no describe la imagen.
    $dirty = @(git status --porcelain -- backend frontend docker-compose.yml)
    $worktreeClean = ($dirty.Count -eq 0)
    if (-not $worktreeClean) {
        Write-Host "[AVISO] Hay cambios sin confirmar en backend/, frontend/ o docker-compose.yml: los reportes NO describen exactamente el commit $Sha." -ForegroundColor Yellow
    }

    $Reports = if ($ReportDir) { $ReportDir } else { Join-Path $Root "reports" }
    New-Item -ItemType Directory -Force $Reports | Out-Null
    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("container-scan-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force $work | Out-Null
    docker volume create $CacheVolume | Out-Null

    $failed = $false
    $images = @()

    # ---------------------------------------------------------------- 1. build
    foreach ($c in $Components) {
        $name = "proyecto-seguridad-${c}:sha-$Sha"
        Write-Step "1/4 Construyendo $name"
        docker build --pull=false --build-arg "COMMIT_SHA=$Sha" --label "org.opencontainers.image.revision=$Sha" -t $name (Join-Path $Root $c)
        $buildOk = ($LASTEXITCODE -eq 0)
        if (-not $buildOk) { $failed = $true }
        $images += [ordered]@{ component = $c; image = $name; build = $(if ($buildOk) { "PASS" } else { "FAIL" }) }
    }

    # ---------------------------------------------------------------- 2. trivy config
    Write-Step "2/4 Trivy config (Dockerfiles + docker-compose.yml)"
    $stage = Join-Path $work "iac"
    New-Item -ItemType Directory -Force (Join-Path $stage "backend"), (Join-Path $stage "frontend") | Out-Null
    Copy-Item (Join-Path $Root "backend/Dockerfile") (Join-Path $stage "backend/Dockerfile")
    Copy-Item (Join-Path $Root "frontend/Dockerfile") (Join-Path $stage "frontend/Dockerfile")
    Copy-Item (Join-Path $Root "docker-compose.yml") (Join-Path $stage "docker-compose.yml")
    $configReport = "trivy-config-$Sha.json"
    docker run --rm -v "${CacheVolume}:/root/.cache" -v "${stage}:/iac:ro" -v "${Reports}:/reports" `
        $TrivyImage config --quiet --format json --output "/reports/$configReport" /iac
    $configExec = ($LASTEXITCODE -eq 0)
    $configBlocking = -1
    if ($configExec) {
        $cfg = Get-Content (Join-Path $Reports $configReport) -Raw -Encoding UTF8 | ConvertFrom-Json
        $configBlocking = @($cfg.Results | ForEach-Object { $_.Misconfigurations } |
            Where-Object { $_ -and $_.Status -eq "FAIL" -and $_.Severity -in @("HIGH", "CRITICAL") }).Count
        docker run --rm -v "${Reports}:/reports:ro" $TrivyImage convert --format table "/reports/$configReport"
    }
    $configStatus = if (-not $configExec) { "INCOMPLETE" } elseif ($configBlocking -gt 0) { "FAIL" } else { "PASS" }
    if ($configStatus -ne "PASS") { $failed = $true }
    Write-Host "Trivy config: $configStatus (HIGH/CRITICAL fallidas: $configBlocking)"

    # ---------------------------------------------------------------- 3 y 4. trivy image + SBOM
    foreach ($img in $images) {
        $c = $img.component
        if ($img.build -ne "PASS") { $img.image_scan = "INCOMPLETE"; $img.sbom = "INCOMPLETE"; continue }

        $img.image_id = (docker image inspect --format "{{.Id}}" $img.image).Trim()
        $repoDigests = docker image inspect --format "{{json .RepoDigests}}" $img.image | ConvertFrom-Json
        $img.repo_digests = @($repoDigests)
        $labels = docker image inspect --format "{{json .Config.Labels}}" $img.image | ConvertFrom-Json
        $img.revision_label = $labels.'org.opencontainers.image.revision'

        $tar = Join-Path $work "$c.tar"
        docker save -o $tar $img.image
        if ($LASTEXITCODE -ne 0) { $img.image_scan = "INCOMPLETE"; $img.sbom = "INCOMPLETE"; $failed = $true; continue }

        Write-Step "3/4 Trivy image $($img.image) (HIGH,CRITICAL, --ignore-unfixed)"
        $imgReport = "trivy-image-$c-$Sha.json"
        docker run --rm -v "${CacheVolume}:/root/.cache" -v "${work}:/work:ro" -v "${Reports}:/reports" `
            $TrivyImage image --input "/work/$c.tar" --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 `
            --quiet --format json --output "/reports/$imgReport"
        $code = $LASTEXITCODE
        $img.image_scan = switch ($code) { 0 { "PASS" } 1 { "FAIL" } default { "INCOMPLETE" } }
        $img.image_report = "reports/$imgReport"
        if (Test-Path (Join-Path $Reports $imgReport)) {
            $r = Get-Content (Join-Path $Reports $imgReport) -Raw -Encoding UTF8 | ConvertFrom-Json
            # Digest de configuración que Trivy registra en el reporte y en el SBOM (aquasecurity:trivy:ImageID).
            $img.config_digest = $r.Metadata.ImageID
            $vulns = @($r.Results | ForEach-Object { $_.Vulnerabilities } | Where-Object { $_ })
            $img.vulnerabilities = [ordered]@{
                critical = @($vulns | Where-Object Severity -eq "CRITICAL").Count
                high     = @($vulns | Where-Object Severity -eq "HIGH").Count
            }
            docker run --rm -v "${Reports}:/reports:ro" $TrivyImage convert --format table "/reports/$imgReport"
        }
        if ($img.image_scan -ne "PASS") { $failed = $true }
        Write-Host "Trivy image ${c}: $($img.image_scan)"

        Write-Step "4/4 SBOM CycloneDX $($img.image)"
        $sbom = "sbom-$c-$Sha.cdx.json"
        docker run --rm -v "${CacheVolume}:/root/.cache" -v "${work}:/work:ro" -v "${Reports}:/reports" `
            $TrivyImage image --input "/work/$c.tar" --quiet --format cyclonedx --output "/reports/$sbom"
        $img.sbom = if ($LASTEXITCODE -eq 0) { "PASS" } else { "FAIL" }
        $img.sbom_report = "reports/$sbom"
        if ($img.sbom -ne "PASS") { $failed = $true }
        Remove-Item $tar -Force
    }

    # ---------------------------------------------------------------- resumen
    $ver = docker run --rm -v "${CacheVolume}:/root/.cache" $TrivyImage version --format json | ConvertFrom-Json
    $summary = [ordered]@{
        item            = "3.3"
        controls        = @("THR-05", "CTL-05")
        commit          = $Sha
        worktree_clean  = $worktreeClean
        scanned_at      = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        trivy           = [ordered]@{ version = $ver.Version; image = $TrivyImage; vulnerability_db_updated_at = $ver.VulnerabilityDB.UpdatedAt }
        policy          = "Bloquea: vulnerabilidades HIGH/CRITICAL con corrección disponible (--ignore-unfixed) y configuraciones HIGH/CRITICAL fallidas"
        config_scan     = [ordered]@{ targets = @("backend/Dockerfile", "frontend/Dockerfile", "docker-compose.yml"); report = "reports/$configReport"; blocking_findings = $configBlocking; result = $configStatus }
        images          = $images
        result          = $(if ($failed) { "FAILED" } else { "APPROVED" })
    }
    $summaryPath = Join-Path $Reports "container-scan-$Sha.json"
    # UTF-8 sin BOM para que jq/python lo lean sin problemas.
    [System.IO.File]::WriteAllText($summaryPath, ($summary | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
    Write-Step "Resultado: $($summary.result)  ->  reports/container-scan-$Sha.json"
    if ($failed) { exit 1 }
    exit 0
}
finally {
    if ($work -and (Test-Path $work)) { Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue }
    Pop-Location
}
