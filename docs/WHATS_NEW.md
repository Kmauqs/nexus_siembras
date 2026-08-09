# NEXUS Siembras — Notas de versión (What's new)

Texto listo para Play Store / comunicación de release.  
**Última generación:** 2026-08-09 · **Versión:** 0.3.0  
**Versión anterior documentada:** 0.2.8 (2026-08-03)

---

## Novedades (What's new) — v0.3.0

### Sitio web y panel de gestión

**Web pública y backoffice:** sitio en Netlify con estadísticas del proyecto (usuarios, predios, mapa de calor de patologías) y panel de administración: usuarios, papelera, datos comunitarios, bandeja de feedback y configuración.

**Acceso sin contraseña:** el panel usa el enlace mágico por email de Supabase (compatible con el plan gratuito; no hace falta código de 6 dígitos).

**Papelera de usuarios:** suspender cuentas con opción de recuperar o borrar de forma definitiva (patrimonio comunitario protegido).

**Feedback de testers:** micro-encuestas en la app y bandeja web con filtros, notas, marcado masivo y export CSV. Guía corta para testers incluida.

### Compras entre co-propietarios

**Comprobantes en la nube:** los PDF/fotos de soporte de compras se sincronizan por Supabase Storage. El **ZIP completo** incluye los adjuntos de todas las cuentas con rol Propietario del predio, no solo los guardados en el dispositivo local.

### Comunidad y privacidad

**Patrimonio comunitario:** al eliminar una cuenta se conservan variedades aportadas y reportes de patologías (anonimizados). Los focos pueden pasar a «desatendidos» tras inactividad y reactivarse.

**Más seguro en el panel:** escrituras administrativas validadas con rol admin en la base; emails reales del administrador no van en el repositorio (configuración manual).

### App

**Reset local más limpio:** al borrar datos locales también se vacía la cola de feedback pendiente.

**Identidad visual en la web:** logotipo de la app en cabecera, login y panel (en lugar del emoji).

---

## Novedades (What's new) — v0.2.8

**Sync de cultivos borrados:** si eliminas un cultivo en un dispositivo, al sincronizar desaparece en los demás (sin errores de eventos huérfanos). Vaciar la papelera marca borrado en la nube en lugar de borrar la fila a ciegas.

**Dashboard en Windows:** los recuadros de Cultivos, Alertas, Próximas cosechas e Inventario muestran una muestra de elementos; Alertas próximas abre el cultivo; Compras año fiscal abre Compras.

**Cronograma en detalle de cultivo:** toca el círculo de una actividad pendiente para abrir «Registrar tarea» ya precargada con fecha y actividad.

**Instalador Windows:** el setup ya no exige la carpeta de compilación Flutter en el PC del usuario (validación solo al generar el instalador).

---

## Novedades (What's new) — v0.2.7

**Navegación a una mano:** botón **Volver** además de Inicio; el atrás del sistema ya no sale de la app por error. Volver, Inicio y Sincronizar viven abajo (zona del pulgar); el título queda completo a la izquierda y el menú ☰ a la derecha.

**GPS con altitud:** al pulsar obtener coordenadas se rellenan latitud, longitud y altitud en predios, lotes, cultivos, onboarding y patologías (con aviso si el sensor no entrega altitud).

**Cronograma y pantallas:** el calendario ya no se desborda cuando un día tiene muchas actividades; se corrigen desbordes en Proveedores, Reportes e Inventario.

**Patologías en el cronograma:** reportar, intervenir o marcar curada crea eventos visibles en Gantt, Calendario y Actividades.

**Sync de variedades:** corrige el caso en que un cultivo sincronizado mostraba otra planta (p. ej. Tomate → Yuca) entre dispositivos.

**Eliminar cuenta:** en Cuenta / Sincronización puedes borrar tu cuenta y tus datos privados en la nube. Se conservan en la comunidad las variedades aportadas y los reportes de patologías (anonimizados). Después eliges si eliminar o conservar los datos locales del dispositivo.

---

## Novedades (What's new) — v0.2.6

**Sync entre colaboradores (correcciones):** si el dueño borra un cultivo o registra una patología en un predio compartido, el cambio llega al co-propietario o trabajador tras sincronizar. Las detecciones de patología por cultivo viajan por la nube entre cuentas del mismo predio.

**Estabilidad al arrancar:** corrige un error de base de datos local («Cannot add a column with non-constant default») que podía bloquear el onboarding tras actualizar o reinstalar la app en Android.

**Sync más fiable:** la app verifica que los cambios realmente se escribieron en la nube antes de marcarlos como sincronizados, evitando pérdidas silenciosas cuando un permiso remoto bloquea la operación.

---

## Novedades (What's new) — v0.2.5

### Colaboradores y sincronización

**Co-propietarios:** lo que crea un colaborador con rol propietario (cultivos, tareas, eventos, inventario) se sincroniza con el dueño del predio y viceversa.

**Proveedores compartidos:** el listado de proveedores es común para propietario y trabajadores del mismo predio compartido.

**Descarga completa de predios compartidos:** al unirte a un predio ajeno, la app descarga de forma fiable condiciones, suelo, lotes, cultivos, inventario, compras (co-propietarios), eventos y tareas — incluso si el primer intento falló por red o el acceso se recuperó después.

