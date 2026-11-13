#!/usr/bin/env python3
"""
Ítem 7.4 (prerrequisito) — Condición mínima de disparo para investigar (THR-06 / CTL-06).

NO es el ítem 7.3 (alertas con umbral y notificación): no notifica, no bloquea, no modifica nada.
Solo lee los eventos de seguridad del 7.2 y responde: ¿hay algo que una persona deba investigar?

Regla SIG-01: un mismo actor_id genera N o más eventos de tipo
    abuse_suspected | validation_rejected | access_denied | not_found
dentro de una ventana deslizante de T minutos. (server_error no cuenta: no lo provoca el cliente.)

Entrada: archivo .jsonl o stdin (p. ej. `docker compose logs backend --no-log-prefix | python ... -`).
Las líneas que no son eventos de seguridad (arranque de Nest, etc.) se ignoran.
Salida: JSON con la regla, el umbral, la ventana y, por actor que la supera, el conteo por
event_type, el rango de tiempo de la ventana más densa y sus correlation_ids.

Uso:
  python scripts/security-alert-check.py reports/security-alert-logs-<sha>.jsonl [--threshold 10] [--window-minutes 5]
  docker compose logs backend --no-log-prefix | python scripts/security-alert-check.py -
Exit: 0 siempre (solo informa). Con --fail-on-signal: 1 si hay señal (útil en scripts).
"""
import argparse
import datetime as dt
import json
import sys
from collections import Counter, defaultdict

RULE_ID = "SIG-01"
COUNTED = ("abuse_suspected", "validation_rejected", "access_denied", "not_found")
DEFAULT_THRESHOLD = 10
DEFAULT_WINDOW_MIN = 5
MAX_IDS = 100


def parse_ts(s):
    try:
        return dt.datetime.fromisoformat(str(s).replace("Z", "+00:00"))
    except ValueError:
        return None


def iso(t):
    return t.astimezone(dt.timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("input", help="archivo .jsonl o '-' para stdin")
    ap.add_argument("--threshold", "-n", type=int, default=DEFAULT_THRESHOLD, help=f"N eventos (por defecto {DEFAULT_THRESHOLD})")
    ap.add_argument("--window-minutes", "-t", type=float, default=DEFAULT_WINDOW_MIN, help=f"T minutos (por defecto {DEFAULT_WINDOW_MIN})")
    ap.add_argument("--output", "-o", help="guardar el JSON también en este archivo")
    ap.add_argument("--fail-on-signal", action="store_true", help="exit 1 si hay señal")
    args = ap.parse_args()
    if args.threshold < 1 or args.window_minutes <= 0:
        ap.error("--threshold debe ser >= 1 y --window-minutes > 0")

    stream = sys.stdin if args.input == "-" else open(args.input, encoding="utf-8", errors="replace")
    lines = security = 0
    by_actor = defaultdict(list)
    first = last = None
    with stream:
        for raw in stream:
            lines += 1
            raw = raw.strip()
            if not raw.startswith("{"):
                continue
            try:
                ev = json.loads(raw)
            except json.JSONDecodeError:
                continue
            if ev.get("log_type") != "security_event":
                continue
            security += 1
            t = parse_ts(ev.get("timestamp"))
            if t is None:
                continue
            first = t if first is None or t < first else first
            last = t if last is None or t > last else last
            if ev.get("event_type") in COUNTED and ev.get("actor_id"):
                by_actor[ev["actor_id"]].append((t, ev))

    window = dt.timedelta(minutes=args.window_minutes)
    signals = []
    for actor, evs in by_actor.items():
        evs.sort(key=lambda x: x[0])
        # Ventana deslizante: se conserva la ventana con más eventos (la más densa).
        best = (0, 0, 0)
        j = 0
        for i in range(len(evs)):
            while evs[i][0] - evs[j][0] > window:
                j += 1
            if i - j + 1 > best[0]:
                best = (i - j + 1, j, i)
        count, a, b = best
        if count < args.threshold:
            continue
        chunk = [e for _, e in evs[a:b + 1]]
        ids = [e.get("correlation_id") for e in chunk]
        signals.append({
            "actor_id": actor,
            "actor_id_scope": chunk[0].get("actor_id_scope"),
            "count": count,
            "counts_by_event_type": dict(sorted(Counter(e["event_type"] for e in chunk).items())),
            "status_codes": dict(sorted(Counter(str(e.get("status_code")) for e in chunk).items())),
            "methods": dict(sorted(Counter(e.get("method") for e in chunk).items())),
            "routes": dict(Counter(e.get("route") for e in chunk).most_common(20)),
            "suspicious_patterns": dict(sorted(Counter(p for e in chunk for p in e.get("suspicious_patterns", [])).items())),
            "first_seen": iso(evs[a][0]),
            "last_seen": iso(evs[b][0]),
            "duration_seconds": round((evs[b][0] - evs[a][0]).total_seconds(), 3),
            "total_counted_events_for_actor": len(evs),
            "correlation_ids": ids[:MAX_IDS],
            "correlation_ids_truncated": len(ids) > MAX_IDS,
        })
    signals.sort(key=lambda s: -s["count"])

    out = {
        "rule": {
            "id": RULE_ID,
            "description": "Un mismo actor_id genera N o más eventos de rechazo/abuso dentro de una ventana deslizante de T minutos",
            "event_types": list(COUNTED),
            "threshold": args.threshold,
            "window_minutes": args.window_minutes,
        },
        "generated_at": iso(dt.datetime.now(dt.timezone.utc)),
        "input": {
            "source": args.input,
            "lines_read": lines,
            "security_events": security,
            "counted_events": sum(len(v) for v in by_actor.values()),
            "actors": len(by_actor),
            "time_range": {"first": iso(first) if first else None, "last": iso(last) if last else None},
        },
        "result": "SIGNAL" if signals else "NO_SIGNAL",
        "signals": signals,
        "note": "Señal para investigación humana (7.4). No es una alerta con notificación (7.3), no bloquea ni modifica nada.",
    }
    text = json.dumps(out, indent=2, ensure_ascii=False)
    print(text)
    if args.output:
        with open(args.output, "w", encoding="utf-8", newline="\n") as f:
            f.write(text + "\n")
    return 1 if (args.fail_on_signal and signals) else 0


if __name__ == "__main__":
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if hasattr(sys.stdin, "reconfigure"):
        sys.stdin.reconfigure(encoding="utf-8", errors="replace")
    sys.exit(main())
