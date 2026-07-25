import 'package:drift/drift.dart';
import '../database/database.dart';

class LoteRepository {
  LoteRepository(this.db);
  final AppDatabase db;

  Stream<List<Lote>> watchByPredio(int predioId) {
    return (db.select(db.lotes)
          ..where((l) => l.predioId.equals(predioId))
          ..where((l) => l.deletedAt.isNull())
          ..orderBy([(l) => OrderingTerm.asc(l.nombre)]))
        .watch();
  }

  Stream<List<Lote>> watchAll() {
    return (db.select(db.lotes)
          ..where((l) => l.deletedAt.isNull())
          ..orderBy([(l) => OrderingTerm.asc(l.nombre)]))
        .watch();
  }

  Future<Lote?> byId(int id) =>
      (db.select(db.lotes)..where((l) => l.id.equals(id))).getSingleOrNull();

  Future<int> insert({
    required int predioId,
    required String nombre,
    String? administrador,
    double? altitudMsnm,
    double? areaM2,
    String? poligonoGeoJson,
    String? notas,
  }) =>
      db.into(db.lotes).insert(LotesCompanion.insert(
            predioId: predioId,
            nombre: nombre,
            administrador: Value(administrador),
            altitudMsnm: Value(altitudMsnm),
            areaM2: Value(areaM2),
            poligonoGeoJson: Value(poligonoGeoJson),
            notas: Value(notas),
          ));

  Future<void> update({
    required int id,
    required String nombre,
    String? administrador,
    double? altitudMsnm,
    double? areaM2,
    String? poligonoGeoJson,
    String? notas,
  }) =>
      (db.update(db.lotes)..where((l) => l.id.equals(id))).write(
        LotesCompanion(
          nombre: Value(nombre),
          administrador: Value(administrador),
          altitudMsnm: Value(altitudMsnm),
          areaM2: Value(areaM2),
          poligonoGeoJson: Value(poligonoGeoJson),
          notas: Value(notas),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> softDelete(int id) {
    final now = DateTime.now();
    return (db.update(db.lotes)..where((l) => l.id.equals(id))).write(
      LotesCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
