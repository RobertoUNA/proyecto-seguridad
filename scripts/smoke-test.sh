#!/usr/bin/env bash
# Health checks y Smoke Tests posteriores al despliegue (Ítems 3.1 y 6.5)
set -euo pipefail

BASE_URL="${1:-http://localhost:3000}"
REPORT_PATH="${2:-reports/smoke-test-report.json}"
mkdir -p "$(dirname "$REPORT_PATH")"

echo "=================================================================="
echo " Ejecutando Health Checks y Smoke Tests contra: ${BASE_URL}"
echo "=================================================================="

FAILED=0

check_status() {
  local name="$1"
  local url="$2"
  local expected="$3"
  local code
  code=$(curl -s -o /tmp/smoke_body.json -w "%{http_code}" "$url" || echo "000")
  if [[ "$code" == "$expected" ]]; then
    echo "  [PASS] ${name} (HTTP ${code})"
  else
    echo "  [FAIL] ${name} (Esperado HTTP ${expected}, recibido HTTP ${code})"
    cat /tmp/smoke_body.json || true
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

cat > "$REPORT_PATH" <<EOF
{
  "base_url": "${BASE_URL}",
  "executed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "total_checks": 8,
  "failed": ${FAILED},
  "status": "${STATUS}"
}
EOF

if [[ "$FAILED" -gt 0 ]]; then
  echo "[RESULTADO] FALLO (${FAILED} comprobaciones fallaron). Se bloquea despliegue / inicia rollback."
  exit 1
fi

echo "[RESULTADO] APROBADO (Las 8 comprobaciones posteriores al despliegue pasaron)."
exit 0
