import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/inventory/inventory_categories.dart';
import '../../core/reports/export_helpers.dart';
import '../../core/reports/report_data_builder.dart';
import '../../core/units/units_catalog.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/unit_dropdown.dart';
import '../../state/app_state.dart';
import '../../state/data_state.dart';

class InventoryScreen extends ConsumerWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inv = ref.watch(inventoryProvider);
    final permisos = ref.watch(permisosPredioActivoProvider);
    final puedeEditar = permisos.puedeEditarInventario;

    return AppShell(
      title: 'Inventario',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            if (puedeEditar) ...[
              FilledButton.icon(
                onPressed: () => _showEditModal(context, ref, null),
                icon: const Icon(Icons.add),
                label: const Text('Nuevo'),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ExportButtons(
                    onExport: (fmt) => _exportar(context, ref, fmt)),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          if (inv.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text('Sin ítems en inventario',
                    style: TextStyle(color: Colors.grey)),
              ),
            )
          else
            ...InventoryCategories.all.map((cat) {
              final seccion = inv.where((i) {
                final c = i.categoria ?? InventoryCategories.insumos;
                return c == cat;
              }).toList();
              final activos =
                  seccion.where((i) => i.cantidad > 0).toList();
              final agotados =
                  seccion.where((i) => i.cantidad <= 0).toList();
              return _CategoriaSection(
                categoria: cat,
                activos: activos,
                agotados: agotados,
                puedeEditar: puedeEditar,
                onEdit: (it) => _showEditModal(context, ref, it),
              );
            }),
        ],
      ),
    );
  }

  static void _showEditModal(BuildContext ctx, WidgetRef ref, InvItem? existing) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _InvEditModal(existing: existing),
    );
  }

  static Future<void> _exportar(
      BuildContext context, WidgetRef ref, String fmt) async {
    final t = buildInventarioReporte(ref);
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

class _CategoriaSection extends StatelessWidget {
  const _CategoriaSection({
    required this.categoria,
    required this.activos,
    required this.agotados,
    required this.puedeEditar,
    required this.onEdit,
  });

  final String categoria;
  final List<InvItem> activos;
  final List<InvItem> agotados;
  final bool puedeEditar;
  final void Function(InvItem) onEdit;

  @override
  Widget build(BuildContext context) {
    final total = activos.length + agotados.length;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        initiallyExpanded: total > 0,
        title: Text(
          '${InventoryCategories.label(categoria)} ($total)',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          InventoryCategories.hints[categoria] ?? '',
          style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
        ),
        children: [
          if (total == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('Sin ítems en esta categoría',
                  style: TextStyle(color: Theme.of(context).hintColor)),
            )
          else ...[
            if (activos.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Text('Disponibles (${activos.length})',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              ...activos.map((it) => _InvTile(
                    item: it,
                    onEdit: puedeEditar ? () => onEdit(it) : null,
                  )),
            ],
            if (agotados.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Agotados (${agotados.length})',
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(color: Colors.grey)),
              ),
              ...agotados.map((it) => _InvTile(
                    item: it,
                    onEdit: puedeEditar ? () => onEdit(it) : null,
                    agotado: true,
                  )),
            ],
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

class _InvEditModal extends ConsumerStatefulWidget {
  const _InvEditModal({this.existing});
  final InvItem? existing;
  @override
  ConsumerState<_InvEditModal> createState() => _InvEditModalState();
}

class _InvEditModalState extends ConsumerState<_InvEditModal> {
  late final _desc = TextEditingController(text: widget.existing?.desc ?? '');
  late final _cod = TextEditingController(text: widget.existing?.cod ?? '');
  late final _cant =
      TextEditingController(text: widget.existing?.cantidad.toString() ?? '');
  late final _fab =
      TextEditingController(text: widget.existing?.fabricante ?? '');
  late final _ubicacion =
      TextEditingController(text: widget.existing?.ubicacion ?? '');
  late String _unidad = widget.existing?.unidad ?? 'kg';
  late String _categoria =
      widget.existing?.categoria ?? InventoryCategories.insumos;
  late String? _grado = widget.existing?.gradoPoscosecha;

  @override
  void dispose() {
    _desc.dispose();
    _cod.dispose();
    _cant.dispose();
    _fab.dispose();
    _ubicacion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final knownProveedores = ref.watch(proveedoresProvider);
    final esHerramientas =
        _categoria == InventoryCategories.herramientasEquipos;
    final esPoscosecha = _categoria == InventoryCategories.poscosecha;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                widget.existing == null
                    ? 'Nuevo ítem'
                    : 'Editar #${widget.existing!.cod}',
                style:
                    const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _categoria,
              decoration: const InputDecoration(
                  labelText: 'Categoría', border: OutlineInputBorder()),
              items: InventoryCategories.all
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(InventoryCategories.label(c)),
                      ))
                  .toList(),
              onChanged: (v) => setState(() {
                _categoria = v ?? InventoryCategories.insumos;
                if (_categoria != InventoryCategories.poscosecha) {
                  _grado = null;
                } else {
                  _grado ??= GradosPoscosecha.primera;
                }
              }),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(
                  labelText: 'Descripción', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cod,
                  decoration: const InputDecoration(
                      labelText: 'Código', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Autocomplete<String>(
                  optionsBuilder: (te) {
                    if (te.text.isEmpty) return knownProveedores;
                    return knownProveedores.where(
                        (n) => n.toLowerCase().contains(te.text.toLowerCase()));
                  },
                  initialValue: TextEditingValue(text: _fab.text),
                  fieldViewBuilder: (ctx, controller, focus, onSubmit) {
                    controller.text = _fab.text;
                    controller.addListener(() => _fab.text = controller.text);
                    return TextField(
                      controller: controller,
                      focusNode: focus,
                      decoration: const InputDecoration(
                        labelText: 'Proveedor',
                        hintText: 'Elegir o escribir nuevo',
                        suffixIcon: Icon(Icons.arrow_drop_down),
                        border: OutlineInputBorder(),
                      ),
                    );
                  },
                  onSelected: (v) => _fab.text = v,
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _cant,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Cantidad', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: UnitDropdown(
                  value: _unidad,
                  onChanged: (v) => setState(() => _unidad = v ?? 'kg'),
                  dimensions: esPoscosecha ? const ['peso'] : null,
                ),
              ),
            ]),
            if (esHerramientas) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _ubicacion,
                decoration: const InputDecoration(
                  labelText: 'Ubicación actual',
                  hintText: 'Ej. Bodega, tractor, lote 3…',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
            if (esPoscosecha) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _grado ?? GradosPoscosecha.primera,
                decoration: const InputDecoration(
                    labelText: 'Clasificación', border: OutlineInputBorder()),
                items: GradosPoscosecha.all
                    .map((g) => DropdownMenuItem(
                          value: g,
                          child: Text(GradosPoscosecha.label(g)),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _grado = v),
              ),
            ],
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  final cant = double.tryParse(_cant.text) ?? 0;
                  final mut = ref.read(dataMutationsProvider);
                  final ubic = esHerramientas
                      ? (_ubicacion.text.trim().isEmpty
                          ? null
                          : _ubicacion.text.trim())
                      : null;
                  final grado = esPoscosecha ? _grado : null;
                  if (widget.existing == null) {
                    await mut.addOrIncrementInventory(
                      descripcion: _desc.text.trim(),
                      cantidad: cant,
                      unidad: _unidad,
                      codigo: _cod.text.trim(),
                      fabricante: _fab.text.trim(),
                      categoria: _categoria,
                      ubicacion: ubic,
                      gradoPoscosecha: grado,
                    );
                  } else {
                    await mut.updateInventoryFields(
                      id: widget.existing!.id,
                      descripcion: _desc.text.trim(),
                      codigo: _cod.text.trim(),
                      fabricante: _fab.text.trim(),
                      cantidadBase: cant,
                      unidadBase: _unidad,
                      categoria: _categoria,
                      ubicacion: ubic ?? '',
                      gradoPoscosecha: grado ?? '',
                    );
                  }
                  if (!mounted) return;
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Guardado')));
                },
                child: const Text('Guardar'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _InvTile extends ConsumerWidget {
  const _InvTile({required this.item, required this.onEdit, this.agotado = false});
  final InvItem item;
  final VoidCallback? onEdit;
  final bool agotado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proveedoresMap = ref.watch(proveedoresPorItemProvider);
    final proveedores =
        proveedoresMap[item.desc.trim().toLowerCase()] ?? const <String>[];
    final meta = <String>[];
    if (item.ubicacion != null && item.ubicacion!.isNotEmpty) {
      meta.add('📍 ${item.ubicacion}');
    }
    if (item.gradoPoscosecha != null && item.gradoPoscosecha!.isNotEmpty) {
      meta.add(GradosPoscosecha.label(item.gradoPoscosecha));
    }
    return Opacity(
      opacity: agotado ? 0.5 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Material(
          color: agotado ? Colors.grey.shade100 : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.desc,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                decoration: agotado
                                    ? TextDecoration.lineThrough
                                    : null)),
                        Text(
                            [
                              if (item.cod.isNotEmpty) item.cod,
                              item.fecha,
                              ...meta,
                            ].join(' · '),
                            style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).hintColor)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Builder(builder: (_) {
                        final sistema = ref.watch(unitSystemProvider);
                        final disp = displayInSystem(
                            item.cantidad, item.unidad, sistema);
                        int dec;
                        final abs = disp.value.abs();
                        if (disp.value == disp.value.roundToDouble()) {
                          dec = 0;
                        } else if (abs < 0.01) {
                          dec = 4;
                        } else if (abs < 1) {
                          dec = 3;
                        } else if (abs < 100) {
                          dec = 2;
                        } else {
                          dec = 1;
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(disp.value.toStringAsFixed(dec),
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: agotado ? Colors.red : null)),
                            Text(disp.codigo,
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Theme.of(context).hintColor)),
                          ],
                        );
                      }),
                    ],
                  ),
                  if (onEdit != null)
                    IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: onEdit),
                  if (onEdit != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => ref
                          .read(dataMutationsProvider)
                          .deleteInventoryItem(item.id),
                    ),
                ]),
                const SizedBox(height: 4),
                if (proveedores.isEmpty &&
                    (item.fabricante == null || item.fabricante!.isEmpty))
                  Text('Sin proveedor registrado',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).hintColor,
                          fontStyle: FontStyle.italic))
                else
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      ...proveedores.map((p) => _ProvChip(nombre: p)),
                      if (item.fabricante != null &&
                          item.fabricante!.trim().isNotEmpty &&
                          !proveedores
                              .map((e) => e.toLowerCase())
                              .contains(
                                  item.fabricante!.trim().toLowerCase()))
                        _ProvChip(nombre: item.fabricante!),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProvChip extends StatelessWidget {
  const _ProvChip({required this.nombre});
  final String nombre;
  @override
  Widget build(BuildContext c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(c).colorScheme.primary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: Theme.of(c).colorScheme.primary.withOpacity(0.3),
              width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront,
                size: 12, color: Theme.of(c).colorScheme.primary),
            const SizedBox(width: 4),
            Text(nombre,
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(c).colorScheme.primary,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
