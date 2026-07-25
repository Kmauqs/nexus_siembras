import 'package:drift/drift.dart';
import '../database/database.dart';

class CondicionesPredioRepository {
  CondicionesPredioRepository(this.db);
  final AppDatabase db;

  Stream<CondicionesPredioData?> watchByPredio(int predioId) {
    return (db.select(db.condicionesPredio)
          ..where((c) => c.predioId.equals(predioId))
          ..where((c) => c.deletedAt.isNull())
          ..limit(1))
        .watchSingleOrNull();
  }

  Future<CondicionesPredioData?> byPredio(int predioId) =>
      (db.select(db.condicionesPredio)
            ..where((c) => c.predioId.equals(predioId))
            ..where((c) => c.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();

  /// Upsert: si no existe fila para el predio, la crea; si existe, la actualiza.
  Future<void> upsert({
    required int predioId,
    double? altitudMsnm,
    double? precipitacionAnualMm,
    double? tempMediaC,
    double? tempMinC,
    double? tempMaxC,
    double? humedadRelativaPct,
    String? zonaClimatica,
    String? pisoTermico,
    String? fuente,
    String? notas,
  }) async {
    final existing = await byPredio(predioId);
    final now = DateTime.now();
    if (existing == null) {
      await db.into(db.condicionesPredio).insert(
            CondicionesPredioCompanion.insert(
              predioId: predioId,
              altitudMsnm: Value(altitudMsnm),
              precipitacionAnualMm: Value(precipitacionAnualMm),
              tempMediaC: Value(tempMediaC),
              tempMinC: Value(tempMinC),
              tempMaxC: Value(tempMaxC),
              humedadRelativaPct: Value(humedadRelativaPct),
              zonaClimatica: Value(zonaClimatica),
              pisoTermico: Value(pisoTermico),
              fuente: Value(fuente),
              notas: Value(notas),
              fechaActualizacion: Value(now),
            ),
          );
    } else {
      await (db.update(db.condicionesPredio)
            ..where((c) => c.id.equals(existing.id)))
          .write(CondicionesPredioCompanion(
        altitudMsnm: Value(altitudMsnm),
        precipitacionAnualMm: Value(precipitacionAnualMm),
        tempMediaC: Value(tempMediaC),
        tempMinC: Value(tempMinC),
        tempMaxC: Value(tempMaxC),
        humedadRelativaPct: Value(humedadRelativaPct),
        zonaClimatica: Value(zonaClimatica),
        pisoTermico: Value(pisoTermico),
        fuente: Value(fuente),
        notas: Value(notas),
        fechaActualizacion: Value(now),
        updatedAt: Value(now),
      ));
    }
  }
}
