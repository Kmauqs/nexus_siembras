import 'package:drift/drift.dart';
import '../../core/units/units_catalog.dart';
import '../database/database.dart';

class InventoryRepository {
  InventoryRepository(this.db);
  final AppDatabase db;

  /// Stream de ítems del predio activo (deleted_at IS NULL).
  Stream<List<Inventario>> watchByPredio(int predioId) {
    return (db.select(db.inventarios)
          ..where((i) => i.predioId.equals(predioId))
          ..where((i) => i.deletedAt.isNull())
          ..orderBy([(i) => OrderingTerm.desc(i.fecha)]))
        .watch();
  }

  Future<Inventario?> findByDescripcion(int predioId, String desc) async {
    return await (db.select(db.inventarios)
          ..where((i) => i.predioId.equals(predioId))
          ..where((i) => i.descripcion.lower().equals(desc.toLowerCase().trim()))
          ..where((i) => i.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
  }

  /// Suma al ítem existente (o crea nuevo). La `cantidad` está en la unidad
  /// del usuario; se convierte a base SI antes de persistir.
  Future<int> addOrIncrement({
    required int predioId,
    required String descripcion,
    required double cantidad,
    required String unidad,
    String? codigo,
    String? fabricante,
    DateTime? fecha,
  }) async {
    if (cantidad <= 0) return -1;
    final (baseVal, baseCode) = toBase(cantidad, unidad);
    final existing = await findByDescripcion(predioId, descripcion);
    if (existing != null) {
      // Los ítems siempre se almacenan en unidad base SI. Sumamos en base.
      await (db.update(db.inventarios)
            ..where((i) => i.id.equals(existing.id)))
          .write(InventariosCompanion(
        cantidadBase: Value(existing.cantidadBase + baseVal),
        fabricante: fabricante != null && fabricante.isNotEmpty
            ? Value(fabricante)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ));
      return existing.id;
    }
    return await db.into(db.inventarios).insert(InventariosCompanion.insert(
          predioId: predioId,
          fecha: fecha ?? DateTime.now(),
          descripcion: descripcion,
          codigo: Value(codigo),
          fabricante: Value(fabricante),
          cantidadBase: baseVal,
          unidadBase: baseCode,
        ));
  }

  /// Descuenta cantidad (en unidad del usuario) — convierte a base.
  Future<void> consume({
    required int predioId,
    required String descripcion,
    required double cantidad,
    String unidad = 'kg',
  }) async {
    if (cantidad <= 0) return;
    final (baseVal, _) = toBase(cantidad, unidad);
    await consumeBase(
        predioId: predioId, descripcion: descripcion, cantidadBase: baseVal);
  }

  /// Descuenta cantidad expresada ya en unidad base SI.
  Future<void> consumeBase({
    required int predioId,
    required String descripcion,
    required double cantidadBase,
  }) async {
    if (cantidadBase <= 0) return;
    final existing = await findByDescripcion(predioId, descripcion);
    if (existing == null) return;
    final nueva =
        (existing.cantidadBase - cantidadBase).clamp(0.0, double.infinity);
    await (db.update(db.inventarios)
          ..where((i) => i.id.equals(existing.id)))
        .write(InventariosCompanion(
      cantidadBase: Value(nueva.toDouble()),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> update(Inventario updated) async {
    await (db.update(db.inventarios)
          ..where((i) => i.id.equals(updated.id)))
        .write(InventariosCompanion(
      descripcion: Value(updated.descripcion),
      codigo: Value(updated.codigo),
      fabricante: Value(updated.fabricante),
      cantidadBase: Value(updated.cantidadBase),
      unidadBase: Value(updated.unidadBase),
      updatedAt: Value(DateTime.now()),
    ));
  }

  /// Update parcial por ID — solo modifica los campos que se pasen.
  Future<void> updateFields({
    required int id,
    String? descripcion,
    String? codigo,
    String? fabricante,
    double? cantidadBase,
    String? unidadBase,
  }) async {
    await (db.update(db.inventarios)..where((i) => i.id.equals(id))).write(
        InventariosCompanion(
      descripcion:
          descripcion != null ? Value(descripcion) : const Value.absent(),
      codigo: codigo != null ? Value(codigo) : const Value.absent(),
      fabricante:
          fabricante != null ? Value(fabricante) : const Value.absent(),
      cantidadBase:
          cantidadBase != null ? Value(cantidadBase) : const Value.absent(),
      unidadBase:
          unidadBase != null ? Value(unidadBase) : const Value.absent(),
      updatedAt: Value(DateTime.now()),
    ));
  }

  Future<void> softDelete(int id) async {
    final now = DateTime.now();
    await (db.update(db.inventarios)..where((i) => i.id.equals(id))).write(
      InventariosCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
