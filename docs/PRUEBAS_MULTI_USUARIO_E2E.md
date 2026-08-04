# NEXUS Siembras — Pruebas end-to-end multi-usuario (Fase 3e-9+)

Plan de verificación completa del ciclo multi-usuario introducido en las
fases 3e-1 hasta 3e-8, ampliado con sync por lotes/paginado, soft-delete
de cultivos (tombstones), eliminar cuenta y build **0.2.8+**.

Ejecutar en orden con **dos cuentas Supabase**:

- **Cuenta A** — propietario del predio (rol autoritativo).
- **Cuenta B** — colaborador (rol trabajador por defecto).

Se recomienda usar dos dispositivos (o dispositivo + emulador) para
observar la propagación. Tras cada cambio relevante, sincronizar en el
dispositivo origen y luego en el peer.

**Versión mínima de app:** 0.2.8 (incluye soft-delete remoto al vaciar
papelera, verificación de tombstones de cultivo tras el pull, Dashboard
Windows con muestras y cronograma→Registrar tarea).

**Esquema remoto:** `schema_meta.version` ≥ **11** (alineado con
`SyncService.schemaRemotoRequerido`). Aplicar todas las migraciones en
`supabase/migrations/` en orden.

---

## Precondiciones

- [ ] Ambas cuentas fueron creadas en Supabase Auth y tienen sus emails
      verificados.
- [ ] La app está compilada con la última versión (`flutter build apk` /
      `flutter build windows --release` +
      `dart run build_runner build --delete-conflicting-outputs` si hubo
      cambios Drift).
- [ ] En Supabase están aplicadas las migraciones hasta la que sube
      `schema_meta` a **11** (incl. eliminar cuenta si se va a probar
      Bloque 10).
- [ ] Ambas cuentas tienen `consentimientoPatologias = true` (Settings
      → Comunidad NEXUS) para poder probar la contribución opt-in.
- [ ] Al menos una cuenta tiene el token EPPO configurado (Settings →
      EPPO Global Database) para probar el enriquecimiento remoto.
- [ ] (Opcional) Tests automatizados verdes:
      `flutter test test/sync_policy_test.dart test/sync_service_test.dart`.

---

## Bloque 1 — Onboarding multi-usuario

### 1.1 Onboarding con cuenta nueva (cuenta A)

En un dispositivo limpio (reset total previo):

- [ ] Abre la app → aparece el paso 0 "Iniciar sesión".
- [ ] Escribe email y contraseña de cuenta A y pulsa **Siguiente**.
- [ ] Verifica que el login se ejecuta automáticamente (no debería
      solicitar login de nuevo en el Dashboard).
- [ ] Preferencias, Predio, Ubicación, Permisos → completa normalmente.
      Crea predio "Finca de Prueba A" en Colombia.
- [ ] En el paso Permisos, los checkboxes vienen activados por defecto y
      al pulsar Siguiente se solicitan los permisos nativos del SO.
- [ ] Consentimiento activado → **Comenzar**.
- [ ] Dashboard aparece con ☁️✓ activa (sesión persistida). Card "Cuenta"
      muestra tu email en verde, sin pedir re-login.
- [ ] (0.2.7) Nav inferior: Volver / Inicio / Sync accesibles; el título
      de pantalla no queda tapado.

### 1.2 Onboarding con "sin predio propio" (cuenta B)

En otro dispositivo (o después de reset total):

- [ ] Login con cuenta B en el paso 0 del onboarding.
- [ ] Paso 2 (Predio): marca **"Continuar sin crear predio propio"**.
- [ ] Termina el onboarding.
- [ ] Dashboard muestra "Sin predios registrados" con botón **Sync** que,
      al tocar, ejecuta la sincronización directamente (sin pedir login
      de nuevo).

---

## Bloque 2 — Compartir predio (roles y permisos)

### 2.1 Compartir de A a B

En **cuenta A** (dispositivo 1):

- [ ] Ve a Predios → toca la card de "Finca de Prueba A" → botón
      **"Colaboradores"**.
