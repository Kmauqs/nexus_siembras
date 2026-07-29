import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'dart:math' as math;
import '../../core/reports/report_data_builder.dart';
import '../../core/reports/report_service.dart';
import '../../core/theme/themes.dart';
import '../../core/units/units_catalog.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/repositories/cultivo_repository.dart';
import '../../state/app_state.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final compras = ref.watch(comprasProvider);
    final inv = ref.watch(inventoryProvider);
    final activos = ref.watch(cultivosActivosProvider);
    final hhMap = <int, double>{for (final c in activos) c.id: c.hh};
    // Consultor: solo lectura → oculta el FAB "+" que abre el menú de
    // crear (nuevo cultivo, nuevo insumo, nueva compra, etc.). Se
    // conserva el FAB de mapa: navegar/consultar es lectura.
    final permisos = ref.watch(permisosPredioActivoProvider);
    final puedeCrearAlgo = permisos.puedeEditarCultivosYTareas ||
        permisos.puedeEditarInventario ||
        permisos.puedeEditarCompras ||
        permisos.puedeEditarPredioYLotes ||
        permisos.puedeEditarSueloYCondiciones;
    // Oferta del Asistente paso a paso tras completar el onboarding
    // (2026-07-20). La bandera es efímera: se apaga antes de mostrar el
    // diálogo para no re-disparar en rebuilds.
    if (ref.watch(ofrecerWizardProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref.read(ofrecerWizardProvider.notifier).state = false;
        showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Asistente paso a paso'),
            content: const Text(
                '¿Quieres que te guiemos en la configuración inicial? '
                'Predio, lotes, proveedores, inventario y tu primer '
                'cultivo, en 10 pasos.\n\n'
                'También está disponible cuando quieras desde el menú o '
                'el botón ✨ de la barra superior.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Ahora no')),
              FilledButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    context.go('/wizard');
                  },
                  child: const Text('Iniciar asistente')),
            ],
          ),
        );
      });
    }
    return AppShell(
      title: 'Dashboard',
      bottomBar: const _PredioActivoSelector(),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'fabMap',
            backgroundColor: theme.colorScheme.surface,
            foregroundColor: theme.colorScheme.primary,
            onPressed: () => context.go('/map'),
            child: const Icon(Icons.map),
          ),
          if (puedeCrearAlgo) const SizedBox(height: 12),
          if (puedeCrearAlgo)
            FloatingActionButton(
              heroTag: 'fabAdd',
              onPressed: () => context.go('/add'),
              child: const Icon(Icons.add),
            ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _KpiGrid(invItems: inv.length, activos: activos.length),
          const SizedBox(height: 12),
          _AlertsCard(),
          const SizedBox(height: 12),
          _NextEventsCard(),
          if (permisos.puedeVerCompras) ...[
            const SizedBox(height: 12),
            _ComprasCard(compras: compras),
          ],
          const SizedBox(height: 12),
          _HHCard(hhMap: hhMap),
          const SizedBox(height: 20),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _exportDashboard(context, ref, 'csv'),
                icon: const Icon(Icons.file_download, size: 18),
                label: const Text('Exportar CSV'),
              ),
              OutlinedButton.icon(
                onPressed: () => _exportDashboard(context, ref, 'pdf'),
                icon: const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('Exportar PDF'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Center(
            child: Text('Reporte integral: alertas, eventos, compras, HH',
                style: theme.textTheme.bodySmall),
          ),
          const SizedBox(height: 80), // margen para FAB
        ],
      ),
    );
  }

  /// Reporte integral del Dashboard (2026-07-20). Secciones en orden:
  /// alertas de cultivos y próximos eventos primero, luego compras del año
  /// fiscal (con gráfico circular en PDF), HH por mes, distribución por
  /// cultivo y por usuario. Usa los datos REALES del predio activo.
  static Future<void> _exportDashboard(
      BuildContext ctx, WidgetRef ref, String fmt) async {
    try {
      final sistema = ref.read(unitSystemProvider);
      final predio = await ref.read(reportPredioProvider.future);
      // Recolección centralizada (2026-07-20): misma fuente que la
      // pantalla Reportes y el consolidado.
      final data = await buildDashboardData(ref);

      if (fmt == 'csv') {
        // CSV con las mismas secciones en bloques (builder compartido).
        final all = dashboardCsvBlocks(data);
        final file = await exportCsv(
          scope: 'dashboard',
          predio: predio,
          sistemaUnidades: sistema,
          columns: const [], // cabeceras dentro de cada bloque
          rows: all,
        );
        if (!ctx.mounted) return;
        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text('CSV generado: ${file.path}'),
          duration: const Duration(seconds: 6),
        ));
      } else {
        final file = await exportDashboardPdf(
          predio: predio,
          sistemaUnidades: sistema,
          data: data,
        );
        if (!ctx.mounted) return;
        await previewPdf(file);
      }
    } catch (e) {
      if (!ctx.mounted) return;
      ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('Error exportando: $e')));
    }
  }
}

