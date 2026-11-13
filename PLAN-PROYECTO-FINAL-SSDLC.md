# Plan Maestro y Asignación de Tareas — Proyecto Final de Desarrollo Seguro de Software (SSDLC & DevSecOps)

> **Proyecto base (Caso de Uso):** Observatorio de Seguridad Vial y Urbana de Costa Rica (OSINT: OIJ, COSEVI, SNIT, OpenStreetMap/Overpass)  
> **Fecha de entrega:** Viernes 13 de noviembre de 2026 a las 23:59:59 (Hora de Costa Rica)  
> **Valor total:** 30% de la nota del curso (20% grupal · 10% defensa individual)  
> **Integrantes del equipo:** Roberto (`RobertoUNA`), Billy (`Billy-Ugalde`), Jose (`Jose-Picado-Zamora`) y Brandon (`Brandon-Corrales`)

---

## 1. Resumen del Enunciado y Reglas de Evaluación

El objetivo del proyecto final es **construir y demostrar un Ciclo de Vida de Desarrollo Seguro de Software (SSDLC)** apoyado en **prácticas de IA, programación agéntica y DevSecOps**, tomando como referencia las **7 etapas del modelo NIST NCCoE** aplicadas a nuestro sistema web OSINT.

### Reglas clave del alcance seleccionado
1. **Mínimo por integrante y del equipo:** Cada integrante debe asumir **al menos 3 ítems numerados distintos** de las etapas 1 a 7 (mínimo **12 ítems** para un equipo de 4 personas). En este plan hemos seleccionado **16 ítems conectados** (**3 Ítems Titulares de Defensa + 1 Ítem de Enlace/Prerrequisito por integrante**) para cubrir todas las dependencias entre etapas sin huecos técnicos.
2. **Cobertura de las 7 etapas:** La selección cubre las **7 etapas** (con al menos 2 ítems por etapa) e integra **calidad, seguridad, uso de IA y automatización en CI**.
3. **Responsable y Revisor obligatorios:** Cada ítem tiene un **Responsable Principal** (quien lo implementa y lo defiende individualmente) y un **Revisor** (otro integrante del equipo que revisa el PR, valida las pruebas y aprueba los juicios humanos). **Nadie puede aprobar su propio PR ni el agente de IA puede aprobar su propio trabajo.**
4. **Evidencia verificable:** Cada tarea completada debe dejar rastro en el repositorio: archivo de configuración o código, enlace al Pull Request (PR), SHA del commit, digest de imagen Docker (`sha256:...` cuando aplique) y artefactos/reportes de ejecución. Una comprobación omitida o sin evidencia no cuenta como aprobada.

### Criterios de calificación (30%)

| Criterio | Valor | Qué se evalúa |
| :--- | :---: | :--- |
| **Repositorio y entrega** | 5% | Organización y reproducción del alcance elegido. |
| **Documentación** | 5% | Selección, responsables, evidencia y limitaciones claras (documento en Profelink + repo). |
| **Cumplimiento técnico** | 10% | Calidad (5%) y Seguridad (5%): funcionamiento e integración de los ítems elegidos. |
| **Defensa individual** | 10% | Aporte verificable, demostración en vivo y comprensión de los **3 ítems propios**. |

---

## 2. Roles Transversales del Equipo (Gobernanza SSDLC)

Además de sus ítems técnicos, el enunciado exige designar responsables de **requisitos**, **integración** y **operación**, así como mantener un **registro único de hallazgos y excepciones**:

| Integrante | Usuario GitHub | Módulo OSINT Base | Rol Transversal SSDLC | Responsabilidad del Rol |
| :--- | :--- | :--- | :--- | :--- |
| **Jose Picado** | `Jose-Picado-Zamora` | SNIT + Cruce | **Responsable de Requisitos y Base de Conocimiento (KB)** | Confirma el comportamiento esperado, permisos, flujos críticos y criterios `Dado/Cuando/Entonces`. Mantiene `AGENTS.md` y consulta al docente si una duda afecta el alcance académico. |
| **Roberto** | `RobertoUNA` | OIJ | **Responsable de Integración y CI/CD** | Administra la protección de ramas (`main` / `development`), los workflows de GitHub Actions, permisos de tokens y la verificación de checks antes de fusionar PRs. |
| **Billy Ugalde** | `Billy-Ugalde` | COSEVI | **Responsable de Calidad, Pruebas y Registro Único** | Coordina las suites de pruebas unitarias/integración y mantiene el **Registro Único de Hallazgos y Excepciones** (`docs/ssdcl/REGISTRO-HALLAZGOS.md` + GitHub Issues). |
| **Brandon Corrales** | `Brandon-Corrales` | OSM / Overpass | **Responsable de Operación, Contenedores y Despliegue** | Administra los `Dockerfile`, políticas de contenedores, publicación en Docker Hub, despliegue, monitoreo de logs de seguridad y ejecución de rollback/recuperación. |

---

