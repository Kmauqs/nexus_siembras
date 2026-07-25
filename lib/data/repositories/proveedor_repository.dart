import 'package:drift/drift.dart';
import '../database/database.dart';

class ProveedorRepository {
  ProveedorRepository(this.db);
  final AppDatabase db;

  Stream<List<Proveedore>> watchAll() {
    return (db.select(db.proveedores)
          ..where((p) => p.deletedAt.isNull())
          ..orderBy([(p) => OrderingTerm.asc(p.nombre)]))
        .watch();
  }

  Future<Proveedore?> findByNombre(String nombre) =>
      (db.select(db.proveedores)
            ..where((p) => p.nombre.equals(nombre))
            ..where((p) => p.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();

  Future<int> addIfMissing(String nombre) async {
    final existing = await findByNombre(nombre);
    if (existing != null) return existing.id;
    return await db.into(db.proveedores)
        .insert(ProveedoresCompanion.insert(nombre: nombre));
  }

  Future<int> insert({
    required String nombre,
    String? nit,
    String? telefono,
    String? email,
    String? web,
    String? direccion,
    String? notas,
  }) =>
      db.into(db.proveedores).insert(ProveedoresCompanion.insert(
            nombre: nombre,
            nit: Value(nit),
            telefono: Value(telefono),
            email: Value(email),
            web: Value(web),
            direccion: Value(direccion),
            notas: Value(notas),
          ));

  Future<void> update({
    required int id,
    required String nombre,
    String? nit,
    String? telefono,
    String? email,
    String? web,
    String? direccion,
    String? notas,
  }) =>
      (db.update(db.proveedores)..where((p) => p.id.equals(id))).write(
        ProveedoresCompanion(
          nombre: Value(nombre),
          nit: Value(nit),
          telefono: Value(telefono),
          email: Value(email),
          web: Value(web),
          direccion: Value(direccion),
          notas: Value(notas),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<void> softDelete(int id) {
    final now = DateTime.now();
    return (db.update(db.proveedores)..where((p) => p.id.equals(id))).write(
      ProveedoresCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
