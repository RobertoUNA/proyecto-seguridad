#!/usr/bin/env bash
# =============================================================================
# Ítem 3.4 — Verifica policy/container.rego con Conftest (THR-05 / CTL-05).
# Equivalente a scripts/policy-check.ps1. Uso:  bash scripts/policy-check.sh [SHA]
#
#   1. conftest verify                         → pruebas unitarias (policy/container_test.rego)
#   2. conftest test sobre archivos REALES     → deben pasar sin fallos ni advertencias
#   3. conftest test sobre policy/examples/*   → cada ejemplo DEBE ser rechazado (se comprueba
#      en el JSON que haya un deny real; un error de Conftest no cuenta como rechazo)
# Salidas: reports/conftest-<sha>.json y reports/conftest-insecure-demo-<sha>.txt
# Requiere: docker, git, python3. Conftest se ejecuta desde su imagen oficial fijada por digest.
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

CONFTEST_VERSION="v0.71.1"
CONFTEST_IMAGE="openpolicyagent/conftest:${CONFTEST_VERSION}@sha256:0e77cdf7c1fcde035f3c579e4aaa6664ee2a8be5777eaa9af9f520cdd02280c0"

ALLOWED=("dockerfile:backend/Dockerfile" "dockerfile:frontend/Dockerfile" "yaml:docker-compose.yml")
INSECURE=("dockerfile:policy/examples/Dockerfile.insecure" "dockerfile:policy/examples/Dockerfile.insecure-root" "yaml:policy/examples/docker-compose.insecure.yml")

SHA="${1:-$(git rev-parse HEAD)}"
if [[ ! "$SHA" =~ ^[0-9a-f]{7,40}$ ]]; then echo "SHA inválido: '$SHA'" >&2; exit 2; fi

PYTHON=""
for p in python3 python; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c "import sys" >/dev/null 2>&1; then PYTHON="$p"; break; fi
done
[[ -n "$PYTHON" ]] || { echo "Se requiere python3" >&2; exit 2; }

host_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
export MSYS_NO_PATHCONV=1

WORKTREE_CLEAN=true
if [[ -n "$(git status --porcelain -- policy backend/Dockerfile frontend/Dockerfile docker-compose.yml)" ]]; then
  WORKTREE_CLEAN=false
  echo "[AVISO] Hay cambios sin confirmar en los archivos verificados: el reporte no describe exactamente el commit ${SHA}." >&2
fi

REPORTS="$ROOT/reports"
mkdir -p "$REPORTS"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

conftest() { docker run --rm -v "$(host_path "$ROOT"):/project:ro" -w /project "$CONFTEST_IMAGE" "$@"; }

# Cada ejecución JSON se guarda en $WORK para evaluarla después con Python.
echo; echo "=== 1/3 conftest verify (pruebas unitarias de policy/container.rego)"
conftest verify --policy policy --output json --no-color > "$WORK/verify.json" 2>&1
conftest verify --policy policy --no-color | tail -n 1

i=0
for group in ALLOWED INSECURE; do
  declare -n list="$group"
  if [[ "$group" == ALLOWED ]]; then echo; echo "=== 2/3 conftest test sobre archivos REALES (deben pasar)"
  else echo; echo "=== 3/3 conftest test sobre ejemplos INSEGUROS (deben ser rechazados)"; fi
  for e in "${list[@]}"; do
    parser="${e%%:*}"; file="${e#*:}"
    conftest test --policy policy --parser "$parser" --output json --no-color "$file" > "$WORK/$group.$i.json" 2>&1
    printf '%s\t%s\t%s\n' "$group" "$parser" "$file" >> "$WORK/index.tsv"
    conftest test --policy policy --parser "$parser" --no-color "$file"
    echo "(exit code $?)"
    i=$((i + 1))
  done
  unset -n list
done

# Texto legible de la demostración (mismo formato que la versión PowerShell).
VERSION="$(conftest --version | tr '\n' ' ' | sed 's/ *$//; s/ /  /2')"
DEMO="$REPORTS/conftest-insecure-demo-${SHA}.txt"
{
  echo "Ítem 3.4 — Demostración Conftest (THR-05 / CTL-05)"
  echo "Commit: ${SHA}"
  echo "Fecha (UTC): $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Versiones: ${VERSION}"
  echo "Imagen: ${CONFTEST_IMAGE}"
  echo
  echo "================ CASO PERMITIDO (archivos reales) ================"
  for e in "${ALLOWED[@]}"; do
    echo "\$ conftest test --policy policy --parser ${e%%:*} ${e#*:}"
    conftest test --policy policy --parser "${e%%:*}" --no-color "${e#*:}" 2>&1
    echo
  done
  echo "================ CASO RECHAZADO (policy/examples) ================"
  for e in "${INSECURE[@]}"; do
    echo "\$ conftest test --policy policy --parser ${e%%:*} ${e#*:}"
    conftest test --policy policy --parser "${e%%:*}" --no-color "${e#*:}" 2>&1
    echo "(exit code $?)"
    echo
  done
} > "$DEMO"

