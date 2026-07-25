# Backlog de tareas pendientes — NEXUS Siembras
**Actualizado:** 2026-07-20

## A. Operativos inmediatos (no requieren código)

| # | Tarea | Origen |
|---|-------|--------|
| A1 | Supabase → Authentication → Settings: longitud mínima de contraseña **8** y activar *Leaked password protection* | Auditoría S7 (paso manual 5, sin confirmar) |
| A2 | Borrar el respaldo sin cifrar `nexus_siembras.sqlite.pre-cifrado.bak` (Documentos de la app) tras verificar que los datos están intactos | Auditoría S4 (paso manual 7, sin confirmar) |
| A3 | Probar en Windows **y** Android lo entregado en 3j/3k: comprobante de compra (PDF/foto y carpeta `soportes/{año}/`), exports CSV/PDF de las 5 pantallas, reporte integral del Dashboard (verificar gráfico circular en el PDF), PDF de laboratorio en análisis de suelo, y el Asistente paso a paso completo (incluida la oferta tras un onboarding nuevo) | Fases 3j/3k recién implementadas |
| A4 | Re-ejecutar el plan E2E multi-usuario (`docs/PRUEBAS_MULTI_USUario_E2E.md`) — el sync cambió a lotes/paginado y conviene revalidar colaboradores con `schema_meta` v7 aplicado | Auditoría P1-P5 |

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
| C2 | Revisión de código formal (code-review) de lo implementado en 3j/3k | Ofrecida |
| C3 | Ampliar tests: hoy solo 3 unitarios; faltan tests de widgets y del SyncService (mergers, LWW, batch) | — |
| C4 | Renovación del pin TLS de EPPO cuando rote el certificado (síntoma: Android falla, Windows no; correr `dart run tool/eppo_fingerprint.dart`) | Recurrente, documentado |
| C5 | Nueva migración remota ⇒ nuevo archivo en `supabase/migrations/` + subir `schema_meta.version` y `schemaRemotoRequerido` | Regla permanente S6 |

## D. Publicación y distribución

| # | Tarea | Notas |
|---|-------|-------|
| D1 | Instalador Windows con Inno Setup + subir `version:` en pubspec por release | Guía en conversación 2026-07-20 |
| D2 | Android release: keystore de firma propio, `flutter build appbundle`, y eventualmente Play Store (política de datos, privacidad) | Hoy se usa firma debug |
| D3 | Branding definitivo: fuentes NexusSans (comentadas en pubspec), íconos por plataforma, borrar `flutter_01.png` (0 bytes) y `schema_3e_v*.sql` obsoletos al consolidar | — |

## Sugerencia de orden

1. **A1-A3** (minutos, cierran la auditoría y validan lo nuevo).
2. **A4** (media jornada, asegura el multi-usuario).
3. **B1** (banco comunitario — siguiente fase de producto).
4. **D1-D2** cuando haya usuarios reales esperando instalar.
5. B3 (freemium) cuando el producto esté estable — define el modelo de negocio.