**Compras entre co-propietarios:** cada compra muestra quién la registró («Registrada por: …»).

### Variedades y cultivos

**Variedades de la comunidad:** sincroniza un banco comunitario desde la nube, úsalo al crear variedades o cultivos, y copia al catálogo propio con un toque.

**Listado unificado:** propias + comunitarias en Agregar cultivo, el asistente y los autocompletados del modal Nueva variedad.

**Tiempos más legibles:** en variedades, cultivos y tareas puedes ingresar duraciones en días, semanas, meses o años; la app convierte y guarda todo en días.

### Patologías

**Reclasificación manual:** mueve una patología al grupo correcto (hongos, plagas, deficiencias, etc.) cuando la clasificación automática no acierta; tu elección se conserva al actualizar el catálogo.

### Compras y reportes

**Paquete ZIP completo:** exporta PDF extendido, CSV detallado y carpeta `comprobantes/` con todos los adjuntos, listo para compartir.

**Reportes PDF de compras:** columnas Cant./Und., sin columna Comprobante en el resumen; Fecha y Valor más legibles.

### Onboarding y estabilidad

**Onboarding Android:** corrige errores de base de datos cifrada tras reinstalar; el paso de ubicación se puede omitir.

Sigue funcionando **offline** con base de datos cifrada; sincroniza con la nube si tienes cuenta.

---

## Cambios y correcciones acumulados (post v0.2.2)

Resumen técnico-usuario de mejoras incluidas desde 0.2.5 hasta 0.3.0:

| Área | Qué se corrigió o mejoró |
|------|--------------------------|
| **Web / backoffice (0.3.0)** | Next.js en Netlify: sitio público + panel admin; magic link; papelera de usuarios; feedback; logo de la app. |
| **Compras sync (0.3.0)** | Bucket `compras-soportes` + metadatos; ZIP con comprobantes de todos los Propietario. |
| **Patrimonio (0.3.0)** | Migraciones 0018–0021; estado desatendida; RLS admin; Edge Function `notify-feedback` (código). |
| **Sync tombstones (0.2.8)** | Soft-delete remoto al vaciar papelera; verificación post-pull de cultivos ausentes/borrados; no push de hijos de cultivo borrado (evita FK 23503). |
| **Dashboard Windows (0.2.8)** | KPI con muestra de ítems; navegación alerta→cultivo y compras→pantalla Compras. |
| **Cronograma (0.2.8)** | Círculos pendientes abren Registrar tarea precargada. |
| **Instalador (0.2.8)** | Validación Release en compilación Inno Setup, no en runtime del setup. |
| **Navegación (0.2.7)** | Pila con `push` (`AppNav`); Volver + Inicio + Sync en barra inferior; título AppBar a la izquierda; PopScope evita salir al escritorio fuera de Inicio. |
| **GPS (0.2.7)** | Helper `capturarGps()` unificado; rellena lat/lng/altitud y refina altitud vía stream si el primer fix no la trae. |
| **UI (0.2.7)** | Overflows en Proveedores/Reportes/Inventario; celdas del calendario con recorte dinámico de chips. |
| **Sync multi-usuario** | Propagación de cambios de rol; políticas remotas; reconciliación; «Resincronizar todo»; Gantt del colaborador; permisos de UI; soft-delete y patologías por cultivo. |
| **Predios compartidos** | Backfill e hidratación; proveedores del equipo; co-propietarios sin shares invertidos. |
| **Cultivos** | Variedades stub al bajar; resolución de planta por nombre (no por ID local); eventos al registrar tareas; patologías → eventos de cronograma. |
| **Cola offline** | Borrados en la papelera se encolan y suben cuando vuelve la conexión. |
| **Seguridad** | BD local cifrada (SQLCipher); fotos comunitarias sin EXIF/GPS; reportes comunitarios solo vía vista anonimizada. |
| **Cuenta (0.2.7)** | Eliminar cuenta: RPC `eliminar_mi_cuenta`; borra datos privados y Auth; conserva variedades comunitarias y anonimiza patologías compartidas; opción de borrar o conservar datos locales. |
| **Exportaciones** | Reporte integral, CSV/PDF, adjuntos y ZIP de compras. |
| **Asistente** | Guía de 10 pasos; mismo AppShell/navegación inferior. |
| **Migraciones Supabase** | `0011`–`0021` (compras, proveedores, patologías, cuenta, feedback, backoffice, patrimonio, papelera, RLS admin, soportes Storage). |

---

## Referencia — v0.2.2

**Cultivos más flexibles:** define variedades como **ciclo único** o **perenne**, con periodos de cosecha y ciclos de abono personalizables. Al crear un cultivo, los datos se precargan desde la variedad.

**Cronograma inteligente:** si registras una tarea en otra fecha, los eventos pendientes se ajustan solos. En cultivos perennes puedes registrar **cosechas periódicas** y **renovación**.

**Mapa mejorado:** brújula con norte arriba y seguimiento GPS en tiempo real para orientarte en el predio.

---

## Descripción corta sugerida (Play Store, ≤80 caracteres)

Control agropecuario offline: cultivos, compras con comprobantes, mapa y reportes.
