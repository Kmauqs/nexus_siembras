import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_siembras/data/database/database.dart';
import 'package:nexus_siembras/services/sync_service.dart';

/// Tests de SyncService que no requieren Supabase: cola offline,
/// tombstone local y merge LWW/tombstone sobre Drift en memoria.
void main() {
  late AppDatabase db;
  late SyncService sync;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    sync = SyncService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<({int predioId, int plantaId, int cultivoId})> seedCultivo({
    DateTime? updatedAt,
    DateTime? deletedAt,
  }) async {
    final predioId = await db.into(db.predios).insert(
          PrediosCompanion.insert(nombre: 'Finca Test'),
        );
    final plantaId = await db.into(db.plantas).insert(
          PlantasCompanion.insert(nombreComun: 'Tomate chonto'),
        );
    final cultivoId = await db.into(db.cultivos).insert(
          CultivosCompanion.insert(
            predioId: predioId,
            plantaId: plantaId,
            fechaSiembra: DateTime.utc(2026, 7, 1),
            updatedAt: Value(updatedAt ?? DateTime.utc(2026, 8, 1, 12)),
            deletedAt: Value(deletedAt),
          ),
        );
    return (predioId: predioId, plantaId: plantaId, cultivoId: cultivoId);
  }

  group('eliminarRemoto offline', () {
    test('encola soft-delete y elimina el mapping local', () async {
      final ids = await seedCultivo();
      await db.into(db.syncMappings).insert(SyncMappingsCompanion.insert(
            tabla: 'cultivos',
            localId: ids.cultivoId,
            remoteId: 47,
          ));

      await sync.eliminarRemoto('cultivos', ids.cultivoId);

      final ops = await db.select(db.syncOps).get();
      expect(ops, hasLength(1));
      expect(ops.single.tipo, 'delete_remoto');
      expect(ops.single.tabla, 'cultivos');
      expect(ops.single.remoteId, 47);

      final mappings = await (db.select(db.syncMappings)
            ..where((m) => m.tabla.equals('cultivos')))
          .get();
      expect(mappings, isEmpty);
    });
  });

  group('tombstoneCultivoLocal', () {
    test('marca cultivo y eventos hijos con deletedAt', () async {
      final ids = await seedCultivo();
      await db.into(db.eventosCultivo).insert(EventosCultivoCompanion.insert(
            cultivoId: ids.cultivoId,
            tipo: 'abono',
          ));

      await sync.tombstoneCultivoLocalForTest(ids.cultivoId);

      final cultivo = await (db.select(db.cultivos)
            ..where((c) => c.id.equals(ids.cultivoId)))
          .getSingle();
      expect(cultivo.deletedAt, isNotNull);

      final eventos = await (db.select(db.eventosCultivo)
            ..where((e) => e.cultivoId.equals(ids.cultivoId)))
          .get();
      expect(eventos, isNotEmpty);
      expect(eventos.every((e) => e.deletedAt != null), isTrue);
    });
  });

  group('mergeCultivo LWW / tombstone', () {
    test('remoto más nuevo sobrescribe notas', () async {
      final ids = await seedCultivo(
        updatedAt: DateTime.utc(2026, 8, 1, 10),
      );
      await db.into(db.syncMappings).insert(SyncMappingsCompanion.insert(
            tabla: 'predios',
            localId: ids.predioId,
            remoteId: 100,
          ));
      await db.into(db.syncMappings).insert(SyncMappingsCompanion.insert(
            tabla: 'cultivos',
            localId: ids.cultivoId,
            remoteId: 47,
          ));
      await (db.update(db.cultivos)
            ..where((c) => c.id.equals(ids.cultivoId)))
          .write(CultivosCompanion(
            notas: const Value('local-viejo'),
            updatedAt: Value(DateTime.utc(2026, 8, 1, 10)),
          ));

      await sync.mergeCultivoForTest({
        'id': 47,
        'predio_id': 100,
        'nombre_planta': 'Tomate chonto',
        'fecha_siembra': '2026-07-01',
        'updated_at': '2026-08-01T12:00:00.000Z',
        'notas': 'remoto-nuevo',
        'deleted_at': null,
      });

      final cultivo = await (db.select(db.cultivos)
            ..where((c) => c.id.equals(ids.cultivoId)))
          .getSingle();
      expect(cultivo.notas, 'remoto-nuevo');
      expect(cultivo.deletedAt, isNull);
    });

    test('local más nuevo conserva notas (LWW)', () async {
      final ids = await seedCultivo(
        updatedAt: DateTime.utc(2026, 8, 1, 14),
      );
      await db.into(db.syncMappings).insert(SyncMappingsCompanion.insert(
            tabla: 'predios',
            localId: ids.predioId,
            remoteId: 100,
          ));
      await db.into(db.syncMappings).insert(SyncMappingsCompanion.insert(
            tabla: 'cultivos',
            localId: ids.cultivoId,
            remoteId: 47,
          ));
      await (db.update(db.cultivos)
            ..where((c) => c.id.equals(ids.cultivoId)))
          .write(CultivosCompanion(
            notas: const Value('local-nuevo'),
            updatedAt: Value(DateTime.utc(2026, 8, 1, 14)),
          ));

      await sync.mergeCultivoForTest({
        'id': 47,
        'predio_id': 100,
        'nombre_planta': 'Tomate chonto',
        'fecha_siembra': '2026-07-01',
        'updated_at': '2026-08-01T12:00:00.000Z',
        'notas': 'remoto-viejo',
        'deleted_at': null,
      });

      final cultivo = await (db.select(db.cultivos)
            ..where((c) => c.id.equals(ids.cultivoId)))
          .getSingle();
      expect(cultivo.notas, 'local-nuevo');
    });

    test('tombstone remoto aplica aunque local sea más nuevo', () async {
      final ids = await seedCultivo(
        updatedAt: DateTime.utc(2026, 8, 1, 14),
      );
      await db.into(db.syncMappings).insert(SyncMappingsCompanion.insert(
            tabla: 'predios',
            localId: ids.predioId,
            remoteId: 100,
          ));
      await db.into(db.syncMappings).insert(SyncMappingsCompanion.insert(
            tabla: 'cultivos',
            localId: ids.cultivoId,
            remoteId: 47,
          ));

      await sync.mergeCultivoForTest({
        'id': 47,
        'predio_id': 100,
        'nombre_planta': 'Tomate chonto',
        'fecha_siembra': '2026-07-01',
        'updated_at': '2026-08-01T12:00:00.000Z',
        'notas': null,
        'deleted_at': '2026-08-01T12:00:00.000Z',
      });

      final cultivo = await (db.select(db.cultivos)
            ..where((c) => c.id.equals(ids.cultivoId)))
          .getSingle();
      expect(cultivo.deletedAt, isNotNull);
    });
  });
}
