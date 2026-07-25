// NEXUS Siembras — Servicio Supabase (offline-first)
// Sincroniza los cambios locales con la nube cuando hay conexión.

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();
  static final SupabaseService instance = SupabaseService._();

  bool _initialized = false;
  bool get isInitialized => _initialized;

  /// Modo actual leído de .env
  String get syncMode =>
      dotenv.env['SYNC_MODE'] ?? 'offline_first';

  Future<void> init() async {
    if (_initialized) return;
    final url = dotenv.env['SUPABASE_URL'];
    // Preferir la publishable key (nueva generación, rotable desde el
    // dashboard). SUPABASE_ANON_KEY (JWT legacy) queda como respaldo
    // mientras se rotan las claves — auditoría S1. El parámetro
    // `publishableKey` del SDK acepta ambos formatos.
    final key = dotenv.env['SUPABASE_PUBLISHABLE_KEY'] ??
        dotenv.env['SUPABASE_ANON_KEY'];
    if (url == null || key == null || url.contains('YOUR_PROJECT')) {
      // Config incompleta -> la app funciona 100% local
      return;
    }
    await Supabase.initialize(url: url, publishableKey: key);
    _initialized = true;
  }

  SupabaseClient? get client => _initialized ? Supabase.instance.client : null;

  // Nota (Fase B5, 2026-07-20): los antiguos placeholders enqueue()/
  // flushQueue() fueron retirados. La cola persistente real vive en
  // SyncService (tabla local `sync_ops`, Drift v14): los inserts/updates
  // los cubre el sync por estado (la BD local ES la cola), y las
  // operaciones puntuales que fallan sin conexión (deletes remotos de la
  // papelera) se encolan en `sync_ops` y se procesan al inicio de cada
  // `SyncService.sincronizar()` — que el AutoSyncService dispara al
  // recuperar conectividad.
}
