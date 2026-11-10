# Pipeline de Integración Continua (CI), Análisis SCA y Protección de Ramas — Etapa 3 (`Ítems 3.1, 3.2, 3.5 y 3.6`)

> **Responsable Principal:** Roberto (`RobertoUNA`)  
> **Revisores:** Billy Ugalde (`Billy-Ugalde`) en `3.1`/`3.6` y Jose Picado (`Jose-Picado-Zamora`) en `3.2`  
> **Archivos Implementados:** [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml), [`osv-scanner.toml`](../../osv-scanner.toml), [`backend/database/seed_test.sql`](../../backend/database/seed_test.sql)

---

## 1. Arquitectura del Pipeline en GitHub Actions (`Ítem 3.1`)

El workflow [`.github/workflows/ci.yml`](../../.github/workflows/ci.yml) se dispara automáticamente en cada `pull_request` y `push` hacia las ramas `main` y `development`. Se divide en dos jobs obligatorios paralelos:

### Job 1: `quality-and-tests` (`3.1 Calidad, Build, Pruebas y Ambiente Aislado`)
1. **Ambiente aislado de base de datos con datos ficticios:** Levanta un contenedor de servicio `postgis/postgis:16-3.4` (`seguridad_vial_test`) con credenciales efímeras exclusivas de CI (`test_pass_isolated_ci`).
2. **Instalación determinista con lockfiles:** Ejecuta `npm ci` tanto en `backend/` como en `frontend/` utilizando `package-lock.json`, e instala las dependencias de los workers Python (`requirements.txt`).
3. **Verificaciones de calidad y compilación:**
   - Linter de frontend (`npm run lint` con `oxlint`) y backend (`npm run lint --if-present`).
   - Compilación TypeScript estricta (`npm run build` en `frontend` y `backend`).
   - Pruebas unitarias (`python -m unittest discover -s workers/cosevi -p "test_*.py" -v` y `npm test --if-present`).
4. **Migraciones, carga de semilla controlada y verificación en vivo:**
   - Aplica las 4 migraciones SQL (`001` a `004`) y carga [`backend/database/seed_test.sql`](../../backend/database/seed_test.sql) con datos sintéticos de 3 cantones (`1001 San José`, `2001 Alajuela`, `3001 Cartago`).
   - Levanta el backend compilado y ejecuta [`scripts/smoke-test.sh`](../../scripts/smoke-test.sh) comprobando las 8 verificaciones de API.
5. **Limpieza y artefactos:** Ejecuta `TRUNCATE TABLE ... RESTART IDENTITY CASCADE` al finalizar (`if: always()`) y publica el reporte JSON como artefacto asociado al SHA del commit (`quality-and-smoke-reports-${{ github.sha }}`).

---

## 2. Análisis de Código, Secretos y Dependencias en CI (`Ítem 3.2`)

El Job 2 (`security-sast-secrets-sca`) reutiliza las configuraciones creadas en Desarrollo (`2.3`) e incorpora el Análisis de Composición de Software (SCA) con **OSV-Scanner**:

| Herramienta | Tipo | Configuración Utilizada | Qué Analiza en CI | Condición de Bloqueo (`exit code != 0`) | Artefacto Generado |
| :--- | :---: | :--- | :--- | :--- | :--- |
| **Semgrep CE** | SAST | [`.semgrep.yml`](../../.semgrep.yml) + [`scripts/sast-check.py`](../../scripts/sast-check.py) | `backend/src`, `frontend/src`, `workers/` | Cualquier hallazgo de severidad `ERROR` (`--error`) o fallo de ejecución detiene el job. | `reports/semgrep-<sha>.json` |
| **Gitleaks** | Secretos | [`.gitleaks.toml`](../../.gitleaks.toml) | Árbol de archivos (`dir`) e historial de commits (`git` con `fetch-depth: 0`) | Cualquier secreto detectado (`--exit-code 1`) bloquea inmediatamente el PR. | `reports/gitleaks-dir-<sha>.json`, `reports/gitleaks-git-<sha>.json` |
| **OSV-Scanner** | SCA | [`osv-scanner.toml`](../../osv-scanner.toml) | `backend/package-lock.json`, `frontend/package-lock.json`, `workers/{oij,cosevi,snit,osm}/requirements.txt` | Cualquier vulnerabilidad conocida (CVE/GHSA/PYSEC) no cubierta por una excepción vigente y revisada devuelve código `1`. | `reports/osv-scanner-<sha>.json` |

### 2.1 Evidencia de Ejecución y Remediación SCA con OSV-Scanner

