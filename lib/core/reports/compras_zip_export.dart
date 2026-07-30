// NEXUS Siembras — Paquete ZIP de compras (reporte completo + comprobantes).
// Genera un .zip con PDF y CSV extendidos y copia de cada factura adjunta.

import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import '../../state/app_state.dart';
import '../../state/data_state.dart';
import 'report_data_builder.dart';
import 'report_service.dart';

/// Crea el ZIP consolidado: `compras_completo.pdf`, `compras_completo.csv`
/// y carpeta `comprobantes/` con los adjuntos referenciados en el reporte.
Future<File> exportComprasPaqueteZip(WidgetRef ref) async {
  final predio = await ref.read(reportPredioProvider.future);
  final sistema = ref.read(unitSystemProvider);
  final paquete = await buildComprasPaqueteExport(ref);
  final t = paquete.tabla;

  final pdf = await exportPdf(
    scope: t.scope,
    scopeTitle: t.titulo,
    predio: predio,
    sistemaUnidades: sistema,
    columns: t.columns,
    rows: t.rows,
    pageFormat: PdfPageFormat.a4.landscape,
  );
  final csv = await exportCsv(
    scope: t.scope,
    predio: predio,
    sistemaUnidades: sistema,
    columns: t.columns,
    rows: t.rows,
  );

  final docs = await getApplicationDocumentsDirectory();
  final stamp = DateTime.now().millisecondsSinceEpoch;
  final predioSlug = _sanitizar(predio.nombre);
  final zipPath = p.join(docs.path, 'compras_completo_${predioSlug}_$stamp.zip');

  final encoder = ZipFileEncoder();
  encoder.create(zipPath);
  encoder.addFile(pdf, 'compras_completo.pdf');
  encoder.addFile(csv, 'compras_completo.csv');
  for (final adj in paquete.adjuntos) {
    final f = File(adj.rutaLocal);
    if (await f.exists()) {
      encoder.addFile(f, adj.rutaEnZip);
    }
  }
  encoder.close();

  return File(zipPath);
}

String _sanitizar(String s) {
  final limpio = s
      .trim()
      .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
      .replaceAll(RegExp(r'\s+'), '_');
  return limpio.isEmpty ? 'predio' : limpio;
}
