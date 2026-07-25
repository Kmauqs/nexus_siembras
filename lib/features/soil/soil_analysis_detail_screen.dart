import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import '../../core/reports/adjunto_viewer.dart';
import '../../core/widgets/app_shell.dart';
import '../../state/data_state.dart';

class SoilAnalysisDetailScreen extends ConsumerWidget {
  const SoilAnalysisDetailScreen({super.key, required this.id});
  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analisisSueloProvider);
    return async.when(
      loading: () => const AppShell(
          title: 'Análisis', child: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          AppShell(title: 'Análisis', child: Center(child: Text('Error: $e'))),
      data: (list) {
        final a = list.where((x) => x.id == id).firstOrNull;
        if (a == null) {
          return AppShell(
            title: 'Análisis',
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.search_off, size: 60, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('Análisis no encontrado'),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => context.go('/soil-analysis'),
                    child: const Text('Volver')),
              ]),
            ),
          );
        }
        return AppShell(
          title: 'Análisis del ${_iso(a.fechaMuestreo)}',
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Encabezado',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const Divider(),
                      _row('Fecha muestreo', _iso(a.fechaMuestreo)),
                      if (a.lote != null) _row('Lote', a.lote!),
                      if (a.laboratorio != null)
                        _row('Laboratorio', a.laboratorio!),
                      if (a.profundidadCm != null)
                        _row('Profundidad', '${a.profundidadCm} cm'),
                      if (a.textura != null) _row('Textura', a.textura!),
                      // B8: adjunto del laboratorio, si existe.
                      if (a.soportePath != null) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () =>
                                  abrirAdjunto(context, a.soportePath!),
                              icon: const Icon(Icons.picture_as_pdf_outlined,
                                  size: 18),
                              label: Text(
                                'Ver ${p.basename(a.soportePath!)}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Compartir',
                            icon: const Icon(Icons.share, size: 18),
                            onPressed: () =>
                                compartirArchivo(context, a.soportePath!),
                          ),
                        ]),
                      ],
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Resultados químicos',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      const Divider(),
                      if (a.ph != null) _row('pH', a.ph!.toStringAsFixed(2)),
                      if (a.materiaOrganicaPct != null)
                        _row('Materia orgánica',
                            '${a.materiaOrganicaPct!.toStringAsFixed(2)} %'),
                      if (a.nPpm != null) _row('Nitrógeno (N)', '${a.nPpm} ppm'),
                      if (a.pPpm != null) _row('Fósforo (P)', '${a.pPpm} ppm'),
                      if (a.kPpm != null) _row('Potasio (K)', '${a.kPpm} ppm'),
                      if (a.caMeq != null)
                        _row('Ca', '${a.caMeq} meq/100g'),
                      if (a.mgMeq != null)
                        _row('Mg', '${a.mgMeq} meq/100g'),
                      if (a.naMeq != null)
                        _row('Na', '${a.naMeq} meq/100g'),
                      if (a.cicMeq != null)
                        _row('CIC', '${a.cicMeq} meq/100g'),
                      if (a.sPpm != null) _row('S', '${a.sPpm} ppm'),
                      if (a.bPpm != null) _row('B', '${a.bPpm} ppm'),
                    ],
                  ),
                ),
              ),
              if (a.densidadGCm3 != null || a.conductividadMsCm != null)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Físicas',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const Divider(),
                        if (a.densidadGCm3 != null)
                          _row('Densidad', '${a.densidadGCm3} g/cm³'),
                        if (a.conductividadMsCm != null)
                          _row('Conductividad',
                              '${a.conductividadMsCm} mS/cm'),
                      ],
                    ),
                  ),
                ),
              if (a.notas != null && a.notas!.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Notas',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const Divider(),
                        Text(a.notas!),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 140,
                child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}

extension _First<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
