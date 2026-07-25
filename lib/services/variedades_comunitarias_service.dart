// NEXUS Siembras — Banco comunitario de variedades (Fase B1, 2026-07-20).
//
// Búsqueda y contribución sobre la tabla pública
// `variedades_comunitarias` (ver supabase/migrations/0008).
// Degrada con gracia: sin sesión, sin red o sin la migración aplicada,
// `buscar` retorna [] y `contribuir` no hace nada — el modal "Nueva
// variedad" funciona igual que siempre.

import '../core/log.dart';
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

  String get subtitulo => [
        if (especie != null && especie!.isNotEmpty) especie!,
        '$contribuciones aporte${contribuciones == 1 ? '' : 's'}',
      ].join(' · ');
}

class VariedadesComunitariasService {
  VariedadesComunitariasService._();

  /// Sanea el término para el filtro `or=(...ilike...)` de PostgREST:
  /// comas, paréntesis y comodines romperían la sintaxis del filtro.
  static String _sanear(String term) =>
      term.replaceAll(RegExp(r'[,()%*]'), ' ').trim();

  /// Busca variedades por nombre o especie. Ordena por número de aportes.
  static Future<List<VariedadComunitaria>> buscar(String term) async {
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
      return [
        for (final r in res as List<dynamic>)
          VariedadComunitaria.fromJson(r as Map<String, dynamic>)
      ];
    } catch (e) {
      // Tabla inexistente (migración 0008 sin aplicar), sin red, etc.
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
}
