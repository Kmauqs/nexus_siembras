// NEXUS Siembras — Constructores de datos para reportes (2026-07-20).
//
// Centraliza la recolección de datos que antes vivía duplicada en cada
// pantalla. Los usan tanto los botones "Exportar" de cada pantalla como
// la pantalla Reportes (incluido el reporte consolidado).

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../data/repositories/cultivo_repository.dart';
import '../../state/app_state.dart';
import '../../state/data_state.dart';
import '../units/units_catalog.dart';
import 'report_service.dart';

/// Tabla lista para exportar con `exportarTabla`/`exportPdf`/`exportCsv`.
class TablaReporte {
  const TablaReporte({
    required this.scope,
    required this.titulo,
    required this.columns,
    required this.rows,
  });
  final String scope;
  final String titulo;
  final List<String> columns;
  final List<List<String>> rows;
}

/// Datos del reporte integral del Dashboard (alertas, eventos, compras,
/// HH). Misma derivación que las cards de la pantalla de inicio.
Future<DashboardReportData> buildDashboardData(WidgetRef ref) async {
  final sistema = ref.read(unitSystemProvider);
  final compras = ref.read(comprasProvider);
  final cultivos = ref.read(cultivosActivosProvider);
  final plantas = ref.read(plantasProvider);
  final plantasById = {for (final pl in plantas) pl.id: pl};
  final anio = DateTime.now().year;

  // 1-2. Alertas y próximos eventos.
  final alertas = <List<String>>[];
  final eventos = <List<String>>[];
  for (final c in cultivos) {
    final est = await ref.read(estadoCultivoProvider(c.id).future);
    if (est.estado != EstadoCultivo.verde) {
      final nombre = '${plantasById[c.plantaId]?.nombre ?? '?'} · ${c.lote}';
      alertas.add([
        nombre,
        est.estado == EstadoCultivo.rojo ? 'Alerta' : 'Atención',
        est.nota,
      ]);
      eventos.add([est.nota, nombre]);
    }
  }

  // 3. Compras del año fiscal + agrupación por tipo.
  final delAnio = compras.where((c) => c.fecha.startsWith('$anio')).toList();
  final comprasTotal = delAnio.fold<double>(0, (s, c) => s + c.valor);
  final porTipo = <String, double>{};
  for (final c in delAnio) {
    final t = c.tipo.isEmpty ? 'otro' : c.tipo;
    porTipo[t] = (porTipo[t] ?? 0) + c.valor;
  }
  final rowsCompras = delAnio.map((c) {
    final d = displayInSystem(c.cantidad, c.unidad, sistema);
    final dec = d.value == d.value.roundToDouble() ? 0 : 2;
    return [
      c.fecha, c.desc, c.tipo, c.proveedor,
      d.value.toStringAsFixed(dec), d.codigo,
      '\$ ${c.valor.toStringAsFixed(0)}',
    ];
  }).toList();

  // 4-5. Horas-hombre.
  final hhMes = ref.read(hhPorMesProvider);
  final hhTotal = cultivos.fold<double>(0, (s, c) => s + c.hh);
  final hhPorCultivo = [
    for (final c in cultivos)
      if (c.hh > 0)
        [
          '${plantasById[c.plantaId]?.nombre ?? '?'} · ${c.lote}',
          c.hh.toStringAsFixed(1),
          '${(c.hh / (hhTotal == 0 ? 1 : hhTotal) * 100).toStringAsFixed(1)}%',
        ],
  ];

  // 6. Distribución por usuario (emails vía RPC con caché).
  final hhUsuarios = ref.read(hhPorUsuarioProvider);
  final hhUsuariosTotal = hhUsuarios.values.fold<double>(0, (s, v) => s + v);
  final hhPorUsuario = <List<String>>[];
  for (final e in hhUsuarios.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value))) {
    String etiqueta;
    if (e.key.isEmpty) {
      etiqueta = 'Sin autor (legacy/local)';
    } else {
      final email = await ref.read(emailPorUserIdProvider(e.key).future);
      etiqueta = email ?? '(usuario ${e.key.substring(0, 8)})';
    }
    hhPorUsuario.add([
      etiqueta,
      e.value.toStringAsFixed(1),
      '${(e.value / (hhUsuariosTotal == 0 ? 1 : hhUsuariosTotal) * 100).toStringAsFixed(1)}%',
    ]);
  }

  return DashboardReportData(
    anio: anio,
    alertas: alertas,
    proximosEventos: eventos,
    comprasRows: rowsCompras,
    comprasPorTipo: porTipo,
    comprasTotal: comprasTotal,
    hhPorMes: hhMes,
    hhPorCultivo: hhPorCultivo,
    hhPorUsuario: hhPorUsuario,
  );
}

