#!/usr/bin/env python3
"""Ingesta de accidentes con víctimas desde el CSV público de COSEVI."""

import csv
import io
import os
import sys
import unicodedata
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
import requests

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

COSEVI_CSV_URL = os.getenv(
    "COSEVI_CSV_URL",
    "https://datosabiertos.csv.go.cr/datasets/193472-consolidado-de-accidentes-de-transito-con-victimas.download/",
)
FUENTE = "COSEVI"
REQUIRED_COLUMNS = {"CLASE DE ACCIDENTE", "TIPO DE ACCIDENTE", "ANO", "CANTON"}
ALIASES = {
    "LEON CORTES": "LEON CORTES CASTRO",
    "VASQUEZ DE CORONADO": "VAZQUEZ DE CORONADO",
}


def normalize(value):
    if not value:
        return ""
    text = unicodedata.normalize("NFKD", value.strip())
    text = "".join(char for char in text if not unicodedata.combining(char))
    return " ".join(text.upper().split())


def load_local_env():
    env_path = Path(__file__).resolve().parents[2] / "backend" / ".env"
    if not env_path.exists():
        return
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        os.environ.setdefault(key.strip(), value.strip())


def column_lookup(fieldnames):
    lookup = {normalize(name): name for name in fieldnames or [] if name}
    missing = REQUIRED_COLUMNS - set(lookup)
    if missing:
        names = ", ".join(sorted(missing))
        raise ValueError(f"CSV sin columnas requeridas: {names}")
    return lookup


def parse_records(csv_text):
    reader = csv.DictReader(io.StringIO(csv_text), delimiter=";")
    columns = column_lookup(reader.fieldnames)
    records = []

    for row in reader:
        try:
            anio = int((row.get(columns["ANO"]) or "").strip())
        except ValueError:
            continue
        if not 1900 <= anio <= 2100:
            continue

        clase = (row.get(columns["CLASE DE ACCIDENTE"]) or "").strip()
        tipo = (row.get(columns["TIPO DE ACCIDENTE"]) or "").strip()
        canton = (row.get(columns["CANTON"]) or "").strip()
        if not clase or not tipo:
            continue

        records.append(
            {
                "anio": anio,
                "clase": clase,
                "tipo": tipo,
                "canton_nombre": canton or None,
                "provincia": (row.get(columns.get("PROVINCIA")) or "").strip() or None,
                "distrito": (row.get(columns.get("DISTRITO")) or "").strip() or None,
            }
        )
    return records


def aggregate_records(records, canton_lookup):
    aggregated = {}
    unmatched = Counter()
    for record in records:
        normalized_canton = normalize(record["canton_nombre"] or "")
        lookup_key = ALIASES.get(normalized_canton, normalized_canton)
        canton = canton_lookup.get(lookup_key)
        if normalized_canton and canton is None:
            unmatched[normalized_canton] += 1

        row = {
            **record,
            "canton_id": canton[0] if canton else None,
            "canton_nombre": record["canton_nombre"],
            "cantidad": 1,
        }
        key = (
            row["canton_id"],
            row["canton_nombre"],
            row["anio"],
            row["clase"],
            row["tipo"],
            row["provincia"],
            row["distrito"],
        )
        if key in aggregated:
            aggregated[key]["cantidad"] += 1
        else:
            aggregated[key] = row
    return aggregated, unmatched


def load_canton_lookup(cursor):
    cursor.execute("SELECT id, codigo, nombre FROM canton")
    return {normalize(nombre): (id_, codigo) for id_, codigo, nombre in cursor.fetchall()}


def insert_aggregates(connection, aggregated, fetched_at):
    cursor = connection.cursor()
    for row in aggregated.values():
        cursor.execute(
            """
            INSERT INTO accidente (
                canton_id, canton_nombre, provincia, distrito, anio, clase, tipo,
                cantidad, fuente, fecha_obtencion
            ) VALUES (%(canton_id)s, %(canton_nombre)s, %(provincia)s, %(distrito)s,
                %(anio)s, %(clase)s, %(tipo)s, %(cantidad)s, %(fuente)s, %(fetched_at)s)
            ON CONFLICT (
                COALESCE(canton_id, 0), COALESCE(canton_nombre, ''), anio, clase, tipo,
                COALESCE(provincia, ''), COALESCE(distrito, '')
            ) DO UPDATE SET
                cantidad = EXCLUDED.cantidad,
                fuente = EXCLUDED.fuente,
                fecha_obtencion = EXCLUDED.fecha_obtencion
            """,
            {**row, "fuente": FUENTE, "fetched_at": fetched_at},
        )
    connection.commit()
    cursor.close()


def main():
    load_local_env()
    db_config = {
        "host": os.getenv("DB_HOST", "localhost"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "user": os.getenv("DB_USER", "seguridad_vial"),
        "password": os.getenv("DB_PASSWORD"),
        "dbname": os.getenv("DB_NAME", "seguridad_vial_db"),
    }
    fetched_at = datetime.now(timezone.utc).isoformat()
    print(f"[{fetched_at}] Descargando consolidado oficial de COSEVI...")
    response = requests.get(COSEVI_CSV_URL, timeout=180)
    response.raise_for_status()
    records = parse_records(response.content.decode("utf-8-sig"))
    print(f"  -> {len(records)} registros válidos descargados")

    with psycopg2.connect(**db_config) as connection:
        with connection.cursor() as cursor:
            lookup = load_canton_lookup(cursor)
        aggregated, unmatched = aggregate_records(records, lookup)
        insert_aggregates(connection, aggregated, fetched_at)

    print(f"✓ Proceso completado: {len(aggregated)} agregados almacenados")
    if unmatched:
        print("  Cantones no vinculados:")
        for name, count in unmatched.most_common(10):
            print(f"    - {name}: {count} registros")


if __name__ == "__main__":
    try:
        main()
    except (requests.RequestException, psycopg2.Error, UnicodeDecodeError, ValueError) as error:
        print(f"✗ Error de ingesta COSEVI: {error}", file=sys.stderr)
        sys.exit(1)
