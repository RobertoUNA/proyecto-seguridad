<#
.SYNOPSIS
  Ítem 3.4 — Verifica las políticas de contenedor (policy/container.rego) con Conftest (THR-05 / CTL-05).

.DESCRIPTION
  1. `conftest verify`: pruebas unitarias de la política (policy/container_test.rego).
  2. `conftest test` sobre los archivos REALES (deben pasar sin fallos ni advertencias):
       backend/Dockerfile, frontend/Dockerfile (--parser dockerfile) y docker-compose.yml (--parser yaml).
  3. `conftest test` sobre los ejemplos INSEGUROS de policy/examples/ (cada uno DEBE ser rechazado).
     Se comprueba en el JSON que haya un `deny` real: un error de Conftest no cuenta como rechazo.
  Salidas: reports/conftest-<sha>.json y reports/conftest-insecure-demo-<sha>.txt.
  Conftest se ejecuta con su imagen oficial fijada por digest; no se instala en el sistema.

  Exit 0 solo si todo es correcto. Si algo no se pudo ejecutar, el estado es INCOMPLETE y el script falla.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts/policy-check.ps1
#>
param(
    [string]$Sha = "",
    # Carpeta alternativa de reportes (la usa scripts/agent-verify para no sobrescribir la evidencia de reports/).
    [string]$ReportDir = $env:REPORT_DIR
)

$ErrorActionPreference = "Continue"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Root = Split-Path -Parent $PSScriptRoot
Push-Location $Root

$ConftestVersion = "v0.71.1"
$ConftestImage = "openpolicyagent/conftest:${ConftestVersion}@sha256:0e77cdf7c1fcde035f3c579e4aaa6664ee2a8be5777eaa9af9f520cdd02280c0"

$Allowed = @(
    @{ parser = "dockerfile"; file = "backend/Dockerfile" },
    @{ parser = "dockerfile"; file = "frontend/Dockerfile" },
    @{ parser = "yaml";       file = "docker-compose.yml" }
)
$Insecure = @(
    @{ parser = "dockerfile"; file = "policy/examples/Dockerfile.insecure" },
    @{ parser = "dockerfile"; file = "policy/examples/Dockerfile.insecure-root" },
    @{ parser = "yaml";       file = "policy/examples/docker-compose.insecure.yml" }
)

# stdout y stderr por separado: `out` (solo stdout) es lo que se interpreta como JSON; `text`
# (stdout + stderr) se usa para la demostración y el diagnóstico. Así el progreso de un `docker pull`
# en un runner limpio no invalida el JSON.
function Invoke-Conftest([string[]]$ConftestArgs) {
    $errFile = [System.IO.Path]::GetTempFileName()
    $out = docker run --rm -v "${Root}:/project:ro" -w /project $ConftestImage @ConftestArgs 2>$errFile | Out-String
    $code = $LASTEXITCODE
    $err = (Get-Content $errFile -Raw -ErrorAction SilentlyContinue) -replace '(?m)^docker : ', ''
    Remove-Item $errFile -Force -ErrorAction SilentlyContinue
    return @{ exit = $code; out = $out; text = ($out + $err) }
}

# Ejecuta `conftest test --output json` sobre un archivo y resume el resultado.
function Test-File($entry) {
    $r = Invoke-Conftest @("test", "--policy", "policy", "--parser", $entry.parser, "--output", "json", "--no-color", $entry.file)
    $res = [ordered]@{ file = $entry.file; parser = $entry.parser; executed = $false; successes = 0; failures = @(); warnings = @() }
    try {
        $j = $r.out | ConvertFrom-Json
        $res.executed = $true
        foreach ($x in @($j | ForEach-Object { $_ })) {
            $res.successes += [int]$x.successes
            $res.failures += @($x.failures | Where-Object { $_ } | ForEach-Object { $_.msg })
            $res.warnings += @($x.warnings | Where-Object { $_ } | ForEach-Object { $_.msg })
        }
    } catch {
        $res.error = $r.text.Trim()
    }
    return $res
}

