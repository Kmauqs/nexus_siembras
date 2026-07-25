import 'dart:convert';

/// Un ciclo de fertilización: tipo de abono y días desde la fecha base
/// fenológica (siembra o trasplante).
class CicloAbono {
  const CicloAbono({required this.tipo, required this.dias});
  final String tipo;
  final int dias;

  Map<String, dynamic> toJson() => {'tipo': tipo, 'dias': dias};

  factory CicloAbono.fromJson(Map<String, dynamic> j) => CicloAbono(
        tipo: (j['tipo'] as String?)?.trim() ?? '',
        dias: (j['dias'] as num?)?.toInt() ?? 1,
      );
}

/// Tipos de abono sugeridos en el selector del formulario de variedad.
const tiposAbonoSugeridos = [
  'Triple 15',
  'Gallinaza',
  'Urea 15-15-15',
  'DAP 18-46-0',
  'Compost',
  'Cal dolomita',
  'Otro',
];

String? encodeCiclosAbonoJson(List<CicloAbono> ciclos) {
  if (ciclos.isEmpty) return null;
  return jsonEncode(ciclos.map((c) => c.toJson()).toList());
}

/// Decodifica [json]. Si está vacío, reconstruye desde columnas legacy
/// (`tipoAbono1` día 1, `tipoAbono2` + `diasAbono2`).
List<CicloAbono> decodeCiclosAbonoJson(
  String? json, {
  String? tipoAbono1,
  String? tipoAbono2,
  int? diasAbono2,
}) {
  if (json != null && json.trim().isNotEmpty) {
    try {
      final raw = jsonDecode(json) as List<dynamic>;
      final list = raw
          .map((e) => CicloAbono.fromJson(e as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.dias.compareTo(b.dias));
      if (list.isNotEmpty) return list;
    } catch (_) {}
  }
  final legacy = <CicloAbono>[];
  if (tipoAbono1 != null && tipoAbono1.trim().isNotEmpty) {
    legacy.add(CicloAbono(tipo: tipoAbono1.trim(), dias: 1));
  } else {
    legacy.add(const CicloAbono(tipo: '', dias: 1));
  }
  if (tipoAbono2 != null &&
      tipoAbono2.trim().isNotEmpty &&
      diasAbono2 != null &&
      diasAbono2 > 0) {
    legacy.add(CicloAbono(tipo: tipoAbono2.trim(), dias: diasAbono2));
  }
  return legacy;
}
