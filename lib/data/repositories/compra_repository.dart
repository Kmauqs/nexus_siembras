import 'package:drift/drift.dart';
import '../../core/units/units_catalog.dart';
import '../database/database.dart';
import 'inventory_repository.dart';

class CompraRepository {
  CompraRepository(this.db, this.inv);
  final AppDatabase db;
  final InventoryRepository inv;

  Stream<List<Compra>> watchByPredio(int predioId) {
    return (db.select(db.compras)
          ..where((c) => c.predioId.equals(predioId))
          ..where((c) => c.deletedAt.isNull())
          ..orderBy([(c) => OrderingTerm.desc(c.fecha)]))
        .watch();
  }

  static const _consumibles = {'semilla', 'abono', 'pesticida'};

  Future<int> add({
    required int predioId,
    required DateTime fecha,
    required String desc,
    String? desc2,
    required double valor,
    required double cantidad,
    required String unidad,
    String? codigo,
    String? factura,
    int? proveedorId,
    String? proveedorNombre,  // Nombre del proveedor para inventario
    required String tipo,
    int? plantaRef,
    String? soporteName,
    String? soporteTipo,
  }) async {
    // Conversión a unidad base SI antes de persistir.
    final (baseVal, baseCode) = toBase(cantidad, unidad);
    final idUnico =
        '$desc-${fecha.year.toString().substring(2)}${fecha.month.toString().padLeft(2, "0")}${fecha.day.toString().padLeft(2, "0")}';
    final id = await db.into(db.compras).insert(ComprasCompanion.insert(
          predioId: predioId,
          proveedorId: Value(proveedorId),
          fecha: fecha,
          descripcion1: desc,
          descripcion2: Value(desc2),
          valorTotal: valor,
          cantidadBase: baseVal,
          unidadBase: baseCode,
          cantidadDisplay: Value(cantidad),
          codigo: Value(codigo),
          factura: Value(factura),
          tipo: Value(tipo),
          plantaRef: Value(plantaRef),
          soportePath: Value(soporteName),
          soporteTipo: Value(soporteTipo),
          idUnico: Value(idUnico),
        ));
    if (_consumibles.contains(tipo)) {
      await inv.addOrIncrement(
        predioId: predioId,
        descripcion: desc,
        cantidad: cantidad,   // se convierte dentro del repo de inventario
        unidad: unidad,
        codigo: codigo,
        fabricante: proveedorNombre,
        fecha: fecha,
      );
    }
    return id;
  }

  /// Actualiza una compra existente y ajusta el inventario en consecuencia:
  /// - Si la compra era consumible (semilla/abono/pesticida), resta la cantidad
  ///   vieja de la descripción vieja.
  /// - Si la compra actualizada es consumible, suma la cantidad nueva a la
  ///   descripción nueva (que puede ser la misma o diferente).
  ///
  /// Nota: el ajuste es aditivo simple. Si parte del inventario ya fue consumido
  /// por otras actividades, el clamp a cero de `consume()` evita saldos negativos
  /// (puede haber pequeñas discrepancias en escenarios extremos que Fase 2h
  /// resolverá con event-sourcing).
  Future<void> update({
    required int id,
    required int predioId,
    required DateTime fecha,
    required String desc,
    String? desc2,
    required double valor,
    required double cantidad,
    required String unidad,
    String? codigo,
    String? factura,
    int? proveedorId,
    String? proveedorNombre,
    required String tipo,
    int? plantaRef,
    String? soporteName,
    String? soporteTipo,
  }) async {
    final old = await (db.select(db.compras)..where((c) => c.id.equals(id)))
        .getSingleOrNull();
    if (old == null) return;

    // Revertir efecto viejo en inventario (usa cantidadBase, ya en unidad base)
    if (_consumibles.contains(old.tipo)) {
      await inv.consumeBase(
        predioId: predioId,
        descripcion: old.descripcion1,
        cantidadBase: old.cantidadBase,
      );
    }

    final (baseVal, baseCode) = toBase(cantidad, unidad);
    final idUnico =
        '$desc-${fecha.year.toString().substring(2)}${fecha.month.toString().padLeft(2, "0")}${fecha.day.toString().padLeft(2, "0")}';

    await (db.update(db.compras)..where((c) => c.id.equals(id))).write(
      ComprasCompanion(
        proveedorId: Value(proveedorId),
        fecha: Value(fecha),
        descripcion1: Value(desc),
        descripcion2: Value(desc2),
        valorTotal: Value(valor),
        cantidadBase: Value(baseVal),
        unidadBase: Value(baseCode),
        cantidadDisplay: Value(cantidad),
        codigo: Value(codigo),
        factura: Value(factura),
        tipo: Value(tipo),
        plantaRef: Value(plantaRef),
        soportePath: Value(soporteName),
        soporteTipo: Value(soporteTipo),
        idUnico: Value(idUnico),
        updatedAt: Value(DateTime.now()),
      ),
    );

    if (_consumibles.contains(tipo)) {
      await inv.addOrIncrement(
        predioId: predioId,
        descripcion: desc,
        cantidad: cantidad,
        unidad: unidad,
        codigo: codigo,
        fabricante: proveedorNombre,
        fecha: fecha,
      );
    }
  }

  Future<void> softDelete(int id) async {
    final now = DateTime.now();
    await (db.update(db.compras)..where((c) => c.id.equals(id))).write(
      ComprasCompanion(deletedAt: Value(now), updatedAt: Value(now)),
    );
  }
}
