#!/usr/bin/env python3
"""
Worker OIJ - Descarga Estadísticas Policiales desde el CKAN del Poder Judicial
y las inseruta en PostgreSQL (tabla delito), vinculando por nombre de cantón.

Fuente: Poder Judicial de Costa Rica — Datos Abiertos (Estadísticas Policiales)
CKAN:    https://datosabiertospj.poder-judicial.go.cr/dataset/estadisticas-policiales
Endpoint CSV: https://pjcrdatosabiertos.blob.core.windows.net/datosabiertos/PJCROD_POLICIALES_V1/PJCROD_POLICIALES_V1-{año}.csv
Formato: CSV sin encabezado, 11 columnas:
  tipo_delito | modalidad | fecha | tipo_victima | victima | edad | sexo | nacionalidad | provincia | canton | distrito
Fecha de verificación: 2026-09-10
"""

import sys
import os
import argparse
import unicodedata
import csv
import io
from datetime import datetime, timezone

import requests
import psycopg2

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

CSV_URL_TEMPLATE = (
    "https://pjcrdatosabiertos.blob.core.windows.net/datosabiertos/"
    "PJCROD_POLICIALES_V1/PJCROD_POLICIALES_V1-{anio}.csv"
)

DB_CONFIG = {
    "host": os.getenv("DB_HOST", "localhost"),
    "port": int(os.getenv("DB_PORT", 5432)),
    "user": os.getenv("DB_USER", "seguridad_vial"),
    "password": os.getenv("DB_PASSWORD", "S3gur!d@dV1al_2026"),
    "dbname": os.getenv("DB_NAME", "seguridad_vial_db"),
}

FUENTE = "OIJ/CKAN"

# Alias de nombres de cantón: OIJ usa unos nombres que difieren de la DTA oficial (SNIT).
# Normalizados a mayúsculas sin acentos.
ALIASES = {
    "LEON CORTES": "LEON CORTES CASTRO",
    "LEON CORTES CASTRO": "LEON CORTES CASTRO",
    "VASQUEZ DE CORONADO": "VAZQUEZ DE CORONADO",
}


def normalizar(texto):
    """Elimina acentos y colapsa espacios para comparar nombres (LIMÓN -> LIMON)."""
    if not texto:
        return None
    texto = unicodedata.normalize("NFKD", texto)
    texto = "".join(c for c in texto if not unicodedata.combining(c))
    return " ".join(texto.upper().split())


def descargar_csv(anio):
    url = CSV_URL_TEMPLATE.format(anio=anio)
    print(f"[{datetime.now(timezone.utc).isoformat()}] Descargando CSV {anio}: {url}")
    resp = requests.get(url, timeout=120)
    resp.raise_for_status()
    resp.encoding = resp.apparent_encoding or "utf-8"
    return resp.text


def leer_csv(texto):
    """Lee el CSV sin encabezado y devuelve filas con 11 columnas."""
    reader = csv.reader(io.StringIO(texto))
    filas = []
    for linea in reader:
        if len(linea) < 11:
            continue
        filas.append([celda.strip() for celda in linea[:11]])
    return filas


def cargar_lookup_cantones(cur):
    """Mapea nombre normalizado de cantón -> (id, codigo) desde tabla canton."""
    cur.execute("SELECT id, codigo, nombre FROM canton")
    lookup = {}
    for id_, codigo, nombre in cur.fetchall():
        lookup[normalizar(nombre)] = (id_, codigo)
    return lookup


