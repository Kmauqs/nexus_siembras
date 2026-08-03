// Política pura de sincronización (LWW, elegibilidad de push, lotes).
// Extraída de SyncService para poder unit-testear sin Supabase ni Drift.

import 'dart:math' show min;

/// Tamaño de lote para upserts remotos (auditoría P2 / SyncService).
const int kSyncBatchSize = 200;

/// ¿Debe subirse una fila local según su mapping?
///
/// - Sin `lastPushedAt` (nunca mapeada) → sí.
/// - Con mapping → solo si `updatedAt` es estrictamente posterior a
///   `lastPushedAt` (cambios locales pendientes de push).
bool debeSubirFila({
  required DateTime? lastPushedAt,
  required DateTime updatedAt,
}) {
  if (lastPushedAt == null) return true;
  return updatedAt.isAfter(lastPushedAt);
}

/// ¿Debe el merge remoto sobreescribir la fila local?
///
/// Regla base: last-write-wins por `updated_at`.
///
/// Excepción (`tombstoneRemotoGana`): si el remoto trae `deleted_at` y lo
/// local aún está vivo, el tombstone gana aunque el reloj local diga
/// "más nuevo" (evita que un peer ignore el soft-delete de otro dispositivo
/// por skew de reloj). Usado en cultivos y cultivo_patologias.
bool debeAplicarMergeRemoto({
  required DateTime? localUpdatedAt,
  required DateTime remoteUpdatedAt,
  DateTime? remoteDeletedAt,
  DateTime? localDeletedAt,
  bool tombstoneRemotoGana = false,
}) {
  // Sin fila local → insertar.
  if (localUpdatedAt == null) return true;

  if (tombstoneRemotoGana &&
      remoteDeletedAt != null &&
      localDeletedAt == null) {
    return true;
  }

  // Local más nuevo → conservar local.
  if (localUpdatedAt.isAfter(remoteUpdatedAt)) return false;

  return true;
}

/// Parte una lista en trozos de a lo sumo [batchSize] (push por lotes).
List<List<T>> particionarEnLotes<T>(List<T> items, [int batchSize = kSyncBatchSize]) {
  if (batchSize <= 0) {
    throw ArgumentError.value(batchSize, 'batchSize', 'debe ser > 0');
  }
  if (items.isEmpty) return const [];
  final out = <List<T>>[];
  for (var i = 0; i < items.length; i += batchSize) {
    out.add(items.sublist(i, min(i + batchSize, items.length)));
  }
  return out;
}

/// Separa filas nuevas (sin remoteId) de existentes (con remoteId) para
/// las dos rutas de `_pushBatch`.
({List<T> nuevos, List<T> existentes}) particionarNuevosYExistentes<T>(
  List<T> items,
  int? Function(T item) remoteIdOf,
) {
  final nuevos = <T>[];
  final existentes = <T>[];
  for (final item in items) {
    if (remoteIdOf(item) == null) {
      nuevos.add(item);
    } else {
      existentes.add(item);
    }
  }
  return (nuevos: nuevos, existentes: existentes);
}
