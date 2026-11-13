# Publicación en Docker Hub por SHA y Digest (Etapa 5)

> **Ítem:** `5.5` · **Responsable:** Brandon Corrales (`Brandon-Corrales`) · **Revisor:** Roberto (`RobertoUNA`)  
> **Relación con la KB:** `EXT-06` (Docker Hub), `SEC-03` (`DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`), `THR-05` / `CTL-05` (solo se publica lo que pasó Trivy y Conftest), `SEC-05` (permisos mínimos del `GITHUB_TOKEN`).  
> **Publicación real vigente:** commit `ddf53201e2899b99bd859b36f2ba28b8676e9d07` (merge del PR #16 `development → main`), publicado el 2026-11-13T17:28:37Z por la corrida [#1 (43472950185)](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43472950185). Detalle en [Primera publicación real (ddf5320)](#primera-publicación-real-ddf5320).
> - `docker.io/elrobb/proyecto-seguridad-backend@sha256:5bfc15e6e7688c167fd4ca1bf1ebdc354c0b16d24b96bb0b2eae6718ef712797`
> - `docker.io/elrobb/proyecto-seguridad-frontend@sha256:e478b510e4ed37192a991aeb8e1d220dffc7351c1fdeff20edd56908177e77ee`
> - Registro: [`reports/candidate-release-ddf53201e2899b99bd859b36f2ba28b8676e9d07.json`](../../reports/candidate-release-ddf53201e2899b99bd859b36f2ba28b8676e9d07.json).
>
> **Simulación local (commit `67965235342d27bd4f53dc118f3a62a3d78785d0`, `feat(ssdlc): item 5.5 …`, árbol limpio):** [`reports/release-local-sim-67965235342d27bd4f53dc118f3a62a3d78785d0.json`](../../reports/release-local-sim-67965235342d27bd4f53dc118f3a62a3d78785d0.json) (simulación local, 2026-11-12T03:46:13Z).
> - **Backend `BLOCKED`:** Trivy image `FAIL`, 9 HIGH (caso negativo).
> - **Frontend `PUBLISHED`** como `localhost:5055/proyecto-seguridad-frontend@sha256:fde4ed562c4b3b38400b527c0468bb68042760722ac360c5c914d205edaff9ed`. El digest del registro, el de `imagetools`, el image ID antes y el image ID tras el pull por digest son iguales.
> - **Limpieza:** `mechanics_verified: true`, `registry_removed: true`, 0 imágenes `localhost:5055` restantes y la lista de contenedores idéntica antes y después.

## Archivos

| Archivo | Función |
| :--- | :--- |
| [`.github/workflows/release-deploy.yml`](../../.github/workflows/release-deploy.yml) | Workflow de publicación (Docker Hub real). |
| [`scripts/release-local-sim.ps1`](../../scripts/release-local-sim.ps1) | Simulación local de la misma mecánica con un registro temporal `registry:2.8.3` en `127.0.0.1`. |
| Reutilizados (sin cambios) | `scripts/container-scan.*` (`3.3`: build + Trivy + SBOM) y `scripts/policy-check.*` (`3.4`: Conftest). |

## Flujo de `release-deploy.yml`

```text
push a main / development
   ├── CI SSDLC (ci.yml: 3.1 + 3.2) ───────────────┐  workflow_run (completed, success, event=push)
   └── Contenedores SSDLC (3.3 + 3.4) ─────────────┤
                                                   ▼
   [required-checks]  API de checks del head_sha: 3.1, 3.2, 3.3 y 3.4 en success
        │  fallido / omitido / sin resultado → FALLA, no publica
        │  alguno aún en curso → termina sin publicar ni aprobar (lo hará la siguiente ejecución)
        ▼
   [publish]  SEC-03 presente → checkout del head_sha → login Docker Hub
        │  ¿sha-<SHA> ya existe en Docker Hub? → no se reconstruye ni se sobrescribe
        ├─ build ÚNICO + Trivy image/config + SBOM   (scripts/container-scan.sh)
        ├─ Conftest Dockerfiles + compose             (scripts/policy-check.sh)
        ├─ docker tag + push de ESA imagen → :sha-<SHA> (+ :development en development)
        ├─ digest real: docker buildx imagetools inspect → pull por digest = mismo image ID
        └─ candidate-release-<sha>.json → artefacto release-candidate-<sha> (sin commit)
```

### Condiciones para publicar

| # | Condición | Si no se cumple |
| :-: | :--- | :--- |
| 1 | El `workflow_run` disparador terminó en `success`, por `push`, en `main` o `development` | El workflow no se ejecuta. |
| 2 | Los check runs del `head_sha` (`3.1 Calidad…`, `3.2 Seguridad…`, `3.3 Imagen candidata…`, `3.4 Políticas Conftest…`) están `completed` + `success`; si un job se re-ejecutó, cuenta el más reciente | **Falla sin publicar** si alguno está fallido, omitido (`skipped`) o ausente. Si alguno sigue en curso, termina sin publicar y sin aprobar. |
| 3 | `DOCKERHUB_USERNAME` y `DOCKERHUB_TOKEN` existen | **Falla** con `SEC-03 no configurado`; el candidato **no** se considera aprobado. |
| 4 | Compuerta final sobre la imagen construida en ese mismo job: Trivy image sin HIGH/CRITICAL corregibles, Trivy config y Conftest en PASS | **Falla sin publicar ninguna imagen**: un candidato de versión requiere backend **y** frontend. |
| 5 | El image ID no cambia entre la imagen evaluada, la etiquetada y la obtenida por digest | **Falla** (no es la imagen evaluada). |

**Permisos:** `contents: read`, `actions: read`, `checks: read`. No escribe en el repositorio.

**Acciones:** fijadas por SHA real (consultado con `gh api`):
- `actions/checkout@11bd719…` (v4.2.2);
- `actions/upload-artifact@b4b15b8…` (v4.4.3);
- `docker/login-action@8aa5831fb8d48d8f76594c7ddde61ae58019f550` (v4.8.0).

**Secretos:** los secretos solo se pasan por `env` a pasos concretos y al `docker/login-action`; GitHub los enmascara en los logs. `actionlint 1.7.7` sin hallazgos.

**Ejecuciones duplicadas:** cada push dispara este workflow **dos veces** (uno por cada workflow terminado). `concurrency: release-<sha>` las serializa. Publica la primera corrida cuya compuerta encuentre los 4 checks en `success`. Si el otro workflow aún está en curso, esa corrida termina sin publicar y publica la siguiente. Si `sha-<SHA>` ya existe, no se reconstruye: así nunca se sobrescribe una etiqueta con una imagen distinta. En la publicación real de `ddf5320` el otro workflow ya había terminado, así que publicó la corrida #1 y la #2 se detuvo con "ya existe" (ver abajo).

**Prueba de la compuerta de checks.** El script del job `required-checks` se extrajo tal cual del YAML y se ejecutó con un `gh` simulado (contenedor con `jq`) en 7 escenarios:

| Escenario | Exit | Publica |
| :--- | :---: | :---: |
| Todo en `success` | 0 | Sí (`ready=true`) |
| Uno fallido | 1 | No |
| Uno `skipped` | 1 | No |
| Uno ausente | 1 | No |
| Uno en curso | 0 | No (`ready=false`) |
| Re-ejecutado y terminado en `success` | 0 | Sí |
| Re-ejecutado y terminado en `failure` | 1 | No |

## Etiquetas

| Etiqueta | Cuándo | Uso |
| :--- | :--- | :--- |
| `sha-<SHA completo de 40 caracteres>` | Siempre | Identifica el commit evaluado. No se sobrescribe (ver condición de existencia). |
| `development` | Solo en pushes a `development` | Referencia móvil al **último candidato aprobado** de esa rama. Es informativa: **no** se usa para desplegar. |
| `latest` | **Nunca** | Es mutable y no identifica qué se evaluó (`EXT-06`). |

## Digest: cómo se obtiene, se verifica y se usa

1. **Obtención:** después del `docker push`, el digest se pide **al registro**: `docker buildx imagetools inspect docker.io/elrobb/proyecto-seguridad-<c>:sha-<SHA> --format '{{json .Manifest}}'` → `.digest`.
2. **Verificación:** se hace `docker pull <repo>@<digest>` y se comprueba que el image ID coincide con el de la imagen evaluada por Trivy/Conftest. Si no coincide, el job falla.
3. **Registro:** `candidate-release-<sha>.json` guarda `backend_image` y `frontend_image` como `docker.io/elrobb/proyecto-seguridad-<c>@sha256:…`, junto con `commit_sha`, `ref`, enlaces a la ejecución y los nombres de los artefactos de reportes y SBOM. Se sube como artefacto `release-candidate-<sha>`; **no** se hace commit al repositorio.
4. **Despliegue:** se despliega por **digest** (`backend_image` / `frontend_image`), nunca por etiqueta. Lo hacen `5.1` (Jose, registro de versión) y `6.5`/`6.6` (Roberto, despliegue y rollback).

Para verificarlo manualmente:

```bash
docker buildx imagetools inspect docker.io/elrobb/proyecto-seguridad-backend:sha-<SHA>   # digest del índice
docker pull docker.io/elrobb/proyecto-seguridad-backend@sha256:<digest>
```

**Si se reconstruye, se vuelve a evaluar.** Dos builds del mismo commit no producen el mismo digest. En la simulación local, el frontend del mismo SHA dio `sha256:b8687d39…` en una ejecución y `sha256:4f8e66d2…` en la siguiente, entre otras cosas porque `apk upgrade` puede instalar parches distintos. Por eso el workflow evalúa y publica **la imagen construida en el mismo job**, nunca una reconstrucción. Toda imagen nueva pasa otra vez por Trivy y Conftest antes de aprobarse.

## Primera publicación real (ddf5320)

**Commit:** `ddf53201e2899b99bd859b36f2ba28b8676e9d07` (merge del PR #16 `development → main`).

El push a `main` disparó los dos workflows de la Etapa 3, ambos por `push` y en `success`:
- CI SSDLC ([43472781348](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43472781348)), de 17:26:16 a 17:27:14Z;
- Contenedores SSDLC ([43472781428](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43472781428)), de 17:26:16 a 17:27:17Z.

Cada uno, al terminar, disparó una corrida de `release-deploy.yml`.

| | Corrida #1 ([43472950185](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43472950185)) | Corrida #2 ([43472955459](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43472955459)) |
| :--- | :--- | :--- |
| Disparada por | `workflow_run` de **CI SSDLC** (43472781348; campo `links.triggering_run` del artefacto) | `workflow_run` de **Contenedores SSDLC** (43472781428). Se deduce por eliminación: son los dos únicos workflows del disparador y cada uno corrió una vez sobre este SHA. |
| Compuerta `required-checks` | 17:27:22–17:27:31Z. Encontró los 4 checks `completed` + `success` y dio `ready=true`. | En cola por `concurrency: release-<sha>` hasta que terminó la #1. Corrió de 17:28:52 a 17:29:07Z y dio `ready=true`. |
| "Etiquetas inmutables ya publicadas" | `exists=false` | `exists=true` → `##[notice]sha-ddf53201e2899b99bd859b36f2ba28b8676e9d07 ya existe en Docker Hub: no se reconstruye ni se sobrescribe.` |
| Compuerta final | Build único y `container-scan.sh`: Trivy config PASS; Trivy image backend **PASS (0 HIGH/CRITICAL, 9 suprimidas por `EXC-03`)**, frontend PASS; SBOM de ambos; resultado **APPROVED**. `policy-check.sh`: verify, permitido y demo insegura PASS (25/25 pruebas Rego; los 3 ejemplos inseguros rechazados); resultado **APPROVED**. | Omitida (`skipped`) |
| Publicación | `docker push` de **esa** imagen como `sha-ddf5320…` (backend y frontend), digest leído con `imagetools`, `pull` por digest y comparación de image ID | Omitida: no se reconstruye ni se publica nada |
| Artefactos | `release-candidate-ddf5320…` y `release-gate-reports-ddf5320…` | Ninguno |

**Publicación vigente:** la de la corrida #1. Hubo **una sola publicación**; la #2 no generó un segundo digest.

**Por qué siempre hay dos corridas por SHA.** `release-deploy.yml` escucha el `workflow_run` de **dos** workflows (`CI SSDLC` y `Contenedores SSDLC`), y un push dispara los dos. El diseño lo maneja así:
- **Concurrencia por SHA:** `concurrency: release-<sha>` con `cancel-in-progress: false` serializa las dos corridas. Nunca publican en paralelo y ninguna cancela a la otra.
- **No republicar:** si `sha-<SHA>` ya existe en Docker Hub, la corrida no reconstruye. Una reconstrucción daría otro digest (ver "Si se reconstruye, se vuelve a evaluar").
- **Compuerta de checks:** si la primera corrida encuentra el otro workflow aún en curso, termina con `ready=false` sin publicar, y publica la siguiente.

### Registro de la versión candidata

[`reports/candidate-release-ddf53201e2899b99bd859b36f2ba28b8676e9d07.json`](../../reports/candidate-release-ddf53201e2899b99bd859b36f2ba28b8676e9d07.json) (copia del artefacto `release-candidate-ddf5320…`):

| Campo | Valor |
| :--- | :--- |
| `commit_sha` | `ddf53201e2899b99bd859b36f2ba28b8676e9d07` |
| `ref` | `main` |
| `published_at` | `2026-11-13T17:28:37Z` |
| `backend_image` | `docker.io/elrobb/proyecto-seguridad-backend@sha256:5bfc15e6e7688c167fd4ca1bf1ebdc354c0b16d24b96bb0b2eae6718ef712797` |
| `frontend_image` | `docker.io/elrobb/proyecto-seguridad-frontend@sha256:e478b510e4ed37192a991aeb8e1d220dffc7351c1fdeff20edd56908177e77ee` |
| `tags` | `["sha-ddf53201e2899b99bd859b36f2ba28b8676e9d07"]` |
| `gate` | `required_checks: success (3.1, 3.2, 3.3, 3.4)`, `trivy_image: PASS`, `conftest: PASS` |

### Estado en Docker Hub (verificado el 2026-11-13)

| Repositorio | `sha-ddf53201e2899b99bd859b36f2ba28b8676e9d07` → digest | `development` | `latest` | Etiquetas totales |
| :--- | :--- | :---: | :---: | :---: |
| `docker.io/elrobb/proyecto-seguridad-backend` | `sha256:5bfc15e6e7688c167fd4ca1bf1ebdc354c0b16d24b96bb0b2eae6718ef712797` | no existe | no existe | 1 |
| `docker.io/elrobb/proyecto-seguridad-frontend` | `sha256:e478b510e4ed37192a991aeb8e1d220dffc7351c1fdeff20edd56908177e77ee` | no existe | no existe | 1 |

- Ambos digests tienen **64 caracteres hexadecimales** y coinciden con el artefacto.
- **`latest` no existe** porque el workflow nunca la publica (`EXT-06`).
- **`development` no existe** porque este push fue a `main`; esa etiqueta solo se agrega en pushes a `development`. Es el comportamiento esperado, no un fallo.

**Verificación por imagen:**
- `docker pull` por digest funciona;
- la etiqueta `org.opencontainers.image.revision` es `ddf53201e2899b99bd859b36f2ba28b8676e9d07`;
- el usuario es **`node`** en el backend y **`101`** en el frontend (`CTL-05`).

**Comandos usados** (sin credenciales; los repositorios son públicos):

```bash
SHA=ddf53201e2899b99bd859b36f2ba28b8676e9d07
# Corridas y artefactos
gh run list --workflow release-deploy.yml
gh run view 43472950185 --log ; gh run view 43472955459 --log
gh run download 43472950185 -D <carpeta temporal fuera del repo>   # la 43472955459 no tiene artefactos
# Etiqueta → digest (y ausencia de development / latest)
docker buildx imagetools inspect docker.io/elrobb/proyecto-seguridad-backend:sha-$SHA
docker buildx imagetools inspect docker.io/elrobb/proyecto-seguridad-frontend:sha-$SHA
docker buildx imagetools inspect docker.io/elrobb/proyecto-seguridad-backend:development   # ERROR: not found
docker buildx imagetools inspect docker.io/elrobb/proyecto-seguridad-backend:latest        # ERROR: not found
curl -s "https://hub.docker.com/v2/repositories/elrobb/proyecto-seguridad-backend/tags?page_size=100"   # count: 1
# Pull por digest, commit y usuario
docker pull docker.io/elrobb/proyecto-seguridad-backend@sha256:5bfc15e6e7688c167fd4ca1bf1ebdc354c0b16d24b96bb0b2eae6718ef712797
docker image inspect --format '{{.Config.User}} {{index .Config.Labels "org.opencontainers.image.revision"}}' \
  docker.io/elrobb/proyecto-seguridad-backend@sha256:5bfc15e6e7688c167fd4ca1bf1ebdc354c0b16d24b96bb0b2eae6718ef712797
# → node ddf53201e2899b99bd859b36f2ba28b8676e9d07   (frontend: 101 ddf53201e2899b99bd859b36f2ba28b8676e9d07)
```

### Reportes de la compuerta final (evidencia versionada)

Son copias de los archivos `-ddf5320…` del artefacto `release-gate-reports-ddf5320…` de la corrida #1. Antes de versionarlos se revisaron así:
- **Búsqueda de patrones de token y clave** (`dckr_pat_`, `ghp_`, `github_pat_`, `Bearer`, claves privadas, `AKIA…`): sin coincidencias. Las únicas apariciones de "token" son nombres de paquetes npm (`@tokenizer/*`, `token-types`).
- **Gitleaks v8.21.2** (imagen fijada por digest, `.gitleaks.toml` del repo, `--redact`): `no leaks found`.

| Archivo | Contenido |
| :--- | :--- |
| [`container-scan-ddf5320….json`](../../reports/container-scan-ddf53201e2899b99bd859b36f2ba28b8676e9d07.json) | Resumen 3.3: `APPROVED`, `worktree_clean: true`, ignorefile `.trivyignore.yaml`, backend con 9 suprimidas |
| [`trivy-config-ddf5320….json`](../../reports/trivy-config-ddf53201e2899b99bd859b36f2ba28b8676e9d07.json) | Trivy config (Dockerfiles y compose) |
| [`trivy-image-backend-ddf5320….json`](../../reports/trivy-image-backend-ddf53201e2899b99bd859b36f2ba28b8676e9d07.json) | Trivy image backend; las 9 CVE de `HAL-04` aparecen en `ExperimentalModifiedFindings` con estado `ignored` |
| [`trivy-image-frontend-ddf5320….json`](../../reports/trivy-image-frontend-ddf53201e2899b99bd859b36f2ba28b8676e9d07.json) | Trivy image frontend |
| [`sbom-backend-ddf5320….cdx.json`](../../reports/sbom-backend-ddf53201e2899b99bd859b36f2ba28b8676e9d07.cdx.json) · [`sbom-frontend-ddf5320….cdx.json`](../../reports/sbom-frontend-ddf53201e2899b99bd859b36f2ba28b8676e9d07.cdx.json) | SBOM CycloneDX de las imágenes publicadas |
| [`conftest-ddf5320….json`](../../reports/conftest-ddf53201e2899b99bd859b36f2ba28b8676e9d07.json) · [`conftest-insecure-demo-ddf5320….txt`](../../reports/conftest-insecure-demo-ddf53201e2899b99bd859b36f2ba28b8676e9d07.txt) | Conftest 3.4: `APPROVED` y la salida del caso permitido y de los rechazados |

> **Nota sobre `release-gate-reports`:** el artefacto también contiene reportes de SHA anteriores (`15c7b8b…`, `36f2324…`, `f045577…`). Esto pasa porque el job sube la carpeta `reports/` completa, que incluye los reportes ya versionados en el repositorio. La evidencia de **esta** publicación son **solo** los archivos que terminan en `-ddf53201e2899b99bd859b36f2ba28b8676e9d07`. Los demás son evidencia histórica del ítem `3.3` y no se evaluaron en esta corrida.

## Candidatos publicados en `development` (384d680 y 6342cd3)

Los pushes a `development` también disparan `release-deploy.yml`. El workflow corre con la versión de `main`, pero evalúa `github.event.workflow_run.head_sha`. Por eso, en la lista de corridas de GitHub aparecen con `headSha ddf5320 / main`, mientras que el SHA real evaluado figura en los avisos y en los artefactos.

| Corrida | SHA evaluado | Disparada por | Resultado |
| :--- | :--- | :--- | :--- |
| [43490080513](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43490080513) | `384d680828efecfbefbada3ca3bbd2e61f36cc48` (PR #19, nginx configurable) | Contenedores [43489924849](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43489924849) | **Publicó** `sha-384d680…` + `development`: backend `sha256:af8327426f52f6565f20fa4cc2aa5d57902dded2b9f2fe0e8fe7fef53616f7ac`, frontend `sha256:bf74dc0f54f083be68774b34f5076c0ff4f7e36295c7c55bcafda181c2fb2d54` |
| [43490092797](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43490092797) | `384d680…` | CI (la otra finalización) | "`sha-384d680…` ya existe": no reconstruye |
| [43496289699](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43496289699) | `6342cd32e5cb675ca7e26448e93cb1ae795d0d16` (PR #7) | Contenedores [43496114419](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43496114419) (terminó 19:52:36Z) | **No publicó.** CI [43496114184](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43496114184) seguía en ejecución (terminó 19:53:05Z). La compuerta registró `Checks requeridos aún en ejecución para 6342cd32…: no se publica en esta ejecución.` (`ready=false`) y el job de publicación quedó `skipped`. |
| [43496370884](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43496370884) | `6342cd3…` | CI [43496114184](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43496114184) | **Publicó** `sha-6342cd3…` + `development`: backend `sha256:b1763f4dde20eb348f948061d9e7421e8ba9e74044c59519a8028567e8ee4d34`, frontend `sha256:ef7f7909e82318488a4454b6eabd80dabaa7cba64fd102c04e6e9e41487ff851` |

- **Compuerta y registro:** ambos candidatos pasaron la compuerta final completa (container-scan `APPROVED` con el backend con 9 suprimidas por `EXC-03`, y Conftest `APPROVED`). El registro de `6342cd3` está en [`reports/candidate-release-6342cd32e5cb675ca7e26448e93cb1ae795d0d16.json`](../../reports/candidate-release-6342cd32e5cb675ca7e26448e93cb1ae795d0d16.json) y sus reportes `-6342cd3…`, en `reports/`.
- **Etiqueta `development`:** hoy apunta a `6342cd3`, el candidato desplegado en Render (ver [`06-despliegue-render.md`](./06-despliegue-render.md)). `384d680` es la versión de recuperación en Render.
- **Corridas con evento `pull_request`:** las que vienen de las corridas `pull_request` de CI y Contenedores quedan `skipped` por el `if` del workflow (`event == 'push'`).

## Caso negativo: una comprobación obligatoria fallida impide publicar

**Dónde queda demostrado.**
- **Check en curso (real):** la corrida [43496289699](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43496289699) (sección anterior) **no publicó** porque un check obligatorio seguía en ejecución.
- **Check fallido en `release-deploy.yml`:** todavía **no** hay una corrida real bloqueada por eso. Ese caso está demostrado con la siguiente evidencia:
1. **Simulación local sobre `6796523`:** [`reports/release-local-sim-67965235342d27bd4f53dc118f3a62a3d78785d0.json`](../../reports/release-local-sim-67965235342d27bd4f53dc118f3a62a3d78785d0.json). Corre el mismo código de compuerta; el backend quedó `BLOCKED` por Trivy image `FAIL` (9 HIGH) y **no se publicó**.
2. **Check `3.3` en `failure` en GitHub Actions** antes de `EXC-03`. Ejemplo: la corrida [43165841264](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43165841264) (commit `6e22a07`, PR #6, 2026-11-12) terminó con `3.3 Imagen candidata…` en `failure`. Es el mismo check que `required-checks` exige en `success`. En ese momento `release-deploy.yml` aún no estaba en `main`, así que esta corrida demuestra que el check falla, no que el workflow de publicación se bloqueó.
3. **Prueba de la lógica de `required-checks`** con un `gh` simulado en 7 escenarios (tabla de "Prueba de la compuerta de checks"): un check fallido, omitido o ausente da exit 1 y no publica. Esta prueba se ejecutó durante el desarrollo y **no tiene un reporte versionado**.

Hasta la aprobación de `EXC-03`, el **backend** tenía 9 vulnerabilidades HIGH corregibles (`multer`, `body-parser`, `lodash`; `HAL-04`; ver [`03-evidencia-conftest-trivy.md`](./03-evidencia-conftest-trivy.md)). La simulación de `6796523` (evidencia vigente arriba) se ejecutó **antes** de la excepción. En ese estado:

- **En GitHub Actions:** el job `3.3` de `container-supply-chain.yml` falla, el `workflow_run` de contenedores no termina en `success` y `release-deploy.yml` **ni siquiera arranca**. Si arrancara (p. ej. por el otro disparador), `required-checks` vería `3.3` en `failure` y fallaría sin publicar.
- **En la simulación local:** la compuerta marca el backend como `BLOCKED` ("Una comprobación obligatoria falló (Trivy image: FAIL…); no se publica") y solo publica el frontend.

**Después de la excepción:** Billy Ugalde aprobó `EXC-03` (commit `6e22a07`, vence `2026-12-15`) y se aplica con `.trivyignore.yaml` (9 CVE, por paquete y versión exactos). El backend pasa la compuerta (0 HIGH/CRITICAL restantes, 9 suprimidas y visibles en el reporte) y se pueden publicar ambas imágenes. La regla sigue igual: si la excepción vence (`expired_at`) o aparece otra CVE, la compuerta vuelve a bloquear la publicación. Las vulnerabilidades están **aceptadas temporalmente, no corregidas**.

## Simulación local (evidencia de la mecánica)

`scripts/release-local-sim.ps1` reproduce la mecánica sin Docker Hub:

1. Build **único** de ambas imágenes para el `HEAD` + Trivy + SBOM (`container-scan.ps1`) y Conftest (`policy-check.ps1`), con los reportes en una carpeta temporal.
2. Registro temporal `registry:2.8.3@sha256:a3d8aaa6…`: contenedor `proyecto-seguridad-release-sim-registry`, con etiquetas propias y publicado **solo en `127.0.0.1:5055`**. No toca los demás contenedores.
3. Por cada imagen que pasa la compuerta:
   - `docker tag` + `docker push` de **esa** imagen como `sha-<SHA>`;
   - digest desde la API del registro (cabecera `Docker-Content-Digest`) y con `docker buildx imagetools inspect`;
   - se quita la etiqueta y se hace `docker pull` **por digest**.
4. Guarda `reports/release-local-sim-<sha>.json` y elimina el registro temporal (con su volumen) y las etiquetas `localhost:5055/*`.

**Prueba previa (antes del commit, mismo código):**
- **backend:** `BLOCKED` por Trivy.
- **frontend:** `PUBLISHED` como `localhost:5055/proyecto-seguridad-frontend@sha256:b8687d39…`. Coinciden el **digest de la API del registro = digest de `imagetools` = image ID antes = después de etiquetar = después del pull por digest**.
- **Limpieza:** registro eliminado, 0 imágenes `localhost:5055` restantes y la lista de contenedores idéntica antes y después.

## `deploy/last-approved-release.json` (Roberto, `6.6`)

Ese archivo (no modificado) contiene **digests ficticios**: `sha256:9e06aae000…0001` y `…0002`. Ya existen candidatos reales: los valores `backend_image` / `frontend_image` de los artefactos `release-candidate-<sha>`. En Render, la versión de recuperación es `384d680`; el frontend de `ddf5320` no arranca fuera de compose. Los valores vienen en formato `docker.io/elrobb/proyecto-seguridad-<c>@sha256:…`. Actualizarlos le corresponde a Roberto; así su rollback (`6.6`) apuntará a imágenes que existen y que pasaron la compuerta.

## Limitaciones y dependencias pendientes

- **Dependencias de Roberto: resueltas** (verificado el 2026-11-12):
  - la rama `development` existe en `origin`;
  - los secretos `DOCKERHUB_USERNAME` y `DOCKERHUB_TOKEN` están configurados (`gh api …/actions/secrets` lista ambos nombres; los valores no son visibles);
  - los 4 checks `3.1`–`3.4` son obligatorios en `main` (`gh pr checks 6 --required`).
  - Las imágenes se publican en la cuenta **`elrobb`**: `docker.io/elrobb/proyecto-seguridad-backend` y `docker.io/elrobb/proyecto-seguridad-frontend`.
- **Ejecución real en Docker Hub: realizada.**
  - El 2026-11-13 sobre `ddf5320` (`main`; ver [Primera publicación real](#primera-publicación-real-ddf5320)).
  - Después, sobre `384d680` y `6342cd3` (`development`, con la etiqueta `development`; ver [Candidatos publicados en `development`](#candidatos-publicados-en-development-384d680-y-6342cd3)).
- **`workflow_run` solo funciona desde `main`:** GitHub usa la versión del workflow de la rama por defecto. `release-deploy.yml` debe estar fusionado en `main` para dispararse, incluso para pushes a `development`.
- **Depende de `EXC-03`:** con la excepción vigente `3.3` puede pasar. Si vence (`2026-12-15`) sin que `HAL-04` se corrija, `3.3` vuelve a fallar y no se publica nada en `main`/`development`. Es el comportamiento correcto.
- **El nombre de usuario de Docker Hub es un secreto (`SEC-03`):** GitHub lo enmascara (`***`) en los logs y en los nombres de imagen que aparecen ahí. El artefacto JSON sí lo contiene, porque es necesario para desplegar. El nombre de usuario no es una credencial: forma parte del nombre público de la imagen, y por eso aparece en `reports/candidate-release-ddf5320….json` y en este documento. La credencial es `DOCKERHUB_TOKEN`, que no aparece en ningún archivo.
- **Re-escaneo en el job de publicación:** las vulnerabilidades se evalúan con la base de Trivy del momento. Una imagen aprobada en `3.3` podría fallar minutos después si se publica una CVE nueva; el job falla y no publica, como corresponde.
- **Diferencias de la simulación:** usa HTTP sin TLS sobre loopback y no tiene autenticación; no prueba el login ni los permisos del token de Docker Hub. Con el *containerd image store* de Docker Desktop, el image ID local es el digest del índice, y por eso coincide exactamente con el del registro.
