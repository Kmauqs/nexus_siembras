# Revisión de código C2 — Fase 3 finalizada
**Fecha:** 2026-08-03 · **Alcance:** estado actual v0.2.8 (Drift v20, `schema_meta` v11, migraciones 0007-0014), con foco en lo implementado después de la auditoría de 2026-07-19 y de la primera revisión de 2026-07-20.

## Veredicto general

La base está en buen estado para pasar a **pruebas por terceros**. Los controles de la auditoría original siguen vigentes y las funcionalidades nuevas (tombstones, eliminación de cuenta, proveedores compartidos, caché de variedades, tipo de ciclo de cultivo) mantienen el nivel: RLS con funciones `SECURITY DEFINER` de `search_path` fijo, RPC de borrado de cuenta con anonimización y `REVOKE PUBLIC`, política de sync extraída a módulo puro **con tests unitarios**, y cero `print()` en `lib/`.

## Verificado en verde ✅

| Control | Estado |
|---|---|
| Logging centralizado (0 `print`, buffer de diagnóstico) | ✅ |
| Contraseña mínima 8 en registro (2 pantallas) | ✅ |
| Pinning EPPO: hoja + intermedio Sectigo presentes | ✅ |
| Eliminación de cuenta: doble confirmación con email visible; RPC transaccional que anonimiza reportes públicos, borra los soft-deleted, limpia storage con tolerancia a fallos, `REVOKE ALL FROM PUBLIC` | ✅ |
| `schema_meta` con `GREATEST(version, N)` (no puede retroceder) y cliente exigiendo v11 | ✅ |
| `sync_policy.dart` puro + `tombstoneRemotoGana` (soft-delete inmune al skew de reloj) + tests (`sync_policy_test`, `sync_service_test`, widgets) | ✅ |
| Migración local v20 documenta y evita el bug de `ALTER TABLE` con default no constante | ✅ |
| Caché local del banco de variedades con upsert por id remoto y clave natural | ✅ |
| Gating por rol en pantallas de edición (muestreado: lotes, condiciones, análisis) | ✅ |

## Hallazgos y mejoras propuestas

### Media

**C2-1 · Privacidad: el directorio de proveedores se comparte completo.**
`0012_proveedores_compartidos.sql` — `puede_ver_proveedor` da a cualquier colaborador propietario/trabajador de *un* predio compartido visibilidad sobre **todos** los proveedores del dueño, incluidos los de predios no compartidos y los personales. Si el diseño es "directorio común del equipo", es válido, pero el dueño no lo sabe.
*Propuesta:* (a) restringir la policy a proveedores referenciados por compras de predios visibles para el solicitante, o (b) mantener el diseño actual pero avisarlo en la UI de colaboradores ("tus proveedores serán visibles para el equipo").

**C2-2 · Robustez: el CASCADE del borrado de cuenta depende de las FKs.**
`eliminar_mi_cuenta` hace `DELETE FROM auth.users` confiando en que **todas** las FKs hacia `auth.users` (predios.owner_id, predio_shares, compras.created_by_user_id…) tengan `ON DELETE CASCADE`/`SET NULL`. Si alguna quedó sin acción referencial, el DELETE falla y la función aborta (la transacción revierte — sin corrupción, pero la cuenta no se borra y el mensaje al usuario será críptico.
*Propuesta:* añadir al plan de pruebas E2E un caso "eliminar cuenta con datos completos + colaboradores", y ejecutar una verificación única en SQL: `SELECT conrelid::regclass, confdeltype FROM pg_constraint WHERE confrelid = 'auth.users'::regclass;` (todo debe ser `c` cascade o `n` set null).

**C2-3 · Consistencia: la caché de variedades sobrevive al borrado local.**
`AccountService.borrarDatosLocales()` limpia 19 tablas pero no `variedadesComunitariasCache`. Es contenido público (impacto de privacidad bajo), pero rompe la semántica de "reset total".
*Propuesta:* añadir `await db.delete(db.variedadesComunitariasCache).go();` a esa transacción (1 línea).

**C2-4 · Calidad: 40 `catch (_) {}` vacíos.**
La regla del proyecto (comentario justificando el silencio, o `Log.w`) se cumplió en sync, pero el conteo creció con las funcionalidades nuevas.
*Propuesta:* barrido de una sesión: los de flujos de datos (sync, adjuntos, storage) a `Log.w`; los legítimos (dispose, formatos opcionales) con comentario.

### Baja

**C2-5 · Rendimiento futuro: refresh completo del banco de variedades.**
`sincronizarEnLocal` descarga todo el banco en cada arranque con sesión. Hoy es trivial; con miles de filas comunitarias será tráfico y escrituras innecesarias. La tabla ya guarda `remoteUpdatedAt`.
*Propuesta:* filtro incremental `updated_at > max(remoteUpdatedAt) local` (mismo patrón del sync principal).

**C2-6 · Datos en reposo: el backup JSON queda en claro.**
Con la BD cifrada (SQLCipher), el export de respaldo a Documentos es ahora el artefacto más legible del dispositivo. Es un trade-off deliberado (portabilidad para usuarios locales), pero merece decisión explícita.
*Propuesta:* corto plazo, una línea en la UI de backup ("el archivo exportado no está cifrado — guárdalo en un lugar seguro"); mediano plazo, opción de cifrar el backup con contraseña.

**C2-7 · Dependencia beta en producción.**
`file_picker 12.0.0-beta` es la única línea compatible con el toolchain AGP 9. Funciona, pero es prerelease.
*Propuesta:* vigilar la salida de la 12 estable y fijarla apenas exista (cambio de una línea).

**C2-8 · Recordatorio operativo: pin de la hoja EPPO.**
El certificado hoja anclado (jul-2026) rotará en ~oct-2026. El intermedio Sectigo (2036) mantiene Android funcionando, así que no es urgente — pero el checklist del runbook (`RUNBOOK_PIN_EPPO.md`) debe entrar en la rutina de cada release.

### Para la etapa de pruebas por terceros

**C2-9 · Kit del tester.** Ya existen las piezas (logs compartibles en Reportes, backup JSON, `PRUEBAS_MULTI_USUARIO_E2E.md`); falta empaquetarlas: una guía de 1 página para testers (qué probar, cómo reportar, cómo adjuntar logs y versión — visible en el menú), y decidir el canal de recepción de feedback. Sugerencia de recorridos mínimos: onboarding+asistente completo, ciclo cultivo→tarea→cosecha, compra con comprobante, colaborador trabajador/consultor en 2 dispositivos, borrado de cuenta, restauración de backup.

## Nota final

Ningún hallazgo es bloqueante para iniciar las pruebas por terceros. C2-2 y C2-3 son las de mejor relación esfuerzo/beneficio para cerrar antes de distribuir builds.
