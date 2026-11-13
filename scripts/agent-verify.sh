#!/usr/bin/env bash
# =============================================================================
# Ítem 2.4 — Wrapper de verificación del agente (hook "Stop" de Claude Code).
# Equivalente a scripts/agent-verify.ps1. Uso:
#   bash scripts/agent-verify.sh            verificación estándar
#   bash scripts/agent-verify.sh --full     + Trivy/SBOM (scripts/container-scan.sh)
#   bash scripts/agent-verify.sh --hook     modo hook Stop (lee el JSON de stdin)
#
# Pasos (PASS / FAIL / SKIPPED / INCOMPLETE), en orden:
#   frontend:lint, frontend:build, backend:lint, backend:build, backend:test,
#   security:sast-check (scripts/sast-check.py), security:semgrep (semgrep/semgrep:1.185.0),
#   security:gitleaks (zricethezav/gitleaks:v8.21.2, --redact), containers:policy
#   (scripts/policy-check.sh), containers:trivy (solo --full).
# INCOMPLETE = herramienta no ejecutable -> cuenta como fallo. SKIPPED nunca cuenta como PASS.
# Hook: PASS -> exit 0 | FAIL e intento < 3 -> exit 2 (resumen en stderr) |
#       intento = 3 -> reports/agent-verify-blocked-<ts>.json + "BLOQUEO..." + exit 0.
# Requiere: git, python3 (resúmenes JSON), docker (análisis), npm (builds).
# =============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

FULL=0; HOOK=0
for a in "$@"; do case "$a" in --full) FULL=1 ;; --hook) HOOK=1 ;; esac; done

MAX_ATTEMPTS=3
SEMGREP_IMAGE="semgrep/semgrep:1.185.0@sha256:67518c174185a2043fdbed16c70631b79209499b3671178e7194379b48295a0d"
GITLEAKS_IMAGE="zricethezav/gitleaks:v8.21.2@sha256:0e99e8821643ea5b235718642b93bb32486af9c8162c8b8731f7cbdc951a7f46"
COUNTER_FILE="$ROOT/.claude/verify-attempts"
REPORTS="$ROOT/reports"
WATCHED=(backend frontend policy scripts workers docker-compose.yml .semgrep.yml .gitleaks.toml .github)
OWN_OUTPUTS='^(reports/agent-verify-|\.claude/verify-attempts)'
export NO_COLOR=1 FORCE_COLOR=0 PYTHONIOENCODING=utf-8

PYTHON=""
for p in python3 python; do
  if command -v "$p" >/dev/null 2>&1 && "$p" -c "import sys" >/dev/null 2>&1; then PYTHON="$p"; break; fi
done
host_path() { if command -v cygpath >/dev/null 2>&1; then cygpath -m "$1"; else printf '%s' "$1"; fi; }
export MSYS_NO_PATHCONV=1

HOOK_INPUT=""
if [[ "$HOOK" == 1 ]]; then HOOK_INPUT="$(cat || true)"; fi

