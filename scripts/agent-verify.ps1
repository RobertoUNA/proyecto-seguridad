<#
.SYNOPSIS
  Ítem 2.4 — Wrapper de verificación del agente (hook "Stop" de Claude Code).

.DESCRIPTION
  Ejecuta, en orden, las verificaciones del proyecto y reporta cada paso como
  PASS / FAIL / SKIPPED / INCOMPLETE:
    1. frontend:lint        npm run lint
    2. frontend:build       npm run build
    3. backend:lint         npm run lint     (SKIPPED si el script no existe)
    4. backend:build        npm run build
    5. backend:test         npm test         (SKIPPED si el script no existe; las pruebas son de Billy, 2.2)
    6. security:sast-check  python scripts/sast-check.py   (reglas .semgrep.yml de Roberto, 2.3)
    7. security:semgrep     semgrep/semgrep:1.185.0 (fijada por digest) con .semgrep.yml
    8. security:gitleaks    zricethezav/gitleaks:v8.21.2 con .gitleaks.toml y --redact
    9. containers:policy    scripts/policy-check.ps1 (Conftest, 3.4)
   10. containers:trivy     scripts/container-scan.ps1 (Trivy + SBOM, 3.3)   solo con -Full

  INCOMPLETE = la herramienta no se pudo ejecutar (Docker apagado, comando o dependencias
  inexistentes). Cuenta como fallo: un análisis que no se ejecutó no está aprobado.
  SKIPPED nunca cuenta como PASS: se informa como pendiente.

  Sin cambios en código, configuración de seguridad o despliegue (git status) termina en PASS
  ("sin cambios que verificar"). Si solo cambiaron otros archivos (por ejemplo docs/), se
  ejecuta únicamente Gitleaks.

  -Hook: modo hook "Stop" de Claude Code (lee el JSON de stdin).
    PASS                          -> exit 0 y se reinicia el contador .claude/verify-attempts
    FAIL, intento < 3             -> exit 2 y resumen en stderr (el agente lo recibe y corrige)
    FAIL, intento = 3 (límite)    -> reports/agent-verify-blocked-<ts>.json,
                                     "BLOQUEO: requiere intervención humana", exit 0 (sin ciclo)
    stop_hook_active = false      -> nueva tarea: el contador se reinicia antes de verificar.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/agent-verify.ps1          # verificación normal
  powershell -ExecutionPolicy Bypass -File scripts/agent-verify.ps1 -Full    # + Trivy/SBOM
