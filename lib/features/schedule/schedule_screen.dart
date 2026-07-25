import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/themes.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/repositories/cultivo_repository.dart';
import '../../state/data_state.dart';

enum _CronView { gantt, calendar, actividades }

class ScheduleScreen extends ConsumerStatefulWidget {
  const ScheduleScreen({super.key});
  @override
  ConsumerState<ScheduleScreen> createState() => _ScheduleScreenState();
}

class _ScheduleScreenState extends ConsumerState<ScheduleScreen> {
  _CronView _view = _CronView.gantt;
  DateTime _calAnchor = DateTime(DateTime.now().year, DateTime.now().month, 1);
  // Gantt: ancla = fecha central (por defecto HOY). Ventana = ± 3 meses.
  DateTime _ganttCenter = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final cultivos = ref.watch(cultivosActivosProvider);
    final finalizados = ref.watch(cultivosFinalizadosProvider);
    final eventos = ref.watch(eventosPredioProvider);
    final plantas = ref.watch(plantasProvider);
    final plantasById = {for (final p in plantas) p.id: p};
    return AppShell(
      title: 'Cronograma',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: SegmentedButton<_CronView>(
              segments: const [
                ButtonSegment(value: _CronView.gantt,
                    label: Text('Gantt'), icon: Icon(Icons.bar_chart)),
                ButtonSegment(value: _CronView.calendar,
                    label: Text('Calendario'), icon: Icon(Icons.calendar_month)),
                ButtonSegment(value: _CronView.actividades,
                    label: Text('Actividades'), icon: Icon(Icons.checklist)),
              ],
              selected: {_view},
              onSelectionChanged: (s) => setState(() => _view = s.first),
            ),
          ),
          Expanded(
            child: _view == _CronView.actividades
                ? _ActividadesView(
                    cultivos: [...cultivos, ...finalizados],
                    plantasById: plantasById,
                  )
                : _view == _CronView.gantt
                ? _GanttView(
                    cultivos: cultivos,
                    eventos: eventos,
                    plantasById: plantasById,
                    center: _ganttCenter,
                    onNav: (delta) => setState(() {
                      _ganttCenter = DateTime(_ganttCenter.year,
                          _ganttCenter.month + delta, _ganttCenter.day);
                    }),
                    onReset: () =>
                        setState(() => _ganttCenter = DateTime.now()),
                  )
                : _CalendarView(
                    anchor: _calAnchor,
                    // Calendario incluye finalizados (spec 2.14)
                    cultivos: [...cultivos, ...finalizados],
                    eventos: eventos,
                    plantasById: plantasById,
                    onNav: (d) => setState(() =>
                        _calAnchor = DateTime(_calAnchor.year, _calAnchor.month + d, 1)),
                  ),
          ),
        ],
      ),
    );
  }
}

// ============ Gantt ============