- [ ] Añade el email de cuenta B con rol **"trabajador"**.
- [ ] Confirma que el chip verde "compartido" aparece bajo el email.
- [ ] Toca **Sincronizar ahora** en Cuenta → snackbar OK con
      `↑pushed ≥ 1 · ↓pulled`.

En **cuenta B** (dispositivo 2):

- [ ] Cuenta → **Sincronizar ahora**.
- [ ] Ve a Predios → aparece "Finca de Prueba A" con chip **"Compartido"**.
- [ ] Verifica que **no** hay botones de editar/eliminar en la card de
      ese predio (solo el owner puede).
- [ ] Selecciona ese predio como activo desde el selector inferior del
      Dashboard.

### 2.2 Verificación de permisos por rol (trabajador)

En **cuenta B** con Finca de Prueba A activa:

- [ ] Puede **ver** cultivos, lotes, inventario, análisis de suelo.
- [ ] Puede **crear** un cultivo nuevo → se sincroniza a A.
- [ ] Puede **editar** el inventario (consumir insumos) al registrar
      tareas.
- [ ] **NO puede** editar el predio (info general bloqueada / read-only).
- [ ] **NO puede** editar lotes.
- [ ] **NO puede** ver ni crear compras (menú Compras muestra listado
      vacío o mensaje "sin permisos").

### 2.3 Cambio de rol a consultor

En **cuenta A** → Predios → Colaboradores → cambia rol de B a **"consultor"**.

En **cuenta B**:

- [ ] Sincroniza.
- [ ] Ahora **NO puede** crear cultivos, ni editar inventario.
- [ ] Solo puede **ver** todo lo del predio.
- [ ] **NO puede** ver la lista de colaboradores.

### 2.4 Revocar acceso

En **cuenta A** → Predios → Colaboradores → elimina B.

En **cuenta B**:

- [ ] Sincroniza.
- [ ] "Finca de Prueba A" desaparece de la lista de predios.
- [ ] Los cultivos/inventario asociados a ese predio ya no son visibles.

---

## Bloque 3 — Sync bidireccional

Devuelve rol de trabajador a B para continuar.

### 3.1 Cultivos

- [ ] A crea cultivo "Frijol Cargamanto" con GNSS capturado (lat/lng/alt).
- [ ] A sincroniza → B sincroniza.
- [ ] B ve el cultivo con el mismo GNSS y ubicación en el mapa.
- [ ] La **variedad** en B coincide con A (no se intercambia por otro
      `planta_id` local).
- [ ] B registra una tarea de "Abono 1" con HH=2, insumos.
- [ ] B sincroniza → A sincroniza.
- [ ] A ve la tarea en el Cronograma → Actividades con:
      - **Autor: `<email de B>`** (Fase 3g).
      - Actividad "Abono1" registrada.
      - HH acumuladas en el cultivo.
      - Inventario reducido según insumos.

### 3.2 Inventario

- [ ] A crea inventario "Gallinaza 50kg" con cantidad_base=50.
- [ ] A sincroniza → B sincroniza.
- [ ] B ve el inventario con cantidad 50.
- [ ] B registra tarea consumiendo 10 kg de gallinaza.
- [ ] B sincroniza → A sincroniza.
- [ ] A ve inventario con cantidad 40 (no duplicado, no reset).

### 3.3 Sin duplicados tras reset

- [ ] En A, ejecuta el mantenimiento "Reemplazar nube con local".
- [ ] B sincroniza.
- [ ] B ve los mismos datos, sin duplicados.

### 3.4 Soft-delete / tombstone de cultivo (regresión 2026-08-02)

Escenario que fallaba cuando vaciar papelera hacía DELETE físico remoto
(B no recibía tombstone y fallaba al subir `eventos_cultivo` con FK 23503).

En **cuenta A**:

