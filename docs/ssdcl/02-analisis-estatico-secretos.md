# Análisis de Seguridad en el Entorno de Desarrollo — Etapa 2 (`Ítem 2.3`)

> **Responsable Principal:** Roberto (`RobertoUNA`)  
> **Revisor:** Billy Ugalde (`Billy-Ugalde`)  
> **Archivos de Configuración:** [`.semgrep.yml`](../../.semgrep.yml), [`.gitleaks.toml`](../../.gitleaks.toml), [`scripts/sast-check.py`](../../scripts/sast-check.py), [`scripts/security-scan.ps1`](../../scripts/security-scan.ps1)

---

## 1. Alcance de los Análisis y Criterios de Corrección

### 1.1 Análisis Estático de Seguridad de Aplicaciones (SAST) — Semgrep CE
Se configuró [`.semgrep.yml`](../../.semgrep.yml) para analizar el código fuente del backend (`backend/src/**/*.ts`), del frontend (`frontend/src/**/*.tsx`) y de los workers de ingesta OSINT (`workers/**/*.py`).

| ID de Regla en `.semgrep.yml` | Lenguaje / Alcance | Amenaza / Control (`KB`) | Severidad | Qué Detecta y Criterio de Corrección |
| :--- | :---: | :---: | :---: | :--- |
| `ssdcl-ts-raw-sql-interpolation` | TypeScript / JS (`backend/`) | `THR-01` / `CTL-01` (`CWE-89`) | `ERROR` (Bloqueante) | Detecta interpolación de variables (`${...}`) dentro de `.query()`, `.where()`, `.andWhere()` o `.orWhere()`. **Corrección obligatoria:** usar parámetros enlazados (`:param`, `{ param }`). |
| `ssdcl-ts-dangerous-eval-or-function` | TypeScript / JS (`backend/`, `frontend/`) | `CTL-01` (`CWE-95`) | `ERROR` (Bloqueante) | Detecta uso de `eval()` o `new Function()`. **Corrección obligatoria:** eliminar ejecución dinámica de cadenas. |
| `ssdcl-ts-cors-wildcard-credentials` | TypeScript (`backend/`) | `CWE-942` | `WARNING` | Detecta combinación insegura `origin: '*'` con `credentials: true` en `enableCors()`. |
| `ssdcl-py-requests-without-timeout` | Python (`workers/`) | `THR-02` / `CTL-02` (`CWE-400`) | `ERROR` (Bloqueante) | Detecta llamadas `requests.get()` o `requests.post()` hacia fuentes OSINT sin parámetro `timeout=...`. **Corrección obligatoria:** definir timeout explícito. |
| `ssdcl-py-insecure-ssl-verify-false` | Python (`workers/`) | `THR-04` / `CTL-04` (`CWE-295`) | `ERROR` (Bloqueante) | Detecta `verify=False` en peticiones HTTPS. **Corrección obligatoria:** mantener validación TLS activa. |
| `ssdcl-py-raw-sql-format-string` | Python (`workers/`) | `THR-01` / `CTL-01` (`CWE-89`) | `ERROR` (Bloqueante) | Detecta `f-strings` o `.format()` dentro de `cur.execute()`. **Corrección obligatoria:** usar placeholders `%s` de `psycopg2`. |
| `ssdcl-hardcoded-db-password` | TS / JS / Python | `THR-03` / `CTL-03` (`CWE-798`) | `ERROR` (Bloqueante) | Detecta contraseñas literales asignadas en objetos de configuración de base de datos. |

### 1.2 Detección de Secretos — Gitleaks
Se configuró [`.gitleaks.toml`](../../.gitleaks.toml) extendiendo el catálogo oficial de Gitleaks (`useDefault = true`: claves AWS, tokens de GitHub, claves privadas RSA/SSH, JWT, tokens genéricos) más dos reglas específicas para el proyecto:
1. **`postgres-connection-uri-with-password`**: Detecta cadenas `postgres://usuario:password@host/db` o `postgresql://...` con credenciales embebidas (`THR-03`).
2. **`hardcoded-db-password-env-assignment`**: Detecta asignaciones directas `DB_PASSWORD=...` cuyo valor no sea un placeholder documentado (`tu_password`, `TU_PASSWORD_AQUI`, `cambia_por_tu_password`).

> **Política de corrección:** Todo hallazgo de severidad `ERROR` en Semgrep o cualquier secreto detectado por Gitleaks devuelve código de salida `1`, bloqueando tanto el wrapper local como el pipeline de GitHub Actions (`Ítem 3.2`). Si una credencial real llega a exponerse, debe **rotarse/revocarse inmediatamente** según el catálogo de secretos (`Ítem 1.5`), no solo borrarse del archivo.

