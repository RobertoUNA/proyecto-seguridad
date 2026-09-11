# Observatorio de Seguridad Vial y Urbana de Costa Rica

Sistema web que integra **4 fuentes OSINT de Costa Rica** y las cruza
espacialmente para responder: **¿qué tan preparada está una zona ante una
emergencia de seguridad o un accidente vial?**

- Fuentes: **OIJ/Poder Judicial**, **COSEVI**, **SNIT** y **OpenStreetMap/Overpass**.
- Valor central: la relación geoespacial entre criminalidad, accidentabilidad e
  infraestructura de atención (hospitales, comisarías, vías).
- Solo datos **agregados por cantón/distrito**, nunca perfiles individuales.

---

## Quick Start

```bash
# 1. Clonar
git clone https://github.com/RobertoUNA/proyecto-seguridad.git
cd proyecto-seguridad

# 2. Base de datos (PostgreSQL + PostGIS)
psql -U postgres -c "CREATE ROLE seguridad_vial LOGIN PASSWORD 'TU_PASSWORD_AQUI' CREATEDB;"
psql -U postgres -c "CREATE DATABASE seguridad_vial_db OWNER seguridad_vial;"
psql -U postgres -d seguridad_vial_db -c "CREATE EXTENSION IF NOT EXISTS postgis;"

# 3. Backend
cd backend
npm install
npm run db:migrate
npm run start:dev          # http://localhost:3000

# 4. Workers de ingesta (en otra terminal)
cd ..
pip install -r workers/snit/requirements.txt
pip install -r workers/oij/requirements.txt
pip install -r workers/cosevi/requirements.txt
pip install -r workers/osm/requirements.txt
python workers/snit/fetch_cantones.py
python workers/oij/fetch_delitos.py --anio 2020 2021 2022 2023 2024 2025
python workers/cosevi/fetch_accidentes.py
python workers/osm/fetch_infraestructura.py   # requiere OSM_CONTACT_EMAIL en backend/.env

# 5. Frontend (en otra terminal)
cd frontend
npm install
npm run dev                # http://localhost:5173
```

---

## Prerrequisitos

| Requisito | Versión mínima | Verificado con |
|-----------|---------------|----------------|
| Node.js | >= 20 | 22 |
| Python | >= 3.10 | 3.12 |
| PostgreSQL | >= 13 | 16 |
| PostGIS | >= 3.0 | 3.6.1 |

> **PostGIS**: si no está instalado, descargar el bundle oficial para tu versión
> de PostgreSQL desde `https://download.osgeo.org/postgis/windows/`. Luego ejecutar:
> `psql -U postgres -d seguridad_vial_db -c "CREATE EXTENSION IF NOT EXISTS postgis;"`.

---

## Estructura del proyecto

```
proyecto-seguridad/
├── backend/                   API NestJS (TypeScript)
│   ├── src/modules/snit/      Cantones (límites oficiales + geometría PostGIS)
│   ├── src/modules/oij/       Delitos (normalización y endpoints)
│   ├── database/migrations/   SQL: 001_cantones, 002_delitos
│   ├── .env.example           Variables de entorno documentadas
│   └── package.json
├── frontend/                  React + TypeScript + Vite + Leaflet
│   ├── src/components/        Mapa, filtros, ficha de cantón
│   └── package.json
├── workers/                   Scripts Python de ingesta
│   ├── snit/                  fetch_cantones.py, backfill_cantones.py
│   ├── oij/                   fetch_delitos.py
│   ├── cosevi/                fetch_accidentes.py
│   └── osm/                   fetch_infraestructura.py
├── plan-proyecto-seguridad-vial-urbana.md   Roadmap y tareas pendientes
└── .gitignore
```

---

## Arquitectura