class _GanttView extends ConsumerWidget {
  const _GanttView({
    required this.cultivos,
    required this.eventos,
    required this.plantasById,
    required this.center,
    required this.onNav,
    required this.onReset,
  });
  final List<Cultivo> cultivos;
  final List<Evento> eventos;
  final Map<int, Planta> plantasById;
  final DateTime center;
  final void Function(int delta) onNav;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (cultivos.isEmpty) {
      return const Center(
          child: Padding(padding: EdgeInsets.all(40),
              child: Text('Sin cultivos activos para mostrar')));
    }
    // Ventana fija: 6 meses centrados en `center` (3 antes, 3 después)
    final min = DateTime(center.year, center.month - 3, 1);
    final max = DateTime(center.year, center.month + 3, 1);
    final totalDays = max.difference(min).inDays;
    const meses = ['ene','feb','mar','abr','may','jun','jul','ago','sep','oct','nov','dic'];
    const mesesLongo = ['Enero','Febrero','Marzo','Abril','Mayo','Junio',
        'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
    final centerLabel = '${mesesLongo[center.month - 1]} ${center.year}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra de navegación
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(icon: const Icon(Icons.chevron_left),
                    tooltip: '3 meses antes',
                    onPressed: () => onNav(-3)),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text('Centro: $centerLabel',
                      style: Theme.of(context).textTheme.titleSmall),
                  Text('Ventana: ${meses[min.month - 1]} \'${min.year.toString().substring(2)} → '
                       '${meses[(max.month - 2) % 12]} \'${(max.month == 1 ? max.year - 1 : max.year).toString().substring(2)}',
                      style: const TextStyle(fontSize: 10, color: Colors.grey)),
                ]),
                Row(children: [
                  TextButton.icon(
                    icon: const Icon(Icons.today, size: 16),
                    label: const Text('HOY'),
                    onPressed: onReset,
                  ),
                  IconButton(icon: const Icon(Icons.chevron_right),
                      tooltip: '3 meses después',
                      onPressed: () => onNav(3)),
                ]),
              ]),
              const SizedBox(height: 8),
              // Área del Gantt con LayoutBuilder interno para medir el Row exacto
              LayoutBuilder(builder: (ctx, cons) {
      const labelW = 110.0;
      final laneW = (cons.maxWidth - labelW - 8).clamp(50, 10000).toDouble();
      double pctOf(DateTime d) {
        final v = d.difference(min).inDays / totalDays;
        return (v * laneW).clamp(0.0, laneW);
      }
      double rawPctOf(DateTime d) => (d.difference(min).inDays / totalDays) * laneW;

      final ticks = <(DateTime, double)>[];
      var dt = DateTime(min.year, min.month, 1);
      while (dt.isBefore(max)) {
        ticks.add((dt, pctOf(dt)));
        dt = DateTime(dt.year, dt.month + 1, 1);
      }
      final hoyPos = rawPctOf(DateTime.now());

      // Agrupa eventos por cultivo
      final evsByCultivo = <int, List<Evento>>{};
      for (final e in eventos) {
        (evsByCultivo[e.cultivoId] ??= []).add(e);
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
                Stack(children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Fila años
                      SizedBox(height: 16, child: Row(children: [
                        SizedBox(width: labelW),
                        Expanded(child: _YearsRow(
                          min: min, max: max, pctOf: pctOf, laneW: laneW,
                        )),
                      ])),
                      // Fila meses
                      SizedBox(height: 18, child: Row(children: [
                        SizedBox(width: labelW),
                        Expanded(child: Stack(children: [
                          for (final t in ticks)
                            Positioned(
                              left: t.$2, top: 0, bottom: 0,
                              child: Container(
                                padding: const EdgeInsets.only(left: 3),
                                decoration: BoxDecoration(
                                  border: Border(left: BorderSide(
                                    color: Theme.of(context).dividerColor,
                                  )),
                                ),
                                child: Text(meses[t.$1.month - 1],
                                    style: const TextStyle(
                                        fontSize: 10, color: Colors.grey,
                                        fontWeight: FontWeight.w600)),
                              ),
                            ),
                        ])),
                      ])),
                      const Divider(height: 1),
                      // Filas de cultivos
                      ...cultivos.map((c) {
                        final estAsync = ref.watch(estadoCultivoProvider(c.id));
                        final color = estAsync.hasValue
                            ? switch (estAsync.value!.estado) {
                                EstadoCultivo.verde   => AppThemes.colorOk,
                                EstadoCultivo.naranja => AppThemes.colorWarn,
                                EstadoCultivo.rojo    => AppThemes.colorAlert,
                              }
                            : AppThemes.colorOk;
                        final pl = plantasById[c.plantaId];
                        final evs = evsByCultivo[c.id] ?? const [];
                        final sembrado = DateTime.parse(c.sembrado);
                        final ultima = evs.isEmpty
                            ? sembrado.add(const Duration(days: 90))
                            : evs.map((e) => e.fechaEjecutada ?? e.fechaProgramada)
                                .reduce((a, b) => a.isAfter(b) ? a : b);
                        return _GanttRow(
                          plantaNombre: pl?.nombre ?? '?',
                          lote: c.lote,
                          labelW: labelW,
                          barColor: color,
                          barLeft: pctOf(sembrado),
                          barRight: pctOf(ultima),
                          milestones: evs.map((e) {
                            final fecha = e.fechaEjecutada ?? e.fechaProgramada;
                            return (
                              e.descripcion,
                              pctOf(fecha),
                              e.ejecutada,
                              e.ejecutada
                                  ? AppThemes.colorOk
                                  : (fecha.isBefore(DateTime.now())
                                      ? AppThemes.colorAlert
                                      : (fecha.difference(DateTime.now())
                                                  .inDays <= 7
                                              ? AppThemes.colorWarn
                                              : Colors.grey.shade400)),
                            );
                          }).toList(),
                        );
                      }),
                    ],
                  ),
                  // Línea HOY
                  if (hoyPos >= 0 && hoyPos <= laneW)
                    Positioned(
                      left: labelW + hoyPos - 1,
                      top: 0, bottom: 0,
                      child: IgnorePointer(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppThemes.colorAlert,
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: const Text('HOY',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 9,
                                      fontWeight: FontWeight.bold)),
                            ),
                            Expanded(
                              child: Container(
                                  width: 2,
                                  color: AppThemes.colorAlert.withOpacity(0.75)),
                            ),
                          ],
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 12),
                Wrap(spacing: 12, children: const [
                  _LegendItem(color: AppThemes.colorOk, label: 'Completado'),
                  _LegendItem(color: AppThemes.colorWarn, label: '≤ 7 días'),
                  _LegendItem(color: AppThemes.colorAlert, label: 'Vencido'),
                ]),
              ],
            );
          }),
            ],
          ),
        ),
      ),
    );
  }
}

