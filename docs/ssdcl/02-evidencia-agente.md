# Evidencia de Operación y Gobernanza del Agente de IA — Etapa 2 (`Ítems 1.8 y 2.1`)

> **Proyecto:** Observatorio de Seguridad Vial y Urbana de Costa Rica (`proyecto-seguridad`)  
> **Responsable:** Jose Picado (`Jose-Picado-Zamora`) — *Responsable de Requisitos y Base de Conocimiento (KB)*  
> **Revisor Asignado:** Brandon Corrales (`Brandon-Corrales`)  
> **Archivos Asociados:** [`AGENTS.md`](../../AGENTS.md), [`docs/ssdcl/01-planificacion-kb.md`](./01-planificacion-kb.md), [`scripts/agent-verify.ps1`](../../scripts/agent-verify.ps1), [`docs/ssdcl/02-hook-agente.md`](./02-hook-agente.md)

---

## 1. Resumen del Entregable y Objetivos

En cumplimiento con los requerimientos del SSDLC para la **Etapa 1 (Planificación - Ítem 1.8)** y la **Etapa 2 (Desarrollo - Ítem 2.1)**:
1. Se definió y versionó el archivo central [`AGENTS.md`](../../AGENTS.md) en la raíz del repositorio, estableciendo las normas de consulta a la Base de Conocimiento (KB), las convenciones técnicas del Observatorio y las restricciones de acceso.
2. Se configuraron los límites estrictos del agente para impedir modificaciones no autorizadas en workflows de CI/CD, secretos, políticas de contenedores y reglas de seguridad.
3. Se integró formalmente el hook Stop de Claude Code con el script wrapper `scripts/agent-verify.ps1` y `scripts/agent-verify.sh` (Ítem `2.4`).
4. El presente documento enlaza las evidencias reales y auditables registradas en el repositorio que demuestran la consulta previa a la KB, la detención ante límites de seguridad y la intervención humana ante bloqueos.

---

## 2. Demostración de Consulta a la Base de Conocimiento (KB)

