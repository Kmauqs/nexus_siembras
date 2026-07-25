# NEXUS Siembras — Pruebas end-to-end multi-usuario (Fase 3e-9)

Plan de verificación completa del ciclo multi-usuario introducido en las
fases 3e-1 hasta 3e-8. Ejecutar en orden con **dos cuentas Supabase**:

- **Cuenta A** — propietario del predio (rol autoritativo).
- **Cuenta B** — colaborador (rol trabajador por defecto).

Se recomienda usar dos dispositivos (o dispositivo + navegador) para
observar la propagación en tiempo real.

---

## Precondiciones

- [ ] Ambas cuentas están creadas en Supabase Auth y tienen sus emails
      verificados.
- [ ] La app está compilada con la última versión (`flutter build apk`
      + `dart run build_runner build --delete-conflicting-outputs`).
- [ ] En Supabase ejecutados en orden todos los `schema*.sql`:
      base → 3e → 3e_v2 → 3e_v3 → 3e_v4 → 3g.
- [ ] Ambas cuentas tienen `consentimientoPatologias = true` (Settings
      → Comunidad NEXUS) para poder probar la contribución opt-in.
- [ ] Al menos una cuenta tiene el token EPPO configurado (Settings →
      EPPO Global Database) para probar el enriquecimiento remoto.

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

- [ ] A crea cultivo "Frijol Cargamanto" con GNSS capturado.
- [ ] A sincroniza → B sincroniza.
- [ ] B ve el cultivo con el mismo GNSS y ubicación en el mapa.
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
- [ ] Pulsa "Usar GNSS" → coordenadas capturadas.
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

---

## Criterios de aceptación general

Al terminar todos los bloques:

- [ ] Ambas cuentas ven la misma información sincronizada, con
      permisos correctos por rol.
- [ ] Ninguna acción de una cuenta afecta datos de otra sin permiso.
- [ ] Los reportes de patologías con GNSS son visibles en el mapa de
      ambas cuentas.
- [ ] Los tratamientos filtrados por país aparecen correctamente.
- [ ] No hay duplicados en ninguna tabla local ni remota.
- [ ] La sesión persiste tras hot restart en ambas cuentas.

**Firma del tester:** _____________________  **Fecha:** _____________

---

## Notas de desarrollo

Si alguna prueba falla, adjuntar:
1. Screenshot del error o del estado inconsistente.
2. Salida del script `verificacion_e2e.sql` para el bloque relevante.
3. Log de `flutter run` filtrado por prefijos relevantes.
