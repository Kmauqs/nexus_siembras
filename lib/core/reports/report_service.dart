// NEXUS Siembras — Exportadores CSV/PDF
// Se invocan desde los botones "Exportar CSV / PDF" y reciben datos ya
// convertidos al sistema de unidades activo. Ambos incluyen encabezado con
// datos del predio y nota "Sistema de unidades: X" según lo solicitado.

import 'dart:io';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../units/units_catalog.dart';

class ReportPredio {
  const ReportPredio({
    required this.nombre,
    this.municipio,
    this.region,
    this.pais,
    this.propietario,
  });
  final String nombre;
  final String? municipio, region, pais, propietario;

  String get localizacion => [municipio, region, pais]
      .whereType<String>()
      .where((s) => s.isNotEmpty)
      .join(', ');
}

/// Exporta cualquier tabla como CSV — encabezado del predio + nota del sistema
/// de unidades + filas de datos.
Future<File> exportCsv({
  required String scope, // 'dashboard' | 'inventario' | 'compras' | 'cultivos'
  required ReportPredio predio,
  required String sistemaUnidades,
  required List<String> columns,
  required List<List<Object?>> rows,
}) async {
  final now = DateTime.now();
  final meta = [
    ['Reporte', scope.toUpperCase()],
    ['Predio', predio.nombre],
    ['Localización', predio.localizacion],
    if (predio.propietario != null) ['Propietario', predio.propietario!],
    ['Sistema de unidades', nombreSistema(sistemaUnidades)],
    ['Generado', now.toIso8601String()],
    [],
    columns,
    ...rows,
  ];
  final csv = const ListToCsvConverter().convert(meta);
  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(
      dir.path, 'nexus_${scope}_${now.millisecondsSinceEpoch}.csv'));
  await file.writeAsString(csv);
  return file;
}

/// Genera un PDF con header (predio + logo personalizado a la derecha),
/// tabla y footer con los logos centrados. Devuelve el archivo generado.
/// Usa los mismos helpers que el reporte integral y el consolidado, para
/// que los tres compartan encabezado, pie y saneo de caracteres.
Future<File> exportPdf({
  required String scope,
  required String scopeTitle, // ej. 'Compras del predio'
  required ReportPredio predio,
  required String sistemaUnidades,
  required List<String> columns,
  required List<List<String>> rows,
  PdfPageFormat pageFormat = PdfPageFormat.a4,
}) async {
  final doc = pw.Document();
  final logos = await _cargarLogos();

  doc.addPage(pw.MultiPage(
    pageFormat: pageFormat,
    margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    header: (ctx) => _pdfHeader(predio, sistemaUnidades, logos),
    footer: (ctx) => _pdfFooter(ctx, logos),
    build: (ctx) => [
      pw.SizedBox(height: 8),
      pw.Text(_txt(scopeTitle),
          style: pw.TextStyle(
              fontSize: 14, fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900)),
      pw.SizedBox(height: 8),
      _tablaSec(columns, rows),
    ],
  ));

  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(
      dir.path, 'nexus_${scope}_${DateTime.now().millisecondsSinceEpoch}.pdf'));
  await file.writeAsBytes(await doc.save());
  return file;
}

// =====================================================================
// Reporte integral del Dashboard (2026-07-20)
// Orden solicitado: 1) cultivos con alertas y próximos eventos,
// 2) compras del año fiscal con gráfico circular por tipo,
// 3) horas-hombre por mes, 4) distribución por cultivo,
// 5) distribución por usuario.
// =====================================================================

class DashboardReportData {
  const DashboardReportData({
    required this.anio,
    required this.alertas,
    required this.proximosEventos,
    required this.comprasRows,
    required this.comprasPorTipo,
    required this.comprasTotal,
    required this.hhPorMes,
    required this.hhPorCultivo,
    required this.hhPorUsuario,
  });
  final int anio;
  final List<List<String>> alertas; // [Cultivo, Estado, Detalle]
  final List<List<String>> proximosEventos; // [Actividad, Cultivo]
  final List<List<String>> comprasRows;
  final Map<String, double> comprasPorTipo;
  final double comprasTotal;
  final Map<int, double> hhPorMes; // mes(1-12) → HH
  final List<List<String>> hhPorCultivo; // [Cultivo, HH, %]
  final List<List<String>> hhPorUsuario; // [Usuario, HH, %]
}

const _mesesEs = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', 'Julio',
  'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre'
];

