// Utilidades de mantenimiento de la base de datos.
//
// Casos de uso:
//   1. Depurar local: elimina permanentemente todas las filas con
//      `deleted_at != null` de todas las tablas, incluso las que no
//      aparecen en la Papelera (eventos_cultivo, condiciones_predio,
//      registros huérfanos, etc.).
//
//   2. Reemplazar nube: elimina TODOS los datos del usuario en Supabase
//      y sube el estado local depurado. Útil cuando la nube quedó en un
//      estado inconsistente y el local es la fuente de verdad.
//
// Ambas operaciones son destructivas — la UI debe pedir confirmación.

import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../data/database/database.dart';
import 'sync_service.dart';

/// Estadísticas de filas con soft-delete pendientes por tabla local.
class SoftDeleteStats {
  final Map<String, int> porTabla;
  final int total;
  const SoftDeleteStats(this.porTabla) : total = 0;
  factory SoftDeleteStats.from(Map<String, int> map) {
    return SoftDeleteStats._(
      map,
      map.values.fold(0, (a, b) => a + b),
    );
  }
  const SoftDeleteStats._(this.porTabla, this.total);
}

class MaintenanceResult {
  final int depuradosLocal;
  final int borradosRemoto;
  final int subidos;
  final String? error;
  final Duration duracion;
  const MaintenanceResult({
    required this.depuradosLocal,
    required this.borradosRemoto,
    required this.subidos,
    this.error,
    required this.duracion,
  });
  bool get exito => error == null;
}

class MaintenanceService {
  MaintenanceService(this.db, this.sync);
  final AppDatabase db;
  final SyncService sync;
  SupabaseClient get _sb => Supabase.instance.client;

  /// Tablas locales con soft-delete que sincronizan a Supabase.
  /// El String es el nombre de la tabla REMOTA.
  static const _tablasSync = <String>[
    'predios',
    'lotes',
    'proveedores',
    'cultivos',
    'inventarios',
    'compras',
    'analisis_suelo',
    'eventos_cultivo',
    'condiciones_predio',
    // tareas_completadas no tiene deleted_at
  ];

  // ============================================================
  // ESTADÍSTICAS
  // ============================================================

  /// Cuenta filas con `deleted_at != null` en cada tabla local.
  Future<SoftDeleteStats> contarSoftDeletes() async {
    final map = <String, int>{};
    map['predios'] = (await (db.select(db.predios)
              ..where((t) => t.deletedAt.isNotNull()))
            .get())
        .length;
    map['lotes'] = (await (db.select(db.lotes)
              ..where((t) => t.deletedAt.isNotNull()))
            .get())
        .length;
    map['proveedores'] = (await (db.select(db.proveedores)
              ..where((t) => t.deletedAt.isNotNull()))
            .get())
        .length;
    map['cultivos'] = (await (db.select(db.cultivos)
              ..where((t) => t.deletedAt.isNotNull()))
            .get())
        .length;
    map['inventarios'] = (await (db.select(db.inventarios)
              ..where((t) => t.deletedAt.isNotNull()))
            .get())
        .length;
    map['compras'] = (await (db.select(db.compras)
              ..where((t) => t.deletedAt.isNotNull()))
            .get())
        .length;
    map['analisis_suelo'] = (await (db.select(db.analisisSuelo)
              ..where((t) => t.deletedAt.isNotNull()))
            .get())
        .length;
    map['eventos_cultivo'] = (await (db.select(db.eventosCultivo)
              ..where((t) => t.deletedAt.isNotNull()))
            .get())
        .length;
    map['condiciones_predio'] = (await (db.select(db.condicionesPredio)
              ..where((t) => t.deletedAt.isNotNull()))
            .get())
        .length;
    map.removeWhere((_, v) => v == 0);
    return SoftDeleteStats.from(map);
  }

  // ============================================================
  // DEPURAR LOCAL
  // ============================================================

