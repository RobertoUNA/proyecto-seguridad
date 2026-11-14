# Despliegue Seguro en Render y Gestión de Secretos (Etapa 6)

> **Ítems:** `6.2` (configuración segura de despliegue) y `6.4` (gestión de secretos) · **Responsable:** Brandon Corrales (`Brandon-Corrales`) · **Revisor:** Roberto (`RobertoUNA`)  
> **Relación con la KB:** `THR-03` / `CTL-03` (secretos solo desde el entorno), `THR-05` / `CTL-05` (contenedores no root, BD sin acceso público), `THR-06` / `CTL-06` (eventos de seguridad con `actor_id`), `SEC-03` (credenciales de Docker Hub), `EXT-06` (Docker Hub).  
> **Versión desplegada (actual):** candidato `0961a7ec33de584c75f8215c0aab2c124bd756d4` (merge del PR #29: corrección de `HAL-09`). Registro: [`reports/candidate-release-0961a7ec33de584c75f8215c0aab2c124bd756d4.json`](../../reports/candidate-release-0961a7ec33de584c75f8215c0aab2c124bd756d4.json). Publicado por Release SSDLC #19 (corrida [43528185151](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43528185151)); la #20 ([43528188313](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43528188313)) se detuvo con "ya existe". Ver el [Historial de despliegues](#historial-de-despliegues).  
> **Versión de recuperación:** `6342cd32e5cb675ca7e26448e93cb1ae795d0d16`.  
> **Registro de versión:** [`docs/releases/v1.0.0-rc1.md`](../releases/v1.0.0-rc1.md) (describe el candidato `6342cd3`).  
> **Verificado el:** 2026-11-13 (ver [Verificación de `0961a7e`](#verificación-de-0961a7e-versión-actual)).

---

## 6.2 — Configuración segura de despliegue

### Plataforma: por qué Render

| Necesidad | Cómo la cubre Render |
| :--- | :--- |
| Desplegar **exactamente** la imagen aprobada por la compuerta `5.5`, sin reconstruir | Web services *image-backed*: ejecutan una imagen de un registro público referenciada por **digest** (`@sha256:…`). No hay build en Render. |
| PostgreSQL con PostGIS | Render Postgres admite la extensión `postgis` (PostgreSQL 13 o posterior). La migración `001` hace `CREATE EXTENSION IF NOT EXISTS postgis`. |
| HTTPS sin gestionar certificados | Cada web service tiene un dominio `*.onrender.com` con TLS gestionado por Render. |
| Base de datos sin exposición a Internet | Reglas de entrada de IP (`ipAllowList`): con la lista vacía se bloquea toda conexión externa y solo queda la red privada. |
| Costo cero para el curso | Plan **Free** para los 3 recursos (ver [Limitaciones](#limitaciones)). |

### Componentes

Creados **manualmente en el panel de Render**, sin conectar Render al repositorio de GitHub (`RobertoUNA/proyecto-seguridad`), en:
- Workspace "My Workspace", proyecto **`proyecto-seguridad`**, ambiente **`Pruebas`**;
- región **Ohio** y plan **Free**.

[`render.yaml`](../../render.yaml) es la **configuración declarativa equivalente**, versionada para que sea revisable y reproducible. Render no la lee (no hay repo conectado); se aplicó a mano en el panel.

| Recurso | Tipo | Configuración |
| :--- | :--- | :--- |
| `proyecto-seguridad-db` | Render Postgres | PostgreSQL 16, PostGIS 3.6, base `proyecto_seguridad_gpja` (Render agregó el sufijo), usuario `proyecto_seguridad`, vence 2026-12-13. **Todo el tráfico de Internet bloqueado** ("All internet traffic is blocked by PostgreSQL inbound IP rules"): solo red privada. **Datos:** reales de OIJ, COSEVI, SNIT y OSM desde el 2026-11-13 (ver [Carga de datos reales](#carga-de-datos-reales-2026-11-13)); antes tenía la semilla ficticia. |
| `proyecto-seguridad-backend` | Web service (imagen) | `https://proyecto-seguridad-backend-ajby.onrender.com`, health check `/api/health` |
| `proyecto-seguridad-frontend` | Web service (imagen) | `https://proyecto-seguridad-frontend.onrender.com`, health check `/`, `PORT=8080`, `API_UPSTREAM=https://proyecto-seguridad-backend-ajby.onrender.com` |

### Red

```text
 Navegador
    │ HTTPS (TLS de Render)
    ▼
 proyecto-seguridad-frontend.onrender.com     nginx, UID 101, :8080
    │  /       → SPA estática (cabeceras nosniff / DENY / Referrer-Policy)
    │  /api/*  → proxy_pass ${API_UPSTREAM}
    │ HTTPS por la URL PÚBLICA del backend
    │ (SNI + proxy_ssl_verify contra las CA del sistema; Host = dominio del backend)
    ▼
 proyecto-seguridad-backend-ajby.onrender.com NestJS, usuario node, PORT inyectado por Render
    │ TCP 5432 por la RED PRIVADA de Render (DB_HOST = hostname interno)
    ▼
 proyecto-seguridad-db                        Postgres 16 + PostGIS; ipAllowList vacía (sin Internet)
```

**Por qué el frontend usa la URL pública del backend:** en el plan Free, un web service **no puede recibir** tráfico por la red privada, aunque sí puede enviarlo a bases de datos de la misma región. Por eso:
- **frontend → backend:** va por la URL pública HTTPS del backend, con verificación de certificado;
- **backend → BD:** va por la red privada.

El upstream es configurable sin reconstruir la imagen: `API_UPSTREAM` se renderiza en la plantilla de nginx al arrancar (`frontend/nginx.conf.template`, PR #19). Los logs del frontend en Render muestran `Running envsubst on /etc/nginx/templates/default.conf.template to /tmp/default.conf`.

### Imágenes por digest

| Servicio | Imagen desplegada |
| :--- | :--- |
| backend | `docker.io/elrobb/proyecto-seguridad-backend@sha256:5e94b8daae3731aa950fb85e86c15a40cbcd12aa2f0e6cd6fe8cd9914c593652` |
| frontend | `docker.io/elrobb/proyecto-seguridad-frontend@sha256:f4731411996da6a9061a551cb3ebd9b8ec3d011550dfc44c26861e0fc322001c` |

- **Origen:** son las imágenes que publicó la compuerta `5.5` para `0961a7e` en la corrida [43528185151](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43528185151).
  - Checks `3.1`–`3.4` en `success`; compuerta final `APPROVED` (Trivy PASS, backend con 9 suprimidas por `EXC-03`, SBOM PASS y Conftest PASS, con `worktree_clean: true`).
  - Las etiquetas `sha-0961a7e…` y `development` apuntan a estos digests; `latest` no existe.
  - Las imágenes llevan `org.opencontainers.image.revision=0961a7ec33de584c75f8215c0aab2c124bd756d4` y usuario `node` / `101`.
- **Versión de recuperación: `6342cd32e5cb675ca7e26448e93cb1ae795d0d16`**, con backend `docker.io/elrobb/proyecto-seguridad-backend@sha256:b1763f4dde20eb348f948061d9e7421e8ba9e74044c59519a8028567e8ee4d34` y frontend `docker.io/elrobb/proyecto-seguridad-frontend@sha256:ef7f7909e82318488a4454b6eabd80dabaa7cba64fd102c04e6e9e41487ff851`.
  - Corrió en Render con la semilla y con los datos reales (smoke test 8/8 en ambos casos).
  - Su frontend ya tiene el upstream configurable; lo único que le falta es la corrección de `HAL-09`.

### Historial de despliegues

| # | Candidato | Imágenes (backend / frontend) | Motivo del cambio | Estado |
| :-: | :--- | :--- | :--- | :--- |
| 1 | `ddf53201e2899b99bd859b36f2ba28b8676e9d07` (`main`, corrida [43472950185](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43472950185)) | `5bfc15e6…` / `e478b510…` | Primera publicación real. Solo el backend llegó a correr en Render: el frontend tiene `proxy_pass http://backend:3000` fijo y nginx no arranca fuera de docker-compose. | Retirado; **no sirve** para recuperación en Render |
| 2 | `6342cd32e5cb675ca7e26448e93cb1ae795d0d16` (`development`, corrida [43496370884](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43496370884)) | `b1763f4d…` / `ef7f7909…` | Incluye el upstream configurable (`API_UPSTREAM`, PR #19) y las pruebas del backend (PR #7). Primer despliegue completo (frontend y backend). Después se cargaron los datos reales. La fusión `20f0725` (PR #11) solo cambió documentación, así que se mantuvo `6342cd3`. | **Versión de recuperación** |
| 3 | `0961a7ec33de584c75f8215c0aab2c124bd756d4` (`development`, corrida [43528185151](https://github.com/RobertoUNA/proyecto-seguridad/actions/runs/43528185151)) | `5e94b8da…` / `f4731411…` | Corrección de `HAL-09` (panorama con filtro de cantón), PR #29. Entre `6342cd3` y `0961a7e` solo cambian `frontend/src/App.tsx` y `frontend/src/components/CantonDetail.tsx`. El backend tiene el mismo código, pero se reconstruyó en la compuerta y por eso su digest es otro. | **Desplegado (actual)** |

- **`384d680`** (backend `af832742…`, frontend `bf74dc0f…`) se publicó y es compatible con Render, pero nunca se desplegó allí.
- **`deploy/last-approved-release.json`** y el 5.4 de [`docs/releases/v1.0.0-rc1.md`](../releases/v1.0.0-rc1.md) todavía apuntan a `384d680`. Actualizarlos a `6342cd3` les corresponde a sus dueños: Roberto (`6.6`) y Jose (`5.1`/`5.4`).

### Reproducir desde cero

1. **Base de datos.**
   - En Render, crear un **New → Postgres** con plan Free, región Ohio, PostgreSQL 16, usuario `proyecto_seguridad` y base `proyecto_seguridad`.
   - En *Networking → Inbound IP rules*, dejar **solo** la IP pública del operador como `/32`.
2. **Cargar el esquema una sola vez** desde la máquina del operador. Se usa la imagen fijada del proyecto y `sslmode=require`, y la contraseña solo como variable de la sesión, nunca en un archivo:
   ```powershell
   $env:PGPASSWORD = '<contraseña desde el panel de la BD>'   # solo en la sesión
   docker run --rm -e PGPASSWORD -v "${PWD}/backend/database:/sql:ro" `
     postgis/postgis:16-3.4@sha256:44126d872ac91993766c341e369c539e8196614321765d36a6f1bab0419a5fa5 `
     psql "host=<host EXTERNO de la BD> port=5432 dbname=<base> user=proyecto_seguridad sslmode=require" `
     -v ON_ERROR_STOP=1 `
     -f /sql/migrations/001_create_cantones.sql -f /sql/migrations/002_create_delitos.sql `
     -f /sql/migrations/003_create_accidentes.sql -f /sql/migrations/004_create_infraestructura.sql `
     -f /sql/seed_test.sql
   Remove-Item Env:PGPASSWORD
   ```
   `seed_test.sql` contiene datos **ficticios** (los mismos del CI): son los que permiten que respondan los smoke tests (`1001` → 200, `999999` → 404). Para tener datos reales, se omite la semilla y se aplica el procedimiento de [Carga de datos reales](#carga-de-datos-reales-2026-11-13); así se hizo en el ambiente `Pruebas`.
3. **Cerrar el acceso externo:** eliminar la regla `/32`. El panel debe mostrar "All internet traffic is blocked by PostgreSQL inbound IP rules".
4. **Backend.** Crear un **New → Web Service → Existing image** con `docker.io/elrobb/proyecto-seguridad-backend@sha256:<digest del candidato>`, plan Free, región Ohio y health check `/api/health`. Variables:
   - `DB_HOST`: hostname **interno** de la BD;
   - `DB_PORT=5432`;
   - `DB_USER`, `DB_NAME` y `DB_PASSWORD`: desde el panel de la BD;
   - `LOG_ACTOR_SALT`: con el botón *Generate*;
   - `LOG_TRUSTED_PROXY`: **no** se define.
5. **Frontend.** Crear un **New → Web Service → Existing image** con `docker.io/elrobb/proyecto-seguridad-frontend@sha256:<digest del mismo candidato>`, plan Free, región Ohio y health check `/`. Variables: `API_UPSTREAM=https://<backend>.onrender.com` y `PORT=8080`.
6. **Verificar** como en la sección siguiente: despertar el backend y luego correr el smoke test contra la URL del frontend.

### Verificación de `0961a7e` (versión actual)

El 2026-11-13, con los datos reales y después de despertar el backend:

| Comprobación | Resultado |
| :--- | :--- |
| `GET <frontend>/api/health` y `GET <backend>/api/health` | `200`, `status: ok`, `database: up`, PostGIS `3.6`, **`commit_sha: 0961a7ec33de584c75f8215c0aab2c124bd756d4`** en ambos: [`reports/render-health-0961a7ec33de584c75f8215c0aab2c124bd756d4.json`](../../reports/render-health-0961a7ec33de584c75f8215c0aab2c124bd756d4.json) |
| `scripts/smoke-test.ps1 -BaseUrl https://proyecto-seguridad-frontend.onrender.com` | **APPROVED 8/8**: 85 cantones; San José `indice_cobertura` 89; `999999` → 404; fecha inválida → 400. Reporte: [`reports/smoke-test-render-0961a7ec33de584c75f8215c0aab2c124bd756d4.json`](../../reports/smoke-test-render-0961a7ec33de584c75f8215c0aab2c124bd756d4.json). Ese reporte no incluye `commit_sha`, porque el campo se agregó en el PR #23, que se fusionó en `main` y aún no está en `development`; el commit queda demostrado por el reporte de `/api/health`. |
| `HAL-09` en el navegador (verificado por Brandon) | `HOMICIDIO` + Dota + Aplicar muestra el panorama (índice 15). `ASALTO` + Cartago + Aplicar muestra el panorama (índice 60, 1 358 delitos). No aparece "No se pudo cargar el panorama". `GET /api/cantones/1017/panorama` y `/3001/panorama` responden 200 con índices 15 y 60 (en el mismo reporte de `/api/health`). |
| Compuerta de la imagen | [`container-scan-0961a7e….json`](../../reports/container-scan-0961a7ec33de584c75f8215c0aab2c124bd756d4.json), [`conftest-0961a7e….json`](../../reports/conftest-0961a7ec33de584c75f8215c0aab2c124bd756d4.json), `trivy-*-0961a7e…` y `sbom-*-0961a7e…`, copiados del artefacto `release-gate-reports-0961a7e…`. Gitleaks dio `no leaks found` antes de versionarlos. |

**Revisión de los reportes nuevos:** Gitleaks v8.21.2 dio `no leaks found`, y no contienen contraseñas, sales, tokens ni el host de la BD. `Env` de las imágenes nuevas:
- **backend:** `PATH`, `NODE_VERSION`, `YARN_VERSION`, `NODE_ENV`, `PORT`, `COMMIT_SHA`;
- **frontend:** variables de nginx y `API_UPSTREAM` por defecto;
- ningún secreto en ninguna de las dos.

### Verificación inicial (`6342cd3`)

El 2026-11-13, con la **semilla ficticia** todavía cargada, y después de despertar el backend (la primera petición dio timeout y la segunda, 200). La verificación con datos reales está en [Carga de datos reales](#carga-de-datos-reales-2026-11-13).

| Comprobación | Resultado |
| :--- | :--- |
| `GET <frontend>/api/health` y `GET <backend>/api/health` | `200`, `status: ok`, `database: up`, PostGIS `3.6`, **`commit_sha: 6342cd32e5cb675ca7e26448e93cb1ae795d0d16`** en ambos: [`reports/render-health-6342cd32e5cb675ca7e26448e93cb1ae795d0d16.json`](../../reports/render-health-6342cd32e5cb675ca7e26448e93cb1ae795d0d16.json) |
| `/api/cantones/1001/panorama` y `/api/cantones/999999/panorama` (vía frontend y vía backend) | `200` y `404` en ambos caminos |
| `scripts/smoke-test.ps1 -BaseUrl https://proyecto-seguridad-frontend.onrender.com` | **APPROVED 8/8**: [`reports/smoke-test-render-6342cd32e5cb675ca7e26448e93cb1ae795d0d16.json`](../../reports/smoke-test-render-6342cd32e5cb675ca7e26448e93cb1ae795d0d16.json) |
| Cabeceras del frontend (`/` y `/api/health`) | `x-content-type-options: nosniff`, `x-frame-options: DENY`, `referrer-policy: strict-origin-when-cross-origin`; `x-correlation-id` en las respuestas de `/api` |
| Navegador (verificado por Brandon) | La aplicación carga el mapa con datos |

- **Revisión de los dos reportes:** Gitleaks v8.21.2 (`.gitleaks.toml`) dio `no leaks found`, y no contienen contraseñas, sales, tokens ni el host de la BD.
- **Verificación TLS hacia el backend:** que `/api/health` responda 200 **a través del frontend** demuestra que nginx validó el certificado del backend, porque `proxy_ssl_verify on` rechaza certificados no confiables. Se probó localmente con un certificado autofirmado: `502` y `upstream SSL certificate verify error`.

### Carga de datos reales (2026-11-13)

La semilla ficticia (`seed_test.sql`: cantones `1001`/`2001`/`3001` con rectángulos de prueba, 2 delitos, 2 accidentes y 2 hospitales "(Test)") se **reemplazó por los datos reales** de las 4 fuentes OSINT, cargados con los workers del repositorio.

**Procedimiento (plan B: carga local y luego transferencia única):** los workers insertan fila por fila, así que contra Render cada inserción sería un viaje de red a Ohio. Se cargó primero en local y se transfirió en un solo paso, con la ventana de acceso externo abierta solo unos minutos.

1. **BD local temporal:**
   - contenedor `ps-ingesta-db` (`postgis/postgis:16-3.4@sha256:44126d87…`), en una red Docker propia y sin puertos publicados;
   - contraseña aleatoria generada en la sesión, sin escribirla en archivos;
   - migraciones `001..004` **sin** la semilla.
2. **Workers en un contenedor aislado:**
   - imagen `python:3.12-slim@sha256:5e2bdb1b0d542d5039cffb8181c65930093949194a65c365dfb1b0fe13a4fa5b`, con `--cap-drop ALL` y `no-new-privileges`;
   - solo `workers/` montado de solo lectura, así que `backend/.env` no era visible (lo que importa porque `cosevi` y `osm` lo leen si existe);
   - `OSM_CONTACT_EMAIL` con el correo institucional del operador (política de uso de Overpass).

   | Paso | Worker | Resultado | Duración |
   | :-: | :--- | :--- | :-: |
   | 1 | `snit/fetch_cantones.py` | 82 features de ArcGIS: 81 cantones y 1 feature vacío omitido | 3 s |
   | 2 | `snit/backfill_cantones.py` | 5 cantones DTA 2022 sin geometría (`2012` ya existía en ArcGIS como "Valverde Vega" y quedó como "Sarchí") | 0 s |
   | 3 | `oij/fetch_delitos.py --anio 2020 2021 2022 2023 2024 2025` | 258 150 registros → 188 582 agregados | 44 s |
   | 4 | `cosevi/fetch_accidentes.py` | 93 699 registros (2020–2025) → 21 333 agregados. **Requirió un ajuste** (ver la nota) | 5 s |
   | 5 | `osm/fetch_infraestructura.py` | 1 916 elementos de `overpass-api.de` | 47 s |

3. **Validación local:**
   - conteos y cantones `1001`/`2001`/`3001` con nombre, población y geometría reales;
   - `999999` inexistente, geometrías válidas (`ST_IsValid`) y 0 registros de la semilla.
4. **Volcado:** `pg_dump --data-only --no-owner --no-privileges` de `canton`, `delito`, `accidente` e `infraestructura`: `COPY` (primero `canton`) más `setval` de las secuencias. Tamaño: 24 033 231 bytes. **SHA-256 `a1a3d00dd962c8798a14ed064611f74d263e731b7e15ee73197d3f016f62da35`**. Se guardó fuera del repositorio y se eliminó después de la carga.
5. **Ensayo:** sobre una base local que imitaba Render (migraciones y semilla):
   - la carga completa en una sola transacción terminó con `exit 0` en 12 s;
   - con un volcado corrupto, falló (`ON_ERROR_STOP`) y **revirtió todo**.
6. **Carga en Render:** la ejecutó el operador desde su terminal.
   - Abrió temporalmente su IP pública `/32` en *Inbound IP rules*.
   - Pasó la contraseña con `Read-Host -AsSecureString` a `PGPASSWORD` (solo en la sesión) y usó `PGSSLMODE=require`.
   - Usó el contenedor `postgis/postgis:16-3.4` fijado, con el volcado montado de solo lectura:
     ```text
     psql "host=<host externo> port=5432 dbname=proyecto_seguridad_gpja user=proyecto_seguridad" -1 -v ON_ERROR_STOP=1 -q \
       -c "TRUNCATE TABLE public.infraestructura, public.accidente, public.delito, public.canton RESTART IDENTITY CASCADE;" \
       -f /dump/datos-reales.sql
     ```
   - **Resultado:** `exit=0`, con la verificación posterior `85|188582|21333|1916|San José`.
7. **Cierre:** se eliminó la regla `/32` (otra vez "All internet traffic is blocked by PostgreSQL inbound IP rules") y se borraron `PGPASSWORD` y `PGSSLMODE` de la sesión. Del lado local se eliminaron el contenedor, la red, el volumen, el volcado y los CSV.

**Datos en Render tras la carga:**

| Tabla | Filas | Sin cantón / sin geometría | Fuente y periodo |
| :--- | ---: | :--- | :--- |
| `canton` | 85 | 4 sin geometría | SNIT/ArcGIS (81) + SNIT/IGN DTA 2022 (5) |
| `delito` | 188 582 | 589 sin `canton_id` | OIJ/CKAN, 2020-01-01 a 2025-12-31 (258 150 registros) |
| `accidente` | 21 333 | 143 sin `canton_id` | COSEVI, 2020–2025 (93 699 registros) |
| `infraestructura` | 1 916 | 2 sin `canton_id` | OSM/Overpass: 1 141 clínicas, 663 comisarías, 112 hospitales |

**Verificación después de la carga (2026-11-13):**
- [`reports/smoke-test-render-datos-reales-6342cd32e5cb675ca7e26448e93cb1ae795d0d16.json`](../../reports/smoke-test-render-datos-reales-6342cd32e5cb675ca7e26448e93cb1ae795d0d16.json): **APPROVED 8/8** vía el frontend. Gitleaks dio `no leaks found`.
- `/api/cantones`: 85 features (4 sin geometría).
- `/api/cantones/1001/panorama`: San José, `indice_cobertura = 89`; 48 900 delitos, 10 512 accidentes y 189 puntos de infraestructura (17 hospitales, 108 clínicas, 64 comisarías).
- `/api/cantones/999999/panorama`: `404`.

> **Nota — COSEVI.** El CSV oficial (`2 Base de accidentes con victimas 2020_ 2025_UTF8.csv`, SHA-256 `63cd529d8ec47c3cfc12e372fc70d28c7875fdfca90f3d7fca0ffc3cad291e81`) viene en **Windows-1252**, aunque el nombre diga UTF-8.
> - El worker lo decodifica como `utf-8-sig` y falló con `'utf-8' codec can't decode byte 0xf1` (la "ñ" de "Año").
> - Sin modificar el worker, el mismo archivo se convirtió a UTF-8 (SHA-256 `81594b19ef0c2e69394f267366fff16d9cc65ebeb2a57c20dfd9a2e5941905fc`). Se comprobó que la conversión es reversible byte a byte.
> - Se sirvió en la red Docker aislada mediante `COSEVI_CSV_URL`, que el worker ya admite.
> - Además, 263 registros con cantón "VALVERDE VEGA" no se vinculan, porque ese cantón ahora se llama "Sarchí" y el worker no tiene ese alias.
> - Registrado como **`HAL-08`** en [`REGISTRO-HALLAZGOS.md`](./REGISTRO-HALLAZGOS.md).

### Endurecimiento conservado y perdido frente a docker-compose

| Control | docker-compose | Render |
| :--- | :--- | :--- |
| Usuario no root (`CTL-05`) | `node` / `101` | **Conservado**: la misma imagen (`Config.User` = `node` / `101`) |
| Imagen inmutable y aprobada | Build local | **Mejorado**: imagen por digest aprobada por la compuerta `5.5` |
| BD sin acceso público | Red interna `data`, sin `ports` | **Conservado**: `ipAllowList` vacía, solo red privada |
| TLS | No aplica (HTTP interno) | **Mejorado**: HTTPS gestionado por Render; frontend → backend con TLS **verificado** (SNI + CA) |
| Cabeceras de seguridad, `server_tokens off`, sobrescritura de `X-Forwarded-For` | Sí | **Conservado** (misma configuración de nginx) |
| Secretos solo en el entorno (`CTL-03`) | Variables de la sesión | **Conservado**: variables de entorno de Render (ver `6.4`) |
| `read_only: true` + `tmpfs` | Sí | **Perdido**: Render no ofrece un sistema de archivos raíz de solo lectura |
| `cap_drop: [ALL]`, `no-new-privileges` | Sí | **Perdido**: Render no expone estas opciones |
| Backend solo detrás del frontend | El backend se publica solo en `127.0.0.1` | **Perdido parcialmente**: el backend tiene URL pública (requisito del plan Free). La API es de solo lectura (`GET`), los límites de `CTL-02` siguen activos y el CORS es el del backend (`enableCors()`). |
| Rotación de logs (`json-file` 10m×5) | Sí | **Distinto**: los logs los retiene Render según su plan |

---

## 6.4 — Gestión de secretos

### Inventario por consumidor

| Secreto | Consumidor | Dónde vive | Quién lo gestiona / accede | Cómo llega al proceso |
| :--- | :--- | :--- | :--- | :--- |
| `DOCKERHUB_USERNAME` (`SEC-03`) | Pipeline: job de publicación de `release-deploy.yml` (`5.5`) | GitHub Actions secrets del repositorio | **RobertoUNA** (administración del repo). Solo lo leen los pasos que lo declaran en `env` y `docker/login-action`. GitHub lo enmascara en los logs. | `${{ secrets.DOCKERHUB_USERNAME }}` |
| `DOCKERHUB_TOKEN` (`SEC-03`) | Pipeline: login y push a Docker Hub | GitHub Actions secrets | **RobertoUNA**. Solo `docker/login-action` y la verificación previa de `SEC-03`. | `${{ secrets.DOCKERHUB_TOKEN }}` |
| `DB_PASSWORD` | Aplicación: backend (TypeORM) | Variables de entorno del servicio backend en Render (copiada del panel de la BD) | **Brandon**. Lo ven los miembros del workspace de Render con acceso al servicio o a la BD. | `process.env.DB_PASSWORD` |
| `LOG_ACTOR_SALT` | Aplicación: backend (`7.2`, hash del `actor_id`) | Variables de entorno del backend en Render (botón *Generate*) | **Brandon**. Los mismos accesos que `DB_PASSWORD`. | `process.env.LOG_ACTOR_SALT` |

- **Variables no secretas:**
  - `DB_HOST` (hostname interno, solo alcanzable por la red privada), `DB_PORT`, `DB_USER` y `DB_NAME`;
  - en el frontend, `API_UPSTREAM` y `PORT`;
  - `COMMIT_SHA`, que viene dentro de la imagen (`ENV`).
- **Docker Hub en Render:** las imágenes son públicas, así que Render no necesita ninguna credencial de Docker Hub.
- **Nombres en GitHub:** `gh api repos/RobertoUNA/proyecto-seguridad/actions/secrets` lista solo los **nombres** `DOCKERHUB_TOKEN` y `DOCKERHUB_USERNAME` (actualizados el 2026-11-12). Los valores no son visibles.

### Reemplazo (rotación)

| Secreto | Procedimiento | Efecto |
| :--- | :--- | :--- |
| `DB_PASSWORD` | 1) En el panel de la BD, usar **Credential Rotation** para crear una credencial nueva. 2) Actualizar `DB_PASSWORD` (y `DB_USER` si cambia) en el backend; Render redespliega el servicio. 3) Verificar `/api/health` (`database: up`). 4) Eliminar la credencial anterior. | Corte breve durante el redespliegue. No requiere reconstruir la imagen. |
| `LOG_ACTOR_SALT` | Regenerar el valor en las variables del backend (*Generate*) y redesplegar. | El `actor_id` de una misma IP **cambia**: los eventos anteriores y posteriores no se pueden correlacionar por actor, y los contadores de la alerta SIG-01 (N=10 en T=5 min por actor) empiezan de cero. `actor_id_scope` sigue `persistent`. Se recomienda rotar fuera de una investigación en curso. |
| `DOCKERHUB_TOKEN` | 1) En Docker Hub (cuenta `elrobb`), crear un *access token* nuevo con permiso de escritura solo para los repos del proyecto. 2) Reemplazar `DOCKERHUB_TOKEN` en GitHub Actions secrets (RobertoUNA). 3) Revocar el token anterior. 4) Verificar con la siguiente corrida de `release-deploy.yml`. | No afecta a Render (imágenes públicas) ni a las imágenes ya publicadas. |

### Dónde **no** hay secretos (y cómo se verificó)

| Lugar | Verificación |
| :--- | :--- |
| Repositorio Git | **Configuración del despliegue:** `render.yaml` no contiene valores secretos (`fromDatabase`, `generateValue`, `sync: false`). No hay `.env` versionado. **Historial completo:** el check `3.2` corre Gitleaks sobre árbol e historial (`fetch-depth: 0`) en cada push; en `20f0725` dio `success`. **Evidencia nueva:** los reportes nuevos de `reports/` se revisaron con Gitleaks antes de versionarlos (`no leaks found`). |
| Imágenes | `docker image inspect` del backend `b1763f4d…` (y del actual `5e94b8da…`, con los mismos nombres de variables): `Env` = `PATH`, `NODE_VERSION`, `YARN_VERSION`, `NODE_ENV=production`, `PORT=3000`, `COMMIT_SHA`, sin secretos. Búsqueda de `.env*`, `*.pem` e `id_rsa*` fuera de `node_modules`: solo los bundles públicos de CA (`/etc/ssl/cert.pem`, `/etc/ssl1.1/cert.pem`). Gitleaks sobre `/app/dist` (backend) y `/usr/share/nginx/html` (frontend), extraídos de las imágenes: `no leaks found`. |
| Artefactos de CI | El `candidate-release` y los reportes de la compuerta (`-ddf5320…`, `-6342cd3…`, `-0961a7e…`) se revisaron con Gitleaks antes de copiarlos a `reports/`: `no leaks found`. El usuario `elrobb` aparece porque es parte del nombre público de la imagen; no es una credencial. |
| Logs | **Backend:** los eventos de seguridad (`7.2`) registran `actor_id` = SHA-256(sal\|IP) truncado y nunca la IP, los valores de los parámetros ni el stack. Se verificó con la misma imagen del backend en docker-compose: [`reports/verify-security-logs-bd5a92a572119b2b568aea83b4e7dcc8ce631164.txt`](../../reports/verify-security-logs-bd5a92a572119b2b568aea83b4e7dcc8ce631164.txt) da `PASS`, sin IPs en claro, sin valores de parámetros y sin `Authorization`/`Cookie` (ver [`07-operacion-investigacion-ia.md`](./07-operacion-investigacion-ia.md)). En Render no se versionó una muestra de logs del backend. **GitHub Actions:** enmascara los secretos (`***`). |
| Frontend (navegador) | El bundle no contiene la URL del backend ni variables del servidor. El navegador solo llama a `/api` en el mismo origen, y `API_UPSTREAM` vive solo en la configuración de nginx. Se buscó `onrender.com`, `DB_PASSWORD` y `LOG_ACTOR_SALT` en `/usr/share/nginx/html`: 0 coincidencias. |

---

## Limitaciones

- **`actor_id` detrás del proxy de Render.** `LOG_TRUSTED_PROXY` no se define, así que el backend no confía en `X-Forwarded-For` y usa la IP del socket, que en Render es un salto del proxy de Render, no el cliente. Es seguro (no se puede falsificar), pero el `actor_id` agrupa a muchos clientes, y la alerta SIG-01 pierde granularidad por actor en este ambiente. El `correlation_id` sigue funcionando de punta a punta. Para corregirlo habría que confiar en el XFF de Render, conociendo sus saltos y rangos de IP, que no están verificados.
- **Servicios dormidos (plan Free).** Render apaga un web service Free tras 15 minutos sin tráfico entrante.
  - La primera petición tarda unos 50 s.
  - Si el frontend despierta antes que el backend, la primera llamada a `/api` puede devolver **504**, por los timeouts de nginx (5 s de conexión y 30 s de lectura).
  - Antes de una demostración, conviene despertar primero el backend.
- **Vencimiento de la BD.** La base Free vence el **2026-12-13** (Render da 30 días desde la creación y un periodo de gracia antes de eliminarla). No tiene respaldos: **los datos reales cargados se pierden con ella**. Para recrearlos hay que repetir el procedimiento de [Carga de datos reales](#carga-de-datos-reales-2026-11-13); el volcado no se conserva, porque se regenera con los workers.
- **Cobertura de los datos reales:**
  - **4 cantones sin geometría:** `2016` Río Cuarto, `6012` Quepos, `6013` Monteverde y `6014` Puerto Jiménez, creados después de 2015 y ausentes de la capa ArcGIS. No se dibujan en el mapa y no reciben infraestructura OSM, porque esta se asigna con `ST_Contains`.
  - **Registros sin cantón vinculado:** 589 delitos (cantón "DESCONOCIDO" en el CSV del OIJ), 143 accidentes (incluido "VALVERDE VEGA", ver `HAL-08`) y 2 puntos de infraestructura fuera de las geometrías disponibles. Se conservan con `canton_id NULL` y no cuentan en el panorama de ningún cantón.
  - **Instantánea del 2026-11-13:** no hay ingesta programada, así que los datos no se actualizan solos.
- **PostGIS 3.6 en Render vs 3.4 en local/CI.** Las funciones usadas (`ST_GeomFromText`, `PostGIS_Version`, …) se comportan igual, y el smoke test pasó 8/8. Aun así, es una diferencia de versión entre ambientes.
- **Sin `read_only` ni `cap_drop`** en Render (ver la tabla de endurecimiento).
- **Despliegue manual.** El ítem `6.1` (despliegue automatizado) no fue seleccionado. Los servicios se crearon y actualizan a mano en el panel, siempre **por digest**, y `render.yaml` documenta el estado equivalente.
- **Aviso de `10-listen-on-ipv6-by-default.sh`** en los logs del frontend: es informativo. El script no modifica la configuración, porque `default.conf` solo hace `include /tmp/default.conf`, y el servicio responde 200.
- **Rollback.** En Render, revertir significa cambiar los digests de **ambos** servicios a los de `6342cd3` en el panel (backend `b1763f4d…`, frontend `ef7f7909…`) y luego correr el smoke test. Al revertir vuelve el defecto `HAL-09`. Los scripts `scripts/rollback.*` (Roberto, `6.6`) restauran con docker-compose y no actúan sobre Render.
- **Nombre del documento:** el PLAN preveía `06-despliegue-seguro.md` y `deploy/docker-compose.prod.yml`. El despliegue real es en Render y queda documentado aquí y en `render.yaml`.