// Colores por tipo de compra — espejo de los del donut del Dashboard.
const _tipoPdfColors = <String, PdfColor>{
  'semilla': PdfColor.fromInt(0xFF1B7A3E),
  'abono': PdfColor.fromInt(0xFF8B6F47),
  'pesticida': PdfColor.fromInt(0xFFB91C1C),
  'herramienta': PdfColor.fromInt(0xFF2563EB),
  'servicio': PdfColor.fromInt(0xFF7C3AED),
  'otro': PdfColor.fromInt(0xFF6B7280),
};
const _tipoPdfLabels = <String, String>{
  'semilla': 'Semilla', 'abono': 'Abono', 'pesticida': 'Pesticida',
  'herramienta': 'Herramienta', 'servicio': 'Servicio', 'otro': 'Otro',
};

/// Saneador para las fuentes base del PDF (Helvetica no mapea varios
/// caracteres Unicode y se imprimen como "Not Defined" ⌷ — reporte del
/// usuario 2026-07-20). Se aplica a títulos y celdas.
String _txt(String s) => s
    .replaceAll('—', '-')
    .replaceAll('–', '-')
    .replaceAll('·', '-')
    .replaceAll('…', '...')
    .replaceAll('“', '"')
    .replaceAll('”', '"')
    .replaceAll('’', '\'')
    .replaceAll('↑', 'sube ')
    .replaceAll('↓', 'baja ')
    .replaceAll('✓', 'OK ')
    .replaceAll('⚠', '! ')
    .replaceAll('🌱', '')
    .replaceAll('💰', '')
    .replaceAll('📦', '')
    .replaceAll('👥', '')
    .replaceAll('🏁', '')
    // Último recurso: cualquier carácter fuera de Latin-1 (que es lo que
    // cubren las fuentes base del PDF) se sustituye para que no aparezca
    // el glifo "Not Defined".
    .replaceAll(RegExp(r'[^\x00-\xFF]'), '');

pw.Widget _tituloSec(String t) => pw.Padding(
      padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
      child: pw.Text(_txt(t),
          style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900)),
    );

pw.Widget _tablaSec(List<String> cols, List<List<String>> rows) => rows.isEmpty
    ? pw.Text('Sin datos.',
        style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700))
    : pw.TableHelper.fromTextArray(
        headers: cols.map(_txt).toList(),
        data: [
          for (final r in rows) r.map(_txt).toList(),
        ],
        headerStyle: pw.TextStyle(
            fontSize: 9,
            fontWeight: pw.FontWeight.bold,
            color: PdfColors.white),
        headerDecoration: const pw.BoxDecoration(color: PdfColors.green800),
        cellStyle: const pw.TextStyle(fontSize: 8),
        cellAlignment: pw.Alignment.centerLeft,
        border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
        columnWidths: _columnWidthsComprasPdf(cols),
      );

/// Anchos relativos para tablas de compras en PDF (reporte propio,
/// consolidado y sección 3 del dashboard). Descripción y Factura −25%;
/// Fecha y Valor ampliadas; sin columna Comprobante.
Map<int, pw.TableColumnWidth>? _columnWidthsComprasPdf(List<String> cols) {
  if (!_esTablaComprasPdf(cols)) return null;
  double flex(String h) => switch (h) {
        'Fecha' => 1.35,
        'Descripción' => 0.75,
        'Tipo' => 0.85,
        'Proveedor' => 1.0,
        'Factura' => 0.85,
        'Desc. 2' => 0.65,
        'Código' => 0.55,
        'Registrada por' => 0.95,
        'Comprobante (ZIP)' => 0.85,
        'Cant.' || 'Cantidad' => 0.65,
        'Und.' || 'Unidad' || 'Unid.' => 0.55,
        'Valor' => 1.35,
        _ => 1.0,
      };
  return {for (var i = 0; i < cols.length; i++) i: pw.FlexColumnWidth(flex(cols[i]))};
}

bool _esTablaComprasPdf(List<String> cols) =>
    cols.isNotEmpty &&
    cols.first == 'Fecha' &&
    cols.contains('Valor') &&
    cols.contains('Descripción') &&
    (cols.contains('Cant.') || cols.contains('Cantidad'));

