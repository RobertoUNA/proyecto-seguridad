#!/usr/bin/env python3
"""Worker OSM/Overpass - Descarga infraestructura de atención (hospitales,
clínicas, comisarías) desde Overpass API y la inserta en PostgreSQL
(tabla infraestructura), cruzando cada punto contra la geometría cantonal
de SNIT vía PostGIS (ST_Contains), no por nombre.

Fuente: OpenStreetMap vía Overpass API, sin API key.
Instancia principal: https://overpass-api.de/api/interpreter
Mirror de respaldo:  https://overpass.kumi.systems/api/interpreter

Un diagnóstico previo confirmó que el bloqueo 406/timeout documentado en
el README no reproduce con un User-Agent identificable. Ver SPEC-osm.md
para el detalle de la decisión.
"""

import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import psycopg2
import requests

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8")

OSM_CONTACT_EMAIL = os.getenv("OSM_CONTACT_EMAIL", "tu_email@ejemplo.com")
USER_AGENT = f"ProyectoSeguridadVialUNA/1.0 (contacto: {OSM_CONTACT_EMAIL})"

INSTANCIAS = [
    "https://overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
]

FUENTE = "OSM/Overpass"

# amenity de OSM -> categoría normalizada del proyecto (coincide con el
# CHECK de la migración 004_create_infraestructura.sql).
CATEGORIAS = {
    "hospital": "hospital",
    "clinic": "clinica",
    "police": "comisaria",
}

QUERY = """
[out:json][timeout:180];
area["ISO3166-1"="CR"][admin_level=2]->.cr;
(
  node["amenity"="hospital"](area.cr);
  way["amenity"="hospital"](area.cr);
  node["amenity"="clinic"](area.cr);
  way["amenity"="clinic"](area.cr);
  node["amenity"="police"](area.cr);
  way["amenity"="police"](area.cr);
);
out center;
""".strip()

MAX_INTENTOS_POR_INSTANCIA = 3
ESPERA_BASE_SEGUNDOS = 10
TIMEOUT_HTTP_SEGUNDOS = 200


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


def consultar_overpass():
    """Prueba cada instancia con reintentos y backoff exponencial.

    Nunca reintenta en loop agresivo: máximo MAX_INTENTOS_POR_INSTANCIA por
    instancia, con espera creciente entre intentos (respeta el fair-use de
    Overpass). Devuelve (url_instancia, elementos) o (None, []) si ninguna
    instancia respondió.
    """
    headers = {"User-Agent": USER_AGENT}

    for url in INSTANCIAS:
        for intento in range(1, MAX_INTENTOS_POR_INSTANCIA + 1):
            print(f"[.] Consultando {url} (intento {intento}/{MAX_INTENTOS_POR_INSTANCIA})...")
            try:
                response = requests.post(
                    url, data={"data": QUERY}, headers=headers, timeout=TIMEOUT_HTTP_SEGUNDOS
                )
            except requests.RequestException as error:
                espera = ESPERA_BASE_SEGUNDOS * (2 ** (intento - 1))
                print(f"    x Error de red: {error}. Reintentando en {espera}s...")
                time.sleep(espera)
                continue

            if response.status_code == 200:
                try:
                    data = response.json()
                except ValueError:
                    print("    x HTTP 200 pero el cuerpo no es JSON válido, se descarta")
                    break
                elementos = data.get("elements", [])
                print(f"    -> {url} respondió con {len(elementos)} elementos")
                return url, elementos

            if response.status_code == 429 or response.status_code >= 500:
                espera = ESPERA_BASE_SEGUNDOS * (2 ** (intento - 1))
                print(f"    x HTTP {response.status_code}, reintentando en {espera}s...")
                time.sleep(espera)
                continue

            # 4xx que no es 429 (p.ej. 406): reintentar no va a cambiar el resultado.
            preview = response.text[:200].replace("\n", " ")
            print(f"    x HTTP {response.status_code}, sin reintentos para esta instancia: {preview}")
            break

        print(f"  Instancia agotada ({url}), probando siguiente mirror si existe...")

    return None, []


