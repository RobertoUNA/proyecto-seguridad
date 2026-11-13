# Evidencia de Pruebas Asistidas por IA y Corrección de Defectos — Etapa 4 (`Ítems 4.8 y 4.9`)

> **Proyecto:** Observatorio de Seguridad Vial y Urbana de Costa Rica (`proyecto-seguridad`)  
> **Responsable:** Jose Picado (`Jose-Picado-Zamora`) — *Responsable de Requisitos y Base de Conocimiento (KB)*  
> **Revisor Asignado:** Billy Ugalde (`Billy-Ugalde`)  
> **Archivos Asociados:** [`docs/ssdcl/01-planificacion-kb.md`](./01-planificacion-kb.md), [`backend/src/modules/cruce/cruce.service.ts`](../../backend/src/modules/cruce/cruce.service.ts), [`backend/test/api.integration.spec.ts`](../../backend/test/api.integration.spec.ts)

---

## 1. Propósito y Alcance del Control

En cumplimiento con los requerimientos de verificación de calidad y robustez del SSDLC:
- **Ítem 4.8 (Pruebas asistidas por IA):** Contrastar los criterios de aceptación `Dado / Cuando / Entonces` definidos en la Base de Conocimiento ([`01-planificacion-kb.md`](./01-planificacion-kb.md)) para los flujos críticos **`FLOW-01`** y **`FLOW-02`**, identificando casos límite o pruebas de abuso faltantes.
- **Ítem 4.9 (Demostración de ciclo de detección y corrección):** Introducir de manera controlada **1 defecto funcional** y **1 defecto de seguridad**, registrar la ejecución fallida en rojo, aplicar la remediación asistida y registrar la ejecución aprobada en verde.

---

## 2. Análisis Asistido por IA sobre Criterios de Aceptación (`Ítem 4.8`)

El agente de IA analizó la implementación de endpoints en relación con los criterios formalizados en la KB:

| Flujo | Criterio Evaluado | Estado en Pruebas | Hallazgo / Mejora Identificada por IA |
| :--- | :--- | :---: | :--- |
| **`FLOW-01`** | Percentil `indice_cobertura` (`0..100`) | ✅ Cubierto | Verificado con cantones semilla (`1001` San José, `2001` Alajuela). Se validó caso límite de cantón con 0 infraestructura (`1 + totalInfraestructura`). |
| **`FLOW-01`** | Manejo de Cantón Inexistente (`404`) | ✅ Cubierto | El backend debe devolver `404 Not Found` en lugar de `500 Internal Server Error` cuando no se encuentra el código o nombre. |
| **`FLOW-02`** | Validación de Fechas (`desde` > `hasta`) | ✅ Cubierto | El DTO de consulta debe validar que la fecha inicial no sea posterior a la final, respondiendo `400 Bad Request`. |
| **`FLOW-02`** | Inyección SQL en Parámetros de Filtro | ✅ Cubierto | Se incorporó prueba con payload `?tipo=x'; DROP TABLE delito;--`, validando neutralización por parámetros enlazados de TypeORM. |

---

## 3. Demostración de Detección y Corrección de Defectos (`Ítem 4.9`)

### 3.1 Defecto 1 (Funcional): Cálculo Invertido del Percentil Cantonal

#### A. Inyección del Defecto Controlado
En [`backend/src/modules/cruce/cruce.service.ts`](../../backend/src/modules/cruce/cruce.service.ts), se alteró deliberadamente la lógica de cálculo del percentil:
```typescript
// DEFECTO CONTROLADO INYECTADO: Se invirtió la condición de cálculo (menores -> mayores)
const mayores = scores.filter((s) => s > scoreActual).length;
const indiceCobertura = Math.round((mayores / (n - 1)) * 100); // ❌ Error funcional
```

#### B. Ejecución Fallida (Rojo ❌)
Al ejecutar la suite de pruebas con `npm test`:
```text
FAIL src/modules/cruce/cruce.service.spec.ts
  CruceService
    obtenerPanorama
      ✕ calcula correctamente el percentil del indice de cobertura cantonal (12 ms)

  ● CruceService › obtenerPanorama › calcula correctamente el percentil del indice de cobertura cantonal

    expect(received).toBe(expected) // Object.is equality

    Expected: 100
    Received: 0

      42 |       const panorama = await service.obtenerPanorama('1001');
      43 |       expect(panorama.properties.indice_cobertura_ratio).toBe(21.5);
    > 44 |       expect(panorama.properties.indice_cobertura).toBe(100);
         |                                                   ^
      45 |     });
```

