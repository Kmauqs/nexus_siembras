// NEXUS Siembras — Adjuntos de soporte (comprobantes de compra, PDFs de
// laboratorio, etc.). 2026-07-20.
//
// Convención de almacenamiento (espejo de la carpeta física del usuario):
//   {Documents}/soportes/{año}/{Proveedor}-{factura}.pdf   ← compras
//   {Documents}/analisis_suelo/{año}/{nombre}.pdf          ← laboratorio
//
// El path absoluto resultante se guarda en la columna correspondiente
// (compras.soportePath / analisis_suelo.soportePath).

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../core/log.dart';

class SoporteService {
  SoporteService._();
  static final SoporteService instance = SoporteService._();
  final _imgPicker = ImagePicker();

  /// Elimina caracteres inválidos para nombre de archivo (Windows/Android).
  String sanitizar(String s) {
    final limpio = s
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ');
    return limpio.isEmpty ? 'SIN_NOMBRE' : limpio;
  }

  /// Selecciona un PDF y lo copia a `{subdir}/{anio}/{nombreBase}.pdf`.
  /// Retorna el path destino o null si el usuario canceló.
  Future<String?> adjuntarPdf({
    required int anio,
    required String nombreBase,
    String subdir = 'soportes',
  }) async {
    // file_picker 11: API estática (FilePicker.platform fue eliminado).
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      dialogTitle: 'Seleccionar PDF',
    );
    final path = res?.files.single.path;
    if (path == null) return null;
    return _copiar(
        origen: File(path), anio: anio, nombreBase: nombreBase,
        ext: '.pdf', subdir: subdir);
  }

  /// Toma o selecciona una foto y la copia con la misma convención.
  Future<String?> adjuntarFoto({
    required int anio,
    required String nombreBase,
    required bool desdeCamara,
    String subdir = 'soportes',
  }) async {
    final xf = await _imgPicker.pickImage(
      source: desdeCamara ? ImageSource.camera : ImageSource.gallery,
      maxWidth: 2000,
      imageQuality: 85,
    );
    if (xf == null) return null;
    final ext = p.extension(xf.path).toLowerCase();
    final extSegura =
        const ['.jpg', '.jpeg', '.png', '.webp'].contains(ext) ? ext : '.jpg';
    return _copiar(
        origen: File(xf.path), anio: anio, nombreBase: nombreBase,
        ext: extSegura, subdir: subdir);
  }

  Future<String> _copiar({
    required File origen,
    required int anio,
    required String nombreBase,
    required String ext,
    required String subdir,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, subdir, '$anio'));
    if (!await dir.exists()) await dir.create(recursive: true);
    final nombre = sanitizar(nombreBase);
    var destino = File(p.join(dir.path, '$nombre$ext'));
    // No sobrescribir: sufijos -2, -3, … (misma factura re-adjuntada).
    var n = 2;
    while (await destino.exists()) {
      destino = File(p.join(dir.path, '$nombre-$n$ext'));
      n++;
    }
    await origen.copy(destino.path);
    Log.i('[soporte] guardado en ${destino.path}');
    return destino.path;
  }

  /// Borra un adjunto si existe. Silencioso: un soporte huérfano no debe
  /// bloquear el flujo de edición.
  Future<void> borrar(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (e) {
      Log.w('[soporte] no se pudo borrar $path: $e');
    }
  }
}