# En modo hook el progreso va a un log; stdout queda libre para el JSON de Claude Code.
say() { if [[ "$HOOK" == 1 ]]; then printf '%s\n' "$*" >> "$WORK/progress.log"; else printf '%s\n' "$*"; fi; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$REPORTS" "$WORK/steps"
: > "$WORK/steps.tsv"

# record ID STATUS COMMAND NOTE SECONDS [LOGFILE]
record() {
  local id="$1" st="$2" cmd="$3" note="$4" secs="$5" log="${6:-}"
  if [[ -n "$log" ]]; then cp "$log" "$WORK/steps/$id.log"; fi
  printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$st" "$cmd" "$note" "$secs" >> "$WORK/steps.tsv"
  say "$(printf '  [%-10s] %-20s %s' "$st" "$id" "${note:-$cmd}")"
}
msg_log() { printf '%s\n' "$*" > "$WORK/msg.log"; echo "$WORK/msg.log"; }

npm_step() {
  local id="$1" dir="$2" script="$3" cmd="cd $2 && npm run $3"
  if ! command -v npm >/dev/null 2>&1; then record "$id" INCOMPLETE "$cmd" "" 0 "$(msg_log "npm no está instalado o no está en PATH")"; return; fi
  if ! grep -q "\"$script\"[[:space:]]*:" "$dir/package.json"; then record "$id" SKIPPED "$cmd" "el script '$script' no existe en $dir/package.json" 0; return; fi
  if [[ ! -d "$dir/node_modules" ]]; then record "$id" INCOMPLETE "$cmd" "" 0 "$(msg_log "$dir/node_modules no existe: ejecute 'npm ci' en $dir")"; return; fi
  local t0=$SECONDS
  (cd "$dir" && npm run "$script") > "$WORK/out.log" 2>&1
  local rc=$?
  record "$id" "$([[ $rc == 0 ]] && echo PASS || echo FAIL)" "$cmd" "" $((SECONDS - t0)) "$WORK/out.log"
}

# Tar con los archivos versionables (git ls-files -co --exclude-standard) para entregarlos a
# Semgrep/Gitleaks en Docker sin bind-mount del repo (muy lento en Windows).
source_tar() {
  local tarfile="$1"; shift
  git -c core.quotepath=false ls-files -co --exclude-standard -- "$@" |
    while IFS= read -r f; do [[ -f "$f" ]] && printf '%s\n' "$f"; done > "$tarfile.list"
  tar -cf "$tarfile" -T "$tarfile.list" 2>"$WORK/tar.err"
}

verify() {
  SHA="$(git rev-parse HEAD)"
  git -c core.quotepath=false status --porcelain --untracked-files=all | cut -c4- | sed 's/^"//; s/"$//' |
    grep -Ev "$OWN_OUTPUTS" > "$WORK/changed.txt" || true
  CODE_CHANGED=0
  while IFS= read -r f; do
    for w in "${WATCHED[@]}"; do [[ "$f" == "$w" || "$f" == "$w/"* ]] && CODE_CHANGED=1; done
  done < "$WORK/changed.txt"

  if [[ ! -s "$WORK/changed.txt" ]]; then
    say "agent-verify: sin cambios que verificar (git status limpio) -> PASS"
    RESULT=PASS; NO_CHANGES=1; return
  fi
  NO_CHANGES=0

  local docker_ok=0
  command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1 && docker_ok=1
  local nodocker="Docker no está disponible (instalado y con el daemon en ejecución): el análisis no se ejecutó"
  say "agent-verify ($([[ $FULL == 1 ]] && echo full || echo standard)) commit ${SHA:0:7} | archivos cambiados: $(wc -l < "$WORK/changed.txt" | tr -d ' ')"

  if [[ "$CODE_CHANGED" == 1 ]]; then
    npm_step frontend:lint frontend lint
    npm_step frontend:build frontend build
    npm_step backend:lint backend lint
    npm_step backend:build backend build
    npm_step backend:test backend test

    if [[ -z "$PYTHON" ]]; then record security:sast-check INCOMPLETE "python scripts/sast-check.py" "" 0 "$(msg_log "Python no está disponible")"
    else
      local t0=$SECONDS; "$PYTHON" scripts/sast-check.py > "$WORK/out.log" 2>&1; local rc=$?
      record security:sast-check "$([[ $rc == 0 ]] && echo PASS || echo FAIL)" "python scripts/sast-check.py" "" $((SECONDS - t0)) "$WORK/out.log"
    fi

    local cmd="semgrep scan --config .semgrep.yml --error backend/src frontend/src workers"
    if [[ "$docker_ok" != 1 ]]; then record security:semgrep INCOMPLETE "$cmd" "" 0 "$(msg_log "$nodocker")"
    elif ! source_tar "$WORK/semgrep.tar" backend/src frontend/src workers .semgrep.yml; then
      record security:semgrep INCOMPLETE "$cmd" "" 0 "$WORK/tar.err"
    else
      local t0=$SECONDS
      docker run --rm -v "$(host_path "$WORK"):/in:ro" --entrypoint sh "$SEMGREP_IMAGE" -c \
        'mkdir -p /w && tar -xf /in/semgrep.tar -C /w && cd /w && semgrep scan --config .semgrep.yml --error --metrics=off --disable-version-check --quiet --json --output /tmp/out.json backend/src frontend/src workers >/dev/null 2>/tmp/err; rc=$?; cat /tmp/out.json 2>/dev/null || cat /tmp/err; exit $rc' \
        > "$WORK/semgrep.json" 2>"$WORK/semgrep.err"   # stderr aparte: el progreso de un pull no invalida el JSON
      local rc=$? st
      case $rc in 0) st=PASS ;; 1) st=FAIL ;; *) st=INCOMPLETE ;; esac
      "$PYTHON" - "$(host_path "$WORK/semgrep.json")" > "$WORK/out.log" 2>/dev/null <<'PY' || { st=INCOMPLETE; cat "$WORK/semgrep.json" "$WORK/semgrep.err" >> "$WORK/out.log"; }
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
for r in d.get("results", []):
    print(f"error: {r['check_id']} en {r['path']}:{r['start']['line']} — {r['extra'].get('message', '')}")
