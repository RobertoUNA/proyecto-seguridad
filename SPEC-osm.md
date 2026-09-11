# Spec: Módulo OSM/Overpass de infraestructura

## Objetivo

Incorporar infraestructura de atención (hospitales, clínicas, comisarías) desde
OpenStreetMap al backend, como insumo del futuro índice de cobertura de
`/api/cantones/:id/panorama`. El worker consulta Overpass API en tiempo real,
cruza cada punto contra la geometría cantonal de SNIT (PostGIS) y guarda los
resultados normalizados con `fuente` y `fecha_obtencion`.

## Fuente y alcance

- Fuente: OpenStreetMap vía Overpass API (`overpass-api.de`), consulta real, sin API key.
- Categorías cubiertas: `amenity=hospital`, `amenity=clinic`, `amenity=police`
  (hospitales, clínicas, comisarías) — lo que el README original y el plan del
  proyecto piden para el índice de cobertura ante emergencias.
- Consulta a nivel país (`area["ISO3166-1"="CR"][admin_level=2]`) en una sola
  petición por instancia, en vez de iterar por cantón: una consulta pesada es
  más respetuosa del fair-use de Overpass que 84 consultas pequeñas.
- El mirror `overpass.kumi.systems` es un fallback automático si la instancia
  oficial falla tras agotar reintentos; no se usa por defecto.

## Por qué el bloqueo original ya no reproduce

El README documentaba rechazo (406/timeout) desde esta red. Un diagnóstico
aislado previo a este módulo (una consulta mínima contra `overpass-api.de`,
descartado una vez confirmado el resultado) mostró que la causa más probable
era la falta de un `User-Agent` identificable: Overpass es estricto con
peticiones anónimas o mal identificadas bajo su política de uso. Con
`User-Agent: ProyectoSeguridadVialUNA/1.0 (contacto: <email>)`,
`overpass-api.de` respondió `HTTP 200` en ~1s con datos reales, sin necesitar
el mirror. El propio `fetch_infraestructura.py` reproduce esta verificación
en cada corrida (reintentos + fallback), así que no se mantiene un script de
diagnóstico aparte. Se deja documentado por si el bloqueo reaparece en otra
red o en CI.

## Cruce geográfico: por qué no se reutiliza la tabla de alias de OIJ/COSEVI

OIJ y COSEVI reciben el nombre del cantón como texto en su fuente (CSV), por
lo que necesitan normalizar acentos/mayúsculas y mapear alias (`LEÓN CORTÉS`
→ `LEÓN CORTÉS CASTRO`, etc.). Overpass, en cambio, entrega coordenadas
(lat/lon) por elemento, no nombres de cantón confiables (los tags de
dirección de OSM son opcionales y poco consistentes en Costa Rica). Por eso
el cruce geográfico se hace con PostGIS (`ST_Contains(canton.geom, punto)`)
directamente en el `INSERT`, más preciso que un cruce por nombre y sin
reintroducir una tabla de alias donde no aplica.

## Contrato HTTP

- `GET /api/infraestructura?canton&tipo`: hasta 1,000 registros y resumen.
  `tipo` acepta `hospital`, `clinica` o `comisaria`.
- `GET /api/infraestructura/por-canton?canton&tipo`: FeatureCollection con
  `total_infraestructura`, `hospitales`, `clinicas` y `comisarias` por
  cantón — insumo directo del índice de cobertura de `/panorama`.

Los filtros inválidos devuelven `400`. Las respuestas incluyen
`X-Data-Source: OSM/Overpass` y `X-Fetch-Date`.

## Datos y seguridad

- Clave natural: `(osm_type, osm_id)`, el identificador estable que entrega
  OSM, usado en el `ON CONFLICT` del upsert — a diferencia de OIJ/COSEVI, que
  agregan por combinaciones de campos porque su fuente no trae un ID único.
- El worker no arma SQL a partir de tags de OSM; todo valor va parametrizado.
- `OSM_CONTACT_EMAIL` es público (viaja en el `User-Agent` hacia Overpass) y
  no es secreto, pero vive en `.env`/`.env.example` para poder rotarlo sin
  tocar código.
- No se guardan datos personales: solo ubicación y nombre público de
  instalaciones, ya públicos en el propio dataset de OSM.

## Limitaciones de Overpass (documentadas para el equipo)

1. **Rate limits**: Overpass limita peticiones concurrentes y consultas
   pesadas por IP/User-Agent. El worker hace una sola consulta país-completo
   por corrida (no un loop por cantón) y no debe programarse en un cron
   agresivo sin caché delante.
2. **Necesidad de caché**: como señala el README, falta Redis (u otro caché)
   delante de este worker para no volver a golpear Overpass en cada carga del
   frontend. Mientras tanto, la propia tabla `infraestructura` en PostgreSQL
   actúa como caché: el worker se corre manualmente o en un cron espaciado
   (p. ej. diario), nunca por request.
3. **Cobertura dependiente de la comunidad**: OSM es un mapa colaborativo;
   zonas rurales pueden tener menos hospitales/clínicas/comisarías mapeadas
   de las que existen en realidad. El índice de cobertura debe leerse como
   "cobertura mapeada en OSM", no como inventario oficial exhaustivo.
4. **Reintentos, no evasión**: ante error de red, HTTP 5xx o 429, el worker
   reintenta con backoff exponencial (máximo 3 intentos por instancia) y
   luego cae al mirror; nunca reintenta en loop agresivo ni ignora un 429.

## Comandos

```powershell
python -m pip install -r workers\osm\requirements.txt
python workers\osm\fetch_infraestructura.py
cd backend
npm.cmd run db:migrate
npm.cmd run build
```

## Éxito verificable

- El worker trae elementos reales de Overpass (verificado con una corrida
  real del worker completo).
- La migración crea la tabla `infraestructura` y sus índices idempotentemente.
- El backend compila.
- Los dos endpoints responden contra PostgreSQL tras ejecutar la ingesta.
- El mapa podrá sumar la capa OSM sin mezclar métricas de OIJ/COSEVI.
