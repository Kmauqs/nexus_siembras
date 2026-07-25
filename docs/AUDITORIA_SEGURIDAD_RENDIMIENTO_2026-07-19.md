# Auditoría de código — NEXUS Siembras
**Fecha:** 2026-07-19 · **Alcance:** `APP_NEXUS_SIEMBRAS/nexus_siembras` (Flutter + Drift + Supabase)

## Resumen ejecutivo

| ID | Severidad | Área | Hallazgo |
|----|-----------|------|----------|
| S1 | 🔴 Crítica | Secretos | `.env` con credenciales reales empaquetado como asset y sin excluir de control de versiones; `Subabase CONFIG.txt` con claves en carpeta OneDrive |
| S2 | 🔴 Alta | Red/TLS | `badCertificateCallback` acepta **cualquier** certificado para `api.eppo.int` → vulnerable a MITM |
| S3 | 🟠 Media | Secretos | Token EPPO guardado en texto plano en SQLite (`configs.eppo_token`) |
| S4 | 🟠 Media | Datos locales | Base SQLite sin cifrar en el directorio de documentos |
| S5 | 🟠 Media | Privacidad | Bucket `patologias` público; fotos pueden conservar EXIF/GPS del predio |
| S6 | 🟠 Media | RLS | Esquema RLS fragmentado en 7+ archivos SQL; el cliente tiene ramas "por si el servidor no tiene el fix aplicado" |
| S7 | 🟡 Baja | Auth | Contraseña mínima de 6 caracteres, sin protecciones adicionales |
| P1 | 🔴 Alta | Rendimiento | Patrón N+1 masivo en sync: consulta a `sync_mappings` por cada fila |
| P2 | 🔴 Alta | Rendimiento | Push fila-por-fila: 1 petición HTTP por registro |
| P3 | 🔴 Alta | Estabilidad | `_pullTable` sin paginación ni orden → timeouts/memoria en primer sync |
| P4 | 🔴 Alta | Integridad | `lastPulledAt = DateTime.now()` del cliente → pérdida de cambios por desfase de reloj |
| P5 | 🟠 Media | Integridad | Last-write-wins con `updated_at` del reloj del cliente |
| P6 | 🟠 Media | Rendimiento | Auto-sync ejecuta `contarPendientes()` (muy costoso) en cada cambio de red y descarta el resultado; posible sync doble concurrente |
| P7 | 🟠 Media | Estabilidad | 59 `catch (_)` silenciosos; filas que fallan en merge se descartan sin registro |
| P8 | 🟡 Baja | Arranque | `main()` bloquea `runApp` esperando Supabase + notificaciones |

---

# PARTE 1 — SEGURIDAD

## S1 · Credenciales expuestas (CRÍTICA)

**Evidencia**
- `pubspec.yaml` incluye `assets: - .env` → el `.env` real (URL + anon key del proyecto `llxaxdyczysfktvdpqwj`) viaja dentro del APK y, en web, es **descargable como archivo estático** (`assets/.env`).
- `.gitignore` **no excluye `.env`** → si el repo se publica o comparte, las claves van incluidas.
- `E:\dev\SIEMBRAS\Subabase CONFIG.txt` contiene la anon key legacy (JWT válido hasta 2036), la publishable key y la cadena de conexión directa a Postgres, en una carpeta sincronizada.

**Riesgo.** La anon key está diseñada para ser pública *siempre que las políticas RLS sean correctas* (ver S6). Pero la cadena de conexión directa con contraseña de BD otorgaría acceso total sin RLS. Y las claves legacy no expiran hasta 2036.

**Parche**

