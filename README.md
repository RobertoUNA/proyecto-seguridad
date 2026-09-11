# Observatorio de Seguridad Vial y Urbana de Costa Rica

Sistema web que integra **4 fuentes OSINT de Costa Rica** y las cruza
espacialmente para responder: **¿qué tan preparada está una zona ante una
emergencia de seguridad o un accidente vial?**

- Fuentes: **OIJ/Poder Judicial**, **COSEVI**, **SNIT** y **OpenStreetMap/Overpass**.
- Valor central: la relación geoespacial entre criminalidad, accidentabilidad e
  infraestructura de atención (hospitales, comisarías, vías).
- Solo datos **agregados por cantón/distrito**, nunca perfiles individuales.

---

## El problema y el objetivo

En Costa Rica la información sobre criminalidad (OIJ), accidentabilidad vial
(COSEVI), límites territoriales (SNIT) e infraestructura de atención
(hospitales, clínicas, comisarías, vía OpenStreetMap) vive en fuentes
públicas separadas, cada una con su propio formato y mecanismo de consumo.
Por separado, cada fuente responde una pregunta parcial; ninguna por sí sola
dice qué tan preparada está una zona específica ante una emergencia.

El objetivo de este proyecto es integrar esas 4 fuentes OSINT en un mismo
sistema, normalizarlas a un modelo común por cantón y cruzarlas
geoespacialmente para responder: ¿qué tan preparada está una zona ante una
emergencia de seguridad o un accidente vial? como por ejemplo, identificar
cantones con alta incidencia delictiva o de accidentes que además tienen
baja cobertura de infraestructura de atención cercana.

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
   - /api/cantones/:id/panorama (cruce) ✅
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
| **Endpoint de cruce** | ✅ | `GET /api/cantones/:id/panorama` combina las 4 fuentes + índice de cobertura |

### Pendiente (tareas para el equipo)

| Tarea | Responsable | Estado | Notas |
|-------|-------------|--------|-------|
| Geometría de 5 cantones faltantes | — | 🟡 Parcial | Sarchí, Río Cuarto, Quepos, Monteverde, Puerto Jiménez (DTA 2022 sin geom) |
| Capas adicionales en frontend | — | 🟡 Parcial | Marcadores de infraestructura ✅ listos; falta heatmap de delitos y gráficos por cantón |
| Redis caché para Overpass/SNIT | — | 🔴 No iniciado | Evitar sobrecargar APIs públicas |
| Despliegue | — | 🔴 No iniciado | Decidir plataforma (Vercel, Railway, etc.) |

Ver `plan-proyecto-seguridad-vial-urbana.md` para el roadmap detallado y contexto por módulo.

---

## Fuentes OSINT

| # | Fuente | Qué aporta | Enlace oficial | Responsable |
|---|--------|-----------|-----------------|-------------|
| 1 | OIJ — Estadísticas Policiales | Frecuencia y tipo de delitos por cantón (2020-2025) | [datosabiertospj.poder-judicial.go.cr](https://datosabiertospj.poder-judicial.go.cr/dataset/estadisticas-policiales) | Roberto (RobertoUNA) |
| 2 | COSEVI | Accidentes de tránsito con víctimas por cantón/distrito/año | [datosabiertos.csv.go.cr](https://datosabiertos.csv.go.cr/datasets/193472-consolidado-de-accidentes-de-transito-con-victimas.download/) | Billy-Ugalde |
| 3 | SNIT | Límites cantonales oficiales (geometría) | [snitcr.go.cr/ico_servicios_ogc](https://www.snitcr.go.cr/ico_servicios_ogc) | Jose-Picado-Zamora |
| 4 | OpenStreetMap / Overpass | Hospitales, clínicas y comisarías (infraestructura de atención) | [wiki.openstreetmap.org/wiki/Overpass_API](https://wiki.openstreetmap.org/wiki/Overpass_API) | Brandon-Corrales |

**Cómo se consume cada fuente:**

- **OIJ**: CSV descargado de un dataset CKAN (Azure Blob) por
  `workers/oij/fetch_delitos.py`, normalizado y cargado a la tabla `delito`.
- **COSEVI**: CSV oficial "Consolidado de accidentes de tránsito con
  víctimas" descargado y validado por `workers/cosevi/fetch_accidentes.py`
  → tabla `accidente` (detalle en `SPEC-cosevi.md`).
- **SNIT**: ArcGIS FeatureServer (servicio tipo OGC) consultado por
  `workers/snit/fetch_cantones.py`, guardado como geometría PostGIS en la
  tabla `canton`.
- **OpenStreetMap/Overpass**: Overpass QL vía Overpass API (JSON), consultado
  a nivel país por `workers/osm/fetch_infraestructura.py` y cruzado por
  PostGIS contra la geometría de cada cantón → tabla `infraestructura`
  (detalle en `SPEC-osm.md`).

Cada worker guarda `fuente` y `fecha_obtencion` en cada registro que inserta,
y cada endpoint de la API expone esos mismos datos en la respuesta y en las
cabeceras `X-Data-Source` / `X-Fetch-Date`

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
| GET | `/api/cantones/:id/panorama` | Cruce de las 4 fuentes para un cantón (código o nombre): delitos, accidentes, infraestructura e `indice_cobertura` |

Las respuestas incluyen metadata: `X-Data-Source`, `X-Fetch-Date`, y campos
`fuente` / `fecha_obtencion` en cada registro.

**Índice de cobertura** (`/api/cantones/:id/panorama`, campo
`indice_cobertura`): percentil de **0 a 100** que ubica al cantón frente a
todos los demás — **100 = el más vulnerable del país, 0 = el mejor
cubierto**. Se calcula así:

1. Ratio bruto por cantón: `(delitos + accidentes) / (1 + infraestructura)`
   (el +1 evita dividir entre cero cuando no hay infraestructura registrada).
   Este ratio no tiene techo, así que no es comparable por sí solo entre
   cantones de distinto tamaño (un cantón grande como San José siempre da
   un número alto en términos absolutos).
2. Ese ratio se calcula para los ~80 cantones del país y se convierte en un
   **percentil**: qué porcentaje de cantones tiene un ratio igual o menor
   al de este cantón. El resultado (`indice_cobertura`) sí es comparable
   entre cantones grandes y chicos.

El ratio bruto sin normalizar queda disponible en `indice_cobertura_ratio`
por transparencia de cómo se llegó al percentil.

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