class _YearsRow extends StatelessWidget {
  const _YearsRow({
    required this.min, required this.max,
    required this.pctOf, required this.laneW,
  });
  final DateTime min, max;
  final double Function(DateTime) pctOf;
  final double laneW;

  @override
  Widget build(BuildContext context) {
    final years = <int>[];
    for (var y = min.year; y <= max.year; y++) {
      years.add(y);
    }
    return Stack(children: [
      for (final y in years) ...[
        () {
          final start = DateTime(y, 1, 1);
          final end = DateTime(y + 1, 1, 1);
          final l = pctOf(start.isBefore(min) ? min : start).clamp(0.0, laneW);
          final r = pctOf(end.isAfter(max) ? max : end).clamp(0.0, laneW);
          if (r <= l) return const SizedBox.shrink();
          return Positioned(
            left: l, top: 0, bottom: 0, width: r - l,
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.10),
                border: Border(left: BorderSide(color: Theme.of(context).dividerColor)),
              ),
              alignment: Alignment.center,
              child: Text('$y', style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.primary)),
            ),
          );
        }(),
      ],
    ]);
  }
}

class _GanttRow extends StatelessWidget {
  const _GanttRow({
    required this.plantaNombre,
    required this.lote,
    required this.labelW,
    required this.barColor,
    required this.barLeft,
    required this.barRight,
    required this.milestones,
  });
  final String plantaNombre, lote;
  final double labelW, barLeft, barRight;
  final Color barColor;
  // (description, leftPct, ejecutada, color)
  final List<(String, double, bool, Color)> milestones;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(children: [
        SizedBox(
          width: labelW,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(plantaNombre,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  overflow: TextOverflow.ellipsis),
              Text(lote,
                  style: TextStyle(fontSize: 10, color: Theme.of(context).hintColor),
                  overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        Expanded(child: SizedBox(
          height: 30,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned(
              left: barLeft, top: 8,
              width: (barRight - barLeft).clamp(2, double.infinity),
              height: 14,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [barColor, barColor.withOpacity(0.75)]),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            for (final m in milestones)
              Positioned(
                left: m.$2 - 7, top: 4,
                child: Tooltip(
                  message: '${m.$1}${m.$3 ? " · ✓ completado" : ""}',
                  child: Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: m.$4, width: 3),
                      boxShadow: const [
                        BoxShadow(color: Colors.black26, blurRadius: 2, spreadRadius: 0.5),
                      ],
                    ),
                    // Ícono ✓ para completados
                    child: m.$3
                        ? Icon(Icons.check, size: 9, color: m.$4)
                        : null,
                  ),
                ),
              ),
          ]),
        )),
      ]),
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 12, height: 6,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      );
}

