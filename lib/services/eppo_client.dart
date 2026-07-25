// NEXUS Siembras — Cliente EPPO Global Database (API v2)
//
// Documentación: https://data.eppo.int/ui/#/docs/GDAPI
// Base URL:      https://api.eppo.int/gd/v2
// Auth:          header `X-Api-Key: <token>`
// Token:         se genera en https://data.eppo.int/ui/#/apikeys/
//
// ---------------------------------------------------------------
// Endpoints usados por la app (Fase 3i-B):
//   GET  /status                                     → healthcheck
//   GET  /taxons/list?limit=1                        → verificar token
//   GET  /tools/name2codes?intext=<nombres>          → nombres → EPPO codes
//   GET  /taxons/taxon/{EPPOCODE}/pests              → pests de un host
//
// ---------------------------------------------------------------
// Endpoints adicionales expuestos para uso futuro (mismo patrón,
// respuesta paginada `data[]`):
//   GET  /taxons/taxon/{EPPOCODE}/hosts              → hosts de un pest
//   GET  /taxons/taxon/{EPPOCODE}/vectors            → vectores
//   GET  /taxons/taxon/{EPPOCODE}/vectorof           → organismos de los que es vector
//   GET  /taxons/taxon/{EPPOCODE}/bca                → BCAs para un taxon
//   GET  /taxons/taxon/{EPPOCODE}/bcaof              → organismos para los que es BCA
//   GET  /taxons/taxon/{EPPOCODE}/photos             → fotos
//   GET  /taxons/taxon/{EPPOCODE}/reporting_articles → artículos de reporte
//   GET  /taxons/taxon/{EPPOCODE}/names              → nombres alternativos
//   GET  /references/pestHostClassification          → clasificaciones pest/host
//   GET  /references/vectorClassification            → clasificaciones vector
//   GET  /references/countries                       → países
//   GET  /references/countriesStates                 → estados de país
//   GET  /country/{ISOCODE}/overview                 → info básica país
//
// Rate limit: pausa de 200ms entre requests para no saturar el servidor.
// Timeout:    20s por request.

import 'dart:async';
import 'dart:convert';
import 'dart:io' show HandshakeException, HttpClient;
import 'package:crypto/crypto.dart' show sha256;
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../core/log.dart';

