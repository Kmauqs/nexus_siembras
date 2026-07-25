// NEXUS Siembras — Helper compartido de exportación CSV/PDF (2026-07-20).
// Unifica el flujo de los botones "Exportar" de todas las pantallas:
// encabezado con el predio activo REAL, conversión al sistema de unidades
// activo (responsabilidad del llamador), snackbar con la ruta del CSV y
// preview nativo del PDF.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_state.dart';
import '../../state/data_state.dart';
import 'report_service.dart';

Future<void> exportarTabla({
  required BuildContext context,
  required WidgetRef ref,
  required String fmt, // 'csv' | 'pdf'
  required String scope, // 'cultivos' | 'inventario' | 'compras' | 'proveedores'
  required String titulo,
  required List<String> columns,
  required List<List<String>> rows,
}) async {
  try {
    final predio = await ref.read(reportPredioProvider.future);
    final sistema = ref.read(unitSystemProvider);
    if (fmt == 'csv') {
      final file = await exportCsv(
        scope: scope,
        predio: predio,
        sistemaUnidades: sistema,
        columns: columns,
        rows: rows,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('CSV generado: ${file.path}'),
        duration: const Duration(seconds: 6),
      ));
    } else {
      final file = await exportPdf(
        scope: scope,
        scopeTitle: titulo,
        predio: predio,
        sistemaUnidades: sistema,
        columns: columns,
        rows: rows,
      );
      if (!context.mounted) return;
      await previewPdf(file);
    }
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Error exportando: $e')));
  }
}

/// Par de botones "CSV / PDF" con el estilo usado en todas las pantallas.
class ExportButtons extends StatelessWidget {
  const ExportButtons({super.key, required this.onExport});
  final void Function(String fmt) onExport;

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      OutlinedButton.icon(
        onPressed: () => onExport('csv'),
        icon: const Icon(Icons.file_download, size: 18),
        label: const Text('CSV'),
      ),
      const SizedBox(width: 8),
      OutlinedButton.icon(
        onPressed: () => onExport('pdf'),
        icon: const Icon(Icons.picture_as_pdf, size: 18),
        label: const Text('PDF'),
      ),
    ]);
  }
}
