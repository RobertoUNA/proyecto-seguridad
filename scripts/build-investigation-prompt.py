#!/usr/bin/env python3
"""
Ítem 7.4 — Construye el prompt concreto de investigación a partir de la plantilla de
docs/ssdcl/07-prompt-investigacion.md (bloque entre <!-- BEGIN PROMPT --> y <!-- END PROMPT -->),
sustituyendo {{SIGNAL_JSON}} y {{LOGS_JSONL}}. Solo biblioteca estándar.

Antes de construirlo comprueba que la señal es SIGNAL y que cada línea del extracto es un evento
de seguridad del 7.2. Así no entra al prompt contenido que no sea un evento sanitizado.

Uso:
  python scripts/build-investigation-prompt.py reports/security-alert-<sha>.json \
      reports/security-alert-logs-<sha>.jsonl --output reports/security-alert-prompt-<sha>.md
"""
import argparse
import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
TEMPLATE = ROOT / "docs" / "ssdcl" / "07-prompt-investigacion.md"
ALLOWED_KEYS = {"timestamp", "level", "log_type", "event_type", "correlation_id", "method", "route", "status_code",
                "param_names", "suspicious_patterns", "actor_id", "actor_id_scope", "error_class"}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("signal_json")
    ap.add_argument("logs_jsonl")
    ap.add_argument("--output", "-o", required=True)
    args = ap.parse_args()

    text = TEMPLATE.read_text(encoding="utf-8")
    try:
        prompt = text.split("<!-- BEGIN PROMPT -->", 1)[1].split("<!-- END PROMPT -->", 1)[0].strip()
    except IndexError:
        print("No se encontró el bloque BEGIN/END PROMPT en la plantilla", file=sys.stderr)
        return 2

    signal = json.loads(pathlib.Path(args.signal_json).read_text(encoding="utf-8"))
    if signal.get("result") != "SIGNAL":
        print("La señal no es SIGNAL: no hay nada que investigar", file=sys.stderr)
        return 2

    lines = []
    for n, raw in enumerate(pathlib.Path(args.logs_jsonl).read_text(encoding="utf-8").splitlines(), 1):
        if not raw.strip():
            continue
        ev = json.loads(raw)
        extra = set(ev) - ALLOWED_KEYS
        if ev.get("log_type") != "security_event" or extra:
            print(f"línea {n}: no es un evento sanitizado del 7.2 (claves inesperadas: {sorted(extra)})", file=sys.stderr)
            return 2
        lines.append(json.dumps(ev, ensure_ascii=False, separators=(",", ":")))

    prompt = prompt.replace("{{SIGNAL_JSON}}", json.dumps(signal, indent=2, ensure_ascii=False))
    prompt = prompt.replace("{{LOGS_JSONL}}", "\n".join(lines))
    pathlib.Path(args.output).write_text(prompt + "\n", encoding="utf-8", newline="\n")
    print(f"Prompt construido: {args.output} ({len(prompt)} caracteres, {len(lines)} eventos)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
