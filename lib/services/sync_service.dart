// Servicio de sincronización bidireccional entre Drift local y Supabase.
//
// Estrategia:
//   - Sync manual disparado por el usuario (botón "Sincronizar ahora").
//   - Resolución de conflictos: last-write-wins por `updated_at`.
//   - Push en orden topológico (predios/proveedores → cultivos/lotes/etc.)
//     para respetar las FKs.
//   - Pull en el mismo orden. Al pull, se resuelven remote_id → local_id
//     usando la tabla `sync_mappings`.
//
// Formato de mapping local ↔ remoto:
//   - Al insertar en la nube por primera vez, se manda `cliente_id = local_id`.
//   - La nube retorna el `remote_id` (BIGSERIAL) y lo guardamos en sync_mappings.
//   - Para actualizaciones subsecuentes se usa `.upsert(...)` con
//     `onConflict: 'owner_id,cliente_id'` (UNIQUE en Postgres).

import 'dart:async';
import 'dart:convert';
import 'dart:math' show min;
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/log.dart';
import '../data/database/database.dart';
import '../data/repositories/cultivo_repository.dart';
import 'supabase_service.dart';

class SyncResult {
  final int pushed;
  final int pulled;

  /// Filas individuales que fallaron (RLS, datos corruptos, red) sin
  /// abortar el sync completo (auditoría P7). Si > 0, el sync terminó
  /// pero quedó trabajo pendiente — revisar logs.
  final int errores;
  final String? error;
  final Duration duration;
  const SyncResult({
    required this.pushed,
    required this.pulled,
    this.errores = 0,
    this.error,
    required this.duration,
  });

  bool get exito => error == null;
  @override
  String toString() =>
      'SyncResult(pushed: $pushed, pulled: $pulled, errores: $errores, '
      'error: $error, dur: ${duration.inMilliseconds}ms)';
}

/// Fila preparada para push por lotes (auditoría P2).
class _FilaPush {
  _FilaPush({required this.localId, required this.payload, this.remoteId});
  final int localId;
  final Map<String, dynamic> payload;
  final int? remoteId;
}

class SyncService {
  SyncService(this.db);
  final AppDatabase db;

  SupabaseClient get _sb => Supabase.instance.client;

  /// Tamaño de lote para upserts remotos (auditoría P2).
  static const int _batchSize = 200;

  /// Versión mínima de esquema remoto requerida por este cliente
  /// (auditoría S6). Se compara contra `public.schema_meta.version`.
  /// Ver supabase/migrations/README.md.
  static const int schemaRemotoRequerido = 7;

  /// Guard de reentrada: botón manual + auto-sync pueden coincidir
  /// (auditoría P6).
  bool _enCurso = false;

  /// Contador de filas fallidas del sync en curso (auditoría P7).
  int _erroresFilas = 0;

  /// Cache de permisos de edición por predio durante un sync (auditoría P1).
  final Map<int, bool> _permisoCache = {};
  final Map<int, bool> _propietarioCache = {};

  /// Borra permanentemente una fila remota dado su ID local + tabla.
  /// Se usa cuando el usuario vacía la papelera o borra definitivamente
  /// un ítem — debe propagarse al server para no reaparecer en el próximo
  /// pull.
  ///
  /// Fase B5 (2026-07-20): si no hay conexión/sesión o el DELETE remoto
  /// falla, la operación se ENCOLA en `sync_ops` y se reintenta al inicio
  /// de cada sincronización. Antes se perdía y la fila "revivía" en el
  /// siguiente pull, obligando a vaciar la papelera de nuevo.
  Future<void> eliminarRemoto(String tablaRemota, int localId) async {
    // Cliente seguro: en modo 100% local (sin .env) Supabase nunca se
    // inicializó y `Supabase.instance` lanzaría.
    final sb = SupabaseService.instance.client;
    final remoteId = await _resolveRemoteId(tablaRemota, localId);
    if (remoteId != null) {
      if (sb == null || sb.auth.currentSession == null) {
        // Sin sesión: encolar para cuando vuelva la conexión/login.
        await _encolarOp('delete_remoto', tablaRemota, remoteId);
      } else {
        try {
          await sb.from(tablaRemota).delete().eq('id', remoteId);
        } catch (e) {
          Log.w('[sync] delete remoto $tablaRemota#$remoteId falló, '
              'encolado para reintento: $e');
          await _encolarOp('delete_remoto', tablaRemota, remoteId);
        }
      }
    }
    // Elimina el mapping para que en el próximo sync la fila no se re-suba
    // desde local (aunque ya no exista local).
    await (db.delete(db.syncMappings)
          ..where((s) => s.tabla.equals(tablaRemota))
          ..where((s) => s.localId.equals(localId)))
        .go();
  }

  // ==================================================
  // COLA PERSISTENTE DE OPERACIONES (Fase B5)
  // ==================================================

  /// Descartar una operación tras este número de fallos (cola envenenada:
  /// p. ej. RLS que nunca va a permitir el delete).
  static const int _maxIntentosOp = 10;

  Future<void> _encolarOp(String tipo, String tabla, int remoteId) async {
    // Deduplicación: no encolar dos veces la misma operación.
    final existente = await (db.select(db.syncOps)
          ..where((o) => o.tipo.equals(tipo))
          ..where((o) => o.tabla.equals(tabla))
          ..where((o) => o.remoteId.equals(remoteId))
          ..limit(1))
        .getSingleOrNull();
    if (existente != null) return;
    await db.into(db.syncOps).insert(SyncOpsCompanion.insert(
          tipo: tipo,
          tabla: tabla,
          remoteId: Value(remoteId),
        ));
  }

  /// Procesa la cola pendiente. Se llama al inicio de cada sincronización
  /// (antes del pull, para que un delete encolado no sea "revivido" por
  /// el pull de esta misma ronda). Retorna cuántas operaciones ejecutó.
  Future<int> procesarColaPendiente() async {
    final ops = await (db.select(db.syncOps)
          ..orderBy([(o) => OrderingTerm.asc(o.id)]))
        .get();
    if (ops.isEmpty) return 0;
    var ejecutadas = 0;
    for (final op in ops) {
      try {
        switch (op.tipo) {
          case 'delete_remoto':
            if (op.remoteId != null) {
              await _sb.from(op.tabla).delete().eq('id', op.remoteId!);
            }
          default:
            Log.w('[sync] op desconocida en cola: ${op.tipo} — descartada');
        }
        await (db.delete(db.syncOps)..where((o) => o.id.equals(op.id))).go();
        ejecutadas++;
      } catch (e) {
        final intentos = op.intentos + 1;
        if (intentos >= _maxIntentosOp) {
          Log.e('[sync] op ${op.tipo} ${op.tabla}#${op.remoteId} descartada '
              'tras $_maxIntentosOp intentos: $e');
          await (db.delete(db.syncOps)..where((o) => o.id.equals(op.id)))
              .go();
          _erroresFilas++;
        } else {
          Log.w('[sync] op ${op.tipo} ${op.tabla}#${op.remoteId} falló '
              '(intento $intentos/$_maxIntentosOp): $e');
          await (db.update(db.syncOps)..where((o) => o.id.equals(op.id)))
              .write(SyncOpsCompanion(
            intentos: Value(intentos),
            ultimoError: Value('$e'),
          ));
        }
      }
    }
    if (ejecutadas > 0) {
      Log.i('[sync] cola: $ejecutadas operación(es) pendiente(s) ejecutada(s)');
    }
    return ejecutadas;
  }

  /// Cuenta filas locales con cambios pendientes de subir a la nube.
  /// Suma todas las tablas sincronizables.
  Future<int> contarPendientes() async {
    if (_sb.auth.currentSession == null) return 0;
    var total = 0;
    total += await _contarPendientesTabla(
        'predios', () => db.select(db.predios).get(),
        idOf: (r) => r.id, updatedOf: (r) => r.updatedAt);
    total += await _contarPendientesTabla(
        'proveedores', () => db.select(db.proveedores).get(),
        idOf: (r) => r.id, updatedOf: (r) => r.updatedAt);
    total += await _contarPendientesTabla(
        'lotes', () => db.select(db.lotes).get(),
        idOf: (r) => r.id, updatedOf: (r) => r.updatedAt);
    total += await _contarPendientesTabla(
        'cultivos', () => db.select(db.cultivos).get(),
        idOf: (r) => r.id, updatedOf: (r) => r.updatedAt);
    total += await _contarPendientesTabla(
        'condiciones_predio', () => db.select(db.condicionesPredio).get(),
        idOf: (r) => r.id, updatedOf: (r) => r.updatedAt);
    total += await _contarPendientesTabla(
        'inventarios', () => db.select(db.inventarios).get(),
        idOf: (r) => r.id, updatedOf: (r) => r.updatedAt);
    total += await _contarPendientesTabla(
        'analisis_suelo', () => db.select(db.analisisSuelo).get(),
        idOf: (r) => r.id, updatedOf: (r) => r.updatedAt);
    total += await _contarPendientesTabla(
        'compras', () => db.select(db.compras).get(),
        idOf: (r) => r.id, updatedOf: (r) => r.updatedAt);
    total += await _contarPendientesTabla(
        'eventos_cultivo', () => db.select(db.eventosCultivo).get(),
        idOf: (r) => r.id, updatedOf: (r) => r.updatedAt);
    // Tareas: cuentan solo las que no tienen mapping (nuevas).
    final tareas = await db.select(db.tareasCompletadas).get();
    final mapTareas = await _mappingsDe('tareas_completadas');
    for (final t in tareas) {
      if (!mapTareas.containsKey(t.id)) total++;
    }
    // Fase B5: operaciones encoladas (deletes remotos pendientes).
    total += (await db.select(db.syncOps).get()).length;
    return total;
  }

  Future<int> _contarPendientesTabla<T>(
    String tabla,
    Future<List<T>> Function() reader, {
    required int Function(T) idOf,
    required DateTime Function(T) updatedOf,
  }) async {
    // Auditoría P1: antes se consultaba sync_mappings fila por fila (N+1).
    // Ahora se cargan todos los mappings de la tabla en 1 consulta.
    final rows = await reader();
    final mappings = await _mappingsDe(tabla);
    var count = 0;
    for (final r in rows) {
      final m = mappings[idOf(r)];
      if (m == null || updatedOf(r).isAfter(m.lastPushedAt)) count++;
    }
    return count;
  }

  /// Todos los mappings de una tabla como mapa localId → fila, en una
  /// sola consulta (auditoría P1 — elimina el patrón N+1).
  Future<Map<int, SyncMapping>> _mappingsDe(String tabla) async {
    final rows = await (db.select(db.syncMappings)
          ..where((s) => s.tabla.equals(tabla)))
        .get();
    return {for (final r in rows) r.localId: r};
  }

  /// Igual que `_debeSubir` pero contra un mapa precargado (auditoría P1).
  bool _debeSubirEnMapa(
      Map<int, SyncMapping> mappings, int localId, DateTime updatedAt) {
    final m = mappings[localId];
    if (m == null) return true; // nunca subido
    return updatedAt.isAfter(m.lastPushedAt);
  }

  /// Reinicia el estado de pull/push y ejecuta un sync completo.
  ///
  /// Borra `syncTables` (los `lastPulledAt` por tabla) y resetea
  /// `lastPushedAt` a epoch en `syncMappings` para forzar la re-evaluación
  /// de todas las filas locales. Se mantienen los `remoteId` para que el
  /// re-push haga UPDATE en lugar de INSERT — así no se duplica nada en
  /// el remoto (los mergers hacen LWW por `updated_at`).
  ///
  /// Uso: cuando un colaborador recupera acceso a un predio y los
  /// registros históricos no bajaron (porque los pulls incrementales
  /// previos avanzaron el cut-off mientras RLS bloqueaba las filas).
  /// También sirve como remedio genérico si la BD local quedó atrasada
  /// o si un bug pasado dejó filas sin subir (p. ej. eventos con
  /// `fechaEjecutada` cuyo `updatedAt` no se bumpeó — bug 3e-9-11).
  Future<SyncResult> sincronizarDesdeCero() async {
    if (_sb.auth.currentSession == null) {
      return const SyncResult(
        pushed: 0,
        pulled: 0,
        error: 'No hay sesión iniciada',
        duration: Duration.zero,
      );
    }
    await db.delete(db.syncTables).go();
    // Reset lastPushedAt para forzar re-evaluación. Los remoteId se
    // preservan, así que el próximo push hace UPDATE por remote_id en
    // vez de INSERT. No hay riesgo de duplicados.
    await db.customStatement(
      'UPDATE sync_mappings SET last_pushed_at = 0',
    );
    return sincronizar();
  }

  /// Sincroniza todo. IMPORTANTE: pull PRIMERO, después push.
  /// Este orden es clave para el last-write-wins: primero se aplican los
  /// cambios remotos al local (respetando `updated_at`), y luego se suben
  /// los cambios locales que sigan siendo más nuevos. Si hiciéramos push
  /// primero, machacaríamos las ediciones remotas del usuario en la nube.
  Future<SyncResult> sincronizar() async {
    final start = DateTime.now();
    if (_sb.auth.currentSession == null) {
      return SyncResult(
        pushed: 0,
        pulled: 0,
        error: 'No hay sesión iniciada',
        duration: DateTime.now().difference(start),
      );
    }
    // Guard de reentrada (auditoría P6): el botón "Sincronizar ahora" y el
    // auto-sync por conectividad pueden coincidir; dos syncs concurrentes
    // sobre los mismos mappings producen duplicados y condiciones de carrera.
    if (_enCurso) {
      return SyncResult(
        pushed: 0,
        pulled: 0,
        error: 'Sincronización ya en curso',
        duration: DateTime.now().difference(start),
      );
    }
    _enCurso = true;
    _erroresFilas = 0;
    _permisoCache.clear();
    _propietarioCache.clear();
    try {
      // Auditoría S6: verificar versión del esquema remoto antes de tocar
      // datos. Si el servidor está desactualizado respecto a lo que este
      // cliente asume (RLS, triggers), se bloquea el sync por seguridad.
      final schemaError = await _verificarSchemaRemoto();
      if (schemaError != null) {
        return SyncResult(
          pushed: 0,
          pulled: 0,
          error: schemaError,
          duration: DateTime.now().difference(start),
        );
      }
      // Fase B5: ejecutar la cola de operaciones pendientes ANTES del
      // pull — un delete remoto encolado debe aplicarse antes de que el
      // pull pueda traer de vuelta la fila.
      await procesarColaPendiente();
      final pulled = await _pullAll();
      final pushed = await _pushAll();
      // Reconciliación local de eventos: a partir de las tareas locales
      // reconstruye qué eventos deben marcarse como completados. Esto
      // repara casos donde el remoto tiene eventos con fecha_ejecutada
      // NULL (bug pre-3e-9-11) — cada cliente cierra sus eventos según
      // sus propias tareas sin depender del estado de la nube.
      await _reconciliarEventosLocales();
      if (_erroresFilas > 0) {
        Log.w('[sync] terminado con $_erroresFilas fila(s) con error — '
            'revisar logs anteriores');
      }
      return SyncResult(
        pushed: pushed,
        pulled: pulled,
        errores: _erroresFilas,
        duration: DateTime.now().difference(start),
      );
    } catch (e, st) {
      Log.e('[sync] sincronizar() abortó', e, st);
      return SyncResult(
        pushed: 0,
        pulled: 0,
        errores: _erroresFilas,
        error: '$e',
        duration: DateTime.now().difference(start),
      );
    } finally {
      _enCurso = false;
    }
  }

