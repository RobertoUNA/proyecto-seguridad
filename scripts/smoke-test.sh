#!/usr/bin/env bash
# Health checks y Smoke Tests posteriores al despliegue (Ítems 3.1 y 6.5)
set -euo pipefail

BASE_URL="${1:-http://localhost:3000}"
if [[ -n "${2:-}" ]]; then
  REPORT_PATH="$2"
else
  SHORT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo "local")
  STAMP=$(date -u +"%Y%m%dT%H%M%SZ")
  REPORT_PATH="reports/smoke-test-${SHORT_SHA}-${STAMP}.json"
fi
mkdir -p "$(dirname "$REPORT_PATH")"

echo "=================================================================="
echo " Ejecutando Health Checks y Smoke Tests contra: ${BASE_URL}"
echo "=================================================================="

FAILED=0
HEALTH_COMMIT_SHA=""
HEALTH_VERSION=""
TARGET_COMMIT_SHA="${COMMIT_SHA:-$(git rev-parse --short HEAD 2>/dev/null || echo 'local')}"
DEPLOYED_IMAGE_DIGEST="${DEPLOYED_IMAGE_DIGEST:-no-aplica (ejecucion desde codigo fuente sin imagen por digest)}"
SMOKE_BODY_FILE="$(dirname "$REPORT_PATH")/.smoke_body_$$.tmp"
trap 'rm -f "$SMOKE_BODY_FILE"' EXIT

PYTHON_BIN=""
if command -v python3 >/dev/null 2>&1 && python3 -c "import json" >/dev/null 2>&1; then
  PYTHON_BIN="python3"
elif command -v python >/dev/null 2>&1 && python -c "import json" >/dev/null 2>&1; then
  PYTHON_BIN="python"
fi

check_status() {
  local name="$1"
  local url="$2"
  local expected="$3"
  local code
  code=$(curl -s -o "$SMOKE_BODY_FILE" -w "%{http_code}" "$url" || echo "000")
  if [[ "$code" == "$expected" ]]; then
    echo "  [PASS] ${name} (HTTP ${code})"
    if [[ "$name" == "1. Health Check (/api/health)" && "$code" == "200" ]]; then
      if [[ -n "$PYTHON_BIN" ]]; then
        HEALTH_COMMIT_SHA=$("$PYTHON_BIN" -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); print(d.get("commit_sha") or "")' "$SMOKE_BODY_FILE" 2>/dev/null || echo "")
        HEALTH_VERSION=$("$PYTHON_BIN" -c 'import json,sys; d=json.load(open(sys.argv[1], encoding="utf-8")); print(d.get("version") or "")' "$SMOKE_BODY_FILE" 2>/dev/null || echo "")
      elif command -v jq >/dev/null 2>&1; then
        HEALTH_COMMIT_SHA=$(jq -r '.commit_sha // empty' "$SMOKE_BODY_FILE" 2>/dev/null || echo "")
        HEALTH_VERSION=$(jq -r '.version // empty' "$SMOKE_BODY_FILE" 2>/dev/null || echo "")
      fi
    fi
  else
    echo "  [FAIL] ${name} (Esperado HTTP ${expected}, recibido HTTP ${code})"
    cat "$SMOKE_BODY_FILE" 2>/dev/null || true
    FAILED=$((FAILED + 1))
  fi
}

check_status "1. Health Check (/api/health)" "${BASE_URL}/api/health" "200"
check_status "2. SNIT Cantones (/api/cantones)" "${BASE_URL}/api/cantones" "200"
check_status "3. OIJ Tipos de Delito (/api/delitos/tipos)" "${BASE_URL}/api/delitos/tipos" "200"
check_status "4. COSEVI Tipos de Accidente (/api/accidentes/tipos)" "${BASE_URL}/api/accidentes/tipos" "200"
check_status "5. OSM Infraestructura (/api/infraestructura/por-canton)" "${BASE_URL}/api/infraestructura/por-canton" "200"
check_status "6. Cruce 4 Fuentes (/api/cantones/1001/panorama)" "${BASE_URL}/api/cantones/1001/panorama" "200"
check_status "7. Rechazo Cantón Inexistente (404 esperado)" "${BASE_URL}/api/cantones/999999/panorama" "404"
check_status "8. Rechazo Filtro Fecha Inválida (400 esperado)" "${BASE_URL}/api/delitos?desde=fecha-invalida" "400"

STATUS="APPROVED"
if [[ "$FAILED" -gt 0 ]]; then
  STATUS="FAILED"
fi
PASSED=$((8 - FAILED))
VERIFIED_COMMIT_SHA="${HEALTH_COMMIT_SHA:-$TARGET_COMMIT_SHA}"
EXECUTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ -n "$PYTHON_BIN" ]]; then
  "$PYTHON_BIN" - "$REPORT_PATH" "$BASE_URL" "$EXECUTED_AT" "$VERIFIED_COMMIT_SHA" "$HEALTH_COMMIT_SHA" "$HEALTH_VERSION" "$DEPLOYED_IMAGE_DIGEST" "$PASSED" "$FAILED" "$STATUS" <<'PYEOF'
import json, sys
_, out_path, base_url, executed_at, commit_sha, health_sha, app_ver, digest, passed, failed, status = sys.argv
payload = {
    "base_url": base_url,
    "executed_at": executed_at,
    "commit_sha": commit_sha,
    "health_commit_sha": health_sha or None,
    "app_version": app_ver or None,
    "image_digest": digest,
    "total_checks": 8,
    "passed": int(passed),
    "failed": int(failed),
    "status": status,
}
with open(out_path, "w", encoding="utf-8") as fh:
    json.dump(payload, fh, indent=2, ensure_ascii=False)
    fh.write("\n")
PYEOF
else
  cat > "$REPORT_PATH" <<EOF
{
  "base_url": "${BASE_URL}",
  "executed_at": "${EXECUTED_AT}",
  "commit_sha": "${VERIFIED_COMMIT_SHA}",
  "health_commit_sha": "${HEALTH_COMMIT_SHA}",
  "app_version": "${HEALTH_VERSION}",
  "image_digest": "${DEPLOYED_IMAGE_DIGEST}",
  "total_checks": 8,
  "passed": ${PASSED},
  "failed": ${FAILED},
  "status": "${STATUS}"
}
EOF
fi

if [[ "$FAILED" -gt 0 ]]; then
  echo "[RESULTADO] FALLO (${FAILED} comprobaciones fallaron). Se bloquea despliegue / inicia rollback."
  exit 1
fi

echo "[RESULTADO] APROBADO (Las 8 comprobaciones posteriores al despliegue pasaron)."
exit 0