// ============ Calendar ============

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.anchor,
    required this.cultivos,
    required this.eventos,
    required this.plantasById,
    required this.onNav,
  });
  final DateTime anchor;
  final List<Cultivo> cultivos;
  final List<Evento> eventos;
  final Map<int, Planta> plantasById;
  final void Function(int delta) onNav;

  @override
  Widget build(BuildContext context) {
    const meses = ['Enero','Febrero','Marzo','Abril','Mayo','Junio',
        'Julio','Agosto','Septiembre','Octubre','Noviembre','Diciembre'];
    final firstOffset = DateTime(anchor.year, anchor.month, 1).weekday % 7;
    final daysInMonth = DateTime(anchor.year, anchor.month + 1, 0).day;

    final cultivoById = {for (final c in cultivos) c.id: c};
    // Agrupa eventos por fecha string
    final byDate = <String, List<Evento>>{};
    for (final e in eventos) {
      final f = e.fechaEjecutada ?? e.fechaProgramada;
      (byDate[_iso(f)] ??= []).add(e);
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          IconButton(icon: const Icon(Icons.chevron_left), onPressed: () => onNav(-1)),
          Text('${meses[anchor.month - 1]} ${anchor.year}',
              style: Theme.of(context).textTheme.titleMedium),
          IconButton(icon: const Icon(Icons.chevron_right), onPressed: () => onNav(1)),
        ]),
        const SizedBox(height: 8),
        const _DayHeaders(),
        const SizedBox(height: 4),
        Expanded(
          child: GridView.count(
            crossAxisCount: 7,
            childAspectRatio: 0.9,
            crossAxisSpacing: 3,
            mainAxisSpacing: 3,
            children: [
              for (int i = 0; i < firstOffset; i++) const SizedBox.shrink(),
              for (int d = 1; d <= daysInMonth; d++)
                _DayCell(
                  day: d,
                  date: DateTime(anchor.year, anchor.month, d),
                  events: byDate[_iso(DateTime(anchor.year, anchor.month, d))] ?? const [],
                  cultivoById: cultivoById,
                  plantasById: plantasById,
                ),
            ],
          ),
        ),
      ]),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}

