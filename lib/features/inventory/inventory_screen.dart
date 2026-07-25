import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final activos = inv.where((i) => i.cantidad > 0).toList();
    final agotados = inv.where((i) => i.cantidad <= 0).toList();
    // Consultor: solo lectura. Se oculta "Nuevo" y los íconos edit/eliminar
    // por tile. Los exports CSV/PDF sí siguen visibles (son solo consumo).
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
            ExportButtons(onExport: (fmt) => _exportar(context, ref, fmt)),
          ]),
          const SizedBox(height: 12),
          if (activos.isEmpty && agotados.isEmpty)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: Text('Sin ítems en inventario',
                    style: TextStyle(color: Colors.grey)),
              ),
            ),
          if (activos.isNotEmpty) ...[
            Text('📦 Disponibles (${activos.length})',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            ...activos.map((it) => _InvTile(
                  item: it,
                  onEdit: puedeEditar
                      ? () => _showEditModal(context, ref, it)
                      : null,
                )),
          ],
          if (agotados.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('⚠ Agotados (${agotados.length})',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: Colors.grey)),
            const SizedBox(height: 6),
            ...agotados.map((it) => _InvTile(
                  item: it,
                  onEdit: puedeEditar
                      ? () => _showEditModal(context, ref, it)
                      : null,
                  agotado: true,
                )),
          ],
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

  /// Exportación CSV/PDF del inventario (recolección centralizada).
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

class _InvEditModal extends ConsumerStatefulWidget {
  const _InvEditModal({this.existing});
  final InvItem? existing;
  @override
  ConsumerState<_InvEditModal> createState() => _InvEditModalState();
}

class _InvEditModalState extends ConsumerState<_InvEditModal> {
  late final _desc = TextEditingController(text: widget.existing?.desc ?? '');
  late final _cod = TextEditingController(text: widget.existing?.cod ?? '');
  late final _cant = TextEditingController(text: widget.existing?.cantidad.toString() ?? '');
  late final _fab = TextEditingController(text: widget.existing?.fabricante ?? '');
  late String _unidad = widget.existing?.unidad ?? 'kg';

  @override
  Widget build(BuildContext context) {
    final knownProveedores = ref.watch(proveedoresProvider);
    return Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Nuevo ítem' : 'Editar #${widget.existing!.cod}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
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
                ),
              ),
            ]),
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
                  if (widget.existing == null) {
                    await mut.addOrIncrementInventory(
                      descripcion: _desc.text.trim(),
                      cantidad: cant,
                      unidad: _unidad,
                      codigo: _cod.text.trim(),
                      fabricante: _fab.text.trim(),
                    );
                  } else {
                    // Update parcial por ID — persiste todos los campos editados.
                    await mut.updateInventoryFields(
                      id: widget.existing!.id,
                      descripcion: _desc.text.trim(),
                      codigo: _cod.text.trim(),
                      fabricante: _fab.text.trim(),
                      cantidadBase: cant,
                      unidadBase: _unidad,
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
      );
  }
}

class _InvTile extends ConsumerWidget {
  const _InvTile({required this.item, required this.onEdit, this.agotado = false});
  final InvItem item;
  /// null = consultor / sin permiso de edición → oculta botones edit/delete.
  final VoidCallback? onEdit;
  final bool agotado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final proveedoresMap = ref.watch(proveedoresPorItemProvider);
    final proveedores = proveedoresMap[item.desc.trim().toLowerCase()] ?? const <String>[];
    return Opacity(
      opacity: agotado ? 0.5 : 1.0,
      child: Card(
        color: agotado ? Colors.grey.shade100 : null,
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
                              decoration: agotado ? TextDecoration.lineThrough : null)),
                      Text('${item.cod} · ${item.fecha}',
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
                      final disp = displayInSystem(item.cantidad, item.unidad, sistema);
                      // Escala de decimales según magnitud: valores pequeños necesitan
                      // más precisión para no aparecer como 0.00.
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
                  IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
                if (onEdit != null)
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () =>
                        ref.read(dataMutationsProvider).deleteInventoryItem(item.id),
                  ),
              ]),
              const SizedBox(height: 4),
              // Chips de proveedores agregados (desde compras)
              if (proveedores.isEmpty && (item.fabricante == null || item.fabricante!.isEmpty))
                Text('Sin proveedor registrado',
                    style: TextStyle(
                        fontSize: 11, color: Theme.of(context).hintColor,
                        fontStyle: FontStyle.italic))
              else
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    ...proveedores.map((p) => _ProvChip(nombre: p)),
                    // Si el ítem tiene fabricante en Drift pero NO aparece en compras (ítem creado
                    // manualmente en inventario, no vía compra), muéstralo también.
                    if (item.fabricante != null &&
                        item.fabricante!.trim().isNotEmpty &&
                        !proveedores.map((e) => e.toLowerCase())
                            .contains(item.fabricante!.trim().toLowerCase()))
                      _ProvChip(nombre: item.fabricante!),
                  ],
                ),
            ],
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
              color: Theme.of(c).colorScheme.primary.withOpacity(0.3), width: 1),
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