## 3. Tablero Maestro de Tareas y Estado del Alcance Seleccionado

> **Instrucciones de uso:** Cada vez que un integrante inicie o termine un ítem, debe actualizar la columna **Estado** (`🔴 Pendiente`, `🟡 En progreso`, `🟢 Completado`) y colocar el enlace al **PR / Commit / Evidencia** en esta tabla dentro de su Pull Request.

| Etapa | Ítem | Descripción del Control / Entregable | Responsable Principal | Revisor | Tipo | Estado | PR / Commit / Evidencia |
| :--- | :---: | :--- | :---: | :---: | :---: | :---: | :--- |
| **1. Planificación** | **1.1** | Seleccionar **3 flujos críticos** del proyecto con actor, objetivo y criterios `Dado/Cuando/Entonces` (éxito, error y uso indebido). | **Jose** | Roberto | ⭐ Titular Defensa | 🟢 Completado | `[docs/ssdcl/01-planificacion-kb.md](./docs/ssdcl/01-planificacion-kb.md)` |
| **1. Planificación** | **1.2 + 1.7** | Mapa mínimo de arquitectura, límites de confianza, datos sensibles y tabla `actor → recurso → acción → condición` versionada con IDs (`FLOW-xx`, `THR-xx`, `CTL-xx`). | **Jose** | Billy | 🔗 Enlace / Prerreq. | 🟢 Completado | `[docs/ssdcl/01-planificacion-kb.md](./docs/ssdcl/01-planificacion-kb.md)` |
| **1. Planificación** | **1.3** | Modelado y priorización de amenazas con **STRIDE** en **OWASP Threat Dragon** (mín. 3 amenazas justificadas reutilizando el diagrama de arquitectura). | **Billy** | Jose | ⭐ Titular Defensa | 🔴 Pendiente | `docs/threat-model/amenazas-stride.json` |
| **1. Planificación** | **1.4 + 1.5** | Matriz de medidas propuestas por amenaza (`Medida | Componente | Comprobación | Responsable`) + catálogo de terceros (APIs OSINT/lockfiles) y secretos sin valores. | **Roberto** | Brandon | 🔗 Enlace / Prerreq. | 🟢 Completado | [`docs/ssdcl/01-planificacion-kb.md`](./docs/ssdcl/01-planificacion-kb.md) |
| **2. Desarrollo** | **2.1 + 1.8** | Configurar AGENTS.md con instrucciones para consultar requisitos, permisos, amenazas y comandos antes de modificar flujos cr�ticos, demostrando su uso. | **Jose** | Brandon | ⭐ Titular Defensa | 🟢 Completado | [AGENTS.md](./AGENTS.md), [docs/ssdcl/02-evidencia-agente.md](./docs/ssdcl/02-evidencia-agente.md) |
| **2. Desarrollo** | **2.2 + 4.2** | Comandos reproducibles de compilación, linting y **pruebas unitarias** de reglas de negocio (`indice_cobertura`, validaciones y parser) con errores y valores límite. | **Billy** | Roberto | ⭐ Titular Defensa | 🔴 Pendiente | `backend/src/**/*.spec.ts`, `README.md` |
| **2. Desarrollo** | **2.3** | Análisis de seguridad local con **Semgrep CE** (SAST) y **Gitleaks** (secretos), demostrado con un defecto controlado y un secreto ficticio. | **Roberto** | Billy | ⭐ Titular Defensa | 🟢 Completado | [`.semgrep.yml`](./.semgrep.yml), [`.gitleaks.toml`](./.gitleaks.toml), [`docs/ssdcl/02-analisis-estatico-secretos.md`](./docs/ssdcl/02-analisis-estatico-secretos.md) |
| **2. Desarrollo** | **2.4** | Script **hook / wrapper** para el agente (`scripts/agent-verify.ps1` y `.sh`) que ejecuta lint, tests, Semgrep y Gitleaks con límite de reintentos. | **Brandon** | Jose | 🔗 Enlace / Prerreq. | 🔴 Pendiente | `scripts/agent-verify.ps1` |
| **3. Construcción e Integración** | **3.1 + 3.6** | Workflow de **GitHub Actions** en PRs hacia `development`/`main` (lockfiles, lint, build, tests) y demostración de un **PR bloqueado** por fallo y luego corregido. | **Roberto** | Billy | ⭐ Titular Defensa | 🟢 Completado | [`.github/workflows/ci.yml`](./.github/workflows/ci.yml), [`docs/ssdcl/03-ci-sca-y-proteccion-ramas.md`](./docs/ssdcl/03-ci-sca-y-proteccion-ramas.md) |
| **3. Construcción e Integración** | **3.2** | Ejecución en CI de **Semgrep CE**, **Gitleaks** y **OSV-Scanner** (SCA de dependencias) con códigos de salida que bloquean la integración y reportes como artefactos. | **Roberto** | Jose | ⭐ Titular Defensa | 🟢 Completado | [`.github/workflows/ci.yml`](./.github/workflows/ci.yml), [`osv-scanner.toml`](./osv-scanner.toml), [`docs/ssdcl/03-ci-sca-y-proteccion-ramas.md`](./docs/ssdcl/03-ci-sca-y-proteccion-ramas.md) |
| **3. Construcción e Integración** | **3.3** | Construcción de imágenes Docker (`backend` y `frontend`), escaneo con **Trivy** (imagen + Dockerfile) y generación de **SBOM** (CycloneDX/SPDX) ligado al commit. | **Brandon** | Roberto | ⭐ Titular Defensa | 🔴 Pendiente | `backend/Dockerfile`, `frontend/Dockerfile` |
| **3. Construcción e Integración** | **3.4** | Dos políticas **Conftest + OPA/Rego** (prohibir modo `privileged` y exigir usuario no-root explícito), demostrando un caso rechazado y uno permitido. | **Brandon** | Billy | ⭐ Titular Defensa | 🔴 Pendiente | `policy/container.rego` |
| **4. Pruebas** | **4.3 + 4.1** | Ambiente aislado de pruebas con datos ficticios y **pruebas de integración API + BD** con **Supertest** (persistencia, manejo de errores 400/404 y limpieza). | **Billy** | Jose | ⭐ Titular Defensa | 🔴 Pendiente | `backend/test/integration.e2e-spec.ts` |
| **4. Pruebas** | **4.9 + 4.8** | Contraste de pruebas con IA para cubrir casos límite/abuso en filtros y demostración controlada de detección y corrección de **1 fallo funcional + 1 fallo de seguridad**. | **Jose** | Billy | ⭐ Titular Defensa | 🟢 Completado | [docs/ssdcl/04-evidencia-pruebas-ia.md](./docs/ssdcl/04-evidencia-pruebas-ia.md) |
| **5. Preparación de la Versión** | **5.1 + 5.4** | **Registro de la versión candidata** (SHA, digest de imagen, cambios, enlaces a reportes y SBOM) + plan documentado de **versión de recuperación (rollback)**. | **Jose** | Brandon | 🔗 Enlace / Prerreq. | 🟢 Completado | [docs/releases/v1.0.0-rc1.md](./docs/releases/v1.0.0-rc1.md) |
| **5. Preparación de la Versión** | **5.5** | Publicación automatizada en **Docker Hub** de la imagen aprobada (etiquetada por SHA y `development`, verificada por digest) condicionada a los checks de CI. | **Brandon** | Roberto | ⭐ Titular Defensa | 🔴 Pendiente | `.github/workflows/release-deploy.yml` |
| **6. Despliegue** | **6.5 + 6.6** | Despliegue automatizado con configuración segura (`6.2`/`6.4`), **health checks y smoke tests** posteriores al despliegue y demostración de **recuperación/reversión**. | **Roberto** | Brandon | ⭐ Titular Defensa | 🟢 Completado | [`backend/src/modules/health/`](./backend/src/modules/health/health.controller.ts), [`scripts/smoke-test.ps1`](./scripts/smoke-test.ps1), [`scripts/rollback.ps1`](./scripts/rollback.ps1), [`docs/ssdcl/06-smoke-tests-y-rollback.md`](./docs/ssdcl/06-smoke-tests-y-rollback.md) |
| **7. Operación y Mejora** | **7.2 + 7.4** | Registro estructurado de **eventos de seguridad** en backend sin exponer datos sensibles (accesos/filtros rechazados con `correlationId`) + **investigación de alerta con IA**. | **Brandon** | Billy | ⭐ Titular Defensa | 🔴 Pendiente | `backend/src/common/security-logger.interceptor.ts` |
| **7. Operación y Mejora** | **7.5 + 7.7** | **Registro Único de Hallazgos y Excepciones** (`REGISTRO-HALLAZGOS.md` + GitHub Issues), configuración de **Renovate** (`7.6`), cierre verificado de un hallazgo y aprendizaje (`7.8`). | **Billy** | Roberto | ⭐ Titular Defensa | 🔴 Pendiente | `docs/ssdcl/REGISTRO-HALLAZGOS.md`, `renovate.json` |

