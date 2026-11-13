# Publicación en Docker Hub por SHA y Digest (Etapa 5)

> **Ítem:** `5.5` · **Responsable:** Brandon Corrales (`Brandon-Corrales`) · **Revisor:** Roberto (`RobertoUNA`)  
> **Relación con la KB:** `EXT-06` (Docker Hub), `SEC-03` (`DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`), `THR-05` / `CTL-05` (solo se publica lo que pasó Trivy y Conftest), `SEC-05` (permisos mínimos del `GITHUB_TOKEN`).  
> **Commit analizado (evidencia vigente):** `67965235342d27bd4f53dc118f3a62a3d78785d0` (commit `feat(ssdlc): item 5.5 …`), árbol limpio (`worktree_clean: true`).  
> **Evidencia de la mecánica:** [`reports/release-local-sim-67965235342d27bd4f53dc118f3a62a3d78785d0.json`](../../reports/release-local-sim-67965235342d27bd4f53dc118f3a62a3d78785d0.json) (simulación local, 2026-11-12T03:46:13Z).
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

**Ejecuciones duplicadas:** cada push dispara este workflow **dos veces** (uno por cada workflow terminado). `concurrency: release-<sha>` las serializa. La primera suele encontrar al otro workflow en curso y no publica; la segunda publica. Si `sha-<SHA>` ya existe, no se reconstruye: así nunca se sobrescribe una etiqueta con una imagen distinta.

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

## Caso negativo: una comprobación obligatoria fallida impide publicar

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

Ese archivo (no modificado) contiene **digests ficticios**: `sha256:9e06aae000…0001` y `…0002`. Cuando el workflow publique un candidato real, Roberto puede reemplazarlos con los valores `backend_image` / `frontend_image` del artefacto `release-candidate-<sha>`, que ya vienen en formato `docker.io/elrobb/proyecto-seguridad-<c>@sha256:…`. Así su rollback (`6.6`) apuntará a imágenes que existen y que pasaron la compuerta.

## Limitaciones y dependencias pendientes

- **Dependencias de Roberto: resueltas** (verificado el 2026-11-12):
  - la rama `development` existe en `origin`;
  - los secretos `DOCKERHUB_USERNAME` y `DOCKERHUB_TOKEN` están configurados (`gh api …/actions/secrets` lista ambos nombres; los valores no son visibles);
  - los 4 checks `3.1`–`3.4` son obligatorios en `main` (`gh pr checks 6 --required`).
  - Las imágenes se publicarán en la cuenta **`elrobb`**: `docker.io/elrobb/proyecto-seguridad-backend` y `docker.io/elrobb/proyecto-seguridad-frontend`.
- **Ejecución real en Docker Hub aún pendiente:** requiere que `release-deploy.yml` esté en `main` y un push a `main`/`development` con los 4 checks en `success`. Hasta entonces la evidencia es la simulación local y la validación del workflow (actionlint + prueba de la compuerta de checks).
- **`workflow_run` solo funciona desde `main`:** GitHub usa la versión del workflow de la rama por defecto. `release-deploy.yml` debe estar fusionado en `main` para dispararse, incluso para pushes a `development`.
- **Depende de `EXC-03`:** con la excepción vigente `3.3` puede pasar. Si vence (`2026-12-15`) sin que `HAL-04` se corrija, `3.3` vuelve a fallar y no se publica nada en `main`/`development`. Es el comportamiento correcto.
- **El nombre de usuario de Docker Hub es un secreto (`SEC-03`):** GitHub lo enmascara (`***`) en los logs y en los nombres de imagen que aparecen ahí. El artefacto JSON sí lo contiene, porque es necesario para desplegar.
- **Re-escaneo en el job de publicación:** las vulnerabilidades se evalúan con la base de Trivy del momento. Una imagen aprobada en `3.3` podría fallar minutos después si se publica una CVE nueva; el job falla y no publica, como corresponde.
- **Diferencias de la simulación:** usa HTTP sin TLS sobre loopback y no tiene autenticación; no prueba el login ni los permisos del token de Docker Hub. Con el *containerd image store* de Docker Desktop, el image ID local es el digest del índice, y por eso coincide exactamente con el del registro.