- [ ] Crea cultivo "Tomate chonto" (o usa uno existente visible en B).
- [ ] A sincroniza → B sincroniza → ambos ven el cultivo.
- [ ] A elimina el cultivo (papelera / soft-delete) y **sincroniza**.
- [ ] (Si aplica) A vacía la papelera y sincroniza de nuevo.

En **cuenta B**:

- [ ] Sincroniza **sin** errores de fila (no FK `cultivo_id` / 23503).
- [ ] El cultivo **desaparece** de la lista activa (o queda solo en
      papelera local si aún no se vació; no debe "revivir" como vivo).
- [ ] Si B tenía eventos locales pendientes de ese cultivo, **no** se
      re-suben contra un remoto inexistente.

Verificación remota opcional (SQL Editor):

```sql
SELECT id, nombre_planta, deleted_at, updated_at
FROM public.cultivos
WHERE nombre_planta ILIKE '%tomate chonto%'
ORDER BY updated_at DESC
LIMIT 5;
```

Esperado: fila con `deleted_at IS NOT NULL` (no borrada físicamente).

### 3.5 Sync por lotes bajo volumen

- [ ] Con varios cultivos/eventos pendientes, un sync completo termina
      sin abortar por timeout; snackbar muestra pushed/pulled coherentes.
- [ ] Si hay filas con error RLS, el sync **no** aborta entero
      (`errores` > 0 en log) y el resto sí sube.

---

## Bloque 4 — Trazabilidad (Fase 3g)

### 4.1 HH por usuario en el Dashboard

- [ ] En A y B registran tareas con HH.
- [ ] Ambos sincronizan.
- [ ] Dashboard de A → card "Horas hombre año fiscal" → sección
      **"👥 Distribución por usuario"** aparece con barras por email.
- [ ] Verifica: `HH_totales = HH_A + HH_B + HH_legacy (si aplica)`.

### 4.2 Autor visible en Cronograma

- [ ] Cronograma → Actividades → cada tarjeta muestra `👤 email` bajo
      la fecha/HH.

---

## Bloque 5 — Patologías (Fase 3e-5)

### 5.1 Reporte con foto + GNSS

En **cuenta B**:

- [ ] Ve a Ver cultivos → detalle → botón 🐛 naranja.
- [ ] Selecciona patología del catálogo (verifica que aparecen las
      asociadas a la variedad primero).
- [ ] Toma foto con cámara.
- [ ] Pulsa "Usar GNSS" → coordenadas capturadas (lat/lng; alt si hay).
- [ ] Activa "Compartir a comunidad NEXUS".
- [ ] Guardar → snackbar "compartido con la comunidad".

### 5.2 Sync a otra cuenta

- [ ] B sincroniza → A sincroniza.
- [ ] A ve la nueva detección en Patologías → Detecciones activas con:
      - Thumbnail de la foto.
      - Chip de coordenadas.
      - Chip verde "compartida".
- [ ] A entra al detalle del cultivo → card "Patologías reportadas"
      muestra el mismo reporte.
- [ ] StatusDot del cultivo cambia de verde a naranja (inicial) o rojo
      (avanzada) según la severidad del reporte.

### 5.3 Curación

- [ ] A marca la patología como "Curada" desde su detalle.
- [ ] Sincroniza.
- [ ] B ve el StatusDot del cultivo en verde de nuevo.
- [ ] La **variedad del cultivo no cambia** en B tras curar/sync.

---

## Bloque 6 — Catálogo comunitario (Fases 3h/3i)

### 6.1 Auto-población al crear variedad (3h)

- [ ] En A, Plantas → Agregar variedad → nombre "Prueba Tomate",
      especie "Solanum lycopersicum".
- [ ] Ver tarjeta amarilla con patologías conocidas de esa especie.
- [ ] Guardar → snackbar indica cuántas patologías se auto-asociaron.
- [ ] La tarjeta de "Prueba Tomate" en Plantas muestra
      "🐛 N conocidas" en naranja.

### 6.2 Actualizar catálogo (3i-A + 3i-B + 3e-8)