---

## 4. Instrucciones Detalladas por Integrante

A continuación se detalla exactamente qué debe construir, documentar y defender cada integrante.

---

### 👤 1. JOSE PICADO (`Jose-Picado-Zamora`)
**Rol transversal:** Responsable de Requisitos y Base de Conocimiento (KB)  
**Tus 3 Ítems Titulares de Defensa Individual:** `1.1` (con `1.2`/`1.7`), `2.1` (con `1.8`), `4.9` (con `4.8`)  
**Tu Ítem de Enlace/Soporte:** `5.1 + 5.4` (Registro de versión candidata y plan de recuperación)  
**Revisiones que debes hacer (Peer Review):** Revisar `1.3` y `4.3` (de Billy), `2.4` (de Brandon) y `3.2` (de Roberto).

#### Paso a paso de tus tareas:
1. **Tarea A — Base de Conocimiento y Flujos Críticos (`Ítems 1.1, 1.2 y 1.7`)**:
   - Crear el archivo `docs/ssdcl/01-planificacion-kb.md`.
   - Definir los **3 flujos críticos** del sistema justificando su importancia por los datos que manejan o el impacto de un fallo:
     - `FLOW-01`: **Cruce geoespacial y cálculo del índice de vulnerabilidad cantonal** (`GET /api/cantones/:id/panorama`).
     - `FLOW-02`: **Consulta filtrada de delitos (OIJ), accidentes (COSEVI) e infraestructura (OSM)** (`GET /api/delitos`, `/api/accidentes`, `/api/infraestructura`).
     - `FLOW-03`: **Ingesta y normalización de fuentes OSINT hacia PostgreSQL/PostGIS** (`workers/*/fetch_*.py`).
   - Para cada flujo escribir: **Actor**, **Objetivo**, **Resultado esperado** y al menos 3 escenarios en formato **`Dado / Cuando / Entonces`** cubriendo:
     - ✅ Caso de éxito.
     - ⚠️ Caso de error controlado (ej. cantón inexistente `404`, fuente externa caída o timeout).
     - 🚫 Caso de uso indebido / abuso (ej. intento de inyección SQL en query params `?canton=' OR 1=1--`, rango de años inválido, intento de lectura/escritura fuera de permisos).
   - Incluir la tabla de arquitectura y acceso: `Actor/Rol → Recurso → Acción → Condición de acceso` (distinguiendo consulta pública de solo lectura vs. ejecución administrativa de workers/migraciones).
