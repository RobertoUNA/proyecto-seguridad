#!/usr/bin/env python3
"""
Verificador SAST local compatible con las reglas definidas en .semgrep.yml (Ítem 2.3).
Si el binario `semgrep` está disponible en PATH, delega la ejecución a `semgrep scan --config .semgrep.yml --error`.
En entornos Windows sin WSL/Docker activo, ejecuta las mismas reglas estáticas de .semgrep.yml
sobre backend/src, frontend/src y workers/ para garantizar reproducibilidad local inmediata.
"""

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parents[1]

SCAN_DIRS = [
    ROOT / "backend" / "src",
    ROOT / "frontend" / "src",
    ROOT / "workers",
]

RULES = [
    {
        "id": "ssdcl-ts-raw-sql-interpolation",
        "exts": {".ts", ".tsx", ".js"},
        "severity": "ERROR",
        "cwe": "CWE-89",
        "threat": "THR-01 / CTL-01",
        "message": "Posible inyección SQL: interpolación ${...} dentro de .query/.where/.andWhere/.orWhere.",
        "regex": re.compile(r"\.(?:query|where|andWhere|orWhere)\s*\(\s*`[^`]*\$\{[^}]+\}[^`]*`"),
    },
    {
        "id": "ssdcl-ts-dangerous-eval-or-function",
        "exts": {".ts", ".tsx", ".js"},
        "severity": "ERROR",
        "cwe": "CWE-95",
        "threat": "CTL-01",
        "message": "Ejecución dinámica de código insegura: uso prohibido de eval() o new Function().",
        "regex": re.compile(r"\b(?:eval|new\s+Function)\s*\("),
    },
    {
        "id": "ssdcl-py-requests-without-timeout",
        "exts": {".py"},
        "severity": "ERROR",
        "cwe": "CWE-400",
        "threat": "THR-02 / CTL-02",
        "message": "Llamada requests.get/post sin parámetro timeout explícito.",
        "regex": re.compile(r"\brequests\.(?:get|post)\s*\((?![^)]*timeout\s*=)[^)]*\)"),
    },
    {
        "id": "ssdcl-py-insecure-ssl-verify-false",
        "exts": {".py"},
        "severity": "ERROR",
        "cwe": "CWE-295",
        "threat": "THR-04 / CTL-04",
        "message": "Verificación de certificado TLS desactivada (verify=False).",
        "regex": re.compile(r"\brequests\.(?:get|post|request)\s*\([^)]*verify\s*=\s*False"),
    },
    {
        "id": "ssdcl-py-raw-sql-format-string",
        "exts": {".py"},
        "severity": "ERROR",
        "cwe": "CWE-89",
        "threat": "THR-01 / CTL-01",
        "message": "Posible inyección SQL en Python: f-string dentro de cur.execute().",
        "regex": re.compile(r"\.execute\s*\(\s*f[\"']"),
    },
]


def main() -> int:
    semgrep_bin = shutil.which("semgrep")
    if semgrep_bin:
        print(f"[SAST] Ejecutando Semgrep CE ({semgrep_bin}) con .semgrep.yml...")
        res = subprocess.run(
            [semgrep_bin, "scan", "--config", str(ROOT / ".semgrep.yml"), "--error"],
            cwd=ROOT,
        )
        return res.returncode

    print("[SAST] Analizando código con las reglas de .semgrep.yml (modo nativo multiplataforma)...")
    findings = []
    scanned_files = 0

    for scan_dir in SCAN_DIRS:
        if not scan_dir.exists():
            continue
        for path in scan_dir.rglob("*"):
            if not path.is_file() or path.suffix not in {".ts", ".tsx", ".js", ".py"}:
                continue
            scanned_files += 1
            content = path.read_text(encoding="utf-8", errors="ignore")
            lines = content.splitlines()
            for rule in RULES:
                if path.suffix not in rule["exts"]:
                    continue
                for match in rule["regex"].finditer(content):
                    line_no = content[: match.start()].count("\n") + 1
                    snippet = lines[line_no - 1].strip() if 0 < line_no <= len(lines) else ""
                    findings.append(
                        {
                            "rule_id": rule["id"],
                            "severity": rule["severity"],
                            "cwe": rule["cwe"],
                            "threat": rule["threat"],
                            "file": str(path.relative_to(ROOT)),
                            "line": line_no,
                            "message": rule["message"],
                            "snippet": snippet,
                        }
                    )

    print(f"[SAST] Archivos analizados: {scanned_files} | Reglas activas (.semgrep.yml): {len(RULES)}")
    if findings:
        print(f"\n[SAST] ✗ Se encontraron {len(findings)} hallazgo(s) que bloquean la verificación:\n")
        for f in findings:
            print(f"  - [{f['severity']}] {f['rule_id']} ({f['cwe']} | {f['threat']})")
            print(f"    Archivo: {f['file']}:{f['line']}")
            print(f"    Detalle: {f['message']}")
            print(f"    Código:  {f['snippet']}\n")
        return 1

    print("[SAST] ✓ 0 hallazgos detectados. Código cumple las reglas de .semgrep.yml.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