Durante la primera ejecución de `osv-scanner` sobre los 6 manifiestos/lockfiles del proyecto:
1. **Hallazgo detectado y corregido en `workers/*/requirements.txt` (`HAL-01`):**
   - `osv-scanner` detectó 3 vulnerabilidades en `requests 2.31` (`PYSEC-2026-1872` / `GHSA-9hjg-9r4m-mvj7`, `PYSEC-2026-1873` / `GHSA-9wx4-h78v-vm56` y `PYSEC-2026-2275` / `GHSA-gc5v-m9x4-r6x2`).
   - **Corrección aplicada:** Se actualizaron los 4 archivos `workers/{oij,cosevi,snit,osm}/requirements.txt` a `requests>=2.33.0` y `psycopg2-binary>=2.9.10`.
2. **Hallazgo detectado y corregido en `frontend/package-lock.json` (`HAL-02`):**
   - `osv-scanner` detectó vulnerabilidades en `vite` y `source-map-js`.
   - **Corrección aplicada:** Se ejecutó `npm audit fix` en `frontend/`, actualizando 7 paquetes y reduciendo a **0 vulnerabilidades** el frontend.
3. **Gestión de Excepciones Temporales en `backend/package-lock.json` (`EXC-01` y `EXC-02`):**
   - Las dependencias transitivas de `@nestjs/platform-express` v10 (`multer`, `file-type`, `body-parser`) y de `@nestjs/cli` (tiempo de compilación) requieren migrar a NestJS v12 (cambio disruptivo mayor). Dado que la API pública expone exclusivamente endpoints `GET` sin subida de archivos, se registraron las excepciones `EXC-01` y `EXC-02` en [`osv-scanner.toml`](../../osv-scanner.toml) y en [`docs/ssdcl/REGISTRO-HALLAZGOS.md`](./REGISTRO-HALLAZGOS.md) con vencimiento `2026-12-15`.

**Salida verificada tras la remediación:**
```text
Scanned backend\package-lock.json file and found 417 packages
Scanned frontend\package-lock.json file and found 75 packages
Scanned workers\oij\requirements.txt file and found 2 packages
Scanned workers\cosevi\requirements.txt file and found 2 packages
Scanned workers\snit\requirements.txt file and found 2 packages
Scanned workers\osm\requirements.txt file and found 2 packages
Filtered 33 vulnerabilities from output
No issues found
OSV_EXIT_CODE=0
```

---

## 3. Protección de Ramas y Endurecimiento del Pipeline (`Ítem 3.5`)

1. **Permisos mínimos del `GITHUB_TOKEN`:** Ambos workflows declaran en el nivel superior:
   ```yaml
   permissions:
     contents: read
   ```
   Esto garantiza que el token efímero de GitHub Actions sea de solo lectura y no pueda modificar ramas protegidas, crear releases no autorizados ni aprobar PRs.
2. **Fijación de Acciones de Terceros mediante SHA completo (Supply Chain Security):**
   - `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683 # v4.2.2`
   - `actions/setup-node@39370e3970a6d050c480ffad4ff0ed4d3fdee5af # v4.1.0`
   - `actions/setup-python@0b93645e9fea7318ecaed2b359559ac225c90a2b # v5.3.0`
   - `actions/upload-artifact@b4b15b8c7c6ac21ea08fcf65892d2ee8f75cf882 # v4.4.3`
3. **Reglas de Branch Protection en GitHub (`main` y `development`):**
   - *Require a pull request before merging* → Activado (`Require approvals: 1`, *Dismiss stale pull request approvals when new commits are pushed*).
   - *Require status checks to pass before merging* → Activado con los checks obligatorios:
     - `3.1 Calidad, Build, Pruebas y Ambiente Aislado`
     - `3.2 Seguridad: Semgrep CE, Gitleaks y OSV-Scanner`
   - *Do not allow bypassing the above settings* → Activado para impedir que el agente o un push directo omita las revisiones.

---

## 4. Demostración de Bloqueo de Integración en PR (`Ítem 3.6`)

Para reproducir y verificar el bloqueo de un Pull Request en GitHub Actions aunque se omitan las verificaciones locales (`git commit --no-verify`):
1. En una rama de prueba, se introduce un hallazgo controlado (ej. el defecto SAST o el secreto ficticio documentado en el `Ítem 2.3`, o una dependencia vulnerable sin excepción).
2. Al abrir el PR hacia `main`/`development`, el job `3.2 Seguridad: Semgrep CE, Gitleaks y OSV-Scanner` termina con `exit code 1` y GitHub bloquea el botón **Merge pull request**.
3. Los reportes detallados (`semgrep-<sha>.json`, `gitleaks-dir-<sha>.json`, `osv-scanner-<sha>.json`) quedan adjuntos en la sección **Artifacts** de la ejecución del workflow.
4. Al subir el commit correctivo a la misma rama, ambos jobs pasan a estado verde (`Succeeded`) y, tras la aprobación del compañero Revisor, se habilita la fusión.