1. `.gitignore` — añadir:
```gitignore
# Secretos
.env
*.env.local
```
2. `pubspec.yaml` — mantener `.env` como asset es aceptable solo si únicamente contiene la anon key. Alternativa más limpia con `--dart-define` (nada de archivos en el bundle):
```dart
// lib/services/supabase_service.dart
const _url  = String.fromEnvironment('SUPABASE_URL');
const _anon = String.fromEnvironment('SUPABASE_ANON_KEY');
```
```bash
flutter build apk --dart-define=SUPABASE_URL=https://xxx.supabase.co --dart-define=SUPABASE_ANON_KEY=xxx
```
3. Mover `Subabase CONFIG.txt` y `Hosting CONFIG.txt` fuera de carpetas de proyecto/sincronizadas (usar un gestor de contraseñas). Nunca guardar la contraseña de Postgres ni la `service_role` key en estas carpetas.
4. En el dashboard de Supabase: **rotar/deshabilitar las "Legacy API keys" (JWT)** y usar solo la publishable key nueva. Verificar en *Settings → API* que la `service_role` nunca haya salido del dashboard.

## S2 · Validación TLS deshabilitada para EPPO (ALTA)

**Evidencia** — `lib/services/eppo_client.dart:215-219`:
```dart
final ioClient = HttpClient()
  ..badCertificateCallback = (cert, host, port) =>
      host == _apiHost && port == 443;
```
Esto acepta **cualquier certificado** (incluido uno autofirmado por un atacante) para `api.eppo.int`. En una red WiFi hostil, un MITM puede interceptar el token EPPO (viaja en el header `X-Api-Key`) y falsificar respuestas de patologías/plagas — datos que alimentan recomendaciones fitosanitarias.

**Parche** — anclar la clave pública (SPKI pinning) en lugar de aceptar todo:
```dart
import 'dart:io';
import 'package:crypto/crypto.dart';   // añadir crypto: ^3.0.3 a pubspec

/// SHA-256 del DER del certificado hoja de api.eppo.int.
/// Obtener con:
///   openssl s_client -connect api.eppo.int:443 </dev/null 2>/dev/null \
///     | openssl x509 -outform DER | openssl dgst -sha256
/// Incluir también el fingerprint del certificado de respaldo/renovación.
const _eppoPins = <String>{
  'PONER_FINGERPRINT_SHA256_AQUI',
  'PONER_FINGERPRINT_BACKUP_AQUI',
};

static http.Client _crearHttpClient() {
  final ioClient = HttpClient()
    ..badCertificateCallback = (cert, host, port) {
      if (host != _apiHost || port != 443) return false;
      final fp = sha256.convert(cert.der).toString();
      return _eppoPins.contains(fp);
    };
  return IOClient(ioClient);
}
```
Nota: al renovarse el certificado de EPPO habrá que actualizar el pin (por eso el pin de respaldo). Es un mantenimiento pequeño a cambio de cerrar el MITM. Verificar también periódicamente si Dart ya resuelve la cadena (probar sin callback); si sí, eliminar la excepción por completo.

## S3 · Token EPPO en texto plano (MEDIA)

**Evidencia** — `database.dart:631`: `TextColumn get eppoToken => text().nullable()();` en la tabla `configs` de SQLite sin cifrar.

**Parche** — usar almacenamiento seguro del sistema (Keystore/Keychain/DPAPI):
```yaml
# pubspec.yaml
flutter_secure_storage: ^9.2.2
```
```dart
// lib/services/secure_store.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const _s = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );
  static Future<void> setEppoToken(String t) => _s.write(key: 'eppo_token', value: t);
  static Future<String?> getEppoToken() => _s.read(key: 'eppo_token');
  static Future<void> deleteEppoToken() => _s.delete(key: 'eppo_token');
}
```
Migración: al arrancar, si `configs.eppo_token` no es null → copiarlo a SecureStore y poner la columna a null.

## S4 · SQLite sin cifrar (MEDIA)

`nexus_siembras.sqlite` queda legible en el directorio de documentos (extraíble en dispositivos rooteados o vía backup ADB). Contiene datos de negocio del productor (compras, costos, colaboradores).