---

## 2. Comandos Reproducibles de Ejecución Local

```powershell
# 1. Ejecutar el script unificado (SAST + Gitleaks)
powershell -ExecutionPolicy Bypass -File scripts/security-scan.ps1

# 2. Ejecutar únicamente SAST (usa semgrep CLI si está en PATH o el verificador nativo de .semgrep.yml)
python scripts/sast-check.py

# 3. Ejecutar Semgrep CE mediante contenedor oficial Docker
docker run --rm -v "${PWD}:/src" semgrep/semgrep semgrep scan --config /src/.semgrep.yml --error /src

# 4. Ejecutar Gitleaks sobre el árbol de trabajo y sobre el historial de Git
gitleaks dir . --config .gitleaks.toml --verbose
gitleaks git . --config .gitleaks.toml --verbose
```

---

## 3. Evidencia Verificable: Demostración con Defecto Controlado y Secreto Ficticio

Para comprobar empíricamente que las herramientas detectan incumplimientos y bloquean el flujo antes de integrar cambios, se creó de forma controlada el archivo temporal `backend/src/modules/oij/defect_demo.temp.ts` con:
1. **Un secreto ficticio** (`postgresql://seguridad_vial:F4k3_S3cr3t_P@ssw0rd_998877!@localhost:5432/seguridad_vial_db`).
2. **Dos defectos SAST controlados**: uso de `eval(...)` y concatenación directa con template string en `qb.where(\`d.nombre = '${cantonInput}'\`)`.

### 3.1 Resultado de la Ejecución con el Defecto y el Secreto Ficticio (Bloqueo Confirmado)

**Salida de SAST (`python scripts/sast-check.py` / `.semgrep.yml`):**
```text
[SAST] Analizando código con las reglas de .semgrep.yml (modo nativo multiplataforma)...
[SAST] Archivos analizados: 38 | Reglas activas (.semgrep.yml): 5

[SAST] ✗ Se encontraron 2 hallazgo(s) que bloquean la verificación:

  - [ERROR] ssdcl-ts-raw-sql-interpolation (CWE-89 | THR-01 / CTL-01)
    Archivo: backend\src\modules\oij\defect_demo.temp.ts:12
    Detalle: Posible inyección SQL: interpolación ${...} dentro de .query/.where/.andWhere/.orWhere.
    Código:  return qb.where(`d.nombre = '${cantonInput}'`);

  - [ERROR] ssdcl-ts-dangerous-eval-or-function (CWE-95 | CTL-01)
    Archivo: backend\src\modules\oij\defect_demo.temp.ts:11
    Detalle: Ejecución dinámica de código insegura: uso prohibido de eval() o new Function().
    Código:  eval('console.log("unsafe eval")');

SAST_EXIT_CODE=1
```

**Salida de Gitleaks (`gitleaks dir . --config .gitleaks.toml --verbose`):**
```text
    ○
    │╲
    │ ○
    ○ ░
    ░    gitleaks

Finding:     'postgresql://seguridad_vial:F4k3_S3cr3t_P@ssw0rd_998877!@localhost:5432/seg...
Secret:      F4k3_S3cr3t_P
RuleID:      postgres-connection-uri-with-password
Entropy:     3.180833
Tags:        [database postgres secret THR-03]
File:        backend\src\modules\oij\defect_demo.temp.ts
Line:        7
Fingerprint: backend\src\modules\oij\defect_demo.temp.ts:postgres-connection-uri-with-password:7

3:25PM INF scan completed in 1.51s
3:25PM WRN leaks found: 1
GITLEAKS_EXIT_CODE=1
```

### 3.2 Resultado Posterior a la Eliminación/Corrección del Defecto y Secreto

Una vez remediado el archivo de prueba, ambas herramientas se ejecutaron nuevamente sobre los 37 archivos de código fuente y los commits del repositorio:

```text
[SAST] Analizando código con las reglas de .semgrep.yml (modo nativo multiplataforma)...
[SAST] Archivos analizados: 37 | Reglas activas (.semgrep.yml): 5
[SAST] ✓ 0 hallazgos detectados. Código cumple las reglas de .semgrep.yml.
CLEAN_SAST_EXIT_CODE=0

    ○
    │╲
    │ ○
    ○ ░
    ░    gitleaks

3:26PM INF scan completed in 1.53s
3:26PM INF no leaks found
CLEAN_GITLEAKS_EXIT_CODE=0
```
