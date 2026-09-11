#!/usr/bin/env python3
"""
Worker SNIT - Descarga cantones de Costa Rica desde ArcGIS FeatureServer
y los inserta en PostgreSQL con geometría PostGIS.

Fuente: Cantones de Costa Rica (ArcGIS FeatureServer)
Endpoint: https://services5.arcgis.com/4u1m1BBDkNDTVWsd/arcgis/rest/services/Cantones_de_Costa_Rica/FeatureServer/0
Fecha de verificación: 2026-09-10
"""

import sys
import os
import requests
import psycopg2
import psycopg2.extras
from datetime import datetime, timezone

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

# Configuración de la fuente de datos
ARCGIS_URL = (
    "https://services5.arcgis.com/4u1m1BBDkNDTVWsd/arcgis/rest/services/"
    "Cantones_de_Costa_Rica/FeatureServer/0/query"
)
PARAMS = {
    "where": "1=1",
    "outFields": "ID,NAME,TOTPOP_CY",
    "f": "geojson",
    "outSR": "4326",
}

# Configuración de PostgreSQL
DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", 5432)),
    "user": os.getenv("DB_USER", "seguridad_vial"),
    "password": os.getenv("DB_PASSWORD"),
    "dbname": os.getenv("DB_NAME", "seguridad_vial_db"),
}

FUENTE = "SNIT/ArcGIS"


def fetch_cantones():
    print(f"[{datetime.now(timezone.utc).isoformat()}] Consultando ArcGIS FeatureServer...")
    resp = requests.get(ARCGIS_URL, params=PARAMS, timeout=30)
    resp.raise_for_status()
    data = resp.json()
    features = data.get("features", [])
    print(f"  → {len(features)} cantones obtenidos")
    return features


def insert_cantones(features):
    conn = psycopg2.connect(**DB_CONFIG)
    cur = conn.cursor()

    now = datetime.now(timezone.utc).isoformat()
    inserted = 0
    updated = 0

    for f in features:
        props = f.get("properties", {})
        geom = f.get("geometry")

        codigo = str(props.get("ID", "") or "").strip()
        nombre = (props.get("NAME") or "").strip()
        poblacion = props.get("TOTPOP_CY")

        if not codigo or not nombre:
            print(f"  ⚠ Saltando feature sin código/nombre: {props}")
            continue

        cur.execute(
            """
            INSERT INTO canton (codigo, nombre, poblacion, geom, fuente, fecha_obtencion)
            VALUES (%s, %s, %s, ST_GeomFromGeoJSON(%s), %s, %s)
            ON CONFLICT (codigo) DO UPDATE SET
                nombre = EXCLUDED.nombre,
                poblacion = EXCLUDED.poblacion,
                geom = EXCLUDED.geom,
                fuente = EXCLUDED.fuente,
                fecha_obtencion = EXCLUDED.fecha_obtencion
            """,
            (codigo, nombre, poblacion, psycopg2.extras.Json(geom), FUENTE, now),
        )

        if cur.rowcount > 0:
            inserted += 1

    conn.commit()
    cur.close()
    conn.close()

    print(f"  → {inserted} cantones insertados/actualizados")
    return inserted


def main():
    try:
        features = fetch_cantones()
        if not features:
            print("No se obtuvieron cantones. Verificar el endpoint.")
            sys.exit(1)
        insert_cantones(features)
        print("✓ Proceso completado exitosamente")
    except requests.RequestException as e:
        print(f"✗ Error de red: {e}")
        sys.exit(1)
    except psycopg2.Error as e:
        print(f"✗ Error de base de datos: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"✗ Error inesperado: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