for e in d.get("errors", []):
    print(f"error de Semgrep: {e.get('message')}")
sys.exit(3 if d.get("errors") else 0)
PY
      record security:semgrep "$st" "$cmd" "" $((SECONDS - t0)) "$WORK/out.log"
    fi
  else
    say "  (sin cambios en código/configuración: solo se ejecuta Gitleaks)"
  fi

  # Gitleaks ante cualquier cambio (también si solo cambió docs/).
  local cmd="gitleaks dir --config .gitleaks.toml --redact"
  if [[ "$docker_ok" != 1 ]]; then record security:gitleaks INCOMPLETE "$cmd" "" 0 "$(msg_log "$nodocker")"
  elif ! source_tar "$WORK/repo.tar" .; then record security:gitleaks INCOMPLETE "$cmd" "" 0 "$WORK/tar.err"
  else
    local t0=$SECONDS
    docker run --rm -v "$(host_path "$WORK"):/in:ro" --entrypoint sh "$GITLEAKS_IMAGE" -c \
      'mkdir -p /w && tar -xf /in/repo.tar -C /w && cd /w && gitleaks dir . --config .gitleaks.toml --redact --no-banner --log-level error --report-format json --report-path /tmp/r.json --exit-code 1 >/tmp/log 2>&1; rc=$?; if [ -f /tmp/r.json ]; then cat /tmp/r.json; else cat /tmp/log; fi; exit $rc' \
      > "$WORK/gitleaks.json" 2>"$WORK/gitleaks.err"   # stderr aparte: el progreso de un pull no invalida el JSON
    local rc=$? st
    case $rc in 0) st=PASS ;; 1) st=FAIL ;; *) st=INCOMPLETE ;; esac
    if "$PYTHON" - "$(host_path "$WORK/gitleaks.json")" > "$WORK/out.log" 2>/dev/null <<'PY'
import json, sys
for f in json.load(open(sys.argv[1], encoding="utf-8")):
    print(f"leak: regla {f['RuleID']} en {f['File']}:{f['StartLine']} (valor enmascarado: {f.get('Secret')})")
PY
    then cp "$WORK/gitleaks.json" "$REPORTS/agent-verify-gitleaks-last.json"   # reporte enmascarado (--redact)
    else [[ "$st" == FAIL ]] && st=INCOMPLETE; cat "$WORK/gitleaks.json" "$WORK/gitleaks.err" > "$WORK/out.log"; fi
    record security:gitleaks "$st" "$cmd" "" $((SECONDS - t0)) "$WORK/out.log"
  fi

  if [[ "$CODE_CHANGED" == 1 ]]; then
    local cmd="scripts/policy-check.sh"
    if [[ "$docker_ok" != 1 ]]; then record containers:policy INCOMPLETE "$cmd" "" 0 "$(msg_log "$nodocker")"
    else
      local t0=$SECONDS; mkdir -p "$WORK/policy"
      REPORT_DIR="$WORK/policy" bash scripts/policy-check.sh > "$WORK/out.log" 2>&1; local rc=$? st
      if ! ls "$WORK/policy"/conftest-*.json >/dev/null 2>&1; then st=INCOMPLETE; elif [[ $rc == 0 ]]; then st=PASS; else st=FAIL; fi
      record containers:policy "$st" "$cmd" "" $((SECONDS - t0)) "$WORK/out.log"
    fi

    local cmd="scripts/container-scan.sh"
    if [[ "$FULL" != 1 ]]; then record containers:trivy SKIPPED "$cmd" "solo con --full (tarda varios minutos)" 0
    elif [[ "$docker_ok" != 1 ]]; then record containers:trivy INCOMPLETE "$cmd" "" 0 "$(msg_log "$nodocker")"
    else
      local t0=$SECONDS; mkdir -p "$WORK/trivy"
      REPORT_DIR="$WORK/trivy" bash scripts/container-scan.sh > "$WORK/out.log" 2>&1; local rc=$? st
      if ! ls "$WORK/trivy"/container-scan-*.json >/dev/null 2>&1; then st=INCOMPLETE; elif [[ $rc == 0 ]]; then st=PASS; else st=FAIL; fi
      record containers:trivy "$st" "$cmd" "" $((SECONDS - t0)) "$WORK/out.log"
    fi
  fi

  RESULT=PASS
  awk -F'\t' '$2=="FAIL"||$2=="INCOMPLETE"{f=1} END{exit f?0:1}' "$WORK/steps.tsv" && RESULT=FAIL
}

