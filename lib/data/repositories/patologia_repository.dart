import 'dart:convert';
import 'package:drift/drift.dart';
import '../database/database.dart';

class PatologiaRepository {
  PatologiaRepository(this.db);
  final AppDatabase db;

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

  /// Registra intervención: agrega nota + baja severidad a inicial (estado naranja).
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
    await (db.update(db.cultivoPatologias)..where((c) => c.id.equals(cpId)))
        .write(CultivoPatologiasCompanion(
      intervencionesJson: Value(jsonEncode(ivs)),
      severidad: const Value('inicial'),
      updatedAt: Value(now),
    ));
  }

  Future<void> marcarCurada(int cpId) async {
    final now = DateTime.now();
    await (db.update(db.cultivoPatologias)..where((c) => c.id.equals(cpId)))
        .write(CultivoPatologiasCompanion(
      curaFecha: Value(now),
      updatedAt: Value(now),
    ));
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
              ),
            );
      }
      return cpId;
    });
  }

  /// Elimina un reporte (soft-delete). No borra la copia comunitaria
  /// asociada; esa mantiene el valor epidemiológico ya publicado.
  Future<void> softDeleteReporte(int cpId) async {
    final now = DateTime.now();
    await (db.update(db.cultivoPatologias)..where((c) => c.id.equals(cpId)))
        .write(CultivoPatologiasCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }
}