- [ ] A pulsa "Actualizar" en Patologías.
- [ ] Snackbar verde con contadores: patologías locales + relaciones
      + EPPO (si hay token) + tratamientos.
- [ ] Catálogo agrupado muestra secciones con contadores.
- [ ] Sección "Otras" tiene pocas entradas (heurística de tipos
      funcionando).

### 6.3 Verificación EPPO en modal Variedad

- [ ] Nueva variedad → escribe "Coffea arabica" en especie.
- [ ] Aparece ✓ verde "Especie reconocida en EPPO Global DB".
- [ ] Escribe "Xyz nonsenseae" → warning naranja + botón Diagnóstico.

---

## Bloque 7 — Mapa con capas y heatmap (Fases 3e-6, 3e-7)

### 7.1 Capas de contenido

- [ ] Mapa → panel de capas visible (inferior derecha).
- [ ] "Cultivos del predio" activo → marcadores con color por estado.
- [ ] Activa "Todos mis cultivos" → aparecen marcadores azules de
      otros predios (si aplica).
- [ ] Activa "Heatmap patologías" → círculos naranja/rojo en cada
      reporte.

### 7.2 Fallback de coordenadas

- [ ] Crear un cultivo sin GNSS pero con lote asignado → el marcador
      aparece **dentro del polígono del lote**, no en offset random.
- [ ] Reportar patología en un cultivo sin GNSS del reporte → el
      punto del heatmap aparece en la coordenada del cultivo o del
      centroide del lote (nunca invisible).

### 7.3 Tap sobre zona caliente

- [ ] Toca cerca de un cluster de círculos → bottom sheet aparece con:
      "N reportes en esta zona".
- [ ] Lista ordenada por distancia con miniaturas, chips y botones
      🩺 tratamientos + 📍 centrar.
- [ ] Botón 📍 mueve el mapa a la ubicación del reporte.
- [ ] Botón 🩺 abre el diálogo de tratamientos filtrados por país.

---

## Bloque 8 — Tratamientos por país (Fase 3e-8)

### 8.1 Priorización local

- [ ] Con predio en Colombia (ISO2=CO), abre tratamientos de "Roya del
      café" desde el catálogo.
- [ ] Los tratamientos con `pais_iso2="CO"` aparecen **primero** con
      badge verde 🏳️ "Tratamiento local (CO)".
- [ ] Debajo, los globales (paisIso2=null).
- [ ] Ninguno de otro país en las primeras posiciones (si los hubiera).

### 8.2 Sostenibilidad primero

- [ ] Dentro del grupo cultural/biológico, los `sostenibilidad: alta`
      aparecen antes que `media` o `baja`.
- [ ] Chip 🌿 alta / ⚠ media / ⚗ baja visible en cada card.

---

## Bloque 9 — Diagnóstico técnico

Ejecutar el script `supabase/verificacion_e2e.sql` en el SQL Editor de
Supabase para confirmar el estado esperado. Cada bloque tiene comentarios
con lo que debería retornar.

Además:

- [ ] `schema_meta.version` ≥ 11.
- [ ] No hay cultivos "vivos" (`deleted_at IS NULL`) que B siga
      mostrando tras un soft-delete sincronizado desde A (ver 3.4).

---

## Bloque 10 — Eliminar cuenta (0.2.7)

Usar una **cuenta desechable** (no A/B de producción de pruebas).

### 10.0 Precondición técnica (Revisión C2-2, una sola vez por proyecto)

- [ ] Aplicar `supabase/migrations/0015_verificacion_fks_auth.sql` en el
      SQL Editor. Debe terminar SIN excepción (si corrigió FKs, muestra
      `NOTICE` por cada una).
- [ ] La consulta de auditoría del final del script lista todas las FKs
      hacia `auth.users` con acción `c` (CASCADE) o `n` (SET NULL) —
      ninguna otra letra.

### 10.1 Cuenta simple

- [ ] Cuenta → Eliminar cuenta → confirma (doble diálogo, muestra email).
- [ ] La sesión se cierra; no se puede volver a iniciar con esa
      contraseña (usuario Auth eliminado o deshabilitado según RPC).