**Parche** — Drift soporta SQLCipher:
```yaml
# pubspec.yaml — reemplaza sqlite3_flutter_libs
sqlcipher_flutter_libs: ^0.6.0
```
```dart
// db_connection_native.dart
return NativeDatabase.createInBackground(
  file,
  setup: (db) {
    final key = /* clave generada una vez y guardada en SecureStore */;
    db.execute("PRAGMA key = '$key';");
  },
);
```
La clave se genera aleatoria en el primer arranque (32 bytes, base64) y se guarda con `flutter_secure_storage`. Requiere migración única: exportar → recrear cifrada → importar (puede reutilizarse `BackupService`).

## S5 · Bucket público + EXIF/GPS en fotos (MEDIA)

**Evidencia** — `schema_3e.sql`: `INSERT INTO storage.buckets ... public => true`. Las fotos de patologías son legibles por cualquiera con la URL. `image_picker` puede conservar metadatos EXIF (incluidas coordenadas GPS del predio) según plataforma.

**Parche**
1. Re-encodificar la imagen antes de persistir para eliminar EXIF:
```yaml
image: ^4.2.0
```
```dart
// patologia_foto_service.dart — dentro de _persistir()
import 'package:image/image.dart' as img;

Future<String> _persistir(XFile xf) async {
  final bytes = await xf.readAsBytes();
  final decoded = img.decodeImage(bytes)!;      // decodificar…
  final clean = img.encodeJpg(decoded, quality: 82); // …re-encodificar sin EXIF
  final dir = await _dir();
  final path = '${dir.path}${Platform.pathSeparator}${_uuid.v4()}.jpg';
  await File(path).writeAsBytes(clean);
  return path;
}
```
2. Si las fotos son "comunitarias" por diseño, el bucket público es válido — pero documentarlo en la UI ("esta foto será visible públicamente"). Si no, cambiar a `public => false` y servir con `createSignedUrl(path, 3600)`.

## S6 · RLS fragmentado y ramas "por si el schema no está aplicado" (MEDIA)

**Evidencia** — 7 archivos (`schema.sql`, `schema_3e.sql`, `_v2`–`_v4`, `schema_3g.sql`, más `fix_*.sql`) que se aplican manualmente, y comentarios en `sync_service.dart` tipo *"si el proyecto Postgres NO tiene aplicado schema_3e_v4.sql…"*. El cliente compensa políticas de seguridad posiblemente ausentes: un entorno desactualizado puede quedar con RLS incompleta sin que nadie lo note.

**Parche**
1. Consolidar en **una migración canónica versionada** (idealmente con `supabase migration` CLI: `supabase/migrations/0001_init.sql`, `0002_shares.sql`, …).
2. Añadir tabla de versión + verificación al arrancar:
```sql
CREATE TABLE IF NOT EXISTS public.schema_meta (id int PRIMARY KEY DEFAULT 1, version int NOT NULL);
INSERT INTO public.schema_meta (version) VALUES (7) ON CONFLICT (id) DO UPDATE SET version = 7;
CREATE POLICY schema_meta_read ON public.schema_meta FOR SELECT USING (auth.role() = 'authenticated');
ALTER TABLE public.schema_meta ENABLE ROW LEVEL SECURITY;
```
```dart
// En SyncService.sincronizar(), antes de pull:
const requiredSchema = 7;
final meta = await _sb.from('schema_meta').select('version').single();
if ((meta['version'] as int) < requiredSchema) {
  return SyncResult(pushed: 0, pulled: 0,
    error: 'El servidor requiere actualización de esquema (v${meta['version']} < v$requiredSchema). Sync bloqueado por seguridad.',
    duration: Duration.zero);
}
```
3. Eliminar del cliente las ramas de compatibilidad una vez verificada la versión.

## S7 · Política de contraseñas (BAJA)