/// Infiere el tipo taxonómico de una patología a partir del nombre
/// científico usando sufijos y géneros conocidos. Retorna null si no
/// puede clasificar.
///
/// Motivo: los endpoints de EPPO v2 (/pests) devuelven `class_label`
/// con valores como "Major pest" / "Minor pest" (severidad, no tipo
/// biológico). Determinar hongo vs bacteria vs virus requiere
/// /taxon/{code}/taxonomy — una llamada extra por cada pest. La
/// heurística cubre ~95% de casos sin llamadas de red.
String? inferirTipoTaxonomico(String? nombreCientifico) {
  if (nombreCientifico == null) return null;
  final n = nombreCientifico.toLowerCase().trim();
  if (n.isEmpty) return null;

  // 1. VIRUS — indicadores muy específicos (baja tasa de falsos positivos).
  if (n.contains('virus') || n.contains('viro') || n.endsWith('viroid')) {
    return 'virus';
  }

  // 2. BACTERIAS — primero géneros conocidos.
  const generosBacterias = [
    'xanthomonas', 'pseudomonas', 'erwinia', 'ralstonia', 'clavibacter',
    'candidatus', 'agrobacterium', 'burkholderia', 'streptomyces',
    'xylella', 'liberibacter', 'phytoplasma', 'spiroplasma', 'pantoea',
    'dickeya', 'pectobacterium', 'rhizobium',
  ];
  for (final g in generosBacterias) {
    if (n.startsWith(g) || n.contains(' $g')) return 'bacteria';
  }
  // "bacter" en el nombre → bacteria. Notar que "Bactrocera" (mosca de
  // fruta) NO contiene "bacter" (falta la 'e'), por lo que este catch-all
  // no colisiona con las plagas.
  if (n.contains('bacter')) return 'bacteria';

  // 3. PLAGAS — géneros conocidos (insectos, nematodos, ácaros).
  const generosPlaga = [
    // Nematodos
    'meloidogyne', 'radopholus', 'pratylenchus', 'heterodera',
    'globodera', 'aphelenchoides', 'ditylenchus', 'longidorus',
    // Ácaros
    'tetranychus', 'panonychus', 'brevipalpus', 'oligonychus',
    'polyphagotarsonemus',
    // Insectos comunes
    'bemisia', 'trialeurodes', 'aleurocanthus',
    'frankliniella', 'thrips', 'scirtothrips',
    'aphis', 'myzus', 'brevicoryne', 'toxoptera', 'rhopalosiphum',
    'spodoptera', 'helicoverpa', 'heliothis', 'agrotis', 'plutella',
    'tuta', 'diaphorina', 'diabrotica', 'anthonomus',
    'hypothenemus', 'scolytus', 'ips',
    'bactrocera', 'ceratitis', 'anastrepha', 'rhagoletis', 'drosophila',
    'coccus', 'planococcus', 'pseudococcus', 'saissetia', 'dactylopius',
    'aonidiella', 'diaspis', 'lepidosaphes', 'quadraspidiotus',
    'nezara', 'euschistus', 'lygus', 'dysdercus',
    'liriomyza', 'phytomyza',
    'acanthoscelides', 'callosobruchus', 'zabrotes',
    'amblypelta',
    // Hormigas arrieras (Formicidae) — plagas primarias en Colombia.
    'atta', 'acromyrmex',
  ];
  for (final g in generosPlaga) {
    if (n.startsWith(g) || n.contains(' $g')) return 'plaga';
  }

  // 4. SUFIJOS DE PLAGA sobre el GÉNERO (primera palabra del nombre
  //    binomial). Ejemplo: "Maconellicoccus hirsutus" → género
  //    "maconellicoccus" termina en -coccus → plaga.
  //    Aplicados DESPUÉS de bacterias para no confundir Streptococcus,
  //    y ANTES de hongos genéricos.
  final genero = n.split(' ').first;
  const sufijosPlagaGenero = ['coccus', 'optera', 'nodes'];
  for (final s in sufijosPlagaGenero) {
    if (genero.endsWith(s)) return 'plaga';
  }

  // 5. HONGOS — géneros conocidos (antes que -oides para no confundir
  //    Colletotrichum gloeosporioides con plaga).
  const generosHongo = [
    'fusarium', 'alternaria', 'botrytis', 'colletotrichum', 'phytophthora',
    'puccinia', 'cercospora', 'mycosphaerella', 'hemileia', 'ceratocystis',
    'erysiphe', 'peronospora', 'plasmopara', 'sclerotinia', 'rhizoctonia',
    'sclerotium', 'verticillium', 'pythium', 'penicillium', 'aspergillus',
    'trichoderma', 'monilinia', 'venturia', 'taphrina', 'oidium',
    'phakopsora', 'uredo', 'ustilago', 'tilletia', 'peronosclerospora',
    'sphaerotheca', 'podosphaera', 'leveillula', 'entyloma', 'pestalotia',
    'pestalotiopsis', 'lasiodiplodia', 'diplodia', 'macrophomina',
    'phomopsis', 'diaporthe', 'phoma', 'stemphylium', 'exserohilum',
    'bipolaris', 'drechslera', 'pyricularia', 'magnaporthe',
  ];
  for (final g in generosHongo) {
    if (n.startsWith(g) || n.contains(' $g')) return 'hongo';
  }

  // 6. SUFIJOS DE HONGOS: incluye "ospora" en cualquier posición
  //    (Cercospora, Peronospora, etc.) además de sufijos de familia/orden.
  const sufijosHongoEnd = ['mycota', 'mycetes', 'sporium'];
  for (final s in sufijosHongoEnd) {
    if (n.endsWith(s)) return 'hongo';
  }
  if (n.contains('ospora')) return 'hongo';

  // 7. FALLBACK: -oides en el género (nematodos y otros invertebrados
  //    sin género catalogado, ej. Aphelenchoides). Aplicado al final
  //    para no chocar con Colletotrichum gloeosporioides (hongo, ya
  //    atrapado en el paso 5).
  if (genero.endsWith('oides')) return 'plaga';

  return null;
}