#>
param(
    [switch]$Full,
    [switch]$Hook
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$env:PYTHONIOENCODING = "utf-8"
$env:NO_COLOR = "1"; $env:FORCE_COLOR = "0"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$MaxAttempts = 3
$SemgrepImage = "semgrep/semgrep:1.185.0@sha256:67518c174185a2043fdbed16c70631b79209499b3671178e7194379b48295a0d"
$GitleaksImage = "zricethezav/gitleaks:v8.21.2@sha256:0e99e8821643ea5b235718642b93bb32486af9c8162c8b8731f7cbdc951a7f46"
$CounterFile = Join-Path $Root ".claude/verify-attempts"
$Reports = Join-Path $Root "reports"
$Utf8 = New-Object System.Text.UTF8Encoding($false)

# Rutas cuyo cambio exige la verificación completa.
$WatchedPaths = @("backend", "frontend", "policy", "scripts", "workers", "docker-compose.yml",
                  ".semgrep.yml", ".gitleaks.toml", ".github")
# Salidas del propio wrapper: no cuentan como cambios (evita que se dispare a sí mismo).
$OwnOutputs = '^(reports/agent-verify-|\.claude/verify-attempts)'

# En modo hook la salida de progreso va a un log; stdout queda libre para el JSON de Claude Code.
$Log = New-Object System.Collections.Generic.List[string]
function Say([string]$msg) { $Log.Add($msg); if (-not $Hook) { Write-Host $msg } }

# ----------------------------------------------------------------------------- utilidades
function Invoke-Native([string]$Exe, [string[]]$Arguments) {
    $out = & $Exe @Arguments 2>&1 | ForEach-Object { "$_" }
    return @{ exit = $LASTEXITCODE; lines = @($out) }
}

# Quita fragmentos de código y cualquier valor con forma de token antes de guardar o mostrar.
function Protect-Lines([string[]]$Lines) {
    $Lines | ForEach-Object { $_ -replace "$([char]27)\[[0-9;]*[A-Za-z]", "" } | ForEach-Object {
        if ($_ -match '^\s*C[oó]digo:') { "    Código:  [omitido por agent-verify]" }
        else {
            $_ -replace '(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}|sk-[A-Za-z0-9]{20,})', '[REDACTED]'
        }
    }
}

# Primeras líneas útiles del error (si no hay líneas de error reconocibles, las últimas).
function Get-Excerpt([string[]]$Lines, [int]$Max = 12) {
    $clean = @(Protect-Lines ($Lines | Where-Object { $_ -and $_.Trim() }))
    $err = @($clean | Where-Object { $_ -match '(?i)error|fail|✗|\bx\b|denied|deny|leak|finding|hallazgo|not found|no se|cannot|missing' })
    if ($err.Count -gt 0) { return @($err | Select-Object -First $Max) }
    return @($clean | Select-Object -Last $Max)
}

function Get-Files([string[]]$Lines) {
    $found = foreach ($l in $Lines) {
        [regex]::Matches($l, '((?:[\w.-]+/)*[\w.-]+\.(?:tsx?|jsx?|py|rego|ya?ml|json|toml|md|sh|ps1))(?::(\d+))?') |
            ForEach-Object { $_.Value }
    }
    return @($found | Where-Object { $_ -notmatch '^(package|tsconfig)' } | Select-Object -Unique -First 5)
}

$Results = New-Object System.Collections.Generic.List[object]
function Add-Result($Id, $Status, $Command, $Lines = @(), $Note = "", $Seconds = 0) {
    $r = [ordered]@{ id = $Id; status = $Status; command = $Command; seconds = $Seconds }
    if ($Note) { $r.note = $Note }
    if ($Status -in @("FAIL", "INCOMPLETE")) {
        $r.excerpt = @(Get-Excerpt $Lines)
        $r.files = @(Get-Files $r.excerpt)
    }
    $Results.Add($r)
    Say ("  [{0,-10}] {1,-20} {2}" -f $Status, $Id, $(if ($Note) { $Note } else { $Command }))
}

function Test-NpmScript([string]$Dir, [string]$Name) {
    $pkg = Get-Content (Join-Path $Root "$Dir/package.json") -Raw -Encoding UTF8 | ConvertFrom-Json
    return [bool]($pkg.scripts.PSObject.Properties.Name -contains $Name)
}

function Invoke-NpmStep([string]$Id, [string]$Dir, [string]$Script) {
    $cmd = "cd $Dir && npm run $Script"
    if (-not (Get-Command npm -ErrorAction SilentlyContinue)) { Add-Result $Id "INCOMPLETE" $cmd @("npm no está instalado o no está en PATH"); return }
    if (-not (Test-NpmScript $Dir $Script)) { Add-Result $Id "SKIPPED" $cmd @() "el script '$Script' no existe en $Dir/package.json"; return }
    if (-not (Test-Path (Join-Path $Root "$Dir/node_modules"))) { Add-Result $Id "INCOMPLETE" $cmd @("$Dir/node_modules no existe: ejecute 'npm ci' en $Dir"); return }
    $t = [Diagnostics.Stopwatch]::StartNew()
    Push-Location (Join-Path $Root $Dir)
    $r = Invoke-Native "npm" @("run", $Script)
    Pop-Location
    Add-Result $Id $(if ($r.exit -eq 0) { "PASS" } else { "FAIL" }) $cmd $r.lines "" ([math]::Round($t.Elapsed.TotalSeconds, 1))
}

# Empaqueta archivos versionables (git ls-files -co --exclude-standard) en un tar. Se usa para
# entregar el código a Semgrep/Gitleaks en Docker sin bind-mount del repo (que en Windows es muy lento).
function New-SourceTar([string]$TarPath, [string[]]$PathSpec) {
    $files = @(git -c core.quotepath=false ls-files -co --exclude-standard -- @PathSpec |
               Where-Object { $_ -and (Test-Path -LiteralPath (Join-Path $Root $_) -PathType Leaf) })
    $list = "$TarPath.list"
    [System.IO.File]::WriteAllText($list, (($files -join "`n") + "`n"), $Utf8)
    $tar = Join-Path $env:SystemRoot "System32/tar.exe"
    if (-not (Test-Path $tar)) { $tar = "tar" }
    $r = Invoke-Native $tar @("-cf", $TarPath, "-T", $list)
    return ($r.exit -eq 0)
}

# ----------------------------------------------------------------------------- verificación
function Invoke-Verification {
    $script:Results.Clear()
    $sha = (git rev-parse HEAD).Trim()
    $porcelain = @(git -c core.quotepath=false status --porcelain --untracked-files=all |
                   ForEach-Object { $_.Substring(3).Trim('"') } | Where-Object { $_ -notmatch $OwnOutputs })
    $codeChanged = @($porcelain | Where-Object { $p = $_; @($WatchedPaths | Where-Object { $p -eq $_ -or $p.StartsWith("$_/") }).Count -gt 0 })

    $summary = [ordered]@{
        item = "2.4"; commit = $sha; executed_at = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        mode = $(if ($Full) { "full" } else { "standard" }); changed_files = @($porcelain | Select-Object -First 50)
        steps = $null; result = $null
    }

    if ($porcelain.Count -eq 0) {
        Say "agent-verify: sin cambios que verificar (git status limpio) -> PASS"
        $summary.result = "PASS"; $summary.note = "sin cambios que verificar"; $summary.steps = @()
        return $summary
    }

    $work = Join-Path ([System.IO.Path]::GetTempPath()) ("agent-verify-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force $work | Out-Null
    $dockerOk = $false
    if (Get-Command docker -ErrorAction SilentlyContinue) { docker info *> $null; $dockerOk = ($LASTEXITCODE -eq 0) }
    $noDocker = @("Docker no está disponible (instalado y con el daemon en ejecución): el análisis no se ejecutó")

    Say "agent-verify ($($summary.mode)) commit $($sha.Substring(0,7)) | archivos cambiados: $($porcelain.Count)"
    try {
        if ($codeChanged.Count -gt 0) {
            # ---- a) frontend
            Invoke-NpmStep "frontend:lint" "frontend" "lint"
            Invoke-NpmStep "frontend:build" "frontend" "build"
            # ---- b) backend
            Invoke-NpmStep "backend:lint" "backend" "lint"
            Invoke-NpmStep "backend:build" "backend" "build"
            Invoke-NpmStep "backend:test" "backend" "test"

            # ---- c) seguridad: SAST con las reglas de Roberto
            $py = $null
            foreach ($c in @("python", "python3", "py")) {
                if (Get-Command $c -ErrorAction SilentlyContinue) { & $c -c "import sys" *> $null; if ($LASTEXITCODE -eq 0) { $py = $c; break } }
            }
            if (-not $py) { Add-Result "security:sast-check" "INCOMPLETE" "python scripts/sast-check.py" @("Python no está disponible") }
            else {
                $t = [Diagnostics.Stopwatch]::StartNew()
                $r = Invoke-Native $py @("scripts/sast-check.py")
                Add-Result "security:sast-check" $(if ($r.exit -eq 0) { "PASS" } else { "FAIL" }) "python scripts/sast-check.py" $r.lines "" ([math]::Round($t.Elapsed.TotalSeconds, 1))
            }

            # ---- c) seguridad: Semgrep CE fijado por digest
            $cmd = "semgrep scan --config .semgrep.yml --error backend/src frontend/src workers"
            if (-not $dockerOk) { Add-Result "security:semgrep" "INCOMPLETE" $cmd $noDocker }
            elseif (-not (New-SourceTar (Join-Path $work "semgrep.tar") @("backend/src", "frontend/src", "workers", ".semgrep.yml"))) {
                Add-Result "security:semgrep" "INCOMPLETE" $cmd @("No se pudo empaquetar el código fuente para Semgrep")
            } else {
                $t = [Diagnostics.Stopwatch]::StartNew()
                $r = Invoke-Native "docker" @("run", "--rm", "-v", "${work}:/in:ro", "--entrypoint", "sh", $SemgrepImage, "-c",
                    "mkdir -p /w && tar -xf /in/semgrep.tar -C /w && cd /w && semgrep scan --config .semgrep.yml --error --metrics=off --disable-version-check --quiet --json --output /tmp/out.json backend/src frontend/src workers >/dev/null 2>/tmp/err; rc=`$?; cat /tmp/out.json 2>/dev/null || cat /tmp/err; exit `$rc")
                $lines = @()
                $status = switch ($r.exit) { 0 { "PASS" } 1 { "FAIL" } default { "INCOMPLETE" } }
                try {
                    $sg = ($r.lines -join "`n") | ConvertFrom-Json
                    $lines = @($sg.results | ForEach-Object { "error: $($_.check_id) en $($_.path):$($_.start.line) — $($_.extra.message)" })
                    $lines += @($sg.errors | ForEach-Object { "error de Semgrep: $($_.message)" })
                    if ($status -eq "PASS" -and @($sg.errors).Count -gt 0) { $status = "INCOMPLETE" }
                } catch { $lines = $r.lines; if ($status -ne "FAIL") { $status = "INCOMPLETE" } }
                Add-Result "security:semgrep" $status $cmd $lines "" ([math]::Round($t.Elapsed.TotalSeconds, 1))
            }
        } else {
            Say "  (sin cambios en código/configuración: solo se ejecuta Gitleaks)"
        }

        # ---- c) seguridad: Gitleaks (se ejecuta ante cualquier cambio, incluso solo en docs/)
        $cmd = "gitleaks dir --config .gitleaks.toml --redact"
        if (-not $dockerOk) { Add-Result "security:gitleaks" "INCOMPLETE" $cmd $noDocker }
        elseif (-not (New-SourceTar (Join-Path $work "repo.tar") @("."))) {
            Add-Result "security:gitleaks" "INCOMPLETE" $cmd @("No se pudo empaquetar el árbol versionable para Gitleaks")
        } else {
            $t = [Diagnostics.Stopwatch]::StartNew()
            $r = Invoke-Native "docker" @("run", "--rm", "-v", "${work}:/in:ro", "--entrypoint", "sh", $GitleaksImage, "-c",
                "mkdir -p /w && tar -xf /in/repo.tar -C /w && cd /w && gitleaks dir . --config .gitleaks.toml --redact --no-banner --log-level error --report-format json --report-path /tmp/r.json --exit-code 1 >/tmp/log 2>&1; rc=`$?; if [ -f /tmp/r.json ]; then cat /tmp/r.json; else cat /tmp/log; fi; exit `$rc")
            $status = switch ($r.exit) { 0 { "PASS" } 1 { "FAIL" } default { "INCOMPLETE" } }
            $lines = $r.lines
            try {
                $gl = @((($r.lines -join "`n") | ConvertFrom-Json) | ForEach-Object { $_ })
                # Reporte enmascarado (--redact): conserva regla, archivo y línea; el secreto queda como REDACTED.
                [System.IO.File]::WriteAllText((Join-Path $Reports "agent-verify-gitleaks-last.json"), ($r.lines -join "`n"), $Utf8)
                $lines = @($gl | ForEach-Object { "leak: regla $($_.RuleID) en $($_.File):$($_.StartLine) (valor enmascarado: $($_.Secret))" })
            } catch { if ($status -eq "FAIL") { $status = "INCOMPLETE" } }
            Add-Result "security:gitleaks" $status $cmd $lines "" ([math]::Round($t.Elapsed.TotalSeconds, 1))
        }

        if ($codeChanged.Count -gt 0) {
            # ---- d) contenedores: Conftest (3.4). Reportes en carpeta temporal: no toca la evidencia de reports/.
            $cmd = "scripts/policy-check.ps1"
            if (-not $dockerOk) { Add-Result "containers:policy" "INCOMPLETE" $cmd $noDocker }
            else {
                $t = [Diagnostics.Stopwatch]::StartNew()
                $pdir = Join-Path $work "policy"; New-Item -ItemType Directory -Force $pdir | Out-Null
                $r = Invoke-Native "powershell" @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $Root "scripts/policy-check.ps1"), "-ReportDir", $pdir)
                $pj = Get-ChildItem $pdir -Filter "conftest-*.json" -ErrorAction SilentlyContinue | Select-Object -First 1
                $status = if (-not $pj) { "INCOMPLETE" } elseif ($r.exit -eq 0) { "PASS" } else { "FAIL" }
                Add-Result "containers:policy" $status $cmd $r.lines "" ([math]::Round($t.Elapsed.TotalSeconds, 1))
            }

            # ---- d) contenedores: Trivy + SBOM (3.3), solo con -Full
            $cmd = "scripts/container-scan.ps1"
            if (-not $Full) { Add-Result "containers:trivy" "SKIPPED" $cmd @() "solo con -Full (tarda varios minutos)" }
            elseif (-not $dockerOk) { Add-Result "containers:trivy" "INCOMPLETE" $cmd $noDocker }
            else {
                $t = [Diagnostics.Stopwatch]::StartNew()
                $cdir = Join-Path $work "trivy"; New-Item -ItemType Directory -Force $cdir | Out-Null
                $r = Invoke-Native "powershell" @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", (Join-Path $Root "scripts/container-scan.ps1"), "-ReportDir", $cdir)
                $cj = Get-ChildItem $cdir -Filter "container-scan-*.json" -ErrorAction SilentlyContinue | Select-Object -First 1
                $status = if (-not $cj) { "INCOMPLETE" } elseif ($r.exit -eq 0) { "PASS" } else { "FAIL" }
                Add-Result "containers:trivy" $status $cmd $r.lines "" ([math]::Round($t.Elapsed.TotalSeconds, 1))
            }
        }
    } finally {
        Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
    }

    $summary.steps = $Results.ToArray()
    $bad = @($Results | Where-Object { $_.status -in @("FAIL", "INCOMPLETE") })
    $summary.result = if ($bad.Count -gt 0) { "FAIL" } else { "PASS" }
    $summary.skipped = @($Results | Where-Object { $_.status -eq "SKIPPED" } | ForEach-Object { $_.id })
    New-Item -ItemType Directory -Force $Reports | Out-Null
    [System.IO.File]::WriteAllText((Join-Path $Reports "agent-verify-last.json"), ($summary | ConvertTo-Json -Depth 6), $Utf8)
    return $summary
}

