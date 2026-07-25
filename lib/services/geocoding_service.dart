// NEXUS Siembras — Geocodificación inversa (coordenadas → lugar).
//
// Usa Nominatim (OpenStreetMap): gratuito, sin API key, cobertura mundial.
// Política de uso: máximo 1 req/s y User-Agent identificable — aquí solo
// se llama puntualmente (onboarding / edición de predio), muy por debajo
// del límite. https://operations.osmfoundation.org/policies/nominatim/
//
// Requiere conexión a internet; los llamadores deben manejar el caso null
// (sin red o sin resultado) dejando la selección manual como alternativa.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/log.dart';

class GeoLugar {
  const GeoLugar({this.pais, this.iso2, this.region, this.municipio});
  final String? pais;      // "Colombia"
  final String? iso2;      // "CO"
  final String? region;    // departamento/estado: "Quindío"
  final String? municipio; // ciudad/municipio: "Filandia"

  @override
  String toString() =>
      [municipio, region, pais].where((e) => e != null).join(', ');
}

class GeocodingService {
  GeocodingService._();

  static const _timeout = Duration(seconds: 15);

  /// Coordenadas → país/región/municipio. Retorna null si no hay red,
  /// el servicio falla o no encuentra dirección.
  static Future<GeoLugar?> reverse(double lat, double lng) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': '$lat',
      'lon': '$lng',
      'format': 'jsonv2',
      'accept-language': 'es',
      // zoom 10 ≈ nivel ciudad/municipio: suficiente y más estable que
      // el detalle calle a calle.
      'zoom': '10',
    });
    try {
      final r = await http.get(uri, headers: {
        // Requerido por la política de Nominatim.
        'User-Agent': 'NEXUS-Siembras/0.1 (control agropecuario)',
      }).timeout(_timeout);
      if (r.statusCode != 200) {
        Log.w('[geo] Nominatim respondió ${r.statusCode}');
        return null;
      }
      final decoded = jsonDecode(utf8.decode(r.bodyBytes));
      if (decoded is! Map<String, dynamic>) return null;
      final addr = decoded['address'];
      if (addr is! Map<String, dynamic>) return null;

      String? s(dynamic v) {
        final t = v?.toString().trim();
        return (t == null || t.isEmpty) ? null : t;
      }

      // Nominatim varía la clave del nivel "municipio" según el país.
      final municipio = s(addr['city']) ??
          s(addr['town']) ??
          s(addr['village']) ??
          s(addr['municipality']) ??
          s(addr['county']);
      final region = s(addr['state']) ?? s(addr['region']);
      return GeoLugar(
        pais: s(addr['country']),
        iso2: s(addr['country_code'])?.toUpperCase(),
        region: region,
        municipio: municipio,
      );
    } on TimeoutException {
      Log.w('[geo] Nominatim timeout');
      return null;
    } catch (e) {
      Log.w('[geo] reverse($lat,$lng) fallo: $e');
      return null;
    }
  }
}
