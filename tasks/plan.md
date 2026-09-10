# Implementation Plan: COSEVI backend

## Overview

Agregar una ruta vertical completa desde el CSV oficial de COSEVI hasta endpoints REST y una capa seleccionable en el frontend.

## Arquitectura

`CSV oficial COSEVI -> worker Python validado -> accidente (PostgreSQL) -> módulo NestJS -> /api/accidentes -> capa COSEVI`

El worker agrega registros por cantón, distrito, año, clase y tipo; la API suma esos agregados para el mapa cantonal.

## Task List

1. Fundación: migración, entidad y prueba del parser del CSV.
2. Ingesta: worker que descarga, valida, normaliza y hace upsert.
3. Consulta: servicio/controlador NestJS con filtros y resumen GeoJSON.
4. Capa: selector accesible y mapa para alternar OIJ/COSEVI.
5. Verificación: migración, worker con fuente real, builds y endpoints locales.

## Risks and mitigations

| Riesgo | Mitigación |
| --- | --- |
| Cambio de columnas COSEVI | Validación explícita y mensaje de error accionable. |
| Cantón no presente en SNIT | Se conserva agregado con `canton_id` nulo y se reporta. |
| Fuente no disponible | URL configurable por `COSEVI_CSV_URL`; no se borra información existente. |