class _KpiGrid extends ConsumerWidget {
  const _KpiGrid({required this.invItems, required this.activos});
  final int invItems, activos;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Alertas: cuenta cultivos con estado != verde (evalúa cada uno)
    final cultivos = ref.watch(cultivosActivosProvider);
    int alertas = 0;
    for (final c in cultivos) {
      final asyncEst = ref.watch(estadoCultivoProvider(c.id));
      if (asyncEst.hasValue && asyncEst.value!.estado != EstadoCultivo.verde) {
        alertas++;
      }
    }
    // Cosechas próximas: aproximación provisional (Fase 2i tendrá cálculo exacto)
    final proximasCosechas = (cultivos.length * 0.3).ceil();
    final tiles = [
      _KpiTile(label: 'Cultivos activos', value: '$activos',
          color: Colors.green, route: '/crops'),
      _KpiTile(label: 'Alertas', value: '$alertas',
          color: alertas > 0 ? Colors.orange : Colors.grey, route: '/crops'),
      _KpiTile(label: 'Próximas cosechas', value: '$proximasCosechas',
          color: Colors.blue, route: '/schedule'),
      _KpiTile(label: 'Ítems inventario', value: '$invItems',
          color: Colors.brown, route: '/inventory'),
    ];
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.0,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      children: tiles,
    );
  }
}

class _KpiTile extends StatelessWidget {
  const _KpiTile({required this.label, required this.value, required this.color, this.route});
  final String label;
  final String value;
  final Color color;
  final String? route;

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
              overflow: TextOverflow.ellipsis, maxLines: 1),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
    return Card(
      clipBehavior: Clip.antiAlias,
      child: route == null
          ? content
          : InkWell(onTap: () => context.go(route!), child: content),
    );
  }
}

class _AlertsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cultivos = ref.watch(cultivosActivosProvider);
    final plantas = ref.watch(plantasProvider);
    final plantasById = {for (final p in plantas) p.id: p};
    final alertas = <_AlertData>[];
    for (final c in cultivos) {
      final asyncEst = ref.watch(estadoCultivoProvider(c.id));
      if (asyncEst.hasValue && asyncEst.value!.estado != EstadoCultivo.verde) {
        final info = asyncEst.value!;
        final pl = plantasById[c.plantaId];
        alertas.add(_AlertData(
          color: info.estado == EstadoCultivo.rojo
              ? AppThemes.colorAlert : AppThemes.colorWarn,
          name: '${pl?.nombre ?? "?"} · ${c.lote}',
          note: info.nota,
        ));
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Alertas próximas', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (alertas.isEmpty)
              Text('Sin alertas activas ✅',
                  style: TextStyle(color: Theme.of(context).hintColor))
            else
              ...alertas.map((a) => _AlertLine(color: a.color, name: a.name, note: a.note)),
          ],
        ),
      ),
    );
  }
}

class _AlertData {
  const _AlertData({required this.color, required this.name, required this.note});
  final Color color;
  final String name;
  final String note;
}

