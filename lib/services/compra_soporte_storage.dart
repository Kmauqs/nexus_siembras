// NEXUS Siembras — Sync de comprobantes de compra vía Supabase Storage.
//
// El path local (`compras.soportePath`) es solo caché del dispositivo.
// El object key (`compras.soporteStoragePath`) viaja en Postgres y permite
// que co-propietarios descarguen el mismo PDF/foto al generar el ZIP.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/log.dart';
import '../data/database/database.dart';

class CompraSoporteStorage {
  CompraSoporteStorage(this.db, {SupabaseClient? client})
      : _sb = client ?? Supabase.instance.client;

  final AppDatabase db;
  final SupabaseClient _sb;

  static const bucket = 'compras-soportes';

  /// Construye el object key: `{predioRemote}/{compraRemote}/{nombre}`.
  static String objectKey({
    required int predioRemoteId,
    required int compraRemoteId,
    required String nombreArchivo,
  }) {
    final nombre = p.basename(nombreArchivo);
    return '$predioRemoteId/$compraRemoteId/$nombre';
  }

  static String? mimeDePath(String? path) {
    if (path == null || path.isEmpty) return null;
    final ext = p.extension(path).toLowerCase();
    return switch (ext) {
      '.pdf' => 'application/pdf',
      '.png' => 'image/png',
      '.webp' => 'image/webp',
      '.jpg' || '.jpeg' => 'image/jpeg',
      _ => 'application/octet-stream',
    };
  }

  /// Sube el archivo local si hace falta. Devuelve el object key o null.
  Future<String?> subirSiNecesario({
    required Compra compra,
    required int predioRemoteId,
    required int compraRemoteId,
  }) async {
    final local = compra.soportePath;
    if (local == null || local.isEmpty) {
      // Adjunto quitado localmente: borrar remoto si existía.
      if (compra.soporteStoragePath != null &&
          compra.soporteStoragePath!.isNotEmpty) {
        await borrarRemoto(compra.soporteStoragePath!);
        await _marcarLocal(
          compra.id,
          storagePath: null,
          nombre: null,
          tipo: null,
          tocarUpdatedAt: true,
        );
      }
      return null;
    }

    final file = File(local);
    if (!await file.exists()) {
      Log.w('[compra-soporte] local ausente, no se sube: $local');
      return compra.soporteStoragePath;
    }

    final nombre = p.basename(local);
    final key = objectKey(
      predioRemoteId: predioRemoteId,
      compraRemoteId: compraRemoteId,
      nombreArchivo: nombre,
    );
    final mime = compra.soporteTipo ?? mimeDePath(local);

    if (compra.soporteStoragePath == key) {
      return key; // ya alineado
    }

    // Reemplazo: quitar object anterior si cambió el nombre/ruta.
    final prev = compra.soporteStoragePath;
    if (prev != null && prev.isNotEmpty && prev != key) {
      await borrarRemoto(prev);
    }

    try {
      await _sb.storage.from(bucket).upload(
            key,
            file,
            fileOptions: FileOptions(
              upsert: true,
              contentType: mime,
            ),
          );
      await _marcarLocal(
        compra.id,
        storagePath: key,
        nombre: nombre,
        tipo: mime,
        tocarUpdatedAt: true,
      );
      Log.i('[compra-soporte] subido $key');
      return key;
    } catch (e) {
      Log.w('[compra-soporte] upload falló ($key): $e');
      return null;
    }
  }

  Future<void> borrarRemoto(String storagePath) async {
    try {
      await _sb.storage.from(bucket).remove([storagePath]);
    } catch (e) {
      Log.w('[compra-soporte] no se pudo borrar $storagePath: $e');
    }
  }

  /// Garantiza un path local usable (caché). Descarga si falta el archivo.
  Future<String?> asegurarLocal(Compra compra) async {
    final local = compra.soportePath;
    if (local != null && local.isNotEmpty) {
      final f = File(local);
      if (await f.exists()) return local;
    }

    final key = compra.soporteStoragePath;
    if (key == null || key.isEmpty) return null;
    if (_sb.auth.currentSession == null) return null;

    try {
      final bytes = await _sb.storage.from(bucket).download(key);
      final nombre = compra.soporteNombre?.isNotEmpty == true
          ? compra.soporteNombre!
          : p.basename(key);
      final anio = compra.fecha.year;
      final dest = await _pathCacheLocal(anio: anio, nombre: nombre);
      await File(dest).writeAsBytes(bytes, flush: true);
      await _marcarLocal(
        compra.id,
        storagePath: key,
        nombre: nombre,
        tipo: compra.soporteTipo ?? mimeDePath(dest),
        pathLocal: dest,
        tocarUpdatedAt: false, // no re-pushear solo por caché
      );
      Log.i('[compra-soporte] descargado $key → $dest');
      return dest;
    } catch (e) {
      Log.w('[compra-soporte] download falló ($key): $e');
      return null;
    }
  }

  Future<String> _pathCacheLocal({
    required int anio,
    required String nombre,
  }) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'soportes', '$anio'));
    if (!await dir.exists()) await dir.create(recursive: true);
    var dest = File(p.join(dir.path, nombre));
    if (!await dest.exists()) return dest.path;
    // Evitar pisar otro archivo distinto: sufijo con hash corto del key.
    final stem = p.basenameWithoutExtension(nombre);
    final ext = p.extension(nombre);
    var n = 2;
    while (await dest.exists()) {
      dest = File(p.join(dir.path, '$stem-$n$ext'));
      n++;
    }
    return dest.path;
  }

  Future<void> _marcarLocal(
    int compraId, {
    String? storagePath,
    String? nombre,
    String? tipo,
    String? pathLocal,
    required bool tocarUpdatedAt,
  }) async {
    await (db.update(db.compras)..where((c) => c.id.equals(compraId))).write(
      ComprasCompanion(
        soporteStoragePath: Value(storagePath),
        soporteNombre: Value(nombre),
        soporteTipo: Value(tipo),
        soportePath: pathLocal == null
            ? const Value.absent()
            : Value(pathLocal),
        updatedAt: tocarUpdatedAt
            ? Value(DateTime.now())
            : const Value.absent(),
      ),
    );
  }
}
