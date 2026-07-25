// Stub para web — se activa cuando dart:io NO está disponible (osea, en el navegador).
// Fase 3: reemplazar por drift_wasm (WasmDatabase.open) para SQLite en el navegador
// vía WebAssembly + IndexedDB. Ver: https://drift.simonbinder.eu/web/
import 'package:drift/drift.dart';

LazyDatabase openConnection() {
  return LazyDatabase(() async {
    throw UnsupportedError(
      'Web SQLite pendiente para Fase 3 (drift_wasm + WasmDatabase). '
      'Por ahora la app corre en Android/iOS/Desktop.',
    );
  });
}