```
Fuentes OSINT (OIJ, COSEVI, SNIT, OSM/Overpass)
        │
        ▼
  Workers de ingesta (Python)
   - normalizan cada fuente a un modelo común
   - guardan fuente y fecha de obtención
        │
        ▼
   PostgreSQL + PostGIS (seguridad_vial_db)
        │
        ▼
   API NestJS (backend/)
   - /api/cantones         (SNIT) ✅
   - /api/delitos          (OIJ)  ✅
   - /api/accidentes       (COSEVI) ✅
   - /api/infraestructura  (OSM)   ✅
   - /api/cantones/:id/panorama (cruce) ⏳ pendiente
        │
        ▼
   Frontend React + TS (Leaflet)
   - mapa interactivo con capas togglables
   - panel de filtros + ficha de cantón
```

**Principio clave**: el backend consume y normaliza; el frontend nunca llama
directo a las fuentes externas (evita CORS, controla caché y errores).

---

## Estado actual del proyecto

### Completado

| Módulo | Estado | Detalle |
|--------|--------|---------|
| **Base de datos** | ✅ | PostgreSQL + PostGIS, migraciones SQL, esquema `cantones` y `delitos` |
| **Worker SNIT** | ✅ | `fetch_cantones.py` descarga geometrías cantonales vía ArcGIS FeatureServer |
| **Worker OIJ** | ✅ | `fetch_delitos.py` descarga CSVs de datosabiertospj (2020-2025) |
| **Backend SNIT** | ✅ | Endpoints `GET /api/cantones` y `GET /api/cantones/:codigo` |
| **Backend OIJ** | ✅ | Endpoints `/api/delitos`, `/api/delitos/por-canton`, `/api/delitos/tipos` |
| **Frontend mapa** | ✅ | Mapa Leaflet con capa de cantones, panel de filtros, ficha de detalle |
| **Migraciones SQL** | ✅ | `001_create_cantones.sql`, `002_create_delitos.sql`, `003_create_accidentes.sql`, `004_create_infraestructura.sql` |
| **Worker OSM/Overpass** | ✅ | `fetch_infraestructura.py` consulta Overpass API (hospitales, clínicas, comisarías) sin API key |
| **Backend OSM/Overpass** | ✅ | Endpoints `/api/infraestructura`, `/api/infraestructura/por-canton` |
| **Worker COSEVI** | ✅ | `fetch_accidentes.py` descarga el CSV oficial de accidentes con víctimas |
| **Backend COSEVI** | ✅ | Endpoints `/api/accidentes`, `/api/accidentes/por-canton`, `/api/accidentes/tipos`, `/api/accidentes/clases` |

### Pendiente (tareas para el equipo)

| Tarea | Responsable | Estado | Notas |
|-------|-------------|--------|-------|
| Endpoint de cruce `/api/cantones/:id/panorama` | Compartido | 🔴 No iniciado | Combina las 4 fuentes + índice de cobertura |
| Geometría de 5 cantones faltantes | — | 🟡 Parcial | Sarchí, Río Cuarto, Quepos, Monteverde, Puerto Jiménez (DTA 2022 sin geom) |
| Capas adicionales en frontend | — | 🟡 Parcial | Marcadores de infraestructura ✅ listos; falta heatmap de delitos y gráficos por cantón |
| Redis caché para Overpass/SNIT | — | 🔴 No iniciado | Evitar sobrecargar APIs públicas |
| Despliegue | — | 🔴 No iniciado | Decidir plataforma (Vercel, Railway, etc.) |

Ver `plan-proyecto-seguridad-vial-urbana.md` para el roadmap detallado y contexto por módulo.

---

## Integrante responsable de cada fuente

| # | Fuente | Responsable |
|---|--------|-------------|
| 1 | OIJ — Estadísticas Policiales | Roberto (RobertoUNA) |
| 2 | COSEVI | Billy-Ugalde |
| 3 | SNIT | Roberto (RobertoUNA) |
| 4 | OpenStreetMap / Overpass | Brandon-Corrales |

---

