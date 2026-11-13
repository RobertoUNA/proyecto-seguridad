# AGENTS.md — Directivas de Gobernanza y Seguridad para Agentes de IA

> **Proyecto:** Observatorio de Seguridad Vial y Urbana de Costa Rica (`proyecto-seguridad`)  
> **Versión:** `1.0.0` · **Última actualización:** `2026-11-12`  
> **Responsable del Documento:** Jose Picado (`Jose-Picado-Zamora`) — *Responsable de Requisitos y Base de Conocimiento (KB)*  
> **Cumplimiento SSDLC:** Ítems `1.8` y `2.1` (NIST NCCoE — Etapa 1 Planificación y Etapa 2 Desarrollo)  
> **Revisor Asignado:** Brandon Corrales (`Brandon-Corrales`)

---

## 1. Propósito y Ámbito de Aplicación

Este documento establece las instrucciones operativas, restricciones de seguridad, convenciones de arquitectura y comandos reproducibles obligatorios que **todo agente de Inteligencia Artificial** (Claude Code, Antigravity, GitHub Copilot, Gemini CLI o similares) debe consultar y acatar rigurosamente antes de proponer, modificar o verificar código en este repositorio.

El agente opera bajo el principio de **Mínimo Privilegio** y **Supervisión Humana Obligatoria (Human-in-the-Loop)**. Ningún cambio generado por IA puede integrarse a ramas productivas sin validación automatizada y revisión por pares de un integrante humano del equipo.

---

## 2. Consulta Obligatoria de la Base de Conocimiento (KB)

Antes de realizar modificaciones sobre endpoints, lógica de negocio o esquemas de base de datos, el agente **DEBE consultar** la Base de Conocimiento central en:
👉 [`docs/ssdcl/01-planificacion-kb.md`](./docs/ssdcl/01-planificacion-kb.md)

### 2.1 Flujos Críticos Identificados

| ID Flujo | Nombre del Flujo | Endpoint / Ruta | Justificación e Impacto de Fallo |
| :--- | :--- | :--- | :--- |
| **`FLOW-01`** | **Cruce Geoespacial y Panorama Cantonal** | `GET /api/cantones/:id/panorama` | Cálculo del percentil `indice_cobertura` (`0..100`) y ratio cantonal. Un fallo distorsiona la toma de decisiones territoriales de emergencia. |
| **`FLOW-02`** | **Consulta Multicapa Dinámica** | `GET /api/delitos`<br/>`GET /api/accidentes`<br/>`GET /api/infraestructura` | Filtros dinámicos (`canton`, `tipo`, `desde`, `hasta`, `anio`). Requiere cotas estrictas (`LIMIT 1000`/`5000`) para evitar DoS. |
| **`FLOW-03`** | **Ingesta y Normalización OSINT** | `workers/{oij,cosevi,snit,osm}/*.py` | Cruza la frontera de confianza hacia APIs públicas y escribe en PostGIS. Requiere transacciones atómicas y timeouts. |

### 2.2 Amenazas STRIDE y Controles Vinculados

El agente debe verificar que todo código preserve los siguientes controles preventivos:

| Amenaza | Tipo STRIDE | Control Asociado | Regla Obligatoria en Código |
| :---: | :--- | :---: | :--- |
| **`THR-01`** | Tampering / Information Disclosure | **`CTL-01`** | Prohibido interpolar strings en consultas SQL (`${...}`). Obligatorio usar parámetros enlazados en TypeORM / QueryBuilder. Detección por Semgrep `ssdcl-ts-raw-sql-interpolation`. |
| **`THR-02`** | Denial of Service (DoS) | **`CTL-02`** | Consultas en backend con cotas explícitas (`take(1000)` / `limit(5000)`). En Python, llamadas `requests` con `timeout=15` obligatorio. |
| **`THR-03`** | Information Disclosure | **`CTL-03`** | Secretos únicamente inyectados por variables de entorno (`process.env`). Prohibido hardcodear contraseñas o tokens. Escaneo con Gitleaks y Semgrep. |
| **`THR-04`** | Tampering (Corrupción OSINT) | **`CTL-04`** | Workers Python deben validar columnas mínimas requeridas, tipos y rango de años (`1900..2100`). Prohibido `verify=False` en peticiones HTTPS. |
| **`THR-05`** | Elevation of Privilege | **`CTL-05`** | Dockerfiles deben declarar usuario no root (`USER nodejs` / `USER nginx`). Contenedores sin modo privilegiado (`no-new-privileges`). |
| **`THR-06`** | Repudiation / Falta Trazabilidad | **`CTL-06`** | Logs de eventos de seguridad con `correlationId` (UUID v4). Anonimización de IP con sal persistente (`actor_id`). Prohibido registrar contraseñas o stack traces en 500. |

---

## 3. Límites Estrictos del Agente (Archivos y Acciones Restringidas)

