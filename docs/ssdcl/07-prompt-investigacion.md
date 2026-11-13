# Prompt de Investigación de Alertas con IA (Ítem 7.4)

> **Responsable:** Brandon Corrales (`Brandon-Corrales`) · **Revisor:** Billy Ugalde (`Billy-Ugalde`)  
> **Uso:** plantilla reutilizable para pedir a una IA el análisis de una señal de `scripts/security-alert-check.py` (regla `SIG-01`).  
> **Relación con la KB:** `THR-06` / `CTL-06` (trazabilidad e investigación), con contexto de `FLOW-01`, `FLOW-02`, `THR-01`, `THR-02`, `CTL-01`, `CTL-02`.

## Condición mínima de disparo (prerrequisito del 7.4, no es el ítem 7.3)

[`scripts/security-alert-check.py`](../../scripts/security-alert-check.py) solo responde **"¿hay algo que una persona deba investigar?"**. No notifica, no bloquea, no modifica nada y no reemplaza el ítem `7.3` (alertas con umbral y notificación), que no forma parte de este alcance.

**Regla `SIG-01`.** Un mismo `actor_id` acumula **N o más** eventos `abuse_suspected`, `validation_rejected`, `access_denied` o `not_found` dentro de una **ventana deslizante de T minutos**. `server_error` no cuenta, porque no lo provoca el cliente. La salida es un JSON con la regla, el umbral, la ventana y, por actor, el conteo por `event_type`, códigos, métodos, rutas, patrones, el rango de tiempo de la ventana más densa y sus `correlation_id`.

**Valores por defecto: N = 10, T = 5 minutos.**

| Referencia observada en el proyecto | Eventos de un mismo actor |
| :--- | :--- |
| Una ejecución de los smoke tests (`6.5`) | 2 (el 404 y el 400 esperados) |
| La muestra del `7.2` (`security-log-sample.ps1`) | 6 en ~2 s |
| Uso normal: un usuario se equivoca de fecha o de cantón | 1–3 en varios minutos |
| Escaneo de la demo (`generate-security-traffic.ps1`) | 18 en ~4 s |

- **Por qué N = 10:** queda por encima de los errores legítimos y de las propias pruebas del equipo (un smoke test más la muestra del `7.2` suman 8), pero cualquier sondeo de rutas o parámetros lo supera en segundos.
- **Por qué T = 5 min:** agrupa una ráfaga de escaneo sin sumar errores aislados de todo un día.
- **Configurables:** `--threshold` y `--window-minutes`.

**Limitaciones de la regla:**
- Un escaneo lento (menos de 2 eventos por minuto) no la activa.
- Varios usuarios detrás de una misma NAT comparten `actor_id` y pueden activarla juntos.
- Solo ve lo que el `7.2` registra: las peticiones sospechosas que responden `200` no generan evento. Ejemplo comprobado: `?tipo=x'; DROP TABLE delito;--` responde `200` con resultado vacío, porque la consulta parametrizada lo neutraliza.

## Cómo se usa