#### C. Corrección Aplicada (Asistida por IA)
Se restauró la fórmula correcta basada en la definición matemática de percentil (proporción de cantones con score inferior):
```typescript
// CORRECCIÓN APLICADA: Conteo estricto de valores menores
const menores = scores.filter((s) => s < scoreActual).length;
const indiceCobertura = n === 1 ? 100 : Math.round((menores / (n - 1)) * 100); // ✅ Correcto
```

#### D. Ejecución Aprobada (Verde ✅)
```text
PASS src/modules/cruce/cruce.service.spec.ts
  CruceService
    obtenerPanorama
      ✓ calcula correctamente el percentil del indice de cobertura cantonal (4 ms)
      ✓ maneja division por cero cuando totalInfraestructura es cero (2 ms)
      ✓ lanza NotFoundException cuando el canton no existe (2 ms)

Test Suites: 1 passed, 1 total
Tests:       3 passed, 3 total
Snapshots:   0 total
Time:        1.214 s
```

---

### 3.2 Defecto 2 (Seguridad): Fuga de Información en Error de Base de Datos (`THR-01` / `CTL-01`)

#### A. Inyección del Defecto Controlado
En el controlador de cruce, se modificó el bloque de captura de errores para responder directamente con el objeto de error crudo (`error.message` y `error.stack`):
```typescript
// DEFECTO CONTROLADO DE SEGURIDAD: Exposición de error interno al cliente HTTP
@Get('cantones/:id/panorama')
async getPanorama(@Param('id') id: string) {
  try {
    return await this.cruceService.obtenerPanorama(id);
  } catch (err: any) {
    throw new HttpException({ error: err.message, stack: err.stack, sql: err.query }, 500); // ❌ Fuga de información
  }
}
```

#### B. Ejecución Fallida (Rojo ❌)
El escáner estático Semgrep y la prueba de integración con Supertest detectaron la fuga:
```text
[FAIL] security:sast-check
- rule: ssdcl-ts-information-disclosure-stacktrace
  file: backend/src/modules/cruce/cruce.controller.ts:48
  message: [THR-01 / CTL-06] Prohibido retornar err.stack o err.query en respuestas HTTP al cliente.

[FAIL] backend:test (Supertest)
  ● API + BD de pruebas (integracion) › GET /api/cantones/9999/panorama
    expect(res.body).not.toHaveProperty('stack')
    Received: { error: "QueryFailedError: ...", stack: "Error: ...\n at Query.run (/app/node_modules/pg/..." }
```

#### C. Corrección Aplicada (Asistida por IA)
Se aplicó el estándar de sanitización de excepciones de NestJS definido en `AGENTS.md` y `CTL-06`:
```typescript
// CORRECCIÓN APLICADA: Delegación en excepciones tipadas estándar
@Get('cantones/:id/panorama')
async getPanorama(@Param('id') id: string) {
  const result = await this.cruceService.obtenerPanorama(id);
  if (!result) {
    throw new NotFoundException(`Cantón '${id}' no encontrado`); // ✅ Respuesta limpia 404
  }
  return result;
}
```

#### D. Ejecución Aprobada (Verde ✅)
```text
PASS backend/test/api.integration.spec.ts
  API + BD de pruebas (integracion)
    GET /api/cantones/:id/panorama
      ✓ 404 cuando el canton no existe sin exponer trazas internas (18 ms)
      ✓ respuesta saneada sin campos stack ni query (14 ms)

Test Suites: 1 passed, 1 total
Tests:       8 passed, 8 total
Snapshots:   0 total
Time:        2.456 s
```

---

## 4. Registro en el Historial del Proyecto

- **Hallazgos Asociados:** Los defectos controlados y sus correcciones se vincularon a los controles `CTL-01` (neutralización de inyecciones), `CTL-02` (cotas de disponibilidad) y `CTL-06` (sanitización de respuestas y trazabilidad).
- **Aprobación de la Suite:** Ambos ciclos demuestran que el pipeline detecta fallos funcionales y de seguridad de forma determinista, bloqueando el avance hasta que la remediación quede verificada con pruebas automáticas.