try {
    if (-not $Sha) { $Sha = (git rev-parse HEAD).Trim() }
    if ($Sha -notmatch '^[0-9a-f]{7,40}$') { throw "SHA inválido: '$Sha'" }
    $Reports = if ($ReportDir) { $ReportDir } else { Join-Path $Root "reports" }
    New-Item -ItemType Directory -Force $Reports | Out-Null
    $dirty = @(git status --porcelain -- policy backend/Dockerfile frontend/Dockerfile docker-compose.yml)
    if ($dirty.Count -gt 0) { Write-Host "[AVISO] Hay cambios sin confirmar en los archivos verificados: el reporte no describe exactamente el commit $Sha." -ForegroundColor Yellow }

    # Descarga explícita de la imagen antes de cualquier ejecución (runner limpio).
    docker pull -q $ConftestImage *> $null
    $version = (Invoke-Conftest @("--version")).out.Trim() -replace "\r?\n", " / "

    # ------------------------------------------------------------ 1. verify
    Write-Host "`n=== 1/3 conftest verify (pruebas unitarias de policy/container.rego)" -ForegroundColor Cyan
    $v = Invoke-Conftest @("verify", "--policy", "policy", "--output", "json", "--no-color")
    $verify = [ordered]@{ result = "INCOMPLETE"; tests = 0; passed = 0; failed = 0 }
    try {
        # En PowerShell 5.1 ConvertFrom-Json emite el arreglo como UN objeto: se enumera explícitamente.
        $parsed = $v.out | ConvertFrom-Json
        $vj = @($parsed | ForEach-Object { $_ })
        $verify.tests = $vj.Count
        $verify.failed = @($vj | Where-Object { @($_.failures | Where-Object { $_ }).Count -gt 0 }).Count
        $verify.passed = $verify.tests - $verify.failed
        $verify.result = if ($verify.failed -eq 0 -and $verify.tests -gt 0) { "PASS" } else { "FAIL" }
    } catch { $verify.error = $v.text.Trim() }
    Write-Host ("verify: {0} ({1} pruebas, {2} ok, {3} fallidas)" -f $verify.result, $verify.tests, $verify.passed, $verify.failed)

    # ------------------------------------------------------------ 2. archivos reales
    Write-Host "`n=== 2/3 conftest test sobre archivos REALES (deben pasar)" -ForegroundColor Cyan
    $allowedResults = @()
    foreach ($e in $Allowed) {
        $r = Test-File $e
        $r.result = if (-not $r.executed) { "INCOMPLETE" } elseif ($r.failures.Count -eq 0 -and $r.warnings.Count -eq 0) { "PASS" } else { "FAIL" }
        Write-Host ("  [{0}] {1} ({2} comprobaciones)" -f $r.result, $r.file, $r.successes)
        $r.failures + $r.warnings | ForEach-Object { Write-Host "        $_" -ForegroundColor Red }
        $allowedResults += $r
    }
    $allowedStatus = if (@($allowedResults | Where-Object { $_.result -eq "INCOMPLETE" }).Count) { "INCOMPLETE" }
                     elseif (@($allowedResults | Where-Object { $_.result -ne "PASS" }).Count) { "FAIL" } else { "PASS" }

    # ------------------------------------------------------------ 3. ejemplos inseguros
    Write-Host "`n=== 3/3 conftest test sobre ejemplos INSEGUROS (deben ser rechazados)" -ForegroundColor Cyan
    $insecureResults = @()
    foreach ($e in $Insecure) {
        $r = Test-File $e
        $r.result = if (-not $r.executed) { "INCOMPLETE" } elseif ($r.failures.Count -gt 0) { "REJECTED" } else { "NOT_REJECTED" }
        Write-Host ("  [{0}] {1}" -f $r.result, $r.file)
        $r.failures | ForEach-Object { Write-Host "        $_" -ForegroundColor Yellow }
        $insecureResults += $r
    }
    $demoStatus = if (@($insecureResults | Where-Object { $_.result -eq "INCOMPLETE" }).Count) { "INCOMPLETE" }
                  elseif (@($insecureResults | Where-Object { $_.result -ne "REJECTED" }).Count) { "FAIL" } else { "PASS" }

    $overall = if ($verify.result -eq "PASS" -and $allowedStatus -eq "PASS" -and $demoStatus -eq "PASS") { "APPROVED" } else { "FAILED" }

    # ------------------------------------------------------------ reportes
    $report = [ordered]@{
        item          = "3.4"
        controls      = @("THR-05", "CTL-05")
        commit        = $Sha
        worktree_clean = ($dirty.Count -eq 0)
        executed_at   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        conftest      = [ordered]@{ version = $version; image = $ConftestImage }
        policy        = "policy/container.rego"
        verify        = $verify
        allowed       = [ordered]@{ expectation = "Sin fallos ni advertencias"; result = $allowedStatus; files = $allowedResults }
        insecure_demo = [ordered]@{ expectation = "Cada ejemplo debe ser rechazado por al menos un deny"; result = $demoStatus; files = $insecureResults }
        result        = $overall
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText((Join-Path $Reports "conftest-$Sha.json"), ($report | ConvertTo-Json -Depth 8), $utf8)

    # Demostración legible: salida textual de Conftest para el caso permitido y el rechazado.
    $txt = New-Object System.Text.StringBuilder
    [void]$txt.AppendLine("Ítem 3.4 — Demostración Conftest (THR-05 / CTL-05)")
    [void]$txt.AppendLine("Commit: $Sha")
    [void]$txt.AppendLine("Fecha (UTC): $($report.executed_at)")
    [void]$txt.AppendLine("Versiones: $version")
    [void]$txt.AppendLine("Imagen: $ConftestImage")
    [void]$txt.AppendLine("")
    [void]$txt.AppendLine("================ CASO PERMITIDO (archivos reales) ================")
    foreach ($e in $Allowed) {
        [void]$txt.AppendLine("`$ conftest test --policy policy --parser $($e.parser) $($e.file)")
        [void]$txt.AppendLine((Invoke-Conftest @("test", "--policy", "policy", "--parser", $e.parser, "--no-color", $e.file)).text.TrimEnd())
        [void]$txt.AppendLine("")
    }
    [void]$txt.AppendLine("================ CASO RECHAZADO (policy/examples) ================")
    foreach ($e in $Insecure) {
        $t = Invoke-Conftest @("test", "--policy", "policy", "--parser", $e.parser, "--no-color", $e.file)
        [void]$txt.AppendLine("`$ conftest test --policy policy --parser $($e.parser) $($e.file)")
        [void]$txt.AppendLine($t.text.TrimEnd())
        [void]$txt.AppendLine("(exit code $($t.exit))")
        [void]$txt.AppendLine("")
    }
    [void]$txt.AppendLine("================ VERIFICACIÓN DEL SCRIPT ================")
    [void]$txt.AppendLine("conftest verify: $($verify.result) ($($verify.passed)/$($verify.tests))")
    [void]$txt.AppendLine("Archivos reales permitidos: $allowedStatus")
    foreach ($r in $insecureResults) { [void]$txt.AppendLine("  $($r.file): $($r.result) ($($r.failures.Count) deny)") }
    [void]$txt.AppendLine("Ejemplos inseguros rechazados como se esperaba: $demoStatus")
    [void]$txt.AppendLine("RESULTADO GLOBAL: $overall")
    [System.IO.File]::WriteAllText((Join-Path $Reports "conftest-insecure-demo-$Sha.txt"), $txt.ToString(), $utf8)

    # Carpeta real de los reportes (relativa al repo si está dentro; si no, ruta completa).
    $shown = if ($Reports.StartsWith($Root)) { $Reports.Substring($Root.Length).TrimStart([char[]]@('\', '/')).Replace('\', '/') } else { $Reports }
    Write-Host "`n=== Resultado: $overall  ->  $shown/conftest-$Sha.json, $shown/conftest-insecure-demo-$Sha.txt" -ForegroundColor Cyan
    if ($overall -ne "APPROVED") { exit 1 }
    exit 0
}
finally {
    Pop-Location
}
