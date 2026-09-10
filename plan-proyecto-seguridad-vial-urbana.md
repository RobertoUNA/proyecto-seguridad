# Plan de proyecto: Observatorio de Seguridad Vial y Urbana de Costa Rica

> Documento de trabajo para el equipo. Aquí está la idea general, la arquitectura
> y la ruta a seguir para completar el proyecto.

---

## 1. ¿Qué estamos construyendo?

Un sistema web que integra **4 fuentes OSINT de Costa Rica** y las cruza
espacialmente para responder: **¿qué tan preparada está una zona ante una
emergencia de seguridad o un accidente vial?**

No es un dashboard de estadísticas: el valor está en la **relación geoespacial**
entre criminalidad, accidentabilidad e infraestructura de atención
(hospitales, comisarías, vías).

**Entregable académico**: repositorio GitHub + exposición técnica
(rúbrica de evaluación en la sección 8).

---

## 2. Fuentes OSINT — reparto por integrante

| # | Fuente | Qué aporta | Formato / mecanismo | Responsable |
|---|--------|-----------|---------------------|-------------|
| 1 | **OIJ — Estadísticas Policiales** ([Datas Abiertos PJ](https://datosabiertospj.poder-judicial.go.cr/dataset/estadisticas-policiales)) | Frecuencia y tipo de delitos por cantón | CSV, URL directa a Azure Blob | Persona A |
| 2 | **COSEVI** | Accidentabilidad vial (muertes, lesiones) por ruta/cantón | Pendiente verificar portal | Persona B |
| 3 | **SNIT** ([SNITCR](https://www.snitcr.go.cr/ico_servicios_ogc)) | Límites cantonales | ArcGIS FeatureServer / WFS → GeoJSON | Persona C |
| 4 | **OpenStreetMap / Overpass** ([wiki](https://wiki.openstreetmap.org/wiki/Overpass_API)) | Hospitales, clínicas, comisarías | Overpass QL → JSON | Persona D |

> **Importante**: antes de implementar un conector, **verificar en vivo** que el
> endpoint/portal sigue funcionando y documentar la fecha de verificación en el
> README.

---

## 3. Arquitectura

```
Fuentes OSINT (OIJ, COSEVI, SNIT, OSM/Overpass)
        │
        ▼
  Workers de ingesta (Python - workers/fuente)
   - normalizan cada fuente a un modelo común
   - guardan fuente y fecha de obtención
        │
        ▼
   PostgreSQL + PostGIS (seguridad_vial_db)
        │
        ▼
   API NestJS (backend/)
   - un módulo por fuente (4 módulos, 1 por integrante)
   - un módulo de cruce que combina las 4 en un endpoint
        │
        ▼
   Frontend: React + TypeScript
   - mapa interactivo (Leaflet)
   - capas togglables + panel de filtros
```

**Regla de oro**: el backend consume y normaliza las fuentes; el frontend
**nunca** llama directo a las APIs externas.

### Stack

- Backend: **NestJS** + TypeScript + TypeORM
- Workers/ETL: **Python** (scripts standalone) para OIJ CSV, COSEVI, WFS→GeoJSON
- Base de datos: **PostgreSQL + PostGIS** (geometrías)
- Caché (futuro): **Redis** para Overpass y SNIT
- Frontend: **React + TypeScript**, Vite, Leaflet, Recharts/Chart.js (gráficos)

---

## 4. Modelo de datos

```sql
canton (id, nombre, provincia, geom [PostGIS, de SNIT])
delito (id, canton_id, tipo, fecha, cantidad, fuente='OIJ', fecha_obtencion)
accidente (id, canton_id, tipo, fecha, muertes, lesionados, fuente='COSEVI', fecha_obtencion)
infraestructura (id, canton_id, tipo['hospital','clinica','comisaria'], nombre, lat, lon, fuente='OSM', fecha_obtencion)

-- endpoint calculado:
indice_cobertura(canton_id) =
  combina delito + accidente + distancia mínima a infraestructura cercana
```

Cada tabla debe guardar `fuente` y `fecha_obtencion` (requisito explícito del profe).

---

## 5. Módulos backend — asignación

| Módulo | Persona | Endpoint | Descripción |
|--------|---------|----------|-------------|
| `modules/oij` | A | `GET /api/delitos?canton=&tipo=&desde=&hasta=` | ✅ **Ya implementado** |
| `modules/cosevi` | B | `GET /api/accidentes?canton=&ruta=` | 🔴 **Pendiente** |
| `modules/snit` | C | `GET /api/cantones` | ✅ **Ya implementado** |
| `modules/osm` | D | `GET /api/infraestructura?canton=&tipo=` | 🔴 **Pendiente** |
| `modules/cruce` | Todos | `GET /api/cantones/:id/panorama` | 🔴 **Pendiente** |

Cada módulo debe manejar errores cuando la fuente externa no responda (timeout,
503, formato inesperado) con un estado claro, no romper el sistema completo.

---

## 6. Ruta de trabajo sugerida

### Fase 1 — Base (ya completada)
- [x] Scaffolding monorepo (`backend/`, `frontend/`, `workers/`)
- [x] Modelo de datos y migraciones (001_cantones, 002_delitos)
- [x] Módulo SNIT (cantones + geometría) completo
- [x] Módulo OIJ (delitos) completo
- [x] Frontend con mapa base + capa de cantones + filtros

### Fase 2 — Fuentes restantes (siguiente sprint)
- [ ] **COSEVI (Persona B)**: verificar portal en vivo → crear worker +
      módulo NestJS + migración `003_create_accidentes.sql`
- [ ] **OSM/Overpass (Persona D)**: worker que consulta Overpass por cantón →
      módulo NestJS + migración `004_create_infraestructura.sql`

### Fase 3 — Cruce (feature principal)
- [ ] Endpoint `GET /api/cantones/:id/panorama` que combine las 4 fuentes
      + índice de cobertura calculado (distancia mínima a infraestructura)
- [ ] Filtro demostrable: "cantones con delitos+accidentes > X, a más de Y km
      del hospital más cercano"

### Fase 4 — Frontend avanzado
- [ ] Capa heatmap de delitos
- [ ] Capa de marcadores de infraestructura por tipo
- [ ] Gráficos (series temporales por cantón) con Recharts
- [ ] Pipe de despliegue (Vercel/Railway/etc.)

### Fase 5 — Pulido para la rúbrica
- [ ] Verificar que cada respuesta de API incluya `fuente` y `fecha_obtencion`
- [ ] Testear el flujo de error (fuente caída, timeout)
- [ ] Revisar README y mantenerlo actualizado

---

## 7. Buenas prácticas para el equipo

1. **Nunca** commitear `.env` con credenciales reales (está en `.gitignore`).
2. Documentar en el README: fuente, endpoint/mecanismo, fecha de verificación,
   y responsable de cada integración.
3. Antes de mergear, correr: `npm run build` (backend y frontend) para verificar
   que compila.
4. Respetar límites de Overpass: implementar caché (Redis o en-memoria).
5. Usar commits descriptivos y en español.
6. Actualizar el README al completar cada tarea marcada como pendiente.

---

## 8. Rúbrica de evaluación (5% de la nota)

| Criterio | Qué se espera | Valor |
|---|---|---|
| Integración y consumo de fuentes OSINT | Cada integrante aporta una fuente; consumo real y transformación | 2% |
| Sistema web funcional | Interfaz funcional y presentación útil | 1.5% |
| Calidad técnica y GitHub | Organización, README, configuración y repo comprensible | 0.5% |
| Exposición y demostración | Explicación de fuentes, arquitectura y funcionamiento | 1% |

---

## 9. Decisiones técnicas ya tomadas (para no repetirlas)

- **SNIT desactualizado**: el FeatureServer de Cantones no incluye cantones
  post-2015 (Sarchí, Río Cuarto, Quepos, Monteverde, Puerto Jiménez). Se crearon
  con códigos DTA 2022 pero **sin geometría**. Si alguien encuentra una capa
  oficial vigente, actualizar el worker y hacer el backfill de geometrías.
- **PostGIS**: se instaló el bundle 3.6.1 para PostgreSQL 16. Documentado en
  README para otros integrantes.
- **Overpass** desde red local dio 406/timeout. El módulo queda para Fase 2;
  respetar User-Agent identificado.
- **Alias de cantones OIJ**: normalización + mapeos para `LEÓN CORTÉS`,
  `VÁSQUEZ DE CORONADO`. El único nombre sin cruzar es `DESCONOCIDO`.
- **Correlación ≠ causalidad**: la UI lo indica explícitamente.