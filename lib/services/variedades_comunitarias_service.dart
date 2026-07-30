// NEXUS Siembras — Banco comunitario de variedades (Fase B1, 2026-07-20).
//
// Búsqueda y contribución sobre la tabla pública
// `variedades_comunitarias` (ver supabase/migrations/0008).
// Desde v18 mantiene un espejo local (`variedades_comunitarias_cache`)
// que se refresca al arrancar la app (con sesión) para autocompletar sin
// depender de una consulta remota en cada tecleo.

import 'package:drift/drift.dart';

import '../core/log.dart';
import '../data/database/database.dart';
import 'supabase_service.dart';

class VariedadComunitaria {
  const VariedadComunitaria({
    required this.nombre,
    this.especie,
    this.metodoSiembra,
    this.germinadorDias,
    this.cosechaMinDias,
    this.cosechaMaxDias,
    this.tipoAbono1,
    this.tipoAbono2,
    this.abono2Dias,
    this.fuente,
    this.contribuciones = 1,
  });

  final String nombre;
  final String? especie;
  final String? metodoSiembra;
  final int? germinadorDias;
  final int? cosechaMinDias;
  final int? cosechaMaxDias;
  final String? tipoAbono1;
  final String? tipoAbono2;
  final int? abono2Dias;
  final String? fuente;
  final int contribuciones;

  factory VariedadComunitaria.fromJson(Map<String, dynamic> j) =>
      VariedadComunitaria(
        nombre: j['nombre_comun'] as String? ?? '',
        especie: j['especie'] as String?,
        metodoSiembra: j['metodo_siembra'] as String?,
        germinadorDias: (j['germinador_dias'] as num?)?.toInt(),
        cosechaMinDias: (j['cosecha_min_dias'] as num?)?.toInt(),
        cosechaMaxDias: (j['cosecha_max_dias'] as num?)?.toInt(),
        tipoAbono1: j['tipo_abono1'] as String?,
        tipoAbono2: j['tipo_abono2'] as String?,
        abono2Dias: (j['abono2_dias'] as num?)?.toInt(),
        fuente: j['fuente'] as String?,
        contribuciones: (j['contribuciones'] as num?)?.toInt() ?? 1,
      );

  factory VariedadComunitaria.fromCacheRow(VariedadesComunitariasCacheData r) =>
      VariedadComunitaria(
        nombre: r.nombreComun,
        especie: r.especie,
        metodoSiembra: r.metodoSiembra,
        germinadorDias: r.germinadorDias,
        cosechaMinDias: r.cosechaMinDias,
        cosechaMaxDias: r.cosechaMaxDias,
        tipoAbono1: r.tipoAbono1,
        tipoAbono2: r.tipoAbono2,
        abono2Dias: r.abono2Dias,
        fuente: r.fuente,
        contribuciones: r.contribuciones,
      );

  String get subtitulo => [
        if (especie != null && especie!.isNotEmpty) especie!,
        '$contribuciones aporte${contribuciones == 1 ? '' : 's'}',
      ].join(' · ');
}

class VariedadesComunitariasService {
  VariedadesComunitariasService._();

  static const _pageSize = 500;

  /// Sanea el término para el filtro `or=(...ilike...)` de PostgREST:
  /// comas, paréntesis y comodines romperían la sintaxis del filtro.
  static String _sanear(String term) =>
      term.replaceAll(RegExp(r'[,()%*]'), ' ').trim();

  static String _especieKey(String? especie) {
    final t = especie?.trim();
    return (t == null || t.isEmpty) ? '' : t;
  }

  /// Descarga/actualiza el espejo local desde Supabase. Idempotente.
  /// Requiere sesión; sin red o sin migración 0008 retorna 0 sin lanzar.
  static Future<int> sincronizarEnLocal(AppDatabase db) async {
    final sb = SupabaseService.instance.client;
    if (sb == null || sb.auth.currentSession == null) return 0;
    var total = 0;
    var offset = 0;
    try {
      while (true) {
        final page = await sb
            .from('variedades_comunitarias')
            .select()
            .order('id', ascending: true)
            .range(offset, offset + _pageSize - 1);
        final rows = page as List<dynamic>;
        if (rows.isEmpty) break;
        for (final raw in rows) {
          await _upsertFilaLocal(db, raw as Map<String, dynamic>);
          total++;
        }
        if (rows.length < _pageSize) break;
        offset += _pageSize;
      }
      if (total > 0) {
        Log.i('[variedades] caché local actualizada ($total filas)');
      }
    } catch (e) {
      Log.w('[variedades] sincronizarEnLocal falló: $e');
    }
    return total;
  }

