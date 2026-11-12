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
| Fecha y hora | *(completar)* |
| Herramienta / modelo | *(completar: p. ej. claude.ai — nombre exacto del modelo mostrado en el chat)* |
| Modalidad | Chat **nuevo** en claude.ai, **sin herramientas, sin archivos adjuntos y sin acceso al repositorio**. Se pegó únicamente el contenido de `reports/security-alert-prompt-4aa366d1805038e6d152164961972995ffcbb011.md`. |
| Entrada | Prompt de 14 312 bytes (plantilla `07-prompt-investigacion.md` + `security-alert-4aa366d….json` + 18 eventos sanitizados) |
| Enlace o captura del chat | *(opcional: completar)* |

### Respuesta de la IA (pegada tal cual, sin editar)

<!-- PEGAR AQUÍ LA RESPUESTA COMPLETA DE LA IA, SIN MODIFICARLA -->

*(pendiente: la pega Brandon)*

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

| Hipótesis | Evidencia revisada | ¿Se confirma? (sí / no / parcial) | Comentario |
| :--- | :--- | :---: | :--- |
| H1. Escaneo automatizado | | | |
| H2. Intento de inyección dirigido contra FLOW-01 / FLOW-02 | | | |
| H3. Error de un cliente legítimo | | | |
| H4. Falso positivo (patrones o regla SIG-01) | | | |
| H5. *(si la IA propuso otra)* | | | |

**Comprobaciones propuestas por la IA que se realizaron:** *(completar)*

**Decisión registrada:** *(completar: p. ej. cerrar como prueba controlada / escalar / registrar hallazgo)*

**Fecha:** *(completar)* · **Responsable:** Brandon Corrales · **Revisor:** Billy Ugalde

### Fila propuesta para el Registro Único (`REGISTRO-HALLAZGOS.md`, Billy) — solo si la decisión lo amerita

Redactada a partir de la observación anterior. Billy decide si la registra y Brandon confirma la severidad en la validación; no edité ese archivo.

```markdown
| **`HAL-05`** | Etapa 7 (`7.4`) — Investigación de la señal `SIG-01` | `THR-06` / `CTL-06` (relacionado `THR-01`) | Backend `4aa366d` — `backend/src/common/security-event.filter.ts` (solo registra respuestas `>= 400`) | En la demo, `GET /api/delitos?tipo=<payload SQL>` respondió `200` sin generar evento; ver `reports/security-alert-logs-4aa366d….jsonl` y la sección 7.4 de `07-operacion-investigacion-ia.md`. | **Baja** (la consulta parametrizada neutraliza el payload: sin impacto en datos; el efecto es pérdida de visibilidad para la investigación) | **Brandon** (`Brandon-Corrales`) | 🔴 **Abierto** *(si se registra)* | Mejora propuesta: registrar también como `abuse_suspected` las peticiones `2xx` cuyos valores coincidan con `suspicious_patterns`, y verificarlo repitiendo `generate-security-traffic.ps1` + `security-alert-check.py`. |
```
