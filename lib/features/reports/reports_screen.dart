// NEXUS Siembras — Pantalla Reportes (Fase B8+, 2026-07-20).
//
// Central de reportes de la app:
//   1. Generar cada reporte (Dashboard integral, Cultivos, Inventario,
//      Compras, Proveedores) en PDF o CSV, más un CONSOLIDADO que une
//      todos en un solo PDF.
//   2. Logo personalizado para el encabezado/pie de los PDF.
//   3. Listado de reportes generados con Ver / Compartir / Eliminar.
//   4. Logs de diagnóstico de la sesión: ver, compartir y "Limpiar
//      caché y logs".
//
// Los archivos se generan en el directorio Documentos de la app con el
// prefijo `nexus_` — el listado escanea ese patrón.

import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/log.dart';
import '../../core/reports/adjunto_viewer.dart';
import '../../core/reports/report_data_builder.dart';
import '../../core/reports/report_service.dart';
import '../../core/widgets/app_shell.dart';
import '../../state/app_state.dart';
import '../../state/data_state.dart';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  bool _generando = false;
  List<FileSystemEntity> _archivos = const [];
  bool _logoExiste = false;

  @override
  void initState() {
    super.initState();
    _refrescar();
  }

  Future<void> _refrescar() async {
    final dir = await getApplicationDocumentsDirectory();
    final regex = RegExp(r'^nexus_.*\.(pdf|csv)$');
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => regex.hasMatch(p.basename(f.path)))
        .toList()
      ..sort((a, b) =>
          b.statSync().modified.compareTo(a.statSync().modified));
    final logo = await logoPersonalizadoFile();
    final logoOk = await logo.exists();
    if (!mounted) return;
    setState(() {
      _archivos = files;
      _logoExiste = logoOk;
    });
  }

  // ================================================================
  // Generación
  // ================================================================
  Future<void> _generar(String tipo, String fmt) async {
    if (_generando) return;
    setState(() => _generando = true);
    try {
      final predio = await ref.read(reportPredioProvider.future);
      final sistema = ref.read(unitSystemProvider);
      File file;
      switch (tipo) {
        case 'dashboard':
          final data = await buildDashboardData(ref);
          file = fmt == 'pdf'
              ? await exportDashboardPdf(
                  predio: predio, sistemaUnidades: sistema, data: data)
              : await exportCsv(
                  scope: 'dashboard',
                  predio: predio,
                  sistemaUnidades: sistema,
                  columns: const [],
                  rows: dashboardCsvBlocks(data));
        case 'consolidado':
          final data = await buildDashboardData(ref);
          final cultivos = await buildCultivosReporte(ref);
          final inventario = buildInventarioReporte(ref);
          final compras = buildComprasReporte(ref);
          final proveedores = await buildProveedoresReporte(ref);
          file = await exportConsolidadoPdf(
            predio: predio,
            sistemaUnidades: sistema,
            dashboard: data,
            secciones: [
              for (final t in [cultivos, inventario, compras, proveedores])
                SeccionReporte(
                    titulo: t.titulo, columns: t.columns, rows: t.rows),
            ],
          );
        default:
          final TablaReporte t = switch (tipo) {
            'cultivos' => await buildCultivosReporte(ref),
            'inventario' => buildInventarioReporte(ref),
            'compras' => buildComprasReporte(ref),
            _ => await buildProveedoresReporte(ref),
          };
          file = fmt == 'pdf'
              ? await exportPdf(
                  scope: t.scope,
                  scopeTitle: t.titulo,
                  predio: predio,
                  sistemaUnidades: sistema,
                  columns: t.columns,
                  rows: t.rows)
              : await exportCsv(
                  scope: t.scope,
                  predio: predio,
                  sistemaUnidades: sistema,
                  columns: t.columns,
                  rows: t.rows);
      }
      await _refrescar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Generado: ${p.basename(file.path)}')));
    } catch (e) {
      Log.e('[reportes] generación $tipo/$fmt falló', e);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error generando: $e')));
      }
    } finally {
      if (mounted) setState(() => _generando = false);
    }
  }

  // ================================================================
  // Logo personalizado
  // ================================================================
  Future<void> _cambiarLogo() async {
    final res = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
      dialogTitle: 'Seleccionar logotipo',
    );
    final path = res?.files.single.path;
    if (path == null) return;
    try {
      final destino = await logoPersonalizadoFile();
      await destino.parent.create(recursive: true);
      await File(path).copy(destino.path);
      await _refrescar();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Logotipo actualizado — aparecerá en los '
              'próximos PDF generados')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _quitarLogo() async {
    final f = await logoPersonalizadoFile();
    if (await f.exists()) await f.delete();
    await _refrescar();
  }

  // ================================================================
  // Logs y caché
  // ================================================================
  Future<void> _compartirLogs() async {
    try {
      final dir = await getTemporaryDirectory();
      final f = File(p.join(dir.path,
          'nexus_logs_${DateTime.now().millisecondsSinceEpoch}.txt'));
      await f.writeAsString(Log.volcado().isEmpty
          ? '(sin entradas en esta sesión)'
          : Log.volcado());
      if (!mounted) return;
      await compartirArchivo(context, f.path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _limpiarCacheYLogs() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Limpiar caché y logs'),
        content: const Text(
            'Se borrarán los archivos temporales de la app y los logs de '
            'diagnóstico de esta sesión. Tus datos, reportes y adjuntos '
            'NO se tocan.\n\n¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Limpiar')),
        ],
      ),
    );
    if (ok != true) return;
    var borrados = 0;
    try {
      final tmp = await getTemporaryDirectory();
      for (final e in tmp.listSync()) {
        try {
          if (e is File) {
            e.deleteSync();
            borrados++;
          } else if (e is Directory) {
            e.deleteSync(recursive: true);
            borrados++;
          }
        } catch (_) {
          // Archivo en uso por el SO: se omite sin fallar la limpieza.
        }
      }
    } catch (e) {
      Log.w('[reportes] limpieza de caché parcial: $e');
    }
    Log.limpiar();
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            'Caché limpiada ($borrados elemento(s)) y logs reiniciados')));
  }

  // ================================================================
  // UI
  // ================================================================
  @override
  Widget build(BuildContext context) {
    // Mantener vivos los streams que alimentan los builders.
    ref.watch(comprasProvider);
    ref.watch(inventoryProvider);
    ref.watch(cultivosActivosProvider);
    ref.watch(plantasProvider);
    ref.watch(proveedoresDriftProvider);

    return AppShell(
      title: 'Reportes',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _cardGenerar(),
          const SizedBox(height: 12),
          _cardLogo(),
          const SizedBox(height: 12),
          _cardGenerados(),
          const SizedBox(height: 12),
          _cardLogs(),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _cardGenerar() {
    Widget fila(String tipo, IconData icono, String nombre,
        {bool soloPdf = false}) {
      return ListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icono, color: Colors.green.shade800),
        title: Text(nombre, style: const TextStyle(fontSize: 14)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          OutlinedButton(
            onPressed: _generando ? null : () => _generar(tipo, 'pdf'),
            child: const Text('PDF'),
          ),
          if (!soloPdf) ...[
            const SizedBox(width: 6),
            OutlinedButton(
              onPressed: _generando ? null : () => _generar(tipo, 'csv'),
              child: const Text('CSV'),
            ),
          ],
        ]),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.description, color: Colors.green),
              const SizedBox(width: 6),
              Text('Generar reportes',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (_generando)
                const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
            ]),
            const SizedBox(height: 4),
            Text(
                'Con encabezado del predio activo y el sistema de unidades '
                'configurado. Quedan en el listado de abajo.',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            const SizedBox(height: 6),
            fila('dashboard', Icons.dashboard_outlined,
                'Integral del Dashboard (alertas, eventos, compras, HH)'),
            fila('cultivos', Icons.eco_outlined,
                'Cultivos y patologías activas'),
            fila('inventario', Icons.inventory_2_outlined, 'Inventario'),
            fila('compras', Icons.receipt_long_outlined, 'Compras'),
            fila('proveedores', Icons.storefront_outlined, 'Proveedores'),
            const Divider(),
            fila('consolidado', Icons.auto_stories_outlined,
                'CONSOLIDADO — todos los anteriores en un PDF',
                soloPdf: true),
          ],
        ),
      ),
    );
  }

  Widget _cardLogo() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.image_outlined, color: Colors.green),
              const SizedBox(width: 6),
              Text('Logotipo del encabezado',
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text(
                'Imagen (PNG/JPG) que aparece en el pie de los reportes '
                'PDF en lugar del logo por defecto.',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            const SizedBox(height: 10),
            Row(children: [
              if (_logoExiste)
                FutureBuilder<File>(
                  future: logoPersonalizadoFile(),
                  builder: (_, snap) => snap.hasData
                      ? Container(
                          height: 48,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                              border:
                                  Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(6)),
                          child: Image.file(snap.data!,
                              key: ValueKey(DateTime.now()
                                  .millisecondsSinceEpoch),
                              fit: BoxFit.contain),
                        )
                      : const SizedBox.shrink(),
                )
              else
                Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Image.asset('assets/images/ic_launcher.png',
                        height: 36,
                        errorBuilder: (_, __, ___) =>
                            const SizedBox.shrink()),
                  ),
                  const SizedBox(width: 8),
                  Text('Sin logo personalizado\n(se usa el ícono de la app)',
                      style: TextStyle(
                          fontSize: 11,
                          fontStyle: FontStyle.italic,
                          color: Theme.of(context).hintColor)),
                ]),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _cambiarLogo,
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: Text(_logoExiste ? 'Cambiar' : 'Cargar logo'),
              ),
              if (_logoExiste)
                IconButton(
                  tooltip: 'Quitar logo personalizado',
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: _quitarLogo,
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _cardGenerados() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.folder_open, color: Colors.green),
              const SizedBox(width: 6),
              Text('Reportes generados (${_archivos.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                  tooltip: 'Refrescar',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: _refrescar),
            ]),
            if (_archivos.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Aún no hay reportes generados.',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).hintColor)),
              )
            else
              ..._archivos.map((f) {
                final nombre = p.basename(f.path);
                final esPdf = nombre.endsWith('.pdf');
                final stat = f.statSync();
                final fecha =
                    stat.modified.toString().substring(0, 16);
                final kb = (stat.size / 1024).toStringAsFixed(0);
                return ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                      esPdf
                          ? Icons.picture_as_pdf_outlined
                          : Icons.table_chart_outlined,
                      color: esPdf ? Colors.red.shade700 : Colors.teal),
                  title: Text(nombre,
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis),
                  subtitle: Text('$fecha · $kb KB',
                      style: const TextStyle(fontSize: 10)),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                        tooltip: 'Ver',
                        icon: const Icon(Icons.visibility_outlined,
                            size: 20),
                        onPressed: () => abrirAdjunto(context, f.path)),
                    IconButton(
                        tooltip: 'Compartir',
                        icon: const Icon(Icons.share, size: 18),
                        onPressed: () =>
                            compartirArchivo(context, f.path)),
                    IconButton(
                        tooltip: 'Eliminar',
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _eliminarArchivo(f.path)),
                  ]),
                );
              }),
          ],
        ),
      ),
    );
  }

  Future<void> _eliminarArchivo(String path) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar reporte'),
        content: Text('¿Eliminar ${p.basename(path)}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await File(path).delete();
    } catch (e) {
      Log.w('[reportes] no se pudo eliminar $path: $e');
    }
    await _refrescar();
  }

  Widget _cardLogs() {
    final lineas = Log.lineas;
    final preview = lineas.length <= 12
        ? lineas
        : lineas.sublist(lineas.length - 12);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.terminal, color: Colors.blueGrey),
              const SizedBox(width: 6),
              Text('Logs de diagnóstico',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                  tooltip: 'Refrescar',
                  icon: const Icon(Icons.refresh, size: 20),
                  onPressed: () => setState(() {})),
            ]),
            Text(
                '${lineas.length} entrada(s) en esta sesión. Útiles para '
                'diagnosticar problemas de sincronización o conexión.',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 180),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF263238),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  preview.isEmpty
                      ? '(sin entradas todavía)'
                      : preview.join('\n'),
                  style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      color: Color(0xFFB2DFDB)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              OutlinedButton.icon(
                onPressed: lineas.isEmpty ? null : _verLogsCompletos,
                icon: const Icon(Icons.open_in_full, size: 16),
                label: const Text('Ver todo'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _compartirLogs,
                icon: const Icon(Icons.share, size: 16),
                label: const Text('Compartir'),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _limpiarCacheYLogs,
                style:
                    TextButton.styleFrom(foregroundColor: Colors.red),
                icon: const Icon(Icons.cleaning_services_outlined,
                    size: 16),
                label: const Text('Limpiar caché y logs'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _verLogsCompletos() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Logs de la sesión (${Log.lineas.length})'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: SelectableText(Log.volcado(),
                style: const TextStyle(
                    fontFamily: 'monospace', fontSize: 10)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _compartirLogs();
              },
              child: const Text('Compartir')),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }
}
