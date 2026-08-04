# Backlog de tareas pendientes — NEXUS Siembras
**Actualizado:** 2026-08-02

## A. Operativos inmediatos (no requieren código)

| # | Tarea | Origen |
|---|-------|--------|
| A1 | Supabase → Authentication → Settings: longitud mínima de contraseña **8** y activar *Leaked password protection* | Auditoría S7 (paso manual 5, sin confirmar) |
| ~~A2~~ | ~~Borrar el respaldo sin cifrar `nexus_siembras.sqlite.pre-cifrado.bak` (Documentos de la app) tras verificar que los datos están intactos~~ | Auditoría S4 (paso manual 7, sin confirmar) |
| ~~A3~~ | ~~Probar en Windows **y** Android lo entregado en 3j/3k: comprobante de compra (PDF/foto y carpeta `soportes/{año}/`), exports CSV/PDF de las 5 pantallas, reporte integral del Dashboard (verificar gráfico circular en el PDF), PDF de laboratorio en análisis de suelo, y el Asistente paso a paso completo (incluida la oferta tras un onboarding nuevo)~~ | Fases 3j/3k recién implementadas |
| A4 | Re-ejecutar el plan E2E multi-usuario (`docs/PRUEBAS_MULTI_USUARIO_E2E.md`) — incluye §3.4 soft-delete/tombstone cultivo y schema_meta ≥ 11 | Auditoría P1-P5 + regresión 2026-08-02 |

## B. Desarrollo — funcionalidad pendiente

| # | Tarea | Notas |
|---|-------|-------|
| ~~B1~~ | ~~Banco comunitario de variedades~~ — **COMPLETADO 2026-07-20** (migración `0008`, `VariedadesComunitariasService`, sugerencias + opt-in en el modal). Pendiente operativo: aplicar `0008_banco_variedades.sql` en el dashboard de Supabase | ✔ |
| B2 | **Web de consulta y reportes** (solo lectura): migrar BD web a `drift_wasm` (WasmDatabase + IndexedDB) y adaptar servicios con `dart:io` para descarga de archivos | Pospuesta por decisión 2026-07-20 |
| B3 | **Modelo freemium** (visión del proyecto): gating versión gratuita (alertas y patologías) vs completa. De la versión completa faltan por construir: **presupuestos**, **pronósticos climáticos**, **informes de rendimiento por cosecha** y **control de costos consolidado** (hoy existen HH y compras por separado) | Instrucciones del proyecto |
| B4 | **Infraestructura COMPLETADA 2026-07-20** (`AppLocalizations`: carga ARB en runtime, delegate, fallback a es, `context.t()`; 115 claves con paridad es/en/pt; menú y AppShell migrados). **Queda pendiente incremental**: migrar los literales de las ~30 pantallas restantes (~700 strings) siguiendo `docs/GUIA_I18N.md`. Sin migrar, esas pantallas siguen en español sin errores | Fase 2f — ver guía |
| ~~B5~~ | ~~Cola persistente de sincronización~~ — **COMPLETADO 2026-07-20** (tabla `sync_ops` Drift v14; deletes remotos offline encolados y procesados al inicio de cada sync). Requiere `dart run build_runner build --delete-conflicting-outputs` | ✔ |
| B6 | Importador del Excel histórico (`tool/import_excel.dart`): migrar `2026-Control Siembras.xlsx` (plantas, proveedores, compras, inventario) a la BD | TODO Fase 2b |
| ~~B7~~ | ~~Tratamientos por país~~ — **COMPLETADO 2026-07-20**: catálogo de 51 → **214 tratamientos**, 19 países LATAM, 95% sostenibilidad alta (123 culturales / 64 biológicos / 22 orgánicos / 5 químicos). Pendiente operativo: pulsar "Actualizar" en la pantalla Patologías de cada dispositivo para cargar el asset (merge idempotente) | ✔ |
| ~~B8~~ | ~~Mostrar/abrir adjuntos~~ — **COMPLETADO 2026-07-20**, ampliado con pantalla Reportes (generación + consolidado + listado con ver/compartir/eliminar + logo personalizado + logs de diagnóstico). Requiere `flutter pub get` (nueva dependencia `share_plus`) | ✔ |

## C. Calidad y mantenimiento