### Caso de Validación: Consulta Previa antes de Proponer Modificaciones en Endpoints
Antes de sugerir cualquier cambio en la capa de servicios o controladores del backend:
1. **Paso 1: Consulta Previa a la KB:**
   El agente consulta obligatoriamente [`docs/ssdcl/01-planificacion-kb.md`](./01-planificacion-kb.md#criterios-de-aceptación-dado--cuando--entonces-por-flujo) e identifica los requisitos y cotas de los flujos críticos:
   - **`FLOW-01`**: Cálculo del percentil `indice_cobertura` (`0..100`), protección contra división por cero (`1 + totalInfraestructura`) y respuesta `404` ante cantones no encontrados.
   - **`FLOW-02`**: Filtros dinámicos con cotas de paginación obligatorias (`.take(1000)` / `.limit(5000)`) vinculadas al control **`CTL-02`** (mitigación de DoS / `THR-02`).
   - **`FLOW-03`**: Ingesta OSINT mediante transacciones atómicas y timeouts obligatorios (`CTL-04`).
2. **Paso 2: Respeto a Controles de Seguridad:**
   El agente verifica que no se utilicen template literals con interpolación (`${...}`) en consultas SQL de TypeORM, en estricto cumplimiento del control **`CTL-01`** (detectado por la regla Semgrep `ssdcl-ts-raw-sql-interpolation`).

> **Limitación declarada:** esta sección describe el **procedimiento** que `AGENTS.md` exige. **No hay una transcripción versionada** de una sesión real en la que un agente haya consultado `AGENTS.md` y la KB antes de modificar un flujo crítico, y no se presenta ninguna como evidencia. El cumplimiento verificable de las reglas es el de la sección 3: los bloqueos y correcciones del hook, registrados por el propio wrapper. Para completar el ítem hace falta una sesión real con fecha, modelo y extracto.

---

## 3. Demostración de Límites y Consulta al Humano (Human-in-the-Loop)

En cumplimiento de la Sección 3 de `AGENTS.md`, el agente tiene prohibido modificar reglas de seguridad, configuraciones de CI, archivos `.env`, configuraciones del hook o el archivo `.trivyignore.yaml`.

### Evidencias Reales Registradas en el Repositorio:

Las pruebas reales del mecanismo de límite de reintentos y bloqueo ante intervención humana se encuentran versionadas y verificadas en:

1. **Evidencia de Bloqueo al Tercer Intento (`reports/agent-verify-blocked-20261112T005840Z.json`):**
   - Enlace directo: [`reports/agent-verify-blocked-20261112T005840Z.json`](../../reports/agent-verify-blocked-20261112T005840Z.json)
   - **Estado:** `status: "BLOCKED"`, `attempts: 3/3`, `message: "BLOQUEO: requiere intervención humana"`.
   - **Causa Real:** Gitleaks detectó una clave de acceso simulada enmascarada (`REDACTED`) bajo la regla `github-pat`. El agente agotó los 3 intentos sin poder relajar la regla, deteniéndose y exigiendo autorización humana.
2. **Historial Cronológico de Invocaciones del Hook (`reports/agent-verify-hook-history.jsonl`):**
   - Enlace directo: [`reports/agent-verify-hook-history.jsonl`](../../reports/agent-verify-hook-history.jsonl)
   - Registra cada disparo del hook Stop: hora UTC (`at`), commit, `stop_hook_active`, intento y resultado.
   - **Secuencia real del bloqueo** (commit `8e49b16`): tres líneas `FAIL` con `failed: ["security:gitleaks:FAIL"]`:
     - intento 1, a las `2026-11-12T00:57:27Z`, con `stop_hook_active: false`;
     - intento 2, a las `00:57:58Z`;
     - intento 3, a las `00:58:20Z`.
   - El tercer fallo agota el límite. El estado `BLOCKED` **no** es una línea del historial: queda en el reporte aparte `reports/agent-verify-blocked-20261112T005840Z.json` (punto 1).
3. **Evidencia de Corrección Exitosa y Aprobación en Verde (`reports/agent-verify-demo-a-green.json`):**
   - Enlace directo: [`reports/agent-verify-demo-a-green.json`](../../reports/agent-verify-demo-a-green.json)
   - Demuestra el ciclo en el que se detecta un defecto de tipos controlado en TypeScript (`TS2322` en `backend/src/demo-hook.temp.ts`, `exit 2`), se corrige en el turno siguiente y se aprueba (`result: "PASS"`, `2026-11-12T01:04:43Z`). El detalle está en [`02-hook-agente.md`](./02-hook-agente.md).

---

## 4. Verificación de Comandos y Pipeline del Agente

Las herramientas y comandos reproducibles referenciados en `AGENTS.md` se verifican localmente mediante la ejecución del wrapper. La evidencia versionada de una ejecución completa es [`reports/agent-verify-demo-a-green.json`](../../reports/agent-verify-demo-a-green.json) (commit `8e49b16`, `2026-11-12T01:04:43Z`, modo `standard`), con el estado de cada paso:

| Paso de Verificación | Comando Real Ejecutado | Herramienta | Estado en `agent-verify-demo-a-green.json` |
| :--- | :--- | :---: | :--- |
| `frontend:lint` | `cd frontend && npm run lint` | oxlint | `PASS` |
| `frontend:build` | `cd frontend && npm run build` | tsc + Vite | `PASS` |
| `backend:lint` | `cd backend && npm run lint` | ESLint | `SKIPPED`: el script aún no existía en ese commit; hoy existe en `backend/package.json` |
| `backend:build` | `cd backend && npm run build` | nest build | `PASS` |
| `backend:test` | `cd backend && npm test` | Jest | `SKIPPED`: igual que `backend:lint` |
| `security:sast-check` | `python scripts/sast-check.py` | Semgrep CE (reglas `.semgrep.yml`) | `PASS` |
| `security:semgrep` | `semgrep scan --config .semgrep.yml --error …` | `semgrep/semgrep:1.185.0` (fijada por digest) | `PASS` |
| `security:gitleaks` | `gitleaks dir --config .gitleaks.toml --redact` | Gitleaks v8.21.2 | `PASS` |
| `containers:policy` | `scripts/policy-check.ps1` / `.sh` | Conftest + OPA/Rego | `PASS` |

**Evidencia de Conftest por commit:** por ejemplo [`reports/conftest-6342cd32e5cb675ca7e26448e93cb1ae795d0d16.json`](../../reports/conftest-6342cd32e5cb675ca7e26448e93cb1ae795d0d16.json), de la versión candidata `v1.0.0-rc1`.

`reports/agent-verify-last.json` y `reports/agent-verify-gitleaks-last.json` son archivos de trabajo que se reescriben en cada ejecución: **no se versionan y no son evidencia** (ver [`02-hook-agente.md`](./02-hook-agente.md)).

---

## 5. Conclusiones y Estado del Control

- **Gobernanza Operativa:** El repositorio cuenta con una directiva explícita, auditable y versionada en [`AGENTS.md`](../../AGENTS.md) que delimita la interacción de cualquier modelo de IA con el código del proyecto.
- **Trazabilidad:** `AGENTS.md` exige verificar las amenazas y controles de la KB antes de cambiar flujos críticos (`FLOW-01..03`). Todavía no hay una transcripción real de esa consulta (ver la limitación de la sección 2).
- **Supervisión Humana Activa:** Se comprueba documental y técnicamente que el agente carece de privilegios para suprimir controles de seguridad o alterar infraestructura de contenedores sin revisión de los integrantes del equipo.
