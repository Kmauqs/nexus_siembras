import 'package:drift/drift.dart';
import '../database/database.dart';

class AnalisisSueloRepository {
  AnalisisSueloRepository(this.db);
  final AppDatabase db;

  Stream<List<AnalisisSueloData>> watchByPredio(int predioId) {
    return (db.select(db.analisisSuelo)
          ..where((a) => a.predioId.equals(predioId))
          ..where((a) => a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.desc(a.fechaMuestreo)]))
        .watch();
  }

  /// Devuelve el análisis más útil para un cultivo. Estrategia:
  ///   1. Si `lote` no es vacío, busca el más reciente con ese lote exacto.
  ///   2. Si no hay match, busca el más reciente del predio sin filtrar lote
  ///      (asumiendo suelo homogéneo del predio).
  Future<AnalisisSueloData?> ultimoDelPredio(int predioId, {String? lote}) async {
    final loteTrim = lote?.trim();
    if (loteTrim != null && loteTrim.isNotEmpty) {
      final porLote = await (db.select(db.analisisSuelo)
            ..where((a) => a.predioId.equals(predioId))
            ..where((a) => a.deletedAt.isNull())
            ..where((a) => a.lote.equals(loteTrim))
            ..orderBy([(a) => OrderingTerm.desc(a.fechaMuestreo)])
            ..limit(1))
          .getSingleOrNull();
      if (porLote != null) return porLote;
    }
    return (db.select(db.analisisSuelo)
          ..where((a) => a.predioId.equals(predioId))
          ..where((a) => a.deletedAt.isNull())
          ..orderBy([(a) => OrderingTerm.desc(a.fechaMuestreo)])
          ..limit(1))
        .getSingleOrNull();
  }

  Future<AnalisisSueloData?> byId(int id) =>
      (db.select(db.analisisSuelo)..where((a) => a.id.equals(id)))
          .getSingleOrNull();

  Future<int> insert({
    required int predioId,
    required DateTime fechaMuestreo,
    String? lote,
    String? laboratorio,
    double? profundidadCm,
    String? textura,
    double? densidadGCm3,
    double? conductividadMsCm,
    double? ph,
    double? materiaOrganicaPct,
    double? nPpm,
    double? pPpm,
    double? kPpm,
    double? caMeq,
    double? mgMeq,
    double? naMeq,
    double? cicMeq,
    double? sPpm,
    double? bPpm,
    String? soportePath,
    String? soporteTipo,
    String? notas,
  }) =>
      db.into(db.analisisSuelo).insert(AnalisisSueloCompanion.insert(
            predioId: predioId,
            fechaMuestreo: fechaMuestreo,
            lote: Value(lote),
            laboratorio: Value(laboratorio),
            profundidadCm: Value(profundidadCm),
            textura: Value(textura),
            densidadGCm3: Value(densidadGCm3),
            conductividadMsCm: Value(conductividadMsCm),
            ph: Value(ph),
            materiaOrganicaPct: Value(materiaOrganicaPct),
            nPpm: Value(nPpm),
            pPpm: Value(pPpm),
            kPpm: Value(kPpm),
            caMeq: Value(caMeq),
            mgMeq: Value(mgMeq),
            naMeq: Value(naMeq),
            cicMeq: Value(cicMeq),
            sPpm: Value(sPpm),
            bPpm: Value(bPpm),
            soportePath: Value(soportePath),
            soporteTipo: Value(soporteTipo),
            notas: Value(notas),
          ));

  Future<void> update({
    required int id,
    required DateTime fechaMuestreo,
    String? lote,
    String? laboratorio,
    double? profundidadCm,
    String? textura,
    double? densidadGCm3,
    double? conductividadMsCm,
    double? ph,
    double? materiaOrganicaPct,
    double? nPpm,
    double? pPpm,
    double? kPpm,
    double? caMeq,
    double? mgMeq,
    double? naMeq,
    double? cicMeq,
    double? sPpm,
    double? bPpm,
    String? soportePath,
    String? soporteTipo,
    String? notas,
  }) =>
      (db.update(db.analisisSuelo)..where((a) => a.id.equals(id))).write(
        AnalisisSueloCompanion(
          fechaMuestreo: Value(fechaMuestreo),
          lote: Value(lote),
          laboratorio: Value(laboratorio),
          profundidadCm: Value(profundidadCm),
          textura: Value(textura),
          densidadGCm3: Value(densidadGCm3),
          conductividadMsCm: Value(conductividadMsCm),
          ph: Value(ph),
          materiaOrganicaPct: Value(materiaOrganicaPct),
          nPpm: Value(nPpm),
          pPpm: Value(pPpm),
          kPpm: Value(kPpm),
          caMeq: Value(caMeq),
          mgMeq: Value(mgMeq),
          naMeq: Value(naMeq),
          cicMeq: Value(cicMeq),
          sPpm: Value(sPpm),
          bPpm: Value(bPpm),
          soportePath: Value(soportePath),
          soporteTipo: Value(soporteTipo),
          notas: Value(notas),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> softDelete(int id) {
    final now = DateTime.now();
    return (db.update(db.analisisSuelo)..where((a) => a.id.equals(id))).write(
      AnalisisSueloCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
