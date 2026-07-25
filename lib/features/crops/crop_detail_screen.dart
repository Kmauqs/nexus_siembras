// Detalle consolidado de un cultivo: info base + eventos + tareas + insumos.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/theme/themes.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/status_dot.dart';
import '../../data/repositories/cultivo_repository.dart';
import '../../data/repositories/recomendacion_agronomica.dart';
import '../../state/data_state.dart';
import '../pathologies/patologia_activa_card.dart';
import '../pathologies/reportar_patologia_modal.dart';
import 'crops_list_screen.dart' show showRegistrarTareaModal;
import 'cultivo_info_widgets.dart';

class CropDetailScreen extends ConsumerWidget {
  const CropDetailScreen({super.key, required this.cultivoId});
  final int cultivoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activos = ref.watch(cultivosActivosProvider);
    final finalizados = ref.watch(cultivosFinalizadosProvider);
    final all = [...activos, ...finalizados];
    final cul = all.where((c) => c.id == cultivoId).firstOrNull;
    if (cul == null) {
      return AppShell(
        title: 'Cultivo',
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search_off, size: 60, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Cultivo no encontrado',
                style: TextStyle(fontSize: 18, color: Colors.grey)),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: () => context.go('/crops'),
                child: const Text('Volver')),
          ]),
        ),
      );
    }
    final plantas = ref.watch(plantasProvider);
    final pl = plantas.where((p) => p.id == cul.plantaId).firstOrNull;
    final tareas = ref.watch(tareasPredioProvider)
        .where((t) => t.cultivoId == cultivoId)
        .toList()
      ..sort((a, b) => b.fecha.compareTo(a.fecha));
    final estadoAsync = ref.watch(estadoCultivoProvider(cultivoId));
    final eventos = ref.watch(eventosCultivoProvider(cultivoId));

    // Cálculos consolidados
    final totalHH = tareas.fold<double>(0, (s, t) => s + t.hh);
    final valorHora = cul.horaValor ?? 6500;
    final costoMO = totalHH * valorHora;

    // Permisos por rol: propietario y trabajador pueden registrar tareas
    // y reportar patologías; consultor solo lee.
    final permisos = ref.watch(permisosPredioActivoProvider);
    final puedeEditar = permisos.puedeEditarCultivosYTareas;

    return AppShell(
      title: pl?.nombre ?? 'Cultivo',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ============ Info base ============
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    estadoAsync.when(
                      data: (info) => StatusDot(estado: info.estado),
                      loading: () => const SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                      error: (_, __) =>
                          const StatusDot(estado: EstadoCultivo.verde),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(pl?.nombre ?? '?',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                          if (pl != null)
                            Text(pl.especie,
                                style: TextStyle(fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: Theme.of(context).hintColor)),
                        ],
                      ),
                    ),
                    if (cul.isFinalizado)
                      const Chip(label: Text('🏁 Finalizado')),
                  ]),
                  const Divider(),
                  _row('Lote', cul.lote),
                  _row('Sembrado', cul.sembrado),
                  estadoAsync.maybeWhen(
                    data: (info) => _row('Estado', info.nota),
                    orElse: () => const SizedBox.shrink(),
                  ),
                  if (cul.areaBaseM2 != null)
                    _row('Área', '${cul.areaBaseM2!.toStringAsFixed(0)} m²'),
                  if (cul.lat != null && cul.lng != null)
                    _row('Coordenadas', '${cul.lat}, ${cul.lng}'),
                ],
              ),
            ),
          ),
          // ============ Tipo y periodos ============
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Text('Tipo y periodos',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    TipoCultivoChip(cultivo: cul),
                  ]),
                  const SizedBox(height: 10),
                  PeriodosConfiguradosList(cultivo: cul),
                  if (cul.lineasPeriodosConfigurados.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'Contados desde la fecha base fenológica '
                        '(siembra o trasplante).',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).hintColor),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // ============ Cronograma ============
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Expanded(
                      child: Text('Cronograma',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    Text('${eventos.length} evento(s)',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor)),
                  ]),
                  const SizedBox(height: 4),
                  Text(
                    'Las fechas se ajustan al registrar tareas con fecha '
                    'distinta a la programada.',
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).hintColor),
                  ),
                  const Divider(),
                  CronogramaCultivoList(eventos: eventos),
                ],
              ),
            ),
          ),
          // ============ Consolidado ============
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Consolidado',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  _row('Tareas registradas', '${tareas.length}'),
                  _row('HH totales', '${totalHH.toStringAsFixed(1)} h'),
                  _row('Costo mano de obra',
                      '\$ ${costoMO.toStringAsFixed(0)} '
                      '(${totalHH.toStringAsFixed(0)}h × \$${valorHora.toStringAsFixed(0)}/h)'),
                  _row('Insumos únicos', '${_insumosUnicos(tareas).length}'),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Resincronizar eventos'),
                      onPressed: () => _resincronizar(context, ref),
                    ),
                  ),
                  Text(
                      'Reconstruye el cronograma desde la configuración del '
                      'cultivo y reaplica las tareas, ajustando fechas según '
                      'las fechas reales de ejecución.',
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).hintColor)),
                ],
              ),
            ),
          ),
          // ============ Recomendación agronómica ============
          _RecomendacionCard(cultivoId: cultivoId),
          // ============ Insumos totalizados ============
          if (tareas.any((t) => t.insumos.isNotEmpty)) ...[
            const SizedBox(height: 4),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Insumos usados (totales)',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ..._insumosTotalizados(tareas).entries.map((e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(children: [
                            const Icon(Icons.circle, size: 6, color: Colors.grey),
                            const SizedBox(width: 6),
                            Expanded(child: Text(e.key)),
                            Text('${e.value.$1.toStringAsFixed(e.value.$1 == e.value.$1.roundToDouble() ? 0 : 3)} ${e.value.$2}',
                                style: const TextStyle(fontWeight: FontWeight.bold)),
                          ]),
                        )),
                  ],
                ),
              ),
            ),
          ],
          // ============ Patologías reportadas ============
          const SizedBox(height: 4),
          _PatologiasCultivoCard(
            cultivoId: cultivoId,
            plantaNombre: pl?.nombre ?? '?',
            lote: cul.lote,
          ),
          // ============ Historial de tareas ============
          const SizedBox(height: 4),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Expanded(
                      child: Text('Historial de tareas',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                    // Reportar patología: cualquier colaborador puede
                    // reportar (incluso consultor). Un consultor suele
                    // ser un agrónomo asesor cuyo aporte de detección es
                    // valioso; además el reporte alimenta el heatmap
                    // comunitario opt-in.
                    IconButton(
                      onPressed: () => showReportarPatologiaModal(
                        context: context,
                        cultivoId: cultivoId,
                      ),
                      icon: const Icon(Icons.bug_report,
                          color: Colors.orange, size: 22),
                      tooltip: 'Reportar patología',
                    ),
                    if (puedeEditar)
                      FilledButton.icon(
                        onPressed: () => showRegistrarTareaModal(
                          context: context,
                          cultivoId: cultivoId,
                          plantaNombre: pl?.nombre ?? '?',
                        ),
                        icon: const Icon(Icons.check_circle, size: 18),
                        label: const Text('Registrar tarea'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppThemes.colorOk,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 8),
                  if (tareas.isEmpty)
                    Text('Sin tareas registradas',
                        style: TextStyle(color: Theme.of(context).hintColor))
                  else
                    ...tareas.map((t) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text('📅 ${_iso(t.fecha)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Text('${t.hh.toStringAsFixed(t.hh == t.hh.roundToDouble() ? 0 : 1)} h',
                                    style: TextStyle(color: Theme.of(context).hintColor)),
                              ]),
                              Wrap(spacing: 4, children: t.actividades.map((a) => Container(
                                margin: const EdgeInsets.only(top: 2),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppThemes.colorOk.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(a, style: const TextStyle(
                                    fontSize: 10, color: AppThemes.colorOk,
                                    fontWeight: FontWeight.w600)),
                              )).toList()),
                              if (t.insumos.isNotEmpty)
                                ...t.insumos.map((ins) => Padding(
                                      padding: const EdgeInsets.only(left: 12, top: 2),
                                      child: Text(
                                          '· ${ins.desc}: ${ins.cantidad.toStringAsFixed(ins.cantidad == ins.cantidad.roundToDouble() ? 0 : 3)} ${ins.unidad}',
                                          style: const TextStyle(fontSize: 11)),
                                    )),
                              if (t.notas != null && t.notas!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(left: 12, top: 2),
                                  child: Text('📝 ${t.notas}',
                                      style: const TextStyle(
                                          fontSize: 11, fontStyle: FontStyle.italic,
                                          color: Colors.grey)),
                                ),
                              const Divider(height: 12),
                            ],
                          ),
                        )),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _resincronizar(BuildContext context, WidgetRef ref) async {
    try {
      final n = await ref
          .read(dataMutationsProvider)
          .resincronizarEventos(cultivoId);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(n == 0
              ? 'No había eventos por cerrar según las tareas registradas'
              : '$n evento(s) sincronizado(s) según tareas registradas')));
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 130, child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v)),
          ],
        ),
      );

  Set<String> _insumosUnicos(List<TareaCompletada> tareas) {
    final set = <String>{};
    for (final t in tareas) {
      for (final i in t.insumos) {
        set.add(i.desc);
      }
    }
    return set;
  }

  /// Totaliza insumos por descripción. Devuelve `desc → (cantidad, unidad)`.
  Map<String, (double, String)> _insumosTotalizados(List<TareaCompletada> tareas) {
    final map = <String, (double, String)>{};
    for (final t in tareas) {
      for (final i in t.insumos) {
        final existing = map[i.desc];
        if (existing == null) {
          map[i.desc] = (i.cantidad, i.unidad);
        } else {
          map[i.desc] = (existing.$1 + i.cantidad, existing.$2);
        }
      }
    }
    return map;
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Recomendación agronómica basada en análisis de suelo, condiciones del
/// predio y requerimientos de la planta.
class _RecomendacionCard extends ConsumerWidget {
  const _RecomendacionCard({required this.cultivoId});
  final int cultivoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recomendacionCultivoProvider(cultivoId));
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                const Icon(Icons.eco, color: Colors.green),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text('Recomendación agronómica',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ]),
              const Divider(),
              async.when(
                loading: () =>
                    const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
                error: (e, _) => Text('Error: $e',
                    style: const TextStyle(color: Colors.red)),
                data: (r) => r == null
                    ? const Text('Sin datos')
                    : _RecomendacionContent(rec: r),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecomendacionContent extends StatelessWidget {
  const _RecomendacionContent({required this.rec});
  final RecomendacionAgronomica rec;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rec.resumen != null && rec.resumen!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(rec.resumen!,
                style: const TextStyle(fontStyle: FontStyle.italic)),
          ),

        // Dosis N-P-K
        if (rec.dosis.nKgHa != null ||
            rec.dosis.pKgHa != null ||
            rec.dosis.kKgHa != null) ...[
          const Text('Dosis sugerida (por hectárea)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          if (rec.dosis.nKgHa != null)
            _dosisRow('N', rec.dosis.nKgHa!, rec.dosis.notaN),
          if (rec.dosis.pKgHa != null)
            _dosisRow('P', rec.dosis.pKgHa!, rec.dosis.notaP),
          if (rec.dosis.kKgHa != null)
            _dosisRow('K', rec.dosis.kKgHa!, rec.dosis.notaK),
          const SizedBox(height: 8),
        ],

        // Alertas
        if (rec.alertas.isNotEmpty) ...[
          const Text('Observaciones',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          ...rec.alertas.map(_alertaRow),
        ],

        // Fuente
        if (rec.planta.fuenteAgronomica != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Requerimientos: ${rec.planta.fuenteAgronomica}',
                style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ),
      ],
    );
  }

  Widget _dosisRow(String nut, double kgHa, String? nota) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 26,
              height: 26,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(nut,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: Colors.green)),
            ),
            const SizedBox(width: 8),
            Text('${kgHa.toStringAsFixed(0)} kg/ha',
                style: const TextStyle(fontWeight: FontWeight.bold)),
          ]),
          if (nota != null)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 2),
              child: Text(nota,
                  style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
        ],
      ),
    );
  }

  Widget _alertaRow(AlertaAgronomica a) {
    final (color, icon) = switch (a.nivel) {
      NivelAlerta.critico => (Colors.red, Icons.error_outline),
      NivelAlerta.atencion => (Colors.orange, Icons.warning_amber),
      NivelAlerta.info => (Colors.blue, Icons.info_outline),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.titulo,
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: color, fontSize: 13)),
                Text(a.detalle, style: const TextStyle(fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Card con las patologías activas reportadas para este cultivo.
/// Reutiliza PatologiaActivaCard (mismo componente que usa la pantalla
/// Patologías) y ofrece un botón directo para levantar un nuevo reporte.
class _PatologiasCultivoCard extends ConsumerWidget {
  const _PatologiasCultivoCard({
    required this.cultivoId,
    required this.plantaNombre,
    required this.lote,
  });
  final int cultivoId;
  final String plantaNombre, lote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(patologiasActivasCultivoProvider(cultivoId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Expanded(
                child: Text('Patologías reportadas',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold)),
              ),
              // Reportar patología abierto a cualquier colaborador
              // (incluye consultor) — ver nota en Historial de tareas.
              IconButton(
                onPressed: () => showReportarPatologiaModal(
                    context: context, cultivoId: cultivoId),
                icon: const Icon(Icons.add_circle,
                    color: Colors.orange, size: 22),
                tooltip: 'Reportar nueva patología',
              ),
            ]),
            const SizedBox(height: 6),
            async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Error: $e'),
              data: (list) {
                if (list.isEmpty) {
                  return Text(
                      '— sin detecciones activas para este cultivo —',
                      style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).hintColor));
                }
                return Column(
                  children: list
                      .map((cp) => PatologiaActivaCard(
                            cp: cp,
                            plantaNombre: plantaNombre,
                            lote: lote,
                          ))
                      .toList(),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