1. Detectar la señal y extraer los eventos sanitizados del `7.2`:
   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/generate-security-traffic.ps1 -LogsOut reports/security-alert-logs-<sha>.jsonl   # solo en la demo
   python scripts/security-alert-check.py reports/security-alert-logs-<sha>.jsonl --output reports/security-alert-<sha>.json
   python scripts/verify-security-logs.py reports/security-alert-logs-<sha>.jsonl ...   # confirmar que el extracto está sanitizado
   ```
2. Construir el prompt concreto sustituyendo `{{SIGNAL_JSON}}` y `{{LOGS_JSONL}}`:
   ```bash
   python scripts/build-investigation-prompt.py reports/security-alert-<sha>.json reports/security-alert-logs-<sha>.jsonl --output reports/security-alert-prompt-<sha>.md
   ```
3. Entregar a la IA **solo** el contenido de ese archivo: sin acceso al repositorio, a la red ni a otros datos.
4. Pegar la respuesta tal cual en `07-operacion-investigacion-ia.md` (sección `7.4`) y hacer la **validación humana**.

**Reglas de uso:**
- Al prompt solo entran eventos ya sanitizados por el `7.2`, revisados con `verify-security-logs.py`: sin IPs, valores de parámetros, cabeceras ni secretos.
- La IA **no** recibe herramientas ni credenciales: no puede actuar sobre el ambiente aunque lo intentara.
- Toda decisión (cerrar, escalar, registrar un hallazgo) la toma y la registra una persona.

---

## Plantilla del prompt

<!-- BEGIN PROMPT -->
Eres un analista de seguridad que apoya una investigación. Trabajas SOLO con la información de este mensaje: no tienes acceso al sistema, al repositorio, a Internet ni a otros datos. No inventes hechos que no estén aquí y marca como supuesto todo lo que no se pueda verificar con estos datos.

## Restricciones obligatorias

- NO ejecutes, recomiendes ni redactes acciones automáticas: no bloquear IPs ni actores, no cambiar permisos o reglas de firewall, no modificar configuración, código ni el ambiente, no reiniciar servicios, no eliminar datos.
- Tu papel es solo analítico. Propón comprobaciones para que una PERSONA las haga y decida; si una comprobación requiere acceso, dilo y deja la decisión a esa persona.
- No intentes re-identificar al actor: `actor_id` es un seudónimo (hash con sal) y así debe tratarse.

## Contexto del sistema (Base de Conocimiento del proyecto)

Sistema: "Observatorio de Seguridad Vial y Urbana de Costa Rica". Backend NestJS (`/api/*`) con PostgreSQL/PostGIS, frontend React servido por nginx que reenvía `/api` al backend. Integra datos públicos agregados (OIJ, COSEVI, SNIT, OpenStreetMap); no maneja datos personales.

- **Control de acceso:** la API es PÚBLICA, de SOLO LECTURA y SIN AUTENTICACIÓN. El único actor externo es un usuario anónimo, al que solo se permiten métodos `GET`. Cualquier `POST/PUT/PATCH/DELETE` está denegado (la API no expone rutas de escritura) y PostgreSQL no se expone fuera de la red interna. No existen usuarios, sesiones, tokens ni roles.
- **FLOW-01 — Panorama cantonal** (`GET /api/cantones/:id/panorama`): devuelve totales e índice de cobertura de un cantón. Un cantón inexistente responde `404`. Un intento de inyección en `:id` (p. ej. `101' OR '1'='1`) debe ser neutralizado por la consulta parametrizada y responder `404` sin exponer registros.
- **FLOW-02 — Consultas con filtros** (`GET /api/delitos`, `/api/accidentes`, `/api/infraestructura`): reciben `canton`, `tipo`, `clase`, `anio`, `desde`, `hasta`. Fechas malformadas o rangos inválidos se rechazan con `400` antes de consultar la BD. Los payloads SQL se neutralizan con consultas parametrizadas y los resultados se truncan (`1000` / `5000`).
- **THR-01 — Inyección / manipulación de parámetros** (prioridad Alta, expuesto a Internet sin sesión). **CTL-01:** parámetros enlazados en TypeORM, validación de fechas y tipos antes del SQL, regla Semgrep que prohíbe interpolar SQL.
- **THR-02 — Denegación de servicio** por consultas masivas o sin límite. **CTL-02:** límites de resultados (`.limit(1000)` / `.take(5000)`) y timeouts.
- **THR-06 — Repudio / falta de trazabilidad** ante intentos repetidos de abuso. **CTL-06:** registro de eventos de seguridad sanitizados con `correlation_id`, más health checks y rollback.

## Formato de los eventos (ítem 7.2)

Cada línea es un evento de una respuesta HTTP `>= 400` (las respuestas `2xx` NO generan evento):

- `event_type`:
  - `validation_rejected`: 400 por entrada inválida;
  - `not_found`: 404 de recurso o de ruta inexistente;
  - `access_denied`: intento de escritura sobre la API de solo lectura, o 401/403/405;
  - `abuse_suspected`: los valores coinciden con un patrón de ataque;
  - `server_error`: 5xx.
- `route`: PATRÓN de la ruta (`/api/cantones/:id/panorama`). En rutas inexistentes, los segmentos con forma de dato aparecen como `:redacted`.
- `param_names`: solo NOMBRES de parámetros (`query.canton`, `path.id`), nunca sus valores.
- `suspicious_patterns`: nombres de patrones detectados con expresiones regulares (`sql_injection`, `path_traversal`, `xss`, `command_injection`, `oversized_input`). Pueden dar falsos positivos y falsos negativos.
- `actor_id`: SHA-256 truncado de la IP con una sal secreta. Varios usuarios detrás de una misma NAT o proxy comparten `actor_id`.
- `correlation_id`: UUID por petición.

## Señal a investigar (regla SIG-01: un mismo actor con N o más eventos de rechazo/abuso en T minutos)

```json
{{SIGNAL_JSON}}
```

## Extracto de eventos sanitizados

```jsonl
{{LOGS_JSONL}}
```

## Lo que debes entregar (en español, con estas secciones)

1. **Resumen del incidente:** qué ocurrió, cuándo, qué volumen, qué rutas y qué tipos de evento. Máximo 8 líneas.
2. **Hipótesis.** Para CADA una de las siguientes, da evidencia a favor, evidencia en contra y una valoración (alta / media / baja) con su justificación:
   - H1. Escaneo automatizado (herramienta que sondea rutas y parámetros);
   - H2. Intento de inyección dirigido contra FLOW-01 / FLOW-02;
   - H3. Error de un cliente legítimo (frontend, integración o usuario);
   - H4. Falso positivo (de la detección por patrones o de la regla SIG-01).
   Si ves otra hipótesis razonable, agrégala como H5.
3. **Qué comprobar a continuación:** comprobaciones concretas y ordenadas por prioridad que una persona puede hacer (qué revisar, dónde y qué resultado confirmaría o descartaría cada hipótesis). Relaciónalas con FLOW/THR/CTL cuando aplique.
4. **Qué NO puede concluirse solo con estos logs:** límites de la evidencia (lo que estos datos no muestran o no permiten afirmar).
5. **Nivel de confianza global** del análisis y qué dato adicional lo cambiaría más.

Recuerda: no recomiendes ni redactes acciones automáticas (bloqueos, cambios de permisos o del ambiente). La decisión la toma una persona.
<!-- END PROMPT -->