2. **Tarea B — Configuración de `AGENTS.md` (`Ítems 1.8 y 2.1`)**:
   - Crear el archivo `AGENTS.md` en la raíz del repositorio.
   - Indicar obligatoriamente:
     - Dónde consultar los flujos (`FLOW-01..03`), amenazas (`THR-01..05`) y controles (`CTL-01..05`) en `docs/ssdcl/01-planificacion-kb.md`.
     - Las convenciones del proyecto (TypeScript estricto en NestJS/React, prohibición de llamadas directas del frontend a fuentes OSINT externas, obligación de conservar `fuente` y `fecha_obtencion`).
     - Los comandos exactos de compilación, linting, pruebas y seguridad (`npm run build`, `npm test`, Semgrep, Gitleaks).
     - Límites del agente: qué archivos no puede modificar sin aprobación humana (workflows de CI, reglas de seguridad, `.env`), y que ante cualquier duda sobre permisos debe detenerse y preguntar al humano.
   - Guardar evidencia en `docs/ssdcl/02-evidencia-agente.md` de una sesión donde el agente lee `AGENTS.md`, consulta la KB antes de tocar un endpoint y señala dudas humanas.
3. **Tarea C — Pruebas Asistidas por IA y Detección/Corrección de Fallos (`Ítems 4.8 y 4.9`)**:
   - Usar el agente de IA para contrastar los criterios `Dado/Cuando/Entonces` de `FLOW-01` y `FLOW-02` contra las pruebas existentes, identificando casos límite o de seguridad faltantes (por ejemplo, validación estricta de query params `anio`, `desde`, `hasta`, `canton` en los controladores de NestJS para rechazar entradas malformadas con `400 Bad Request`).
   - Demostrar el ciclo de detección y corrección (`4.9`):
     - Introducir de forma controlada **1 defecto funcional** (ej. cálculo invertido del percentil en `indice_cobertura`) y **1 defecto de seguridad** (ej. aceptar parámetros sin sanitizar/validar o exponer stacktrace/metadatos internos).
     - Ejecutar la suite de pruebas y guardar captura/log de la **ejecución fallida**.
     - Aplicar la corrección, volver a ejecutar la suite y guardar evidencia de la **ejecución aprobada**. Documentarlo en `docs/ssdcl/04-evidencia-pruebas-ia.md`.
4. **Tarea D — Registro de Versión Candidata y Plan de Recuperación (`Ítems 5.1 y 5.4`)**:
   - Crear `docs/releases/v1.0.0-rc1.md` que registre: SHA del commit aprobado, digest de las imágenes Docker (`backend` y `frontend`), resumen de cambios y limitaciones conocidas (`5.3`), enlaces a los reportes de CI/Semgrep/Trivy/SBOM y los pasos exactos para revertir a la versión anterior o retirar el despliegue (`5.4`).

---

### 👤 2. BILLY UGALDE (`Billy-Ugalde`)
**Rol transversal:** Responsable de Calidad, Pruebas y Registro Único de Hallazgos  
**Tus 3 Ítems Titulares de Defensa Individual:** `1.3` (STRIDE / Threat Dragon), `2.2` (con `4.2`), `4.3` (con `4.1`) + `7.5` (con `7.7`)  
**Revisiones que debes hacer (Peer Review):** Revisar `1.2` y `4.9` (de Jose), `2.3` y `3.1` (de Roberto), `3.4` y `7.2` (de Brandon).

