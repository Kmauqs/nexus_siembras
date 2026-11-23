/// Categorías de inventario / compras (agrupación en pantalla Inventario).
class InventoryCategories {
  InventoryCategories._();

  static const insumos = 'insumos';
  static const semillasEsquejes = 'semillas_esquejes';
  static const herramientasEquipos = 'herramientas_equipos';
  static const poscosecha = 'poscosecha';

  static const all = [
    insumos,
    semillasEsquejes,
    herramientasEquipos,
    poscosecha,
  ];

  static const labels = <String, String>{
    insumos: 'Insumos',
    semillasEsquejes: 'Semillas y esquejes',
    herramientasEquipos: 'Herramientas, equipos y consumibles',
    poscosecha: 'Poscosecha',
  };

  static const hints = <String, String>{
    insumos: 'Abonos, venenos, bolsas, mallas, telas…',
    semillasEsquejes: 'Semillas, esquejes y material de propagación',
    herramientasEquipos: 'Herramientas, equipos y consumibles',
    poscosecha: 'Producto recolectado (primera, segunda, descarte)',
  };

  static String label(String? codigo) =>
      labels[codigo] ?? (codigo?.isNotEmpty == true ? codigo! : 'Sin categoría');

  /// Inferencia desde el `tipo` histórico de compras.
  static String fromCompraTipo(String? tipo) => switch (tipo) {
        'semilla' => semillasEsquejes,
        'abono' || 'pesticida' => insumos,
        'herramienta' => herramientasEquipos,
        _ => insumos,
      };

  static bool vaAlInventario(String? categoria) =>
      categoria != null && all.contains(categoria);
}

/// Grado / clasificación de producto poscosecha.
class GradosPoscosecha {
  GradosPoscosecha._();

  static const primera = 'primera';
  static const segunda = 'segunda';
  static const descarte = 'descarte';

  static const all = [primera, segunda, descarte];

  static const labels = <String, String>{
    primera: 'Primera',
    segunda: 'Segunda',
    descarte: 'Descarte',
  };

  static String label(String? codigo) =>
      labels[codigo] ?? (codigo?.isNotEmpty == true ? codigo! : '—');
}
