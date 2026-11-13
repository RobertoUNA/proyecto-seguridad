#!/usr/bin/env python3
"""
Ítem 7.2 (THR-06 / CTL-06) — Verifica que los eventos de seguridad NO exponen datos sensibles.

Lee un archivo .jsonl (una línea JSON por evento, salida de `docker compose logs backend`) y FALLA si:
  * alguna IP del cliente (--client-ip) aparece en claro, o hay cualquier dirección IPv4/IPv6 en los eventos;
  * aparece algún valor enviado en parámetros o cabeceras (--forbidden-value);
  * aparecen claves o valores de cabeceras Authorization / Cookie (o "Bearer ...");
  * un evento no tiene los campos obligatorios o tienen formato inválido
    (correlation_id UUID, actor_id hex de 16, route sin query string, param_names sin '=');
  * no hay ningún evento con el patrón esperado (--expect-pattern, por defecto sql_injection).

Solo biblioteca estándar. Uso:
  python scripts/verify-security-logs.py reports/security-events-sample-<sha>.jsonl \
      --client-ip 172.19.0.1 --forbidden-value "' OR 1=1--" --forbidden-value "Bearer ..." \
      [--expect-pattern sql_injection] [--expect-event not_found] [--output reports/verify-....txt]
"""
import argparse
import ipaddress
import json
import re
import sys

REQUIRED = ["timestamp", "level", "log_type", "event_type", "correlation_id", "method", "route",
            "status_code", "param_names", "suspicious_patterns", "actor_id"]
EVENT_TYPES = {"validation_rejected", "not_found", "abuse_suspected", "server_error", "access_denied"}
UUID_RE = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$")
IPV4_RE = re.compile(r"(?<![\d.])(?:\d{1,3}\.){3}\d{1,3}(?![\d.])")
IPV6_RE = re.compile(r"(?<![0-9a-fA-F:])(?:[0-9a-fA-F]{1,4}:){2,7}[0-9a-fA-F]{0,4}(?![0-9a-fA-F:])")
SENSITIVE_KEYS = re.compile(r'"(authorization|cookie|set-cookie|password|token|headers?)"\s*:', re.I)
SENSITIVE_VALUES = re.compile(r"\bbearer\s+\S+|\bbasic\s+[A-Za-z0-9+/=]{8,}", re.I)


def looks_like_ip(s: str) -> bool:
    try:
        ipaddress.ip_address(s)
        return True
    except ValueError:
        return False


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("logfile")
    ap.add_argument("--client-ip", action="append", default=[], help="IP real del cliente que no debe aparecer")
    ap.add_argument("--forbidden-value", action="append", default=[], help="Valor enviado que no debe aparecer")
    ap.add_argument("--expect-pattern", action="append", default=None, help="Patrón que debe aparecer en suspicious_patterns")
    ap.add_argument("--expect-event", action="append", default=[], help="event_type que debe aparecer al menos una vez")
    ap.add_argument("--output", help="Guardar también el resultado en este archivo")
    args = ap.parse_args()
    expect_patterns = args.expect_pattern if args.expect_pattern is not None else ["sql_injection"]

    errors, events = [], []
    with open(args.logfile, encoding="utf-8") as f:
        raw_lines = [l.rstrip("\n") for l in f if l.strip()]

    for n, line in enumerate(raw_lines, 1):
        try:
            ev = json.loads(line)
        except json.JSONDecodeError:
            errors.append(f"línea {n}: no es JSON válido")
            continue
        events.append(ev)

        # 1. Campos y formato
        missing = [k for k in REQUIRED if k not in ev]
        if missing:
            errors.append(f"línea {n}: faltan campos {missing}")
        if ev.get("log_type") != "security_event":
            errors.append(f"línea {n}: log_type distinto de security_event")
        if ev.get("event_type") not in EVENT_TYPES:
            errors.append(f"línea {n}: event_type desconocido {ev.get('event_type')!r}")
        if not UUID_RE.match(str(ev.get("correlation_id", ""))):
            errors.append(f"línea {n}: correlation_id no es un UUID")
        if not re.fullmatch(r"[0-9a-f]{16}", str(ev.get("actor_id", ""))):
            errors.append(f"línea {n}: actor_id no es un hash hex de 16")
        if "?" in str(ev.get("route", "")):
            errors.append(f"línea {n}: route contiene query string")
        for p in ev.get("param_names", []):
            if "=" in p or len(p) > 64:
                errors.append(f"línea {n}: param_names contiene algo que no es un nombre")

        # 2. IPs en claro (IP del cliente o cualquier dirección)
        for ip in args.client_ip:
            if ip and ip in line:
                errors.append(f"línea {n}: aparece en claro una IP del cliente")
        for m in IPV4_RE.findall(line) + IPV6_RE.findall(line):
            if looks_like_ip(m):
                errors.append(f"línea {n}: aparece una dirección IP en claro")

        # 3. Valores enviados por el cliente
        for v in args.forbidden_value:
            if v and (v in line or json.dumps(v)[1:-1] in line):
                errors.append(f"línea {n}: aparece un valor enviado por el cliente ({len(v)} caracteres; no se muestra)")

        # 4. Cabeceras sensibles
        if SENSITIVE_KEYS.search(line):
            errors.append(f"línea {n}: contiene una clave sensible (Authorization/Cookie/token/headers)")
        if SENSITIVE_VALUES.search(line):
            errors.append(f"línea {n}: contiene un valor con forma de credencial (Bearer/Basic)")

    # 5. Cobertura esperada
    if not events:
        errors.append("el archivo no contiene eventos de seguridad")
    for p in expect_patterns:
        if not any(p in ev.get("suspicious_patterns", []) for ev in events):
            errors.append(f"ningún evento quedó marcado con suspicious_patterns={p}")
    for t in args.expect_event:
        if not any(ev.get("event_type") == t for ev in events):
            errors.append(f"no hay ningún evento de tipo {t}")

    by_type = {}
    for ev in events:
        by_type[ev.get("event_type")] = by_type.get(ev.get("event_type"), 0) + 1
    lines = [
        "Ítem 7.2 — verify-security-logs.py",
        f"Archivo: {args.logfile}",
        f"Eventos analizados: {len(events)}  |  por tipo: {json.dumps(by_type, sort_keys=True)}",
        f"Patrones encontrados: {sorted({p for ev in events for p in ev.get('suspicious_patterns', [])})}",
        f"Comprobaciones: {len(args.client_ip)} IP(s) de cliente, {len(args.forbidden_value)} valor(es) prohibido(s), "
        f"cabeceras Authorization/Cookie, IPs en claro, formato, patrones esperados {expect_patterns}, eventos esperados {args.expect_event}",
    ]
    if errors:
        lines.append(f"RESULTADO: FAIL ({len(errors)} problema(s))")
        lines += [f"  - {e}" for e in errors]
    else:
        lines.append("RESULTADO: PASS — sin IPs en claro, sin valores de parámetros, sin Authorization/Cookie; inyección marcada.")
    text = "\n".join(lines)
    print(text)
    if args.output:
        with open(args.output, "w", encoding="utf-8", newline="\n") as f:
            f.write(text + "\n")
    return 1 if errors else 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    sys.exit(main())
