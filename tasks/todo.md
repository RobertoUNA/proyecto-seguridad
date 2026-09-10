# COSEVI tasks

- [ ] Fundación: crear tabla `accidente`, entidad y prueba del parser.
  - Acceptance: el parser reconoce el CSV oficial y agrega filas repetidas.
  - Verify: `python -m unittest workers/cosevi/test_fetch_accidentes.py`.
- [ ] Ingesta: implementar worker COSEVI.
  - Acceptance: valida columnas, vincula cantones y hace upsert idempotente.
  - Verify: ejecutar contra el CSV oficial.
- [ ] API: implementar `/api/accidentes`.
  - Acceptance: filtros y GeoJSON cantonal devuelven respuestas consistentes.
  - Verify: `npm.cmd run build` y solicitudes locales.
- [ ] Capa: integrar selector OIJ/COSEVI sin alterar datos de la otra fuente.
  - Acceptance: el mapa y detalle muestran la métrica de la fuente seleccionada.
  - Verify: `cd frontend; npm.cmd run build`.
