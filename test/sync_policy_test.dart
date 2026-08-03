import 'package:flutter_test/flutter_test.dart';
import 'package:nexus_siembras/services/sync_policy.dart';

void main() {
  group('debeSubirFila', () {
    final t0 = DateTime.utc(2026, 8, 1, 12);
    final t1 = DateTime.utc(2026, 8, 1, 13);

    test('sin lastPushedAt siempre sube', () {
      expect(
        debeSubirFila(lastPushedAt: null, updatedAt: t0),
        isTrue,
      );
    });

    test('updatedAt posterior a lastPushedAt → sube', () {
      expect(
        debeSubirFila(lastPushedAt: t0, updatedAt: t1),
        isTrue,
      );
    });

    test('updatedAt igual o anterior → no sube', () {
      expect(
        debeSubirFila(lastPushedAt: t1, updatedAt: t1),
        isFalse,
      );
      expect(
        debeSubirFila(lastPushedAt: t1, updatedAt: t0),
        isFalse,
      );
    });
  });

  group('debeAplicarMergeRemoto (LWW)', () {
    final localOld = DateTime.utc(2026, 8, 1, 10);
    final remoteNew = DateTime.utc(2026, 8, 1, 12);
    final localNew = DateTime.utc(2026, 8, 1, 14);

    test('sin fila local → aplica (insert)', () {
      expect(
        debeAplicarMergeRemoto(
          localUpdatedAt: null,
          remoteUpdatedAt: remoteNew,
        ),
        isTrue,
      );
    });

    test('remoto más nuevo → aplica', () {
      expect(
        debeAplicarMergeRemoto(
          localUpdatedAt: localOld,
          remoteUpdatedAt: remoteNew,
        ),
        isTrue,
      );
    });

    test('local más nuevo → no aplica (LWW)', () {
      expect(
        debeAplicarMergeRemoto(
          localUpdatedAt: localNew,
          remoteUpdatedAt: remoteNew,
        ),
        isFalse,
      );
    });

    test('timestamps iguales → aplica (remoto no pierde)', () {
      expect(
        debeAplicarMergeRemoto(
          localUpdatedAt: remoteNew,
          remoteUpdatedAt: remoteNew,
        ),
        isTrue,
      );
    });

    test('tombstone remoto gana aunque local sea más nuevo', () {
      expect(
        debeAplicarMergeRemoto(
          localUpdatedAt: localNew,
          remoteUpdatedAt: remoteNew,
          remoteDeletedAt: remoteNew,
          localDeletedAt: null,
          tombstoneRemotoGana: true,
        ),
        isTrue,
      );
    });

    test('sin flag tombstone, local más nuevo conserva vivo', () {
      expect(
        debeAplicarMergeRemoto(
          localUpdatedAt: localNew,
          remoteUpdatedAt: remoteNew,
          remoteDeletedAt: remoteNew,
          localDeletedAt: null,
          tombstoneRemotoGana: false,
        ),
        isFalse,
      );
    });

    test('si local ya está borrado, tombstone no fuerza re-merge por sí solo',
        () {
      // Ambos borrados + local más nuevo → LWW normal (no aplicar).
      expect(
        debeAplicarMergeRemoto(
          localUpdatedAt: localNew,
          remoteUpdatedAt: remoteNew,
          remoteDeletedAt: remoteNew,
          localDeletedAt: localNew,
          tombstoneRemotoGana: true,
        ),
        isFalse,
      );
    });
  });

  group('particionarEnLotes (batch)', () {
    test('lista vacía', () {
      expect(particionarEnLotes<int>([]), isEmpty);
    });

    test('menor que batchSize → un solo lote', () {
      final lots = particionarEnLotes(List.generate(50, (i) => i), 200);
      expect(lots, hasLength(1));
      expect(lots.first, hasLength(50));
    });

    test('exactamente N lotes completos', () {
      final lots = particionarEnLotes(List.generate(400, (i) => i), 200);
      expect(lots, hasLength(2));
      expect(lots[0], hasLength(200));
      expect(lots[1], hasLength(200));
    });

    test('último lote parcial', () {
      final lots = particionarEnLotes(List.generate(201, (i) => i), 200);
      expect(lots, hasLength(2));
      expect(lots[0], hasLength(200));
      expect(lots[1], hasLength(1));
    });

    test('usa kSyncBatchSize por defecto', () {
      expect(kSyncBatchSize, 200);
      final lots = particionarEnLotes(List.generate(201, (i) => i));
      expect(lots.first, hasLength(kSyncBatchSize));
    });

    test('batchSize inválido lanza', () {
      expect(() => particionarEnLotes([1], 0), throwsArgumentError);
    });
  });

  group('particionarNuevosYExistentes', () {
    test('separa null remoteId de no-null', () {
      final items = [
        (id: 1, remote: null),
        (id: 2, remote: 10),
        (id: 3, remote: null),
        (id: 4, remote: 20),
      ];
      final partes =
          particionarNuevosYExistentes(items, (e) => e.remote);
      expect(partes.nuevos.map((e) => e.id), [1, 3]);
      expect(partes.existentes.map((e) => e.id), [2, 4]);
    });
  });
}