class EppoException implements Exception {
  final String mensaje;
  final int? statusCode;
  const EppoException(this.mensaje, {this.statusCode});
  @override
  String toString() =>
      statusCode == null ? 'EppoException: $mensaje' : '[$statusCode] $mensaje';
}

class EppoPest {
  final String eppocode;
  final String? prefname;
  const EppoPest({required this.eppocode, this.prefname});
}

class EppoStatus {
  final bool ok;
  final String? version;
  final String? mensaje;
  const EppoStatus({required this.ok, this.version, this.mensaje});
}

/// Resultado detallado de una búsqueda EPPO para inspección diagnóstica.
class EppoDebugSearch {
  final String url;
  final int statusCode;
  final String? bodyPreview;
  final int totalEncontrados;
  final List<Map<String, dynamic>> primerosResultados;
  final String? matchElegido;
  final String? error;
  const EppoDebugSearch({
    required this.url,
    required this.statusCode,
    this.bodyPreview,
    required this.totalEncontrados,
    required this.primerosResultados,
    this.matchElegido,
    this.error,
  });
}

class EppoClient {
  EppoClient(this.token) : _client = _crearHttpClient();
  final String token;
  final http.Client _client;

  static const String _baseUrl = 'https://api.eppo.int/gd/v2';
  static const String _apiHost = 'api.eppo.int';
  static const _rateLimit = Duration(milliseconds: 200);
  static const _timeout = Duration(seconds: 20);
  DateTime? _ultimaReq;

  /// Certificate pinning para `api.eppo.int` (auditoría 2026-07-19, S2).
  ///
  /// Motivo original de la excepción: el servidor EPPO responde con una
  /// cadena TLS que Dart no puede completar (faltan intermediates / la CA
  /// raíz está fuera del bundle Mozilla de Dart). Antes se aceptaba
  /// CUALQUIER certificado para ese host — vulnerable a MITM en redes
  /// hostiles (el token viaja en el header `X-Api-Key`).
  ///
  /// Ahora: solo se acepta un certificado cuyo SHA-256 (del DER) esté en
  /// [_eppoPins]. Para obtener el fingerprint vigente ejecutar:
  ///
  ///     dart run tool/eppo_fingerprint.dart
  ///
  /// e incluirlo abajo. Añadir también el del certificado de renovación
  /// cuando EPPO lo publique (los certificados rotan ~cada 90 días si es
  /// Let's Encrypt; verificar al fallar la conexión).
  ///
  /// MIENTRAS LA LISTA ESTÉ VACÍA: se rechaza el certificado no validable
  /// (comportamiento seguro por defecto) y se registra el fingerprint
  /// observado en el log para poder copiarlo aquí. Si Dart logra validar
  /// la cadena por sí mismo (p. ej. EPPO arregló sus intermediates), la
  /// conexión funciona sin necesidad de pin.
  static const Set<String> _eppoPins = {
    // Certificado HOJA vigente de api.eppo.int (obtenido con
    // tool/eppo_fingerprint.dart el 2026-07-20). Rota cada pocos meses.
    '7f05c01be3c6dc40c82237524c2645fea2e36a3b5f528652a379e3ddae6048ba',
    // Certificado INTERMEDIO "Sectigo Public Server Authentication CA OV
    // R36" (emisor: Sectigo Root R46). Es el que falla en Android: su raíz
    // R46 no está en el almacén de confianza de muchos dispositivos, y la
    // validación se corta en el intermedio (2026-07-20). Anclarlo equivale
    // a confiar en esa CA para este host; es estable por años (el
    // intermedio expira ~2036), a diferencia del pin de la hoja.
    '6542d176bed50f193c0ce297ae44ecd8a0a86bec2ede682769344059b4e78530',
  };

  /// Detalle del último certificado rechazado por el pinning. Se anexa al
  /// mensaje de error TLS para diagnosticar desde la UI (2026-07-20):
  /// permite ver en pantalla el host real, el emisor y el fingerprint que
  /// habría que añadir a [_eppoPins], sin necesidad de adb/logs.
  static String? _ultimoRechazoTls;

