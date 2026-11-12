# Evidencia de Contenedores: Trivy, SBOM y Políticas Conftest (Etapa 3)

> **Ítems:** `3.3` (imagen candidata, Trivy y SBOM) · `3.4` (políticas Conftest + OPA/Rego)  
> **Responsable:** Brandon Corrales (`Brandon-Corrales`) · **Revisores:** Roberto (`3.3`), Billy (`3.4`)  
> **Amenaza / control:** [`THR-05` / `CTL-05`](./01-planificacion-kb.md#3-amenazas-priorizadas-con-stride-ítem-13-y-plan-de-tratamiento-ítem-14) (Elevation of Privilege: contenedor como root, modo privilegiado o CVE conocidas). También apoya `THR-03` / `CTL-03` (sin secretos en imágenes ni en `docker-compose.yml`).  
> **Commit analizado en esta evidencia:** `f045577b963deb228642ebf36963f39fb400fe2c`

---

## 3.3 — Construcción y análisis de la imagen candidata

### Archivos del ítem

| Archivo | Propósito |
| :--- | :--- |
| [`backend/Dockerfile`](../../backend/Dockerfile) | Multi-stage `node:22-alpine` fijada por digest. `build`: `npm ci` + `nest build`. `runtime`: `npm ci --omit=dev` + `dist/`, sin npm/npx/corepack/yarn, `USER node`, `NODE_ENV=production`, `EXPOSE 3000`, `HEALTHCHECK` con `wget` contra `/api/health`. |
| [`frontend/Dockerfile`](../../frontend/Dockerfile) | `build` con `node:22-alpine`; `runtime` con `nginxinc/nginx-unprivileged:alpine` fijada por digest, `apk upgrade`, sin `curl`, `USER 101`, puerto `8080`. |
| [`frontend/nginx.conf`](../../frontend/nginx.conf) | Sirve la SPA, hace proxy de `/api/` a `backend:3000`, `server_tokens off` y cabeceras `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`. |
| [`backend/.dockerignore`](../../backend/.dockerignore), [`frontend/.dockerignore`](../../frontend/.dockerignore) | Excluyen `node_modules`, `dist`, `.env*`, `.git`, `reports`, `coverage` del contexto de build. |
| [`docker-compose.yml`](../../docker-compose.yml) | Proyecto `proyecto-seguridad`: `db` (PostGIS), `backend`, `frontend`. Detalle en la tabla de configuración segura. |
| [`scripts/container-scan.ps1`](../../scripts/container-scan.ps1), [`scripts/container-scan.sh`](../../scripts/container-scan.sh) | Build + Trivy `config` + Trivy `image` + SBOM CycloneDX para un SHA. Equivalentes (Windows / Linux-CI). |
| [`.github/workflows/container-supply-chain.yml`](../../.github/workflows/container-supply-chain.yml) | Workflow nuevo (no se modifica `ci.yml`): ejecuta el mismo script en `pull_request` y `push` a `main`/`development` y sube el artefacto `container-reports-<sha>`. |

### Imágenes base fijadas por digest (consultadas el 2026-11-11)

| Etiqueta | Digest | Uso |
| :--- | :--- | :--- |
| `node:22-alpine` (Node v22.23.5) | `sha256:5b05da3f938f1c604b24c633646d48805a6667f378cb4908438616f3cc48a0bf` | build backend/frontend y runtime backend |
| `nginxinc/nginx-unprivileged:alpine` (nginx 1.31.7, Alpine 3.24.2) | `sha256:b5047b9b76845eac124358373c6852377c52e4b05834a47647e955dd91cb8f1e` | runtime frontend |
| `postgis/postgis:16-3.4` | `sha256:44126d872ac91993766c341e369c539e8196614321765d36a6f1bab0419a5fa5` | BD en `docker-compose.yml` |
| `aquasec/trivy:0.76.2` | `sha256:8f6bb947dbc528902e11f2f5be52f7b519f6a39d5d148f41166f2040499768fb` | escáner (no se instala en el sistema) |

Obtenidos con `docker pull <imagen>` + `docker inspect --format '{{index .RepoDigests 0}}' <imagen>`. Al actualizar un digest hay que volver a ejecutar `container-scan` antes de aprobar la imagen.

### Configuración segura del `docker-compose.yml`

| Control | Implementación | Verificación |
| :--- | :--- | :--- |
| BD no expuesta (`THR-03`) | `db` sin `ports`; red `data` con `internal: true` (sin salida a Internet ni acceso desde el host) | `docker port proyecto-seguridad-db-1` → vacío; `docker network inspect proyecto-seguridad_data` → `internal=true` |
| Contraseña fuera de archivos (`THR-03`) | `${DB_PASSWORD:?...}`: compose se niega a arrancar si no está definida en la sesión | Sin la variable, `docker compose exec` falla con `required variable DB_PASSWORD is missing a value` |
| No root / no privilegiado (`THR-05`) | `USER` en ambos Dockerfiles; ningún `privileged`; `cap_drop: [ALL]`, `no-new-privileges`, `read_only: true` + `tmpfs /tmp` en backend y frontend | `id` en los contenedores (abajo); `docker inspect` → `privileged=false readonly=true capdrop=[ALL]` |
| Puertos del host acotados | Solo `127.0.0.1`, configurables con `BACKEND_HOST_PORT` (3000) y `FRONTEND_HOST_PORT` (8080) | En esta máquina 3000 y 5432 estaban ocupados: se usó `BACKEND_HOST_PORT=3001` |
| Datos ficticios | Migraciones `001..004` + `seed_test.sql` montadas archivo por archivo en `/docker-entrypoint-initdb.d` (no se oculta el `10_postgis.sh` de la imagen) | Smoke test 6: `SAN JOSÉ` desde la semilla |
| Logs con rotación (base de `7.2`) | `logging: json-file`, `max-size: 10m`, `max-file: 5` en los tres servicios | `docker inspect --format '{{.HostConfig.LogConfig}}'` |

### Qué se escanea y qué bloquea

| Modo Trivy | Objetivo | Umbral que bloquea (exit ≠ 0) | Reporte |
| :--- | :--- | :--- | :--- |
| `config` | `backend/Dockerfile`, `frontend/Dockerfile`, `docker-compose.yml` | Cualquier configuración **HIGH/CRITICAL** con estado `FAIL` (el JSON conserva todas las severidades) | `reports/trivy-config-<sha>.json` |
| `image` | `proyecto-seguridad-backend:sha-<sha>` y `proyecto-seguridad-frontend:sha-<sha>` | Vulnerabilidades **HIGH/CRITICAL** con corrección disponible (`--severity HIGH,CRITICAL --ignore-unfixed --exit-code 1`) | `reports/trivy-image-<backend\|frontend>-<sha>.json` |
| `image --format cyclonedx` | Ambas imágenes | Falla si no se puede generar | `reports/sbom-<backend\|frontend>-<sha>.cdx.json` (CycloneDX 1.7) |

**Estados:** `PASS`, `FAIL` o `INCOMPLETE` (el build o la herramienta no se ejecutaron). `INCOMPLETE` **cuenta como no aprobado**: el resultado global es `APPROVED` solo si todo está en `PASS`.

**Diseño:** Trivy recibe las imágenes como tar (`docker save` → `trivy image --input`), **sin acceso al socket de Docker**. La caché de su base de datos vive en el volumen `proyecto-seguridad-trivy-cache`.

### Cómo se relacionan commit e imagen

Para un mismo SHA, todos los artefactos se pueden cruzar entre sí:

1. **Nombre:** cada reporte lleva el SHA completo (`*-<sha>.json`) y la imagen se etiqueta `sha-<sha>`.
2. **Etiqueta OCI dentro de la imagen:** `org.opencontainers.image.revision=<sha>` (`--label` en el build y `LABEL` en el Dockerfile). El backend además expone `COMMIT_SHA` en `GET /api/health`.
3. **SBOM:** Trivy copia en `metadata.component.properties` el `RepoTag`, el `ImageID` y la etiqueta `revision`. Ejemplo del backend:
   `aquasecurity:trivy:RepoTag = proyecto-seguridad-backend:sha-f045577b…` · `aquasecurity:trivy:Labels:org.opencontainers.image.revision = f045577b…`.
4. **`reports/container-scan-<sha>.json`:** lista `commit`, `image`, `image_id`, `repo_digests`, `config_digest`, `revision_label`, la versión de Trivy y la fecha de su BD, el resultado de cada paso y el resultado global.

> **`image_id` vs `config_digest`:** con el *containerd image store* de Docker Desktop, `image_id` es el digest del índice local, que **cambia en cada build** porque la atestación de *provenance* incluye la fecha. `config_digest` (el `ImageID` que Trivy registra en el reporte y en el SBOM) es estable para el mismo contenido: en dos builds del mismo commit cambió el índice (`47b577…` → `a91bb4…`) y el config se mantuvo (`69404fd6…`). Ninguno de los dos es el digest del registro: el que usa el despliegue (`docker.io/...@sha256:…`) se obtiene al publicar en el ítem `5.5`. Allí la imagen se construye **una sola vez**, se re-escanea y se publica esa misma imagen.

### Resultados obtenidos (commit `f045577b`)

**Primera ejecución (antes de corregir):**

| Imagen | HIGH/CRITICAL corregibles | Origen |
| :--- | :---: | :--- |
| backend | 19 (HIGH/CRITICAL) | npm incluido en la imagen base (`brace-expansion`, `ip-address`, `pacote` ×2, `picomatch`, `sigstore`) + dependencias de la app (`multer`, `body-parser`, `lodash`) |
| frontend | 12 (HIGH/CRITICAL) | Paquetes Alpine de la base: `curl`/`libcurl`, `libexpat`, `libxslt`, `musl`/`musl-utils`, `zlib`, `brotli-libs` |

**Correcciones aplicadas (sin ignorar nada):**

- **Backend:** después de `npm ci --omit=dev` se eliminan `npm`, `npx`, `corepack` y `yarn` del runtime. No se usan para ejecutar `node dist/main.js` y eran el origen de todos los hallazgos de herramientas. También reduce la superficie (`CTL-05`).
- **Frontend:** `apk upgrade --no-cache` como root solo durante el build, `apk del curl` (no se usa; el healthcheck usa `wget` de busybox) y vuelta a `USER 101`.

**Ejecución final** (`reports/container-scan-f045577b963deb228642ebf36963f39fb400fe2c.json`):

| Paso | Resultado |
| :--- | :--- |
| Build backend / frontend | `PASS` / `PASS` |
| Trivy `config` | `PASS`. `backend/Dockerfile` y `frontend/Dockerfile`: 27 comprobaciones superadas, 0 fallidas. |
| Trivy `image` frontend | `PASS` (0 HIGH, 0 CRITICAL) |
| Trivy `image` backend | **`FAIL` (9 HIGH, 0 CRITICAL)**. Ver hallazgo pendiente. |
| SBOM backend / frontend | `PASS` (252 / 65 componentes) |
| **Global** | **`FAILED`**. La compuerta funciona y bloquea la imagen del backend. |

### Hallazgo pendiente: dependencias del backend fijadas por NestJS 10

| CVE | Paquete (instalado → corregido) | Llega por |
| :--- | :--- | :--- |
| `CVE-2026-2359`, `CVE-2026-3304`, `CVE-2026-3520`, `CVE-2026-5079`, `CVE-2026-77078`, `CVE-2026-82333`, `CVE-2026-113872` | `multer` 2.0.2 → 2.1.0 … 2.5.0 (DoS en multipart) | `@nestjs/platform-express@10.4.22` (fija `multer: "2.0.2"`) |
| `CVE-2026-111181` | `body-parser` 1.20.4 → 1.20.9 / 2.4.0 (DoS por descompresión) | `@nestjs/platform-express@10.4.22` y `express@4.22.1` |
| `CVE-2026-4800` | `lodash` 4.17.21 → 4.18.0 (ejecución de código vía `_.template`) | `@nestjs/config@3.3.0` (fija `lodash: "4.17.21"`) |

**Por qué no lo corregí:** `@nestjs/platform-express@10.4.22` es la última versión 10.x y fija exactamente esas versiones (`npm view`). Corregirlo exige cambiar `backend/package.json` / `package-lock.json` (`overrides` o migración a NestJS 11+), que no son archivos de este ítem. Son los mismos paquetes que `EXC-01` ya acepta para OSV-Scanner, pero **esa excepción no se extiende automáticamente a Trivy**: no se agregó ningún `.trivyignore` ni se bajó el umbral.

**Opciones para decisión humana:**

1. **Corrección (preferida):** quien sea dueño de las dependencias del backend (Billy `2.2` / Roberto `3.2`) agrega `overrides` (`multer >= 2.5.0`, `body-parser >= 1.20.9`, `lodash >= 4.18.0`) o migra a NestJS 11. Luego se vuelve a ejecutar `container-scan` y las pruebas.
2. **Excepción temporal:** Billy la registra con las filas de abajo. Solo con esa aprobación se crearía un `.trivyignore.yaml` nuevo, con cada CVE, `statement` y `expired_at: 2026-12-15`, y `--ignorefile` en los scripts. Hasta entonces el workflow `container-supply-chain` queda en rojo.

**Filas propuestas para `REGISTRO-HALLAZGOS.md`** (para que Billy decida; no edité ese archivo):

*Sección 1 — Hallazgos:*

```markdown
| **`HAL-04`** | Etapa 3 (`3.3`) — **Trivy image** (`proyecto-seguridad-backend:sha-f045577b…`) | `THR-05` / `CTL-05` | `backend/package-lock.json` vía `@nestjs/platform-express@10.4.22` (`multer 2.0.2`, `body-parser 1.20.4`) y `@nestjs/config@3.3.0` (`lodash 4.17.21`) | `reports/trivy-image-backend-f045577b963deb228642ebf36963f39fb400fe2c.json` (9 HIGH con corrección disponible: CVE-2026-2359, -3304, -3520, -5079, -77078, -82333, -113872, -111181, -4800) | **Alta** (DoS en multipart/descompresión; RCE en `_.template`). Explotabilidad baja en este sistema: API solo `GET`, sin subida de archivos ni `_.template`. | **Brandon** (detecta) / dueño de dependencias backend (corrige) | 🔴 **Abierto** | Pendiente: `overrides` o migración NestJS 11 + re-ejecución de `scripts/container-scan`, **o** excepción `EXC-03`. |
```

*Sección 2 — Excepciones (solo si se aprueba en lugar de corregir):*

```markdown
| **`EXC-03`** | Trivy image HIGH en `multer`, `body-parser`, `lodash` (`HAL-04`) | `proyecto-seguridad-backend:sha-*` (NestJS 10) | `reports/trivy-image-backend-f045577b963deb228642ebf36963f39fb400fe2c.json` | Mismos paquetes y justificación que `EXC-01`: la API expone solo `GET`, no usa `multer` (sin uploads), no recibe cuerpos comprimidos y no invoca `_.template`. Compensación: contenedor no root, `read_only`, `cap_drop: ALL`, límites de resultados (`CTL-02`). Se aplicaría con un `.trivyignore.yaml` con `expired_at`. | **Brandon** (`Brandon-Corrales`) | **Billy Ugalde** (`Billy-Ugalde`) | 🟡 Propuesta | `2026-12-15` |
```

### Verificación en ejecución (`docker compose up`)

```text
$ docker compose ps
proyecto-seguridad-backend-1   Up (healthy)   127.0.0.1:3001->3000/tcp
proyecto-seguridad-db-1        Up (healthy)   5432/tcp           <- sin publicar en el host
proyecto-seguridad-frontend-1  Up (healthy)   127.0.0.1:8080->8080/tcp

$ powershell -File scripts/smoke-test.ps1 -BaseUrl http://localhost:3001 -ReportPath reports/smoke-test-compose-<sha>.json
  [PASS] 1..8  (incluye 7: 404 cantón inexistente y 8: 400 fecha inválida)
  [RESULTADO] APROBADO (Todas las 8 comprobaciones pasaron).

$ docker compose exec backend id
uid=1000(node) gid=1000(node) groups=1000(node)
$ docker compose exec frontend id
uid=101(nginx) gid=101(nginx) groups=101(nginx)
$ docker compose exec backend touch /app/x
touch: /app/x: Read-only file system

$ curl -sD - http://localhost:8080/   (cabeceras)
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Referrer-Policy: strict-origin-when-cross-origin
$ curl http://localhost:8080/api/health  -> 200 (proxy nginx -> backend)
```

Reporte: `reports/smoke-test-compose-f045577b963deb228642ebf36963f39fb400fe2c.json`.

### Comandos para reproducir

```powershell
# Windows / PowerShell (contraseña ficticia SOLO en la sesión)
$env:DB_PASSWORD = '<valor-ficticio>'; $env:COMMIT_SHA = (git rev-parse HEAD)
$env:BACKEND_HOST_PORT = '3001'      # si 3000 está ocupado
docker compose build
powershell -ExecutionPolicy Bypass -File scripts/container-scan.ps1          # SHA = HEAD
docker compose up -d
powershell -ExecutionPolicy Bypass -File scripts/smoke-test.ps1 -BaseUrl http://localhost:3001 -ReportPath "reports/smoke-test-compose-$(git rev-parse HEAD).json"
docker compose exec backend id
docker compose down            # agregar -v para borrar el volumen de la BD
```

```bash
# Linux / CI / Git Bash
bash scripts/container-scan.sh "$(git rev-parse HEAD)"
```

### Limitaciones

- **`--ignore-unfixed`:** las CVE sin versión corregida no bloquean (sí aparecen al quitar el filtro). Es una decisión para no bloquear lo que el equipo no puede corregir; hay que revisarlas en cada actualización de base.
- **Instantánea en el tiempo:** el resultado depende de la BD de Trivy del momento (`vulnerability_db_updated_at` en el resumen). Una imagen aprobada hoy puede tener CVE nuevas mañana; por eso `5.5` re-escanea antes de publicar.
- **`docker-compose.yml` no tiene escáner nativo en Trivy:** Trivy analiza Dockerfile, Kubernetes, Terraform, etc., pero no las reglas de Compose. El archivo se incluye en el objetivo y aparece en el resumen, pero las condiciones de Compose (`privileged`, `user`) se comprueban con **Conftest en `3.4`**.
- **`apk upgrade` no es determinista:** dos builds en fechas distintas pueden instalar parches distintos. La trazabilidad la dan el SBOM y el digest de cada build, no el Dockerfile.
- **Solo detecta lo conocido:** Trivy no detecta vulnerabilidades del código propio (eso es `2.3`/`3.2`) ni comportamiento en ejecución.
- **Digest local ≠ digest de registro:** ver la nota de `image_id` / `config_digest`; el digest desplegable sale de `5.5`.

### Texto sugerido para la KB (`CTL-05`), a aplicar por Jose/Roberto

En `01-planificacion-kb.md`, fila `THR-05`, columna **Componente Afectado** y **Comprobación Prevista**:

> **Componente:** `backend/Dockerfile`, `frontend/Dockerfile`, `docker-compose.yml`, `policy/container.rego`, `.github/workflows/container-supply-chain.yml`.  
> **Comprobación:** 1) `conftest test` rechaza un Dockerfile/compose inseguro y aprueba los productivos (`3.4`, job `policy-conftest`). 2) Trivy `config` + `image` (HIGH/CRITICAL corregibles bloquean) y SBOM CycloneDX por commit en `container-supply-chain.yml` (`3.3`), además de OSV-Scanner en `ci.yml` (`3.2`).

### Observaciones para otros integrantes (no corregidas por estar fuera de alcance)

- **Roberto (`6.5`):** `scripts/smoke-test.ps1` y `.sh` escriben por defecto en `reports/smoke-test-report.json`, que está versionado. Una ejecución local sin `-ReportPath` sobrescribe la evidencia original (me pasó y lo restauré con `git checkout`). Sugerencia: nombre por SHA o fecha por defecto.

---

## 3.4 — Políticas con Conftest + OPA/Rego

*Pendiente (Prompt 2).*
