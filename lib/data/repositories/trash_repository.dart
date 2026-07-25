// NEXUS Siembras — Repositorio de Papelera
// Agrega ítems soft-deleted de TODAS las tablas con deletedAt y expone
// acciones de restaurar / borrar permanentemente.

import 'package:drift/drift.dart';
import '../database/database.dart';

class TrashItem {
  const TrashItem({
    required this.tipo,
    required this.id,
    required this.descripcion,
    required this.fechaEliminacion,
  });
  final String tipo;
  final int id;
  final String descripcion;
  final DateTime fechaEliminacion;
}

class TrashRepository {
  TrashRepository(this.db);
  final AppDatabase db;

  /// Combina los soft-deleted del predio en una lista unificada.
  /// Incluye también entidades sin predio_id (predios, proveedores).
  Stream<List<TrashItem>> watchByPredio(int predioId) async* {
    while (true) {
      final list = await getByPredio(predioId);
      yield list;
      await Future<void>.delayed(const Duration(seconds: 2));
    }
  }

  Future<List<TrashItem>> getByPredio(int predioId) async {
    // Cultivos del predio
    final cultivos = await (db.select(db.cultivos)
          ..where((c) => c.predioId.equals(predioId))
          ..where((c) => c.deletedAt.isNotNull()))
        .get();
    final compras = await (db.select(db.compras)
          ..where((c) => c.predioId.equals(predioId))
          ..where((c) => c.deletedAt.isNotNull()))
        .get();
    final invs = await (db.select(db.inventarios)
          ..where((i) => i.predioId.equals(predioId))
          ..where((i) => i.deletedAt.isNotNull()))
        .get();
    final lotes = await (db.select(db.lotes)
          ..where((l) => l.predioId.equals(predioId))
          ..where((l) => l.deletedAt.isNotNull()))
        .get();
    final analisis = await (db.select(db.analisisSuelo)
          ..where((a) => a.predioId.equals(predioId))
          ..where((a) => a.deletedAt.isNotNull()))
        .get();
    // Predios y proveedores no son "del predio activo" pero conviene
    // listarlos igual en la papelera para poder restaurarlos.
    final predios = await (db.select(db.predios)
          ..where((p) => p.deletedAt.isNotNull()))
        .get();
    final proveedores = await (db.select(db.proveedores)
          ..where((p) => p.deletedAt.isNotNull()))
        .get();

    final items = <TrashItem>[
      for (final c in cultivos)
        TrashItem(
          tipo: 'cultivo', id: c.id,
          descripcion: 'Cultivo · ${c.nombreLote ?? "?"}',
          fechaEliminacion: c.deletedAt ?? DateTime.now(),
        ),
      for (final c in compras)
        TrashItem(
          tipo: 'compra', id: c.id,
          descripcion: 'Compra · ${c.descripcion1}',
          fechaEliminacion: c.deletedAt ?? DateTime.now(),
        ),
      for (final i in invs)
        TrashItem(
          tipo: 'inventario', id: i.id,
          descripcion: 'Inventario · ${i.descripcion}',
          fechaEliminacion: i.deletedAt ?? DateTime.now(),
        ),
      for (final l in lotes)
        TrashItem(
          tipo: 'lote', id: l.id,
          descripcion: 'Lote · ${l.nombre}',
          fechaEliminacion: l.deletedAt ?? DateTime.now(),
        ),
      for (final a in analisis)
        TrashItem(
          tipo: 'analisis', id: a.id,
          descripcion: 'Análisis · ${_iso(a.fechaMuestreo)}'
              '${a.lote != null ? " · ${a.lote}" : ""}',
          fechaEliminacion: a.deletedAt ?? DateTime.now(),
        ),
      for (final p in predios)
        TrashItem(
          tipo: 'predio', id: p.id,
          descripcion: 'Predio · ${p.nombre}',
          fechaEliminacion: p.deletedAt ?? DateTime.now(),
        ),
      for (final p in proveedores)
        TrashItem(
          tipo: 'proveedor', id: p.id,
          descripcion: 'Proveedor · ${p.nombre}',
          fechaEliminacion: p.deletedAt ?? DateTime.now(),
        ),
    ];
    items.sort((a, b) => b.fechaEliminacion.compareTo(a.fechaEliminacion));
    return items;
  }

  Future<void> restore(String tipo, int id) async {
    final now = DateTime.now();
    switch (tipo) {
      case 'cultivo':
        await (db.update(db.cultivos)..where((c) => c.id.equals(id))).write(
          CultivosCompanion(
              deletedAt: const Value(null), updatedAt: Value(now)),
        );
        break;
      case 'compra':
        await (db.update(db.compras)..where((c) => c.id.equals(id))).write(
          ComprasCompanion(
              deletedAt: const Value(null), updatedAt: Value(now)),
        );
        break;
      case 'inventario':
        await (db.update(db.inventarios)..where((i) => i.id.equals(id))).write(
          InventariosCompanion(
              deletedAt: const Value(null), updatedAt: Value(now)),
        );
        break;
      case 'lote':
        await (db.update(db.lotes)..where((l) => l.id.equals(id))).write(
          LotesCompanion(
              deletedAt: const Value(null), updatedAt: Value(now)),
        );
        break;
      case 'analisis':
        await (db.update(db.analisisSuelo)..where((a) => a.id.equals(id))).write(
          AnalisisSueloCompanion(
              deletedAt: const Value(null), updatedAt: Value(now)),
        );
        break;
      case 'predio':
        await (db.update(db.predios)..where((p) => p.id.equals(id))).write(
          PrediosCompanion(
              deletedAt: const Value(null), updatedAt: Value(now)),
        );
        break;
      case 'proveedor':
        await (db.update(db.proveedores)..where((p) => p.id.equals(id))).write(
          ProveedoresCompanion(
              deletedAt: const Value(null), updatedAt: Value(now)),
        );
        break;
    }
  }

  Future<void> hardDelete(String tipo, int id) async {
    switch (tipo) {
      case 'cultivo':
        await (db.delete(db.cultivos)..where((c) => c.id.equals(id))).go();
        break;
      case 'compra':
        await (db.delete(db.compras)..where((c) => c.id.equals(id))).go();
        break;
      case 'inventario':
        await (db.delete(db.inventarios)..where((i) => i.id.equals(id))).go();
        break;
      case 'lote':
        await (db.delete(db.lotes)..where((l) => l.id.equals(id))).go();
        break;
      case 'analisis':
        await (db.delete(db.analisisSuelo)..where((a) => a.id.equals(id))).go();
        break;
      case 'predio':
        await (db.delete(db.predios)..where((p) => p.id.equals(id))).go();
        break;
      case 'proveedor':
        await (db.delete(db.proveedores)..where((p) => p.id.equals(id))).go();
        break;
    }
  }

  Future<int> emptyAll(int predioId) async {
    final items = await getByPredio(predioId);
    for (final it in items) {
      await hardDelete(it.tipo, it.id);
    }
    return items.length;
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}
