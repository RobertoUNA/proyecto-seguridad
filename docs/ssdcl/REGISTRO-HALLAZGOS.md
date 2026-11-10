# Registro Único de Hallazgos y Excepciones de Seguridad (Etapas 1 a 7)

> **Responsable del Registro Único (`Ítems 5.6, 7.5 y 7.7`):** Billy Ugalde (`Billy-Ugalde`)  
> **Colaborador / Aprobador de Integración:** Roberto (`RobertoUNA`)  
> **Propósito:** Mantener en un único lugar versionado todos los hallazgos detectados durante el ciclo SSDLC y las excepciones temporales vigentes, enlazando amenazas (`THR-xx`), controles (`CTL-xx`), archivos de evidencia y commits correctivos.

---

## 1. Registro de Hallazgos de Seguridad y Calidad (`Ítems 7.5 y 7.7`)

| ID Hallazgo | Origen (Etapa / Herramienta) | Amenaza / Control Relacionado | Alcance / Versión Afectada | Evidencia del Hallazgo | Severidad Justificada | Responsable | Estado | Tratamiento y Verificación de Cierre |
| :--- | :--- | :---: | :--- | :--- | :---: | :---: | :---: | :--- |
| **`HAL-01`** | Etapa 3 (`3.2`) — **OSV-Scanner** (SCA Python) | `THR-05` / `CTL-05` | `workers/{oij,cosevi,snit,osm}/requirements.txt` (`requests 2.31`) | `PYSEC-2026-1872` (`GHSA-9hjg-9r4m-mvj7`), `PYSEC-2026-1873` (`GHSA-9wx4-h78v-vm56`) y `PYSEC-2026-2275` (`GHSA-gc5v-m9x4-r6x2`) detectados al escanear los 4 workers OSINT. | **Media** (CVSS `5.3`–`5.6`: fugas de sesión/cabeceras o validación TLS en `requests`). | **Roberto** (`RobertoUNA`) | 🟢 **Cerrado / Verificado** | Se actualizó `requests>=2.33.0` y `psycopg2-binary>=2.9.10` en los 4 `requirements.txt`. Re-ejecución de `osv-scanner` devuelve `No issues found` (`exit code 0`). Ver [`03-ci-sca-y-proteccion-ramas.md`](./03-ci-sca-y-proteccion-ramas.md). |
| **`HAL-02`** | Etapa 3 (`3.2`) — **OSV-Scanner** / `npm audit` (SCA Frontend) | `THR-05` / `CTL-05` | `frontend/package-lock.json` (`vite`, `source-map-js`) | 7 paquetes con avisos GHSA en el lockfile del frontend (`GHSA-68fv-2mgg-jv7q`, `GHSA-587h-7wmj-h5pm`). | **Alta** (CVSS hasta `8.7` en entorno de desarrollo). | **Roberto** (`RobertoUNA`) | 🟢 **Cerrado / Verificado** | Se ejecutó `npm audit fix` en `frontend/`, actualizando las versiones en `frontend/package-lock.json`. Re-ejecución de `npm audit` y `osv-scanner` reporta `0 vulnerabilities`. |
| **`HAL-03`** | Etapa 2 (`2.3`) — **Semgrep CE & Gitleaks** (Prueba controlada) | `THR-01`, `THR-03` / `CTL-01`, `CTL-03` | `backend/src/modules/oij/defect_demo.temp.ts` (Rama de prueba) | Detección de URI PostgreSQL con contraseña embebida (`postgres-connection-uri-with-password`) e interpolación SQL directa (`ssdcl-ts-raw-sql-interpolation`). | **Alta / Crítica** (`CWE-89` y `CWE-798`). | **Roberto** (`RobertoUNA`) | 🟢 **Cerrado / Verificado** | Eliminación del defecto controlado y validación con `python scripts/sast-check.py` (`0 findings`) y `gitleaks dir .` (`no leaks found`). Ver [`02-analisis-estatico-secretos.md`](./02-analisis-estatico-secretos.md). |

---

## 2. Registro de Excepciones de Seguridad Abiertas (`Ítems 5.2 y 5.6`)

> **Regla de gobernanza:** Toda excepción temporal requiere justificación técnica, responsable proponente, aprobación humana de otro integrante revisor y fecha de vencimiento/revisión explícita en [`osv-scanner.toml`](../../osv-scanner.toml).

| ID Excepción | Hallazgo / Regla Asociada | Versión / Alcance Afectado | Evidencia | Justificación Técnica y Mitigación Compensatoria | Responsable | Aprobador Humano (Revisor) | Estado | Fecha de Vencimiento / Revisión |
| :--- | :--- | :--- | :--- | :--- | :---: | :---: | :---: | :---: |
| **`EXC-01`** | Avisos SCA en dependencias transitivas de `@nestjs/platform-express` v10 (`multer`, `file-type`, `body-parser`, `qs`, `lodash`, `uuid`) | `backend/package-lock.json` (`@nestjs/core ^10.4.0`) | Salida de `osv-scanner` y configuración en [`osv-scanner.toml`](../../osv-scanner.toml) | La API del Observatorio expone **únicamente endpoints `GET` de solo lectura**; no utiliza subida de archivos (`multer`), no procesa archivos ZIP/ASF (`file-type`), no recibe cuerpos `POST` comprimidos (`body-parser`) ni invoca `_.template` (`lodash`). Actualizar a `@nestjs/core` v12 requiere migración mayor de framework. | **Roberto** (`RobertoUNA`) | **Billy Ugalde** (`Billy-Ugalde`) | 🟡 **Excepción Vigente** | `2026-12-15` |
| **`EXC-02`** | Avisos SCA en dependencias exclusivas de compilación de `@nestjs/cli` (`ajv`, `deepmerge`, `glob`, `minimatch`, `picomatch`, `tmp`, `webpack`) | `backend/package-lock.json` (`devDependencies`) | Salida de `osv-scanner` y configuración en [`osv-scanner.toml`](../../osv-scanner.toml) | Son paquetes exclusivos de tiempo de construcción (`nest build`) que operan únicamente sobre el código fuente local del repositorio y no forman parte de la ejecución del servidor en producción. | **Roberto** (`RobertoUNA`) | **Billy Ugalde** (`Billy-Ugalde`) | 🟡 **Excepción Vigente** | `2026-12-15` |
