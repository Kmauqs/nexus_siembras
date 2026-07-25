import 'package:drift/drift.dart';
import '../database/database.dart';

class PredioRepository {
  PredioRepository(this.db);
  final AppDatabase db;

  Stream<List<Predio>> watchAll() {
    return (db.select(db.predios)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
        .watch();
  }

  Future<int?> getActiveId() async {
    final cfg = await db.select(db.configs).getSingleOrNull();
    return cfg?.predioActivoId;
  }

  Future<int> insert({
    required String nombre,
    String? propietario,
    int? paisId,
    int? regionId,
    int? municipioId,
    double? lat,
    double? lng,
    double? altM,
    String? notas,
  }) =>
      db.into(db.predios).insert(PrediosCompanion.insert(
            nombre: nombre,
            propietario: Value(propietario),
            paisId: Value(paisId),
            regionId: Value(regionId),
            municipioId: Value(municipioId),
            lat: Value(lat),
            lng: Value(lng),
            altM: Value(altM),
            notas: Value(notas),
          ));

  Future<void> update({
    required int id,
    required String nombre,
    String? propietario,
    int? paisId,
    int? regionId,
    int? municipioId,
    double? lat,
    double? lng,
    double? altM,
    String? notas,
  }) =>
      (db.update(db.predios)..where((p) => p.id.equals(id))).write(
        PrediosCompanion(
          nombre: Value(nombre),
          propietario: Value(propietario),
          paisId: Value(paisId),
          regionId: Value(regionId),
          municipioId: Value(municipioId),
          lat: Value(lat),
          lng: Value(lng),
          altM: Value(altM),
          notas: Value(notas),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> softDelete(int id) {
    final now = DateTime.now();
    // updatedAt también se toca para que el sync detecte el cambio.
    return (db.update(db.predios)..where((p) => p.id.equals(id))).write(
      PrediosCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
  }

  Future<Predio?> byId(int id) =>
      (db.select(db.predios)..where((p) => p.id.equals(id)))
          .getSingleOrNull();
}