Mínimo de 6 caracteres en `onboarding_screen.dart:802`. **Parche:** subir a 8+ en el cliente y, sobre todo, configurarlo en Supabase (*Auth → Settings*): longitud mínima 8, activar *Leaked password protection* y límites de intentos.

---

# PARTE 2 — RENDIMIENTO Y ESTABILIDAD

## P1 · N+1 en sincronización (ALTA)

**Evidencia** — `sync_service.dart`: `contarPendientes()` carga **todas las filas de las 10 tablas** y por cada fila ejecuta `_debeSubir()` → 1 consulta a `sync_mappings` por fila. Con 500 registros son ~510 consultas SQLite; y esto corre en cada transición de red (P6). El mismo patrón se repite en todos los `_pushXxx()` con `_resolveRemoteId()`.

**Parche** — cargar los mappings de una tabla en un `Map` con una sola consulta:
```dart
/// Mapa localId → mapping de una tabla, en 1 consulta.
Future<Map<int, SyncMapping>> _mappingsDe(String tabla) async {
  final rows = await (db.select(db.syncMappings)
        ..where((s) => s.tabla.equals(tabla)))
      .get();
  return {for (final r in rows) r.localId: r};
}

Future<int> _contarPendientesTabla<T>(
  String tabla,
  Future<List<T>> Function() reader, {
  required int Function(T) idOf,
  required DateTime Function(T) updatedOf,
}) async {
  final rows = await reader();
  final mappings = await _mappingsDe(tabla);          // 1 consulta
  var count = 0;
  for (final r in rows) {
    final m = mappings[idOf(r)];
    if (m == null || updatedOf(r).isAfter(m.lastPushedAt)) count++;
  }
  return count;
}
```
Aplicar el mismo patrón en cada `_pushXxx()`: obtener `_mappingsDe('predios')` una vez antes del bucle y resolver en memoria. Reducción esperada: de O(filas) consultas a O(1) por tabla.

## P2 · Push fila-por-fila (ALTA)

Cada registro genera su propio `upsert` HTTP. En conexión rural (latencia 300–800 ms), subir 200 registros toma minutos y multiplica la probabilidad de sync parcial.

**Parche** — `upsert` por lotes (PostgREST acepta arrays):
```dart
const _batchSize = 200;

Future<int> _pushBatch(String tabla, List<Map<String, dynamic>> payloads,
    {required String onConflict}) async {
  var count = 0;
  for (var i = 0; i < payloads.length; i += _batchSize) {
    final chunk = payloads.sublist(i, (i + _batchSize).clamp(0, payloads.length));
    final res = await _sb.from(tabla)
        .upsert(chunk, onConflict: onConflict)
        .select('id, cliente_id');           // devuelve ids para _saveMapping
    for (final row in (res as List)) {
      // cliente_id == localId → guardar mapping en bloque
    }
    count += chunk.length;
  }
  return count;
}
```
Y guardar los mappings también en lote con `db.batch((b) => b.insertAllOnConflictUpdate(...))`.

## P3 · Pull sin paginación ni orden (ALTA)

**Evidencia** — `_pullTable()` hace `select()` sin `order` ni `range`. En el primer sync (o `sincronizarDesdeCero()`) descarga tablas completas en una sola respuesta: riesgo de timeout, consumo de memoria y respuesta truncada por el límite de filas por defecto de PostgREST (1000 — **filas silenciosamente perdidas** si hay más).