/// Bloques del CSV del reporte integral (mismas 6 secciones que el PDF).
List<List<Object?>> dashboardCsvBlocks(DashboardReportData data) => [
      ['== 1. CULTIVOS CON ALERTAS =='],
      ['Cultivo', 'Estado', 'Detalle'],
      ...data.alertas,
      [],
      ['== 2. PRÓXIMOS EVENTOS =='],
      ['Actividad', 'Cultivo'],
      ...data.proximosEventos,
      [],
      [
        '== 3. COMPRAS AÑO FISCAL ${data.anio} '
            '(total \$ ${data.comprasTotal.toStringAsFixed(0)}) =='
      ],
      ['Fecha', 'Descripción', 'Tipo', 'Proveedor', 'Cant.', 'Und.', 'Valor'],
      ...data.comprasRows,
      [],
      ['== 4. HORAS-HOMBRE POR MES =='],
      ['Mes', 'HH'],
      for (var m = 1; m <= 12; m++)
        if ((data.hhPorMes[m] ?? 0) > 0)
          ['$m', data.hhPorMes[m]!.toStringAsFixed(1)],
      [],
      ['== 5. DISTRIBUCIÓN HH POR CULTIVO =='],
      ['Cultivo', 'HH', '% del total'],
      ...data.hhPorCultivo,
      [],
      ['== 6. DISTRIBUCIÓN HH POR USUARIO =='],
      ['Usuario', 'HH', '% del total'],
      ...data.hhPorUsuario,
    ];

/// Estado de cada cultivo con sus patologías activas.
Future<TablaReporte> buildCultivosReporte(WidgetRef ref) async {
  final activos = ref.read(cultivosActivosProvider);
  final finalizados = ref.read(cultivosFinalizadosProvider);
  final plantas = ref.read(plantasProvider);
  final plantasById = {for (final pl in plantas) pl.id: pl};
  final catalogo = await ref.read(patologiasCatalogoProvider.future);
  final patNombre = {for (final pt in catalogo) pt.id: pt.nombreComun};

  String estadoTxt(EstadoCultivo e) => switch (e) {
        EstadoCultivo.verde => 'OK',
        EstadoCultivo.naranja => 'Atención',
        EstadoCultivo.rojo => 'Alerta',
      };

  final rows = <List<String>>[];
  for (final c in activos) {
    final est = await ref.read(estadoCultivoProvider(c.id).future);
    final pats =
        await ref.read(patologiasActivasCultivoProvider(c.id).future);
    final patsTxt = pats
        .map((cp) => '${patNombre[cp.patologiaId] ?? 'Sin identificar'}'
            '${cp.severidad != null ? ' (${cp.severidad})' : ''}')
        .join('; ');
    rows.add([
      plantasById[c.plantaId]?.nombre ?? '?',
      c.lote,
      c.sembrado,
      estadoTxt(est.estado),
      est.nota,
      c.hh.toStringAsFixed(1),
      patsTxt.isEmpty ? '—' : patsTxt,
    ]);
  }
  for (final c in finalizados) {
    rows.add([
      plantasById[c.plantaId]?.nombre ?? '?',
      c.lote,
      c.sembrado,
      'Finalizado',
      'Cosechado el ${c.finalizadoFecha ?? '?'}',
      c.hh.toStringAsFixed(1),
      '—',
    ]);
  }
  return TablaReporte(
    scope: 'cultivos',
    titulo: 'Estado de cultivos y patologías activas',
    columns: const [
      'Cultivo', 'Lote', 'Sembrado', 'Estado', 'Detalle', 'HH',
      'Patologías activas'
    ],
    rows: rows,
  );
}

/// Inventario completo, incluidos agotados.
TablaReporte buildInventarioReporte(WidgetRef ref) {
  final sistema = ref.read(unitSystemProvider);
  final items = ref.read(inventoryProvider);
  final rows = items.map((i) {
    final d = displayInSystem(i.cantidad, i.unidad, sistema);
    final dec = d.value == d.value.roundToDouble() ? 0 : 2;
    return [
      i.desc,
      i.cod,
      i.fabricante ?? '',
      d.value.toStringAsFixed(dec),
      d.codigo,
      i.fecha,
      i.cantidad <= 0 ? 'Agotado' : 'Disponible',
    ];
  }).toList();
  return TablaReporte(
    scope: 'inventario',
    titulo: 'Inventario del predio',
    columns: const [
      'Descripción', 'Código', 'Fabricante', 'Cantidad', 'Unidad',
      'Última fecha', 'Estado'
    ],
    rows: rows,
  );
}