def normalizar_categoria(tags):
    return CATEGORIAS.get(tags.get("amenity"))


def extraer_coordenadas(elemento):
    if "lat" in elemento and "lon" in elemento:
        return elemento["lat"], elemento["lon"]
    centro = elemento.get("center") or {}
    return centro.get("lat"), centro.get("lon")


def procesar_elementos(elementos):
    registros = []
    omitidos = 0
    for elemento in elementos:
        tags = elemento.get("tags") or {}
        tipo = normalizar_categoria(tags)
        lat, lon = extraer_coordenadas(elemento)
        if not tipo or lat is None or lon is None:
            omitidos += 1
            continue
        registros.append(
            {
                "osm_type": elemento.get("type"),
                "osm_id": elemento.get("id"),
                "nombre": tags.get("name"),
                "tipo": tipo,
                "lat": lat,
                "lon": lon,
            }
        )
    return registros, omitidos


def insertar_registros(connection, registros, fecha_obtencion):
    cursor = connection.cursor()
    for registro in registros:
        cursor.execute(
            """
            INSERT INTO infraestructura (
                osm_type, osm_id, canton_id, nombre, tipo, lat, lon, fuente, fecha_obtencion
            ) VALUES (
                %(osm_type)s, %(osm_id)s,
                (
                    SELECT id FROM canton
                    WHERE geom IS NOT NULL
                      AND ST_Contains(geom, ST_SetSRID(ST_MakePoint(%(lon)s, %(lat)s), 4326))
                    LIMIT 1
                ),
                %(nombre)s, %(tipo)s, %(lat)s, %(lon)s, %(fuente)s, %(fetched_at)s
            )
            ON CONFLICT (osm_type, osm_id) DO UPDATE SET
                canton_id = EXCLUDED.canton_id,
                nombre = EXCLUDED.nombre,
                tipo = EXCLUDED.tipo,
                lat = EXCLUDED.lat,
                lon = EXCLUDED.lon,
                fuente = EXCLUDED.fuente,
                fecha_obtencion = EXCLUDED.fecha_obtencion
            """,
            {**registro, "fuente": FUENTE, "fetched_at": fecha_obtencion},
        )
    connection.commit()
    cursor.close()


def main():
    load_local_env()
    if not os.getenv("OSM_CONTACT_EMAIL"):
        print(
            "Aviso: define OSM_CONTACT_EMAIL en backend/.env (política de uso de Overpass)."
        )

    db_config = {
        "host": os.getenv("DB_HOST", "localhost"),
        "port": int(os.getenv("DB_PORT", "5432")),
        "user": os.getenv("DB_USER", "seguridad_vial"),
        "password": os.getenv("DB_PASSWORD"),
        "dbname": os.getenv("DB_NAME", "seguridad_vial_db"),
    }

    fecha_obtencion = datetime.now(timezone.utc).isoformat()
    print(f"[{fecha_obtencion}] Consultando infraestructura OSM/Overpass "
          f"(hospitales, clínicas, comisarías) en Costa Rica...")

    instancia, elementos = consultar_overpass()
    if instancia is None:
        print("✗ Ninguna instancia de Overpass respondió; no se toca la base de datos.", file=sys.stderr)
        sys.exit(1)

    registros, omitidos = procesar_elementos(elementos)
    print(f"  -> {len(registros)} elementos válidos, {omitidos} omitidos (sin categoría o coordenadas)")

    with psycopg2.connect(**db_config) as connection:
        insertar_registros(connection, registros, fecha_obtencion)

    print(f"✓ Proceso completado: {len(registros)} registros almacenados (fuente: {instancia})")


if __name__ == "__main__":
    try:
        main()
    except (psycopg2.Error, ValueError) as error:
        print(f"✗ Error de ingesta OSM: {error}", file=sys.stderr)
        sys.exit(1)
