import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/database.dart';

class PatologiaRepository {
  PatologiaRepository(this.db);
  final AppDatabase db;

  /// Prefijo de `eventos_cultivo.notas` para marcar eventos generados por
  /// patologías. `resincronizarEventos` los conserva al regenerar el
  /// cronograma proyectado (siembra/abonos/cosechas).
  static const notasOrigenPatologia = 'origen=patologia';

  static String notasEventoPatologia(int cpId) =>
      '$notasOrigenPatologia;cp=$cpId';

  static bool esEventoPatologia(String? notas) =>
      (notas ?? '').startsWith(notasOrigenPatologia);

  Stream<List<Patologia>> watchCatalogo() =>
      (db.select(db.patologias)
            ..where((p) => p.deletedAt.isNull())
            ..orderBy([(p) => OrderingTerm.asc(p.nombreComun)]))
          .watch();

  /// Devuelve el mapa `patologiaId -> lista de nombres de plantas afectadas`
  /// según planta_patologias. Solo considera plantas no eliminadas.
  Stream<Map<int, List<String>>> watchPatologiasPorPlantas() {
    final query = db.select(db.plantaPatologias).join([
      innerJoin(db.plantas,
          db.plantas.id.equalsExp(db.plantaPatologias.plantaId)),
    ])
      ..where(db.plantas.deletedAt.isNull());
    return query.watch().map((rows) {
      final map = <int, List<String>>{};
      for (final row in rows) {
        final pp = row.readTable(db.plantaPatologias);
        final planta = row.readTable(db.plantas);
        (map[pp.patologiaId] ??= []).add(planta.nombreComun);
      }
      return map;
    });
  }

  Stream<List<CultivoPatologia>> watchActivasPredio(List<int> cultivoIds) {
    if (cultivoIds.isEmpty) {
      return const Stream<List<CultivoPatologia>>.empty();
    }
    return (db.select(db.cultivoPatologias)
          ..where((cp) => cp.cultivoId.isIn(cultivoIds))
          ..where((cp) => cp.curaFecha.isNull())
          ..where((cp) => cp.deletedAt.isNull())
          ..orderBy([(cp) => OrderingTerm.desc(cp.fechaDeteccion)]))
        .watch();
  }

  Stream<List<CultivoPatologia>> watchHistoricoPredio(List<int> cultivoIds) {
    if (cultivoIds.isEmpty) {
      return const Stream<List<CultivoPatologia>>.empty();
    }
    return (db.select(db.cultivoPatologias)
          ..where((cp) => cp.cultivoId.isIn(cultivoIds))
          ..where((cp) => cp.curaFecha.isNotNull())
          ..where((cp) => cp.deletedAt.isNull())
          ..orderBy([(cp) => OrderingTerm.desc(cp.curaFecha)]))
        .watch();
  }

  Stream<List<PlantaPatologia>> watchPlantaPatologias() =>
      db.select(db.plantaPatologias).watch();

