# Parches de auditoría aplicados — 2026-07-19

Implementación completa de los hallazgos de `AUDITORIA_SEGURIDAD_RENDIMIENTO_2026-07-19.md`, en las 4 fases propuestas.

## Fase 1
| ID | Cambio | Archivos |
|----|--------|----------|
| S1 | `.env` y `*.env.local` excluidos de git | `.gitignore` |
| P4 | Cursor de pull avanza con `max(updated_at)` del **servidor**, nunca con el reloj local | `sync_service.dart` (`_pullTable`) |
| P6 | Guard de reentrada en auto-sync y en `sincronizar()`; eliminado `contarPendientes()` desperdiciado en cada cambio de red | `auto_sync_service.dart`, `sync_service.dart` |

## Fase 2
| ID | Cambio | Archivos |
|----|--------|----------|
| S2 | Certificate pinning SHA-256 para `api.eppo.int`. **La lista de pins está vacía** → por defecto ahora se RECHAZA el certificado no validable (seguro) y el fingerprint observado se registra en el log. Generar el pin con `dart run tool/eppo_fingerprint.dart` (desde red de confianza) y pegarlo en `_eppoPins` | `eppo_client.dart`, `tool/eppo_fingerprint.dart` (nuevo) |
| P1 | Eliminado el patrón N+1: `_mappingsDe()` carga los mappings de cada tabla en 1 consulta; catálogos y cultivos precargados; caché de permisos por predio | `sync_service.dart` |
| P3 | Pull paginado (500 filas/página, `order` + `range`) — antes PostgREST truncaba a 1000 filas en silencio | `sync_service.dart` |
| P7 | Logger central sin dependencia externa (`lib/core/log.dart`), 0 `print()` en `lib/`, contador `errores` en `SyncResult`, filas fallidas ya no se descartan en silencio | `core/log.dart` (nuevo), `sync_service.dart` y servicios |

## Fase 3
| ID | Cambio | Archivos |
|----|--------|----------|
| P2 | Push por lotes (`_pushBatch`, chunks de 200): nuevas por `(owner_id, cliente_id)`, existentes por PK; si un chunk falla se reintenta fila a fila para aislar filas rechazadas por RLS | `sync_service.dart` |
| P5 | Trigger `cap_updated_at`: `updated_at := LEAST(valor_cliente, now())` en las 10 tablas sincronizables — un reloj adelantado ya no puede machacar a los demás. Se usa LEAST (no `now()` puro) para no crear re-push infinito en clientes con reloj atrasado | `supabase/migrations/0007_…sql` (nuevo) |
| S6 | Tabla `schema_meta` + verificación en el cliente antes de cada sync (`schemaRemotoRequerido = 7`). Si la tabla no existe todavía solo advierte; si la versión es menor, bloquea con mensaje claro. Directorio `supabase/migrations/` como fuente canónica con README de orden de aplicación | `supabase/migrations/` (nuevo), `sync_service.dart` |
| S3 | Cubierto vía S4: el token EPPO sigue en `configs`, pero esa tabla ahora vive dentro de la BD **cifrada**; la clave de cifrado va en Keystore/Keychain/DPAPI (`SecureStore`) | `secure_store.dart` (nuevo) |

## Fase 4
| ID | Cambio | Archivos |
|----|--------|----------|
| S4 | BD local cifrada con SQLCipher. Migración automática y única de BD preexistente (`sqlcipher_export`); deja respaldo `nexus_siembras.sqlite.pre-cifrado.bak` | `db_connection_native.dart`, `pubspec.yaml` |
| S5 | Fotos de patologías re-encodificadas a JPEG antes de guardarse → se eliminan metadatos EXIF/GPS del predio (con `bakeOrientation` para no perder la rotación). Fallback a copia directa si el decode falla | `patologia_foto_service.dart` |
| P8 | `runApp` inmediato; Supabase y notificaciones se inicializan tras el primer frame. `supabaseReadyProvider` (nuevo, reactivo) notifica a los providers de auth al terminar — antes `supabaseInitProvider` quedaba congelado al valor del arranque | `main.dart`, `auth_state.dart` |
| S7 | Contraseña mínima 8 caracteres en registro (onboarding y pantalla de auth) | `onboarding_screen.dart`, `auth_screen.dart` |

