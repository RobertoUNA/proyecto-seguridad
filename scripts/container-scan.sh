#!/usr/bin/env bash
# =============================================================================
# Ítem 3.3 — Construye las imágenes candidatas y las analiza con Trivy (THR-05 / CTL-05).
# Equivalente a scripts/container-scan.ps1. Uso:
#   bash scripts/container-scan.sh [SHA]        (por defecto: git rev-parse HEAD)
#
#   1. Construye proyecto-seguridad-<backend|frontend>:sha-<SHA> (label OCI revision=<SHA>).
#   2. Trivy config sobre backend/Dockerfile, frontend/Dockerfile y docker-compose.yml
#      (bloquea configuraciones HIGH/CRITICAL fallidas).
#   3. Trivy image sobre cada imagen (HIGH,CRITICAL, --ignore-unfixed, --exit-code 1).
#   4. SBOM CycloneDX de cada imagen.
#   5. reports/container-scan-<SHA>.json (commit, imágenes, IDs, fecha, versión de Trivy, resultado).
# Trivy corre desde su imagen oficial fijada por digest y recibe las imágenes como tar
# (docker save), sin acceso al socket de Docker. Requiere: docker, git, python3.
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TRIVY_VERSION="0.76.2"
TRIVY_IMAGE="aquasec/trivy:${TRIVY_VERSION}@sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb"
CACHE_VOLUME="proyecto-seguridad-trivy-cache"
COMPONENTS=(backend frontend)

SHA="${1:-$(git rev-parse HEAD)}"
if [[ ! "$SHA" =~ ^[0-9a-f]{7,40}$ ]]; then echo "SHA inválido: '$SHA'" >&2; exit 2; fi

# Se prueba que el intérprete realmente ejecute (en Windows `python3` puede ser el alias de la Store).
PYTHON=""
for p in python3 python; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c "import sys" >/dev/null 2>&1; then PYTHON="$p"; break; fi
done
[[ -n "$PYTHON" ]] || { echo "Se requiere python3 para generar el resumen" >&2; exit 2; }

# Git Bash en Windows: evitar que MSYS reescriba rutas de contenedor y usar rutas C:/...
host_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
export MSYS_NO_PATHCONV=1

REPORTS="$ROOT/reports"
mkdir -p "$REPORTS"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
docker volume create "$CACHE_VOLUME" >/dev/null

trivy() { docker run --rm -v "$CACHE_VOLUME:/root/.cache" -v "$(host_path "$WORK"):/work" -v "$(host_path "$REPORTS"):/reports" "$TRIVY_IMAGE" "$@"; }
step() { printf '\n=== %s\n' "$*"; }

FAILED=0
declare -A BUILD IMG_SCAN SBOM

# ------------------------------------------------------------------ 1. build
for c in "${COMPONENTS[@]}"; do
  name="proyecto-seguridad-${c}:sha-${SHA}"
  step "1/4 Construyendo ${name}"
  if docker build --build-arg "COMMIT_SHA=${SHA}" --label "org.opencontainers.image.revision=${SHA}" -t "$name" "$c"; then
    BUILD[$c]=PASS
  else
    BUILD[$c]=FAIL; FAILED=1
  fi
done

# ------------------------------------------------------------------ 2. trivy config
step "2/4 Trivy config (Dockerfiles + docker-compose.yml)"
mkdir -p "$WORK/iac/backend" "$WORK/iac/frontend"
cp backend/Dockerfile "$WORK/iac/backend/Dockerfile"
cp frontend/Dockerfile "$WORK/iac/frontend/Dockerfile"
cp docker-compose.yml "$WORK/iac/docker-compose.yml"
CONFIG_REPORT="trivy-config-${SHA}.json"
CONFIG_STATUS=INCOMPLETE
CONFIG_BLOCKING=-1
if trivy config --quiet --format json --output "/reports/${CONFIG_REPORT}" /work/iac; then
  CONFIG_BLOCKING="$("$PYTHON" - "$(host_path "$REPORTS/$CONFIG_REPORT")" <<'PY'
import json, sys
r = json.load(open(sys.argv[1], encoding="utf-8"))
print(sum(1 for res in r.get("Results") or [] for m in res.get("Misconfigurations") or []
          if m.get("Status") == "FAIL" and m.get("Severity") in ("HIGH", "CRITICAL")))
PY
)"
  trivy convert --format table "/reports/${CONFIG_REPORT}"
  if [[ "$CONFIG_BLOCKING" == "0" ]]; then CONFIG_STATUS=PASS; else CONFIG_STATUS=FAIL; fi
fi
[[ "$CONFIG_STATUS" == PASS ]] || FAILED=1
echo "Trivy config: ${CONFIG_STATUS} (HIGH/CRITICAL fallidas: ${CONFIG_BLOCKING})"

