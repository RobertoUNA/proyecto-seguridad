# Health Checks, Smoke Tests Post-Despliegue y Procedimiento de Recuperación — Etapa 6 (`Ítems 6.1, 6.5 y 6.6`)

> **Responsable Principal:** Roberto (`RobertoUNA`)  
> **Revisor:** Brandon Corrales (`Brandon-Corrales`)  
> **Archivos Implementados:**  
> - Endpoint de Salud: [`backend/src/modules/health/health.controller.ts`](../../backend/src/modules/health/health.controller.ts), [`health.service.ts`](../../backend/src/modules/health/health.service.ts), [`health.module.ts`](../../backend/src/modules/health/health.module.ts)  
> - Smoke Tests: [`scripts/smoke-test.ps1`](../../scripts/smoke-test.ps1), [`scripts/smoke-test.sh`](../../scripts/smoke-test.sh)  
> - Recuperación / Rollback: [`scripts/rollback.ps1`](../../scripts/rollback.ps1), [`scripts/rollback.sh`](../../scripts/rollback.sh), [`deploy/last-approved-release.json`](../../deploy/last-approved-release.json)  
> - Workflow Automatizado: [`.github/workflows/deploy-verify.yml`](../../.github/workflows/deploy-verify.yml)

---

## 1. Endpoint de Health Check (`GET /api/health`)

Se implementó el módulo `HealthModule` en NestJS para comprobar en tiempo real la salud del servicio desplegado y su conectividad con PostgreSQL/PostGIS:
- Ejecuta la consulta `SELECT 1 AS ok, PostGIS_Version() AS postgis_version` sobre el `DataSource` activo.
- Si la base de datos responde correctamente, devuelve `HTTP 200 OK` con las cabeceras estándar del proyecto (`X-Data-Source: INTERNAL/HEALTH`, `X-Fetch-Date`) y el estado detallado (`status: "ok"`, `database.status: "up"`, `postgis_version`, `version`, `commit_sha`, `uptime_seconds`).
- Si la conexión a la base de datos falla, devuelve `HTTP 503 Service Unavailable` sin exponer credenciales ni trazas internas.

---

## 2. Automatización de Comprobaciones Posteriores al Despliegue (`Ítem 6.5`)

Los scripts [`scripts/smoke-test.ps1`](../../scripts/smoke-test.ps1) (Windows/PowerShell) y [`scripts/smoke-test.sh`](../../scripts/smoke-test.sh) (Linux/GitHub Actions) ejecutan **8 comprobaciones automatizadas** contra la instancia recién desplegada y generan un reporte JSON auditable (`reports/smoke-test-<sha>-<timestamp>.json` por defecto cuando no se pasa `-ReportPath`, o la ruta indicada explícitamente, evitando sobrescribir la evidencia versionada [`reports/smoke-test-report.json`](../../reports/smoke-test-report.json)).

Cada reporte JSON generado registra la versión verificada mediante `commit_sha` (extraído en vivo de `GET /api/health` con respaldo en `COMMIT_SHA`/Git SHA), `health_commit_sha`, `app_version` e `image_digest` (`DEPLOYED_IMAGE_DIGEST` cuando proviene de contenedor o `no-aplica` en ejecuciones desde código fuente).

| # | Comprobación | Ruta Evaluada | Resultado Esperado | Flujo / Riesgo Cubierto |
| :---: | :--- | :--- | :--- | :--- |
| 1 | **Health Check & PostGIS** | `GET /api/health` | `200 OK`, `database.status == "up"` y cabeceras `X-Data-Source` / `X-Fetch-Date` | Disponibilidad de API y extensión espacial PostGIS (`FLOW-01..03`). |
| 2 | **Capa Cantonal SNIT** | `GET /api/cantones` | `200 OK`, `FeatureCollection` con polígonos cantonales | Integridad de la capa geográfica base (`FLOW-01`). |
| 3 | **Catálogo OIJ** | `GET /api/delitos/tipos` | `200 OK`, lista JSON de tipos de delito | Disponibilidad del módulo OIJ (`FLOW-02`). |
| 4 | **Catálogo COSEVI** | `GET /api/accidentes/tipos` | `200 OK`, lista JSON de tipos de accidente | Disponibilidad del módulo COSEVI (`FLOW-02`). |
| 5 | **Cobertura OSM** | `GET /api/infraestructura/por-canton` | `200 OK`, `FeatureCollection` de infraestructura | Disponibilidad del módulo OSM/Overpass (`FLOW-02`). |
| 6 | **Flujo Crítico de Cruce** | `GET /api/cantones/1001/panorama` | `200 OK`, `Feature` de San José con `indice_cobertura` en `[0..100]` | Cruce de las 4 fuentes OSINT (`FLOW-01`). |
| 7 | **Rechazo Funcional Esperado** | `GET /api/cantones/999999/panorama` | `404 Not Found` (nunca `200` ni `500`) | Manejo seguro de recursos inexistentes (`FLOW-01`). |
| 8 | **Rechazo de Seguridad / Validación** | `GET /api/delitos?desde=fecha-invalida` | `400 Bad Request` | Protección contra parámetros malformados (`THR-01` / `CTL-01`). |

---

## 3. Procedimiento de Recuperación / Rollback y Demostración (`Ítem 6.6`)

