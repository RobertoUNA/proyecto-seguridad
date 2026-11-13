# Operación: Registro de Eventos de Seguridad e Investigación con IA (Etapa 7)

> **Ítems:** `7.2` (registro de eventos de seguridad) · `7.4` (investigación de una alerta con IA)  
> **Responsable:** Brandon Corrales (`Brandon-Corrales`) · **Revisor:** Billy Ugalde (`Billy-Ugalde`)  
> **Amenaza / control:** [`THR-06` / `CTL-06`](./01-planificacion-kb.md#3-amenazas-priorizadas-con-stride-ítem-13-y-plan-de-tratamiento-ítem-14) (Repudiation: falta de trazabilidad ante intentos repetidos de abuso). Apoya también la detección de `THR-01` (inyección en parámetros).

---

## 7.2 — Registro de eventos de seguridad

> **Commit analizado (evidencia vigente):** `bd5a92a572119b2b568aea83b4e7dcc8ce631164`. Contiene el código del ítem (`3ad2ecf`) y la corrección del mensaje de `policy-check` (`bd5a92a`), que no afecta al backend. Stack reconstruido con `COMMIT_SHA=bd5a92a…` (`GET /api/health` devuelve ese `commit_sha`), árbol limpio.  
> **Reportes:**
> - [`reports/security-events-sample-bd5a92a572119b2b568aea83b4e7dcc8ce631164.jsonl`](../../reports/security-events-sample-bd5a92a572119b2b568aea83b4e7dcc8ce631164.jsonl): 6 eventos reales, uno por cada petición con error.
> - [`reports/security-traffic-bd5a92a572119b2b568aea83b4e7dcc8ce631164.json`](../../reports/security-traffic-bd5a92a572119b2b568aea83b4e7dcc8ce631164.json): qué se envió, código HTTP y `correlation_id` devuelto.
> - [`reports/verify-security-logs-bd5a92a572119b2b568aea83b4e7dcc8ce631164.txt`](../../reports/verify-security-logs-bd5a92a572119b2b568aea83b4e7dcc8ce631164.txt): **PASS**.
> - [`reports/smoke-test-compose-bd5a92a572119b2b568aea83b4e7dcc8ce631164.json`](../../reports/smoke-test-compose-bd5a92a572119b2b568aea83b4e7dcc8ce631164.json): **8/8**.

### Resultado sobre `bd5a92a`

| Petición (`security-log-sample.ps1`) | HTTP | Evento registrado | `route` | `suspicious_patterns` |
| :--- | :---: | :--- | :--- | :--- |
| normal `/api/cantones` | 200 | — (los 2xx no generan evento) | | |
| fecha inválida | 400 | `validation_rejected` | `/api/delitos` | `[]` |
| cantón inexistente | 404 | `not_found` | `/api/cantones/:id/panorama` | `[]` |
| ruta inexistente | 404 | `not_found` | `/api/ruta-inexistente` | `[]` |
| `?canton=' OR 1=1--` | 400 | `abuse_suspected` | `/api/delitos` | `["sql_injection"]` |
| `POST /api/cantones` | 404 | `access_denied` | `/api/cantones` | `[]` |
| mismo 404 vía nginx `:8080` | 404 | `not_found` | `/api/cantones/:id/panorama` | `[]` |

**Cruce y comprobaciones:**
- Cada `correlation_id` del manifiesto coincide con el de su evento.
- Todos los eventos tienen el **mismo `actor_id`** (`b4231f77ae16e55c`), incluida la petición de inyección, que llevaba un `X-Forwarded-For` falso directo a `:3001` (se ignoró) y la que pasó por nginx.
- Búsqueda en los cuatro reportes: **0** apariciones de la sal, de `DB_PASSWORD`/`PASSWORD`, de las cabeceras ficticias (`Bearer`, cookie) y de **direcciones IPv4**. El texto `' OR 1=1--` solo aparece en la *descripción* de la prueba dentro de `security-traffic-….json`, y **0** veces en la muestra de eventos.

### Contexto de la KB: qué eventos existen en esta versión

Según la [matriz de control de acceso](./01-planificacion-kb.md#matriz-de-control-de-acceso-actorrol--recurso--acción--condición), la API es **pública, de solo lectura y sin sesión**: el único actor externo es el *Usuario Anónimo*, que puede hacer `GET` sobre `/api/*`, y toda escritura está denegada. El código lo confirma: no hay guards, autenticación ni rutas `POST/PUT/PATCH/DELETE` en `backend/src`.

| Evento pedido por el ítem | ¿Existe en esta versión? | Tratamiento |
| :--- | :---: | :--- |
| Intentos fallidos de autenticación | **No existe en esta versión** | No hay login, tokens ni sesiones: no hay ninguna autenticación que pueda fallar. No se inventa el evento. Si una versión futura agrega autenticación, debe registrarse `auth_failed` con el mismo formato. |
| Cambios de privilegios | **No existe en esta versión** | No hay usuarios, roles ni administración por API. Los cambios de privilegios reales (rol `seguridad_vial` en PostgreSQL, secretos de CI) ocurren fuera de la aplicación y se controlan con revisión humana (`SEC-01`, `SEC-05`). |
| Accesos denegados | **Sí** | Cualquier intento de **escritura** (`POST/PUT/PATCH/DELETE`) sobre la API de solo lectura, que Nest rechaza con `404`/`405`, más los `401`/`403` si llegaran a existir → `access_denied`. |
| Entradas rechazadas / abuso | **Sí** | `400` del `ValidationPipe` y de los servicios (`validation_rejected`), recursos o rutas inexistentes (`not_found`), entradas con patrones de ataque (`abuse_suspected`) y errores `5xx` (`server_error`). |

### Implementación

| Archivo | Función |
| :--- | :--- |
| [`backend/src/common/correlation-id.middleware.ts`](../../backend/src/common/correlation-id.middleware.ts) | Acepta `X-Correlation-Id` **solo si es un UUID válido**; si falta o es inválido genera uno nuevo (`crypto.randomUUID`) y lo devuelve en la respuesta. Un valor arbitrario del cliente nunca llega al log. |
| [`backend/src/common/security-event.filter.ts`](../../backend/src/common/security-event.filter.ts) | Filtro global (`@Catch()`, extiende `BaseExceptionFilter`). Para cada respuesta `>= 400` escribe **una línea JSON** en stdout. Las `HttpException` (400, 404…) se delegan a `super.catch()`. Los **errores no controlados (5xx)** los responde el propio filtro con el **mismo cuerpo genérico de Nest** y no se delegan, para que el logger de Nest no imprima el mensaje ni el stack. El código HTTP y el cuerpo que recibe el cliente **no cambian**. |
| [`backend/src/common/security-logging.module.ts`](../../backend/src/common/security-logging.module.ts) | Registra el filtro con `APP_FILTER` y el middleware con `NestModule.configure` (`forRoutes('*')`), **sin tocar `main.ts`**. |
| `backend/src/app.module.ts` | Única modificación autorizada: `import { SecurityLoggingModule }` y su entrada en `imports`. |
| [`docker-compose.yml`](../../docker-compose.yml) | `LOG_ACTOR_SALT: ${LOG_ACTOR_SALT:-}` (solo desde el entorno) y `LOG_TRUSTED_PROXY: frontend`. |
| [`frontend/nginx.conf`](../../frontend/nginx.conf) | `proxy_set_header X-Forwarded-For $remote_addr;`: nginx **sobrescribe** la cabecera con la IP real de la conexión y descarta la que envía el cliente. |
| [`scripts/verify-security-logs.py`](../../scripts/verify-security-logs.py) | Verificador (biblioteca estándar). Falla si encuentra IPs en claro, valores enviados, cabeceras `Authorization`/`Cookie` o formatos inválidos, y exige que la inyección quede marcada. |
| [`scripts/security-log-sample.ps1`](../../scripts/security-log-sample.ps1) | Genera el tráfico controlado (solo `localhost`), extrae los eventos reales de `docker compose logs backend` y ejecuta el verificador. |

**Por qué filtro + middleware y no un "interceptor".** La KB (`CTL-06`) menciona un *interceptor de logs*. Se usó un **filtro global de excepciones + middleware** porque en NestJS un interceptor solo envuelve rutas que coinciden con un controlador: **no ve los 404 de rutas inexistentes** (Nest los genera sin pasar por ningún controlador), que son justamente las señales de escaneo. El filtro global recibe **todas** las excepciones HTTP en un único punto: 404 de rutas inexistentes, 400 del `ValidationPipe` y de los servicios, 404 de recursos y 5xx. El middleware asigna el `correlation_id` antes de cualquier procesamiento.

### Formato del evento

| Campo | Contenido | Qué NO contiene |
| :--- | :--- | :--- |
| `timestamp` | ISO-8601 UTC | |
| `level` | `warn` (4xx) / `error` (5xx) | |
| `log_type` | `security_event` (para filtrarlos del resto del log) | |
| `event_type` | `validation_rejected`, `not_found`, `access_denied`, `abuse_suspected`, `server_error` | |
| `correlation_id` | UUID (el del cliente si es válido, si no uno nuevo); el mismo se devuelve en `X-Correlation-Id` | Valores no UUID enviados por el cliente |
| `method` | `GET`, `POST`, … | |
| `route` | **Patrón** de la ruta si coincide (`/api/cantones/:id/panorama`); en rutas inexistentes, la ruta sin query y con los segmentos con forma de dato sustituidos por `:redacted` | Query string, valores de `:id` |
| `status_code` | Código HTTP enviado al cliente | |
| `param_names` | Solo nombres: `query.desde`, `path.id`, `body.x` | **Valores** de los parámetros |
| `suspicious_patterns` | Nombres de los patrones detectados en los valores: `sql_injection`, `path_traversal`, `xss`, `command_injection`, `oversized_input` | El valor que activó el patrón |
| `actor_id` | `SHA-256(LOG_ACTOR_SALT + IP)` truncado a 16 hex | La IP en claro |
| `actor_id_scope` | `persistent` (con `LOG_ACTOR_SALT`) o `process` (sal aleatoria del proceso) | |
| `error_class` | Solo en errores no controlados: nombre de la clase del error (`QueryFailedError`, `Error`…) | Mensaje del error, SQL, stack |

**Nunca se registran:** el mensaje de la excepción (los servicios lo construyen con la entrada del cliente, p. ej. `Cantón no encontrado: <valor>`), las cabeceras (`Authorization`, `Cookie`, `User-Agent`…), el cuerpo, la IP, el SQL ni el stack trace. Las respuestas `2xx` no generan eventos.

**Errores 5xx sin stack ni SQL.** Por defecto, el `ExceptionsHandler` de Nest escribe en los logs el mensaje y el stack de todo error no controlado. En un `QueryFailedError` de TypeORM ese mensaje incluye la consulta SQL y el nombre de las tablas. Para cumplir el ítem (no registrar contenido sensible), el filtro responde esos errores sin pasar por ese logger. Usa el mismo adaptador HTTP y el mismo cuerpo `{"statusCode":500,"message":"Internal server error"}`; los errores de la librería `http-errors` conservan su `statusCode` y `message`, como hace Nest. El evento `server_error` solo agrega `error_class`.

**`actor_id` y `LOG_ACTOR_SALT`.**
- Con `LOG_ACTOR_SALT` definida, el mismo cliente tiene el mismo `actor_id` entre reinicios (`actor_id_scope: persistent`). Así se pueden correlacionar intentos repetidos (`THR-06`, base del `7.4`).
- **Si `LOG_ACTOR_SALT` no existe, el filtro funciona igual** con una sal aleatoria de 32 bytes generada al iniciar el proceso (`actor_id_scope: process`). En ese caso **el `actor_id` no se puede correlacionar entre reinicios** del backend.
- La sal es un **secreto**: sin ella, recuperar la IP desde el hash exige fuerza bruta con sal desconocida; con ella, el espacio IPv4 (2³²) se recorre en minutos. Por eso solo se toma del entorno y nunca se escribe en archivos.

**Proxy de confianza (`LOG_TRUSTED_PROXY`), equivalente a `trust proxy = 1`.** Sin `main.ts` no se puede configurar `trust proxy` de Express, así que el filtro aplica la misma regla:

1. nginx **sobrescribe** `X-Forwarded-For` con `$remote_addr`, la IP real de la conexión. Ya no se usa `$proxy_add_x_forwarded_for`, que agregaba la cabecera del cliente.
2. El backend resuelve por DNS el nombre `LOG_TRUSTED_PROXY` (`frontend`, el nginx; refresco cada 30 s). Solo si la conexión TCP viene de esa IP toma **el último salto** de `X-Forwarded-For`.
3. Cualquier otra conexión, incluida la directa a `127.0.0.1:3001`, usa la IP del socket e ignora la cabecera. Sin `LOG_TRUSTED_PROXY` nunca se confía en ella.

Así ningún cliente puede elegir su `actor_id`, y el tráfico que pasa por nginx conserva la IP real del cliente (no la del contenedor nginx).

### Ejemplo real

Líneas reales de `docker compose logs backend`, verificación local del 2026-11-12:

```json
{"timestamp":"2026-11-12T01:47:31.367Z","level":"warn","log_type":"security_event","event_type":"abuse_suspected","correlation_id":"cfb4630e-e542-4720-855b-c1bb0ddc03c9","method":"GET","route":"/api/delitos","status_code":400,"param_names":["query.canton"],"suspicious_patterns":["sql_injection"],"actor_id":"b4231f77ae16e55c","actor_id_scope":"persistent"}
{"timestamp":"2026-11-12T01:47:31.247Z","level":"warn","log_type":"security_event","event_type":"not_found","correlation_id":"a8ac17f3-76cc-439e-bb87-b60d8bbea71b","method":"GET","route":"/api/cantones/:id/panorama","status_code":404,"param_names":["path.id"],"suspicious_patterns":[],"actor_id":"b4231f77ae16e55c","actor_id_scope":"persistent"}
{"timestamp":"2026-11-12T01:59:01.108Z","level":"error","log_type":"security_event","event_type":"server_error","correlation_id":"a8992e34-2a2d-4667-a9fa-512f6f60e4c2","method":"GET","route":"/api/cantones","status_code":500,"param_names":[],"suspicious_patterns":[],"actor_id":"b4231f77ae16e55c","actor_id_scope":"persistent","error_class":"QueryFailedError"}
```

- La primera corresponde a `GET /api/delitos?canton=' OR 1=1--`: el log dice que llegó `query.canton` con forma de inyección SQL, pero **no contiene el payload**.
- La segunda es `GET /api/cantones/999999/panorama`: se registra el patrón `:id`, no `999999`.
- La tercera es un `QueryFailedError` provocado al renombrar temporalmente la tabla `canton` en la BD local. Es **la única línea** que quedó en `docker logs`: no hay SQL, nombre de tabla ni stack.

### Verificación adicional (antes del commit, con el mismo código)

- Smoke tests contra `:3001` con `-ReportPath` propio: **8/8 PASS** (incluye el `404` y el `400`). `reports/smoke-test-report.json` se mantiene intacto.
- Tráfico de `scripts/security-log-sample.ps1`:
  - petición normal (`200`, sin evento);
  - fecha inválida (`400` → `validation_rejected`);
  - cantón inexistente (`404` → `not_found`);
  - ruta inexistente (`404` → `not_found`);
  - `?canton=' OR 1=1--` (`400` → `abuse_suspected` + `sql_injection`);
  - `POST /api/cantones` (`404` → `access_denied`);
  - el mismo `404` pasando por nginx.
  - Se enviaron `Authorization` y `Cookie` ficticias y un `X-Forwarded-For` de TEST-NET-3.
- `X-Correlation-Id`: un UUID válido enviado por el cliente se devuelve igual; `no-es-uuid<script>` se reemplaza por un UUID nuevo.
- `verify-security-logs.py`: **PASS**. Comprobó 5 IPs de cliente (loopback, gateways de las redes del proyecto, IP de nginx y el XFF ficticio), 8 valores prohibidos (payload, fecha, `999999`, cabeceras ficticias), la ausencia de claves `authorization`/`cookie`, el formato de cada campo y los tipos de evento esperados.
- **Prueba negativa del verificador:** una línea fabricada con IP en claro, `route` con query, `param_names` con valor, `correlation_id` no UUID y clave `authorization` produjo **FAIL con 9 problemas** más el patrón ausente.
- **5xx idéntico para el cliente y sin stack en logs.** Con la BD detenida, la respuesta 500 antes y después del cambio es **idéntica**: estado, cabeceras, `Content-Length: 52`, `ETag: W/"34-rlKccw1E+/fV8niQk4oFitDfPro"` y cuerpo; solo cambian `Date` y `X-Correlation-Id`.
  - **Antes:** `docker logs` contenía `ERROR [ExceptionsHandler] getaddrinfo EAI_AGAIN db` y el stack.
  - **Después:** solo contiene el evento `server_error` con `error_class: "Error"`.
  - Con un `QueryFailedError` forzado, el log tampoco tiene SQL ni stack.
- **`X-Forwarded-For` no falsificable.**

  | Petición | `actor_id` |
  | :--- | :--- |
  | `:8080` con `XFF: 203.0.113.10` | `b4231f77ae16e55c` |
  | `:8080` con `XFF: 198.51.100.99, 1.2.3.4` | `b4231f77ae16e55c` |
  | `:8080` sin XFF | `b4231f77ae16e55c` |
  | `:3001` directo con `XFF: 203.0.113.10` | `b4231f77ae16e55c` |
  | `:3001` directo sin XFF | `b4231f77ae16e55c` |

  Los valores falsos se descartan. Que el tráfico por nginx coincida con el directo prueba que nginx reenvía la IP real del cliente y que el backend la acepta solo desde `frontend`: si ignorara la cabecera, usaría la IP del contenedor nginx y el `actor_id` sería distinto.
- Tras cambiar `nginx.conf` y `docker-compose.yml`:
  - `scripts/policy-check.ps1`: `APPROVED` (25/25, reales permitidos, ejemplos rechazados).
  - Trivy `config`: 0 HIGH/CRITICAL. Trivy no tiene reglas para `nginx.conf` ni para Compose; el comportamiento de nginx se verificó con la prueba funcional anterior.

### Quién puede consultarlos

Los eventos viven en la salida estándar del contenedor `backend`, gestionada por el driver `json-file` de Docker. Solo pueden leerlos quienes tengan acceso al **host** y a `docker logs` / `docker compose logs`:

- **Brandon Corrales** — responsable de operación (consulta, investigación `7.4`).
- **Billy Ugalde** — revisor del ítem y responsable del Registro Único de Hallazgos (valida decisiones derivadas).

La API no ofrece ningún endpoint para leerlos y la aplicación no los expone. El acceso a Docker equivale a privilegios de administrador en el host, así que se limita a esas dos personas.

```bash
docker compose logs backend --no-log-prefix | grep '"log_type":"security_event"'
```

### Retención

La retención está definida **por tamaño, no por tiempo**. La rotación del driver `json-file` de `docker-compose.yml` (`x-logging`) usa **`max-size: 10m` y `max-file: 5`**: Docker conserva como máximo **5 archivos de 10 MB (50 MB) por contenedor** y, al llenarse, descarta el más antiguo. No existe ningún mecanismo que garantice un número de días.

**Estimación con el tráfico de la prueba (orientativa, no es un compromiso):**
- Los eventos reales de la muestra ocupan **~330 bytes** cada uno, así que caben **≈150 000 eventos** en 50 MB (algo menos por las líneas de arranque de Nest).
- Cada ejecución de `security-log-sample.ps1` genera **6 eventos**, de modo que el límite equivale a unas **25 000 ejecuciones** de ese tráfico.
- Cuánto tiempo representa depende solo de la tasa de errores:
  - con pocos errores, como en la prueba, el límite tarda mucho en alcanzarse;
  - un escaneo sostenido de unos 10 eventos/s lo llenaría en **unas 4 horas**, y a partir de ahí se pierden los eventos más antiguos.

**Conservación de evidencia.** Los logs del contenedor **se borran con `docker compose down` o al recrear el contenedor** (por ejemplo, con `up --build`). Para conservar evidencia hay que exportarlos **antes**, sea antes de recrear el contenedor o al investigar un incidente:

```bash
docker compose logs backend --no-log-prefix | grep '"log_type":"security_event"' > reports/security-events-<fecha>.jsonl
```

`scripts/security-log-sample.ps1` hace lo mismo para la muestra de este ítem.

### Limitaciones

- **Detección por expresiones regulares:** puede dar **falsos positivos** (un nombre con apóstrofe seguido de "or", un `--` legítimo) y **falsos negativos** (codificaciones dobles, payloads ofuscados, inyección sin comillas). `suspicious_patterns` es una señal para investigar, no una prueba de ataque.
- **Solo respuestas de error:** una petición sospechosa que responda `200` no se registra. Hoy los payloads de inyección acaban en `400`/`404`, pero un cambio en la validación podría ocultarlos.
- **Otros logs fuera del filtro:** el filtro controla los errores de las peticiones HTTP. Mensajes propios de TypeORM o Nest al arrancar (p. ej. reintentos de conexión a la BD) siguen su formato normal; no contienen datos de las peticiones de los clientes.
- **Retención por tamaño, no por tiempo:** bajo un escaneo sostenido la rotación descarta eventos en horas. Los logs no sobreviven a la recreación del contenedor y no hay almacenamiento central ni protección de integridad (`THR-06`: quien controla el host podría borrarlos).
- **`actor_id` es seudónimo, no anónimo:** con la sal se puede re-identificar la IP por fuerza bruta, y varios usuarios detrás de una misma NAT comparten `actor_id`. La confianza en `X-Forwarded-For` depende de que el contenedor `frontend` no esté comprometido y de que nginx siga sobrescribiendo la cabecera.
- **Rutas inexistentes:** los segmentos con forma de dato se reemplazan por `:redacted`; se pierde detalle de qué ruta se sondeó a cambio de no registrar contenido arbitrario del cliente.

### Fila propuesta para el inventario de secretos (`1.5`, Roberto)

Para agregar a la tabla 4.3 de `01-planificacion-kb.md` (no edité la KB):

```markdown
| **`SEC-06`** | `LOG_ACTOR_SALT` | Sal del hash SHA-256 que seudonimiza la IP del cliente en el campo `actor_id` de los eventos de seguridad (`7.2`), permitiendo correlacionar intentos repetidos sin registrar la IP. | Backend NestJS (`backend/src/common/security-event.filter.ts`). | No otorga acceso a ningún sistema. Su exposición permitiría re-identificar las IPs de los `actor_id` por fuerza bruta del espacio IPv4. | **Brandon** (`Brandon-Corrales`) | Local: variable de la sesión (nunca en archivos).<br/>Despliegue: secreto del entorno de contenedores / GitHub Actions Secrets (`6.4`), inyectado vía `docker-compose` (`${LOG_ACTOR_SALT}`). | Generar un valor aleatorio nuevo (≥ 32 bytes), actualizar el secreto y reiniciar el backend. Consecuencia: los `actor_id` posteriores no se correlacionan con los anteriores. Si falta, el backend usa una sal aleatoria por proceso. |
```

---

## 7.4 — Investigación de una alerta con IA

> **Commit analizado (evidencia vigente):** `4aa366d1805038e6d152164961972995ffcbb011` (scripts `security-alert-check.py`, `generate-security-traffic.ps1`, `build-investigation-prompt.py` y plantilla [`07-prompt-investigacion.md`](./07-prompt-investigacion.md)). Stack reconstruido con `COMMIT_SHA=4aa366d…` (`/api/health` lo confirma), árbol limpio.  
> **Alcance:** la condición de disparo `SIG-01` es el **prerrequisito mínimo** para tener algo que investigar. **No es el ítem `7.3`**: no hay notificación, Grafana ni Prometheus, y no se bloquea nada.

### Flujo seguido

| Paso | Qué se hizo | Evidencia |
| :--- | :--- | :--- |
| 1. Tráfico controlado | `generate-security-traffic.ps1` (solo `localhost`): 29 peticiones, 10 normales y 19 de un patrón tipo escaneo (rutas inexistentes, inyección SQL, path traversal, XSS, fechas inválidas, POST/PUT/DELETE), parte por nginx `:8080` y parte directo a `:3001`. | Resultado: 10× `200` normales; escaneo: 1× `200`, 7× `400`, 11× `404`. |
| 2. Extracción de logs sanitizados | Eventos de seguridad del backend generados **solo** durante esa ejecución. | [`reports/security-alert-logs-4aa366d….jsonl`](../../reports/security-alert-logs-4aa366d1805038e6d152164961972995ffcbb011.jsonl) (18 eventos) |
| 3. Verificación de sanitización | `verify-security-logs.py`: **PASS**. Comprobó 3 IPs de cliente (loopback, gateway, nginx), 13 valores enviados prohibidos (payloads, fechas, rutas), la ausencia de `Authorization`/`Cookie` y los patrones `sql_injection`, `path_traversal` y `xss`. | [`reports/verify-security-alert-logs-4aa366d….txt`](../../reports/verify-security-alert-logs-4aa366d1805038e6d152164961972995ffcbb011.txt) |
| 4. Señal | `security-alert-check.py` (N=10, T=5 min): **`SIGNAL`**. Actor `b4231f77ae16e55c`, **18 eventos en 4,07 s** (02:50:38.744Z → 02:50:42.815Z): `not_found` 7, `abuse_suspected` 5, `validation_rejected` 3, `access_denied` 3; patrones `sql_injection` 3, `path_traversal` 1, `xss` 1. | [`reports/security-alert-4aa366d….json`](../../reports/security-alert-4aa366d1805038e6d152164961972995ffcbb011.json) |
| 5. Prompt concreto | `build-investigation-prompt.py`: plantilla + señal + extracto (solo eventos del `7.2`; 0 marcadores sin sustituir, 0 IPs ni payloads). | [`reports/security-alert-prompt-4aa366d….md`](../../reports/security-alert-prompt-4aa366d1805038e6d152164961972995ffcbb011.md) |
| 6. Análisis con IA | Lo ejecuta **Brandon** en un chat nuevo, pegando **solo** el contenido del prompt (ver registro abajo). | Respuesta pegada tal cual abajo. |
| 7. Validación humana | Brandon contrasta cada hipótesis con la evidencia y registra la decisión. | Sección "VALIDACIÓN HUMANA". |

La IA **no** recibe herramientas, credenciales ni acceso al repositorio o al ambiente. No puede bloquear, cambiar permisos ni modificar nada, y el prompt le prohíbe además recomendar acciones automáticas.

### Registro de la ejecución del análisis

| Campo | Valor |
| :--- | :--- |
| Ejecutado por | Brandon Corrales (`Brandon-Corrales`) |
| Fecha y hora | 2026-11-11, aprox. 20:56 (hora de Costa Rica, UTC−6) |
| Herramienta / modelo | claude.ai — Claude Opus 5.5 (esfuerzo "Medio"), modo Incógnito ("Sin historial, memoria ni entrenamiento de Claude") |
| Modalidad | Chat **nuevo** en claude.ai, **sin herramientas, sin archivos adjuntos y sin acceso al repositorio**. Se pegó únicamente el contenido de `reports/security-alert-prompt-4aa366d1805038e6d152164961972995ffcbb011.md`. |
| Entrada | Prompt de 14 312 bytes (plantilla `07-prompt-investigacion.md` + `security-alert-4aa366d….json` + 18 eventos sanitizados) |
| Enlace o captura del chat | Chat incógnito, no se conserva enlace persistente. Captura disponible a solicitud. |

### Respuesta de la IA (pegada tal cual, sin editar)

<!-- PEGAR AQUÍ LA RESPUESTA COMPLETA DE LA IA, SIN MODIFICARLA -->

#### Análisis de la señal SIG-01 sobre el actor b4231f77ae16e55c

#### 1. Resumen del incidente

Qué y cuándo: el 2026-11-12, entre 02:50:38.744Z y 02:50:42.815Z (4,07 s; 20:50 del 11-nov en hora de Costa Rica, UTC−6), un único actor_id generó 18 eventos de seguridad. Eso es unas 4,4 peticiones/s con una cadencia muy regular (~205–257 ms entre peticiones).

Fase 1, sondeo de rutas (7 not_found, todas GET): /api/admin, 3 × /api/:redacted, /api/users, /api/swagger, /api/actuator/health.

Fase 2, payloads sospechosos (5 abuse_suspected):
- sql_injection en query.canton de /api/delitos y /api/accidentes (400) y en path.id de FLOW-01 (404);
- path_traversal y xss en query.canton (400).

Fase 3, validación (3 validation_rejected, 400): query.desde (×2) y query.anio.

Fase 4, escritura (3 access_denied, todas 404): POST, PUT y DELETE.

Respuestas: todas fueron 400 o 404, coherentes con lo esperado en FLOW-01/FLOW-02. No hay eventos server_error (5xx) en el archivo fuente.

#### 2. Hipótesis

##### H1. Escaneo automatizado

A favor:
- La cadencia es casi constante (~230 ms) y sería imposible de sostener a mano.
- Prueba rutas genéricas de otros frameworks que no existen en este sistema. /api/actuator/health es típica de Spring Boot y /api/swagger y /api/admin son rutas comunes en diccionarios de escaneo.
- Cubre varias familias de ataque (SQLi, traversal, XSS) y además métodos de escritura.

En contra:
- El volumen es muy bajo para un escáner genérico. Herramientas tipo diccionario o DAST suelen generar cientos o miles de peticiones.
- Hay un solo payload por categoría y no se ve iteración.

Valoración: alta en cuanto a que es automatizado; media en cuanto a que sea una herramienta de escaneo genérica (ver H5).

##### H2. Intento de inyección dirigido contra FLOW-01 / FLOW-02

A favor:
- Los payloads van exactamente a parámetros reales (canton, path.id, desde, anio) y a las tres rutas de los flujos.
- Incluye el caso de FLOW-01 descrito en la base de conocimiento.

En contra:
- Esos nombres de parámetro son públicos: los usa el frontend, así que conocerlos no implica preparación especial.
- No hay adaptación tras los rechazos (no hay variaciones de payload ni reintentos).
- Dura 4 s y no hay ningún indicio de éxito.

Valoración: media. Hubo intentos con forma de inyección (según las etiquetas regex), pero nada indica una campaña persistente ni adaptativa.

##### H3. Error de un cliente legítimo

A favor:
- Los 3 validation_rejected sobre desde y anio sin patrón sospechoso podrían ser un bug de formato de fechas del frontend o de una integración.
- El actor_id puede ser compartido por NAT o proxy.

En contra:
- El frontend no tiene motivo para pedir /api/admin, /api/actuator/health, /api/swagger ni para usar POST/PUT/DELETE.
- Tampoco tiene motivo para enviar valores con forma de XSS o traversal.
- La cadencia uniforme apunta a un único cliente automatizado, no a varios usuarios mezclados.

Valoración: baja para el conjunto. Como mucho, explicaría los 3 eventos de validación de forma aislada.

##### H4. Falso positivo (detección por patrones o regla SIG-01)

A favor:
- Las regex pueden marcar valores benignos. Sin ver los valores no se pueden validar las 5 etiquetas.
- SIG-01 cuenta not_found, que también generan crawlers inofensivos.

En contra:
- SIG-01 se activó correctamente según su definición: 18 eventos frente a un umbral de 10 en 5 min.
- Que coincidan tres familias distintas de patrón, sondeo de rutas administrativas y métodos de escritura en 4 s es difícil de explicar con falsos positivos.

Valoración: baja para la señal en conjunto; media para etiquetas individuales.

##### H5 (adicional). Prueba controlada interna (test de seguridad, e2e o DAST del propio equipo)

A favor (supuestos, no verificados):
- La secuencia está "demasiado ordenada" y recorre exactamente los controles de la base de conocimiento, en orden: rutas inexistentes, inyección en FLOW-01/02, validación de fechas y escritura denegada.
- Hay un caso por categoría.
- El archivo fuente contiene solo 18 líneas y 1 actor.
- El nombre del archivo incluye un hash de 40 caracteres hexadecimales, con forma de SHA de commit, lo que sugiere un reporte generado por CI.
- generated_at aparece solo 4 s después del último evento.

En contra: nada en los datos lo confirma. Un atacante con un script propio produciría un patrón parecido.

Valoración: media. Es la hipótesis que más conviene confirmar o descartar primero, porque cambia por completo la interpretación.

#### 3. Qué comprobar a continuación (por prioridad)

Origen del reporte y posible prueba interna (H5).
- Qué revisar: si el hash del nombre del archivo corresponde a un commit del repositorio y si hubo una ejecución de pipeline, tests e2e de seguridad o DAST alrededor de las 02:50Z. Preguntar al equipo si alguien ejecutó pruebas.
- Acceso necesario: repositorio y CI.
- Resultado: si coincide, se confirma H5 y H1/H2 bajan a "actividad esperada". Si no, H1/H2 ganan peso.

Logs completos de acceso (nginx o backend) en la ventana 02:50:30–02:51:00Z, incluidos los 2xx.
- Qué buscar: si hubo peticiones con respuesta 2xx intercaladas, el user-agent y el volumen total.
- Hay un hueco de ~425 ms entre 02:50:40.755 y 02:50:41.180, el doble de la cadencia habitual. Es un supuesto que ahí hubo una petición con 2xx (sin evento); también puede ser solo latencia.
- Resultado: si algún payload sospechoso recibió 2xx, sería un hueco de detección o de validación relevante para THR-01/CTL-01.
- Acceso: los logs crudos pueden contener valores, así que su consulta debe hacerla una persona autorizada.

Verificación de FLOW-01 y CTL-01 para f48077d8-….
- Qué revisar: en los logs del backend y de PostgreSQL, que no haya errores de sintaxis SQL ni excepciones ligadas a esa petición ni a d4de83b8-… y d204cc9e-….
- Resultado: un error de sintaxis en la BD indicaría interpolación, contradiciendo CTL-01. Su ausencia respalda que la consulta parametrizada funcionó.

Revisión de CTL-01 en el código actual.
- Qué hacer: una persona confirma que la regla Semgrep pasa en el commit desplegado y que canton y anio tienen validación de tipo.
- Por qué: la base de conocimiento solo dice explícitamente que las fechas se rechazan con 400, y aquí canton también devolvió 400.
- Opcional, si lo decide el responsable: reproducir los casos en un ambiente no productivo.

Correlación temporal del actor_id.
- Qué buscar: si b4231f77ae16e55c aparece antes o después en otros reportes (el alcance persistent lo permite mientras no rote la sal) y si otros actor_id muestran la misma secuencia a la misma hora, lo que indicaría actividad distribuida.
- Resultado: recurrencia o expansión favorecen H2; un evento único y aislado favorece H5 o un escaneo oportunista.

Calidad de la detección (H4).
- Qué revisar, con acceso controlado a los valores: si las 5 etiquetas regex corresponden a payloads reales.
- También si los 3 validation_rejected sin patrón eran en realidad payloads no detectados. Eso sería un falso negativo, relevante para CTL-06.

Impacto en disponibilidad (THR-02/CTL-02).
- Qué revisar: latencia y uso de CPU y BD en esa ventana.
- A ~4,4 req/s se espera un impacto nulo; confirmarlo permite descartar DoS.

Coherencia de clasificación y exposición.
- Comprobar que los health checks reales (CTL-06) no usan una ruta expuesta públicamente.
- Comprobar que nginx no reenvía /api a ningún otro servicio que acepte escritura. Las 3 respuestas 404 a POST/PUT/DELETE son coherentes con "no hay rutas de escritura".

#### 4. Qué NO puede concluirse solo con estos logs

- Quién es ni con qué intención actúa. El actor_id es un seudónimo y puede agrupar a varias personas detrás de NAT, proxy o VPN. No debe intentarse revertir.
- Si algún intento tuvo éxito. Las respuestas 2xx no generan evento, así que no se ve la actividad completa del actor. La ausencia de 5xx en este archivo no prueba ausencia de impacto.
- Los valores reales enviados. Las etiquetas de patrón son heurísticas regex; no permiten juzgar la sofisticación de los payloads ni descartar falsos positivos o negativos.
- Qué se pidió en las 3 rutas /api/:redacted.
- Qué herramienta se usó. No hay user-agent ni cabeceras.
- Si el archivo es completo o un extracto filtrado. Contiene 18 líneas y 1 actor.
- El origen interno (H5). Es solo un supuesto basado en la forma del nombre de archivo y del patrón.

#### 5. Nivel de confianza global

- Alta en que se trató de actividad automatizada y breve, y en que las respuestas observadas (400/404) coinciden con el comportamiento esperado de FLOW-01, FLOW-02 y la API de solo lectura.
- Media-baja en la intención: no se puede distinguir entre una prueba interna, un escaneo oportunista o un intento dirigido.
- Dato que más cambiaría el análisis: confirmar si la ejecución corresponde a una prueba interna o de CI (el hash del archivo). Después, los logs de acceso completos con los 2xx y el user-agent de esa ventana.

Este análisis no propone ninguna acción automática; cualquier medida queda a decisión de la persona responsable.

<!-- FIN DE LA RESPUESTA DE LA IA -->

### Observación del agente de desarrollo (no es parte del análisis de la IA)

> Esta observación la registró el agente que construyó la demo (Claude Code) y **no se incluyó en el prompt**, para que el análisis de la IA fuera independiente. Sirve como dato para la validación humana.

De las 19 peticiones del escaneo, **una no aparece en los logs**: `GET /api/delitos?tipo=x'; DROP TABLE delito;--` respondió **`200`** con un resultado vacío (`{"delitos":[], ...}`). Según `FLOW-02`/`CTL-01`, la consulta parametrizada neutraliza el payload, así que no hubo error. Como el `7.2` solo registra respuestas `>= 400`, **no se generó ningún evento**. Por eso:

- los 18 eventos de la señal no son todo el tráfico del actor; un intento de inyección "exitoso" desde el punto de vista HTTP (200) es invisible para el registro y para `SIG-01`;
- el conteo de `abuse_suspected` (5) subestima los intentos de inyección reales (6 en el tráfico);
- es la limitación ya documentada del `7.2` ("Solo respuestas de error"). Si la validación humana la considera relevante, puede derivar en un hallazgo (fila propuesta abajo).

---

## VALIDACIÓN HUMANA — Brandon Corrales

> **Completa esta sección Brandon Corrales.** La IA y el agente de desarrollo no la completan. Contrastar cada hipótesis de la respuesta de la IA con la evidencia (`security-alert-logs-4aa366d….jsonl`, `security-alert-4aa366d….json`, el manifiesto del tráfico, `docker logs` y, si aplica, la observación anterior).

**Evidencia revisada (aplica a todas las filas):** reports/security-alert-logs-4aa366d….jsonl (orden y hora de los 18 eventos, listados con PowerShell) comparado con la secuencia de peticiones de scripts/generate-security-traffic.ps1 (normales: líneas 40–44, ejecutadas antes y después del escaneo; escaneo: líneas 49–70).

| Hipótesis | Evidencia revisada | ¿Se confirma? (sí / no / parcial) | Comentario |
| :--- | :--- | :---: | :--- |
| H1. Escaneo automatizado | Logs vs. script | Parcial | Es automatizado, pero se trata de un script propio de prueba (generate-security-traffic.ps1), no de una herramienta de escaneo de terceros. |
| H2. Intento de inyección dirigido contra FLOW-01 / FLOW-02 | Payloads de las líneas 57–62 del script | Parcial | Los payloads sí apuntaban a parámetros reales de FLOW-01/02, pero por diseño de la prueba, no por un atacante. |
| H3. Error de un cliente legítimo | Líneas 64–70 del script | No | Las 3 fechas inválidas se enviaron a propósito; ningún cliente legítimo pide /api/admin ni usa POST/PUT/DELETE. |
| H4. Falso positivo (patrones o regla SIG-01) | security-alert-4aa366d….json y líneas 57–62 | No | SIG-01 se activó según su regla (18 ≥ 10 en 5 min) y cada etiqueta corresponde a un payload realmente enviado. |
| H5. Prueba controlada interna (propuesta por la IA) | Commit 4aa366d, script y hora de ejecución | Sí | Tráfico generado por Brandon con generate-security-traffic.ps1 sobre el commit 4aa366d, el 2026-11-11 a las ~20:50 (hora de Costa Rica). |

**Correspondencia petición → evento:**

| Peticiones (líneas del script) | Respuesta | Eventos |
| :--- | :--- | :--- |
| 10 normales (40–44, ×2) | 200 | 0 (esperado: los 2xx no generan evento) |
| 7 rutas inexistentes (49–55) | 404 | 7 not_found (38.744 → 40.057) |
| 5 payloads (57, 58, 59, 61, 62) | 400 / 404 | 5 abuse_suspected (3 sql_injection, 1 path_traversal, 1 xss) |
| 1 payload DROP TABLE (60) | 200 | 0 ← punto ciego |
| 3 fechas/años inválidos (64–66) | 400 | 3 validation_rejected, sin patrones |
| 3 escrituras POST/PUT/DELETE (68–70) | 404 | 3 access_denied |
| Total: 29 peticiones | | 18 eventos |

**Comprobaciones propuestas por la IA que se realizaron:**

- Origen del reporte (punto 3.1): el hash del nombre del archivo es el commit 4aa366d del repositorio y la ejecución la hizo Brandon. Se confirma H5.
- Hueco de ~425 ms (punto 3.2): entre 02:50:40.755 (línea 59, /api/cantones/101' OR '1'='1/panorama) y 02:50:41.180 (línea 61, /api/delitos?canton=../../etc/passwd) está la línea 60: /api/delitos?tipo=x'; DROP TABLE delito;-- que respondió 200 sin generar evento. Se confirma la deducción de la IA.
- Calidad de la detección (punto 3.6): los 3 validation_rejected corresponden a desde=no-es-fecha, desde=2025-13-45 y anio=99999, sin comillas, OR, ../ ni <script>. No hay falsos negativos en esos eventos; las 5 etiquetas corresponden a payloads realmente enviados.
- No se realizaron: logs de PostgreSQL (3.3), revisión de código de CTL-01 (3.4), correlación con otros actores (3.5), métricas de disponibilidad (3.7) ni revisión de nginx (3.8), porque al confirmarse H5 (prueba controlada en ambiente local) no aportan a la decisión.

**Decisión registrada:**

La señal SIG-01 es un verdadero positivo de la regla, originado por una prueba controlada interna (H5). No es un incidente y no se requiere ninguna acción sobre el ambiente. Se confirma con evidencia la deducción de la IA (punto 3.2): el hueco de 425 ms corresponde a la petición /api/delitos?tipo=x'; DROP TABLE delito;-- (línea 60 del script), que respondió 200 sin generar evento. La consulta parametrizada neutralizó el payload, así que no es una vulnerabilidad. Pero el 7.2 solo registra respuestas 4xx/5xx, por lo que los intentos de inyección que no producen error no dejan rastro: es un punto ciego de detección (THR-06/CTL-06). Se descartan falsos negativos en los 3 validation_rejected. Se registra la propuesta de HAL-05 (severidad baja) para Billy, con la mejora para el próximo ciclo: detectar patrones sospechosos también en respuestas 2xx.

**Fecha:** 2026-11-11 · **Responsable:** Brandon Corrales · **Revisor:** Billy Ugalde

### Fila propuesta para el Registro Único (`REGISTRO-HALLAZGOS.md`, Billy) — solo si la decisión lo amerita

Redactada a partir de la observación anterior y de la decisión registrada. Severidad **Baja**, confirmada por Brandon. Billy decide si la registra; no edité ese archivo.

```markdown
| **`HAL-05`** | Etapa 7 (`7.4`) — Investigación de la señal `SIG-01` | `THR-06` / `CTL-06` (relacionado `THR-01`) | Backend `4aa366d` — `backend/src/common/security-event.filter.ts` (solo registra respuestas `>= 400`) | En la demo, `GET /api/delitos?tipo=<payload SQL>` respondió `200` sin generar evento; ver `reports/security-alert-logs-4aa366d….jsonl` y la sección 7.4 de `07-operacion-investigacion-ia.md`. | **Baja** (la consulta parametrizada neutraliza el payload: sin impacto en datos; el efecto es pérdida de visibilidad para la investigación) | **Brandon** (`Brandon-Corrales`) | 🔴 **Abierto** *(si se registra)* | Mejora propuesta: registrar también como `abuse_suspected` las peticiones `2xx` cuyos valores coincidan con `suspicious_patterns`, y verificarlo repitiendo `generate-security-traffic.ps1` + `security-alert-check.py`. |
```