- [ ] Datos privados del usuario desaparecen del remoto; variedades
      comunitarias aportadas y reportes de patología comunitarios se
      preservan / anonimizan según diseño de `eliminar_mi_cuenta`.
- [ ] Diálogo de wipe local: si se acepta, BD local queda limpia al
      reabrir.

### 10.2 Cuenta CON datos completos y colaboradores (Revisión C2-2)

Escenario máximo: es el que ejercita todos los CASCADE a la vez.

Preparación con cuenta desechable **D**:

- [ ] D crea un predio con: lote, cultivo con tareas registradas,
      compra con comprobante, ítem de inventario, análisis de suelo,
      condiciones del predio y un reporte de patología compartido.
- [ ] D comparte el predio con **B** (rol trabajador); B sincroniza y
      registra al menos 1 tarea en el cultivo de D (queda
      `created_by_user_id` de B en datos de D, y de D en ninguna parte
      de B).
- [ ] D aporta una variedad al banco comunitario.

Ejecución:

- [ ] D → Cuenta → Eliminar cuenta → confirmar los 2 diálogos.
- [ ] El resultado en pantalla reporta reportes anonimizados,
      variedades conservadas y predios con colaboradores (>0).
- [ ] **No aparece ningún error de FK** (`23503` en logs; ver Reportes →
      Logs). Si aparece, adjuntar log: significa que 10.0 no se ejecutó
      o hay una FK nueva sin acción.

Verificación cruzada en **B** (tras sincronizar):

- [ ] El predio de D desaparece para B (o queda "sin acceso"), sin
      romper el sync de B (`Sincronización OK`).
- [ ] Los datos propios de B están intactos.
- [ ] La variedad comunitaria de D sigue apareciendo en el
      autocompletado de "Nueva variedad" de B.
- [ ] El reporte comunitario de D sigue en el mapa/heatmap, ya sin
      autor.

Verificación en SQL (opcional, service_role):

```sql
-- 0 filas privadas huérfanas del usuario eliminado:
SELECT 'predios', count(*) FROM predios WHERE owner_id NOT IN (SELECT id FROM auth.users)
UNION ALL SELECT 'shares', count(*) FROM predio_shares WHERE owner_id NOT IN (SELECT id FROM auth.users);
-- Reportes anonimizados conservados:
SELECT count(*) FROM patologias_reportadas WHERE owner_id IS NULL AND deleted_at IS NULL;
```

---

## Criterios de aceptación general

Al terminar todos los bloques:

- [ ] Ambas cuentas ven la misma información sincronizada, con
      permisos correctos por rol.
- [ ] Ninguna acción de una cuenta afecta datos de otra sin permiso.
- [ ] Soft-delete de cultivo en A se refleja en B sin errores FK.
- [ ] Los reportes de patologías con GNSS son visibles en el mapa de
      ambas cuentas.
- [ ] Los tratamientos filtrados por país aparecen correctamente.
- [ ] No hay duplicados en ninguna tabla local ni remota.
- [ ] La sesión persiste tras hot restart en ambas cuentas.
- [ ] La variedad de un cultivo no cambia de identidad solo por sync.

**Firma del tester:** _____________________  **Fecha:** _____________

---

## Notas de desarrollo

Si alguna prueba falla, adjuntar:
1. Screenshot del error o del estado inconsistente.
2. Salida del script `verificacion_e2e.sql` para el bloque relevante.
3. Log exportado desde la app (`nexus_logs_*.txt`) filtrado por
   `[sync]` / FK / `23503`.
4. Commit o build number (`0.2.8` o superior con fix de tombstones).

### Cobertura automatizada relacionada

| Área | Archivo |
|------|---------|
| LWW / push / batch | `test/sync_policy_test.dart` |
| Merge cultivo + cola offline | `test/sync_service_test.dart` |
| Widgets base | `test/widgets/core_widgets_test.dart`, `test/widget_test.dart` |
