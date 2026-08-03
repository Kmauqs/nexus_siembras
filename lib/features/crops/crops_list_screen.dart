import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/app_nav.dart';
import '../../core/reports/export_helpers.dart';
import '../../core/reports/report_data_builder.dart';
import '../../core/theme/themes.dart';
import '../../core/units/units_catalog.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/duracion_field.dart';
import '../../core/widgets/status_dot.dart';
import '../../data/repositories/cultivo_repository.dart';
import '../../state/app_state.dart';
import '../../state/data_state.dart';

class CropsListScreen extends ConsumerWidget {
  const CropsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activos = ref.watch(cultivosActivosProvider);
    final finalizados = ref.watch(cultivosFinalizadosProvider);
    final plantas = ref.watch(plantasProvider);
    final plantasById = {for (final p in plantas) p.id: p};
    return AppShell(
      title: 'Ver cultivos',
      actions: [
        IconButton(
          tooltip: 'Exportar CSV',
          icon: const Icon(Icons.file_download),
          onPressed: () => _exportar(context, ref, 'csv'),
        ),
        IconButton(
          tooltip: 'Exportar PDF',
          icon: const Icon(Icons.picture_as_pdf),
          onPressed: () => _exportar(context, ref, 'pdf'),
        ),
      ],
      child: activos.isEmpty && finalizados.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('🌱', style: TextStyle(fontSize: 60)),
                    SizedBox(height: 12),
                    Text('Sin cultivos aún',
                        style: TextStyle(fontSize: 18, color: Colors.grey)),
                    SizedBox(height: 6),
                    Text('Toca ➕ en Inicio para crear el primero',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (activos.isNotEmpty) ...[
                  Text('🌱 Activos (${activos.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...activos.map((c) => _CultivoTile(
                        c: c,
                        plantaNombre: plantasById[c.plantaId]?.nombre ?? '?',
                      )),
                ],
                if (finalizados.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('🏁 Finalizados (${finalizados.length})',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  ...finalizados.map((c) => _CultivoTile(
                        c: c,
                        plantaNombre: plantasById[c.plantaId]?.nombre ?? '?',
                        finalizado: true,
                      )),
                ],
              ],
            ),
    );
  }

  /// Exportación CSV/PDF del estado de cada cultivo con sus patologías
  /// activas (2026-07-20; recolección centralizada en report_data_builder).
  Future<void> _exportar(
      BuildContext context, WidgetRef ref, String fmt) async {
    final t = await buildCultivosReporte(ref);
    if (!context.mounted) return;
    await exportarTabla(
      context: context,
      ref: ref,
      fmt: fmt,
      scope: t.scope,
      titulo: t.titulo,
      columns: t.columns,
      rows: t.rows,
    );
  }
}