/// Todas las compras registradas (histórico completo).
TablaReporte buildComprasReporte(WidgetRef ref) {
  final sistema = ref.read(unitSystemProvider);
  final compras = ref.read(comprasProvider);
  final rows = compras.map((c) {
    final d = displayInSystem(c.cantidad, c.unidad, sistema);
    final dec = d.value == d.value.roundToDouble() ? 0 : 2;
    return [
      c.fecha,
      c.desc,
      c.tipo,
      c.proveedor,
      c.factura,
      d.value.toStringAsFixed(dec),
      d.codigo,
      '\$ ${c.valor.toStringAsFixed(0)}',
    ];
  }).toList();
  return TablaReporte(
    scope: 'compras',
    titulo: 'Compras del predio',
    columns: const [
      'Fecha', 'Descripción', 'Tipo', 'Proveedor', 'Factura',
      'Cant.', 'Und.', 'Valor',
    ],
    rows: rows,
  );
}

/// Datos para el paquete ZIP de compras (reporte extendido + adjuntos).
class ComprasPaqueteExport {
  const ComprasPaqueteExport({
    required this.tabla,
    required this.adjuntos,
  });
  final TablaReporte tabla;
  final List<CompraAdjuntoEnZip> adjuntos;
}

/// Referencia local → ruta dentro del ZIP (`comprobantes/...`).
class CompraAdjuntoEnZip {
  const CompraAdjuntoEnZip({required this.rutaLocal, required this.rutaEnZip});
  final String rutaLocal;
  final String rutaEnZip;
}

/// Reporte completo: factura, código, autor, ruta del comprobante en el ZIP.
Future<ComprasPaqueteExport> buildComprasPaqueteExport(WidgetRef ref) async {
  final sistema = ref.read(unitSystemProvider);
  final compras = ref.read(comprasProvider);
  final rows = <List<String>>[];
  final adjuntos = <CompraAdjuntoEnZip>[];
  final nombresUsados = <String>{};

  for (final c in compras) {
    final d = displayInSystem(c.cantidad, c.unidad, sistema);
    final dec = d.value == d.value.roundToDouble() ? 0 : 2;
    String registradaPor = '—';
    final uid = c.createdByUserId;
    if (uid != null && uid.isNotEmpty) {
      final email = await ref.read(emailPorUserIdProvider(uid).future);
      registradaPor = email ?? '${uid.substring(0, 8)}…';
    }
    var comprobanteZip = '—';
    final soporte = c.soporteName;
    if (soporte != null && soporte.isNotEmpty && await File(soporte).exists()) {
      final enZip = _rutaComprobanteEnZip(c, nombresUsados);
      nombresUsados.add(enZip);
      adjuntos.add(CompraAdjuntoEnZip(rutaLocal: soporte, rutaEnZip: enZip));
      comprobanteZip = enZip;
    }
    rows.add([
      c.fecha,
      c.desc,
      c.desc2 ?? '',
      c.tipo,
      c.proveedor,
      c.factura,
      c.cod,
      d.value.toStringAsFixed(dec),
      d.codigo,
      '\$ ${c.valor.toStringAsFixed(0)}',
      registradaPor,
      comprobanteZip,
    ]);
  }

  return ComprasPaqueteExport(
    tabla: TablaReporte(
      scope: 'compras_completo',
      titulo: 'Compras del predio — reporte completo',
      columns: const [
        'Fecha', 'Descripción', 'Desc. 2', 'Tipo', 'Proveedor', 'Factura',
        'Código', 'Cant.', 'Und.', 'Valor', 'Registrada por',
        'Comprobante (ZIP)',
      ],
      rows: rows,
    ),
    adjuntos: adjuntos,
  );
}

String _rutaComprobanteEnZip(Compra c, Set<String> usados) {
  final factura = _sanitizarNombreArchivo(
      c.factura.trim().isEmpty ? 'sin_factura' : c.factura.trim());
  final fecha = c.fecha.replaceAll('-', '');
  final ext = p.extension(c.soporteName ?? '').toLowerCase();
  final extSegura =
      ext.isNotEmpty ? ext : '.pdf';
  var base = 'comprobantes/${fecha}_${factura}_id${c.id}$extSegura';
  var n = 2;
  while (usados.contains(base)) {
    base =
        'comprobantes/${fecha}_${factura}_id${c.id}_$n$extSegura';
    n++;
  }
  return base;
}

String _sanitizarNombreArchivo(String s) => s
    .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
    .replaceAll(RegExp(r'\s+'), '_');

/// Directorio de proveedores activos.
Future<TablaReporte> buildProveedoresReporte(WidgetRef ref) async {
  final provs = (await ref.read(proveedoresDriftProvider.future))
      .where((x) => x.deletedAt == null)
      .toList();
  final rows = provs
      .map((pr) => [
            pr.nombre,
            pr.nit ?? '',
            pr.telefono ?? '',
            pr.email ?? '',
            pr.web ?? '',
            pr.direccion ?? '',
            pr.notas ?? '',
          ])
      .toList();
  return TablaReporte(
    scope: 'proveedores',
    titulo: 'Directorio de proveedores',
    columns: const [
      'Nombre', 'NIT', 'Teléfono', 'Email', 'Web', 'Dirección', 'Notas'
    ],
    rows: rows,
  );
}
