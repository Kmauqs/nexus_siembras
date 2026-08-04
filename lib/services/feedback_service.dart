// NEXUS Siembras — Micro-encuestas de feedback (Revisión C2-9, 2026-08-03).
//
// Offline-first, mismo patrón que la cola de sync (`sync_ops`):
//   1. `guardar()` SIEMPRE escribe en la cola local Drift
//      (`feedback_encuestas`, v21). Funciona sin red y sin sesión, así que
//      el tester nunca pierde lo que escribió.
//   2. `enviarPendientes()` sube lo pendiente a la tabla Supabase
//      `feedback_encuestas` (migración 0016) cuando hay sesión + red.
//      Se dispara al guardar, al abrir la pantalla y tras cada auto-sync.
//   3. Tras N intentos fallidos la fila se conserva localmente (no se
//      descarta: el feedback es escaso y valioso) pero deja de reintentar
//      en cada ciclo, para no golpear la red.
//
// La notificación por email NO sale del cliente: la dispara un webhook
// de Supabase sobre esta tabla (ver docs/FEEDBACK_ENCUESTAS.md).

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:drift/drift.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/log.dart';
import '../data/database/database.dart';
import 'supabase_service.dart';

class FeedbackService {
  FeedbackService(this.db);

  final AppDatabase db;

  /// Tras estos intentos la fila deja de reintentarse automáticamente
  /// (sigue en la BD y puede reenviarse a mano desde la pantalla).
  static const int maxIntentos = 8;

  static String _plataforma() {
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
      if (Platform.isWindows) return 'windows';
      if (Platform.isLinux) return 'linux';
      if (Platform.isMacOS) return 'macos';
    } catch (_) {
      // Web u otro entorno sin dart:io.
      return 'web';
    }
    return 'desconocida';
  }

  static Future<String?> _appVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (e) {
      Log.d('[feedback] versión no disponible: $e');
      return null;
    }
  }

  /// Guarda la encuesta localmente y devuelve su id. Intenta enviarla de
  /// inmediato (fire-and-forget) si hay conexión.
  Future<int> guardar({
    required String tipo,
    int? calificacion,
    Map<String, dynamic> respuestas = const {},
    String? comentario,
  }) async {
    final id = await db.into(db.feedbackEncuestas).insert(
          FeedbackEncuestasCompanion.insert(
            tipo: Value(tipo),
            calificacion: Value(calificacion),
            respuestasJson: Value(jsonEncode(respuestas)),
            comentario: Value(comentario?.trim().isEmpty ?? true
                ? null
                : comentario!.trim()),
            appVersion: Value(await _appVersion()),
            plataforma: Value(_plataforma()),
          ),
        );
    Log.i('[feedback] encuesta #$id guardada localmente (tipo=$tipo)');
    // No bloquea la UI: si falla, queda pendiente para el próximo ciclo.
    unawaited(enviarPendientes());
    return id;
  }

  /// Cuántas encuestas quedan sin enviar.
  Future<int> contarPendientes() async {
    final rows = await (db.select(db.feedbackEncuestas)
          ..where((f) => f.enviadaAt.isNull()))
        .get();
    return rows.length;
  }

  Future<List<FeedbackEncuesta>> historial({int limit = 20}) {
    return (db.select(db.feedbackEncuestas)
          ..orderBy([(f) => OrderingTerm.desc(f.createdAt)])
          ..limit(limit))
        .get();
  }

  /// Sube las encuestas pendientes. Silencioso y tolerante: sin sesión,
  /// sin red o sin la migración 0016 no lanza — deja todo pendiente.
  /// [forzar] reintenta también las que superaron [maxIntentos].
  Future<int> enviarPendientes({bool forzar = false}) async {
    final sb = SupabaseService.instance.client;
    if (sb == null || sb.auth.currentSession == null) return 0;

    final pendientes = await (db.select(db.feedbackEncuestas)
          ..where((f) => f.enviadaAt.isNull())
          ..orderBy([(f) => OrderingTerm.asc(f.createdAt)]))
        .get();
    if (pendientes.isEmpty) return 0;

    final email = sb.auth.currentUser?.email;
    var enviadas = 0;
    for (final f in pendientes) {
      if (!forzar && f.intentos >= maxIntentos) continue;
      try {
        await sb.from('feedback_encuestas').insert({
          'email_usuario': email,
          'tipo': f.tipo,
          'calificacion': f.calificacion,
          'respuestas': jsonDecode(f.respuestasJson),
          'comentario': f.comentario,
          'app_version': f.appVersion,
          'plataforma': f.plataforma,
          // `user_id` lo pone el DEFAULT auth.uid() del servidor.
          'created_at': f.createdAt.toUtc().toIso8601String(),
        });
        await (db.update(db.feedbackEncuestas)
              ..where((x) => x.id.equals(f.id)))
            .write(FeedbackEncuestasCompanion(
          enviadaAt: Value(DateTime.now()),
          ultimoError: const Value(null),
        ));
        enviadas++;
      } catch (e) {
        await (db.update(db.feedbackEncuestas)
              ..where((x) => x.id.equals(f.id)))
            .write(FeedbackEncuestasCompanion(
          intentos: Value(f.intentos + 1),
          ultimoError: Value('$e'),
        ));
        Log.w('[feedback] envío de #${f.id} falló '
            '(intento ${f.intentos + 1}): $e');
      }
    }
    if (enviadas > 0) {
      Log.i('[feedback] $enviadas encuesta(s) enviada(s) al servidor');
    }
    return enviadas;
  }
}

/// `unawaited` sin importar dart:async en el llamador.
void unawaited(Future<void> future) {
  future.catchError((Object e) {
    Log.d('[feedback] tarea en segundo plano falló: $e');
  });
}