class _DayHeaders extends StatelessWidget {
  const _DayHeaders();
  static const _names = ['Dom', 'Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb'];
  @override
  Widget build(BuildContext c) => Row(
        children: _names
            .map((d) => Expanded(
                  child: Center(child: Text(d,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.grey,
                            fontWeight: FontWeight.w600))),
                )).toList(),
      );
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.date,
    required this.events,
    required this.cultivoById,
    required this.plantasById,
  });
  final int day;
  final DateTime date;
  final List<Evento> events;
  final Map<int, Cultivo> cultivoById;
  final Map<int, Planta> plantasById;

  @override
  Widget build(BuildContext context) {
    final isToday = _sameDay(date, DateTime.now());
    return InkWell(
      onTap: events.isEmpty ? null : () => _showDayModal(context),
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(
            color: isToday
                ? Theme.of(context).colorScheme.primary
                : Theme.of(context).dividerColor,
            width: isToday ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.all(2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Text('$day',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                      color: isToday
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey)),
            ),
            const SizedBox(height: 2),
            for (var i = 0; i < events.length && i < 2; i++)
              Container(
                margin: const EdgeInsets.only(bottom: 1),
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: events[i].ejecutada ? AppThemes.colorOk : AppThemes.colorWarn,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(events[i].descripcion,
                    style: const TextStyle(fontSize: 8, color: Colors.white),
                    overflow: TextOverflow.ellipsis),
              ),
            if (events.length > 2)
              Text('+${events.length - 2}',
                  style: const TextStyle(fontSize: 8, color: Colors.grey),
                  textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _showDayModal(BuildContext ctx) {
    showModalBottomSheet<void>(
      context: ctx,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${date.year}-${date.month.toString().padLeft(2, "0")}-${date.day.toString().padLeft(2, "0")}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...events.map((e) {
              final cul = cultivoById[e.cultivoId];
              final pl = cul != null ? plantasById[cul.plantaId] : null;
              return ListTile(
                leading: Container(width: 12, height: 12,
                    decoration: BoxDecoration(
                        color: e.ejecutada ? AppThemes.colorOk : AppThemes.colorWarn,
                        shape: BoxShape.circle)),
                title: Text(e.descripcion),
                subtitle: Text('${pl?.nombre ?? "?"} · ${cul?.lote ?? "?"}'
                    '${e.ejecutada ? " · ✓" : ""}'),
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ============ Actividades registradas ============

/// Entrada del listado de Actividades: puede ser una TareaCompletada
/// (registrada por el usuario) o un Evento auto-ejecutado por el sistema
/// (Siembra o Semillero al crear un cultivo).
sealed class _ActividadItem {
  DateTime get fecha;
  int get cultivoId;
}

class _ItemTarea extends _ActividadItem {
  _ItemTarea(this.tarea);
  final TareaCompletada tarea;
  @override
  DateTime get fecha => tarea.fecha;
  @override
  int get cultivoId => tarea.cultivoId;
}

class _ItemEvento extends _ActividadItem {
  _ItemEvento(this.evento);
  final Evento evento;
  @override
  DateTime get fecha => evento.fechaEjecutada ?? evento.fechaProgramada;
  @override
  int get cultivoId => evento.cultivoId;
}

class _ActividadesView extends ConsumerWidget {
  const _ActividadesView({required this.cultivos, required this.plantasById});
  final List<Cultivo> cultivos;
  final Map<int, Planta> plantasById;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tareas = ref.watch(tareasPredioProvider);
    final eventos = ref.watch(eventosPredioProvider);
    final cultivosById = {for (final c in cultivos) c.id: c};

    // Une tareas manuales + eventos auto-ejecutados (Siembra/Semillero).
    // Los eventos manuales que ya tienen una TareaCompletada asociada NO se
    // duplican: filtramos los que no aparecen como actividad de una tarea.
    final tareasPorCultivo = <int, Set<String>>{};
    for (final t in tareas) {
      final set = tareasPorCultivo.putIfAbsent(t.cultivoId, () => <String>{});
      for (final a in t.actividades) {
        set.add(a.toLowerCase());
      }
    }
    final items = <_ActividadItem>[
      ...tareas.map((t) => _ItemTarea(t)),
      // Solo eventos ejecutados de siembra y semillero, sin duplicar con tareas
      ...eventos.where((e) {
        if (!e.ejecutada) return false;
        final tipo = e.tipo.toLowerCase();
        if (tipo != 'siembra' && tipo != 'semillero') return false;
        // Si el usuario ya registró una Tarea con esa actividad → no duplicar
        final regs = tareasPorCultivo[e.cultivoId] ?? const <String>{};
        return !regs.contains(tipo);
      }).map((e) => _ItemEvento(e)),
    ];
    // Ordena por fecha descendente (más recientes primero)
    items.sort((a, b) => b.fecha.compareTo(a.fecha));

    if (items.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.checklist, size: 60, color: Colors.grey),
              SizedBox(height: 12),
              Text('Sin actividades registradas',
                  style: TextStyle(fontSize: 18, color: Colors.grey)),
              SizedBox(height: 6),
              Text('Registra tareas desde el botón ✓ en "Ver cultivos"',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        final cul = cultivosById[item.cultivoId];
        final pl = cul != null ? plantasById[cul.plantaId] : null;
        final plantaNombre = pl?.nombre ?? '?';
        final lote = cul?.lote ?? '?';
        return switch (item) {
          _ItemTarea(:final tarea) => _TareaCard(
              tarea: tarea, plantaNombre: plantaNombre, lote: lote),
          _ItemEvento(:final evento) => _EventoAutoCard(
              evento: evento, plantaNombre: plantaNombre, lote: lote),
        };
      },
    );
  }
}

/// Tarjeta para eventos auto-ejecutados (Siembra, Semillero) que no
/// corresponden a una TareaCompletada registrada manualmente.
class _EventoAutoCard extends StatelessWidget {
  const _EventoAutoCard({
    required this.evento,
    required this.plantaNombre,
    required this.lote,
  });
  final Evento evento;
  final String plantaNombre, lote;

  @override
  Widget build(BuildContext context) {
    final tipoLabel = evento.tipo[0].toUpperCase() + evento.tipo.substring(1);
    final fecha = evento.fechaEjecutada ?? evento.fechaProgramada;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppThemes.colorOk.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(
              evento.tipo.toLowerCase() == 'semillero'
                  ? Icons.grass
                  : Icons.eco,
              color: AppThemes.colorOk,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$plantaNombre · $lote',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 14)),
                Text(
                    '${fecha.year}-${fecha.month.toString().padLeft(2, "0")}-${fecha.day.toString().padLeft(2, "0")} · $tipoLabel',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).hintColor)),
                if (evento.descripcion.isNotEmpty)
                  Text(evento.descripcion,
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).hintColor)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text('auto',
                style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }
}

class _TareaCard extends ConsumerWidget {
  const _TareaCard({
    required this.tarea,
    required this.plantaNombre,
    required this.lote,
  });
  final TareaCompletada tarea;
  final String plantaNombre, lote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$plantaNombre · $lote',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${_iso(tarea.fecha)} · ${tarea.hh.toStringAsFixed(tarea.hh == tarea.hh.roundToDouble() ? 0 : 1)} h',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
                    if (tarea.createdByUserId != null &&
                        tarea.createdByUserId!.isNotEmpty)
                      _AutorLabel(userId: tarea.createdByUserId!),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Editar fecha/HH/notas',
                onPressed: () => _showEditModal(context, ref),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Eliminar tarea',
                onPressed: () => _confirmDelete(context, ref),
              ),
            ]),
            if (tarea.actividades.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(spacing: 4, runSpacing: 4,
                children: tarea.actividades.map((a) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppThemes.colorOk.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(a, style: const TextStyle(
                      fontSize: 11, color: AppThemes.colorOk,
                      fontWeight: FontWeight.w600)),
                )).toList(),
              ),
            ],
            if (tarea.insumos.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('Insumos usados:',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor,
                      fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              ...tarea.insumos.map((ins) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 1),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 5, color: Colors.grey),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                            '${ins.desc} · ${ins.cantidad.toStringAsFixed(ins.cantidad == ins.cantidad.roundToDouble() ? 0 : 3)} ${ins.unidad}',
                            style: const TextStyle(fontSize: 11)),
                      ),
                    ]),
                  )),
            ],
            if (tarea.notas != null && tarea.notas!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('📝 ${tarea.notas}',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor,
                      fontStyle: FontStyle.italic)),
            ],
          ],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, WidgetRef ref) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar tarea'),
        content: const Text(
            '¿Eliminar esta tarea?\n\nSe restarán las HH del cultivo, '
            'se devolverán los insumos al inventario y se reabrirán los eventos '
            'del Gantt que había cerrado.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(dataMutationsProvider).deleteTarea(tarea.id);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content: Text('Tarea eliminada · HH e insumos restaurados')));
              }
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _showEditModal(BuildContext ctx, WidgetRef ref) {
    final fechaCtrl = TextEditingController(text: _iso(tarea.fecha));
    final hhCtrl = TextEditingController(text: tarea.hh.toString());
    final notasCtrl = TextEditingController(text: tarea.notas ?? '');
    DateTime fecha = tarea.fecha;
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(builder: (mCtx, setState) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(mCtx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Editar tarea',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              Text('$plantaNombre · $lote',
                  style: TextStyle(color: Theme.of(mCtx).hintColor)),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: mCtx,
                    initialDate: fecha,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                  );
                  if (d != null) {
                    fecha = d;
                    fechaCtrl.text = _iso(d);
                    setState(() {});
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                      labelText: 'Fecha',
                      suffixIcon: Icon(Icons.calendar_today),
                      border: OutlineInputBorder()),
                  child: Text(fechaCtrl.text),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: hhCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'HH trabajadas', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notasCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Notas', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              const Text(
                  'ℹ️ Editar actividades o insumos: elimina esta tarea y crea una nueva.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 16),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(
                    onPressed: () => Navigator.pop(mCtx),
                    child: const Text('Cancelar')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () async {
                    await ref.read(dataMutationsProvider).updateTareaSimple(
                          id: tarea.id,
                          fecha: fecha,
                          hh: double.tryParse(hhCtrl.text) ?? tarea.hh,
                          notas: notasCtrl.text.trim().isEmpty
                              ? null
                              : notasCtrl.text.trim(),
                        );
                    if (mCtx.mounted) {
                      Navigator.pop(mCtx);
                      ScaffoldMessenger.of(mCtx).showSnackBar(
                          const SnackBar(content: Text('Tarea actualizada')));
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ]),
            ],
          ),
        );
      }),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}

/// Etiqueta "👤 email" que resuelve async el UUID Supabase → email vía
/// `emailPorUserIdProvider`. Fallback: primeros 8 caracteres del UUID.
class _AutorLabel extends ConsumerWidget {
  const _AutorLabel({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailAsync = ref.watch(emailPorUserIdProvider(userId));
    final texto = emailAsync.maybeWhen(
      data: (email) => email ?? _resumen(userId),
      orElse: () => _resumen(userId),
    );
    return Text('👤 $texto',
        style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).hintColor,
            fontStyle: FontStyle.italic));
  }

  String _resumen(String uuid) =>
      uuid.length < 12 ? uuid : '${uuid.substring(0, 8)}…';
}