export SHA WORKTREE_CLEAN CONFTEST_IMAGE VERSION
"$PYTHON" - "$(host_path "$WORK")" "$(host_path "$REPORTS")" "$(host_path "$DEMO")" <<'PY'
import datetime, json, os, sys
work, reports, demo = sys.argv[1:4]

def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            return json.load(f), None
    except Exception:
        with open(path, encoding="utf-8", errors="replace") as f:
            return None, f.read().strip()

v, verr = load(os.path.join(work, "verify.json"))
verify = {"result": "INCOMPLETE", "tests": 0, "passed": 0, "failed": 0}
if v is not None:
    failed = sum(1 for t in v if t.get("failures"))
    verify.update(tests=len(v), failed=failed, passed=len(v) - failed,
                  result="PASS" if failed == 0 and v else "FAIL")
else:
    verify["error"] = verr

groups = {"ALLOWED": [], "INSECURE": []}
with open(os.path.join(work, "index.tsv"), encoding="utf-8") as f:
    for i, line in enumerate(f):
        group, parser, file = line.rstrip("\n").split("\t")
        data, err = load(os.path.join(work, f"{group}.{i}.json"))
        r = {"file": file, "parser": parser, "executed": data is not None, "successes": 0, "failures": [], "warnings": []}
        if data is None:
            r["error"] = err
        else:
            for x in data:
                r["successes"] += x.get("successes", 0)
                r["failures"] += [m["msg"] for m in x.get("failures") or []]
                r["warnings"] += [m["msg"] for m in x.get("warnings") or []]
        if group == "ALLOWED":
            r["result"] = "INCOMPLETE" if not r["executed"] else ("PASS" if not r["failures"] and not r["warnings"] else "FAIL")
        else:
            r["result"] = "INCOMPLETE" if not r["executed"] else ("REJECTED" if r["failures"] else "NOT_REJECTED")
        groups[group].append(r)

def status(items, ok):
    if any(r["result"] == "INCOMPLETE" for r in items): return "INCOMPLETE"
    return "PASS" if all(r["result"] == ok for r in items) else "FAIL"

allowed, demo_status = status(groups["ALLOWED"], "PASS"), status(groups["INSECURE"], "REJECTED")
overall = "APPROVED" if verify["result"] == allowed == demo_status == "PASS" else "FAILED"
report = {
    "item": "3.4", "controls": ["THR-05", "CTL-05"], "commit": os.environ["SHA"],
    "worktree_clean": os.environ["WORKTREE_CLEAN"] == "true",
    "executed_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "conftest": {"version": os.environ["VERSION"], "image": os.environ["CONFTEST_IMAGE"]},
    "policy": "policy/container.rego", "verify": verify,
    "allowed": {"expectation": "Sin fallos ni advertencias", "result": allowed, "files": groups["ALLOWED"]},
    "insecure_demo": {"expectation": "Cada ejemplo debe ser rechazado por al menos un deny", "result": demo_status, "files": groups["INSECURE"]},
    "result": overall,
}
with open(os.path.join(reports, f"conftest-{os.environ['SHA']}.json"), "w", encoding="utf-8") as f:
    json.dump(report, f, indent=2, ensure_ascii=False)
with open(demo, "a", encoding="utf-8") as f:
    f.write("================ VERIFICACIÓN DEL SCRIPT ================\n")
    f.write(f"conftest verify: {verify['result']} ({verify['passed']}/{verify['tests']})\n")
    f.write(f"Archivos reales permitidos: {allowed}\n")
    for r in groups["INSECURE"]:
        f.write(f"  {r['file']}: {r['result']} ({len(r['failures'])} deny)\n")
    f.write(f"Ejemplos inseguros rechazados como se esperaba: {demo_status}\n")
    f.write(f"RESULTADO GLOBAL: {overall}\n")
print(f"\nverify={verify['result']} allowed={allowed} insecure_demo={demo_status}")
print(f"=== Resultado: {overall}  ->  reports/conftest-{os.environ['SHA']}.json")
sys.exit(0 if overall == "APPROVED" else 1)
PY
