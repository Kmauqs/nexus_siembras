// NEXUS Siembras — eliminación de cuenta de usuario.
//
// Flujo remoto: RPC `eliminar_mi_cuenta` (migración 0014) anonimiza
// reportes comunitarios de patologías, conserva variedades_comunitarias,
// borra datos privados vía CASCADE de auth.users y limpia storage.
// Luego el cliente decide si borra o conserva la BD Drift local.

import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/log.dart';
import '../data/database/database.dart';

class EliminarCuentaResultado {
  const EliminarCuentaResultado({
    required this.ok,
    this.reportesAnonimizados = 0,
    this.variedadesConservadas = 0,
    this.prediosConColaboradores = 0,
    this.error,
  });

  final bool ok;
  final int reportesAnonimizados;
  final int variedadesConservadas;
  final int prediosConColaboradores;
  final String? error;
}

class AccountService {
  AccountService(this.db);

  final AppDatabase db;

  SupabaseClient get _sb => Supabase.instance.client;

  /// Llama al RPC remoto. Debe ejecutarse con sesión activa.
  Future<EliminarCuentaResultado> eliminarCuentaRemota() async {
    if (_sb.auth.currentSession == null) {
      return const EliminarCuentaResultado(
        ok: false,
        error: 'No hay sesión iniciada',
      );
    }
    try {
      final raw = await _sb.rpc('eliminar_mi_cuenta');
      final map = raw is Map
          ? Map<String, dynamic>.from(raw)
          : <String, dynamic>{};
      return EliminarCuentaResultado(
        ok: map['ok'] == true,
        reportesAnonimizados:
            (map['reportes_anonimizados'] as num?)?.toInt() ?? 0,
        variedadesConservadas:
            (map['variedades_comunitarias_conservadas'] as num?)?.toInt() ??
                0,
        prediosConColaboradores:
            (map['predios_con_colaboradores'] as num?)?.toInt() ?? 0,
      );
    } on PostgrestException catch (e) {
      Log.w('[cuenta] eliminar_mi_cuenta: ${e.message}');
      return EliminarCuentaResultado(
        ok: false,
        error: e.message.contains('schema') || e.code == 'PGRST202'
            ? 'El servidor no tiene la función de eliminar cuenta '
                '(migración 0014). Actualiza el esquema remoto.'
            : e.message,
      );
    } catch (e) {
      Log.w('[cuenta] eliminar_mi_cuenta: $e');
      return EliminarCuentaResultado(ok: false, error: '$e');
    }
  }

  /// Borra dominio local + sync + config (mismo alcance que reset total).
  Future<void> borrarDatosLocales() async {
    await db.transaction(() async {
      await db.delete(db.tareasCompletadas).go();
      await db.delete(db.eventosCultivo).go();
      await db.delete(db.cosechasRegistradas).go();
      await db.delete(db.actividadesCustom).go();
      await db.delete(db.cultivoPatologias).go();
      await db.delete(db.cultivos).go();
      await db.delete(db.compras).go();
      await db.delete(db.inventarios).go();
      await db.delete(db.analisisSuelo).go();
      await db.delete(db.condicionesPredio).go();
      await db.delete(db.lotes).go();
      await db.delete(db.predioColaboradores).go();
      await db.delete(db.patologiasReportadas).go();
      await db.delete(db.predios).go();
      await db.delete(db.proveedores).go();
      await db.delete(db.syncMappings).go();
      await db.delete(db.syncTables).go();
      await db.delete(db.syncOps).go();
      // Revisión C2-3 (2026-08-03): la caché del banco comunitario también
      // se limpia — contenido público, pero el "reset total" debe serlo.
      await db.delete(db.variedadesComunitariasCache).go();
      await db.delete(db.configs).go();
    });
  }

  /// Si el usuario conserva datos locales tras borrar la cuenta en la
  /// nube, limpia mappings/cola para no intentar sync con IDs huérfanos.
  Future<void> limpiarEstadoSyncLocal() async {
    await db.transaction(() async {
      await db.delete(db.syncMappings).go();
      await db.delete(db.syncTables).go();
      await db.delete(db.syncOps).go();
    });
  }

  Future<void> cerrarSesionSilencioso() async {
    try {
      await _sb.auth.signOut();
    } catch (_) {}
  }
}