| # | Tarea | Notas |
|---|-------|-------|
| C1 | Limpieza de `flutter analyze`: ~90 infos + 12 warnings preexistentes (`withOpacity`→`withValues`, `value`→`initialValue`, `prefer_const`, unused) | Cosmético, ~30 archivos |
| ~~C2~~ | ~~Segunda revisión de código formal~~ — **COMPLETADA 2026-08-03** (`docs/REVISION_CODIGO_C2_2026-08-03.md`): 9 controles en verde, 0 hallazgos bloqueantes, 9 mejoras propuestas (C2-1…C2-9). C2-3 aplicada en el acto | ✔ |
| C2-1 | Privacidad proveedores compartidos: restringir policy a proveedores usados en predios visibles, o avisar en la UI que el directorio completo se comparte con el equipo | Revisión C2 · media |
| ~~C2-2~~ | ~~Verificar FKs a auth.users + caso E2E~~ — **COMPLETADO 2026-08-03**: migración `0015_verificacion_fks_auth.sql` (autocorrectiva, con verificación final que aborta si queda una FK sin acción) + Bloque 10 del plan E2E ampliado (10.0 precondición, 10.2 cuenta con colaboradores y verificación cruzada). Pendiente operativo: ejecutar 0015 en el dashboard | ✔ |
| C2-4 | Barrido de 40 `catch (_) {}`: log en flujos de datos, comentario en los legítimos | Revisión C2 · media |
| C2-5 | Refresh incremental de la caché de variedades (`updated_at > max local`) | Revisión C2 · baja |
| C2-6 | Aviso "backup sin cifrar" en la UI; a futuro, backup con contraseña | Revisión C2 · baja |
| C2-7 | Fijar `file_picker` 12 estable cuando salga (hoy beta) | Revisión C2 · baja |
| ~~C2-8~~ | ~~Rotación del pin EPPO~~ — **COMPLETADO 2026-08-03**: `pinHojaCapturadoEl` + `pinHojaProntoAVencer()` (umbral 75 días) y aviso ámbar en la card EPPO de Configuración con enlace al runbook. Al rotar el pin, actualizar también esa fecha | ✔ |
| ~~C2-9~~ | ~~Canal de feedback~~ — **COMPLETADO 2026-08-03**: micro-encuestas offline-first (Drift v21 `feedback_encuestas` + `FeedbackService` + pantalla `/feedback` + hoja modal contextual + envío tras auto-sync) y migración `0016` con `feedback_encuestas` (RLS insert-only) y `feedback_config.email_notificacion` editable. Documentación de la gestión web y del email en `docs/FEEDBACK_ENCUESTAS.md`. Pendiente operativo: aplicar 0016 | ✔ |
| C2-9b | Guía de 1 página para testers (qué probar / cómo reportar) — el canal ya existe; falta el documento de bienvenida | Revisión C2 · pruebas |
| ~~C2-9c~~ | ~~Gestión web~~ — **COMPLETADO 2026-08-04**: backoffice Next.js en `../nexus_backoffice` (landing pública + panel con usuarios, datos, feedback y configuración). Migración `0017`. Pendiente: Edge Function `notify-feedback` para el correo automático | ✔ |
| W1 | Edge Function `notify-feedback` + Database Webhook ON INSERT → email al desarrollador (código listo en `docs/FEEDBACK_ENCUESTAS.md` §3.3) | Backoffice · media |
| W2 | Paginación server-side en `/admin/usuarios` y `/admin/datos` cuando superen ~1000 filas | Backoffice · baja |
| W3 | Vista de detalle por usuario (predios, lotes y cultivos individuales) en el backoffice | Backoffice · baja |
| ~~C3~~ | ~~Ampliar tests: SyncService (mergers/LWW/batch) + widgets~~ — **COMPLETADO 2026-08-02**: `sync_policy.dart` + `test/sync_policy_test.dart`, `test/sync_service_test.dart` (merge/tombstone/cola), `test/widgets/core_widgets_test.dart`; `AppDatabase.forTesting` | ✔ |
| ~~C4~~ | ~~Renovación del pin TLS de EPPO cuando rote el certificado (síntoma: Android falla, Windows no; correr `dart run tool/eppo_fingerprint.dart`)~~ **COMPLETADO 2026-07-20** | Recurrente, documentado |
| C5 | Nueva migración remota ⇒ nuevo archivo en `supabase/migrations/` + subir `schema_meta.version` y `schemaRemotoRequerido` | Regla permanente S6 |

## D. Publicación y distribución

| # | Tarea | Notas |
|---|-------|-------|
| ~~D1~~ | ~~Instalador Windows con Inno Setup + subir `version:` en pubspec por release~~ **COMPLETADO 2026-07-25** (fix runtime `InitializeSetup` 2026-08-02: validar Release solo en compilación) | Guía según instrucciones del 2026-07-20 |
| D2 | Android release: keystore de firma propio, `flutter build appbundle`, y eventualmente Play Store (política de datos, privacidad) | Hoy se usa firma debug |
| D3 | Branding definitivo: fuentes NexusSans (comentadas en pubspec), íconos por plataforma, borrar `flutter_01.png` (0 bytes) y `schema_3e_v*.sql` obsoletos al consolidar | — |

## Sugerencia de orden

1. **A1** y **A4** (auth settings + E2E actualizado con §3.4 tombstones).
2. **D2** cuando haya usuarios reales esperando instalar.
3. B3 (freemium) cuando el producto esté estable — define el modelo de negocio.
4. B4 / B6 de forma incremental.
