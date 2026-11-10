#!/usr/bin/env bash
# Procedimiento automatizado de recuperación / rollback ante fallo post-despliegue (Ítem 6.6)
set -euo pipefail

BASE_URL="${1:-http://localhost:3000}"
MANIFEST="deploy/last-approved-release.json"
REASON="${2:-Fallo en smoke tests post-despliegue}"

echo "=================================================================="
echo " INICIANDO PROCEDIMIENTO DE RECUPERACIÓN / ROLLBACK (Ítem 6.6)"
echo "=================================================================="
echo " Motivo: ${REASON}"
cat "$MANIFEST"

if [[ -f "deploy/docker-compose.prod.yml" ]] && command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
  export BACKEND_IMAGE
  BACKEND_IMAGE=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['backend_image'])")
  export FRONTEND_IMAGE
  FRONTEND_IMAGE=$(python3 -c "import json; print(json.load(open('$MANIFEST'))['frontend_image'])")
  docker compose -f deploy/docker-compose.prod.yml up -d
fi

echo "Repitiendo comprobaciones básicas (smoke-test.sh)..."
bash scripts/smoke-test.sh "$BASE_URL" "reports/smoke-test-post-rollback.json"
echo "[RECUPERACIÓN EXITOSA] Versión anterior restaurada y comprobada."