class _CultivoTile extends ConsumerWidget {
  const _CultivoTile({
    required this.c,
    required this.plantaNombre,
    this.finalizado = false,
  });
  final Cultivo c;
  final String plantaNombre;
  final bool finalizado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estadoAsync = finalizado
        ? const AsyncValue<EstadoInfo>.data(
            EstadoInfo(EstadoCultivo.verde, 'Cultivo finalizado'))
        : ref.watch(estadoCultivoProvider(c.id));
    // Consultor: solo lectura. Oculta botones registrar-tarea, finalizar,
    // reactivar y eliminar. El tile sigue siendo tapeable (navega a
    // /crops/:id) para inspeccionar detalles en modo lectura.
    final permisos = ref.watch(permisosPredioActivoProvider);
    final puedeEditar = permisos.puedeEditarCultivosYTareas;
    return Opacity(
      opacity: finalizado ? 0.7 : 1.0,
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => AppNav.open(context, '/crops/${c.id}'),
          child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              estadoAsync.when(
                data: (info) => StatusDot(
                  estado: info.estado,
                  tooltip: info.nota,
                  onTap: () => _showStatusModal(context, info),
                ),
                loading: () => const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                error: (_, __) =>
                    const StatusDot(estado: EstadoCultivo.verde),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(plantaNombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('${c.lote} · ${c.sembrado}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor)),
                    const SizedBox(height: 2),
                    Text(c.resumenPeriodosCorto,
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).hintColor,
                            fontStyle: FontStyle.italic)),
                    if (finalizado && c.finalizadoFecha != null)
                      Text('🏁 ${c.finalizadoFecha}',
                          style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                              fontStyle: FontStyle.italic)),
                  ],
                ),
              ),
              Text('${c.hh.toStringAsFixed(0)}h',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(width: 4),
              if (puedeEditar && !finalizado)
                IconButton(
                  icon: const Icon(Icons.check_circle, color: AppThemes.colorOk),
                  tooltip: 'Registrar tarea',
                  onPressed: () => _showCheckModal(context),
                ),
              if (puedeEditar && !finalizado)
                IconButton(
                  icon: const Icon(Icons.flag_outlined),
                  tooltip: 'Marcar finalizado',
                  onPressed: () => _confirmFinalize(context, ref),
                )
              else if (puedeEditar && finalizado)
                IconButton(
                  icon: const Icon(Icons.restore),
                  tooltip: 'Reactivar',
                  onPressed: () =>
                      ref.read(dataMutationsProvider).unfinalizeCultivo(c.id),
                ),
              if (puedeEditar)
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => _confirmDelete(context, ref),
                ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext ctx, WidgetRef ref) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar cultivo'),
        content: Text('¿Mover "$plantaNombre · ${c.lote}" a la papelera?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await ref.read(dataMutationsProvider).deleteCultivo(c.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
  }

  void _confirmFinalize(BuildContext ctx, WidgetRef ref) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Marcar cultivo como finalizado'),
        content: Text(
            'El cultivo "$plantaNombre · ${c.lote}" pasará a la sección Finalizados '
            'y no aparecerá en el Gantt (pero sí en el Calendario).'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              await ref.read(dataMutationsProvider).finalizeCultivo(c.id);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  void _showStatusModal(BuildContext ctx, EstadoInfo info) {
    showModalBottomSheet<void>(
      context: ctx,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              StatusDot(estado: info.estado),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Estado — $plantaNombre',
                    style: const TextStyle(
                        fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 12),
            Text(info.nota, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cerrar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCheckModal(BuildContext ctx) {
    showRegistrarTareaModal(
        context: ctx, cultivoId: c.id, plantaNombre: plantaNombre);
  }
}

// ============ Modal Registrar tarea ============

/// Abre el modal "Registrar tarea completada" para un cultivo dado.
///
/// Función pública y compartida: se llama desde el listado de cultivos
/// (botón ✓ en cada card) y desde el detalle del cultivo (botón en
/// "Historial de tareas" / círculos del Cronograma). Reutilizar la misma
/// implementación evita duplicar el formulario en más de una pantalla.
///
/// [fechaInicial] y [actividadInicial] precargan el formulario (p. ej. al
/// tocar un evento del cronograma). [actividadInicial] debe ser un código
/// del dropdown (`Abono1`, `Cosecha1`, …); ver [actividadDesdeEvento].
void showRegistrarTareaModal({
  required BuildContext context,
  required int cultivoId,
  required String plantaNombre,
  DateTime? fechaInicial,
  String? actividadInicial,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RegistrarTareaModal(
      cultivoId: cultivoId,
      plantaNombre: plantaNombre,
      fechaInicial: fechaInicial,
      actividadInicial: actividadInicial,
    ),
  );
}

/// Invierte el mapeo de eventos proyectados → código de actividad del
/// modal (alineado con `_actividadDescMap` / `_actividadTipoMap` del repo).
String? actividadDesdeEvento(Evento e) {
  final desc = e.descripcion.trim();
  // Prefijos más largos primero (p. ej. "Cosecha periódica" antes de "Cosecha").
  const porDesc = <(String, String)>[
    ('Cosecha periódica', 'Cosecha periódica'),
    ('Abono 1', 'Abono1'),
    ('Abono 2', 'Abono2'),
    ('Cosecha 1', 'Cosecha1'),
    ('Cosecha 2', 'Cosecha2'),
    ('Siembra', 'Siembra'),
    ('Semillero', 'Semillero'),
    ('Trasplante', 'Trasplante'),
    ('Desmalezada', 'Desmalezada'),
    ('Renovación', 'Renovación'),
    ('Riego', 'Riego'),
    ('Fumigación', 'Fumigación'),
  ];
  for (final (prefix, code) in porDesc) {
    if (desc == prefix ||
        desc.startsWith('$prefix ·') ||
        desc.startsWith('$prefix ')) {
      return code;
    }
  }
  return switch (e.tipo.toLowerCase()) {
    'siembra' => 'Siembra',
    'semillero' => 'Semillero',
    'trasplante' => 'Trasplante',
    'abono' => null, // ambiguo Abono1/Abono2 sin descripción
    'control_fito' => 'Desmalezada',
    'cosecha' => 'Cosecha1',
    'renovacion' => 'Renovación',
    'riego' => 'Riego',
    'poda' => null,
    _ => null,
  };
}

const _actividadesBaseComun = [
  'Riego', 'Abono1', 'Abono2', 'Desmalezada', 'Fumigación',
];
const _actividadesCicloUnico = ['Cosecha1', 'Cosecha2'];
const _actividadesPerenne = ['Cosecha periódica', 'Renovación'];
const _actividadesGerminador = ['Semillero', 'Trasplante'];

class _RegistrarTareaModal extends ConsumerStatefulWidget {
  const _RegistrarTareaModal({
    required this.cultivoId,
    required this.plantaNombre,
    this.fechaInicial,
    this.actividadInicial,
  });
  final int cultivoId;
  final String plantaNombre;
  final DateTime? fechaInicial;
  final String? actividadInicial;
  @override
  ConsumerState<_RegistrarTareaModal> createState() =>
      _RegistrarTareaModalState();
}

class _InsumoRow {
  _InsumoRow({this.desc, this.cantidad, this.unidad});
  String? desc;      // descripción del ítem en inventario
  String? cantidad;  // texto de cantidad
  String? unidad;    // código de unidad de display (ej. 'kg', 'gr', 'lb')
}

class _RegistrarTareaModalState extends ConsumerState<_RegistrarTareaModal> {
  late DateTime _fecha;
  final _hh = TextEditingController(text: '1');
  final _notas = TextEditingController();
  final _periodicidadCosecha = DuracionController();
  String? _act1;
  String? _act2;
  final List<_InsumoRow> _insumos = [];

  bool _periodicidadInicializada = false;

  @override
  void initState() {
    super.initState();
    _fecha = widget.fechaInicial ?? DateTime.now();
    _act1 = widget.actividadInicial;
  }

  @override
  void dispose() {
    _hh.dispose();
    _notas.dispose();
    _periodicidadCosecha.dispose();
    super.dispose();
  }

  bool _requierePeriodicidad(String? act) => act == 'Cosecha periódica';

  bool get _muestraPeriodicidad =>
      _requierePeriodicidad(_act1) || _requierePeriodicidad(_act2);

  @override
  Widget build(BuildContext context) {
    final plantas = ref.watch(plantasProvider);
    final activosList = ref.watch(cultivosActivosProvider);
    final cul = activosList.firstWhere(
        (c) => c.id == widget.cultivoId,
        orElse: () =>
            activosList.isNotEmpty ? activosList.first : throw StateError(''));
    final pl = plantas.firstWhere((p) => p.id == cul.plantaId,
        orElse: () => plantas.first);
    final esGerm = pl.metodoSiembra == 'germinador';
    final esPerenne = cul.esPerenne;
    if (!_periodicidadInicializada && cul.periodicidadCosechaDias != null) {
      _periodicidadInicializada = true;
      _periodicidadCosecha.setDias(cul.periodicidadCosechaDias);
    }
    final opts = <String>{
      ..._actividadesBaseComun,
      if (esPerenne) ..._actividadesPerenne else ..._actividadesCicloUnico,
      if (esGerm) ..._actividadesGerminador,
      'Siembra',
      if (_act1 != null) _act1!,
    }.toList();
    final act1Value = opts.contains(_act1) ? _act1 : null;

    final firstDate = DateTime(2020);
    final lastDate = DateTime.now().add(const Duration(days: 366));
    var pickerInitial = _fecha;
    if (pickerInitial.isBefore(firstDate)) pickerInitial = firstDate;
    if (pickerInitial.isAfter(lastDate)) pickerInitial = lastDate;

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Registrar tarea completada',
              style: Theme.of(context).textTheme.titleMedium),
          Text(widget.plantaNombre,
              style: TextStyle(color: Theme.of(context).hintColor)),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: pickerInitial,
                firstDate: firstDate,
                lastDate: lastDate,
              );
              if (d != null) setState(() => _fecha = d);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Fecha de la actividad',
                  suffixIcon: Icon(Icons.calendar_today),
                  border: OutlineInputBorder()),
              child: Text(
                  '${_fecha.year}-${_fecha.month.toString().padLeft(2, "0")}-${_fecha.day.toString().padLeft(2, "0")}'),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _hh,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: 'HH trabajadas',
                helperText: 'Se acumulan al total del cultivo',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: act1Value,
                decoration: const InputDecoration(
                    labelText: 'Actividad 1', border: OutlineInputBorder()),
                items: opts
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => setState(() => _act1 = v),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String?>(
                value: _act2,
                decoration: const InputDecoration(
                    labelText: 'Actividad 2 (opcional)',
                    border: OutlineInputBorder()),
                items: [
                  const DropdownMenuItem(value: null, child: Text('—')),
                  ...opts
                      .map((a) => DropdownMenuItem(value: a, child: Text(a))),
                ],
                onChanged: (v) => setState(() => _act2 = v),
              ),
            ),
          ]),
          if (_muestraPeriodicidad) ...[
            const SizedBox(height: 8),
            DuracionField(
              controller: _periodicidadCosecha,
              label: 'Periodicidad de cosecha',
              helperText:
                  'Se programan cosechas periódicas hasta el fin del ciclo de vida',
            ),
          ],
          const SizedBox(height: 12),
          // ============ INSUMOS ============
          const Text('Insumos usados',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          const SizedBox(height: 4),
          Consumer(builder: (ctx, ref, _) {
            final inv = ref.watch(inventoryProvider);
            final sistema = ref.watch(unitSystemProvider);
            final available =
                inv.where((i) => i.cantidad > 0).map((i) => i.desc).toList();
            return Column(
              children: [
                for (int idx = 0; idx < _insumos.length; idx++)
                  () {
                    final ins = _insumos[idx];
                    // Busca el item del inventario correspondiente (si existe)
                    InvItem? matched;
                    for (final it in inv) {
                      if (it.desc == ins.desc) { matched = it; break; }
                    }
                    // Unidad de display: la del sistema seleccionado, derivada de la unidad base del ítem
                    String unidadDisplay = '';
                    String helper = '';
                    if (matched != null) {
                      final disp = displayInSystem(
                          matched.cantidad, matched.unidad, sistema);
                      final dec = disp.value == disp.value.roundToDouble() ? 0 : 2;
                      unidadDisplay = disp.codigo;
                      helper = 'Disp: ${disp.value.toStringAsFixed(dec)} ${disp.codigo}';
                    }
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(children: [
                        Expanded(
                          flex: 3,
                          child: DropdownButtonFormField<String>(
                            value: ins.desc,
                            decoration: const InputDecoration(
                                labelText: 'Insumo',
                                border: OutlineInputBorder(),
                                contentPadding:
                                    EdgeInsets.symmetric(horizontal: 8)),
                            items: available
                                .map((d) => DropdownMenuItem(
                                    value: d,
                                    child: Text(d,
                                        overflow: TextOverflow.ellipsis)))
                                .toList(),
                            onChanged: (v) => setState(() {
                              ins.desc = v;
                              ins.unidad = null;   // se recalcula
                            }),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          flex: 2,
                          child: TextField(
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                                labelText: 'Cant',
                                helperText: helper,
                                border: const OutlineInputBorder(),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8),
                                suffixText: unidadDisplay.isEmpty
                                    ? null
                                    : unidadDisplay),
                            onChanged: (v) {
                              ins.cantidad = v;
                              // Guarda unidad display para conversión al guardar
                              ins.unidad = unidadDisplay;
                            },
                          ),
                        ),
                        IconButton(
                            icon: const Icon(Icons.close, color: Colors.red),
                            onPressed: () =>
                                setState(() => _insumos.removeAt(idx))),
                      ]),
                    );
                  }(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: available.isEmpty
                        ? null
                        : () => setState(() => _insumos.add(_InsumoRow())),
                    icon: const Icon(Icons.add_circle_outline, size: 18),
                    label: const Text('Agregar insumo'),
                  ),
                ),
                if (available.isEmpty)
                  Text('Sin insumos disponibles en inventario',
                      style: TextStyle(
                          fontSize: 11, color: Theme.of(context).hintColor)),
              ],
            );
          }),
          const SizedBox(height: 8),
          TextField(
            controller: _notas,
            decoration: const InputDecoration(
                labelText: 'Notas (opcional)', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: const Text('Guardar')),
          ]),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final acts = [_act1, _act2].whereType<String>().toList();
    if (acts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona al menos una actividad')));
      return;
    }
    if (_muestraPeriodicidad) {
      final p = _periodicidadCosecha.dias;
      if (p == null || p <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Indica la periodicidad de cosecha para «Cosecha periódica»')));
        return;
      }
    }
    final hh = double.tryParse(_hh.text) ?? 0;
    final mut = ref.read(dataMutationsProvider);
    // Convierte cada insumo a unidad base (persistimos en base para poder restaurar
    // al inventario si se borra la tarea).
    final insumosBase = <InsumoUsado>[];
    for (final ins in _insumos) {
      final cant = double.tryParse(ins.cantidad ?? '') ?? 0;
      if (ins.desc == null || cant <= 0) continue;
      final (baseVal, baseCode) = toBase(cant, ins.unidad ?? 'kg');
      insumosBase.add(InsumoUsado(
          desc: ins.desc!, cantidad: baseVal, unidad: baseCode));
    }
    await mut.registrarTarea(
      cultivoId: widget.cultivoId,
      fecha: _fecha,
      hh: hh,
      actividades: acts,
      insumos: insumosBase,
      notas: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
      periodicidadCosechaDias:
          _muestraPeriodicidad ? _periodicidadCosecha.dias : null,
    );
    // Descuenta cada insumo del inventario (en unidad base ya convertida)
    for (final ins in insumosBase) {
      await mut.consumeInventoryBase(
          descripcion: ins.desc, cantidadBase: ins.cantidad);
    }
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Tarea registrada · +${hh}h · ${acts.join(", ")}'
          '${insumosBase.isNotEmpty ? " · ${insumosBase.length} insumo(s) descontados" : ""}'),
    ));
  }
}