# Resumen corto para el agente: qué falló, archivo y primeras líneas del error.
function Format-AgentSummary($S, [string]$Header) {
    $sb = New-Object System.Text.StringBuilder
    $bad = @($S.steps | Where-Object { $_.status -in @("FAIL", "INCOMPLETE") })
    [void]$sb.AppendLine("$Header agent-verify: $($S.result) (commit $($S.commit.Substring(0,7)), $($bad.Count) de $(@($S.steps).Count) pasos con problemas)")
    foreach ($b in $bad) {
        $files = if ($b.files.Count) { " | archivos: " + ($b.files -join ", ") } else { "" }
        [void]$sb.AppendLine("- $($b.id) [$($b.status)] $($b.command)$files")
        foreach ($l in ($b.excerpt | Select-Object -First 6)) { [void]$sb.AppendLine("    $l") }
    }
    if (@($S.skipped).Count) { [void]$sb.AppendLine("Omitidos (no cuentan como aprobados): " + ($S.skipped -join ", ")) }
    [void]$sb.AppendLine("Detalle: reports/agent-verify-last.json")
    return $sb.ToString().TrimEnd()
}

# ----------------------------------------------------------------------------- modo normal
if (-not $Hook) {
    $s = Invoke-Verification
    if ($s.result -eq "PASS") {
        if ($s.note) { Write-Host "[PASS] $($s.note)" -ForegroundColor Green }
        else { Write-Host "`n[PASS] agent-verify: todas las verificaciones aprobaron. Omitidos: $($s.skipped -join ', ')" -ForegroundColor Green }
        exit 0
    }
    Write-Host ""
    Write-Host (Format-AgentSummary $s "[FAIL]") -ForegroundColor Red
    exit 1
}