  static Future<void> _upsertFilaLocal(
      AppDatabase db, Map<String, dynamic> j) async {
    final remoteId = j['id'] as int;
    final nombre = (j['nombre_comun'] as String? ?? '').trim();
    if (nombre.length < 2) return;
    final especie = (j['especie'] as String?)?.trim();
    final especieKey = _especieKey(especie);
    final remoteUpdated = _parseDateOrNull(j['updated_at']);

    final companion = VariedadesComunitariasCacheCompanion(
      remoteId: Value(remoteId),
      nombreComun: Value(nombre),
      especieKey: Value(especieKey),
      especie: Value(especie),
      metodoSiembra: Value(j['metodo_siembra'] as String?),
      germinadorDias: Value((j['germinador_dias'] as num?)?.toInt()),
      cosechaMinDias: Value((j['cosecha_min_dias'] as num?)?.toInt()),
      cosechaMaxDias: Value((j['cosecha_max_dias'] as num?)?.toInt()),
      tipoAbono1: Value(j['tipo_abono1'] as String?),
      tipoAbono2: Value(j['tipo_abono2'] as String?),
      abono2Dias: Value((j['abono2_dias'] as num?)?.toInt()),
      fuente: Value(j['fuente'] as String?),
      contribuciones: Value((j['contribuciones'] as num?)?.toInt() ?? 1),
      remoteUpdatedAt: Value(remoteUpdated),
      syncedAt: Value(DateTime.now()),
    );

    final porRemote = await (db.select(db.variedadesComunitariasCache)
          ..where((v) => v.remoteId.equals(remoteId)))
        .getSingleOrNull();
    if (porRemote != null) {
      await (db.update(db.variedadesComunitariasCache)
            ..where((v) => v.id.equals(porRemote.id)))
          .write(companion);
      return;
    }

    final porNatural = await (db.select(db.variedadesComunitariasCache)
          ..where((v) => v.nombreComun.lower().equals(nombre.toLowerCase()))
          ..where((v) => v.especieKey.equals(especieKey))
          ..limit(1))
        .getSingleOrNull();
    if (porNatural != null) {
      await (db.update(db.variedadesComunitariasCache)
            ..where((v) => v.id.equals(porNatural.id)))
          .write(companion);
    } else {
      await db.into(db.variedadesComunitariasCache).insert(companion);
    }
  }

  /// Busca en la caché local (offline, instantáneo).
  static Future<List<VariedadComunitaria>> buscarEnCache(
    AppDatabase db,
    String term, {
    int limit = 8,
  }) async {
    final t = _sanear(term).toLowerCase();
    if (t.length < 2) return const [];
    final rows = await (db.select(db.variedadesComunitariasCache)
          ..where((v) =>
              v.nombreComun.lower().like('%$t%') |
              v.especieKey.lower().like('%$t%'))
          ..orderBy([
            (v) => OrderingTerm.desc(v.contribuciones),
            (v) => OrderingTerm.asc(v.nombreComun),
          ])
          ..limit(limit))
        .get();
    return rows.map(VariedadComunitaria.fromCacheRow).toList();
  }

  /// Busca variedades por nombre o especie. Prioriza la caché local; si
  /// está vacía y hay sesión, consulta el remoto y persiste el resultado.
  static Future<List<VariedadComunitaria>> buscar(
    AppDatabase db,
    String term,
  ) async {
    final local = await buscarEnCache(db, term);
    if (local.isNotEmpty) return local;

    final sb = SupabaseService.instance.client;
    if (sb == null || sb.auth.currentSession == null) return const [];
    final t = _sanear(term);
    if (t.length < 2) return const [];
    try {
      final res = await sb
          .from('variedades_comunitarias')
          .select()
          .or('nombre_comun.ilike.%$t%,especie.ilike.%$t%')
          .order('contribuciones', ascending: false)
          .limit(8);
      final salida = <VariedadComunitaria>[];
      for (final r in res as List<dynamic>) {
        final j = r as Map<String, dynamic>;
        salida.add(VariedadComunitaria.fromJson(j));
        await _upsertFilaLocal(db, j);
      }
      return salida;
    } catch (e) {
      Log.d('[variedades] búsqueda "$t" sin resultados remotos: $e');
      return const [];
    }
  }

  /// Contribuye la variedad al banco (upsert por nombre+especie vía RPC).
  /// Fire-and-forget: nunca lanza.
  static Future<void> contribuir({
    required String nombre,
    String? especie,
    String? metodoSiembra,
    int? germinadorDias,
    int? cosechaMinDias,
    int? cosechaMaxDias,
    String? tipoAbono1,
    String? tipoAbono2,
    int? abono2Dias,
    String? fuente,
  }) async {
    final sb = SupabaseService.instance.client;
    if (sb == null || sb.auth.currentSession == null) return;
    try {
      await sb.rpc('contribuir_variedad', params: {
        'p_nombre': nombre,
        'p_especie': especie,
        'p_metodo': metodoSiembra,
        'p_germinador': germinadorDias,
        'p_cosecha_min': cosechaMinDias,
        'p_cosecha_max': cosechaMaxDias,
        'p_abono1': tipoAbono1,
        'p_abono2': tipoAbono2,
        'p_abono2_dias': abono2Dias,
        'p_fuente': fuente,
      });
      Log.i('[variedades] "$nombre" contribuida al banco comunitario');
    } catch (e) {
      Log.w('[variedades] no se pudo contribuir "$nombre": $e');
    }
  }

  static DateTime? _parseDateOrNull(dynamic v) {
    if (v == null) return null;
    try {
      if (v is DateTime) return v;
      if (v is String) return DateTime.parse(v);
    } catch (_) {}
    return null;
  }
}