  /// Reclasifica una patología del catálogo en otro grupo. `tipoManual = null`
  /// devuelve la patología a su agrupación automática.
  ///
  /// No toca `tipo`: el catálogo lo sobrescribe en cada "Actualizar", así que
  /// la elección del usuario debe vivir aparte para sobrevivir.
  Future<void> reclasificar({
    required int patologiaId,
    required String? tipoManual,
  }) async {
    await (db.update(db.patologias)..where((p) => p.id.equals(patologiaId)))
        .write(PatologiasCompanion(
      tipoManual: Value(tipoManual),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Registra intervención: agrega nota + baja severidad a inicial (estado naranja)
  /// y crea un evento `control_fito` ejecutado en el cronograma del cultivo.
  Future<void> registrarIntervencion({
    required int cpId,
    required DateTime fecha,
    required String nota,
  }) async {
    final row = await (db.select(db.cultivoPatologias)
          ..where((c) => c.id.equals(cpId)))
        .getSingleOrNull();
    if (row == null) return;
    List<dynamic> ivs = [];
    try {
      ivs = jsonDecode(row.intervencionesJson) as List<dynamic>;
    } catch (_) {}
    ivs.add({'fecha': fecha.toIso8601String(), 'nota': nota});
    final now = DateTime.now();
    final nombre = await _nombrePatologiaDe(row);
    await db.transaction(() async {
      await (db.update(db.cultivoPatologias)..where((c) => c.id.equals(cpId)))
          .write(CultivoPatologiasCompanion(
        intervencionesJson: Value(jsonEncode(ivs)),
        severidad: const Value('inicial'),
        updatedAt: Value(now),
      ));
      await _insertEventoPatologia(
        cultivoId: row.cultivoId,
        cpId: cpId,
        tipo: 'control_fito',
        fecha: fecha,
        descripcion: 'Intervención: $nombre · ${nota.trim()}',
      );
    });
  }

  /// Marca la detección como curada y registra un evento en el cronograma.
  Future<void> marcarCurada(int cpId) async {
    final row = await (db.select(db.cultivoPatologias)
          ..where((c) => c.id.equals(cpId)))
        .getSingleOrNull();
    if (row == null) return;
    final now = DateTime.now();
    final nombre = await _nombrePatologiaDe(row);
    await db.transaction(() async {
      await (db.update(db.cultivoPatologias)..where((c) => c.id.equals(cpId)))
          .write(CultivoPatologiasCompanion(
        curaFecha: Value(now),
        updatedAt: Value(now),
      ));
      await _insertEventoPatologia(
        cultivoId: row.cultivoId,
        cpId: cpId,
        tipo: 'observacion',
        fecha: now,
        descripcion: 'Patología curada: $nombre',
      );
    });
  }

  // ============================================================
  // Fase 3e-5 — Reporte de patologías con foto + GNSS
  // ============================================================

  /// Registra un reporte de patología. Inserta en `CultivoPatologias`,
  /// y si `compartirAComunidad=true` también crea una entrada anonimizada
  /// en `PatologiasReportadas` (denormalizada: nombre de patología y de
  /// planta ya guardados como texto — el catálogo comunitario no depende
  /// de los IDs locales del usuario).
  ///
  /// Retorna el ID del `CultivoPatologias` creado.
  Future<int> reportarPatologia({
    required int cultivoId,
    required int patologiaId,
    required DateTime fechaDeteccion,
    required String severidad, // inicial | avanzada
    String? fotoPath,
    double? lat,
    double? lng,
    double? altM,
    String? notas,
    required bool compartirAComunidad,
    // Denormalización opcional para el reporte comunitario:
    String? patologiaNombre,
    String? patologiaCientifico,
    String? plantaNombre,
    String? paisIso2,
    String? regionNombre,
    String? municipioNombre,
  }) async {
    return await db.transaction<int>(() async {
      final cpId = await db.into(db.cultivoPatologias).insert(
            CultivoPatologiasCompanion.insert(
              cultivoId: cultivoId,
              patologiaId: Value(patologiaId),
              patologiaNombre: Value(patologiaNombre),
              fechaDeteccion: fechaDeteccion,
              severidad: Value(severidad),
              fotoPath: Value(fotoPath),
              fuenteDiagnostico: const Value('manual'),
              notas: Value(notas),
              lat: Value(lat),
              lng: Value(lng),
              altM: Value(altM),
              compartida: Value(compartirAComunidad),
            ),
          );
      if (compartirAComunidad && lat != null && lng != null) {
        await db.into(db.patologiasReportadas).insert(
              PatologiasReportadasCompanion.insert(
                cultivoPatologiaId: Value(cpId),
                patologiaNombre: patologiaNombre ?? '',
                patologiaCientifico: Value(patologiaCientifico),
                plantaNombre: Value(plantaNombre),
                lat: lat,
                lng: lng,
                altM: Value(altM),
                fechaDeteccion: fechaDeteccion,
                severidad: Value(severidad),
                sintomas: Value(notas),
                fotoLocalPath: Value(fotoPath),
                paisIso2: Value(paisIso2),
                regionNombre: Value(regionNombre),
                municipioNombre: Value(municipioNombre),
                ultimaActividadAt: Value(fechaDeteccion),
              ),
            );
      }
      final nombre = (patologiaNombre?.trim().isNotEmpty == true)
          ? patologiaNombre!.trim()
          : 'Patología #$patologiaId';
      final sevLabel = severidad == 'avanzada' ? 'avanzada' : 'inicial';
      final desc = notas != null && notas.trim().isNotEmpty
          ? 'Patología detectada: $nombre · $sevLabel · ${notas.trim()}'
          : 'Patología detectada: $nombre · $sevLabel';
      await _insertEventoPatologia(
        cultivoId: cultivoId,
        cpId: cpId,
        tipo: 'observacion',
        fecha: fechaDeteccion,
        descripcion: desc,
      );
      return cpId;
    });
  }

  /// Elimina un reporte (soft-delete) y sus eventos de cronograma asociados.
  /// No borra la copia comunitaria; esa mantiene el valor epidemiológico.
  Future<void> softDeleteReporte(int cpId) async {
    final now = DateTime.now();
    await db.transaction(() async {
      await (db.update(db.cultivoPatologias)..where((c) => c.id.equals(cpId)))
          .write(CultivoPatologiasCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
      final prefijo = '${notasEventoPatologia(cpId)}%';
      await (db.update(db.eventosCultivo)
            ..where((e) => e.notas.like(prefijo))
            ..where((e) => e.deletedAt.isNull()))
          .write(EventosCultivoCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ));
    });
  }

  Future<String> _nombrePatologiaDe(CultivoPatologia row) async {
    final denorm = row.patologiaNombre?.trim();
    if (denorm != null && denorm.isNotEmpty) return denorm;
    final id = row.patologiaId;
    if (id != null) {
      final p = await (db.select(db.patologias)
            ..where((x) => x.id.equals(id))
            ..limit(1))
          .getSingleOrNull();
      if (p != null) return p.nombreComun;
    }
    return 'Patología';
  }

  /// Evento ya ejecutado ligado a una detección (aparece en Gantt, calendario
  /// y cronograma del cultivo; se sincroniza con `_pushEventos`).
  Future<void> _insertEventoPatologia({
    required int cultivoId,
    required int cpId,
    required String tipo,
    required DateTime fecha,
    required String descripcion,
  }) async {
    final day = DateTime(fecha.year, fecha.month, fecha.day);
    await db.into(db.eventosCultivo).insert(EventosCultivoCompanion.insert(
          cultivoId: cultivoId,
          tipo: tipo,
          fechaProgramada: Value(day),
          fechaEjecutada: Value(day),
          descripcion: Value(descripcion),
          notas: Value(notasEventoPatologia(cpId)),
        ));
  }
}