# ----------------------------------------------------------------------------- modo hook (Stop)
$hookInput = $null
try { $raw = [Console]::In.ReadToEnd(); if ($raw.Trim()) { $hookInput = $raw | ConvertFrom-Json } } catch { }
$stopHookActive = [bool]($hookInput -and $hookInput.stop_hook_active)

New-Item -ItemType Directory -Force (Split-Path $CounterFile) | Out-Null
# stop_hook_active = false: es una tarea nueva (no una continuación provocada por este hook).
if (-not $stopHookActive) { Remove-Item $CounterFile -Force -ErrorAction SilentlyContinue }

$s = Invoke-Verification
$history = Join-Path $Reports "agent-verify-hook-history.jsonl"

if ($s.result -eq "PASS") {
    Remove-Item $CounterFile -Force -ErrorAction SilentlyContinue
    if (-not $s.note) {
        $line = [ordered]@{ at = $s.executed_at; commit = $s.commit; stop_hook_active = $stopHookActive; attempt = 0; result = "PASS"; failed = @() }
        [System.IO.File]::AppendAllText($history, (($line | ConvertTo-Json -Compress) + "`n"), $Utf8)
    }
    exit 0
}

$attempt = 1
if (Test-Path $CounterFile) { $prev = 0; [void][int]::TryParse((Get-Content $CounterFile -Raw).Trim(), [ref]$prev); $attempt = $prev + 1 }
[System.IO.File]::WriteAllText($CounterFile, "$attempt", $Utf8)
$failed = @($s.steps | Where-Object { $_.status -in @("FAIL", "INCOMPLETE") } | ForEach-Object { "$($_.id):$($_.status)" })
$line = [ordered]@{ at = $s.executed_at; commit = $s.commit; stop_hook_active = $stopHookActive; attempt = $attempt; result = "FAIL"; failed = $failed }
[System.IO.File]::AppendAllText($history, (($line | ConvertTo-Json -Compress) + "`n"), $Utf8)