/// Secciones 1-6 del reporte integral del Dashboard. Compartidas entre
/// `exportDashboardPdf` y `exportConsolidadoPdf`.
List<pw.Widget> _cuerpoDashboard(DashboardReportData data) {
  // Gráfico circular de compras por tipo.
  final tiposOrdenados = data.comprasPorTipo.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final pie = data.comprasTotal <= 0
      ? null
      : pw.SizedBox(
          height: 170,
          child: pw.Chart(
            grid: pw.PieGrid(),
            datasets: [
              for (final e in tiposOrdenados)
                pw.PieDataSet(
                  legend: _txt(
                      '${_tipoPdfLabels[e.key] ?? e.key} ${(e.value / data.comprasTotal * 100).toStringAsFixed(1)}%'),
                  value: e.value,
                  color: _tipoPdfColors[e.key] ?? _tipoPdfColors['otro']!,
                  legendStyle: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey800),
                ),
            ],
          ),
        );

  final hhMesRows = [
    for (var m = 1; m <= 12; m++)
      if ((data.hhPorMes[m] ?? 0) > 0)
        [_mesesEs[m - 1], (data.hhPorMes[m]!).toStringAsFixed(1)],
  ];

  return [
    // 1. Cultivos con alertas — primero, por solicitud.
    _tituloSec('1. Cultivos con alertas'),
    _tablaSec(const ['Cultivo', 'Estado', 'Detalle'], data.alertas),
    _tituloSec('2. Próximos eventos'),
    _tablaSec(const ['Actividad', 'Cultivo'], data.proximosEventos),
    _tituloSec('3. Compras del año fiscal ${data.anio} — '
        'total \$ ${data.comprasTotal.toStringAsFixed(0)}'),
    if (pie != null) pie,
    pw.SizedBox(height: 6),
    _tablaSec(
        const ['Fecha', 'Descripción', 'Tipo', 'Proveedor', 'Cant.',
          'Und.', 'Valor'],
        data.comprasRows),
    _tituloSec('4. Horas-hombre por mes (año fiscal ${data.anio})'),
    _tablaSec(const ['Mes', 'HH'], hhMesRows),
    _tituloSec('5. Distribución de HH por cultivo'),
    _tablaSec(const ['Cultivo', 'HH', '% del total'], data.hhPorCultivo),
    _tituloSec('6. Distribución de HH por usuario'),
    _tablaSec(const ['Usuario', 'HH', '% del total'], data.hhPorUsuario),
  ];
}

Future<File> exportDashboardPdf({
  required ReportPredio predio,
  required String sistemaUnidades,
  required DashboardReportData data,
}) async {
  final doc = pw.Document();
  final logos = await _cargarLogos();

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    header: (ctx) => _pdfHeader(predio, sistemaUnidades, logos),
    footer: (ctx) => _pdfFooter(ctx, logos),
    build: (ctx) => [
      pw.SizedBox(height: 8),
      pw.Text(_txt('Reporte integral del predio — año fiscal ${data.anio}'),
          style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900)),
      ..._cuerpoDashboard(data),
    ],
  ));

  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path,
      'nexus_dashboard_${DateTime.now().millisecondsSinceEpoch}.pdf'));
  await file.writeAsBytes(await doc.save());
  return file;
}

/// Sección extra del reporte consolidado.
class SeccionReporte {
  const SeccionReporte({
    required this.titulo,
    required this.columns,
    required this.rows,
  });
  final String titulo;
  final List<String> columns;
  final List<List<String>> rows;
}

/// Reporte consolidado (pantalla Reportes, 2026-07-20): el reporte
/// integral del Dashboard seguido de las tablas completas de cultivos,
/// inventario, compras y proveedores.
Future<File> exportConsolidadoPdf({
  required ReportPredio predio,
  required String sistemaUnidades,
  required DashboardReportData dashboard,
  required List<SeccionReporte> secciones,
}) async {
  final doc = pw.Document();
  final logos = await _cargarLogos();

  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.symmetric(horizontal: 24, vertical: 32),
    header: (ctx) => _pdfHeader(predio, sistemaUnidades, logos),
    footer: (ctx) => _pdfFooter(ctx, logos),
    build: (ctx) => [
      pw.SizedBox(height: 8),
      pw.Text(_txt('Reporte consolidado — año fiscal ${dashboard.anio}'),
          style: pw.TextStyle(
              fontSize: 14,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.green900)),
      ..._cuerpoDashboard(dashboard),
      for (var i = 0; i < secciones.length; i++) ...[
        _tituloSec('${7 + i}. ${secciones[i].titulo}'),
        _tablaSec(secciones[i].columns, secciones[i].rows),
      ],
    ],
  ));

  final dir = await getApplicationDocumentsDirectory();
  final file = File(p.join(dir.path,
      'nexus_consolidado_${DateTime.now().millisecondsSinceEpoch}.pdf'));
  await file.writeAsBytes(await doc.save());
  return file;
}

