import 'package:drift/drift.dart';
import '../database/database.dart';

class ColaboradorRepository {
  ColaboradorRepository(this.db);
  final AppDatabase db;

  Stream<List<PredioColaboradore>> watchPorPredio(int predioId) {
    return (db.select(db.predioColaboradores)
          ..where((c) => c.predioId.equals(predioId))
          ..where((c) => c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.asc(c.invitadoAt)]))
        .watch();
  }

  Stream<List<PredioColaboradore>> watchTodos() {
    return (db.select(db.predioColaboradores)
          ..where((c) => c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.asc(c.invitadoAt)]))
        .watch();
  }

  Future<int> insert({
    required int predioId,
    required String email,
    String? userId,
    required String rol,
    DateTime? aceptadoAt,
  }) =>
      db.into(db.predioColaboradores).insert(
            PredioColaboradoresCompanion.insert(
              predioId: predioId,
              colaboradorEmail: email,
              colaboradorUserId: Value(userId),
              rol: rol,
              aceptadoAt: Value(aceptadoAt),
            ),
          );

  Future<void> actualizarRol({
    required int id,
    required String rol,
  }) {
    final now = DateTime.now();
    return (db.update(db.predioColaboradores)..where((c) => c.id.equals(id)))
        .write(PredioColaboradoresCompanion(
      rol: Value(rol),
      updatedAt: Value(now),
    ));
  }

  Future<void> softDelete(int id) {
    final now = DateTime.now();
    return (db.update(db.predioColaboradores)..where((c) => c.id.equals(id)))
        .write(PredioColaboradoresCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
    ));
  }
}