def agregar(filas, lookup_cantones):
    """Agrega por (canton_id, tipo, modalidad, fecha) acumulando cantidad."""
    agregados = {}
    sin_canton = {}

    for f in filas:
        tipo = f[0] or "SIN TIPO"
        modalidad = f[1] or None
        fecha = f[2] or None
        provincia = f[8] or None
        canton_nombre = f[9] or None
        distrito = f[10] or None

        if not fecha:
            continue

        canton_info = None
        if canton_nombre:
            clave_canton = ALIASES.get(normalizar(canton_nombre), normalizar(canton_nombre))
            canton_info = lookup_cantones.get(clave_canton)
            if canton_info is None:
                clave_canton = normalizar(canton_nombre)
                sin_canton[clave_canton] = sin_canton.get(clave_canton, 0) + 1

        clave = (canton_info[0] if canton_info else None, tipo, modalidad, fecha)
        if clave in agregados:
            agregados[clave]["cantidad"] += 1
        else:
            agregados[clave] = {
                "canton_id": canton_info[0] if canton_info else None,
                "provincia": provincia,
                "distrito": distrito,
                "tipo": tipo,
                "modalidad": modalidad,
                "fecha": fecha,
                "cantidad": 1,
            }
    return agregados, sin_canton


def insertar(conn, agregados, fecha_obtencion):
    cur = conn.cursor()
    insertados = 0
    actualizados = 0

    filas = sorted(agregados.values(), key=lambda r: r["fecha"])
    for r in filas:
        cur.execute(
            """
            INSERT INTO delito (canton_id, provincia, distrito, tipo, modalidad, fecha, cantidad, fuente, fecha_obtencion)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s, %s)
            ON CONFLICT (COALESCE(canton_id, 0), tipo, COALESCE(modalidad, ''), fecha) DO UPDATE SET
                cantidad = EXCLUDED.cantidad,
                provincia = EXCLUDED.provincia,
                distrito = EXCLUDED.distrito,
                fuente = EXCLUDED.fuente,
                fecha_obtencion = EXCLUDED.fecha_obtencion
            """,
            (
                r["canton_id"],
                r["provincia"],
                r["distrito"],
                r["tipo"],
                r["modalidad"],
                r["fecha"],
                r["cantidad"],
                FUENTE,
                fecha_obtencion,
            ),
        )
        if cur.rowcount == 1:
            insertados += 1
        else:
            actualizados += 1

    conn.commit()
    cur.close()
    return insertados, actualizados


def main():
    parser = argparse.ArgumentParser(description="Ingesta de Estadísticas Policiales OIJ")
    parser.add_argument("--anio", nargs="+", type=str, default=["2025"],
                        help="Año(s) a procesar, p.ej. --anio 2024 2025. Default: 2025")
    args = parser.parse_args()

    fecha_obtencion = datetime.now(timezone.utc).isoformat()

    try:
        conn = psycopg2.connect(**DB_CONFIG)
        cur = conn.cursor()
        lookup = cargar_lookup_cantones(cur)
        print(f"  → {len(lookup)} cantones cargados para el cruce")
        conn.rollback()
    except psycopg2.Error as e:
        print(f"✗ No se pudo conectar a la base de datos: {e}")
        sys.exit(1)

    total_insertados = 0
    total_actualizados = 0
    total_sin_canton = {}

    try:
        for anio in args.anio:
            texto = descargar_csv(anio)
            filas = leer_csv(texto)
            print(f"  → {len(filas)} registros en {anio}")

            agregados, sin_canton = agregar(filas, lookup)
            insertados, actualizados = insertar(conn, agregados, fecha_obtencion)

            total_insertados += insertados
            total_actualizados += actualizados
            for k, v in sin_canton.items():
                total_sin_canton[k] = total_sin_canton.get(k, 0) + v

            print(f"  → {anio}: {insertados} filas insertadas, {actualizados} actualizadas")
            print(f"  → {anio}: registros sin cantón reconocido: {len(sin_canton)} grupos")

        if total_sin_canton:
            top = sorted(total_sin_canton.items(), key=lambda x: -x[1])[:10]
            print("  Top nombres de cantón no reconocidos:")
            for nombre, n in top:
                print(f"    - {nombre}: {n} registros")

        print(f"✓ Proceso completado: {total_insertados} insertados, {total_actualizados} actualizados")

    except requests.RequestException as e:
        print(f"✗ Error de red: {e}")
        sys.exit(1)
    except psycopg2.Error as e:
        print(f"✗ Error de base de datos: {e}")
        sys.exit(1)
    except Exception as e:
        print(f"✗ Error inesperado: {e}")
        sys.exit(1)
    finally:
        conn.close()


if __name__ == "__main__":
    main()