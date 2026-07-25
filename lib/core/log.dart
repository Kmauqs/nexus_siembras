// NEXUS Siembras — Logger central (auditoría 2026-07-19, P7).
//
// Reemplaza los `print()` dispersos. Sin dependencias externas:
// usa `debugPrint` (throttled, seguro en release) y niveles simples.
//
// 2026-07-20: buffer de diagnóstico en memoria (últimas [_maxLineas]
// entradas de la sesión) para la card "Logs de diagnóstico" de la
// pantalla Reportes: visualizar, compartir y limpiar.
//
// Regla del proyecto: `catch (_) {}` totalmente silencioso solo se
// permite con un comentario que justifique por qué ignorar es correcto.
// En el resto de casos, mínimo `Log.w(...)`.

import 'package:flutter/foundation.dart';

class Log {
  Log._();

  static const int _maxLineas = 800;
  static final List<String> _buffer = <String>[];

  /// Copia inmutable del buffer de la sesión (más reciente al final).
  static List<String> get lineas => List.unmodifiable(_buffer);

  /// Todo el buffer como un solo texto (para compartir).
  static String volcado() => _buffer.join('\n');

  static void limpiar() => _buffer.clear();

  static void _registrar(String nivel, String msg) {
    final ts = DateTime.now().toIso8601String().substring(0, 19);
    _buffer.add('$ts [$nivel] $msg');
    if (_buffer.length > _maxLineas) {
      _buffer.removeRange(0, _buffer.length - _maxLineas);
    }
  }

  /// Detalle de depuración — solo en modo debug (no entra al buffer).
  static void d(String msg) {
    if (kDebugMode) debugPrint('[D] $msg');
  }

  /// Información operativa.
  static void i(String msg) {
    _registrar('I', msg);
    debugPrint('[I] $msg');
  }

  /// Advertencia: algo inesperado pero recuperable.
  static void w(String msg) {
    _registrar('W', msg);
    debugPrint('[W] $msg');
  }

  /// Error: fallo real. Incluir excepción y stack si están disponibles.
  static void e(String msg, [Object? error, StackTrace? st]) {
    _registrar('E', '$msg${error != null ? ' — $error' : ''}');
    debugPrint('[E] $msg${error != null ? ' — $error' : ''}');
    if (st != null && kDebugMode) debugPrint('$st');
  }
}