**Parche**
```dart
const _pageSize = 500;

Future<int> _pullTable(String tabla,
    Future<void> Function(Map<String, dynamic>) merger,
    {String timestampCol = 'updated_at'}) async {
  final syncRow = await (db.select(db.syncTables)
        ..where((s) => s.tabla.equals(tabla))).getSingleOrNull();
  final since = syncRow?.lastPulledAt;

  var count = 0;
  DateTime? maxRemoto;
  var offset = 0;
  while (true) {
    var q = _sb.from(tabla).select();
    if (since != null) {
      q = q.gt(timestampCol, since.toUtc().toIso8601String());
    }
    final page = await q
        .order(timestampCol, ascending: true)
        .range(offset, offset + _pageSize - 1);
    for (final raw in (page as List)) {
      final row = raw as Map<String, dynamic>;
      try {
        await merger(row);
        count++;
        final ts = DateTime.tryParse('${row[timestampCol]}');
        if (ts != null && (maxRemoto == null || ts.isAfter(maxRemoto))) {
          maxRemoto = ts;
        }
      } catch (e) {
        _log('pull $tabla: fila descartada: $e');   // ver P7
      }
    }
    if (page.length < _pageSize) break;
    offset += _pageSize;
  }
  // Cursor = timestamp del SERVIDOR, no del cliente (ver P4)
  await db.into(db.syncTables).insertOnConflictUpdate(SyncTablesCompanion.insert(
    tabla: tabla,
    lastPulledAt: Value(maxRemoto ?? since ?? DateTime.now()),
    lastAttemptAt: Value(DateTime.now()),
  ));
  return count;
}
```

## P4 · Cursor de pull con reloj del cliente (ALTA — pérdida de datos)

**Evidencia** — `lastPulledAt: Value(DateTime.now())`. Si el reloj del dispositivo va adelantado respecto al servidor (muy común en Android rural sin NTP), el próximo `gt(updated_at, since)` **salta filas escritas por otros usuarios** entre el inicio del pull y "ahora". Los síntomas son exactamente los bugs de colaboradores ya documentados en los comentarios del código.

**Parche** — incluido en el código de P3: el cursor se avanza al **máximo `updated_at` recibido del servidor**, nunca al reloj local. Es la corrección de mayor impacto/menor esfuerzo de toda la auditoría.

## P5 · LWW con `updated_at` del cliente (MEDIA)

La resolución de conflictos compara timestamps generados por relojes de dispositivos distintos. Un teléfono con la hora mal configurada (adelantada) machaca sistemáticamente los cambios de los demás colaboradores.

**Parche** — que el servidor sea la autoridad del tiempo:
```sql
-- Aplicar a todas las tablas sincronizables
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['predios','lotes','proveedores','cultivos',
    'eventos_cultivo','inventarios','compras','analisis_suelo',
    'condiciones_predio','predio_shares']
  LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS trg_updated_at ON public.%I', t);
    EXECUTE format(
      'CREATE TRIGGER trg_updated_at BEFORE INSERT OR UPDATE ON public.%I
       FOR EACH ROW EXECUTE FUNCTION public.set_updated_at()', t);
  END LOOP;
END $$;
```
El cliente deja de enviar `updated_at` en los payloads de push; tras el upsert, lee el `updated_at` devuelto (`.select('id, updated_at')`) y lo guarda localmente. Así el LWW compara siempre tiempos del mismo reloj.

## P6 · Auto-sync: trabajo desperdiciado y syncs concurrentes (MEDIA)

**Evidencia** — `auto_sync_service.dart`: (a) `contarPendientes()` (costosísimo, ver P1) se ejecuta en cada transición offline→online y **su resultado se descarta** (el `if (pendientes == 0) {}` está vacío); (b) `iniciar()` dispara `checkConnectivity().then(...)` además del listener — dos entradas simultáneas pueden lanzar `sincronizar()` en paralelo, y `SyncService` no tiene guard de reentrada.

