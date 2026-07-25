// NEXUS Siembras — Importador del Excel base (2026-Control Siembras.xlsx)
// Uso:
//   dart run tool/import_excel.dart "../../2026-Control Siembras.xlsx"

import 'dart:io';
import 'package:excel/excel.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Uso: dart run tool/import_excel.dart <ruta.xlsx>');
    exit(1);
  }
  final file = File(args[0]);
  if (!file.existsSync()) {
    stderr.writeln('No encontrado: ${args[0]}');
    exit(1);
  }

  final bytes = file.readAsBytesSync();
  final book = Excel.decodeBytes(bytes);

  stdout.writeln('Hojas: ${book.sheets.keys.join(", ")}');
  for (final sheetName in ['PLANTAS', 'PROVEEDORES', 'Compras', 'Inventario']) {
    final sh = book.sheets[sheetName];
    if (sh == null) {
      stdout.writeln('  · $sheetName no encontrada');
      continue;
    }
    // excel 4.x renombró maxCols → maxColumns (fix flutter analyze 2026-07-19)
    stdout.writeln(
        '  · $sheetName: ${sh.maxRows} filas × ${sh.maxColumns} columnas');
    if (sh.rows.isNotEmpty) {
      final header = sh.rows.first.map((c) => c?.value?.toString() ?? '').toList();
      stdout.writeln('    Cabecera: ${header.join(" | ")}');
    }
  }

  // TODO Fase 2b:
  //   1. Abrir AppDatabase().
  //   2. Insertar país/región/municipio desde encabezado de CULTIVOS.
  //   3. Insertar predio "Finca Villamariana".
  //   4. Mapear PROVEEDORES -> proveedor.
  //   5. Mapear PLANTAS -> planta (con abono1Dias, tipoAbono*).
  //   6. Mapear Compras -> compra (convertir Unidad texto -> unidadDisplayId).
  //   7. Mapear Inventario -> inventario.
  //   8. Cerrar db.
  //   9. Reporte de filas migradas por tabla.
  stdout.writeln('\n[Fase 2b] Migración a Drift pendiente.');
}