#### Paso a paso de tus tareas:
1. **Tarea A — Modelo de Amenazas STRIDE con OWASP Threat Dragon (`Ítem 1.3`)**:
   - Descargar o abrir [OWASP Threat Dragon](https://owasp.org/www-project-threat-dragon/) (aplicación de escritorio o web).
   - Crear el diagrama de flujo de datos (DFD) de `proyecto-seguridad` mostrando los límites de confianza (*Trust Boundaries*):
     1. Usuario / Navegador (`Frontend React + Leaflet`).
     2. API Backend (`NestJS /api/*`).
     3. Base de Datos (`PostgreSQL + PostGIS`).
     4. Workers de Ingesta Python y Fuentes OSINT Externas (`OIJ`, `COSEVI`, `SNIT`, `Overpass API`).
   - Documentar y priorizar **al menos 4 a 6 amenazas usando STRIDE**:
     - `THR-01` (**Tampering / Injection**): Manipulación de parámetros de filtro en `/api/delitos`, `/api/accidentes` o `/api/cantones/:id/panorama` para alterar consultas o provocar errores no controlados.
     - `THR-02` (**Denial of Service**): Consultas masivas sin límite de registros o sobrecarga hacia la API / fuentes externas (como el caso real ocurrido en `/api/infraestructura`).
     - `THR-03` (**Information Disclosure**): Exposición de credenciales de base de datos (`.env` / contraseñas hardcodeadas en git history) o exposición directa del puerto de PostgreSQL.
     - `THR-04` (**Tampering / Spoofing en Ingesta OSINT**): Cambio de formato o corrupción de datos en el CSV/API de una fuente pública externa que contamine la tabla PostGIS.
     - `THR-05` (**Elevation of Privilege / Configuración Insegura de Contenedor**): Ejecución del contenedor backend como `root` o en modo privilegiado.
   - Guardar el JSON del modelo en `docs/threat-model/proyecto-seguridad-threat-dragon.json` y exportar la imagen del diagrama en `docs/threat-model/arquitectura-stride.png` (así sirve también para el ítem `1.2`).
2. **Tarea B — Comandos Reproducibles de Calidad y Pruebas Unitarias (`Ítems 2.2 y 4.2`)**:
   - Configurar Jest y ESLint en `backend/package.json` (`npm run lint`, `npm test`, `npm run test:cov`) además de los tests existentes en `workers/cosevi/test_fetch_accidentes.py`.
   - Crear pruebas unitarias en `backend/src/modules/cruce/cruce.service.spec.ts` (y módulos OSINT) que prueben la regla de negocio central del proyecto: el cálculo del **`indice_cobertura`** y **`indice_cobertura_ratio`**, incluyendo:
     - Caso normal (comparación de percentiles entre cantones).
     - Valores límite: cantón con `0` infraestructura (verificar que `1 + infraestructura` evita división por cero), cantón con `0` delitos y `0` accidentes, cantón único.
     - Casos de error: cantón no encontrado (`NotFoundException`), parámetros inválidos.
   - Documentar los comandos exactos en `README.md` y verificar que `AGENTS.md` los referencie.
3. **Tarea C — Ambiente de Pruebas y Pruebas de Integración con Supertest (`Ítems 4.1 y 4.3`)**:
   - Preparar un script/configuración de base de datos de pruebas con datos semilla controlados (`backend/database/seed_test.sql`) para que las pruebas sean 100% repetibles sin depender de datos de producción (`4.1`).
   - Implementar pruebas de integración con **Supertest** (`backend/test/api.integration.spec.ts`) que levanten la aplicación NestJS contra la BD de pruebas y verifiquen:
     - `GET /api/cantones` y `GET /api/cantones/:id/panorama` (estructura GeoJSON/JSON, cabeceras `X-Data-Source` y `X-Fetch-Date`, cálculo correcto).
     - `GET /api/accidentes` y `GET /api/delitos` con filtros válidos e inválidos.
     - Manejo de errores (`404` cuando un cantón no existe, `400` cuando un filtro es inválido) y limpieza posterior.
4. **Tarea D — Registro Único de Hallazgos, Renovate y Cierre Verificado (`Ítems 5.6, 7.5, 7.6, 7.7 y 7.8`)**:
   - Crear `docs/ssdcl/REGISTRO-HALLAZGOS.md` como registro central del proyecto (y crear los GitHub Issues correspondientes) con las columnas: `ID | Origen (Etapa/Herramienta) | Amenaza/Excepción relacionada | Versión/Commit afectado | Evidencia | Severidad justificada | Responsable | Estado | PR Correctivo y Verificación`.
   - Registrar al menos 3 hallazgos reales o controlados del ciclo (por ejemplo: contraseña hardcodeada detectada en historial/Gitleaks, contenedor como `root` detectado por Conftest/Trivy, o falta de validación en DTO de filtros) y demostrar el **cierre completo de al menos 1 hallazgo (`7.7`)** enlazando el PR correctivo y el check en verde.
   - Agregar `renovate.json` en la raíz del repo (`7.6`) para automatizar PRs de actualización de dependencias y documentar una mejora aprendida incorporada a las pruebas o a `AGENTS.md` (`7.8`).

---

### 👤 3. ROBERTO (`RobertoUNA`)
**Rol transversal:** Responsable de Integración y CI/CD  
**Tus 3 Ítems Titulares de Defensa Individual:** `2.3` (Semgrep CE + Gitleaks), `3.2` (con `3.1` y `3.6`: Pipeline CI + SCA + Bloqueo de PR), `6.5` (con `6.1` y `6.6`: Despliegue, Health Checks/Smoke Tests y Recuperación)  
**Tu Ítem de Enlace/Soporte:** `1.4 + 1.5` (Plan de tratamiento de amenazas + inventario de terceros y secretos)  
**Revisiones que debes hacer (Peer Review):** Revisar `1.1` (de Jose), `2.2` y `7.5` (de Billy), `3.3` y `5.5` (de Brandon).

#### Paso a paso de tus tareas:
1. **Tarea A — Plan de Tratamiento de Amenazas, Terceros y Secretos (`Ítems 1.4 y 1.5`)**:
   - En `docs/ssdcl/01-planificacion-kb.md`, completar la tabla de tratamiento para cada amenaza identificada por Billy (`THR-01` a `THR-05`): `Amenaza | Medida propuesta | Componente afectado | Comprobación prevista | Responsable | Estado (Propuesta / Implementada / Verificada)`.
   - Documentar la tabla de **Servicios Externos y Dependencias Críticas** (OIJ CKAN Azure Blob, COSEVI Portal Datos Abiertos, SNIT WFS/FeatureServer, Overpass API, más referencias a `backend/package-lock.json`, `frontend/package-lock.json` y `workers/*/requirements.txt`).
   - Documentar el **Inventario de Secretos** (sin incluir jamás valores reales): `DB_PASSWORD`, `OSM_CONTACT_EMAIL`, `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN`, indicando propósito, consumidor, permisos, responsable y ubicación de almacenamiento (`.env` local ignorado por Git / GitHub Encrypted Secrets).
2. **Tarea B — Análisis de Seguridad Local con Semgrep CE y Gitleaks (`Ítem 2.3`)**:
   - Crear `.gitleaks.toml` y `.semgrep.yml` en la raíz del proyecto con reglas adaptadas a TypeScript/NestJS, React y Python.
   - Documentar en `docs/ssdcl/02-analisis-estatico-secretos.md` cómo ejecutar ambas herramientas localmente (vía CLI o Docker: `docker run --rm -v "${PWD}:/src" zricethezav/gitleaks:latest detect --source="/src"` y `docker run --rm -v "${PWD}:/src" semgrep/semgrep semgrep scan --config auto`).
   - **Demostración obligatoria:** En una rama de prueba, introducir un **secreto ficticio** (ej. `AWS_SECRET_ACCESS_KEY="AKIAIOSFODNN7EXAMPLE..."` o token simulado) y un **defecto de seguridad controlado** (ej. consulta SQL concatenada con template string o `eval()`), ejecutar Semgrep y Gitleaks, guardar la salida donde ambos fallan/detectan el problema, y luego corregirlo.
3. **Tarea C — Pipeline de Integración Continua en GitHub Actions y Protección de Ramas (`Ítems 3.1, 3.2, 3.5 y 3.6`)**:
   - Crear `.github/workflows/ci.yml` que se ejecute en cada `pull_request` y `push` hacia `development` y `main`:
     - Job 1 (`quality-and-tests`): Levanta un contenedor de servicio `postgis/postgis:16-3.4`, instala dependencias con `npm ci` (usando lockfiles), corre migraciones, ejecuta linter, `npm run build`, pruebas unitarias y pruebas de integración con Supertest.
     - Job 2 (`security-scans`): Ejecuta **Semgrep CE**, **Gitleaks** y **OSV-Scanner** (análisis de composición de software SCA sobre `package-lock.json` y `requirements.txt`), subiendo los reportes como artefactos de GitHub Actions (`actions/upload-artifact`) y fallando el pipeline (`exit code != 0`) si hay hallazgos críticos/altos o secretos.
   - Configurar en GitHub (`Settings -> Branches`) la protección de `main` y `development`: exigir PR, al menos 1 aprobación de otro integrante y que pasen los checks obligatorios (`quality-and-tests`, `security-scans`). Fijar las acciones de terceros por SHA y usar `permissions: contents: read`.
   - **Demostración obligatoria (`3.6`):** Abrir un PR con el defecto controlado de `2.3`, tomar captura del PR bloqueado por GitHub Actions, subir el commit correctivo y mostrar el PR desbloqueado y fusionado.
4. **Tarea D — Health Checks, Smoke Tests Post-Despliegue y Demostración de Rollback (`Ítems 6.1, 6.5 y 6.6`)**:
   - Agregar un endpoint `GET /api/health` en el backend NestJS que verifique conectividad con PostgreSQL/PostGIS y devuelva estado `200 OK` + versión/commit.
   - Crear el script `scripts/smoke-test.ps1` (y `.sh`) que compruebe la aplicación desplegada (`/api/health`, `/api/cantones`, `/api/cantones/101/panorama`) y el workflow de despliegue/verificación.
   - Demostrar el procedimiento de recuperación (`6.6`): simular un fallo en la versión recién desplegada, ejecutar la reversión a la imagen anterior aprobada por digest y volver a correr los smoke tests en verde.

---

### 👤 4. BRANDON CORRALES (`Brandon-Corrales`)
**Rol transversal:** Responsable de Operación, Contenedores y Despliegue  
**Tus 3 Ítems Titulares de Defensa Individual:** `3.3` (Docker + Trivy + SBOM), `3.4` (Políticas Conftest + OPA/Rego), `5.5` (Publicación en Docker Hub por SHA/Digest) + `7.2` (con `7.4`: Logs de Seguridad e Investigación con IA)  
**Tu Ítem de Enlace/Soporte:** `2.4` (Hook/Wrapper de verificación para el agente) y `6.2 + 6.4` (Configuración segura de despliegue)  
**Revisiones que debes hacer (Peer Review):** Revisar `1.4` y `6.5` (de Roberto), `2.1` y `5.1` (de Jose).

#### Paso a paso de tus tareas:
1. **Tarea A — Hook / Wrapper de Verificación para el Agente (`Ítem 2.4`)**:
   - Crear `scripts/agent-verify.ps1` y `scripts/agent-verify.sh` que ejecuten en secuencia:
     1. Compilación de backend y frontend (`npm run build`).
     2. Linter y pruebas unitarias (`npm test`).
     3. Escaneo rápido de Gitleaks / Semgrep.
   - El script debe controlar un contador de reintentos (máximo 3 intentos por tarea agéntica) y devolver un resumen claro al agente para que corrija fallos o se detenga si persiste el bloqueo.
2. **Tarea B — Contenedores Seguros, Escaneo con Trivy y Generación de SBOM (`Ítem 3.3`)**:
   - Crear `backend/Dockerfile` y `frontend/Dockerfile` usando builds multi-stage, imágenes base ligeras (`node:22-alpine`) y un usuario explícito sin privilegios (`USER node` o `USER appuser`).
   - Crear `docker-compose.yml` en la raíz para levantar `db` (PostGIS), `backend` y `frontend`.
   - Integrar **Trivy** (en local y en `.github/workflows/ci.yml`) para:
     - Escanear vulnerabilidades de la imagen construida y configuraciones de `Dockerfile`.
     - Generar un **SBOM** en formato **CycloneDX** (`sbom-backend.cdx.json` y `sbom-frontend.cdx.json`) identificando el commit y la imagen analizada.
3. **Tarea C — Políticas como Código con Conftest y OPA/Rego (`Ítem 3.4`)**:
   - Crear la carpeta `policy/` con el archivo `policy/container.rego` que automatice las **2 políticas exigidas por el enunciado**:
     1. **Política 1:** Prohibir ejecutar contenedores en modo privilegiado (`privileged: true` en `docker-compose.yml` o configuración de despliegue).
     2. **Política 2:** Exigir un usuario no-root explícito (`USER` distinto de `root` / `0` en `Dockerfile`).
   - **Demostración obligatoria:** Guardar un ejemplo de archivo rechazado (`policy/examples/Dockerfile.insecure`) y el archivo de producción permitido (`backend/Dockerfile`), ejecutando `conftest test` y conservando la evidencia tanto del rechazo como de la aprobación en `docs/ssdcl/03-evidencia-conftest-trivy.md`.
4. **Tarea D — Publicación en Docker Hub por Digest y Configuración Segura de Despliegue (`Ítems 5.5, 6.2 y 6.4`)**:
   - Configurar en `.github/workflows/release-deploy.yml` el push automático a **Docker Hub** condicionado a que todos los checks de CI (`3.1` a `3.4`) hayan aprobado.
   - Etiquetar las imágenes con el SHA del commit (`sha-<commit>`) y `development`, registrando el **digest inmutable** (`sha256:...`).
   - Documentar en `docs/ssdcl/06-despliegue-seguro.md` la arquitectura de despliegue (`deploy/docker-compose.prod.yml`), asegurando que PostgreSQL solo sea accesible en la red interna de Docker y que las credenciales se inyecten como secretos protegidos (`6.2`, `6.4`).
5. **Tarea E — Registro de Eventos de Seguridad e Investigación de Alerta con IA (`Ítems 7.2 y 7.4`)**:
   - Implementar en el backend NestJS un interceptor/filtro (`backend/src/common/security-logger.ts`) que registre en formato JSON estructurado los **eventos relevantes de seguridad**:
     - Solicitudes rechazadas (`400 Bad Request`, `403 Forbidden`, `404 Not Found`), intentos de parámetros sospechosos (patrones de inyección o rangos fuera de límite) y errores de validación.
     - Cada log debe incluir: `timestamp`, `correlationId` (`X-Correlation-Id`), `event_type`, `method`, `path`, `statusCode`, `clientIp` (o identificador de actor) y mensaje sanitizado (**nunca** registrar contraseñas, tokens ni `.env`).
   - **Demostración con IA (`7.4`):** Generar tráfico de prueba que dispare varios eventos de acceso/filtro rechazado (alerta de seguridad), extraer el log sanitizado y pasarlo al agente de IA junto con el contexto del proyecto para que elabore un resumen del incidente, hipótesis y pasos de comprobación. Validar humanamente el análisis y documentarlo en `docs/ssdcl/07-operacion-investigacion-ia.md`.

---

## 5. Cronograma de Ejecución (Lunes 9 al Viernes 13 de Noviembre de 2026)

Para evitar cuellos de botella por dependencias entre etapas, seguiremos este orden diario:

| Día | Meta Principal | Entregables que deben quedar listos | Responsables |
| :--- | :--- | :--- | :--- |
| **Lunes 9 Nov** | **Etapa 1 (Planificación)** | Flujos críticos `1.1`, mapa de acceso `1.2`, modelo STRIDE en Threat Dragon `1.3`, tabla de medidas y secretos `1.4`/`1.5` y `AGENTS.md` inicial `1.8`/`2.1`. | Todos (Lideran Jose y Billy) |
| **Martes 10 Nov** | **Etapa 2 (Desarrollo)** | Pruebas unitarias en backend `2.2`, configuración local + prueba de fallo de Semgrep y Gitleaks `2.3`, y script wrapper del agente `2.4`. | Billy, Roberto y Brandon |
| **Miércoles 11 Nov** | **Etapa 3 y 4 (CI + Pruebas)** | `Dockerfile` + Trivy + SBOM `3.3`, políticas Conftest/Rego `3.4`, workflow GitHub Actions `3.1`/`3.2`, pruebas Supertest `4.3` y evidencia de fallos `4.9`. | Todos (PRs cruzados y bloqueo `3.6`) |
| **Jueves 12 Nov** | **Etapa 5, 6 y 7 (Release, Deploy y Operación)** | Publicación en Docker Hub `5.5`, registro de versión `5.1`/`5.4`, health checks + smoke tests + rollback `6.5`/`6.6`, security logger + análisis IA `7.2`/`7.4`, Renovate y cierre de hallazgo en registro único `7.5`/`7.7`. | Todos |
| **Viernes 13 Nov** | **Revisión Final y Entrega Profelink** | Verificación de todos los enlaces, capturas y digests en `PLAN-PROYECTO-FINAL-SSDLC.md`, generación del documento PDF/Word para Profelink y ensayo de defensa individual (antes de las 23:59:59). | Todos |

---

## 6. Instrucciones de Trabajo en el Repositorio (Paso a Paso para cada Integrante)

1. **Crear rama por tarea:** Nunca hacer push directo a `main`. Trabajar en ramas descriptivas:
   ```bash
   git checkout -b feat/etapa1-kb-jose
   # o sec/etapa2-semgrep-roberto, test/etapa4-supertest-billy, ops/etapa3-docker-brandon
   ```
2. **Consultar `AGENTS.md` y la KB:** Si usas un agente de IA (Cursor, Claude Code, Antigravity, Copilot), pídele explícitamente al iniciar la sesión: *"Lee `AGENTS.md` y `docs/ssdcl/01-planificacion-kb.md` antes de proponer cambios"* y guarda captura/transcripción como evidencia de las etapas 2, 4 y 7.
3. **Ejecutar verificaciones locales antes de abrir PR:**
   ```bash
   cd backend && npm run build && npm test
   cd ../frontend && npm run build && npm run lint
   ```
4. **Abrir Pull Request y asignar a tu Revisor:**
   - En la descripción del PR, indica qué ítem(s) del enunciado estás cumpliendo (ej. `Cumple Ítem 3.4 - Políticas Conftest OPA/Rego`).
   - Actualiza la tabla de la **Sección 3** de este archivo (`PLAN-PROYECTO-FINAL-SSDLC.md`) cambiando el estado a `🟢 Completado` y agregando el enlace a la evidencia.
   - Asigna al compañero que aparece en la columna **Revisor** de la tabla para que revise y apruebe tu PR.
5. **Preparar tu Defensa Individual (10% de la nota):**
   - Cada integrante debe poder explicar y demostrar en vivo sus **3 ítems titulares**:
     1. Qué problema o riesgo de seguridad/calidad resuelve el ítem.
     2. Qué decisiones técnicas tomó y cómo se conecta con las demás etapas del proyecto.
     3. Demostración de la evidencia (ejecución del comando/workflow, caso que falla vs. caso que aprueba) y limitaciones conocidas.
