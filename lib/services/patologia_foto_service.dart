// NEXUS Siembras — Servicio para guardar/borrar fotos de reportes de
// patologías en el almacenamiento local de la app.
//
// Fase 3e-5. Las fotos se guardan en:
//   {ApplicationDocumentsDirectory}/patologias/{uuid}.jpg
//
// Cuando se sincronizan a la nube (en fase futura), se sube el binario a
// Supabase Storage y se guarda la URL en `PatologiasReportadas.fotoRemoteUrl`.
// El path local se conserva para caché y visualización offline.

import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../core/log.dart';

class PatologiaFotoService {
  PatologiaFotoService._();
  static final PatologiaFotoService instance = PatologiaFotoService._();
  static const _subdir = 'patologias';
  static const _uuid = Uuid();
  final _picker = ImagePicker();

  /// Devuelve el directorio absoluto donde se almacenan las fotos.
  /// Lo crea si no existe.
  Future<Directory> _dir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}${Platform.pathSeparator}$_subdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Toma una foto con la cámara. Retorna el path absoluto de la copia
  /// guardada en el directorio local o null si el usuario canceló.
  Future<String?> tomarFoto() async {
    final xf = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1600,
      imageQuality: 82,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (xf == null) return null;
    return _persistir(xf);
  }

  /// Elige una foto de la galería.
  Future<String?> elegirDeGaleria() async {
    final xf = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 82,
    );
    if (xf == null) return null;
    return _persistir(xf);
  }

  /// Copia el XFile temporal (que el picker deja en cache) a un path
  /// permanente dentro del directorio de la app.
  Future<String> _persistir(XFile xf) async {
    final dir = await _dir();
    // Auditoría S5: re-encodificar SIEMPRE la imagen antes de guardarla.
    // Esto elimina los metadatos EXIF — en particular las coordenadas GPS
    // del predio, que de otro modo viajarían dentro del archivo al bucket
    // público `patologias`. La decodificación + re-encode JPEG descarta
    // todos los chunks de metadatos.
    //
    // Revisión 2026-07-20 (hallazgo #3): SIN fallback de copia directa.
    // Antes, si el decode fallaba, se copiaba el original CON EXIF/GPS —
    // contradecía S5. Ahora un formato no decodificable se rechaza con
    // mensaje al usuario (los llamadores muestran snackbar).
    final bytes = await xf.readAsBytes();
    var decoded = img.decodeImage(bytes);
    if (decoded == null) {
      // Segundo intento: algunos JPEG exóticos decodifican tras releer
      // el archivo desde disco (buffers parciales del picker).
      try {
        decoded = img.decodeImage(await File(xf.path).readAsBytes());
      } catch (_) {
        // Mismo tratamiento que decode nulo: rechazo controlado abajo.
      }
    }
    if (decoded == null) {
      Log.w('[foto] formato no decodificable — rechazado (sin strip EXIF '
          'no se guarda): ${xf.path}');
      throw const FormatException(
          'La imagen no se pudo procesar para eliminar sus metadatos de '
          'ubicación. Intenta con otra foto o toma una nueva con la cámara.');
    }
    // bakeOrientation aplica la rotación EXIF a los píxeles antes de
    // perder ese metadato (si no, las fotos verticales saldrían giradas).
    final oriented = img.bakeOrientation(decoded);
    final limpio = img.encodeJpg(oriented, quality: 82);
    final destino =
        File('${dir.path}${Platform.pathSeparator}${_uuid.v4()}.jpg');
    await destino.writeAsBytes(limpio, flush: true);
    return destino.path;
  }

  /// Borra la foto local si existe. Silencioso si no.
  Future<void> borrar(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }
}