/// Conjunto de logos de un PDF (ajuste 2026-07-20):
///  - [header]: logo personalizado (o ícono de la app como respaldo) —
///    va en el ENCABEZADO, lado derecho, en lugar de la inicial.
///  - [appIcon] + [ncLogo]: van JUNTOS en el CENTRO del pie de página.
class _PdfLogos {
  const _PdfLogos({this.header, this.appIcon, this.ncLogo});
  final pw.MemoryImage? header;
  final pw.MemoryImage? appIcon;
  final pw.MemoryImage? ncLogo;
}

Future<_PdfLogos> _cargarLogos() async {
  pw.MemoryImage? header;
  pw.MemoryImage? appIcon;
  pw.MemoryImage? ncLogo;
  try {
    final custom = await logoPersonalizadoFile();
    if (await custom.exists()) {
      header = pw.MemoryImage(await custom.readAsBytes());
    }
  } catch (_) {
    // Sin acceso al FS (p. ej. tests): sin logo personalizado.
  }
  try {
    final data = await rootBundle.load('assets/images/ic_launcher.png');
    appIcon = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    // Asset ausente: el pie mostrará solo nc_logo.
  }
  try {
    final data = await rootBundle.load('assets/images/nc_logo.jpg');
    ncLogo = pw.MemoryImage(data.buffer.asUint8List());
  } catch (_) {
    // Asset ausente: el pie mostrará solo el ícono.
  }
  // Sin logo personalizado: el ícono de la app preside el encabezado.
  header ??= appIcon;
  return _PdfLogos(header: header, appIcon: appIcon, ncLogo: ncLogo);
}

pw.Widget _pdfHeader(
        ReportPredio predio, String sistemaUnidades, _PdfLogos logos) =>
    pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            bottom: pw.BorderSide(color: PdfColors.green800, width: 1.5)),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(_txt(predio.nombre),
                  style: pw.TextStyle(
                      fontSize: 16,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.green800)),
              if (predio.localizacion.isNotEmpty)
                pw.Text(_txt(predio.localizacion),
                    style: const pw.TextStyle(
                        fontSize: 10, color: PdfColors.grey700)),
              if (predio.propietario != null)
                pw.Text(_txt('Propietario: ${predio.propietario}'),
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700)),
              pw.SizedBox(height: 2),
              pw.Text('Sistema de unidades: ${nombreSistema(sistemaUnidades)}',
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontStyle: pw.FontStyle.italic,
                      color: PdfColors.grey800)),
              pw.Text(
                  'Generado: ${DateTime.now().toString().substring(0, 19)}',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.grey600)),
            ],
          ),
          // Lado derecho: logo personalizado (o ícono de la app). Solo si
          // no hay ninguno disponible, cae a la inicial en círculo.
          if (logos.header != null)
            pw.Container(
              height: 48,
              constraints: const pw.BoxConstraints(maxWidth: 140),
              child: pw.Image(logos.header!, fit: pw.BoxFit.contain),
            )
          else
            pw.Container(
              width: 48,
              height: 48,
              decoration: pw.BoxDecoration(
                color: PdfColors.green800,
                shape: pw.BoxShape.circle,
              ),
              alignment: pw.Alignment.center,
              child: pw.Text(predio.nombre.substring(0, 1).toUpperCase(),
                  style: pw.TextStyle(
                      fontSize: 20,
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold)),
            ),
        ],
      ),
    );

pw.Widget _pdfFooter(pw.Context ctx, _PdfLogos logos) => pw.Container(
      padding: const pw.EdgeInsets.only(top: 6),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
            top: pw.BorderSide(color: PdfColors.grey400, width: 0.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('NEXUS Siembras - NEXUS CREATIO',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          // Centro: ícono de la app + logo NEXUS, uno al lado del otro.
          pw.Row(mainAxisSize: pw.MainAxisSize.min, children: [
            if (logos.appIcon != null)
              pw.Image(logos.appIcon!, height: 20, fit: pw.BoxFit.contain),
            if (logos.appIcon != null && logos.ncLogo != null)
              pw.SizedBox(width: 8),
            if (logos.ncLogo != null)
              pw.Image(logos.ncLogo!, height: 20, fit: pw.BoxFit.contain),
            if (logos.appIcon == null && logos.ncLogo == null)
              pw.Text('NC', style: const pw.TextStyle(fontSize: 9)),
          ]),
          pw.Text('Página ${ctx.pageNumber} / ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
        ],
      ),
    );

/// Archivo del logo personalizado del encabezado (pantalla Reportes).
Future<File> logoPersonalizadoFile() async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, 'branding', 'logo_personalizado.png'));
}

/// Preview del PDF (usa el diálogo nativo del OS gracias a `printing`).
Future<void> previewPdf(File pdf) async {
  await Printing.layoutPdf(onLayout: (_) async => pdf.readAsBytes());
}