## Endpoints de la API

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/api/cantones` | FeatureCollection GeoJSON de todos los cantones (SNIT) |
| GET | `/api/cantones/:codigo` | Un cantón por código DTA |
| GET | `/api/delitos?canton&tipo&desde&hasta` | Delitos filtrados + resumen por cantón |
| GET | `/api/delitos/por-canton` | Totales por cantón (para choropleth) |
| GET | `/api/delitos/tipos` | Lista de tipos de delito disponibles |
| GET | `/api/accidentes?canton&anio&clase&tipo` | Accidentes con víctimas (COSEVI) filtrados + resumen |
| GET | `/api/accidentes/por-canton` | Totales de accidentes por cantón (choropleth) |
| GET | `/api/infraestructura?canton&tipo` | Hospitales, clínicas y comisarías (OSM) filtrados + resumen |
| GET | `/api/infraestructura/por-canton` | Conteo de infraestructura por cantón (índice de cobertura) |

Las respuestas incluyen metadata: `X-Data-Source`, `X-Fetch-Date`, y campos
`fuente` / `fecha_obtencion` en cada registro.

---

## Variables de entorno

Copiar `backend/.env.example` a `backend/.env` y ajustar valores:

```env
DB_HOST=localhost
DB_PORT=5432
DB_USER=seguridad_vial
DB_PASSWORD=tu_password
DB_NAME=seguridad_vial_db
PORT=3000
OSM_CONTACT_EMAIL=tu_email@ejemplo.com
```

> **Nunca** commitear el archivo `.env` con credenciales reales.

---

## Decisiones técnicas y limitaciones

1. **SNIT desactualizado**: el FeatureServer "Cantones_de_Costa_Rica" no incluye
   cantones creados después de 2015. Se dieron de alta 5 cantones nuevos con
   códigos DTA 2022 **sin geometría** (geom NULL). Pendiente completar cuando
   exista una capa oficial vigente.

2. **COSEVI**: resuelto sin scraping. El worker descarga el CSV oficial
   "Consolidado de accidentes de tránsito con víctimas" publicado en
   datosabiertos.csv.go.cr (ver `SPEC-cosevi.md`), sin necesitar la API
   de Junar (que exige API key).

3. **Overpass API**: el rechazo (406/timeout) documentado en pruebas anteriores
   ya no reproduce usando un `User-Agent` identificable
   (`OSM_CONTACT_EMAIL` en `.env`, ver `SPEC-osm.md`). El worker consulta
   `overpass-api.de` a nivel país en una sola petición (no por cantón) y cae
   automáticamente al mirror `overpass.kumi.systems` si la instancia oficial
   falla tras reintentar con backoff. Sigue pendiente el caché (Redis u otro)
   delante del worker, y la cobertura depende de qué tan mapeada esté cada
   zona en OSM.

4. **Límite de resultados en `/api/infraestructura`**: el `findAll` original
   ordenaba por `tipo ASC` y truncaba con `.take(1000)`, patrón copiado de
   delitos/accidentes. Como "clinica" (1124 registros) es alfabéticamente
   primero y por sí sola supera el límite, la respuesta sin filtros nunca
   devolvía hospitales ni comisarías. Corregido subiendo el límite a 5000:
   a diferencia de delitos/accidentes (series temporales donde "los últimos
   1000" tiene sentido), infraestructura es un snapshot nacional acotado.

5. **Alias de nombres OIJ→SNIT**: se normalizan acentos y mayúsculas. Mapeos:
   `LEÓN CORTÉS` → `LEÓN CORTÉS CASTRO`, `VÁSQUEZ DE CORONADO` → `VÁZQUEZ DE CORONADO`.

6. **Correlación ≠ causalidad**: la UI lo indica explícitamente.

---

## Consideraciones éticas

- No se evaden CAPTCHA, autenticación ni rate limits de ninguna fuente.
- No se publican tokens/credenciales (`.env` en `.gitignore`).
- Solo datos agregados por cantón/zona, nunca perfiles individuales.
- Se respetan los límites de uso de la API de Overpass.
- Cada registro almacena `fuente` y `fecha_obtencion`.

---

## Licencia

Proyecto académico — Universidad Nacional (UNA), Costa Rica.