# Escribe reports/agent-verify-last.json y el resumen corto (stdout del bloque python).
summarize() {
  local header="$1"
  "$PYTHON" - "$(host_path "$WORK")" "$(host_path "$REPORTS")" "$header" "$SHA" "$FULL" "$RESULT" <<'PY'
import datetime, json, os, re, sys
work, reports, header, sha, full, result = sys.argv[1:7]
ansi = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")
token = re.compile(r"(gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{5,}|sk-[A-Za-z0-9]{20,})")
errline = re.compile(r"(?i)error|fail|✗|\bx\b|denied|deny|leak|finding|hallazgo|not found|no se|cannot|missing")
fileref = re.compile(r"((?:[\w.-]+/)*[\w.-]+\.(?:tsx?|jsx?|py|rego|ya?ml|json|toml|md|sh|ps1))(?::(\d+))?")

def protect(line):
    line = ansi.sub("", line)
    if re.match(r"^\s*C[oó]digo:", line):
        return "    Código:  [omitido por agent-verify]"
    return token.sub("[REDACTED]", line)

steps = []
for row in open(os.path.join(work, "steps.tsv"), encoding="utf-8"):
    sid, st, cmd, note, secs = row.rstrip("\n").split("\t")
    s = {"id": sid, "status": st, "command": cmd, "seconds": int(secs)}
    if note: s["note"] = note
    if st in ("FAIL", "INCOMPLETE"):
        p = os.path.join(work, "steps", sid + ".log")
        lines = [protect(l.rstrip()) for l in open(p, encoding="utf-8", errors="replace")] if os.path.exists(p) else []
        lines = [l for l in lines if l.strip()]
        err = [l for l in lines if errline.search(l)]
        s["excerpt"] = (err or lines[-12:])[:12]
        files = []
        for l in s["excerpt"]:
            for m in fileref.finditer(l):
                v = m.group(0)
                if not v.startswith(("package", "tsconfig")) and v not in files: files.append(v)
        s["files"] = files[:5]
    steps.append(s)

changed = [l.strip() for l in open(os.path.join(work, "changed.txt"), encoding="utf-8") if l.strip()]
summary = {"item": "2.4", "commit": sha,
           "executed_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
           "mode": "full" if full == "1" else "standard", "changed_files": changed[:50],
           "steps": steps, "result": result,
           "skipped": [s["id"] for s in steps if s["status"] == "SKIPPED"]}
json.dump(summary, open(os.path.join(reports, "agent-verify-last.json"), "w", encoding="utf-8"), indent=2, ensure_ascii=False)
json.dump(summary, open(os.path.join(work, "summary.json"), "w", encoding="utf-8"), ensure_ascii=False)

bad = [s for s in steps if s["status"] in ("FAIL", "INCOMPLETE")]
out = [f"{header} agent-verify: {result} (commit {sha[:7]}, {len(bad)} de {len(steps)} pasos con problemas)"]
for b in bad:
    files = (" | archivos: " + ", ".join(b["files"])) if b.get("files") else ""
    out.append(f"- {b['id']} [{b['status']}] {b['command']}{files}")
    out += ["    " + l for l in b["excerpt"][:6]]
if summary["skipped"]:
    out.append("Omitidos (no cuentan como aprobados): " + ", ".join(summary["skipped"]))
out.append("Detalle: reports/agent-verify-last.json")
print("\n".join(out))
PY
}

[[ -n "$PYTHON" ]] || { echo "agent-verify: INCOMPLETE — se requiere python3 para los resúmenes" >&2; [[ "$HOOK" == 1 ]] && exit 2; exit 1; }