### ⛔ 3.1 Prohibiciones Absolutas (No Modificar sin Aprobación Humana Explícita)
El agente **TIENE PROHIBIDO** crear, editar o eliminar los siguientes componentes bajo ninguna circunstancia sin autorización explícita:

1. **Workflows de CI/CD:** `.github/workflows/*.yml` (incluyendo `ci.yml`, `container-supply-chain.yml`, `release-deploy.yml`).
2. **Reglas y Políticas de Seguridad:** `.semgrep.yml`, `.gitleaks.toml`, `policy/*.rego`, `osv-scanner.toml`. El agente **no puede relajar ni suprimir reglas de seguridad** para forzar que un análisis pase.
3. **Archivos de Secretos y Configuración Local:** `.env`, `.env.local`, `.docker/config.json`.
4. **Scripts de Verificación y Rollback:** `scripts/agent-verify.ps1`, `scripts/agent-verify.sh`, `scripts/rollback.*`.
5. **Registro de Hallazgos y Excepciones:** `docs/ssdcl/REGISTRO-HALLAZGOS.md` (las excepciones de seguridad solo pueden ser aprobadas por integrantes humanos).

### ⚠️ 3.2 Protocolo ante Dudas de Permisos o Alcance
Si una tarea técnica presenta ambigüedades respecto a permisos de acceso, supresión de dependencias, exposición de puertos o cambios en la base de datos:
1. **Detenerse de inmediato.**
2. **No asumir ni improvisar configuraciones permisivas.**
3. **Señalar explícitamente la duda al desarrollador humano**, indicando el riesgo de seguridad potencial y la opción más segura recomendada.

---

## 4. Convenciones de Arquitectura y Código

Todo código propuesto debe apegarse a:

1. **TypeScript Estricto:** Prohibido el uso de `any` injustificado. Tipado estricto en interfaces de NestJS y componentes de React.
2. **Arquitectura Desacoplada:** El Frontend React tiene **estrictamente prohibido** invocar directamente APIs externas de fuentes OSINT (OIJ, COSEVI, etc.). Todo consumo debe realizarse a través del API Gateway del backend (`/api/*`).
3. **Atribución y Trazabilidad:** Todo registro persistido o devuelto en los endpoints debe preservar los metadatos de procedencia:
   - `fuente`: Nombre de la fuente oficial (`SNIT/ArcGIS`, `OIJ/CKAN`, `COSEVI`, `OSM/Overpass`).
   - `fecha_obtencion`: Timestamp ISO 8601 de la extracción de los datos.
   - Cabeceras HTTP: `X-Data-Source` y `X-Fetch-Date`.
4. **Sanitización de Respuestas:** Los errores de servidor (`500 Internal Server Error`) nunca deben propagar trazas de pila (*stack traces*), rutas de archivos del host ni fragmentos de consultas SQL al cliente.

---

## 5. Comandos Reproducibles de Calidad, Compilación y Seguridad

El agente debe verificar localmente el impacto de sus cambios antes de reportar una tarea como lista:

### 5.1 Compilación y Linter
```bash
# Frontend
cd frontend && npm run lint && npm run build

# Backend
cd backend && npm run lint && npm run build
```

### 5.2 Pruebas Automatizadas
```bash
# Pruebas unitarias en Backend (Jest)
cd backend && npm test

# Pruebas de integración API + BD (Supertest)
cd backend && npm run test:integration

# Pruebas unitarias de Workers Python
python -m unittest discover -s workers/cosevi -p "test_*.py" -v
```

### 5.3 Verificación SAST y Secretos
```bash
# Análisis estático SAST local (Semgrep)
python scripts/sast-check.py

# Detección de fugas de secretos (Gitleaks con redacción de datos)
gitleaks dir . --config .gitleaks.toml --redact
```

---

## 6. Integración con el Hook Guardián (`agent-verify`, Ítem 2.4)

Este repositorio cuenta con el script wrapper oficial de verificación desarrollado por Brandon Corrales (`scripts/agent-verify.ps1` en Windows y `scripts/agent-verify.sh` en Linux/macOS).

### 6.1 Ejecución Manual
Para ejecutar la suite completa de verificaciones del agente:
```powershell
powershell -ExecutionPolicy Bypass -File scripts/agent-verify.ps1
```

### 6.2 Comportamiento en Modo Hook Automático
Cuando se utiliza con asistentes que soportan hooks de parada (ej. Claude Code con `.claude/settings.json`):
- Se ejecuta automáticamente al finalizar cada respuesta.
- Si detecta un fallo, el agente recibe el extracto del error con código `exit 2` para corregirlo.
- **Límite de 3 intentos:** Si el agente acumula 3 fallos consecutivos, el script se bloquea automáticamente (`reports/agent-verify-blocked-*.json`), emite `exit 0` y solicita intervención humana para evitar bucles destructivos.