  static http.Client _crearHttpClient() {
    final ioClient = HttpClient()
      ..badCertificateCallback = (cert, host, port) {
        final fp = sha256.convert(cert.der).toString();
        if (host == _apiHost && port == 443 && _eppoPins.contains(fp)) {
          return true;
        }
        _ultimoRechazoTls = 'host=$host:$port | sujeto=${cert.subject} | '
            'emisor=${cert.issuer} | sha256=$fp';
        Log.w('[eppo] certificado rechazado → $_ultimoRechazoTls. '
            'Si es legítimo, añadir el sha256 a _eppoPins '
            '(lib/services/eppo_client.dart).');
        return false;
      };
    return IOClient(ioClient);
  }

  /// Libera recursos del socket subyacente. Llamar cuando ya no se usa.
  void close() => _client.close();

  Map<String, String> get _authHeaders => {
        'X-Api-Key': token,
        'Accept': 'application/json',
      };

  Future<void> _pausarRateLimit() async {
    final ahora = DateTime.now();
    if (_ultimaReq != null) {
      final delta = ahora.difference(_ultimaReq!);
      if (delta < _rateLimit) {
        await Future.delayed(_rateLimit - delta);
      }
    }
    _ultimaReq = DateTime.now();
  }

  Uri _uri(String path, [Map<String, String>? extraParams]) {
    final base = Uri.parse('$_baseUrl$path');
    if (extraParams == null || extraParams.isEmpty) return base;
    return base.replace(queryParameters: extraParams);
  }

  // ==================================================
  // Endpoints principales
  // ==================================================

  /// Healthcheck del API. No requiere token pero lo enviamos igual.
  /// Retorna false si el servidor responde con error o hay problema de red.
  Future<EppoStatus> checkStatus() async {
    try {
      final r = await _get('/status');
      String? version;
      String? mensaje;
      try {
        final decoded = jsonDecode(r.body);
        if (decoded is Map<String, dynamic>) {
          version = decoded['version']?.toString() ??
              decoded['api_version']?.toString();
          mensaje = decoded['status']?.toString() ??
              decoded['message']?.toString();
        }
      } catch (_) {}
      return EppoStatus(ok: true, version: version, mensaje: mensaje);
    } on EppoException catch (e) {
      return EppoStatus(ok: false, mensaje: e.mensaje);
    } catch (e) {
      return EppoStatus(ok: false, mensaje: e.toString());
    }
  }