# ------------------------------------------------------------------ 3 y 4. image + SBOM
for c in "${COMPONENTS[@]}"; do
  name="proyecto-seguridad-${c}:sha-${SHA}"
  if [[ "${BUILD[$c]}" != PASS ]] || ! docker save -o "$(host_path "$WORK/${c}.tar")" "$name"; then
    IMG_SCAN[$c]=INCOMPLETE; SBOM[$c]=INCOMPLETE; FAILED=1; continue
  fi

  step "3/4 Trivy image ${name} (HIGH,CRITICAL, --ignore-unfixed)"
  trivy image --input "/work/${c}.tar" --severity HIGH,CRITICAL --ignore-unfixed --exit-code 1 \
    --quiet --format json --output "/reports/trivy-image-${c}-${SHA}.json"
  case $? in 0) IMG_SCAN[$c]=PASS ;; 1) IMG_SCAN[$c]=FAIL ;; *) IMG_SCAN[$c]=INCOMPLETE ;; esac
  [[ -f "$REPORTS/trivy-image-${c}-${SHA}.json" ]] && trivy convert --format table "/reports/trivy-image-${c}-${SHA}.json"
  [[ "${IMG_SCAN[$c]}" == PASS ]] || FAILED=1
  echo "Trivy image ${c}: ${IMG_SCAN[$c]}"

  step "4/4 SBOM CycloneDX ${name}"
  if trivy image --input "/work/${c}.tar" --quiet --format cyclonedx --output "/reports/sbom-${c}-${SHA}.cdx.json"; then
    SBOM[$c]=PASS
  else
    SBOM[$c]=FAIL; FAILED=1
  fi
  rm -f "$WORK/${c}.tar"
done

# ------------------------------------------------------------------ resumen
TRIVY_VERSION_JSON="$(docker run --rm -v "$CACHE_VOLUME:/root/.cache" "$TRIVY_IMAGE" version --format json)"
INSPECT_JSON="$WORK/inspect.json"
docker image inspect "proyecto-seguridad-backend:sha-${SHA}" "proyecto-seguridad-frontend:sha-${SHA}" > "$INSPECT_JSON" 2>/dev/null || echo "[]" > "$INSPECT_JSON"

export SHA TRIVY_IMAGE CONFIG_REPORT CONFIG_STATUS CONFIG_BLOCKING FAILED TRIVY_VERSION_JSON
export BUILD_backend="${BUILD[backend]:-FAIL}" BUILD_frontend="${BUILD[frontend]:-FAIL}"
export SCAN_backend="${IMG_SCAN[backend]:-INCOMPLETE}" SCAN_frontend="${IMG_SCAN[frontend]:-INCOMPLETE}"
export SBOM_backend="${SBOM[backend]:-INCOMPLETE}" SBOM_frontend="${SBOM[frontend]:-INCOMPLETE}"
"$PYTHON" - "$(host_path "$REPORTS")" "$(host_path "$INSPECT_JSON")" <<'PY'
import datetime, json, os, sys
reports, inspect_path = sys.argv[1], sys.argv[2]
sha = os.environ["SHA"]
inspect = {}
for i in json.load(open(inspect_path, encoding="utf-8")):
    for t in i.get("RepoTags") or []:
        inspect[t] = i
ver = json.loads(os.environ["TRIVY_VERSION_JSON"])
images = []
for c in ("backend", "frontend"):
    name = f"proyecto-seguridad-{c}:sha-{sha}"
    i = inspect.get(name, {})
    entry = {
        "component": c, "image": name, "build": os.environ[f"BUILD_{c}"],
        "image_id": i.get("Id"), "repo_digests": i.get("RepoDigests") or [],
        "revision_label": ((i.get("Config") or {}).get("Labels") or {}).get("org.opencontainers.image.revision"),
        "image_scan": os.environ[f"SCAN_{c}"], "image_report": f"reports/trivy-image-{c}-{sha}.json",
        "sbom": os.environ[f"SBOM_{c}"], "sbom_report": f"reports/sbom-{c}-{sha}.cdx.json",
    }
    p = os.path.join(reports, f"trivy-image-{c}-{sha}.json")
    if os.path.exists(p):
        report = json.load(open(p, encoding="utf-8"))
        # Digest de configuración que Trivy registra en el reporte y en el SBOM (aquasecurity:trivy:ImageID).
        entry["config_digest"] = (report.get("Metadata") or {}).get("ImageID")
        vulns = [v for r in report.get("Results") or [] for v in r.get("Vulnerabilities") or []]
        entry["vulnerabilities"] = {"critical": sum(v["Severity"] == "CRITICAL" for v in vulns),
                                    "high": sum(v["Severity"] == "HIGH" for v in vulns)}
    images.append(entry)
summary = {
    "item": "3.3", "controls": ["THR-05", "CTL-05"], "commit": sha,
    "scanned_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "trivy": {"version": ver.get("Version"), "image": os.environ["TRIVY_IMAGE"],
              "vulnerability_db_updated_at": (ver.get("VulnerabilityDB") or {}).get("UpdatedAt")},
    "policy": "Bloquea: vulnerabilidades HIGH/CRITICAL con corrección disponible (--ignore-unfixed) y configuraciones HIGH/CRITICAL fallidas",
    "config_scan": {"targets": ["backend/Dockerfile", "frontend/Dockerfile", "docker-compose.yml"],
                    "report": f"reports/{os.environ['CONFIG_REPORT']}",
                    "blocking_findings": int(os.environ["CONFIG_BLOCKING"]), "result": os.environ["CONFIG_STATUS"]},
    "images": images,
    "result": "FAILED" if os.environ["FAILED"] != "0" else "APPROVED",
}
with open(os.path.join(reports, f"container-scan-{sha}.json"), "w", encoding="utf-8") as f:
    json.dump(summary, f, indent=2, ensure_ascii=False)
print(f"\n=== Resultado: {summary['result']}  ->  reports/container-scan-{sha}.json")
PY

exit "$FAILED"
