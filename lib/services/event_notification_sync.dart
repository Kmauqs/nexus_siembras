// Sincroniza los eventos programados de cultivos con las notificaciones
// locales del sistema. Se ejecuta al arrancar la app y cada vez que cambia
// un evento (crear cultivo, registrar tarea, etc.).

import 'package:drift/drift.dart';
import '../data/database/database.dart';
import 'notification_service.dart';

class EventNotificationSync {
  EventNotificationSync(this.db);
  final AppDatabase db;

  /// Reprograma todas las notificaciones para eventos futuros no ejecutados
  /// del predio activo. Estrategia:
  ///
  /// 1. Cancela todas las notificaciones previas.
  /// 2. Lee la config: `notificacionesHabilitadas` y `notificacionAntelacionDias`.
  /// 3. Consulta eventos futuros no ejecutados de cultivos activos.
  /// 4. Para cada evento programa una alerta a las 8:00 AM del día
  ///    (fechaProgramada − antelacionDias).
  Future<int> sincronizar() async {
    final notif = NotificationService.instance;
    if (!notif.soportado) return 0;

    // Config
    final cfg = await db.select(db.configs).getSingleOrNull();
    if (cfg == null || !cfg.notificacionesHabilitadas) {
      await notif.cancelarTodas();
      return 0;
    }
    final antelacion = cfg.notificacionAntelacionDias;
    final predioActivoId = cfg.predioActivoId;
    if (predioActivoId == null) return 0;

    // Cancelamos todo y reprogramamos
    await notif.cancelarTodas();

    // Query: eventos futuros de cultivos activos del predio,
    // no ejecutados, no eliminados.
    final ahora = DateTime.now();
    final query = db.select(db.eventosCultivo).join([
      innerJoin(db.cultivos,
          db.cultivos.id.equalsExp(db.eventosCultivo.cultivoId)),
      leftOuterJoin(
          db.plantas, db.plantas.id.equalsExp(db.cultivos.plantaId)),
    ]);

    query.where(db.cultivos.predioId.equals(predioActivoId));
    query.where(db.cultivos.deletedAt.isNull());
    query.where(db.cultivos.finalizadoFecha.isNull());
    query.where(db.eventosCultivo.deletedAt.isNull());
    query.where(db.eventosCultivo.fechaEjecutada.isNull());
    query.where(db.eventosCultivo.fechaProgramada
        .isBiggerOrEqualValue(ahora.subtract(const Duration(days: 1))));

    query.orderBy([
      OrderingTerm.asc(db.eventosCultivo.fechaProgramada),
    ]);

    final rows = await query.get();

    var programadas = 0;
    for (final r in rows) {
      final ev = r.readTable(db.eventosCultivo);
      final cul = r.readTable(db.cultivos);
      final pl = r.readTableOrNull(db.plantas);
      if (ev.fechaProgramada == null) continue;
      final fechaEvento = ev.fechaProgramada!;

      // Aviso a las 8:00 AM del día (fecha − antelacion)
      final fechaAviso = DateTime(
        fechaEvento.year,
        fechaEvento.month,
        fechaEvento.day,
        8, 0, 0,
      ).subtract(Duration(days: antelacion));

      // Si el aviso ya pasó, no programa
      if (fechaAviso.isBefore(ahora)) continue;

      final actividad = ev.descripcion ?? _tituloDeTipo(ev.tipo);
      final plantaNombre = pl?.nombreComun ?? 'cultivo';
      final loteNombre = cul.nombreLote ?? '';
      final loteSufijo = loteNombre.isEmpty ? '' : ' · $loteNombre';

      final titulo = '🌱 $actividad';
      final cuerpo =
          'En $antelacion día(s): $plantaNombre$loteSufijo · ${_fmtFecha(fechaEvento)}';

      // ID único: usa el eventoId (int, único en la tabla)
      await notif.programar(
        id: ev.id,
        cuando: fechaAviso,
        titulo: titulo,
        cuerpo: cuerpo,
        payload: 'evento:${ev.id}:cultivo:${cul.id}',
      );
      programadas++;
    }
    return programadas;
  }

  String _tituloDeTipo(String tipo) {
    switch (tipo) {
      case 'siembra':
        return 'Siembra';
      case 'semillero':
        return 'Semillero';
      case 'trasplante':
        return 'Trasplante';
      case 'abono':
        return 'Abono';
      case 'control_fito':
        return 'Control fitosanitario';
      case 'cosecha':
        return 'Cosecha';
      case 'riego':
        return 'Riego';
      case 'poda':
        return 'Poda';
      default:
        return 'Actividad programada';
    }
  }

  String _fmtFecha(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}