  /// Auditoría S6: lee `public.schema_meta.version` y bloquea el sync si
  /// el servidor es anterior a lo requerido. Si la tabla aún no existe
  /// (proyectos sin la migración aplicada) NO bloquea — solo advierte —
  /// para no dejar inoperante la app antes de aplicar la migración.
  Future<String?> _verificarSchemaRemoto() async {
    try {
      final res =
          await _sb.from('schema_meta').select('version').maybeSingle();
      if (res == null) return null; // tabla vacía → no decidible
      final v = (res['version'] as num?)?.toInt() ?? 0;
      if (v < schemaRemotoRequerido) {
        return 'Esquema del servidor desactualizado (v$v < v$schemaRemotoRequerido). '
            'Aplique las migraciones de supabase/migrations/ en el dashboard.';
      }
      return null;
    } catch (e) {
      Log.w('[sync] schema_meta no disponible (¿migración S6 sin aplicar?): $e');
      return null;
    }
  }

  /// Para cada cultivo local no finalizado, corre la reconciliación de
  /// eventos: reabre todos los eventos, marca siembra/semillero por
  /// fecha_siembra, y para cada tarea completada cierra el primer evento
  /// coincidente pendiente. Idempotente. Los cambios bumpean updatedAt
  /// para que se propaguen al remoto en el próximo sync.
  Future<void> _reconciliarEventosLocales() async {
    try {
      final cultivos = await (db.select(db.cultivos)
            ..where((c) => c.deletedAt.isNull()))
          .get();
      final repo = CultivoRepository(db);
      for (final c in cultivos) {
        try {
          await repo.resincronizarEventos(c.id);
        } catch (_) {
          // Un cultivo problemático no debe romper la reconciliación de
          // los demás. Los errores individuales se silencian.
        }
      }
    } catch (e) {
      Log.w('[sync] _reconciliarEventosLocales fallo: $e');
    }
  }

  // Nota histórica: `_debeSubir` (consulta por fila) fue reemplazada por
  // `_debeSubirEnMapa` + `_mappingsDe` (auditoría P1). La semántica se
  // conserva: una fila se sube si nunca fue subida o si su `updatedAt`
  // local es posterior al último push exitoso. Cuando el pull acaba de
  // bajar un cambio remoto y hace `_saveMapping`, `lastPushedAt` se
  // actualiza a NOW() → no se re-sube lo que acabamos de bajar (evita el
  // ping-pong y evita machacar el remoto).

  // ==================================================
  // PUSH
  // ==================================================

  /// Push por lotes (auditoría P2). Antes cada fila generaba su propio
  /// request HTTP — con latencia rural (300–800 ms) subir 200 registros
  /// tomaba minutos. Ahora:
  ///   - Filas NUEVAS (sin mapping): upsert en chunks por
  ///     (owner_id, cliente_id); la respuesta trae id+cliente_id para
  ///     guardar los mappings.
  ///   - Filas EXISTENTES (con mapping): upsert en chunks con `id`
  ///     explícito (update por PK; las policies UPDATE de RLS aplican
  ///     igual que antes).
  /// Si un chunk falla (p. ej. una fila rechazada por RLS), se reintenta
  /// fila a fila para que una sola fila mala no bloquee a las demás.
  Future<int> _pushBatch(String tabla, List<_FilaPush> filas) async {
    if (filas.isEmpty) return 0;
    var count = 0;
    final nuevos = filas.where((f) => f.remoteId == null).toList();
    final existentes = filas.where((f) => f.remoteId != null).toList();

    // 1) NUEVOS — insert idempotente por (owner_id, cliente_id).
    for (var i = 0; i < nuevos.length; i += _batchSize) {
      final chunk = nuevos.sublist(i, min(i + _batchSize, nuevos.length));
      try {
        final res = await _sb
            .from(tabla)
            .upsert([for (final f in chunk) f.payload],
                onConflict: 'owner_id,cliente_id')
            .select('id, cliente_id');
        for (final raw in (res as List<dynamic>)) {
          final row = raw as Map<String, dynamic>;
          final localId = (row['cliente_id'] as num?)?.toInt();
          final remoteId = (row['id'] as num?)?.toInt();
          if (localId != null && remoteId != null) {
            await _saveMapping(tabla, localId, remoteId);
            count++;
          }
        }
      } catch (e) {
        Log.w('[sync] batch INSERT $tabla (${chunk.length} filas) falló, '
            'reintento fila a fila: $e');
        for (final f in chunk) {
          final id = await _upsert(tabla, f.payload, localId: f.localId);
          if (id != null) {
            await _saveMapping(tabla, f.localId, id);
            count++;
          }
        }
      }
    }

    // 2) EXISTENTES — update por PK remota.
    // IMPORTANTE: `.select('id')` verifica que RLS realmente escribió.
    // Sin eso, un upsert bloqueado por RLS "tiene éxito" en HTTP y
    // bumpeábamos lastPushedAt → el soft-delete nunca se reintentaba
    // (cultivo borrado por co-propietario no llegaba al remoto).
    for (var i = 0; i < existentes.length; i += _batchSize) {
      final chunk =
          existentes.sublist(i, min(i + _batchSize, existentes.length));
      try {
        final payloads = [
          for (final f in chunk)
            (Map<String, dynamic>.from(f.payload)
              // No tocar cliente_id/owner_id de una fila ajena (mismo
              // criterio que el UPDATE fila a fila anterior).
              ..remove('cliente_id')
              ..remove('owner_id')
              ..['id'] = f.remoteId)
        ];
        final res = await _sb.from(tabla).upsert(payloads).select('id');
        final written = <int>{
          for (final raw in (res as List<dynamic>))
            ((raw as Map<String, dynamic>)['id'] as num).toInt(),
        };
        for (final f in chunk) {
          final rid = f.remoteId!;
          if (written.contains(rid)) {
            await _saveMapping(tabla, f.localId, rid);
            count++;
          } else {
            _erroresFilas++;
            Log.w('[sync] UPDATE $tabla local=${f.localId} remote=$rid '
                'sin filas afectadas (¿RLS?) — no se marca como pusheado');
          }
        }
      } catch (e) {
        Log.w('[sync] batch UPDATE $tabla (${chunk.length} filas) falló, '
            'reintento fila a fila: $e');
        for (final f in chunk) {
          final id = await _upsert(tabla, f.payload,
              localId: f.localId, remoteId: f.remoteId);
          if (id != null) {
            await _saveMapping(tabla, f.localId, id);
            count++;
          }
        }
      }
    }
    return count;
  }

  /// Versión cacheada de `_puedoEditarPredioLocal` para el sync en curso
  /// (auditoría P1). El cache se limpia al inicio de cada `sincronizar()`.
  Future<bool> _puedoEditarPredioCached(int predioLocalId) async {
    final cached = _permisoCache[predioLocalId];
    if (cached != null) return cached;
    final v = await _puedoEditarPredioLocal(predioLocalId);
    _permisoCache[predioLocalId] = v;
    return v;
  }

  /// Versión cacheada de `_soyPropietarioPredioLocal` para compras.
  Future<bool> _soyPropietarioPredioCached(int predioLocalId) async {
    final cached = _propietarioCache[predioLocalId];
    if (cached != null) return cached;
    final v = await _soyPropietarioPredioLocal(predioLocalId);
    _propietarioCache[predioLocalId] = v;
    return v;
  }

  Future<int> _pushAll() async {
    var total = 0;
    // Orden topológico — nunca subir un hijo antes que su padre.
    total += await _pushPredios();
    total += await _pushProveedores();
    total += await _pushLotes();
    total += await _pushCondiciones();
    total += await _pushCultivos();
    total += await _pushCultivoPatologias();
    total += await _pushInventarios();
    total += await _pushAnalisis();
    total += await _pushCompras();
    total += await _pushEventos();
    total += await _pushTareas();
    total += await _pushColaboradores();
    return total;
  }

