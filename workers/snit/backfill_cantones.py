#!/usr/bin/env python3
"""
Worker SNIT - Backfill de cantones faltantes en la tabla `canton`.

La capa ArcGIS "Cantones_de_Costa_Rica" (services5.arcgis.com/.../Cantones_de_Costa_Rica)
no incluye los cantones creados después de 2015. Este script los registra usando
los códigos oficiales de la División Territorial Administrativa 2022 del SNIT/IGN
(https://files.snitcr.go.cr/boletines/DTA-TABLA POR PROVINCIA-CANTÓN-DISTRITO 2022V4.pdf).

Los cantones se insertan SIN geometría (geom NULL) porque ninguna fuente oficial
vigente de geometría estuvo disponible en line al momento de crear este worker.
Queda pendiente completarlos cuando se disponga de la capa actualizada.

Cantones faltantes (código DTA 2022 -> convención de la tabla: provincia*1000 + últimos 2 dígitos):
  - SARCHI           (212 -> 2012)
  - RIO CUARTO       (216 -> 2016)
  - QUEPOS           (612 -> 6012)
  - MONTEVERDE       (613 -> 6013)
  - PUERTO JIMENEZ   (614 -> 6014)
Fecha de verificación: 2026-09-10
"""

import sys
import os
from datetime import datetime, timezone

import psycopg2

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", 5432)),
    "user": os.getenv("DB_USER", "seguridad_vial"),
    "password": os.getenv("DB_PASSWORD"),
    "dbname": os.getenv("DB_NAME", "seguridad_vial_db"),
}

CANTONES_FALTANTES = [
    {"codigo": "2012", "nombre": "Sarchí", "provincia": "Alajuela"},
    {"codigo": "2016", "nombre": "Río Cuarto", "provincia": "Alajuela"},
    {"codigo": "6012", "nombre": "Quepos", "provincia": "Puntarenas"},
    {"codigo": "6013", "nombre": "Monteverde", "provincia": "Puntarenas"},
    {"codigo": "6014", "nombre": "Puerto Jiménez", "provincia": "Puntarenas"},
]

FUENTE = "SNIT/IGN (DTA 2022, geometría pendiente)"


def main():
    try:
        conn = psycopg2.connect(**DB_CONFIG)
    except psycopg2.Error as e:
        print(f"✗ No se pudo conectar: {e}")
        sys.exit(1)

    cur = conn.cursor()
    now = datetime.now(timezone.utc).isoformat()
    insertados = 0

    try:
        for c in CANTONES_FALTANTES:
            cur.execute(
                """
                INSERT INTO canton (codigo, nombre, poblacion, geom, fuente, fecha_obtencion)
                VALUES (%s, %s, NULL, NULL, %s, %s)
                ON CONFLICT (codigo) DO UPDATE SET
                    nombre = EXCLUDED.nombre,
                    fuente = EXCLUDED.fuente,
                    fecha_obtencion = EXCLUDED.fecha_obtencion
                """,
                (c["codigo"], c["nombre"], FUENTE, now),
            )
            insertados += cur.rowcount
            print(f"  → {c['codigo']} {c['nombre']} (sin geometría)")

        conn.commit()
        print(f"✓ {insertados} cantones agregados/actualizados sin geometría")
    except psycopg2.Error as e:
        print(f"✗ Error de base de datos: {e}")
        sys.exit(1)
    finally:
        cur.close()
        conn.close()


if __name__ == "__main__":
    main()