Extra: `test/widget_test.dart` referenciaba `MyApp` (clase inexistente — rompía `flutter test`); reemplazado por tests unitarios de `inferirTipoTaxonomico`.

## Dependencias (pubspec)
Añadidas: `crypto`, `flutter_secure_storage`, `image`, `sqlite3`, `sqlcipher_flutter_libs`.
Eliminada: `sqlite3_flutter_libs` (reemplazada por la variante SQLCipher — no deben coexistir).

---

## PASOS MANUALES PENDIENTES (en orden)

1. **`flutter pub get`** — resuelve las dependencias nuevas.
2. **Compilar y probar en Windows primero** (`flutter run -d windows`). Verificar en el log: `[db] Migración a BD cifrada completada`. Si SQLCipher no carga en Windows, el error será explícito ("SQLCipher no disponible"); en ese caso revisar el nombre de la librería en `db_connection_native.dart` (`sqlcipher.dll`).
3. **Aplicar la migración SQL**: dashboard Supabase → SQL Editor → ejecutar `supabase/migrations/0007_schema_meta_y_triggers_updated_at.sql`. Verificar: `SELECT version FROM schema_meta;` → 7.
4. **Pin EPPO**: con internet y desde red de confianza, `dart run tool/eppo_fingerprint.dart` y pegar el SHA-256 en `_eppoPins` (`lib/services/eppo_client.dart`). Hasta entonces, la conexión a EPPO fallará de forma segura si Dart no valida la cadena por sí mismo.
5. **Dashboard Supabase → Authentication → Settings**: longitud mínima de contraseña 8 y activar *Leaked password protection*.
6. **Dashboard Supabase → Settings → API**: deshabilitar/rotar las *Legacy API keys* (JWT) y usar la publishable key en `.env`.
7. Tras verificar que la app abre bien con datos: **eliminar** `nexus_siembras.sqlite.pre-cifrado.bak` del directorio de documentos de la app (es la copia sin cifrar).
8. `flutter analyze` y `flutter test`, y prueba E2E de sync entre dos usuarios (el flujo de colaboradores es el más sensible a estos cambios).

## Correcciones post-integración (mismo día)

1. **Bug "Comenzar no hace nada" (onboarding, paso Comunidad NEXUS).** Causa raíz: en Windows/Linux el plugin SQLCipher empaqueta la librería con el nombre estándar (`sqlite3.dll`/`libsqlite3.so`); el override que intentaba abrir `sqlcipher.dll` (inexistente) rompía la apertura de la BD y todas las escrituras fallaban en silencio. Corregido: override solo en Android; además `_finish()` ahora captura errores y los muestra en pantalla, y `_next()` no toca `Supabase.instance` si la init diferida no terminó.
2. **Mejora: botón "Verificar estado del servicio"** en el paso del token EPPO del onboarding (GET `https://api.eppo.int/gd/v2/status` vía `EppoClient.checkStatus()`), con resultado inline. No requiere token; distingue "API caído / sin internet" de "token inválido". Nota: hasta que se configure el pin S2, la conexión puede fallar con el mensaje de certificado rechazado — es el comportamiento seguro esperado.

3. **Bug Android "Failed to load dynamic library libsqlite3.so" (2026-07-20).** `NativeDatabase.createInBackground` abre la BD en un isolate separado y los `open.overrideFor` son por-isolate: el override de SQLCipher aplicado en el isolate principal no llegaba al isolate de la BD, que intentaba cargar el `libsqlite3.so` por defecto (inexistente tras quitar `sqlite3_flutter_libs`). Corregido con el parámetro `isolateSetup` de drift, que ejecuta el override dentro del isolate de la BD. Windows no se veía afectado porque allí la librería del plugin usa el nombre por defecto.

## Notas de comportamiento

- Primer sync tras actualizar: los cursores existentes se conservan; el pull puede re-procesar algunas filas del pasado reciente (los mergers son idempotentes por LWW).
- Si un lote del push falla completo (p. ej. una fila con RLS denegado), el log mostrará `batch … falló, reintento fila a fila` — es el fallback esperado, no un error fatal.
- `SyncResult.errores > 0` con `exito == true` significa: sync terminó, pero hay filas individuales sin sincronizar — revisar el log.