  /// Push de predio_colaboradores (locales) hacia predio_shares (remoto).
  /// Solo se envían las invitaciones que YO hago a otros (los shares
  /// que soy invitado los recibe el owner por su lado).
  Future<int> _pushColaboradores() async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return 0;
    final rows = await db.select(db.predioColaboradores).get();
    final mappings = await _mappingsDe('predio_colaboradores');
    final prediosMap = await _mappingsDe('predios');
    var count = 0;
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) {
        continue;
      }
      final predioRemote = prediosMap[r.predioId]?.remoteId;
      if (predioRemote == null) continue;
      if (r.colaboradorUserId == null) continue; // no puedo compartir sin uuid
      // Filas con rol='propietario': solo son subibles si YO soy el dueño
      // real del predio — es una invitación de co-propietario legítima
      // (2026-07-29: permite compartir compras con co-propietarios).
      //
      // Si NO soy el dueño, la fila es la informativa que `_mergeShare`
      // crea en la BD del INVITADO para mostrar al dueño en la card de
      // colaboradores. Subirla generaría un share invertido (yo como
      // owner, el propietario como shared_with_id) que al bajarse haría
      // aparecer a otro colaborador como "Propietario" (bug 2026-07-19).
      if (r.rol == 'propietario' && !await _soyOwnerRealDePredio(r.predioId)) {
        continue;
      }
      // NO subir mi fila representativa (colaboradorUserId == mi userId).
      // Solo existe en la BD local del invitado para que
      // `rolEnPredioProvider` sepa mi rol; subirla generaría un share
      // (owner=yo, shared_with=yo) espurio (Fase 3e-9-13).
      if (r.colaboradorUserId == userId) continue;
      // Incluir aceptado_at explícito: si el proyecto Postgres NO tiene
      // aplicado schema_3e_v4.sql (trigger autoaceptar_share), el share
      // quedaría en el remoto con aceptado_at=NULL y la RLS de la tabla
      // predios no dejaría verlo al colaborador. Enviar el valor local
      // garantiza que el share nace aceptado (auto-aceptación en el cliente).
      final aceptadoUtc =
          (r.aceptadoAt ?? DateTime.now()).toUtc().toIso8601String();
      final payload = <String, dynamic>{
        'predio_id': predioRemote,
        'owner_id': userId,
        'shared_with_id': r.colaboradorUserId,
        'rol': r.rol,
        'aceptado_at': aceptadoUtc,
        // updated_at: necesario para que el pull haga last-write-wins.
        // Se ignora silenciosamente por Postgres si la columna aún no
        // existe (proyectos sin fix_predio_shares_updated_at.sql aplicado)
        // — el push seguirá funcionando. En cuanto se aplique el schema
        // fix, este campo se persistirá y el LWW empezará a funcionar.
        'updated_at': r.updatedAt.toUtc().toIso8601String(),
      };
      try {
        // Si el registro está soft-deleted, hacemos DELETE remoto en su lugar
        if (r.deletedAt != null) {
          await _sb
              .from('predio_shares')
              .delete()
              .eq('predio_id', predioRemote)
              .eq('shared_with_id', r.colaboradorUserId as Object);
        } else {
          final res = await _sb
              .from('predio_shares')
              .upsert(payload, onConflict: 'predio_id,shared_with_id')
              .select('id')
              .maybeSingle();
          if (res != null && res['id'] != null) {
            await _saveMapping('predio_colaboradores', r.id, res['id'] as int);
          }
        }
        count++;
      } catch (e, st) {
        // Errores de RLS aquí son diagnósticos importantes (falta de la
        // policy UPDATE en predio_shares, etc.) — nunca silenciar.
        _erroresFilas++;
        Log.e(
            '[sync] _pushColaboradores fallo predio=$predioRemote '
            'shared_with=${r.colaboradorUserId} rol=${r.rol}',
            e,
            st);
      }
    }
    return count;
  }

  Future<int> _pushPredios() async {
    // NOTA: NO filtramos por deletedAt.isNull — necesitamos subir también
    // los soft-deletes para propagar los borrados a los otros dispositivos.
    final rows = await db.select(db.predios).get();
    final mappings = await _mappingsDe('predios');
    // Catálogos geográficos precargados (auditoría P1 — antes 3 consultas
    // por fila). Los catálogos no se sincronizan; se suben nombres.
    final paises = {for (final p in await db.select(db.paises).get()) p.id: p};
    final regiones = {
      for (final x in await db.select(db.regiones).get()) x.id: x
    };
    final municipios = {
      for (final m in await db.select(db.municipios).get()) m.id: m
    };
    final filas = <_FilaPush>[];
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      filas.add(_FilaPush(
        localId: r.id,
        remoteId: mappings[r.id]?.remoteId,
        payload: <String, dynamic>{
          'cliente_id': r.id,
          'nombre': r.nombre,
          'propietario': r.propietario,
          'pais_iso2': r.paisId == null ? null : paises[r.paisId!]?.iso2,
          'region_nombre':
              r.regionId == null ? null : regiones[r.regionId!]?.nombre,
          'municipio_nombre':
              r.municipioId == null ? null : municipios[r.municipioId!]?.nombre,
          'lat': r.lat,
          'lng': r.lng,
          'alt_m': r.altM,
          'notas': r.notas,
          'updated_at': r.updatedAt.toUtc().toIso8601String(),
          'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
        },
      ));
    }
    return _pushBatch('predios', filas);
  }

  Future<int> _pushProveedores() async {
    final rows = await db.select(db.proveedores).get();
    final mappings = await _mappingsDe('proveedores');
    final filas = <_FilaPush>[];
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      filas.add(_FilaPush(
        localId: r.id,
        remoteId: mappings[r.id]?.remoteId,
        payload: <String, dynamic>{
          'cliente_id': r.id,
          'nombre': r.nombre,
          'nit': r.nit,
          'telefono': r.telefono,
          'email': r.email,
          'web': r.web,
          'direccion': r.direccion,
          'notas': r.notas,
          'updated_at': r.updatedAt.toUtc().toIso8601String(),
          'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
        },
      ));
    }
    return _pushBatch('proveedores', filas);
  }

  Future<int> _pushLotes() async {
    final rows = await db.select(db.lotes).get();
    final mappings = await _mappingsDe('lotes');
    final prediosMap = await _mappingsDe('predios');
    final filas = <_FilaPush>[];
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      final predioRemote = prediosMap[r.predioId]?.remoteId;
      if (predioRemote == null) continue;
      // Skip proactivo: los lotes son R/W solo del propietario.
      if (!await _puedoEditarPredioCached(r.predioId)) continue;
      filas.add(_FilaPush(
        localId: r.id,
        remoteId: mappings[r.id]?.remoteId,
        payload: <String, dynamic>{
          'cliente_id': r.id,
          'predio_id': predioRemote,
          'nombre': r.nombre,
          'administrador': r.administrador,
          'altitud_msnm': r.altitudMsnm,
          'area_m2': r.areaM2,
          'poligono_geojson': r.poligonoGeoJson,
          'notas': r.notas,
          'updated_at': r.updatedAt.toUtc().toIso8601String(),
          'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
        },
      ));
    }
    return _pushBatch('lotes', filas);
  }

  Future<int> _pushCondiciones() async {
    // Se mantiene fila a fila: el onConflict es por `predio_id` (no por
    // cliente_id) y el volumen es bajo (1 fila por predio). Los mapas
    // precargados eliminan igualmente el N+1 (auditoría P1).
    final rows = await db.select(db.condicionesPredio).get();
    final mappings = await _mappingsDe('condiciones_predio');
    final prediosMap = await _mappingsDe('predios');
    var count = 0;
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      final predioRemote = prediosMap[r.predioId]?.remoteId;
      if (predioRemote == null) continue;
      // Skip proactivo: si ya no puedo editar este predio (ex-colaborador
      // o degradado a consultor) evitamos el 42501 y no rompemos el sync.
      if (!await _puedoEditarPredioCached(r.predioId)) continue;
      final payload = <String, dynamic>{
        'predio_id': predioRemote,
        'altitud_msnm': r.altitudMsnm,
        'precipitacion_anual_mm': r.precipitacionAnualMm,
        'temp_media_c': r.tempMediaC,
        'temp_min_c': r.tempMinC,
        'temp_max_c': r.tempMaxC,
        'humedad_relativa_pct': r.humedadRelativaPct,
        'zona_climatica': r.zonaClimatica,
        'piso_termico': r.pisoTermico,
        'fuente': r.fuente,
        'notas': r.notas,
        'updated_at': r.updatedAt.toUtc().toIso8601String(),
        'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
      };
      try {
        // condiciones tiene UNIQUE por predio_id (no por cliente_id)
        final res = await _sb
            .from('condiciones_predio')
            .upsert(payload, onConflict: 'predio_id')
            .select('id')
            .maybeSingle();
        if (res != null && res['id'] != null) {
          await _saveMapping('condiciones_predio', r.id, res['id'] as int);
          count++;
        }
      } catch (e) {
        _erroresFilas++;
        Log.w(
            '[sync] _pushCondiciones fallo predio=$predioRemote id=${r.id}: $e');
      }
    }
    return count;
  }

  Future<int> _pushCultivos() async {
    final rows = await db.select(db.cultivos).get();
    final mappings = await _mappingsDe('cultivos');
    final prediosMap = await _mappingsDe('predios');
    final lotesMap = await _mappingsDe('lotes');
    final plantas = {
      for (final p in await db.select(db.plantas).get()) p.id: p
    };
    final filas = <_FilaPush>[];
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      final predioRemote = prediosMap[r.predioId]?.remoteId;
      if (predioRemote == null) continue;
      // Skip proactivo: cultivos son R/W propietario+trabajador.
      if (!await _puedoEditarPredioCached(r.predioId)) continue;
      final loteRemote =
          r.loteId == null ? null : lotesMap[r.loteId!]?.remoteId;
      filas.add(_FilaPush(
        localId: r.id,
        remoteId: mappings[r.id]?.remoteId,
        payload: <String, dynamic>{
          'cliente_id': r.id,
          'predio_id': predioRemote,
          'lote_id': loteRemote,
          'planta_id_local': r.plantaId,
          'nombre_planta': plantas[r.plantaId]?.nombreComun,
          'nombre_lote': r.nombreLote,
          'fecha_siembra': _fmtDate(r.fechaSiembra),
          'fecha_cosecha_estimada': _fmtDateOrNull(r.fechaCosechaEstimada),
          'area_base_m2': r.areaBaseM2,
          'cantidad_semilla_base': r.cantidadSemillaBase,
          'cantidad_semilla_unidad_base': r.cantidadSemillaUnidadBase,
          'hh_total': r.hhTotal,
          'hora_valor': r.horaValor,
          'lat': r.lat,
          'lng': r.lng,
          'alt_m': r.altM,
          'finalizado_fecha': _fmtDateOrNull(r.finalizadoFecha),
          'notas': r.notas,
          'tipo_cultivo': r.tipoCultivo,
          'cosecha1_dias': r.cosecha1Dias,
          'cosecha2_dias': r.cosecha2Dias,
          'periodicidad_cosecha_dias': r.periodicidadCosechaDias,
          'esperanza_vida_dias': r.esperanzaVidaDias,
          'updated_at': r.updatedAt.toUtc().toIso8601String(),
          'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
        },
      ));
    }
    return _pushBatch('cultivos', filas);
  }

  Future<int> _pushCultivoPatologias() async {
    final rows = await db.select(db.cultivoPatologias).get();
    final mappings = await _mappingsDe('cultivo_patologias');
    final cultivosMap = await _mappingsDe('cultivos');
    final cultivosById = {
      for (final c in await db.select(db.cultivos).get()) c.id: c
    };
    final patologiasById = {
      for (final p in await db.select(db.patologias).get()) p.id: p
    };
    final filas = <_FilaPush>[];
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      final cultivoRemote = cultivosMap[r.cultivoId]?.remoteId;
      if (cultivoRemote == null) continue;
      final cultivo = cultivosById[r.cultivoId];
      if (cultivo == null) continue;
      if (!await _puedoEditarPredioCached(cultivo.predioId)) continue;
      final cat = r.patologiaId == null ? null : patologiasById[r.patologiaId!];
      final nombre = (r.patologiaNombre?.trim().isNotEmpty == true)
          ? r.patologiaNombre!.trim()
          : (cat?.nombreComun ?? '');
      dynamic intervenciones;
      try {
        intervenciones = jsonDecode(r.intervencionesJson);
      } catch (_) {
        intervenciones = [];
      }
      filas.add(_FilaPush(
        localId: r.id,
        remoteId: mappings[r.id]?.remoteId,
        payload: <String, dynamic>{
          'cliente_id': r.id,
          'cultivo_id': cultivoRemote,
          'patologia_nombre': nombre,
          'patologia_cientifico': cat?.nombreCientifico,
          'patologia_tipo': cat?.tipoManual ?? cat?.tipo,
          'fecha_deteccion': _fmtDate(r.fechaDeteccion),
          'severidad': r.severidad,
          'fuente_diagnostico': r.fuenteDiagnostico,
          'confianza': r.confianza,
          'resuelta_at': r.resueltaAt?.toUtc().toIso8601String(),
          'cura_fecha': _fmtDateOrNull(r.curaFecha),
          'intervenciones_json': intervenciones,
          'notas': r.notas,
          'lat': r.lat,
          'lng': r.lng,
          'alt_m': r.altM,
          'compartida': r.compartida,
          'updated_at': r.updatedAt.toUtc().toIso8601String(),
          'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
        },
      ));
    }
    if (filas.isEmpty) return 0;
    try {
      return await _pushBatch('cultivo_patologias', filas);
    } catch (e) {
      Log.w('[sync] push cultivo_patologias omitido (¿falta 0013?): $e');
      return 0;
    }
  }

  Future<int> _pushInventarios() async {
    final rows = await db.select(db.inventarios).get();
    var mappings = await _mappingsDe('inventarios');
    final prediosMap = await _mappingsDe('predios');
    // Pre-pasada: adopción de mapping por clave natural (predio +
    // descripcion + codigo) para filas locales sin mapping — evita crear
    // duplicados tras resetear sync. Solo consulta el remoto para las
    // filas que realmente lo necesitan.
    var huboAdopcion = false;
    for (final r in rows) {
      if (mappings.containsKey(r.id)) continue;
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      final predioRemote = prediosMap[r.predioId]?.remoteId;
      if (predioRemote == null) continue;
      try {
        final query = _sb
            .from('inventarios')
            .select('id')
            .eq('predio_id', predioRemote)
            .eq('descripcion', r.descripcion);
        final resList = r.codigo == null
            ? await query.isFilter('codigo', null).limit(1)
            : await query.eq('codigo', r.codigo as Object).limit(1);
        if ((resList as List).isNotEmpty) {
          final matchId = (resList.first as Map)['id'] as int;
          await _saveMapping('inventarios', r.id, matchId);
          huboAdopcion = true;
        }
      } catch (e) {
        // No crítico: si la búsqueda por clave natural falla, la fila se
        // subirá como nueva (idempotente por owner_id+cliente_id).
        Log.d('[sync] adopción inventario id=${r.id} no resuelta: $e');
      }
    }
    if (huboAdopcion) {
      mappings = await _mappingsDe('inventarios'); // refrescar
    }
    final filas = <_FilaPush>[];
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      final predioRemote = prediosMap[r.predioId]?.remoteId;
      if (predioRemote == null) continue;
      // Skip proactivo: inventario R/W propietario+trabajador.
      if (!await _puedoEditarPredioCached(r.predioId)) continue;
      filas.add(_FilaPush(
        localId: r.id,
        remoteId: mappings[r.id]?.remoteId,
        payload: <String, dynamic>{
          'cliente_id': r.id,
          'predio_id': predioRemote,
          'fecha': _fmtDate(r.fecha),
          'codigo': r.codigo,
          'descripcion': r.descripcion,
          'fabricante': r.fabricante,
          'cantidad_base': r.cantidadBase,
          'unidad_base': r.unidadBase,
          'notas': r.notas,
          'updated_at': r.updatedAt.toUtc().toIso8601String(),
          'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
        },
      ));
    }
    return _pushBatch('inventarios', filas);
  }

  Future<int> _pushAnalisis() async {
    final rows = await db.select(db.analisisSuelo).get();
    final mappings = await _mappingsDe('analisis_suelo');
    final prediosMap = await _mappingsDe('predios');
    final filas = <_FilaPush>[];
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      final predioRemote = prediosMap[r.predioId]?.remoteId;
      if (predioRemote == null) continue;
      // Skip proactivo: análisis de suelo R/W solo propietario.
      if (!await _puedoEditarPredioCached(r.predioId)) continue;
      final payload = <String, dynamic>{
        'cliente_id': r.id,
        'predio_id': predioRemote,
        'lote': r.lote,
        'fecha_muestreo': _fmtDate(r.fechaMuestreo),
        'laboratorio': r.laboratorio,
        'profundidad_cm': r.profundidadCm,
        'textura': r.textura,
        'densidad_g_cm3': r.densidadGCm3,
        'conductividad_ms_cm': r.conductividadMsCm,
        'ph': r.ph,
        'materia_organica_pct': r.materiaOrganicaPct,
        'n_ppm': r.nPpm,
        'p_ppm': r.pPpm,
        'k_ppm': r.kPpm,
        'ca_meq': r.caMeq,
        'mg_meq': r.mgMeq,
        'na_meq': r.naMeq,
        'cic_meq': r.cicMeq,
        's_ppm': r.sPpm,
        'b_ppm': r.bPpm,
        'notas': r.notas,
        'updated_at': r.updatedAt.toUtc().toIso8601String(),
        'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
      };
      filas.add(_FilaPush(
        localId: r.id,
        remoteId: mappings[r.id]?.remoteId,
        payload: payload,
      ));
    }
    return _pushBatch('analisis_suelo', filas);
  }

  Future<int> _pushCompras() async {
    final rows = await db.select(db.compras).get();
    final mappings = await _mappingsDe('compras');
    final prediosMap = await _mappingsDe('predios');
    final provMap = await _mappingsDe('proveedores');
    final filas = <_FilaPush>[];
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      final predioRemote = prediosMap[r.predioId]?.remoteId;
      if (predioRemote == null) continue;
      // Skip proactivo: compras R/W solo propietario (dueño o co-propietario).
      if (!await _soyPropietarioPredioCached(r.predioId)) continue;
      final provRemote =
          r.proveedorId == null ? null : provMap[r.proveedorId!]?.remoteId;
      filas.add(_FilaPush(
        localId: r.id,
        remoteId: mappings[r.id]?.remoteId,
        payload: <String, dynamic>{
          'cliente_id': r.id,
          'predio_id': predioRemote,
          'proveedor_id': provRemote,
          'fecha': _fmtDate(r.fecha),
          'descripcion1': r.descripcion1,
          'descripcion2': r.descripcion2,
          'valor_total': r.valorTotal,
          'cantidad_base': r.cantidadBase,
          'unidad_base': r.unidadBase,
          'codigo': r.codigo,
          'factura': r.factura,
          'tipo': r.tipo,
          'notas': r.notas,
          'created_by_user_id': r.createdByUserId,
          'updated_at': r.updatedAt.toUtc().toIso8601String(),
          'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
        },
      ));
    }
    return _pushBatch('compras', filas);
  }

  Future<int> _pushEventos() async {
    final rows = await db.select(db.eventosCultivo).get();
    final mappings = await _mappingsDe('eventos_cultivo');
    final cultivosMap = await _mappingsDe('cultivos');
    // Cultivos locales precargados para resolver el predio (permisos)
    // sin una consulta por fila (auditoría P1).
    final cultivosById = {
      for (final c in await db.select(db.cultivos).get()) c.id: c
    };
    final filas = <_FilaPush>[];
    for (final r in rows) {
      if (!_debeSubirEnMapa(mappings, r.id, r.updatedAt)) continue;
      final cultivoRemote = cultivosMap[r.cultivoId]?.remoteId;
      if (cultivoRemote == null) continue;
      // Skip proactivo: eventos R/W propietario+trabajador.
      // Se resuelve el predio a través del cultivo.
      final cultivo = cultivosById[r.cultivoId];
      if (cultivo == null) continue;
      if (!await _puedoEditarPredioCached(cultivo.predioId)) continue;
      filas.add(_FilaPush(
        localId: r.id,
        remoteId: mappings[r.id]?.remoteId,
        payload: <String, dynamic>{
          'cliente_id': r.id,
          'cultivo_id': cultivoRemote,
          'tipo': r.tipo,
          'fecha_programada': _fmtDateOrNull(r.fechaProgramada),
          'fecha_ejecutada': _fmtDateOrNull(r.fechaEjecutada),
          'descripcion': r.descripcion,
          'notas': r.notas,
          'updated_at': r.updatedAt.toUtc().toIso8601String(),
          'deleted_at': r.deletedAt?.toUtc().toIso8601String(),
        },
      ));
    }
    return _pushBatch('eventos_cultivo', filas);
  }

  Future<int> _pushTareas() async {
    final rows = await db.select(db.tareasCompletadas).get();
    final mappings = await _mappingsDe('tareas_completadas');
    final cultivosMap = await _mappingsDe('cultivos');
    final cultivosById = {
      for (final c in await db.select(db.cultivos).get()) c.id: c
    };
    final filas = <_FilaPush>[];
    for (final r in rows) {
      // Tareas son inmutables: si ya hay mapping, no volver a subir.
      if (mappings.containsKey(r.id)) continue;
      final cultivoRemote = cultivosMap[r.cultivoId]?.remoteId;
      if (cultivoRemote == null) continue;
      // Skip proactivo: tareas R/W propietario+trabajador.
      final cultivo = cultivosById[r.cultivoId];
      if (cultivo == null) continue;
      if (!await _puedoEditarPredioCached(cultivo.predioId)) continue;
      filas.add(_FilaPush(
        localId: r.id,
        // Sin mapping → siempre van por la ruta de "nuevos" del batch.
        payload: <String, dynamic>{
          'cliente_id': r.id,
          'cultivo_id': cultivoRemote,
          'fecha': _fmtDate(r.fecha),
          'hh': r.hh,
          'actividades_json': jsonDecode(r.actividadesJson),
          'insumos_json': jsonDecode(r.insumosJson),
          'notas': r.notas,
          // Fase 3g: autor. En batch todos los payloads deben tener las
          // mismas claves; se envía null y el trigger
          // `tareas_completadas_autor` lo rellena con auth.uid().
          'created_by_user_id': r.createdByUserId,
        },
      ));
    }
    return _pushBatch('tareas_completadas', filas);
  }

  // ==================================================
  // PULL
  // ==================================================
  Future<int> _pullAll() async {
    var total = 0;
    total += await _pullTable('predios', _mergePredio);
    total += await _pullTable('proveedores', _mergeProveedor);
    total += await _pullTable('lotes', _mergeLote);
    total += await _pullTable('condiciones_predio', _mergeCondiciones);
    total += await _pullTable('cultivos', _mergeCultivo);
    // Repara plantaId corruptos por el bug de `planta_id_local` ajeno
    // (incluso si el pull incremental no re-trajo la fila del cultivo).
    final reparadosPlanta = await _repararPlantaIdsDesdeNombreRemoto();
    if (reparadosPlanta > 0) {
      Log.i('[sync] reparados $reparadosPlanta cultivo(s) con plantaId '
          'incorrecto (nombre_planta remoto)');
    }
    try {
      total += await _pullTable('cultivo_patologias', _mergeCultivoPatologia);
    } catch (e) {
      // Tabla ausente hasta aplicar migration 0013.
      Log.w('[sync] pull cultivo_patologias omitido: $e');
    }
    total += await _pullTable('inventarios', _mergeInventario);
    total += await _pullTable('analisis_suelo', _mergeAnalisis);
    total += await _pullTable('compras', _mergeCompra);
    total += await _pullTable('eventos_cultivo', _mergeEvento);
    // Tareas son inmutables → filtran por created_at (no tienen updated_at
    // en la tabla remota).
    total += await _pullTable('tareas_completadas', _mergeTarea,
        timestampCol: 'created_at');
    // Colaboraciones (predio_shares) — filtra por updated_at para captar
    // cambios de rol (invitado_at es inmutable). Requiere que Postgres
    // tenga aplicado supabase/fix_predio_shares_updated_at.sql.
    total += await _pullTable('predio_shares', _mergeShare,
        timestampCol: 'updated_at');
    // Backfill: predios locales con mapping remoto pero sin ownerUserId
    // (creados en versiones anteriores del schema local). Sin esto no
    // funciona la detección de rol en la UI.
    await _backfillOwnerIds();
    // Segunda pasada: recuperar predios/lotes/etc. cuya visibilidad depende
    // de un share que acabamos de descubrir en esta sincronización.
    // Escenario: el owner subió share+predio en un mismo push; el pull de
    // predios corrió PRIMERO — si por RLS (proyectos sin schema_3e_v4.sql
    // aplicado) el predio no era visible aún, ahora que el share está en
    // Postgres SÍ lo será. Reintentamos ignorando el timestamp del primer
    // pass para forzar la revalidación por RLS.
    total += await _repullPrediosCompartidos();
    // Hidratación completa (one-shot con marcador persistente) de los
    // predios compartidos conmigo: el pull incremental de arriba nunca
    // baja las filas históricas del owner (updated_at < mi lastPulledAt),
    // así que la primera vez que un predio ajeno aparece hay que traer
    // TODO su contenido por predio_id/cultivo_id ignorando timestamps.
    total += await _hidratarPrediosCompartidos();
    // Detectar shares eliminados: si el owner me removió como colaborador
    // el remoto hace DELETE físico (no soft-delete) → el pull incremental
    // no lo trae. Aquí comparamos el conjunto remoto con el local para
    // marcar el share como deletedAt y desactivarlo en la UI.
    await _purgarSharesEliminados();
    // Limpiar filas locales con rol='propietario' que se colaron por
    // el bug histórico donde el colaborador subía su fila informativa
    // del owner como si fuera un share invertido.
    await _limpiarSharesInvertidos();
    return total;
  }

  /// Purga filas locales con rol='propietario' que no se explican por
  /// ninguno de los casos legítimos:
  ///   - la fila informativa del owner real (para mostrarlo al invitado);
  ///   - mi propia fila de rol (la que consulta `rolEnPredioProvider`);
  ///   - un co-propietario que YO invité en un predio de mi propiedad
  ///     (2026-07-29 — habilita compartir compras con co-propietarios).
  /// Cualquier otra es residuo del bug histórico de shares invertidos.
  Future<void> _limpiarSharesInvertidos() async {
    final userId = _sb.auth.currentUser?.id;
    try {
      final filas = await (db.select(db.predioColaboradores)
            ..where((c) => c.rol.equals('propietario'))
            ..where((c) => c.deletedAt.isNull()))
          .get();
      for (final f in filas) {
        final predio = await (db.select(db.predios)
              ..where((p) => p.id.equals(f.predioId)))
            .getSingleOrNull();
        if (predio == null) continue;
        final ownerReal = predio.ownerUserId;
        if (ownerReal == null) continue; // sin ownerId → no puedo decidir
        if (f.colaboradorUserId == ownerReal) continue; // fila del owner real
        if (userId == null) continue;
        if (f.colaboradorUserId == userId) continue; // mi propia fila de rol
        if (ownerReal == userId) continue; // co-propietario que yo invité
        // La fila apunta a un tercero en un predio ajeno → invertida.
        await (db.delete(db.predioColaboradores)
              ..where((c) => c.id.equals(f.id)))
            .go();
      }
    } catch (e) {
      Log.w('[sync] _limpiarSharesInvertidos fallo: $e');
    }
  }

  /// Reconciliación de shares eliminados desde el remoto.
  ///
  /// Comparamos los shares locales activos donde YO soy el colaborador
  /// contra los que existen ahora en `predio_shares` remoto para mi user.
  /// Los que ya no están en el remoto se marcan como `deletedAt=now` en
  /// local — el predio se conserva (histórico), pero `rolEnPredio`
  /// pasará a `null` y la UI mostrará el estado "sin acceso".
  Future<void> _purgarSharesEliminados() async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final remoteShares = await _sb
          .from('predio_shares')
          .select('id, predio_id')
          .eq('shared_with_id', userId);
      final remoteShareIds = <int>{
        for (final s in (remoteShares as List<dynamic>))
          (s as Map<String, dynamic>)['id'] as int,
      };
      final remotePrediosConShare = <int>{
        for (final s in (remoteShares as List<dynamic>))
          (s as Map<String, dynamic>)['predio_id'] as int,
      };
      // Filas locales activas donde soy el colaborador.
      final localesActivos = await (db.select(db.predioColaboradores)
            ..where((c) => c.colaboradorUserId.equals(userId))
            ..where((c) => c.deletedAt.isNull()))
          .get();
      for (final local in localesActivos) {
        final mapped = await _resolveRemoteId('predio_colaboradores', local.id);
        if (mapped != null) {
          // Fila subida al remoto (share que otro me invitó a mí): comparar
          // con el id remoto conocido.
          if (remoteShareIds.contains(mapped)) continue;
        } else {
          // Fila representativa mía (nunca subida): comparar por predio.
          // Si aún hay un share activo en el remoto sobre ese predio,
          // no purgar.
          final predioRemote =
              await _resolveRemoteId('predios', local.predioId);
          if (predioRemote == null) continue; // no puedo decidir
          if (remotePrediosConShare.contains(predioRemote)) continue;
        }
        // El share desapareció del remoto → el owner me removió.
        await (db.update(db.predioColaboradores)
              ..where((c) => c.id.equals(local.id)))
            .write(PredioColaboradoresCompanion(
          deletedAt: Value(DateTime.now()),
          updatedAt: Value(DateTime.now()),
        ));
      }
    } catch (e) {
      Log.w('[sync] _purgarSharesEliminados fallo: $e');
    }
  }

  /// Reintenta bajar predios que ahora deberían ser visibles gracias a un
  /// share recién descubierto en esta ronda. Solo trae los predios cuyo
  /// `id` remoto aparece en los shares locales donde YO soy el invitado y
  /// que todavía NO tienen un mapping local (o el predio local no existe).
  Future<int> _repullPrediosCompartidos() async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return 0;
    try {
      // Shares donde YO soy el invitado (colaborador). Uso predio_shares
      // remoto porque la BD local ya se pobló con _mergeShare arriba, pero
      // consultar el remoto directo evita depender del mapping local.
      final shares = await _sb
          .from('predio_shares')
          .select('predio_id')
          .eq('shared_with_id', userId);
      final remoteIds = <int>{
        for (final s in (shares as List<dynamic>))
          (s as Map<String, dynamic>)['predio_id'] as int,
      };
      if (remoteIds.isEmpty) return 0;
      // Filtra los que aún no tienen predio local visible.
      final faltantes = <int>[];
      for (final remoteId in remoteIds) {
        final localId = await _resolveLocalId('predios', remoteId);
        if (localId == null) {
          faltantes.add(remoteId);
          continue;
        }
        final localExiste = await (db.select(db.predios)
              ..where((p) => p.id.equals(localId))
              ..where((p) => p.deletedAt.isNull()))
            .getSingleOrNull();
        if (localExiste == null) faltantes.add(remoteId);
      }
      if (faltantes.isEmpty) return 0;
      // Trae los predios explícitamente por id, sin filtro por updated_at.
      final rows = await _sb.from('predios').select().inFilter('id', faltantes);
      var count = 0;
      for (final raw in (rows as List<dynamic>)) {
        try {
          await _mergePredio(raw as Map<String, dynamic>);
          count++;
        } catch (_) {}
      }
      // Y ahora re-mergeamos los shares locales cuyo predio faltaba, para
      // que _mergeShare pueda enlazarlos ahora que sí existe la fila local.
      if (count > 0) {
        final shareRows = await _sb
            .from('predio_shares')
            .select()
            .inFilter('predio_id', faltantes);
        for (final raw in (shareRows as List<dynamic>)) {
          try {
            await _mergeShare(raw as Map<String, dynamic>);
          } catch (_) {}
        }
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  /// Para cada predio local con mapping remoto pero `ownerUserId=null`,
  /// consulta el server y guarda el owner_id remoto. Ejecuta una sola vez
  /// por predio (después ya no se dispara porque owner_id ya no es null).
  Future<void> _backfillOwnerIds() async {
    final predios = await (db.select(db.predios)
          ..where((p) => p.ownerUserId.isNull()))
        .get();
    for (final p in predios) {
      final remoteId = await _resolveRemoteId('predios', p.id);
      if (remoteId == null) continue;
      try {
        final res = await _sb
            .from('predios')
            .select('owner_id')
            .eq('id', remoteId)
            .maybeSingle();
        if (res != null && res['owner_id'] != null) {
          await (db.update(db.predios)..where((x) => x.id.equals(p.id))).write(
            PrediosCompanion(
                ownerUserId: Value(res['owner_id'] as String)),
          );
        }
      } catch (_) {}
    }
  }

  /// Merge de predio_shares: si yo soy el shared_with_id, aparecerá el
  /// predio en mi selector. Si soy owner_id, veo qué colaboradores tengo.
  Future<void> _mergeShare(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final predioRemoteId = row['predio_id'] as int;
    final predioLocalId = await _resolveLocalId('predios', predioRemoteId);
    if (predioLocalId == null) return; // aún no bajamos ese predio
    final userId = _sb.auth.currentUser?.id;
    final ownerId = row['owner_id'] as String;
    final sharedId = row['shared_with_id'] as String;
    final rolInvitado = row['rol'] as String;
    // Descarta shares invertidos legados: `owner_id` que no coincide con el
    // dueño real del predio (residuo del bug 2026-07-19, ver también
    // supabase/fix_shares_invertidos.sql). Sin este filtro, un share
    // espurio reaparece en cada pull y pinta a un colaborador cualquiera
    // como "Propietario".
    final predioLocal = await (db.select(db.predios)
          ..where((p) => p.id.equals(predioLocalId)))
        .getSingleOrNull();
    final ownerRealPredio = predioLocal?.ownerUserId;
    if (ownerRealPredio != null && ownerRealPredio != ownerId) {
      Log.w('[sync] share invertido ignorado (predio=$predioRemoteId, '
          'owner_id=${_short(ownerId)} ≠ dueño ${_short(ownerRealPredio)})');
      return;
    }
    // Determina el "otro" y el rol REAL de ese otro:
    //   - si yo soy dueño (ownerId==userId): el otro es el invitado con
    //     el rol que le asigné (rolInvitado).
    //   - si yo soy el invitado: el otro es el DUEÑO, cuyo rol es
    //     'propietario' (no rolInvitado, que era mi rol como invitado).
    final String otro;
    final String rolOtro;
    if (ownerId == userId) {
      otro = sharedId;
      rolOtro = rolInvitado;
    } else {
      otro = ownerId;
      rolOtro = 'propietario';
    }
    // Consulta el email real vía RPC (SECURITY DEFINER en Postgres).
    // Si falla, cae al UUID truncado para no bloquear el sync.
    String? emailOtro;
    try {
      final res = await _sb.rpc('email_de_usuario', params: {'p_user_id': otro});
      emailOtro = res as String?;
    } catch (_) {}
    final displayEmail = emailOtro ?? '(usuario ${_short(otro)})';

    // Deduplicación: buscar por (predioId, colaboradorUserId) antes que por
    // mapping. Si ya existe una fila local con ese par, la actualizo (aunque
    // el mapping esté para otro remoteId). Esto corrige duplicados generados
    // por sync anteriores donde el push y el pull crearon dos filas locales.
    // IMPORTANTE: incluir también las eliminadas (deletedAt != null) — un
    // share que fue removido y luego re-invitado debe reactivar la fila
    // local en lugar de crear una nueva.
    final existente = await (db.select(db.predioColaboradores)
          ..where((c) => c.predioId.equals(predioLocalId))
          ..where((c) => c.colaboradorUserId.equals(otro))
          ..limit(1))
        .getSingleOrNull();

    // Detecta si estamos "recuperando acceso": el share llega vivo desde
    // el remoto y localmente no existía, estaba marcado como eliminado
    // por `_purgarSharesEliminados`, o el rol cambió (p. ej. consultor →
    // trabajador, o cualquier bump que pudiera haber traído registros
    // que RLS previamente bloqueaba). Solo aplica si soy YO el
    // colaborador — las apariciones de shares hacia otros no requieren
    // backfill en mi BD.
    final soyElColaborador = userId == sharedId;
    final rolCambio = existente != null && existente.rol != rolOtro;
    final recuperandoAcceso = soyElColaborador &&
        (existente == null || existente.deletedAt != null || rolCambio);

    // Last-write-wins por updated_at. Si el remoto trae updated_at úsalo;
    // si no (por proyectos Postgres que aún no aplicaron el schema con
    // updated_at en predio_shares), cae a invitado_at como aproximación.
    // Si el local es más nuevo, solo enlazamos el mapping sin sobrescribir
    // el contenido — evita que el pull machaque un cambio de rol local
    // que aún no se ha subido.
    final remoteUpdated = _parseDateOrNull(row['updated_at']) ??
        _parseDate(row['invitado_at']);
    if (existente != null &&
        existente.deletedAt == null &&
        existente.updatedAt.isAfter(remoteUpdated)) {
      // Local activo y más nuevo: solo actualiza el mapping (sin bump)
      // para que el próximo push pueda propagar el cambio local al remoto.
      await _saveMapping('predio_colaboradores', existente.id, remoteId,
          bumpLastPushed: false);
      return;
    }

    final companion = PredioColaboradoresCompanion(
      predioId: Value(predioLocalId),
      colaboradorEmail: Value(displayEmail),
      colaboradorUserId: Value(otro),
      rol: Value(rolOtro),
      aceptadoAt: Value(_parseDateOrNull(row['aceptado_at'])),
      invitadoAt: Value(_parseDate(row['invitado_at'])),
      // El share existe en el remoto → localmente no está eliminado.
      // Necesario para revivir filas purgadas por `_purgarSharesEliminados`.
      deletedAt: const Value<DateTime?>(null),
      // Guarda el updated_at del remoto para futuros last-write-wins.
      updatedAt: Value(remoteUpdated),
    );

    if (existente != null) {
      await (db.update(db.predioColaboradores)
            ..where((c) => c.id.equals(existente.id)))
          .write(companion);
      // bumpLastPushed:false porque esto es un pull, no un push. Si lo
      // bumpeáramos, un cambio local posterior con updatedAt < NOW() no
      // se detectaría como pendiente en el próximo _debeSubir.
      await _saveMapping('predio_colaboradores', existente.id, remoteId,
          bumpLastPushed: false);
      // Purga otros duplicados con el mismo par (predio, user), dejando solo `existente`
      await (db.delete(db.predioColaboradores)
            ..where((c) => c.predioId.equals(predioLocalId))
            ..where((c) => c.colaboradorUserId.equals(otro))
            ..where((c) => c.id.isNotValue(existente.id)))
          .go();
    } else {
      final newId =
          await db.into(db.predioColaboradores).insert(companion);
      await _saveMapping('predio_colaboradores', newId, remoteId,
          bumpLastPushed: false);
    }

    // Fila representativa del rol propio del invitado: si YO soy el
    // colaborador, además de la fila del owner informativo, persistir
    // mi propio rol en la BD local con `colaboradorUserId=userId`. Esta
    // fila NO se sube al remoto (la filtra `_pushColaboradores`) pero
    // es lo que consulta `rolEnPredioProvider` en la UI para decidir
    // permisos. Sin esto el rol de B siempre queda como null y B pierde
    // todos los permisos de edición aunque el share remoto diga
    // "trabajador" (bug 2026-07-19).
    if (soyElColaborador) {
      final miEmail = _sb.auth.currentUser?.email ?? '(yo)';
      final miExistente = await (db.select(db.predioColaboradores)
            ..where((c) => c.predioId.equals(predioLocalId))
            ..where((c) => c.colaboradorUserId.equals(userId!))
            ..limit(1))
          .getSingleOrNull();
      final miCompanion = PredioColaboradoresCompanion(
        predioId: Value(predioLocalId),
        colaboradorEmail: Value(miEmail),
        colaboradorUserId: Value(userId),
        rol: Value(rolInvitado),
        aceptadoAt: Value(_parseDateOrNull(row['aceptado_at'])),
        invitadoAt: Value(_parseDate(row['invitado_at'])),
        deletedAt: const Value<DateTime?>(null),
        updatedAt: Value(remoteUpdated),
      );
      if (miExistente != null) {
        await (db.update(db.predioColaboradores)
              ..where((c) => c.id.equals(miExistente.id)))
            .write(miCompanion);
      } else {
        await db.into(db.predioColaboradores).insert(miCompanion);
      }
    }

    // Al recuperar acceso (share nuevo, revivido o con cambio de rol) se
    // invalida el marcador de hidratación del predio: los pulls
    // incrementales previos avanzaron `lastPulledAt` sin bajar filas que
    // RLS bloqueaba, así que hay que volver a traer TODO lo del predio.
    // La descarga en sí la hace `_hidratarPrediosCompartidos()` al final
    // de `_pullAll()` — con marcador persistente y reintento si falla.
    if (recuperandoAcceso) {
      await _invalidarHidratacionPredio(predioRemoteId);
      await _invalidarPullTabla('proveedores');
      await _invalidarPullTabla('cultivo_patologias');
    }
  }

  /// Reinicia el cursor incremental de una tabla para forzar re-pull completo
  /// en la próxima sincronización (p. ej. al recuperar acceso a un predio).
  Future<void> _invalidarPullTabla(String tabla) async {
    await db.into(db.syncTables).insertOnConflictUpdate(
          SyncTablesCompanion.insert(
            tabla: tabla,
            lastPulledAt: Value(DateTime.fromMillisecondsSinceEpoch(0)),
            lastAttemptAt: Value(DateTime.now()),
          ),
        );
  }

  /// Prefijo de los marcadores de hidratación en `syncTables`. Son filas
  /// pseudo-tabla (`hidratado_predio_<remoteId>_<rol>`) que registran que
  /// un predio compartido ya se descargó completo con ese rol. Se borran
  /// junto con el resto de `syncTables` en logout/mantenimiento, lo que
  /// fuerza una rehidratación — comportamiento deseado.
  static const _prefijoHidratacion = 'hidratado_predio_';

  /// Borra los marcadores de hidratación de un predio (todos los roles).
  Future<void> _invalidarHidratacionPredio(int predioRemoteId) async {
    await (db.delete(db.syncTables)
          ..where((s) => s.tabla.like('$_prefijoHidratacion${predioRemoteId}_%')))
        .go();
  }

  /// Hidratación one-shot de predios compartidos conmigo, controlada por
  /// ESTADO y no por evento: en cada sync, para cada predio ajeno donde
  /// tengo un share activo, verifica un marcador persistente en
  /// `syncTables`; si no existe, baja TODO el contenido del predio con
  /// `_backfillRecursosDePredio` y solo entonces escribe el marcador.
  ///
  /// Esto cubre los huecos del disparo por evento en `_mergeShare`:
  ///   - shares que ya existían localmente antes de que existiera el
  ///     backfill (colaboradores atascados con solo predio+lotes);
  ///   - backfills interrumpidos a mitad (red): sin marcador → reintento
  ///     automático en la próxima sincronización;
  ///   - ascensos de rol (el marcador incluye el rol: trabajador →
  ///     propietario rehidrata y ahora sí bajan las compras).
  Future<int> _hidratarPrediosCompartidos() async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return 0;
    var total = 0;
    try {
      // Mis filas de rol activas (predios donde soy colaborador).
      final misShares = await (db.select(db.predioColaboradores)
            ..where((c) => c.colaboradorUserId.equals(userId))
            ..where((c) => c.deletedAt.isNull()))
          .get();
      for (final share in misShares) {
        final predio = await (db.select(db.predios)
              ..where((p) => p.id.equals(share.predioId))
              ..where((p) => p.deletedAt.isNull()))
            .getSingleOrNull();
        if (predio == null) continue;
        // Mis propios predios ya se cubren con el pull incremental normal.
        if (predio.ownerUserId == null || predio.ownerUserId == userId) {
          continue;
        }
        final predioRemote = await _resolveRemoteId('predios', share.predioId);
        if (predioRemote == null) continue;
        final marcador = '$_prefijoHidratacion${predioRemote}_${share.rol}';
        final ya = await (db.select(db.syncTables)
              ..where((s) => s.tabla.equals(marcador)))
            .getSingleOrNull();
        if (ya != null) continue;
        final resultado = await _backfillRecursosDePredio(share.predioId);
        total += resultado.filas;
        // Solo se marca como hidratado si TODAS las tablas respondieron.
        // Si alguna falló (p. ej. se cayó la red a mitad), el marcador no
        // se escribe y la próxima sincronización lo reintenta.
        if (resultado.completo) {
          await db.into(db.syncTables).insertOnConflictUpdate(
                SyncTablesCompanion.insert(
                  tabla: marcador,
                  lastPulledAt: Value(DateTime.now()),
                  lastAttemptAt: Value(DateTime.now()),
                ),
              );
        }
      }
    } catch (e) {
      Log.w('[sync] _hidratarPrediosCompartidos fallo: $e');
    }
    return total;
  }

  /// Trae todos los recursos ligados a un predio sin filtro incremental.
  /// Se usa cuando el usuario tiene acceso a un predio compartido cuyos
  /// datos históricos nunca llegaron: los pulls incrementales anteriores
  /// no vieron esas filas por RLS, y luego el `lastPulledAt` avanzó
  /// dejándolas fuera del cut-off. Recupera sin duplicar (los mergers
  /// hacen LWW por updated_at contra la copia local).
  ///
  /// Devuelve las filas mergeadas y si el backfill fue COMPLETO (ninguna
  /// tabla falló). Los errores de fila individual se registran pero no
  /// marcan el backfill como incompleto — una fila corrupta permanente no
  /// debe provocar re-descargas infinitas del predio entero.
  Future<({int filas, bool completo})> _backfillRecursosDePredio(
      int predioLocalId) async {
    final predioRemote = await _resolveRemoteId('predios', predioLocalId);
    if (predioRemote == null) return (filas: 0, completo: false);
    var total = 0;
    var completo = true;

    // Aplica el merger a cada fila, paginando: PostgREST trunca en
    // silencio a su límite por defecto (auditoría P3) y un predio grande
    // (p. ej. tareas_completadas) puede superarlo.
    Future<void> mergearPaginado(
      String tabla,
      PostgrestFilterBuilder<List<Map<String, dynamic>>> Function() query,
      Future<void> Function(Map<String, dynamic>) merger,
    ) async {
      try {
        var offset = 0;
        while (true) {
          final rows = await query()
              .order('id', ascending: true)
              .range(offset, offset + _pageSize - 1);
          for (final raw in rows) {
            try {
              await merger(raw);
              total++;
            } catch (e) {
              _erroresFilas++;
              Log.w('[sync] backfill $tabla: fila id=${raw['id']} '
                  'descartada: $e');
            }
          }
          if (rows.length < _pageSize) break;
          offset += _pageSize;
        }
      } catch (e) {
        completo = false;
        _erroresFilas++;
        Log.w(
            '[sync] _backfillRecursosDePredio($tabla, predio=$predioRemote) fallo: $e');
      }
    }

    Future<void> pullPorPredio(
      String tabla,
      Future<void> Function(Map<String, dynamic>) merger,
    ) =>
        mergearPaginado(
            tabla, () => _sb.from(tabla).select().eq('predio_id', predioRemote), merger);

    await pullPorPredio('lotes', _mergeLote);
    await pullPorPredio('condiciones_predio', _mergeCondiciones);
    await pullPorPredio('cultivos', _mergeCultivo);
    await pullPorPredio('inventarios', _mergeInventario);
    await pullPorPredio('analisis_suelo', _mergeAnalisis);
    // Compras: R/W solo propietario (dueño o colaborador invitado como
    // propietario). Trabajador/consultor no ven ni editan compras (RLS).
    if (await _soyPropietarioPredioCached(predioLocalId)) {
      await pullPorPredio('compras', _mergeCompra);
    }

    // Eventos y tareas están ligadas a cultivo_id. Resolvemos los ids
    // remotos de los cultivos del predio y hacemos un `inFilter`.
    try {
      final cultivosRows = await _sb
          .from('cultivos')
          .select('id')
          .eq('predio_id', predioRemote);
      final cultivoIds = <int>[
        for (final c in (cultivosRows as List<dynamic>))
          (c as Map<String, dynamic>)['id'] as int,
      ];
      if (cultivoIds.isNotEmpty) {
        Future<void> pullPorCultivo(
          String tabla,
          Future<void> Function(Map<String, dynamic>) merger,
        ) =>
            mergearPaginado(
                tabla,
                () => _sb.from(tabla).select().inFilter('cultivo_id', cultivoIds),
                merger);

        await pullPorCultivo('eventos_cultivo', _mergeEvento);
        await pullPorCultivo('tareas_completadas', _mergeTarea);
        try {
          await pullPorCultivo('cultivo_patologias', _mergeCultivoPatologia);
        } catch (e) {
          // Migration 0013 aún no aplicada: no marcar backfill incompleto
          // de forma permanente si la tabla no existe.
          Log.w('[sync] backfill cultivo_patologias omitido: $e');
        }
      }
    } catch (e) {
      completo = false;
      _erroresFilas++;
      Log.w('[sync] _backfillRecursosDePredio cultivos-ids fallo: $e');
    }

    // Proveedores del equipo (dueño + co-propietarios/trabajadores): no
    // tienen predio_id; el pull incremental pudo avanzar el cursor antes
    // de que RLS permitiera ver el directorio compartido.
    if (await _puedoEditarPredioCached(predioLocalId)) {
      try {
        total += await _pullProveedoresEquipoPredio(predioLocalId);
      } catch (e) {
        completo = false;
        _erroresFilas++;
        Log.w('[sync] _backfillRecursosDePredio proveedores-equipo fallo: $e');
      }
    }

    return (filas: total, completo: completo);
  }

  /// Baja proveedores de dueño y colaboradores propietario/trabajador del
  /// predio (directorio compartido del equipo).
  Future<int> _pullProveedoresEquipoPredio(int predioLocalId) async {
    final predio = await (db.select(db.predios)
          ..where((p) => p.id.equals(predioLocalId)))
        .getSingleOrNull();
    if (predio == null) return 0;

    final ownerIds = <String>{};
    if (predio.ownerUserId != null) ownerIds.add(predio.ownerUserId!);

    final cols = await (db.select(db.predioColaboradores)
          ..where((c) => c.predioId.equals(predioLocalId))
          ..where((c) => c.deletedAt.isNull())
          ..where((c) => c.rol.isIn(['propietario', 'trabajador'])))
        .get();
    for (final c in cols) {
      final uid = c.colaboradorUserId;
      if (uid != null && uid.isNotEmpty) ownerIds.add(uid);
    }

    var count = 0;
    for (final ownerId in ownerIds) {
      var offset = 0;
      while (true) {
        List<dynamic> rows;
        try {
          rows = await _sb
              .from('proveedores')
              .select()
              .eq('owner_id', ownerId)
              .order('id', ascending: true)
              .range(offset, offset + _pageSize - 1);
        } catch (e) {
          _erroresFilas++;
          Log.w('[sync] _pullProveedoresEquipoPredio owner=$ownerId: $e');
          break;
        }
        for (final raw in rows) {
          try {
            await _mergeProveedor(raw as Map<String, dynamic>);
            count++;
          } catch (e) {
            _erroresFilas++;
            Log.w('[sync] pull proveedores equipo: fila descartada: $e');
          }
        }
        if (rows.length < _pageSize) break;
        offset += _pageSize;
      }
    }
    return count;
  }

  static String _short(String uuid) {
    if (uuid.length < 8) return uuid;
    return uuid.substring(0, 8);
  }

  /// Tamaño de página del pull (auditoría P3). PostgREST trunca las
  /// respuestas sin `range` a su límite por defecto (1000 filas) de forma
  /// SILENCIOSA — sin paginación, las filas excedentes se perdían.
  static const int _pageSize = 500;

  Future<int> _pullTable(
    String tabla,
    Future<void> Function(Map<String, dynamic>) merger, {
    String timestampCol = 'updated_at',
  }) async {
    final syncRow = await (db.select(db.syncTables)
          ..where((s) => s.tabla.equals(tabla)))
        .getSingleOrNull();
    final since = syncRow?.lastPulledAt;

    var count = 0;
    // Auditoría P4: el cursor `lastPulledAt` avanza al máximo `updated_at`
    // RECIBIDO DEL SERVIDOR, nunca a DateTime.now() del cliente. Con el
    // reloj local adelantado, el cursor viejo saltaba filas escritas por
    // otros usuarios entre el inicio del pull y "ahora" (causa raíz de
    // varios bugs de colaboradores).
    DateTime? maxRemoto;
    var offset = 0;
    while (true) {
      var query = _sb.from(tabla).select();
      if (since != null) {
        // IMPORTANTE: enviar en UTC. Supabase interpreta el timestamp como
        // UTC si no lleva sufijo de zona; si mandamos local time obtenemos
        // un desfase de horas (bug reportado el 2026-07-11).
        query = query.gt(timestampCol, since.toUtc().toIso8601String());
      }
      // Orden estable por timestamp para que la paginación sea coherente
      // (auditoría P3).
      final page = await query
          .order(timestampCol, ascending: true)
          .range(offset, offset + _pageSize - 1);
      final rows = page as List<dynamic>;
      for (final raw in rows) {
        final row = raw as Map<String, dynamic>;
        try {
          await merger(row);
          count++;
        } catch (e) {
          // Fila problemática: no bloquea el resto, pero ya no es
          // silenciosa (auditoría P7).
          _erroresFilas++;
          Log.w('[sync] pull $tabla: fila id=${row['id']} descartada: $e');
        }
        final ts = _parseDateOrNull(row[timestampCol]);
        if (ts != null && (maxRemoto == null || ts.isAfter(maxRemoto))) {
          maxRemoto = ts;
        }
      }
      if (rows.length < _pageSize) break;
      offset += _pageSize;
    }
    // Actualiza cursor: tiempo del servidor (P4). Si no llegó ninguna fila,
    // el cursor se conserva — NO avanzar con el reloj local.
    await db.into(db.syncTables).insertOnConflictUpdate(
          SyncTablesCompanion.insert(
            tabla: tabla,
            lastPulledAt: Value(maxRemoto ?? since ?? DateTime.fromMillisecondsSinceEpoch(0)),
            lastAttemptAt: Value(DateTime.now()),
          ),
        );
    return count;
  }

  // ==================================================
  // MERGERS (aplican last-write-wins comparando updated_at)
  // ==================================================
  Future<void> _mergePredio(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    var localId = await _resolveLocalId('predios', remoteId);
    // Reconciliación por clave natural cuando no hay mapping. Escenario:
    // Cuenta A ejecutó "Reemplazar nube con local" — el remoto perdió sus
    // ids viejos y ganó ids nuevos; los mappings locales de B quedaron
    // huérfanos y sin este bloque se duplicaría el predio en B con solo
    // permisos de lectura (bug reportado 2026-07-19).
    if (localId == null) {
      final nombre = row['nombre'] as String;
      final ownerId = row['owner_id'] as String?;
      final natural = await (db.select(db.predios)
            ..where((p) => p.nombre.equals(nombre))
            ..where((p) => ownerId == null
                ? p.ownerUserId.isNull()
                : p.ownerUserId.equals(ownerId))
            ..limit(1))
          .getSingleOrNull();
      if (natural != null) {
        localId = natural.id;
        // Adopta el nuevo mapping y purga el mapping viejo (que apuntaba
        // al remote_id ya inexistente) para evitar zombies.
        await (db.delete(db.syncMappings)
              ..where((s) => s.tabla.equals('predios'))
              ..where((s) => s.localId.equals(localId!))
              ..where((s) => s.remoteId.isNotValue(remoteId)))
            .go();
        await _saveMapping('predios', localId, remoteId);
      }
    }
    final updatedRemote = _parseDate(row['updated_at']);
    // Resolver paisId/regionId/municipioId a partir de los nombres/iso
    int? paisId, regionId, municipioId;
    final iso = row['pais_iso2'] as String?;
    if (iso != null) {
      final p = await (db.select(db.paises)..where((x) => x.iso2.equals(iso)))
          .getSingleOrNull();
      paisId = p?.id;
    }
    final companion = PrediosCompanion(
      nombre: Value(row['nombre'] as String),
      propietario: Value(row['propietario'] as String?),
      paisId: Value(paisId),
      regionId: Value(regionId),
      municipioId: Value(municipioId),
      lat: Value((row['lat'] as num?)?.toDouble()),
      lng: Value((row['lng'] as num?)?.toDouble()),
      altM: Value((row['alt_m'] as num?)?.toDouble()),
      notas: Value(row['notas'] as String?),
      // Guardo el UUID del owner remoto para saber luego si soy propietario
      // o colaborador de este predio.
      ownerUserId: Value(row['owner_id'] as String?),
      updatedAt: Value(updatedRemote),
      deletedAt: Value(_parseDateOrNull(row['deleted_at'])),
    );
    final resolved = localId; // captura para promoción de tipo
    if (resolved != null) {
      final local = await (db.select(db.predios)
            ..where((p) => p.id.equals(resolved)))
          .getSingleOrNull();
      if (local != null &&
          local.updatedAt.isAfter(updatedRemote)) {
        return; // local es más nuevo, ignora
      }
      await (db.update(db.predios)..where((p) => p.id.equals(resolved)))
          .write(companion);
      // Refresca mapping para que el push posterior no re-suba lo bajado.
      await _saveMapping('predios', resolved, remoteId);
    } else {
      final newLocalId = await db.into(db.predios).insert(companion);
      await _saveMapping('predios', newLocalId, remoteId);
    }
  }

  Future<void> _mergeProveedor(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final localId = await _resolveLocalId('proveedores', remoteId);
    final updatedRemote = _parseDate(row['updated_at']);
    final c = ProveedoresCompanion(
      nombre: Value(row['nombre'] as String),
      nit: Value(row['nit'] as String?),
      telefono: Value(row['telefono'] as String?),
      email: Value(row['email'] as String?),
      web: Value(row['web'] as String?),
      direccion: Value(row['direccion'] as String?),
      notas: Value(row['notas'] as String?),
      updatedAt: Value(updatedRemote),
      deletedAt: Value(_parseDateOrNull(row['deleted_at'])),
    );
    if (localId != null) {
      final local = await (db.select(db.proveedores)
            ..where((p) => p.id.equals(localId)))
          .getSingleOrNull();
      if (local != null && local.updatedAt.isAfter(updatedRemote)) return;
      await (db.update(db.proveedores)..where((p) => p.id.equals(localId)))
          .write(c);
      await _saveMapping('proveedores', localId, remoteId);
    } else {
      final newId = await db.into(db.proveedores).insert(c);
      await _saveMapping('proveedores', newId, remoteId);
    }
  }

  Future<void> _mergeLote(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final predioLocalId =
        await _resolveLocalId('predios', row['predio_id'] as int);
    if (predioLocalId == null) return;
    var localId = await _resolveLocalId('lotes', remoteId);
    // Reconciliación por clave natural (predio + nombre) tras "Reemplazar
    // nube con local" — evita duplicados cuando los remote_ids cambiaron.
    if (localId == null) {
      final nombre = row['nombre'] as String;
      final natural = await (db.select(db.lotes)
            ..where((l) => l.predioId.equals(predioLocalId))
            ..where((l) => l.nombre.equals(nombre))
            ..limit(1))
          .getSingleOrNull();
      if (natural != null) {
        localId = natural.id;
        await (db.delete(db.syncMappings)
              ..where((s) => s.tabla.equals('lotes'))
              ..where((s) => s.localId.equals(localId!))
              ..where((s) => s.remoteId.isNotValue(remoteId)))
            .go();
        await _saveMapping('lotes', localId, remoteId);
      }
    }
    final updatedRemote = _parseDate(row['updated_at']);
    final c = LotesCompanion(
      predioId: Value(predioLocalId),
      nombre: Value(row['nombre'] as String),
      administrador: Value(row['administrador'] as String?),
      altitudMsnm: Value((row['altitud_msnm'] as num?)?.toDouble()),
      areaM2: Value((row['area_m2'] as num?)?.toDouble()),
      poligonoGeoJson: Value(row['poligono_geojson'] as String?),
      notas: Value(row['notas'] as String?),
      updatedAt: Value(updatedRemote),
      deletedAt: Value(_parseDateOrNull(row['deleted_at'])),
    );
    final resolved = localId; // captura para promoción de tipo
    if (resolved != null) {
      final local = await (db.select(db.lotes)
            ..where((l) => l.id.equals(resolved)))
          .getSingleOrNull();
      if (local != null && local.updatedAt.isAfter(updatedRemote)) return;
      await (db.update(db.lotes)..where((l) => l.id.equals(resolved))).write(c);
      await _saveMapping('lotes', resolved, remoteId);
    } else {
      final newId = await db.into(db.lotes).insert(c);
      await _saveMapping('lotes', newId, remoteId);
    }
  }

  Future<void> _mergeCondiciones(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final predioLocalId =
        await _resolveLocalId('predios', row['predio_id'] as int);
    if (predioLocalId == null) return;
    final updatedRemote = _parseDate(row['updated_at']);
    final existing = await (db.select(db.condicionesPredio)
          ..where((c) => c.predioId.equals(predioLocalId)))
        .getSingleOrNull();
    final c = CondicionesPredioCompanion(
      predioId: Value(predioLocalId),
      altitudMsnm: Value((row['altitud_msnm'] as num?)?.toDouble()),
      precipitacionAnualMm:
          Value((row['precipitacion_anual_mm'] as num?)?.toDouble()),
      tempMediaC: Value((row['temp_media_c'] as num?)?.toDouble()),
      tempMinC: Value((row['temp_min_c'] as num?)?.toDouble()),
      tempMaxC: Value((row['temp_max_c'] as num?)?.toDouble()),
      humedadRelativaPct:
          Value((row['humedad_relativa_pct'] as num?)?.toDouble()),
      zonaClimatica: Value(row['zona_climatica'] as String?),
      pisoTermico: Value(row['piso_termico'] as String?),
      fuente: Value(row['fuente'] as String?),
      notas: Value(row['notas'] as String?),
      updatedAt: Value(updatedRemote),
      deletedAt: Value(_parseDateOrNull(row['deleted_at'])),
    );
    if (existing != null) {
      if (existing.updatedAt.isAfter(updatedRemote)) return;
      await (db.update(db.condicionesPredio)
            ..where((x) => x.id.equals(existing.id)))
          .write(c);
      await _saveMapping('condiciones_predio', existing.id, remoteId);
    } else {
      final newId = await db.into(db.condicionesPredio).insert(c);
      await _saveMapping('condiciones_predio', newId, remoteId);
    }
  }

  Future<void> _mergeCultivo(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final predioLocalId =
        await _resolveLocalId('predios', row['predio_id'] as int);
    if (predioLocalId == null) return;
    final loteRemote = row['lote_id'] as int?;
    final loteLocalId =
        loteRemote == null ? null : await _resolveLocalId('lotes', loteRemote);
    var localId = await _resolveLocalId('cultivos', remoteId);
    final updatedRemote = _parseDate(row['updated_at']);
    // Reconciliación por clave natural (predio + fecha_siembra + planta)
    // tras "Reemplazar nube con local" (Fase 3e-9-14). Se usa el nombre
    // de planta denormalizado para no depender del catálogo local.
    if (localId == null) {
      final fechaSiembra = _parseDate(row['fecha_siembra']);
      final nombrePlanta = row['nombre_planta'] as String?;
      // Cargar candidatos con misma fecha + predio, luego filtrar por
      // nombre de planta en Dart (evita join complejo en Drift).
      final candidatos = await (db.select(db.cultivos)
            ..where((c) => c.predioId.equals(predioLocalId))
            ..where((c) => c.fechaSiembra.equals(fechaSiembra)))
          .get();
      for (final cand in candidatos) {
        final pl = await (db.select(db.plantas)
              ..where((p) => p.id.equals(cand.plantaId)))
            .getSingleOrNull();
        if (pl?.nombreComun == nombrePlanta) {
          localId = cand.id;
          await (db.delete(db.syncMappings)
                ..where((s) => s.tabla.equals('cultivos'))
                ..where((s) => s.localId.equals(localId!))
                ..where((s) => s.remoteId.isNotValue(remoteId)))
              .go();
          await _saveMapping('cultivos', localId, remoteId,
              bumpLastPushed: false);
          break;
        }
      }
    }

    // Resolver planta SOLO por `nombre_planta` denormalizado.
    // NUNCA confiar en `planta_id_local` del remoto: ese ID es local al
    // dispositivo que subió la fila. En el peer el mismo entero puede
    // apuntar a OTRA variedad (bug 2026-08-01: tras sync de "Curada",
    // Cuenta B mostró "Yuca enana" en lugar de "Tomate chonto").
    final resolved = localId;
    Cultivo? localExistente;
    if (resolved != null) {
      localExistente = await (db.select(db.cultivos)
            ..where((x) => x.id.equals(resolved)))
          .getSingleOrNull();
      if (localExistente != null) {
        final remoteDeleted = _parseDateOrNull(row['deleted_at']);
        // Tombstone remota gana: si el remoto está borrado y lo local no,
        // aplicar el borrado aunque el reloj local diga "más nuevo"
        // (evita que B ignore el soft-delete de A por skew de reloj).
        final tombstoneGana =
            remoteDeleted != null && localExistente.deletedAt == null;
        if (!tombstoneGana &&
            localExistente.updatedAt.isAfter(updatedRemote)) {
          // LWW omite el resto, pero aún corrige planta si el nombre
          // remoto no coincide (recuperación del bug planta_id_local).
          await _aplicarPlantaPorNombreSiDifiere(
            localExistente,
            row['nombre_planta'] as String?,
          );
          return;
        }
      }
    }

    var plantaId = await _resolvePlantaIdPorNombreRemoto(
      row['nombre_planta'] as String?,
    );
    // Si el remoto no trae nombre (filas legacy) y ya tenemos el cultivo
    // local, conservar su plantaId actual en vez de adivinar por ID ajeno.
    if (plantaId == 0 && localExistente != null) {
      plantaId = localExistente.plantaId;
    }
    if (plantaId == 0) return; // sin planta no podemos crear cultivo

    final c = CultivosCompanion(
      predioId: Value(predioLocalId),
      plantaId: Value(plantaId),
      loteId: Value(loteLocalId),
      nombreLote: Value(row['nombre_lote'] as String?),
      fechaSiembra: Value(_parseDate(row['fecha_siembra'])),
      fechaCosechaEstimada:
          Value(_parseDateOrNull(row['fecha_cosecha_estimada'])),
      areaBaseM2: Value((row['area_base_m2'] as num?)?.toDouble()),
      cantidadSemillaBase:
          Value((row['cantidad_semilla_base'] as num?)?.toDouble()),
      cantidadSemillaUnidadBase:
          Value(row['cantidad_semilla_unidad_base'] as String?),
      hhTotal: Value((row['hh_total'] as num?)?.toDouble() ?? 0),
      horaValor: Value((row['hora_valor'] as num?)?.toDouble()),
      lat: Value((row['lat'] as num?)?.toDouble()),
      lng: Value((row['lng'] as num?)?.toDouble()),
      altM: Value((row['alt_m'] as num?)?.toDouble()),
      finalizadoFecha: Value(_parseDateOrNull(row['finalizado_fecha'])),
      notas: Value(row['notas'] as String?),
      tipoCultivo: Value(
          (row['tipo_cultivo'] as String?) ?? 'ciclo_unico'),
      cosecha1Dias: Value(row['cosecha1_dias'] as int?),
      cosecha2Dias: Value(row['cosecha2_dias'] as int?),
      periodicidadCosechaDias:
          Value(row['periodicidad_cosecha_dias'] as int?),
      esperanzaVidaDias: Value(row['esperanza_vida_dias'] as int?),
      updatedAt: Value(updatedRemote),
      deletedAt: Value(_parseDateOrNull(row['deleted_at'])),
    );

    if (resolved != null) {
      await (db.update(db.cultivos)..where((x) => x.id.equals(resolved)))
          .write(c);
      // Pull: no bumpear lastPushedAt (si no, un soft-delete local
      // pendiente puede quedar marcado como "ya subido").
      await _saveMapping('cultivos', resolved, remoteId,
          bumpLastPushed: false);
    } else {
      final newId = await db.into(db.cultivos).insert(c);
      await _saveMapping('cultivos', newId, remoteId, bumpLastPushed: false);
    }
  }

  /// Resuelve el `plantas.id` local a partir del nombre denormalizado del
  /// remoto. Crea un stub si la variedad aún no existe en este dispositivo.
  Future<int> _resolvePlantaIdPorNombreRemoto(String? nombrePlanta) async {
    final nombre = nombrePlanta?.trim();
    if (nombre == null || nombre.isEmpty) return 0;
    final existente = await (db.select(db.plantas)
          ..where((x) => x.nombreComun.equals(nombre))
          ..where((x) => x.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    if (existente != null) return existente.id;
    return db.into(db.plantas).insert(PlantasCompanion.insert(
          nombreComun: nombre,
          fuente: const Value('sync_auto'),
          notas: const Value(
              'Auto-creada por sync desde otro dispositivo; '
              'completa datos agronómicos manualmente si es necesario.'),
        ));
  }

  /// Si el cultivo local apunta a una planta cuyo nombre no coincide con
  /// el `nombre_planta` remoto, corrige solo `plantaId` (sin tocar
  /// `updatedAt`, para no disparar un re-push artificial).
  Future<bool> _aplicarPlantaPorNombreSiDifiere(
    Cultivo local,
    String? nombrePlantaRemoto,
  ) async {
    final nombre = nombrePlantaRemoto?.trim();
    if (nombre == null || nombre.isEmpty) return false;
    final actual = await (db.select(db.plantas)
          ..where((p) => p.id.equals(local.plantaId))
          ..limit(1))
        .getSingleOrNull();
    if (actual?.nombreComun == nombre) return false;
    final correcto = await _resolvePlantaIdPorNombreRemoto(nombre);
    if (correcto == 0 || correcto == local.plantaId) return false;
    await (db.update(db.cultivos)..where((c) => c.id.equals(local.id)))
        .write(CultivosCompanion(plantaId: Value(correcto)));
    Log.w('[sync] reparado plantaId cultivo=${local.id}: '
        '${actual?.nombreComun ?? "?"} → $nombre');
    return true;
  }

  /// Pasa por todos los cultivos con mapping remoto y alinea `plantaId`
  /// con `nombre_planta` de Supabase. Recupera dispositivos ya afectados
  /// por el bug de IDs locales de planta entre cuentas.
  Future<int> _repararPlantaIdsDesdeNombreRemoto() async {
    final mappings = await _mappingsDe('cultivos');
    if (mappings.isEmpty) return 0;
    final byRemote = <int, int>{
      for (final e in mappings.entries) e.value.remoteId: e.key,
    };
    final remoteIds = byRemote.keys.toList();
    var reparados = 0;
    try {
      for (var i = 0; i < remoteIds.length; i += _pageSize) {
        final chunk = remoteIds.sublist(
            i, min(i + _pageSize, remoteIds.length));
        final rows = await _sb
            .from('cultivos')
            .select('id, nombre_planta')
            .inFilter('id', chunk);
        for (final row in rows) {
          final remoteId = (row['id'] as num).toInt();
          final localId = byRemote[remoteId];
          if (localId == null) continue;
          final local = await (db.select(db.cultivos)
                ..where((c) => c.id.equals(localId))
                ..limit(1))
              .getSingleOrNull();
          if (local == null) continue;
          if (await _aplicarPlantaPorNombreSiDifiere(
              local, row['nombre_planta'] as String?)) {
            reparados++;
          }
        }
      }
    } catch (e) {
      Log.w('[sync] _repararPlantaIdsDesdeNombreRemoto fallo: $e');
    }
    return reparados;
  }

  Future<void> _mergeCultivoPatologia(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final cultivoLocalId =
        await _resolveLocalId('cultivos', row['cultivo_id'] as int);
    if (cultivoLocalId == null) return;

    var localId = await _resolveLocalId('cultivo_patologias', remoteId);
    final updatedRemote = _parseDate(row['updated_at']);
    final nombre = (row['patologia_nombre'] as String?)?.trim() ?? '';

    // Resolver / crear entrada en catálogo local por nombre.
    int? patologiaId;
    if (nombre.isNotEmpty) {
      final existing = await (db.select(db.patologias)
            ..where((p) => p.nombreComun.equals(nombre))
            ..where((p) => p.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();
      if (existing != null) {
        patologiaId = existing.id;
      } else {
        patologiaId = await db.into(db.patologias).insert(
              PatologiasCompanion.insert(
                nombreComun: nombre,
                nombreCientifico:
                    Value(row['patologia_cientifico'] as String?),
                tipo: Value(row['patologia_tipo'] as String?),
              ),
            );
      }
    }

    final ivRaw = row['intervenciones_json'];
    final ivStr = ivRaw is String
        ? ivRaw
        : jsonEncode(ivRaw ?? []);

    final c = CultivoPatologiasCompanion(
      cultivoId: Value(cultivoLocalId),
      patologiaId: Value(patologiaId),
      patologiaNombre: Value(nombre.isEmpty ? null : nombre),
      fechaDeteccion: Value(_parseDate(row['fecha_deteccion'])),
      severidad: Value(row['severidad'] as String?),
      fuenteDiagnostico: Value(row['fuente_diagnostico'] as String?),
      confianza: Value((row['confianza'] as num?)?.toDouble()),
      resueltaAt: Value(_parseDateOrNull(row['resuelta_at'])),
      curaFecha: Value(_parseDateOrNull(row['cura_fecha'])),
      intervencionesJson: Value(ivStr),
      notas: Value(row['notas'] as String?),
      lat: Value((row['lat'] as num?)?.toDouble()),
      lng: Value((row['lng'] as num?)?.toDouble()),
      altM: Value((row['alt_m'] as num?)?.toDouble()),
      compartida: Value(row['compartida'] as bool? ?? false),
      updatedAt: Value(updatedRemote),
      deletedAt: Value(_parseDateOrNull(row['deleted_at'])),
    );

    final resolved = localId;
    if (resolved != null) {
      final local = await (db.select(db.cultivoPatologias)
            ..where((x) => x.id.equals(resolved)))
          .getSingleOrNull();
      if (local != null) {
        final remoteDeleted = _parseDateOrNull(row['deleted_at']);
        final tombstoneGana =
            remoteDeleted != null && local.deletedAt == null;
        if (!tombstoneGana && local.updatedAt.isAfter(updatedRemote)) {
          return;
        }
      }
      await (db.update(db.cultivoPatologias)
            ..where((x) => x.id.equals(resolved)))
          .write(c);
      await _saveMapping('cultivo_patologias', resolved, remoteId,
          bumpLastPushed: false);
    } else {
      final newId = await db.into(db.cultivoPatologias).insert(c);
      await _saveMapping('cultivo_patologias', newId, remoteId,
          bumpLastPushed: false);
    }
  }

  Future<void> _mergeInventario(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final predioLocalId =
        await _resolveLocalId('predios', row['predio_id'] as int);
    if (predioLocalId == null) return;
    var localId = await _resolveLocalId('inventarios', remoteId);
    // Matching por clave natural (predio + descripcion + codigo) para el
    // caso en que el mapping se haya reseteado (Mantenimiento) y no
    // queremos crear duplicados locales.
    if (localId == null) {
      final descripcion = row['descripcion'] as String;
      final codigo = row['codigo'] as String?;
      final match = await (db.select(db.inventarios)
            ..where((i) => i.predioId.equals(predioLocalId))
            ..where((i) => i.descripcion.equals(descripcion))
            ..where((i) => codigo == null
                ? i.codigo.isNull()
                : i.codigo.equals(codigo))
            ..limit(1))
          .getSingleOrNull();
      if (match != null) {
        localId = match.id;
        await _saveMapping('inventarios', localId, remoteId);
      }
    }
    final updatedRemote = _parseDate(row['updated_at']);
    final c = InventariosCompanion(
      predioId: Value(predioLocalId),
      fecha: Value(_parseDate(row['fecha'])),
      codigo: Value(row['codigo'] as String?),
      descripcion: Value(row['descripcion'] as String),
      fabricante: Value(row['fabricante'] as String?),
      cantidadBase: Value((row['cantidad_base'] as num).toDouble()),
      unidadBase: Value(row['unidad_base'] as String),
      notas: Value(row['notas'] as String?),
      updatedAt: Value(updatedRemote),
      deletedAt: Value(_parseDateOrNull(row['deleted_at'])),
    );
    final resolvedLocalId = localId; // captura para promoción de tipo
    if (resolvedLocalId != null) {
      final local = await (db.select(db.inventarios)
            ..where((i) => i.id.equals(resolvedLocalId)))
          .getSingleOrNull();
      if (local != null && local.updatedAt.isAfter(updatedRemote)) return;
      await (db.update(db.inventarios)
            ..where((i) => i.id.equals(resolvedLocalId)))
          .write(c);
      await _saveMapping('inventarios', resolvedLocalId, remoteId);
    } else {
      final newId = await db.into(db.inventarios).insert(c);
      await _saveMapping('inventarios', newId, remoteId);
    }
  }

  Future<void> _mergeAnalisis(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final predioLocalId =
        await _resolveLocalId('predios', row['predio_id'] as int);
    if (predioLocalId == null) return;
    final localId = await _resolveLocalId('analisis_suelo', remoteId);
    final updatedRemote = _parseDate(row['updated_at']);
    final c = AnalisisSueloCompanion(
      predioId: Value(predioLocalId),
      lote: Value(row['lote'] as String?),
      fechaMuestreo: Value(_parseDate(row['fecha_muestreo'])),
      laboratorio: Value(row['laboratorio'] as String?),
      profundidadCm: Value((row['profundidad_cm'] as num?)?.toDouble()),
      textura: Value(row['textura'] as String?),
      densidadGCm3: Value((row['densidad_g_cm3'] as num?)?.toDouble()),
      conductividadMsCm:
          Value((row['conductividad_ms_cm'] as num?)?.toDouble()),
      ph: Value((row['ph'] as num?)?.toDouble()),
      materiaOrganicaPct:
          Value((row['materia_organica_pct'] as num?)?.toDouble()),
      nPpm: Value((row['n_ppm'] as num?)?.toDouble()),
      pPpm: Value((row['p_ppm'] as num?)?.toDouble()),
      kPpm: Value((row['k_ppm'] as num?)?.toDouble()),
      caMeq: Value((row['ca_meq'] as num?)?.toDouble()),
      mgMeq: Value((row['mg_meq'] as num?)?.toDouble()),
      naMeq: Value((row['na_meq'] as num?)?.toDouble()),
      cicMeq: Value((row['cic_meq'] as num?)?.toDouble()),
      sPpm: Value((row['s_ppm'] as num?)?.toDouble()),
      bPpm: Value((row['b_ppm'] as num?)?.toDouble()),
      notas: Value(row['notas'] as String?),
      updatedAt: Value(updatedRemote),
      deletedAt: Value(_parseDateOrNull(row['deleted_at'])),
    );
    if (localId != null) {
      final local = await (db.select(db.analisisSuelo)
            ..where((a) => a.id.equals(localId)))
          .getSingleOrNull();
      if (local != null && local.updatedAt.isAfter(updatedRemote)) return;
      await (db.update(db.analisisSuelo)..where((a) => a.id.equals(localId)))
          .write(c);
      await _saveMapping('analisis_suelo', localId, remoteId);
    } else {
      final newId = await db.into(db.analisisSuelo).insert(c);
      await _saveMapping('analisis_suelo', newId, remoteId);
    }
  }

  Future<void> _mergeCompra(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final predioLocalId =
        await _resolveLocalId('predios', row['predio_id'] as int);
    if (predioLocalId == null) return;
    final provRemote = row['proveedor_id'] as int?;
    final provLocalId = provRemote == null
        ? null
        : await _resolveLocalId('proveedores', provRemote);
    final localId = await _resolveLocalId('compras', remoteId);
    final updatedRemote = _parseDate(row['updated_at']);
    final c = ComprasCompanion(
      predioId: Value(predioLocalId),
      proveedorId: Value(provLocalId),
      fecha: Value(_parseDate(row['fecha'])),
      descripcion1: Value(row['descripcion1'] as String),
      descripcion2: Value(row['descripcion2'] as String?),
      valorTotal: Value((row['valor_total'] as num).toDouble()),
      cantidadBase: Value((row['cantidad_base'] as num).toDouble()),
      unidadBase: Value(row['unidad_base'] as String),
      codigo: Value(row['codigo'] as String?),
      factura: Value(row['factura'] as String?),
      tipo: Value(row['tipo'] as String?),
      notas: Value(row['notas'] as String?),
      createdByUserId: Value(row['created_by_user_id'] as String?),
      updatedAt: Value(updatedRemote),
      deletedAt: Value(_parseDateOrNull(row['deleted_at'])),
    );
    if (localId != null) {
      final local = await (db.select(db.compras)
            ..where((c) => c.id.equals(localId)))
          .getSingleOrNull();
      if (local != null && local.updatedAt.isAfter(updatedRemote)) return;
      await (db.update(db.compras)..where((c) => c.id.equals(localId)))
          .write(c);
      await _saveMapping('compras', localId, remoteId);
    } else {
      final newId = await db.into(db.compras).insert(c);
      await _saveMapping('compras', newId, remoteId);
    }
  }

  Future<void> _mergeEvento(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final cultivoLocalId =
        await _resolveLocalId('cultivos', row['cultivo_id'] as int);
    if (cultivoLocalId == null) return;
    var localId = await _resolveLocalId('eventos_cultivo', remoteId);
    // Reconciliación por clave natural (cultivo + tipo + fecha_programada
    // + descripcion) tras "Reemplazar nube con local" (Fase 3e-9-14).
    if (localId == null) {
      final tipo = row['tipo'] as String;
      final fechaProgramada = _parseDateOrNull(row['fecha_programada']);
      final descripcion = row['descripcion'] as String?;
      if (fechaProgramada != null) {
        final natural = await (db.select(db.eventosCultivo)
              ..where((e) => e.cultivoId.equals(cultivoLocalId))
              ..where((e) => e.tipo.equals(tipo))
              ..where((e) => e.fechaProgramada.equals(fechaProgramada))
              ..where((e) => descripcion == null
                  ? e.descripcion.isNull()
                  : e.descripcion.equals(descripcion))
              ..limit(1))
            .getSingleOrNull();
        if (natural != null) {
          localId = natural.id;
          await (db.delete(db.syncMappings)
                ..where((s) => s.tabla.equals('eventos_cultivo'))
                ..where((s) => s.localId.equals(localId!))
                ..where((s) => s.remoteId.isNotValue(remoteId)))
              .go();
          await _saveMapping('eventos_cultivo', localId, remoteId);
        }
      }
    }
    final updatedRemote = _parseDate(row['updated_at']);
    final c = EventosCultivoCompanion(
      cultivoId: Value(cultivoLocalId),
      tipo: Value(row['tipo'] as String),
      fechaProgramada: Value(_parseDateOrNull(row['fecha_programada'])),
      fechaEjecutada: Value(_parseDateOrNull(row['fecha_ejecutada'])),
      descripcion: Value(row['descripcion'] as String?),
      notas: Value(row['notas'] as String?),
      updatedAt: Value(updatedRemote),
      deletedAt: Value(_parseDateOrNull(row['deleted_at'])),
    );
    final resolved = localId; // captura para promoción de tipo
    if (resolved != null) {
      final local = await (db.select(db.eventosCultivo)
            ..where((e) => e.id.equals(resolved)))
          .getSingleOrNull();
      if (local != null && local.updatedAt.isAfter(updatedRemote)) return;
      await (db.update(db.eventosCultivo)..where((e) => e.id.equals(resolved)))
          .write(c);
      await _saveMapping('eventos_cultivo', resolved, remoteId);
    } else {
      final newId = await db.into(db.eventosCultivo).insert(c);
      await _saveMapping('eventos_cultivo', newId, remoteId);
    }
  }

  Future<void> _mergeTarea(Map<String, dynamic> row) async {
    final remoteId = row['id'] as int;
    final cultivoLocalId =
        await _resolveLocalId('cultivos', row['cultivo_id'] as int);
    if (cultivoLocalId == null) return;
    var localId = await _resolveLocalId('tareas_completadas', remoteId);
    // Reconciliación por clave natural (cultivo + fecha + hh + actividades)
    // tras "Reemplazar nube con local" (Fase 3e-9-14). Las tareas son
    // inmutables, así que dos con misma clave natural son duplicadas
    // seguras.
    if (localId == null) {
      final fecha = _parseDate(row['fecha']);
      final hh = (row['hh'] as num?)?.toDouble() ?? 0;
      final actividadesJson = jsonEncode(row['actividades_json'] ?? []);
      final natural = await (db.select(db.tareasCompletadas)
            ..where((t) => t.cultivoId.equals(cultivoLocalId))
            ..where((t) => t.fecha.equals(fecha))
            ..where((t) => t.hh.equals(hh))
            ..where((t) => t.actividadesJson.equals(actividadesJson))
            ..limit(1))
          .getSingleOrNull();
      if (natural != null) {
        localId = natural.id;
        await (db.delete(db.syncMappings)
              ..where((s) => s.tabla.equals('tareas_completadas'))
              ..where((s) => s.localId.equals(localId!))
              ..where((s) => s.remoteId.isNotValue(remoteId)))
            .go();
        await _saveMapping('tareas_completadas', localId, remoteId);
        return; // tareas son inmutables — con mapping bastas
      }
    }
    final c = TareasCompletadasCompanion.insert(
      cultivoId: cultivoLocalId,
      fecha: _parseDate(row['fecha']),
      hh: Value((row['hh'] as num?)?.toDouble() ?? 0),
      actividadesJson: jsonEncode(row['actividades_json'] ?? []),
      insumosJson: Value(jsonEncode(row['insumos_json'] ?? [])),
      notas: Value(row['notas'] as String?),
      // Fase 3g: autor Supabase. Null = tarea legacy.
      createdByUserId: Value(row['created_by_user_id'] as String?),
    );
    if (localId != null) {
      // Tareas son inmutables tras crearse; no aplicamos update.
      return;
    }
    final newId = await db.into(db.tareasCompletadas).insert(c);
    await _saveMapping('tareas_completadas', newId, remoteId);
  }

  // ==================================================
  // HELPERS
  // ==================================================

  /// Push genérico con detección de propiedad. Si ya tengo mapping remoto
  /// para (tabla, localId), hace UPDATE por remote_id — así preservo el
  /// `owner_id` original y evito crear duplicados cuando un colaborador
  /// edita algo que no es suyo (RLS decide si tengo permiso).
  ///
  /// Si NO hay mapping, hace INSERT nuevo con mi owner_id automático (por
  /// el trigger). Es el flujo normal de "creación inicial".
  Future<int?> _upsert(
    String tabla,
    Map<String, dynamic> payload, {
    int? localId,
    int? remoteId,
  }) async {
    try {
      // Auditoría P1: el llamador puede pasar el remoteId ya resuelto
      // (desde un mapa precargado) para evitar la consulta por fila.
      if (remoteId == null && localId != null) {
        remoteId = await _resolveRemoteId(tabla, localId);
      }
      if (remoteId != null) {
        // UPDATE preservando owner_id original. Quitamos campos que no
        // debemos tocar en un UPDATE de fila ajena. `.select('id')`
        // verifica que RLS realmente escribió: sin él, un UPDATE
        // bloqueado "tiene éxito" en HTTP y el mapping se marcaría como
        // pusheado dejando el cambio local perdido para siempre.
        final updatePayload = Map<String, dynamic>.from(payload)
          ..remove('cliente_id')
          ..remove('owner_id');
        final res = await _sb
            .from(tabla)
            .update(updatePayload)
            .eq('id', remoteId)
            .select('id');
        if ((res as List).isEmpty) {
          _erroresFilas++;
          Log.w('[sync] _upsert UPDATE $tabla remote=$remoteId sin filas '
              'afectadas (¿RLS?) — no se marca como pusheado');
          return null;
        }
        return remoteId;
      }
      // Nuevo registro: INSERT con upsert por (owner_id, cliente_id) para
      // idempotencia si el mismo push corre dos veces.
      final res = await _sb
          .from(tabla)
          .upsert(payload, onConflict: 'owner_id,cliente_id')
          .select('id')
          .maybeSingle();
      if (res == null) return null;
      return res['id'] as int;
    } catch (e) {
      // Log y contador (auditoría P7) — devuelve null para que el push
      // continúe con las demás filas (una fila prohibida por RLS no debe
      // abortar el sync entero).
      _erroresFilas++;
      Log.w('[sync] _upsert($tabla, localId=$localId) fallo: $e');
      return null;
    }
  }

  Future<int?> _resolveRemoteId(String tabla, int localId) async {
    final row = await (db.select(db.syncMappings)
          ..where((s) => s.tabla.equals(tabla))
          ..where((s) => s.localId.equals(localId)))
        .getSingleOrNull();
    return row?.remoteId;
  }

  Future<int?> _resolveLocalId(String tabla, int remoteId) async {
    final row = await (db.select(db.syncMappings)
          ..where((s) => s.tabla.equals(tabla))
          ..where((s) => s.remoteId.equals(remoteId)))
        .getSingleOrNull();
    return row?.localId;
  }

  /// Retorna true si el usuario actual puede editar recursos del predio
  /// según el estado LOCAL de la BD (dueño, co-propietario con rol
  /// `propietario`, o colaborador con rol `trabajador`). Alineado con
  /// `puede_editar_predio()` en Postgres. Se usa como filtro proactivo en
  /// los `_push*` para
  /// evitar disparar UPDATE/INSERT en el remoto que la RLS de Postgres
  /// rechazaría con 42501 tras revocarse el share (bug 2026-07-19: al
  /// eliminar a un colaborador, el sync del ex-colaborador abortaba
  /// intentando subir recursos huérfanos como condiciones_predio).
  ///
  /// En modo local puro (sin sesión Supabase) siempre true.
  Future<bool> _puedoEditarPredioLocal(int predioLocalId) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return true; // modo local
    final predio = await (db.select(db.predios)
          ..where((p) => p.id.equals(predioLocalId)))
        .getSingleOrNull();
    if (predio == null) return false;
    // Propietario según ownerUserId (backfilleado por el pull).
    if (predio.ownerUserId == userId) return true;
    // Sin ownerUserId aún → asumir propio (fue creado localmente antes
    // del primer sync).
    if (predio.ownerUserId == null) return true;
    // Co-propietario o trabajador. Consultores no pueden editar.
    final share = await (db.select(db.predioColaboradores)
          ..where((c) => c.predioId.equals(predioLocalId))
          ..where((c) => c.colaboradorUserId.equals(userId))
          ..where((c) => c.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    return share?.rol == 'propietario' || share?.rol == 'trabajador';
  }

  /// True solo si soy el DUEÑO REAL del predio (`predios.ownerUserId`), sin
  /// contar shares con rol `propietario`. Se usa para decidir qué filas de
  /// colaboradores puedo subir: únicamente el dueño real crea shares, de lo
  /// contrario se generan shares invertidos (`owner_id` ≠ dueño del predio).
  Future<bool> _soyOwnerRealDePredio(int predioLocalId) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return true; // modo local
    final predio = await (db.select(db.predios)
          ..where((p) => p.id.equals(predioLocalId)))
        .getSingleOrNull();
    if (predio == null) return false;
    // Sin ownerUserId aún → creado localmente antes del primer sync.
    return predio.ownerUserId == null || predio.ownerUserId == userId;
  }

  /// True si el usuario puede ver/editar compras del predio: dueño real
  /// (`ownerUserId`) o colaborador con rol `propietario` en el share.
  Future<bool> _soyPropietarioPredioLocal(int predioLocalId) async {
    final userId = _sb.auth.currentUser?.id;
    if (userId == null) return true; // modo local
    final predio = await (db.select(db.predios)
          ..where((p) => p.id.equals(predioLocalId)))
        .getSingleOrNull();
    if (predio == null) return false;
    if (predio.ownerUserId == userId) return true;
    if (predio.ownerUserId == null) return true;
    final share = await (db.select(db.predioColaboradores)
          ..where((c) => c.predioId.equals(predioLocalId))
          ..where((c) => c.colaboradorUserId.equals(userId))
          ..where((c) => c.deletedAt.isNull())
          ..limit(1))
        .getSingleOrNull();
    return share?.rol == 'propietario';
  }

  Future<void> _saveMapping(String tabla, int localId, int remoteId,
      {bool bumpLastPushed = true}) async {
    // Si otro localId ya tenía este remoteId (reconciliación por clave
    // natural tras reemplazar nube / duplicados), eliminar el mapping
    // viejo antes de insertar — evita UNIQUE (tabla, remote_id).
    await (db.delete(db.syncMappings)
          ..where((s) => s.tabla.equals(tabla))
          ..where((s) => s.remoteId.equals(remoteId))
          ..where((s) => s.localId.isNotValue(localId)))
        .go();
    // Upsert: si ya existe (tabla, localId), actualiza el remoteId.
    // `bumpLastPushed=false` desde los mergers (pull): actualizar el
    // timestamp durante el pull hace que `_debeSubir` crea que no hay
    // cambios locales pendientes, y no subiría al remoto ediciones que
    // el usuario acaba de hacer localmente (bug detectado 2026-07-19
    // en el flujo de cambio de rol de colaborador).
    final existing = await (db.select(db.syncMappings)
          ..where((s) => s.tabla.equals(tabla))
          ..where((s) => s.localId.equals(localId)))
        .getSingleOrNull();
    if (existing != null) {
      await (db.update(db.syncMappings)
            ..where((s) => s.id.equals(existing.id)))
          .write(SyncMappingsCompanion(
        remoteId: Value(remoteId),
        lastPushedAt: bumpLastPushed
            ? Value(DateTime.now())
            : const Value.absent(),
      ));
    } else {
      await db.into(db.syncMappings).insert(SyncMappingsCompanion.insert(
            tabla: tabla,
            localId: localId,
            remoteId: remoteId,
          ));
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

  static String? _fmtDateOrNull(DateTime? d) => d == null ? null : _fmtDate(d);

  static DateTime _parseDate(dynamic v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.parse(v);
    return DateTime.now();
  }

  static DateTime? _parseDateOrNull(dynamic v) {
    if (v == null) return null;
    try {
      return _parseDate(v);
    } catch (_) {
      return null;
    }
  }
}
