// NEXUS Siembras — Almacenamiento seguro de secretos (auditoría S3/S4).
//
// Usa el almacén nativo de cada plataforma:
//   Android → Keystore (EncryptedSharedPreferences)
//   iOS/macOS → Keychain
//   Windows → DPAPI
//   Linux → libsecret
//
// Actualmente guarda la clave de cifrado de la base SQLite (SQLCipher).
// Nota S3: el token EPPO sigue en la tabla `configs`, pero desde la
// migración S4 esa tabla vive dentro de la BD cifrada — el token ya no
// queda en texto plano en disco.

import 'dart:convert';
import 'dart:math';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  SecureStore._();

  // v10 de flutter_secure_storage: EncryptedSharedPreferences es el
  // comportamiento por defecto en Android (la opción explícita
  // `encryptedSharedPreferences` fue retirada del API). La librería
  // migra automáticamente los valores escritos por la v9.
  static const _storage = FlutterSecureStorage();

  static const _kDbKey = 'nexus_db_cipher_key';

  /// Devuelve la clave de cifrado de la BD; la genera (32 bytes aleatorios
  /// seguros, base64url) y la persiste la primera vez.
  ///
  /// ADVERTENCIA: si el usuario borra el almacén seguro del sistema (o
  /// restaura la app en otro dispositivo sin backup del keystore), la BD
  /// local cifrada no podrá abrirse. El respaldo/restore de datos debe
  /// hacerse siempre vía BackupService (JSON) o sync en la nube.
  static Future<String> obtenerOCrearClaveDb() async {
    var key = await _storage.read(key: _kDbKey);
    if (key == null || key.isEmpty) {
      final rnd = Random.secure();
      final bytes = List<int>.generate(32, (_) => rnd.nextInt(256));
      key = base64UrlEncode(bytes);
      await _storage.write(key: _kDbKey, value: key);
    }
    return key;
  }
}