  /// Prueba de conexión con el token. Retorna true si es válido.
  Future<bool> verificarToken() async {
    try {
      final r = await _get('/taxons/list', {'limit': '1'});
      return r.statusCode == 200;
    } on EppoException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Como verificarToken pero lanza la excepción con detalle en caso de
  /// error, para poder mostrar el mensaje exacto en la UI de Settings.
  Future<void> verificarTokenConError() async {
    await _get('/taxons/list', {'limit': '1'});
  }

  /// Resuelve una lista de nombres científicos → mapa {nombre → EPPOCode}.
  /// Los nombres no encontrados (o < 3 chars) se omiten silenciosamente.
  ///
  /// Implementación: llama `/tools/search?keyword=<nombre>&searchMode=3`
  /// por cada nombre. Params del API v2:
  ///   - `keyword` (requerido, min 3 chars)
  ///   - `searchMode`: 1=whole word, 2=starting with (default), 3=containing
  ///
  /// Usamos `searchMode=3` (containing) para ser tolerantes con nombres
  /// compuestos como "Coffea arabica" donde EPPO puede tener sufijos
  /// taxonómicos ("Coffea arabica L.").
  ///
  /// El desempate por match exacto lo hace `_mejorEppoCodeDeSearch`
  /// comparando `preferred_name`/`full_name` con el nombre buscado.
  Future<Map<String, String>> resolverEppoCodes(List<String> nombres) async {
    final resultado = <String, String>{};
    for (final nombre in nombres) {
      final n = nombre.trim();
      if (n.length < 3) continue; // req del API v2
      try {
        final r = await _get('/tools/search', {
          'keyword': n,
          'searchMode': '3',
        });
        final code = _mejorEppoCodeDeSearch(r.body, n);
        if (code != null) resultado[n] = code;
      } on EppoException {
        // silencioso — seguimos con el siguiente
      }
    }
    return resultado;
  }

  /// Ejecuta la misma búsqueda que `resolverEppoCodes` pero retorna el
  /// contexto completo (URL, status, resultados crudos y match elegido)
  /// para diagnóstico. NO cacheado, sí respeta rate limit.
  Future<EppoDebugSearch> debugSearch(String term) async {
    final params = {
      'keyword': term,
      'searchMode': '3',
    };
    final uri = _uri('/tools/search', params);
    try {
      final resp = await _get('/tools/search', params);
      final bodyPreview = resp.body.length > 800
          ? '${resp.body.substring(0, 800)}…'
          : resp.body;
      List<dynamic> items;
      dynamic decoded;
      try {
        decoded = jsonDecode(resp.body);
      } catch (_) {
        return EppoDebugSearch(
          url: uri.toString(),
          statusCode: resp.statusCode,
          bodyPreview: bodyPreview,
          totalEncontrados: 0,
          primerosResultados: const [],
          error: 'Body no es JSON válido',
        );
      }
      if (decoded is Map<String, dynamic> && decoded['data'] is List) {
        items = decoded['data'] as List;
      } else if (decoded is List) {
        items = decoded;
      } else {
        items = const [];
      }
      final primeros = items
          .whereType<Map>()
          .take(5)
          .map((m) => m.cast<String, dynamic>())
          .toList();
      final code = _mejorEppoCodeDeSearch(resp.body, term);
      return EppoDebugSearch(
        url: uri.toString(),
        statusCode: resp.statusCode,
        bodyPreview: bodyPreview,
        totalEncontrados: items.length,
        primerosResultados: primeros,
        matchElegido: code,
      );
    } on EppoException catch (e) {
      return EppoDebugSearch(
        url: uri.toString(),
        statusCode: e.statusCode ?? -1,
        totalEncontrados: 0,
        primerosResultados: const [],
        error: e.mensaje,
      );
    } catch (e) {
      return EppoDebugSearch(
        url: uri.toString(),
        statusCode: -1,
        totalEncontrados: 0,
        primerosResultados: const [],
        error: e.toString(),
      );
    }
  }

  /// Elige el EPPO code que mejor coincide con el nombre buscado.
  /// Prioriza match exacto de `preferred_name`/`full_name` (v2 snake_case)
  /// o `prefname`/`fullname` (v1 legacy). Adicionalmente prefiere las
  /// entradas con `is_preferred=true`.
  String? _mejorEppoCodeDeSearch(String body, String buscado) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return null;
    }
    List<dynamic> items;
    if (decoded is Map<String, dynamic> && decoded['data'] is List) {
      items = decoded['data'] as List;
    } else if (decoded is List) {
      items = decoded;
    } else {
      return null;
    }
    if (items.isEmpty) return null;
    final buscadoLower = buscado.toLowerCase();
    String? codeFallback;
    String? codePreferidoFallback;
    for (final item in items) {
      if (item is! Map) continue;
      final code = item['eppocode']?.toString();
      if (code == null || code.isEmpty) continue;
      codeFallback ??= code;
      final isPreferred = item['is_preferred'] == true;
      if (isPreferred) codePreferidoFallback ??= code;
      // Snake_case (v2 tools search) + camelCase (v1 legacy).
      final pref = (item['preferred_name'] ?? item['prefname'])
              ?.toString()
              .toLowerCase() ??
          '';
      final full = (item['full_name'] ?? item['fullname'])
              ?.toString()
              .toLowerCase() ??
          '';
      if (pref == buscadoLower || full == buscadoLower) {
        return code; // match exacto → preferido
      }
    }
    // Preferimos el primer resultado marcado como preferred; si no hay,
    // el primer resultado en general.
    return codePreferidoFallback ?? codeFallback;
  }

  /// Devuelve la lista de pests/patógenos asociados a un host.
  ///
  /// Endpoint v2: `GET /taxons/taxon/{EPPOCODE}/pests`
  /// Respuesta paginada con `data[]` de taxons.
  Future<List<EppoPest>> getPestsForHost(String hostEppoCode) async {
    return _listarTaxonsPaginados(
        '/taxons/taxon/$hostEppoCode/pests');
  }

  // ==================================================
  // Endpoints adicionales (mismo patrón, respuesta paginada data[])
  // Disponibles para uso futuro por otras features de la app.
  // ==================================================

  /// Hosts que un taxon (patógeno) afecta.
  Future<List<EppoPest>> getHostsForTaxon(String eppoCode) =>
      _listarTaxonsPaginados('/taxons/taxon/$eppoCode/hosts');

  /// Vectores que transmiten un taxon.
  Future<List<EppoPest>> getVectorsForTaxon(String eppoCode) =>
      _listarTaxonsPaginados('/taxons/taxon/$eppoCode/vectors');

  /// Organismos para los que este taxon es un vector.
  Future<List<EppoPest>> getVectorOf(String eppoCode) =>
      _listarTaxonsPaginados('/taxons/taxon/$eppoCode/vectorof');

  /// BCAs (agentes de control biológico) contra un taxon.
  Future<List<EppoPest>> getBcaForTaxon(String eppoCode) =>
      _listarTaxonsPaginados('/taxons/taxon/$eppoCode/bca');

  /// Organismos para los que este taxon es un BCA.
  Future<List<EppoPest>> getBcaOf(String eppoCode) =>
      _listarTaxonsPaginados('/taxons/taxon/$eppoCode/bcaof');

  /// Fotos disponibles en EPPO para un taxon (retorna raw JSON list).
  Future<List<Map<String, dynamic>>> getPhotos(String eppoCode) =>
      _listarRawPaginado('/taxons/taxon/$eppoCode/photos');

  /// Artículos de reporte (EPPO Reporting Service) para un taxon.
  Future<List<Map<String, dynamic>>> getReportingArticles(String eppoCode) =>
      _listarRawPaginado('/taxons/taxon/$eppoCode/reporting_articles');

  /// Todos los nombres alternativos (común, científico, sinónimos) para un taxon.
  Future<List<Map<String, dynamic>>> getNamesForTaxon(String eppoCode) =>
      _listarRawPaginado('/taxons/taxon/$eppoCode/names');

  /// Catálogo de clasificaciones pest/host de EPPO.
  Future<List<Map<String, dynamic>>> getPestHostClassifications() =>
      _listarRawPaginado('/references/pestHostClassification');

  /// Catálogo de clasificaciones de vectores.
  Future<List<Map<String, dynamic>>> getVectorClassifications() =>
      _listarRawPaginado('/references/vectorClassification');

  /// Lista de países (ISO codes + nombres).
  Future<List<Map<String, dynamic>>> getCountries() =>
      _listarRawPaginado('/references/countries');

  /// Lista de estados/regiones por país.
  Future<List<Map<String, dynamic>>> getCountriesStates() =>
      _listarRawPaginado('/references/countriesStates');

  /// Información básica de un país por ISO code (retorna objeto único).
  Future<Map<String, dynamic>?> getCountryOverview(String isoCode) async {
    final r = await _get('/country/$isoCode/overview');
    try {
      final decoded = jsonDecode(r.body);
      if (decoded is Map<String, dynamic>) {
        if (decoded['data'] is Map<String, dynamic>) {
          return decoded['data'] as Map<String, dynamic>;
        }
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  // ==================================================
  // Parsers
  // ==================================================

  /// Extrae mapa {nombre → eppocode} tolerando varios formatos de respuesta:
  ///  - {"data": {"Zea mays": "ZEAMX", ...}}
  ///  - {"data": [{"name":"Zea mays","eppocode":"ZEAMX"}, ...]}
  ///  - {"Zea mays": "ZEAMX"} (formato plano)
  ///  - {"Zea mays": {"eppocode":"ZEAMX", ...}}
  Map<String, String> _extraerNombreACodigo(String body) {
    final resultado = <String, String>{};
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return resultado;
    }
    void procesarMap(Map<String, dynamic> m) {
      m.forEach((nombre, valor) {
        if (valor is String) {
          resultado[nombre] = valor;
        } else if (valor is Map && valor['eppocode'] is String) {
          resultado[nombre] = valor['eppocode'] as String;
        } else if (valor is List && valor.isNotEmpty) {
          final first = valor.first;
          if (first is Map && first['eppocode'] is String) {
            resultado[nombre] = first['eppocode'] as String;
          }
        }
      });
    }

    void procesarList(List lista) {
      for (final item in lista) {
        if (item is! Map) continue;
        final nombre =
            (item['name'] ?? item['input'] ?? item['fullname'])?.toString();
        final code = item['eppocode']?.toString();
        if (nombre != null && code != null) resultado[nombre] = code;
      }
    }

    if (decoded is Map<String, dynamic>) {
      // Formato paginado {data: ..., pagination: ..., meta: ...}
      if (decoded['data'] is Map<String, dynamic>) {
        procesarMap(decoded['data'] as Map<String, dynamic>);
      } else if (decoded['data'] is List) {
        procesarList(decoded['data'] as List);
      } else {
        procesarMap(decoded);
      }
    } else if (decoded is List) {
      procesarList(decoded);
    }
    return resultado;
  }

  /// Lista taxons desde una respuesta paginada v2.
  Future<List<EppoPest>> _listarTaxonsPaginados(String path) async {
    final r = await _get(path, {'limit': '1000'});
    final salida = <EppoPest>[];
    try {
      final decoded = jsonDecode(r.body);
      List<dynamic> items;
      if (decoded is Map<String, dynamic> && decoded['data'] is List) {
        items = decoded['data'] as List;
      } else if (decoded is List) {
        items = decoded;
      } else {
        return const [];
      }
      for (final item in items) {
        if (item is! Map) continue;
        final code = item['eppocode']?.toString();
        if (code == null || code.isEmpty) continue;
        // Reconoce ambos formatos: snake_case (v2 nuevo) y camelCase (v1 legacy).
        final pref = (item['preferred_name'] ??
                item['full_name'] ??
                item['prefname'] ??
                item['fullname'] ??
                item['name'])
            ?.toString();
        salida.add(EppoPest(eppocode: code, prefname: pref));
      }
    } catch (_) {}
    return salida;
  }

  /// Devuelve el array `data` crudo de una respuesta paginada.
  Future<List<Map<String, dynamic>>> _listarRawPaginado(String path) async {
    final r = await _get(path, {'limit': '1000'});
    final salida = <Map<String, dynamic>>[];
    try {
      final decoded = jsonDecode(r.body);
      List<dynamic> items;
      if (decoded is Map<String, dynamic> && decoded['data'] is List) {
        items = decoded['data'] as List;
      } else if (decoded is List) {
        items = decoded;
      } else {
        return const [];
      }
      for (final item in items) {
        if (item is Map<String, dynamic>) salida.add(item);
      }
    } catch (_) {}
    return salida;
  }

  // ==================================================
  // HTTP HELPERS
  // ==================================================

  Future<http.Response> _get(String path,
      [Map<String, String>? queryParams]) async {
    await _pausarRateLimit();
    try {
      final resp = await _client
          .get(_uri(path, queryParams), headers: _authHeaders)
          .timeout(_timeout);
      _throwIfBad(resp, path);
      return resp;
    } on TimeoutException {
      throw const EppoException('Timeout de red al consultar EPPO');
    } on HandshakeException catch (e) {
      // Falla TLS: anexar el detalle del certificado rechazado (si el
      // rechazo vino del pinning) para diagnóstico directo en la UI.
      final detalle = _ultimoRechazoTls;
      throw EppoException(detalle != null
          ? 'TLS rechazado por pinning → $detalle'
          : 'TLS falló antes del pinning (${e.message})');
    }
  }

  /// Intenta extraer el `message` del body de error (formato v2 típico).
  String? _extractServerMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return (decoded['message'] ??
                decoded['error'] ??
                decoded['detail'])
            ?.toString();
      }
    } catch (_) {}
    return null;
  }

  void _throwIfBad(http.Response r, String path) {
    if (r.statusCode == 200) return;
    final srvMsg = _extractServerMessage(r.body);
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw EppoException(
          srvMsg ?? 'Token EPPO inválido o sin permisos',
          statusCode: r.statusCode);
    }
    if (r.statusCode == 404) {
      throw EppoException(
          'Endpoint no encontrado en API v2: $path'
          '${srvMsg != null ? " — $srvMsg" : ""}',
          statusCode: 404);
    }
    throw EppoException(
        'HTTP ${r.statusCode}${srvMsg != null ? " — $srvMsg" : ""} · $path',
        statusCode: r.statusCode);
  }
}