class _AlertLine extends StatelessWidget {
  const _AlertLine({required this.color, required this.name, required this.note});
  final Color color;
  final String name;
  final String note;
  @override
  Widget build(BuildContext context) => InkWell(
        onTap: () => context.go('/crops'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Container(width: 12, height: 12,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(note, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.grey),
          ]),
        ),
      );
}

class _NextEventsCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Fase 2i: leer directamente eventos_cultivo, ordenados por fecha_programada ascendente.
    // Por ahora derivamos de las alertas (los estados naranja/rojo tienen la nota con la próxima actividad).
    final cultivos = ref.watch(cultivosActivosProvider);
    final plantas = ref.watch(plantasProvider);
    final plantasById = {for (final p in plantas) p.id: p};
    final eventos = <(_AlertData, DateTime)>[];
    for (final c in cultivos) {
      final asyncEst = ref.watch(estadoCultivoProvider(c.id));
      if (asyncEst.hasValue) {
        final info = asyncEst.value!;
        if (info.estado != EstadoCultivo.verde) {
          final pl = plantasById[c.plantaId];
          eventos.add((
            _AlertData(
              color: Colors.grey,
              name: info.nota,
              note: '${pl?.nombre ?? "?"} · ${c.lote}',
            ),
            DateTime.now(),
          ));
        }
      }
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Próximos eventos', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (eventos.isEmpty)
              Text('Sin eventos próximos',
                  style: TextStyle(color: Theme.of(context).hintColor))
            else
              ...eventos.take(4).map((e) => _EventLine(
                    desc: e.$1.name,
                    context: e.$1.note,
                    date: 'próximo',
                  )),
          ],
        ),
      ),
    );
  }
}

class _EventLine extends StatelessWidget {
  const _EventLine({required this.desc, required this.context, required this.date});
  final String desc, context, date;
  @override
  Widget build(BuildContext ctx) => InkWell(
        onTap: () => ctx.go('/schedule'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(desc, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text(context, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            Text(date, style: const TextStyle(color: Colors.grey)),
          ]),
        ),
      );
}

// ============ Compras del año fiscal ============
class _ComprasCard extends StatelessWidget {
  const _ComprasCard({required this.compras});
  final List<Compra> compras;

  static const _tipoColors = <String, Color>{
    'semilla':     Color(0xFF1B7A3E),
    'abono':       Color(0xFF8B6F47),
    'pesticida':   Color(0xFFB91C1C),
    'herramienta': Color(0xFF2563EB),
    'servicio':    Color(0xFF7C3AED),
    'otro':        Color(0xFF6B7280),
  };
  static const _tipoLabels = <String, String>{
    'semilla':'Semilla', 'abono':'Abono', 'pesticida':'Pesticida',
    'herramienta':'Herramienta', 'servicio':'Servicio', 'otro':'Otro',
  };

