// Backend nativo (Android, iOS, Windows, macOS, Linux) usando SQLCipher
// vía dart:ffi (auditoría 2026-07-19, S4: la BD local ahora va cifrada).
//
// La clave se genera una sola vez y vive en el almacén seguro del sistema
// (Keystore/Keychain/DPAPI) — ver SecureStore. Una BD preexistente sin
// cifrar se migra automáticamente en el primer arranque con
// `sqlcipher_export`; la copia cifrada se VERIFICA antes de eliminar el
// original, y no queda ningún archivo en texto claro en disco (revisión
// 2026-07-20 #1).

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart';
import '../../core/log.dart';
import '../../services/secure_store.dart';

/// Redirige la carga de la librería nativa hacia SQLCipher según la
/// plataforma. Debe ejecutarse ANTES de abrir cualquier conexión.
///
/// IMPORTANTE (fix 2026-07-19): en Windows y Linux NO se hace override.
/// El CMake de sqlcipher_flutter_libs 0.6.x compila SQLCipher y lo
/// empaqueta con el NOMBRE ESTÁNDAR (`sqlite3.dll` / `libsqlite3.so`),
/// que es justo lo que `package:sqlite3` carga por defecto. El intento
/// anterior de abrir `sqlcipher.dll` (inexistente) rompía la apertura de
/// la BD y dejaba la app muda (bug "Comenzar no hace nada" en el
/// onboarding). El check `PRAGMA cipher_version` de abajo confirma que
/// la librería cargada es realmente SQLCipher.
///
/// IMPORTANTE (fix 2026-07-30): en Android el workaround y el override
/// deben aplicarse también dentro del isolate de Drift (`isolateSetup`).
/// Sin eso, el isolate de fondo carga libsqlite3.so del sistema (sin
/// cifrado) y la BD recién creada queda ilegible → SqliteException(26)
/// "file is not a database" en PRAGMA user_version (onboarding Ubicación).
Future<void> _configurarSqlCipherEnIsolate() async {
  if (Platform.isAndroid) {
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }
}

Future<void> _configurarSqlCipher() async {
  await _configurarSqlCipherEnIsolate();
}

LazyDatabase openConnection() {
  return LazyDatabase(() async {
    await _configurarSqlCipher();
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'nexus_siembras.sqlite'));
    final key = await SecureStore.obtenerOCrearClaveDb();
    await _migrarACifradoSiHaceFalta(file, key);
    // Si quedó un archivo ilegible (p. ej. backup de Android restauró la
    // BD cifrada pero no la clave del Keystore), lo eliminamos antes de
    // que Drift falle en el primer SELECT del onboarding.
    await _eliminarBdIlegibleSiHaceFalta(file, key);
    // Limpieza de respaldos en texto claro dejados por la versión anterior
    // de la migración (revisión 2026-07-20 #1).
    final legacyBak = File('${file.path}.pre-cifrado.bak');
    if (await legacyBak.exists()) {
      try {
        await legacyBak.delete();
        Log.i('[db] respaldo legado sin cifrar eliminado');
      } catch (e) {
        Log.w('[db] no se pudo eliminar el respaldo legado: $e');
      }
    }
    final escapedKey = key.replaceAll("'", "''");
    return NativeDatabase.createInBackground(
      file,
      // Fix Android (2026-07-20): createInBackground abre la BD en un
      // ISOLATE separado, y los overrides de `open.overrideFor` son por
      // isolate — aplicarlos solo en el principal dejaba al isolate de
      // fondo cargando el libsqlite3.so por defecto, que ya no existe
      // ("Failed to load dynamic library libsqlite3.so"). isolateSetup
      // corre dentro del isolate de la BD, antes de abrir.
      isolateSetup: () async {
        await _configurarSqlCipherEnIsolate();
      },
      setup: (db) {
        // La clave debe fijarse antes de cualquier otra sentencia.
        db.execute("PRAGMA key = '$escapedKey';");
        // Fallar temprano y con mensaje claro si la librería enlazada NO
        // es SQLCipher (p. ej. plataforma sin la librería nativa): sin
        // este check el error sería un críptico "file is not a database".
        if (db.select('PRAGMA cipher_version;').isEmpty) {
          throw StateError(
              'SQLCipher no disponible en esta plataforma: la BD cifrada '
              'no puede abrirse. Verifique sqlcipher_flutter_libs.');
        }
      },
    );
  });
}

