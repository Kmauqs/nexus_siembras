import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_shell.dart';
import '../../state/data_state.dart';

class SoilAnalysisListScreen extends ConsumerWidget {
  const SoilAnalysisListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(analisisSueloProvider);
    // Solo el propietario puede registrar/editar análisis de suelo.
    // Trabajador y consultor solo leen la lista.
    final puedeEditar = ref
        .watch(permisosPredioActivoProvider)
        .puedeEditarSueloYCondiciones;
    return AppShell(
      title: 'Análisis de suelo',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (list) => Column(
          children: [
            if (puedeEditar)
              Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton.icon(
                  onPressed: () => context.go('/soil-analysis/add'),
                  icon: const Icon(Icons.add),
                  label: const Text('Nuevo análisis'),
                ),
              ),
            Expanded(
              child: list.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.science_outlined,
                                size: 60, color: Colors.grey),
                            const SizedBox(height: 12),
                            Text('Sin análisis registrados',
                                style: TextStyle(
                                    color: Theme.of(context).hintColor,
                                    fontSize: 16)),
                            const SizedBox(height: 8),
                            const Text(
                                'Registra el análisis físico-químico de tu suelo para '
                                'obtener recomendaciones de abono ajustadas a cada cultivo.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 12, color: Colors.grey)),
                          ]),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: list.length,
                      itemBuilder: (_, i) => _AnalisisCard(a: list[i]),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnalisisCard extends ConsumerWidget {
  const _AnalisisCard({required this.a});
  final dynamic a; // drift.AnalisisSueloData

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: InkWell(
        onTap: () => context.go('/soil-analysis/${a.id}'),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.science, color: Colors.brown),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_iso(a.fechaMuestreo as DateTime),
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 16)),
                      if (a.laboratorio != null)
                        Text(a.laboratorio as String,
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).hintColor)),
                    ],
                  ),
                ),
                if (a.lote != null)
                  Chip(
                      label: Text('Lote: ${a.lote}',
                          style: const TextStyle(fontSize: 10))),
              ]),
              const Divider(),
              Wrap(spacing: 12, runSpacing: 4, children: [
                if (a.ph != null) _chip('pH', a.ph.toStringAsFixed(1)),
                if (a.materiaOrganicaPct != null)
                  _chip('MO', '${a.materiaOrganicaPct.toStringAsFixed(1)}%'),
                if (a.nPpm != null)
                  _chip('N', '${a.nPpm.toStringAsFixed(0)} ppm'),
                if (a.pPpm != null)
                  _chip('P', '${a.pPpm.toStringAsFixed(0)} ppm'),
                if (a.kPpm != null)
                  _chip('K', '${a.kPpm.toStringAsFixed(0)} ppm'),
                if (a.textura != null) _chip('Textura', a.textura as String),
              ]),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                IconButton(
                    icon: const Icon(Icons.delete_outline,
                        color: Colors.red, size: 20),
                    onPressed: () => _confirmDelete(context, ref)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, String value) => Chip(
        label: Text('$label: $value', style: const TextStyle(fontSize: 11)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      );

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar análisis'),
        content: Text(
            '¿Enviar el análisis del ${_iso(a.fechaMuestreo as DateTime)} a la papelera?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Eliminar')),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(dataMutationsProvider).deleteAnalisisSuelo(a.id as int);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Análisis eliminado')));
      }
    }
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}
