// NEXUS Siembras — Catálogo de unidades de medida
// Alineado con el Anexo A de 02_ESQUEMA_BD.md y el prototipo HTML.

class UnidadMedida {
  const UnidadMedida({
    required this.codigo,
    required this.nombre,
    required this.dimension, // peso | volumen | longitud | unidad
    required this.sistema,   // SI | imperial | tecnico | cgs | universal
    required this.factorSi,
    required this.unidadBase, // kg | m3 | m | und
  });
  final String codigo, nombre, dimension, sistema, unidadBase;
  final double factorSi;

  String get label => '$codigo — $nombre';
}

/// Todas las unidades soportadas, agrupables por dimensión.
const kUnidades = <UnidadMedida>[
  // Peso (base: kg)
  UnidadMedida(codigo:'ton', nombre:'Tonelada',    dimension:'peso', sistema:'SI',       factorSi:1000.0,      unidadBase:'kg'),
  UnidadMedida(codigo:'kg',  nombre:'Kilogramo',   dimension:'peso', sistema:'SI',       factorSi:1.0,         unidadBase:'kg'),
  UnidadMedida(codigo:'gr',  nombre:'Gramo',       dimension:'peso', sistema:'SI',       factorSi:0.001,       unidadBase:'kg'),
  UnidadMedida(codigo:'lb',  nombre:'Libra',       dimension:'peso', sistema:'imperial', factorSi:0.45359237,  unidadBase:'kg'),
  UnidadMedida(codigo:'oz',  nombre:'Onza',        dimension:'peso', sistema:'imperial', factorSi:0.0283495,   unidadBase:'kg'),
  UnidadMedida(codigo:'@',   nombre:'Arroba (12.5 kg)',    dimension:'peso', sistema:'universal', factorSi:12.5,   unidadBase:'kg'),
  UnidadMedida(codigo:'carga',nombre:'Carga (125 kg)',     dimension:'peso', sistema:'universal', factorSi:125.0,  unidadBase:'kg'),
  UnidadMedida(codigo:'bulto22',nombre:'Bulto 22.5 kg',    dimension:'peso', sistema:'universal', factorSi:22.5,   unidadBase:'kg'),
  UnidadMedida(codigo:'bulto25',nombre:'Bulto 25 kg',      dimension:'peso', sistema:'universal', factorSi:25.0,   unidadBase:'kg'),
  UnidadMedida(codigo:'bulto50',nombre:'Bulto 50 kg',      dimension:'peso', sistema:'universal', factorSi:50.0,   unidadBase:'kg'),
  UnidadMedida(codigo:'bulto70',nombre:'Bulto 70 kg',      dimension:'peso', sistema:'universal', factorSi:70.0,   unidadBase:'kg'),
  UnidadMedida(codigo:'N',   nombre:'Newton (masa)', dimension:'peso', sistema:'tecnico', factorSi:0.10197,    unidadBase:'kg'),
  UnidadMedida(codigo:'dyn', nombre:'Dina',        dimension:'peso', sistema:'cgs',      factorSi:1.0197e-6,   unidadBase:'kg'),

  // Volumen (base: m3)
  UnidadMedida(codigo:'m3',    nombre:'Metro cúbico',      dimension:'volumen', sistema:'SI',       factorSi:1.0,         unidadBase:'m3'),
  UnidadMedida(codigo:'l',     nombre:'Litro',             dimension:'volumen', sistema:'SI',       factorSi:0.001,       unidadBase:'m3'),
  UnidadMedida(codigo:'ml',    nombre:'Mililitro',         dimension:'volumen', sistema:'SI',       factorSi:1e-6,        unidadBase:'m3'),
  UnidadMedida(codigo:'cm3',   nombre:'Centímetro cúbico', dimension:'volumen', sistema:'cgs',      factorSi:1e-6,        unidadBase:'m3'),
  UnidadMedida(codigo:'mm3',   nombre:'Milímetro cúbico',  dimension:'volumen', sistema:'SI',       factorSi:1e-9,        unidadBase:'m3'),
  UnidadMedida(codigo:'gal',   nombre:'Galón (US)',        dimension:'volumen', sistema:'imperial', factorSi:0.003785411, unidadBase:'m3'),
  UnidadMedida(codigo:'qt',    nombre:'Cuarto (US)',       dimension:'volumen', sistema:'imperial', factorSi:0.000946353, unidadBase:'m3'),
  UnidadMedida(codigo:'pt',    nombre:'Pinta (US)',        dimension:'volumen', sistema:'imperial', factorSi:0.000473176, unidadBase:'m3'),
  UnidadMedida(codigo:'floz',  nombre:'Onza líquida',      dimension:'volumen', sistema:'imperial', factorSi:2.95735e-5,  unidadBase:'m3'),
  UnidadMedida(codigo:'bulto', nombre:'Bulto (equiv. 50 kg)', dimension:'volumen', sistema:'universal', factorSi:0.05,    unidadBase:'m3'),

  // Longitud (base: m)
  UnidadMedida(codigo:'km', nombre:'Kilómetro',  dimension:'longitud', sistema:'SI',       factorSi:1000.0,   unidadBase:'m'),
  UnidadMedida(codigo:'m',  nombre:'Metro',      dimension:'longitud', sistema:'SI',       factorSi:1.0,      unidadBase:'m'),
  UnidadMedida(codigo:'cm', nombre:'Centímetro', dimension:'longitud', sistema:'SI',       factorSi:0.01,     unidadBase:'m'),
  UnidadMedida(codigo:'mm', nombre:'Milímetro',  dimension:'longitud', sistema:'SI',       factorSi:0.001,    unidadBase:'m'),
  UnidadMedida(codigo:'in', nombre:'Pulgada',    dimension:'longitud', sistema:'imperial', factorSi:0.0254,   unidadBase:'m'),
  UnidadMedida(codigo:'ft', nombre:'Pie',        dimension:'longitud', sistema:'imperial', factorSi:0.3048,   unidadBase:'m'),
  UnidadMedida(codigo:'yd', nombre:'Yarda',      dimension:'longitud', sistema:'imperial', factorSi:0.9144,   unidadBase:'m'),
  UnidadMedida(codigo:'mi', nombre:'Milla',      dimension:'longitud', sistema:'imperial', factorSi:1609.344, unidadBase:'m'),

  // Área (base: m²)
  UnidadMedida(codigo:'m2',      nombre:'Metro cuadrado',       dimension:'area', sistema:'SI',       factorSi:1.0,        unidadBase:'m2'),
  UnidadMedida(codigo:'ha',      nombre:'Hectárea',             dimension:'area', sistema:'SI',       factorSi:10000.0,    unidadBase:'m2'),
  UnidadMedida(codigo:'cuadra',  nombre:'Cuadra (Colombia ≈ 80×80 m)', dimension:'area', sistema:'universal', factorSi:6400.0, unidadBase:'m2'),
  UnidadMedida(codigo:'acre',    nombre:'Acre',                 dimension:'area', sistema:'imperial', factorSi:4046.856,   unidadBase:'m2'),
  UnidadMedida(codigo:'ft2',     nombre:'Pie cuadrado',         dimension:'area', sistema:'imperial', factorSi:0.09290304, unidadBase:'m2'),
  UnidadMedida(codigo:'yd2',     nombre:'Yarda cuadrada',       dimension:'area', sistema:'imperial', factorSi:0.83612736, unidadBase:'m2'),
  UnidadMedida(codigo:'mi2',     nombre:'Milla cuadrada',       dimension:'area', sistema:'imperial', factorSi:2589988.11, unidadBase:'m2'),

  // Unidad
  UnidadMedida(codigo:'und', nombre:'Unidad', dimension:'unidad', sistema:'universal', factorSi:1.0, unidadBase:'und'),
];