/// Migración única: si el archivo existe y es SQLite SIN cifrar (header
/// "SQLite format 3"), lo exporta a una copia cifrada y la deja en el
/// path original. Un archivo ya cifrado tiene header aleatorio y no
/// entra en esta rama.
Future<void> _migrarACifradoSiHaceFalta(File file, String key) async {
  if (!await file.exists()) return;
  final raf = await file.open();
  final header = await raf.read(16);
  await raf.close();
  final esPlano = String.fromCharCodes(header).startsWith('SQLite format 3');
  if (!esPlano) return;

  Log.i('[db] BD sin cifrar detectada — migrando a SQLCipher (una vez)…');
  final encPath = '${file.path}.enc';
  final enc = File(encPath);
  if (await enc.exists()) await enc.delete(); // resto de intento previo

  final escapedKey = key.replaceAll("'", "''");
  final escapedPath = encPath.replaceAll("'", "''");
  final plain = sqlite3.open(file.path);
  try {
    // IMPORTANTE (fix 2026-07-19): `sqlcipher_export` NO copia el
    // PRAGMA user_version. Sin esto, Drift ve versión 0 en la BD
    // migrada, re-ejecuta onCreate y el seed choca con los catálogos ya
    // poblados (bug "UNIQUE constraint failed: unidades_medida.codigo").
    final userVersion =
        plain.select('PRAGMA user_version;').first.columnAt(0) as int;
    plain.execute(
        "ATTACH DATABASE '$escapedPath' AS encrypted KEY '$escapedKey';");
    plain.select("SELECT sqlcipher_export('encrypted');");
    plain.execute('PRAGMA encrypted.user_version = $userVersion;');
    plain.execute('DETACH DATABASE encrypted;');
  } finally {
    plain.dispose();
  }

  // Verificación (revisión de código 2026-07-20, hallazgo #1): antes de
  // eliminar el original, la copia cifrada debe abrir con la clave y
  // contener el esquema. El diseño anterior dejaba un respaldo
  // `.pre-cifrado.bak` en texto claro — anulaba el beneficio de SQLCipher.
  var verificada = false;
  try {
    final check = sqlite3.open(encPath);
    try {
      check.execute("PRAGMA key = '$escapedKey';");
      final n = check
          .select('SELECT count(*) AS n FROM sqlite_master;')
          .first['n'] as int;
      verificada = n > 0;
    } finally {
      check.dispose();
    }
  } catch (e) {
    Log.e('[db] verificación de la BD cifrada falló', e);
  }
  if (!verificada) {
    // Conservar el original intacto y descartar la copia cifrada; se
    // reintentará en el próximo arranque. Abortar aquí evita que la app
    // abra el archivo plano con clave y lo reporte como corrupto.
    try {
      await enc.delete();
    } catch (_) {
      // Best effort: un residuo .enc se sobreescribe en el reintento.
    }
    throw StateError(
        'La migración a BD cifrada no pudo verificarse; la BD original '
        'se conserva sin modificar. Reinicie la app para reintentar.');
  }
  // Original en texto claro eliminado — sin respaldos sin cifrar en disco.
  await file.delete();
  await enc.rename(file.path);
  Log.i('[db] Migración a BD cifrada completada y verificada; el archivo '
      'original sin cifrar fue eliminado.');
}

/// Detecta una BD existente que no abre con la clave actual (típico tras
/// reinstalar Android con backup en la nube: restaura el .sqlite pero no
/// la clave del Keystore) y la elimina para que Drift cree una nueva.
Future<void> _eliminarBdIlegibleSiHaceFalta(File file, String key) async {
  if (!await file.exists()) return;
  final escapedKey = key.replaceAll("'", "''");
  Database? db;
  try {
    db = sqlite3.open(file.path);
    db.execute("PRAGMA key = '$escapedKey';");
    if (db.select('PRAGMA cipher_version;').isEmpty) {
      throw StateError('SQLCipher no disponible');
    }
    // Dispara "file is not a database" si la clave no coincide o el
    // archivo quedó creado con sqlite plano (bug del isolate, 2026-07-30).
    db.select('PRAGMA user_version;');
  } catch (e) {
    if (!_esErrorBdIlegible(e)) rethrow;
    Log.w('[db] BD local ilegible — se eliminará y se creará de nuevo: $e');
    await _eliminarArchivosBd(file);
  } finally {
    db?.dispose();
  }
}

bool _esErrorBdIlegible(Object e) {
  final msg = e.toString().toLowerCase();
  return msg.contains('file is not a database') ||
      msg.contains('not a database') ||
      msg.contains('code 26');
}

Future<void> _eliminarArchivosBd(File file) async {
  for (final path in [
    file.path,
    '${file.path}-wal',
    '${file.path}-shm',
    '${file.path}-journal',
    '${file.path}.enc',
    '${file.path}.pre-cifrado.bak',
  ]) {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
