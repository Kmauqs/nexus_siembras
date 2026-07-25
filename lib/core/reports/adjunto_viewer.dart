// NEXUS Siembras — Visor y compartidor de adjuntos (Fase B8, 2026-07-20).
//
// Abre archivos guardados por la app (comprobantes de compra, PDFs de
// laboratorio, reportes generados) sin dependencias de visor externo:
//   - PDF  → preview nativo vía `printing` (imprimir/guardar incluidos).
//   - Imagen → diálogo con zoom (InteractiveViewer).
// Compartir usa `share_plus` (hoja de compartir del SO).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import '../log.dart';

const _extImagen = ['.jpg', '.jpeg', '.png', '.webp'];

/// Abre un adjunto según su tipo. Muestra snackbar si el archivo ya no
/// existe (p. ej. borrado manualmente del disco).
Future<void> abrirAdjunto(BuildContext context, String path) async {
  final f = File(path);
  if (!await f.exists()) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('El archivo no existe: ${p.basename(path)}')));
    return;
  }
  final ext = p.extension(path).toLowerCase();
  try {
    if (ext == '.pdf') {
      await Printing.layoutPdf(
          name: p.basename(path), onLayout: (_) => f.readAsBytes());
    } else if (_extImagen.contains(ext)) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AppBar(
              title: Text(p.basename(path),
                  style: const TextStyle(fontSize: 14)),
              automaticallyImplyLeading: false,
              actions: [
                IconButton(
                    icon: const Icon(Icons.share),
                    tooltip: 'Compartir',
                    onPressed: () => compartirArchivo(ctx, path)),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx)),
              ],
            ),
            Flexible(
              child: InteractiveViewer(
                maxScale: 6,
                child: Image.file(f, fit: BoxFit.contain),
              ),
            ),
          ]),
        ),
      );
    } else {
      // Tipo no visualizable dentro de la app (ej. CSV): compartir para
      // abrirlo con una app externa.
      await compartirArchivo(context, path);
    }
  } catch (e) {
    Log.w('[adjuntos] no se pudo abrir $path: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('No se pudo abrir: $e')));
  }
}

/// Comparte un archivo con apps externas (hoja de compartir del SO).
/// API nueva de share_plus 11+ (`SharePlus.instance.share`): la clase
/// `Share` quedó obsoleta y las versiones 13+ eliminan el warning de
/// Kotlin Gradle Plugin en Android (2026-07-20).
Future<void> compartirArchivo(BuildContext context, String path) async {
  try {
    final result = await SharePlus.instance.share(ShareParams(
      files: [XFile(path)],
      subject: p.basename(path),
    ));
    Log.d('[adjuntos] compartir ${p.basename(path)}: ${result.status}');
  } catch (e) {
    Log.w('[adjuntos] no se pudo compartir $path: $e');
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('No se pudo compartir: $e')));
  }
}