  @override
  Widget build(BuildContext context) {
    final anio = DateTime.now().year;
    final delAnio = compras.where((c) => c.fecha.startsWith('$anio')).toList();
    final total = delAnio.fold<double>(0, (s, c) => s + c.valor);
    final grupos = <String, double>{};
    for (final c in delAnio) {
      final t = c.tipo.isEmpty ? 'otro' : c.tipo;
      grupos[t] = (grupos[t] ?? 0) + c.valor;
    }
    final entries = grupos.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('💰 Compras año fiscal $anio',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (delAnio.isEmpty)
              const Text('Sin compras registradas para el año fiscal en curso.',
                  style: TextStyle(color: Colors.grey))
            else ...[
              Center(
                child: Column(
                  children: [
                    Text('\$ ${_fmt(total)}',
                        style: const TextStyle(fontSize: 22,
                            fontWeight: FontWeight.bold, color: Color(0xFF0F5132))),
                    Text('${delAnio.length} compra(s) registrada(s)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  SizedBox(width: 140, height: 140,
                    child: CustomPaint(painter: _DonutPainter(entries: entries,
                        colors: _tipoColors, total: total))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      children: entries.map((e) {
                        final pct = (e.value / total * 100).toStringAsFixed(1);
                        final color = _tipoColors[e.key] ?? _tipoColors['otro']!;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            Container(width: 12, height: 12,
                                decoration: BoxDecoration(color: color,
                                    borderRadius: BorderRadius.circular(3))),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(_tipoLabels[e.key] ?? e.key,
                                  style: const TextStyle(fontSize: 12)),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('$pct%',
                                    style: const TextStyle(fontSize: 12,
                                        fontWeight: FontWeight.bold)),
                                Text('\$ ${_fmt(e.value)}',
                                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ],
                            ),
                          ]),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _fmt(double v) {
    final s = v.toStringAsFixed(0);
    return s.replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]}.');
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.entries, required this.colors, required this.total});
  final List<MapEntry<String, double>> entries;
  final Map<String, Color> colors;
  final double total;

  @override
  void paint(Canvas c, Size s) {
    final cx = s.width / 2, cy = s.height / 2;
    final r = s.width * 0.45, ri = r * 0.55;
    var start = -math.pi / 2;
    for (final e in entries) {
      final sweep = (e.value / total) * math.pi * 2;
      final paint = Paint()..color = colors[e.key] ?? colors['otro']!;
      final path = Path()
        ..moveTo(cx + r * math.cos(start), cy + r * math.sin(start))
        ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: r), start, sweep, false)
        ..lineTo(cx + ri * math.cos(start + sweep), cy + ri * math.sin(start + sweep))
        ..arcTo(Rect.fromCircle(center: Offset(cx, cy), radius: ri),
            start + sweep, -sweep, false)
        ..close();
      c.drawPath(path, paint);
      c.drawPath(path, Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 1);
      start += sweep;
    }
    final tp = TextPainter(
      text: TextSpan(
        text: total >= 1000000
            ? '${(total / 1000000).toStringAsFixed(1)}M'
            : total >= 1000
                ? '${(total / 1000).round()}K'
                : total.toStringAsFixed(0),
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(cx - tp.width / 2, cy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _) => true;
}

// ============ Horas hombre ============
class _HHCard extends ConsumerWidget {
  const _HHCard({required this.hhMap});
  final Map<int, double> hhMap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final anio = DateTime.now().year;
    final perMonth = ref.watch(hhPorMesProvider);
    final total = hhMap.values.fold<double>(0, (s, v) => s + v);
    const mesesShort = ['Ene','Feb','Mar','Abr','May','Jun','Jul','Ago','Sep','Oct','Nov','Dic'];
    final currentMonth = DateTime.now().month;
    final maxHH = hhMap.values.fold<double>(0, (m, v) => v > m ? v : m);
    final cultivos = ref.watch(cultivosActivosProvider);
    final plantas = ref.watch(plantasProvider);
    final plantasById = {for (final p in plantas) p.id: p};
    // Colores rotativos según estado — sin estado cargado, verde por defecto
    Color colorFor(int cultId) {
      final asyncEst = ref.watch(estadoCultivoProvider(cultId));
      if (asyncEst.hasValue) {
        switch (asyncEst.value!.estado) {
          case EstadoCultivo.verde:   return AppThemes.colorOk;
          case EstadoCultivo.naranja: return AppThemes.colorWarn;
          case EstadoCultivo.rojo:    return AppThemes.colorAlert;
        }
      }
      return AppThemes.colorOk;
    }
    final cultivosById = {for (final c in cultivos) c.id: c};

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('⏱️ Horas hombre año fiscal $anio',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Center(
              child: Column(
                children: [
                  Text('${total.toStringAsFixed(0)} h',
                      style: const TextStyle(fontSize: 22,
                          fontWeight: FontWeight.bold, color: Color(0xFF0F5132))),
                  const Text('HH totales',
                      style: TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text('📅 Por mes', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            // Grilla 3 columnas × 4 filas (Ene–Abr | May–Ago | Sep–Dic)
            for (int row = 0; row < 4; row++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    for (int col = 0; col < 3; col++) ...[
                      Expanded(child: _mesCell(mesesShort[row + col * 4],
                          perMonth[row + col * 4 + 1] ?? 0,
                          row + col * 4 + 1 == currentMonth)),
                      if (col < 2) const SizedBox(width: 6),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total año',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  Text('${total.toStringAsFixed(0)} h',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12,
                          color: Color(0xFF0F5132))),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text('🌱 Distribución por cultivo',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            ...hhMap.entries
                .toList()
                .let((l) {
                  l.sort((a, b) => b.value.compareTo(a.value));
                  return l;
                })
                .map((e) {
              final cul = cultivosById[e.key];
              if (cul == null) return const SizedBox.shrink();
              final pl = plantasById[cul.plantaId];
              final nombre = pl?.nombre ?? '?';
              final lote = cul.lote;
              final color = colorFor(e.key);
              final pctTotal = (e.value / (total == 0 ? 1 : total) * 100).toStringAsFixed(1);
              final pct = (e.value / (maxHH == 0 ? 1 : maxHH)).clamp(0.02, 1.0);
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text('$nombre · $lote',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis),
                      ),
                      Text('${e.value.toStringAsFixed(0)}h ($pctTotal%)',
                          style: const TextStyle(fontSize: 12,
                              fontWeight: FontWeight.bold)),
                    ]),
                    const SizedBox(height: 3),
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: pct.toDouble(),
                        child: Container(
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 14),
            const _HHPorUsuarioSection(),
          ],
        ),
      ),
    );
  }

  Widget _mesCell(String mes, double val, bool isCurrent) {
    final color = isCurrent ? const Color(0xFF0F5132) : null;
    final weight = isCurrent ? FontWeight.bold : FontWeight.normal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: isCurrent ? const Color(0xFF0F5132).withOpacity(0.08) : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(mes,
              style: TextStyle(fontSize: 11, color: color, fontWeight: weight)),
          Text(val > 0 ? val.toStringAsFixed(0) : '—',
              style: TextStyle(
                  fontSize: 11,
                  color: color ?? (val > 0 ? Colors.black : Colors.grey),
                  fontWeight: weight)),
        ],
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// Fase 3g: distribución de HH del año en curso agrupadas por autor
/// (created_by_user_id). Resuelve UUIDs → email vía emailPorUserIdProvider
/// (RPC `email_de_usuario` con caché). Tareas legacy (autor null) se
/// agrupan bajo "— Sin autor —".
class _HHPorUsuarioSection extends ConsumerWidget {
  const _HHPorUsuarioSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final porUsuario = ref.watch(hhPorUsuarioProvider);
    if (porUsuario.isEmpty) return const SizedBox.shrink();
    // Si solo hay un autor y es "" (todo legacy o modo local), no vale la
    // pena mostrar esta sección: ya está reflejado en el total.
    if (porUsuario.length == 1 && porUsuario.containsKey('')) {
      return const SizedBox.shrink();
    }
    final entries = porUsuario.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = porUsuario.values.fold<double>(0, (s, v) => s + v);
    final maxHH =
        porUsuario.values.fold<double>(0, (m, v) => v > m ? v : m);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('👥 Distribución por usuario',
            style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        ...entries.map((e) {
          final horas = e.value;
          final pctTotal =
              (horas / (total == 0 ? 1 : total) * 100).toStringAsFixed(1);
          final pct = (horas / (maxHH == 0 ? 1 : maxHH)).clamp(0.02, 1.0);
          Widget labelWidget;
          if (e.key.isEmpty) {
            labelWidget = const Text('— Sin autor (legacy) —',
                style: TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.grey));
          } else {
            labelWidget = Consumer(builder: (_, ref2, __) {
              final emailAsync = ref2.watch(emailPorUserIdProvider(e.key));
              return emailAsync.when(
                loading: () => Text(_uuidResumido(e.key),
                    style: const TextStyle(fontSize: 12)),
                error: (_, __) => Text(_uuidResumido(e.key),
                    style: const TextStyle(fontSize: 12)),
                data: (email) => Text(email ?? _uuidResumido(e.key),
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              );
            });
          }
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(child: labelWidget),
                  Text('${horas.toStringAsFixed(0)}h ($pctTotal%)',
                      style: const TextStyle(
                          fontSize: 12, fontWeight: FontWeight.bold)),
                ]),
                const SizedBox(height: 3),
                Container(
                  height: 10,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: pct.toDouble(),
                    child: Container(
                      decoration: BoxDecoration(
                        color: e.key.isEmpty
                            ? Colors.grey.shade400
                            : AppThemes.colorOk,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  String _uuidResumido(String uuid) {
    if (uuid.length < 12) return uuid;
    return '${uuid.substring(0, 8)}…';
  }
}

/// Selector de predio activo anclado al pie del Dashboard. Al cambiar
/// escribe en `configs.predioActivoId`, disparando la actualización
/// automática de todos los providers reactivos (cultivos, inventario,
/// compras, lotes, análisis, condiciones, papelera, etc.).
class _PredioActivoSelector extends ConsumerWidget {
  const _PredioActivoSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final activeId = ref.watch(activePredioIdProvider);
    final async = ref.watch(prediosProvider);
    return Material(
      color: theme.colorScheme.surface,
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: async.when(
            loading: () => const SizedBox(
                height: 48,
                child: Center(child: LinearProgressIndicator())),
            error: (e, _) => Text('Error: $e',
                style: const TextStyle(color: Colors.red)),
            data: (list) {
              if (list.isEmpty) {
                return Row(children: [
                  Icon(Icons.landscape, color: theme.hintColor, size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text('Sin predios registrados',
                          style: TextStyle(color: theme.hintColor))),
                  TextButton.icon(
                    onPressed: () async {
                      final logueado = ref.read(isLoggedInProvider);
                      if (!logueado) {
                        context.go('/auth');
                        return;
                      }
                      final messenger = ScaffoldMessenger.of(context);
                      messenger.showSnackBar(const SnackBar(
                          content: Text('Sincronizando…'),
                          duration: Duration(seconds: 2)));
                      try {
                        final res =
                            await ref.read(syncServiceProvider).sincronizar();
                        if (!context.mounted) return;
                        messenger.hideCurrentSnackBar();
                        messenger.showSnackBar(SnackBar(
                            content: Text(res.exito
                                ? 'Sincronización OK (↑${res.pushed} '
                                    '↓${res.pulled}'
                                    '${res.errores > 0 ? ' · ⚠${res.errores} error(es)' : ''})'
                                : 'Error: ${res.error ?? "desconocido"}')));
                      } catch (e) {
                        if (!context.mounted) return;
                        messenger.hideCurrentSnackBar();
                        messenger.showSnackBar(
                            SnackBar(content: Text('Error sync: $e')));
                      }
                    },
                    icon: const Icon(Icons.sync, size: 16),
                    label: const Text('Sync'),
                  ),
                  TextButton.icon(
                    onPressed: () => context.go('/predios'),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Crear'),
                  ),
                ]);
              }
              final validId = list.any((p) => p.id == activeId)
                  ? activeId
                  : list.first.id;
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.landscape,
                      color: theme.colorScheme.primary, size: 20),
                  const SizedBox(width: 8),
                  const Text('Predio activo:',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 10),
                  Flexible(
                    child: DropdownButton<int>(
                      value: validId,
                      isDense: true,
                      underline: const SizedBox.shrink(),
                      items: list
                          .map((p) => DropdownMenuItem<int>(
                                value: p.id,
                                child: Text(p.nombre,
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (v) async {
                        if (v == null || v == activeId) return;
                        await ref
                            .read(dataMutationsProvider)
                            .setPredioActivo(v);
                        if (context.mounted) {
                          final p = list.firstWhere((x) => x.id == v);
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text('Predio activo: ${p.nombre}'),
                              duration: const Duration(seconds: 2)));
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.settings, size: 18),
                    tooltip: 'Administrar predios',
                    onPressed: () => context.go('/predios'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