Iterable<UnidadMedida> unidadesPorDimension(String d) =>
    kUnidades.where((u) => u.dimension == d);

UnidadMedida? unidadPorCodigo(String c) =>
    kUnidades.where((u) => u.codigo == c).cast<UnidadMedida?>().firstOrNull;

extension _ItFirstOrNull<T> on Iterable<T?> {
  T? get firstOrNull => isEmpty ? null : first;
}

// ============================================================
// CONVERSIÓN Y DISPLAY POR SISTEMA
// ============================================================

/// Convierte un valor + código de unidad a su equivalente en unidad base SI.
/// Devuelve `(baseValue, baseCode)`. Si el código no existe, devuelve tal cual.
(double, String) toBase(double value, String codigo) {
  final u = unidadPorCodigo(codigo);
  if (u == null) return (value, codigo);
  return (value * u.factorSi, u.unidadBase);
}

/// Convierte desde la unidad base a la unidad objetivo. Devuelve el valor
/// numérico convertido. Si el objetivo no existe/no aplica, devuelve el input.
double fromBase(double baseValue, String targetCodigo) {
  final u = unidadPorCodigo(targetCodigo);
  if (u == null || u.factorSi == 0) return baseValue;
  return baseValue / u.factorSi;
}

/// Devuelve la unidad de display preferida según el sistema seleccionado y
/// la unidad base (kg/m/m3/m2/und). Fallback conservador si no hay mapping.
String preferredUnitFor(String sistema, String unidadBase) {
  const map = <(String, String), String>{
    // SI
    ('SI', 'kg'): 'kg',
    ('SI', 'm3'): 'm3',
    ('SI', 'm'):  'm',
    ('SI', 'm2'): 'm2',
    ('SI', 'und'):'und',
    // Imperial
    ('imperial', 'kg'): 'lb',
    ('imperial', 'm3'): 'gal',
    ('imperial', 'm'):  'ft',
    ('imperial', 'm2'): 'acre',
    ('imperial', 'und'):'und',
    // Técnico (kgf) — se mantiene métrico para masas, kgf = kg práctico
    ('tecnico', 'kg'): 'kg',
    ('tecnico', 'm3'): 'm3',
    ('tecnico', 'm'):  'm',
    ('tecnico', 'm2'): 'ha',
    ('tecnico', 'und'):'und',
    // CGS (centímetro-gramo-segundo)
    ('cgs', 'kg'): 'gr',
    ('cgs', 'm3'): 'cm3',
    ('cgs', 'm'):  'cm',
    ('cgs', 'm2'): 'm2',
    ('cgs', 'und'):'und',
  };
  return map[(sistema, unidadBase)] ?? unidadBase;
}

/// Nombre legible del sistema (para reportes).
String nombreSistema(String sistema) => switch (sistema) {
      'SI' => 'Internacional (SI)',
      'imperial' => 'Imperial',
      'tecnico' => 'Técnico (kgf)',
      'cgs' => 'Cegesimal (CGS)',
      _ => sistema,
    };

/// Estructura pequeña con el valor + código de unidad ya convertidos para display.
class DisplayQty {
  const DisplayQty(this.value, this.codigo);
  final double value;
  final String codigo;

  String format([int? decimals]) {
    final d = decimals ?? (value == value.roundToDouble() ? 0 : 2);
    return '${value.toStringAsFixed(d)} $codigo';
  }
}

/// Convierte un `(baseValue, baseCode)` al display preferido del sistema.
DisplayQty displayInSystem(
    double baseValue, String baseCode, String sistema) {
  final targetCode = preferredUnitFor(sistema, baseCode);
  final v = fromBase(baseValue, targetCode);
  return DisplayQty(v, targetCode);
}
