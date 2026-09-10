# Spec: Módulo COSEVI de accidentes

## Objetivo

Incorporar accidentes de tránsito con víctimas de COSEVI al backend. El worker descarga el CSV oficial consolidado, valida sus columnas y guarda datos agregados por cantón, distrito, año, clase y tipo de accidente. La API permite consultarlos y obtener totales GeoJSON por cantón.

## Fuente y alcance

- Fuente: CSV oficial "Consolidado de accidentes de tránsito con víctimas" de COSEVI (periodo publicado 2018-2024).
- No se usa la API de Junar porque exige una clave de API; el worker usa la descarga pública del dataset.
- El frontend permite elegir COSEVI u OIJ como capa activa. OSM queda indicado como pendiente, no se simula como disponible.

## Contrato HTTP

- `GET /api/accidentes?canton&anio&clase&tipo`: hasta 1,000 agregados y resumen.
- `GET /api/accidentes/por-canton?anio&clase&tipo`: FeatureCollection con `total_accidentes`, `clases_distintas` y `tipos_distintos`.
- `GET /api/accidentes/tipos`: tipos disponibles.
- `GET /api/accidentes/clases`: clases disponibles.

Los filtros inválidos devuelven `400`. Las respuestas incluyen `X-Data-Source: COSEVI`.

## Datos y seguridad

- La ingesta rechaza un CSV sin las columnas requeridas y no ejecuta SQL a partir de nombres de columnas.
- El worker lee la configuración de PostgreSQL desde variables de entorno; como conveniencia local carga `backend/.env` si existe, sin sobrescribir variables ya definidas.
- No se guardan datos personales: solo agregados territoriales y categóricos.

## Comandos

```powershell
python -m pip install -r workers\cosevi\requirements.txt
python workers\cosevi\fetch_accidentes.py
cd backend
npm.cmd run db:migrate
npm.cmd run build
```

## Éxito verificable

- El worker valida y procesa el CSV oficial descargado.
- La migración crea la tabla `accidente` y sus índices idempotentemente.
- El backend compila.
- Los cuatro endpoints responden contra PostgreSQL tras ejecutar la ingesta.
- El mapa cambia entre totales OIJ y COSEVI sin mezclar métricas.