  /// Elimina permanentemente TODAS las filas con `deleted_at != null`
  /// de todas las tablas. Retorna el total de filas eliminadas.
  Future<int> depurarLocal() async {
    var total = 0;
    total += await (db.delete(db.predios)
          ..where((t) => t.deletedAt.isNotNull()))
        .go();
    total += await (db.delete(db.lotes)
          ..where((t) => t.deletedAt.isNotNull()))
        .go();
    total += await (db.delete(db.proveedores)
          ..where((t) => t.deletedAt.isNotNull()))
        .go();
    total += await (db.delete(db.cultivos)
          ..where((t) => t.deletedAt.isNotNull()))
        .go();
    total += await (db.delete(db.inventarios)
          ..where((t) => t.deletedAt.isNotNull()))
        .go();
    total += await (db.delete(db.compras)
          ..where((t) => t.deletedAt.isNotNull()))
        .go();
    total += await (db.delete(db.analisisSuelo)
          ..where((t) => t.deletedAt.isNotNull()))
        .go();
    total += await (db.delete(db.eventosCultivo)
          ..where((t) => t.deletedAt.isNotNull()))
        .go();
    total += await (db.delete(db.condicionesPredio)
          ..where((t) => t.deletedAt.isNotNull()))
        .go();
    return total;
  }

  // ============================================================
  // WIPE NUBE
  // ============================================================

  /// Elimina TODOS los registros del usuario logueado en Supabase.
  /// Devuelve total borrado (aproximado — PostgREST no devuelve conteo real).
  Future<int> wipeRemoto() async {
    if (_sb.auth.currentSession == null) {
      throw StateError('No hay sesión iniciada');
    }
    final userId = _sb.auth.currentUser!.id;
    var total = 0;
    // Orden inverso al topológico para evitar problemas con FKs
    // (aunque RLS + CASCADE del schema ya cubre esto).
    for (final tabla in [
      'tareas_completadas',
      'eventos_cultivo',
      'compras',
      'analisis_suelo',
      'inventarios',
      'condiciones_predio',
      'cultivos',
      'lotes',
      'predios',
      'proveedores',
    ]) {
      try {
        await _sb.from(tabla).delete().eq('owner_id', userId);
        total++;
      } catch (_) {
        // continúa con la siguiente tabla
      }
    }
    return total;
  }

  // ============================================================
  // RESET SYNC STATE
  // ============================================================

  /// Limpia mappings y timestamps de sincronización. Después de esto el
  /// próximo sync sube todo local y baja todo remoto como si fuera la
  /// primera vez.
  Future<void> resetearSync() async {
    await db.delete(db.syncMappings).go();
    await db.delete(db.syncTables).go();
  }

  // ============================================================
  // OPERACIÓN COMPLETA: DEPURAR + REEMPLAZAR NUBE
  // ============================================================

  /// Ejecuta el ciclo completo:
  ///   1. Depurar local (hard-delete de todos los soft-deletes).
  ///   2. Wipe remoto (borrar todo lo del usuario en Supabase).
  ///   3. Resetear sync state.
  ///   4. Push completo (sube todo local a la nube limpia).
  Future<MaintenanceResult> reemplazarNubeConLocal() async {
    final start = DateTime.now();
    if (_sb.auth.currentSession == null) {
      return MaintenanceResult(
        depuradosLocal: 0,
        borradosRemoto: 0,
        subidos: 0,
        error: 'No hay sesión iniciada',
        duracion: DateTime.now().difference(start),
      );
    }
    try {
      final depurados = await depurarLocal();
      final tablasBorradas = await wipeRemoto();
      await resetearSync();
      // Full push (no importa el pull — la nube está vacía)
      final syncRes = await sync.sincronizar();
      return MaintenanceResult(
        depuradosLocal: depurados,
        borradosRemoto: tablasBorradas,
        subidos: syncRes.pushed,
        duracion: DateTime.now().difference(start),
      );
    } catch (e) {
      return MaintenanceResult(
        depuradosLocal: 0,
        borradosRemoto: 0,
        subidos: 0,
        error: '$e',
        duracion: DateTime.now().difference(start),
      );
    }
  }
}