### 3.1 Identificación de la Versión de Recuperación
El archivo versionado [`deploy/last-approved-release.json`](../../deploy/last-approved-release.json) conserva la identidad de la versión de recuperación base:
- `release_id`: `v1.0.0-rc0-baseline`
- `commit_sha`: `4844d2a`
- `backend_image` y `frontend_image`: actualmente contienen digests de referencia iniciales (`sha256:9e06aae000...0001` y `...0002`), pendientes de sustituirse por los digests reales publicados en `docker.io/elrobb/proyecto-seguridad-{backend,frontend}` cuando el workflow del ítem `5.5` (PR #6) publique desde `main`.
- **Tratamiento de Base de Datos en Rollback:** Todas las migraciones SQL del proyecto (`001` a `004`) son aditivas e idempotentes (`CREATE TABLE IF NOT EXISTS`, `CREATE INDEX IF NOT EXISTS`), por lo que regresar el contenedor backend a la imagen anterior aprobada es directamente compatible sin pérdida de datos ni necesidad de migraciones destructivas (`requires_db_down_migration: false`).

### 3.2 Evidencia de Detección de Fallo, Rollback y Re-verificación

1. **Detección de Fallo Post-Despliegue:** Cuando una comprobación obligatoria falla tras el despliegue, `scripts/smoke-test.ps1` (y el paso `smoke_tests` en `.github/workflows/deploy-verify.yml`) termina con código de salida `1` (`status: "FAILED"`) e impide marcar el despliegue como satisfactorio:
   ```text
   [FAIL] 6. Cruce 4 Fuentes (HTTP 0) - Error o versión degradada detectada.
   ------------------------------------------------------------------
   Reporte guardado en: reports/smoke-test-report.json
   [RESULTADO] FALLO (1 comprobaciones fallaron). Se requiere rollback.
   ```
2. **Ejecución del Rollback y Repetición de Comprobaciones (`scripts/rollback.ps1`):**
   Al dispararse la recuperación (automáticamente en GitHub Actions mediante `if: failure() && steps.smoke_tests.outcome == 'failure'` o localmente con `powershell -File scripts/rollback.ps1`), el script restaura la versión aprobada de `deploy/last-approved-release.json` y repite las 8 comprobaciones básicas:
   ```text
   ==================================================================
    INICIANDO PROCEDIMIENTO DE RECUPERACION / ROLLBACK (Item 6.6)
   ==================================================================
    Motivo del rollback : Simulacion controlada de fallo en version desplegada (Demostracion Item 6.6)
    Version destino     : v1.0.0-rc0-baseline (Commit: 4844d2a)
    Esquema BD          : 004_create_infraestructura.sql (Requiere down-migration: False)

   [2/3] Restaurando artefacto aprobado (v1.0.0-rc0-baseline)...
   [3/3] Repitiendo Health Checks y Smoke Tests posteriores a la recuperacion...
     [PASS] 1. Health Check (/api/health) (HTTP 200) - DB=up, PostGIS=3.6 USE_GEOS=1 USE_PROJ=1 USE_STATS=1
     [PASS] 2. SNIT Cantones (/api/cantones) (HTTP 200) - FeatureCollection con 85 cantones
     [PASS] 3. OIJ Tipos de Delito (/api/delitos/tipos) (HTTP 200)
     [PASS] 4. COSEVI Tipos de Accidente (/api/accidentes/tipos) (HTTP 200)
     [PASS] 5. OSM Infraestructura (/api/infraestructura/por-canton) (HTTP 200)
     [PASS] 6. Cruce 4 Fuentes (/api/cantones/1001/panorama) (HTTP 200) - Cantón=San José, indice_cobertura=89
     [PASS] 7. Rechazo Cantón Inexistente (404 esperado) (HTTP 404)
     [PASS] 8. Rechazo Filtro Fecha Inválida (400 esperado) (HTTP 400)
    [RESULTADO] APROBADO (Todas las 8 comprobaciones pasaron).

   [RECUPERACION EXITOSA] El sistema volvio a la version v1.0.0-rc0-baseline y aprobo las comprobaciones.
   ```
   Los reportes generados quedan guardados en [`reports/smoke-test-report.json`](../../reports/smoke-test-report.json) y [`reports/rollback-evidence.json`](../../reports/rollback-evidence.json).

---

## 4. Limitaciones Conocidas del Alcance (Etapa 6)

1. **Sin despliegue remoto real en infraestructura externa todavía:** [`.github/workflows/deploy-verify.yml`](../../.github/workflows/deploy-verify.yml) compila desde el código fuente y levanta la API localmente en el runner (`http://localhost:3000`) contra un servicio `postgis/postgis:16-3.4` efímero, sin desplegar todavía una imagen por digest hacia un servidor de destino (`6.1` / `6.2` / `6.4`).
2. **Sin pruebas E2E ni DAST en el alcance seleccionado:** El equipo no seleccionó los ítems `4.4` (pruebas E2E en navegador) ni `4.7` (análisis DAST con OWASP ZAP); por ello, la verificación posterior al despliegue se acota a health checks y los 8 smoke tests HTTP/JSON de la API (`6.5`).
3. **Alcance de la simulación de fallo (`simulate_failure`):** Apuntar `smoke-test.sh` al puerto `3999` en `deploy-verify.yml` (o `-SimulateFailureFirst` en `rollback.ps1`) simula un **servicio caído o inalcanzable** para demostrar la detección del fallo y el disparo automático del rollback (`6.6`), no una versión degradada que responda con errores de negocio.
4. **Dependencia de `deploy/docker-compose.prod.yml` y publicación `5.5` para rollback real de contenedores:** Tanto [`scripts/rollback.sh`](../../scripts/rollback.sh) como [`scripts/rollback.ps1`](../../scripts/rollback.ps1) ejecutan `docker compose -f deploy/docker-compose.prod.yml up -d` cuando ese archivo existe y Docker está disponible; mientras no exista `deploy/docker-compose.prod.yml` (`6.2`/`6.4`) ni se hayan publicado las imágenes del `5.5` para sustituir los digests de ejemplo en `deploy/last-approved-release.json`, la demostración repite los smoke tests sobre el entorno local/runner.