if ($attempt -ge $MaxAttempts) {
    $ts = (Get-Date).ToUniversalTime().ToString("yyyyMMddTHHmmssZ")
    $blocked = [ordered]@{
        item = "2.4"; status = "BLOCKED"; message = "BLOQUEO: requiere intervención humana"
        attempts = $attempt; max_attempts = $MaxAttempts; commit = $s.commit; blocked_at = $s.executed_at
        failed_steps = @($s.steps | Where-Object { $_.status -in @("FAIL", "INCOMPLETE") })
        next_steps = "Revisar los pasos fallidos. Tras corregir (o decidir una excepción con revisión de otro integrante), borrar .claude/verify-attempts o iniciar una tarea nueva."
    }
    $blockedPath = "reports/agent-verify-blocked-$ts.json"
    [System.IO.File]::WriteAllText((Join-Path $Root $blockedPath), ($blocked | ConvertTo-Json -Depth 6), $Utf8)
    $msg = "BLOQUEO: requiere intervención humana. agent-verify falló en $attempt de $MaxAttempts intentos ($($failed -join ', ')). Evidencia: $blockedPath"
    [Console]::Error.WriteLine($msg)
    # exit 0: se permite detenerse (sin ciclo infinito) y el mensaje se muestra al usuario.
    [Console]::Out.WriteLine((@{ systemMessage = $msg } | ConvertTo-Json -Compress))
    exit 0
}

[Console]::Error.WriteLine((Format-AgentSummary $s "[INTENTO $attempt de $MaxAttempts]"))
[Console]::Error.WriteLine("Corrija los fallos anteriores. No modifique reglas de seguridad (.semgrep.yml, .gitleaks.toml, policy/) ni este script para que pasen; si no puede corregirlo, explíquelo y deténgase.")
exit 2