**Parche**
```dart
class AutoSyncService {
  // ...
  bool _sincronizando = false;

  Future<void> _intentarSync() async {
    if (_sincronizando) return;                       // guard de reentrada
    if (Supabase.instance.client.auth.currentSession == null) return;

    final ahora = DateTime.now();
    if (_ultimoAutoSync != null &&
        ahora.difference(_ultimoAutoSync!).inSeconds < 30) return;

    _sincronizando = true;
    try {
      // Nota: no llamar contarPendientes() aquí — sincronizar() ya hace
      // pull+push y decide por sí mismo qué subir. El conteo previo era
      // solo costo extra sin efecto.
      final res = await sync.sincronizar();
      if (res.exito) _ultimoAutoSync = ahora;
    } finally {
      _sincronizando = false;
    }
  }
}
```
Añadir el mismo guard dentro de `SyncService.sincronizar()` (por el botón manual + auto-sync simultáneos):
```dart
bool _enCurso = false;
Future<SyncResult> sincronizar() async {
  if (_enCurso) {
    return const SyncResult(pushed: 0, pulled: 0,
        error: 'Sincronización ya en curso', duration: Duration.zero);
  }
  _enCurso = true;
  try { /* ...cuerpo actual... */ } finally { _enCurso = false; }
}
```

## P7 · Errores silenciados (MEDIA)

59 bloques `catch (_)` y 9 `print()`. En particular, `_pullTable` descarta filas que fallan en el merge sin dejar rastro: la BD local diverge del servidor y nadie lo sabe (es la clase de fallo detrás de varios `fix_*.sql` del historial).

**Parche**
1. Logger central en lugar de `print`:
```yaml
logger: ^2.4.0
```
```dart
// lib/core/log.dart
import 'package:logger/logger.dart';
final log = Logger(printer: SimplePrinter(), level: Level.info);
```
2. Contabilizar errores en `SyncResult` y mostrarlos en la UI de sync:
```dart
class SyncResult {
  final int pushed, pulled, errores;      // + errores
  // ...
  bool get exito => error == null && errores == 0;
}
```
3. Regla del proyecto: `catch (_) {}` solo se permite con comentario que justifique por qué ignorar es correcto; en el resto, mínimo `log.w(...)`.

## P8 · Arranque bloqueante (BAJA)

`main()` espera `SupabaseService.init()` + `NotificationService.init()` antes de `runApp`. **Parche:** pintar la UI primero y completar la inicialización después del primer frame:
```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try { await dotenv.load(fileName: '.env'); } catch (_) {}
  runApp(const ProviderScope(child: NexusSiembrasApp()));
  // Después del primer frame — no bloquea el arranque visual
  WidgetsBinding.instance.addPostFrameCallback((_) {
    SupabaseService.instance.init();
    NotificationService.instance.init();
  });
}
```
Requiere que los providers de auth reaccionen cuando `isInitialized` cambie (convertir `supabaseInitProvider` en `StateProvider`/`StreamProvider` en vez de `Provider` estático — hoy queda congelado al valor del arranque, lo que también es un bug latente si la red demora la init).

## Observaciones menores

- `_reconciliarEventosLocales()` recorre todos los cultivos en cada sync; con cientos de cultivos convendrá limitarla a cultivos tocados por el pull.
- `BackupService` arma todo el JSON en memoria con indentación: correcto hoy, revisar si los backups superan ~10 MB.
- `flutter_01.png` (0 bytes) y los `schema_3e_v*.sql` obsoletos deberían eliminarse del repo al consolidar S6.
- `SyncResult.error = '$e'` puede exponer detalles internos (URLs, SQL) en la UI; mostrar mensaje amigable y mandar el detalle al logger.

## Orden de implementación sugerido

1. **Inmediato (sin tocar arquitectura):** S1 (gitignore + rotar claves + mover CONFIG.txt), P4 (cursor con tiempo del servidor), P6 (guards de reentrada).
2. **Sprint corto:** S2 (pinning EPPO), P1 (mapa de mappings), P3 (paginación), P7 (logger + contador de errores).
3. **Sprint medio:** P2 (batch upserts), P5 (triggers `updated_at`), S6 (migraciones canónicas + verificación de versión), S3 (secure storage).
4. **Planificado:** S4 (SQLCipher, requiere migración de datos), S5 (EXIF), P8, S7.