# ----------------------------------------------------------------------------- modo normal
if [[ "$HOOK" != 1 ]]; then
  verify
  if [[ "$RESULT" == PASS ]]; then
    if [[ "$NO_CHANGES" == 1 ]]; then echo "[PASS] sin cambios que verificar"; exit 0; fi
    summarize "[PASS]" >/dev/null
    echo; echo "[PASS] agent-verify: todas las verificaciones aprobaron. Omitidos: $(awk -F'\t' '$2=="SKIPPED"{printf "%s%s", s, $1; s=", "}' "$WORK/steps.tsv")"
    exit 0
  fi
  echo; summarize "[FAIL]"
  exit 1
fi

# ----------------------------------------------------------------------------- modo hook (Stop)
STOP_ACTIVE="$(printf '%s' "$HOOK_INPUT" | "$PYTHON" -c 'import json,sys
try: print("true" if json.load(sys.stdin).get("stop_hook_active") else "false")
except Exception: print("false")')"
mkdir -p "$(dirname "$COUNTER_FILE")"
# stop_hook_active = false: tarea nueva (no es una continuación provocada por este hook).
[[ "$STOP_ACTIVE" == true ]] || rm -f "$COUNTER_FILE"

verify
HISTORY="$REPORTS/agent-verify-hook-history.jsonl"
now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

if [[ "$RESULT" == PASS ]]; then
  rm -f "$COUNTER_FILE"
  if [[ "$NO_CHANGES" != 1 ]]; then
    summarize "[PASS]" >/dev/null
    printf '{"at":"%s","commit":"%s","stop_hook_active":%s,"attempt":0,"result":"PASS","failed":[]}\n' "$(now)" "$SHA" "$STOP_ACTIVE" >> "$HISTORY"
  fi
  exit 0
fi

PREV=0; [[ -f "$COUNTER_FILE" ]] && PREV="$(tr -dc '0-9' < "$COUNTER_FILE")"; ATTEMPT=$(( ${PREV:-0} + 1 ))
printf '%s' "$ATTEMPT" > "$COUNTER_FILE"
SUMMARY_TEXT="$(summarize "[INTENTO $ATTEMPT de $MAX_ATTEMPTS]")"
FAILED="$(awk -F'\t' '$2=="FAIL"||$2=="INCOMPLETE"{printf "%s\"%s:%s\"", s, $1, $2; s=","}' "$WORK/steps.tsv")"
printf '{"at":"%s","commit":"%s","stop_hook_active":%s,"attempt":%s,"result":"FAIL","failed":[%s]}\n' "$(now)" "$SHA" "$STOP_ACTIVE" "$ATTEMPT" "$FAILED" >> "$HISTORY"

if (( ATTEMPT >= MAX_ATTEMPTS )); then
  TS="$(date -u +%Y%m%dT%H%M%SZ)"
  BLOCKED="reports/agent-verify-blocked-$TS.json"
  MSG="BLOQUEO: requiere intervención humana. agent-verify falló en $ATTEMPT de $MAX_ATTEMPTS intentos ($(echo "$FAILED" | tr -d '"')). Evidencia: $BLOCKED"
  "$PYTHON" - "$(host_path "$WORK/summary.json")" "$(host_path "$ROOT/$BLOCKED")" "$ATTEMPT" "$MAX_ATTEMPTS" <<'PY'
import json, sys
s = json.load(open(sys.argv[1], encoding="utf-8"))
json.dump({"item": "2.4", "status": "BLOCKED", "message": "BLOQUEO: requiere intervención humana",
           "attempts": int(sys.argv[3]), "max_attempts": int(sys.argv[4]), "commit": s["commit"], "blocked_at": s["executed_at"],
           "failed_steps": [x for x in s["steps"] if x["status"] in ("FAIL", "INCOMPLETE")],
           "next_steps": "Revisar los pasos fallidos. Tras corregir (o decidir una excepción con revisión de otro integrante), borrar .claude/verify-attempts o iniciar una tarea nueva."},
          open(sys.argv[2], "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PY
  echo "$MSG" >&2
  # exit 0: se permite detenerse (sin ciclo infinito); el mensaje se muestra al usuario.
  "$PYTHON" -c 'import json,sys; print(json.dumps({"systemMessage": sys.argv[1]}, ensure_ascii=False))' "$MSG"
  exit 0
fi

{ echo "$SUMMARY_TEXT"
  echo "Corrija los fallos anteriores. No modifique reglas de seguridad (.semgrep.yml, .gitleaks.toml, policy/) ni este script para que pasen; si no puede corregirlo, explíquelo y deténgase."; } >&2
exit 2
