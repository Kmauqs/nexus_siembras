import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import '../../core/reports/adjunto_viewer.dart';
import '../../core/reports/compras_zip_export.dart';
import '../../core/reports/export_helpers.dart';
import '../../core/reports/report_data_builder.dart';
import '../../core/units/units_catalog.dart';
import '../../core/widgets/acceso_denegado.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/autor_label.dart';
import '../../core/widgets/unit_dropdown.dart';
import '../../services/soporte_service.dart';
import '../../state/app_state.dart';
import '../../state/data_state.dart';

class PurchasesScreen extends ConsumerWidget {
  const PurchasesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final permisos = ref.watch(permisosPredioActivoProvider);
    if (!permisos.puedeVerCompras) {
      return const AppShell(
        title: 'Compras',
        child: AccesoDenegado(
          icono: Icons.lock_outline,
          mensaje: 'Las compras del predio solo están disponibles para '
              'usuarios con rol Propietario (dueño o co-propietario invitado).',
        ),
      );
    }
    final compras = ref.watch(comprasProvider);
    final puedeEditar = permisos.puedeEditarCompras;
    return AppShell(
      title: 'Compras',
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                if (puedeEditar) ...[
                  FilledButton.icon(
                    onPressed: () => _showEditModal(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Nueva compra'),
                  ),
                  const SizedBox(width: 8),
                ],
                ExportButtons(onExport: (fmt) => _exportar(context, ref, fmt)),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _exportarZip(context, ref),
                  icon: const Icon(Icons.folder_zip_outlined, size: 18),
                  label: const Text('ZIP completo'),
                ),
              ]),
            ),
          ),
          Expanded(
            child: compras.isEmpty
                ? const Center(child: Text('Sin compras registradas'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: compras.length,
                    itemBuilder: (_, i) => _CompraTile(
                      item: compras[i],
                      onEdit: puedeEditar
                          ? () => _showEditModal(context, ref, compras[i])
                          : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  static void _showEditModal(BuildContext ctx, WidgetRef ref, Compra? existing) {
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _NuevaCompraModal(existing: existing),
    );
  }

  /// Exportación CSV/PDF de compras (recolección centralizada).
  static Future<void> _exportar(
      BuildContext context, WidgetRef ref, String fmt) async {
    final t = buildComprasReporte(ref);
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

  /// Paquete ZIP: reporte completo (PDF+CSV) + comprobantes adjuntos.
  static Future<void> _exportarZip(
      BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Generando paquete ZIP…'),
      duration: Duration(seconds: 2),
    ));
    try {
      final zip = await exportComprasPaqueteZip(ref);
      if (!context.mounted) return;
      await SharePlus.instance.share(ShareParams(
        files: [XFile(zip.path, mimeType: 'application/zip')],
        subject: 'Compras — reporte completo',
        text: 'Paquete con reporte PDF/CSV y facturas adjuntas.',
      ));
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text('ZIP generado: ${zip.path}'),
        duration: const Duration(seconds: 6),
      ));
    } catch (e) {
      if (!context.mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Error al generar ZIP: $e')));
    }
  }
}

class _NuevaCompraModal extends ConsumerStatefulWidget {
  const _NuevaCompraModal({this.existing});
  final Compra? existing;
  @override
  ConsumerState<_NuevaCompraModal> createState() => _NuevaCompraModalState();
}

class _NuevaCompraModalState extends ConsumerState<_NuevaCompraModal> {
  late final _fecha = TextEditingController(
      text: widget.existing?.fecha ?? DateTime.now().toIso8601String().substring(0, 10));
  late final _desc = TextEditingController(text: widget.existing?.desc ?? '');
  late final _desc2 = TextEditingController(text: widget.existing?.desc2 ?? '');
  late final _valor = TextEditingController(text: widget.existing?.valor.toStringAsFixed(0) ?? '');
  late final _cantidad = TextEditingController(text: widget.existing?.cantidad.toString() ?? '');
  late final _cod = TextEditingController(text: widget.existing?.cod ?? '');
  late final _factura = TextEditingController(text: widget.existing?.factura ?? '');
  late final _proveedor = TextEditingController(text: widget.existing?.proveedor ?? '');
  late String _unidad = widget.existing?.unidad ?? 'kg';
  late String _tipo = widget.existing?.tipo ?? 'semilla';
  late String? _soporteName = widget.existing?.soporteName;

  @override
  Widget build(BuildContext context) {
    final knownNames = ref.watch(knownProductNamesProvider);
    final knownProveedores = ref.watch(proveedoresProvider);
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          Text(widget.existing == null ? 'Nueva compra' : 'Editar compra #${widget.existing!.id}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Campos según tabla REGCOMPRAS del Excel base.',
              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          const SizedBox(height: 12),

          InkWell(
            onTap: () async {
              final actual = DateTime.tryParse(_fecha.text) ?? DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: actual,
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 30)),
              );
              if (picked != null) {
                setState(() {
                  _fecha.text =
                      '${picked.year}-${picked.month.toString().padLeft(2, "0")}-${picked.day.toString().padLeft(2, "0")}';
                });
              }
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                  labelText: 'Fecha',
                  suffixIcon: Icon(Icons.calendar_today),
                  border: OutlineInputBorder()),
              child: Text(_fecha.text),
            ),
          ),
          const SizedBox(height: 8),

          // Descripción 1: Autocomplete con nombres conocidos
          Autocomplete<String>(
            optionsBuilder: (te) {
              if (te.text.isEmpty) return knownNames;
              return knownNames.where(
                  (n) => n.toLowerCase().contains(te.text.toLowerCase()));
            },
            initialValue: TextEditingValue(text: _desc.text),
            fieldViewBuilder: (ctx, controller, focus, onSubmit) {
              controller.text = _desc.text;
              controller.addListener(() => _desc.text = controller.text);
              return TextField(
                controller: controller,
                focusNode: focus,
                decoration: const InputDecoration(
                  labelText: 'Descripción 1 *',
                  hintText: 'Elegir de la lista o escribir nueva',
                  suffixIcon: Icon(Icons.arrow_drop_down),
                  border: OutlineInputBorder(),
                ),
              );
            },
            onSelected: (v) => _desc.text = v,
          ),
          const SizedBox(height: 4),
          Text('💡 Elige un nombre existente para consolidar el ítem en inventario, '
              'o escribe uno nuevo. La compra actualiza automáticamente el inventario.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          const SizedBox(height: 8),

          TextField(
            controller: _desc2,
            decoration: const InputDecoration(
                labelText: 'Descripción 2 (opcional)',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),

          Row(children: [
            Expanded(
              child: TextField(
                controller: _valor,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Valor', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _cantidad,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Cantidad', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: UnitDropdown(
                value: _unidad,
                onChanged: (v) => setState(() => _unidad = v ?? 'kg'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _cod,
                decoration: const InputDecoration(
                    labelText: 'Código', border: OutlineInputBorder()),
              ),
            ),
          ]),
          _ConversionHint(cantidadCtrl: _cantidad, unidad: _unidad),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _factura,
                decoration: const InputDecoration(
                    labelText: 'Factura', border: OutlineInputBorder()),
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
                initialValue: TextEditingValue(text: _proveedor.text),
                fieldViewBuilder: (ctx, controller, focus, onSubmit) {
                  controller.text = _proveedor.text;
                  controller.addListener(() => _proveedor.text = controller.text);
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
                onSelected: (v) => _proveedor.text = v,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _tipo,
            decoration: const InputDecoration(
                labelText: 'Tipo de insumo', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'semilla', child: Text('Semilla')),
              DropdownMenuItem(value: 'abono', child: Text('Abono')),
              DropdownMenuItem(value: 'pesticida', child: Text('Pesticida')),
              DropdownMenuItem(value: 'herramienta', child: Text('Herramienta')),
              DropdownMenuItem(value: 'servicio', child: Text('Servicio')),
              DropdownMenuItem(value: 'otro', child: Text('Otro')),
            ],
            onChanged: (v) => setState(() => _tipo = v ?? 'semilla'),
          ),
          const SizedBox(height: 12),
          // Adjuntar comprobante real (2026-07-20). El archivo se copia a
          // Documents/soportes/{año}/{Proveedor}-{factura}.{ext} y el path
          // queda en compras.soportePath.
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _adjuntarComprobante,
                icon: const Icon(Icons.attach_file),
                label: Text(
                  _soporteName == null
                      ? 'Adjuntar comprobante (PDF/foto)'
                      : p.basename(_soporteName!),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (_soporteName != null)
              IconButton(
                tooltip: 'Quitar comprobante',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() => _soporteName = null),
              ),
          ]),
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

  /// Selección del comprobante: PDF, foto de galería o cámara (móvil).
  /// Nombre destino: {Proveedor}-{factura}; año tomado de la fecha de la
  /// compra para que el archivo caiga en la subcarpeta del año correcto.
  Future<void> _adjuntarComprobante() async {
    final anio =
        DateTime.tryParse(_fecha.text)?.year ?? DateTime.now().year;
    final srv = SoporteService.instance;
    final proveedor = _proveedor.text.trim().isEmpty
        ? 'SIN_PROVEEDOR'
        : _proveedor.text.trim();
    final factura = _factura.text.trim().isEmpty
        ? 'SF${DateTime.now().millisecondsSinceEpoch % 100000}'
        : _factura.text.trim();
    final nombreBase = '${srv.sanitizar(proveedor)}-${srv.sanitizar(factura)}';
    final esMovil = Platform.isAndroid || Platform.isIOS;

    final opcion = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.picture_as_pdf),
            title: const Text('Archivo PDF'),
            onTap: () => Navigator.pop(ctx, 'pdf'),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Foto de la galería'),
            onTap: () => Navigator.pop(ctx, 'galeria'),
          ),
          if (esMovil)
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Tomar foto'),
              onTap: () => Navigator.pop(ctx, 'camara'),
            ),
        ]),
      ),
    );
    if (opcion == null) return;
    try {
      final String? path;
      switch (opcion) {
        case 'pdf':
          path = await srv.adjuntarPdf(anio: anio, nombreBase: nombreBase);
        case 'camara':
          path = await srv.adjuntarFoto(
              anio: anio, nombreBase: nombreBase, desdeCamara: true);
        default:
          path = await srv.adjuntarFoto(
              anio: anio, nombreBase: nombreBase, desdeCamara: false);
      }
      if (path != null && mounted) {
        setState(() => _soporteName = path);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo adjuntar: $e')));
    }
  }

  Future<void> _save() async {
    if (_desc.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La Descripción 1 es requerida')));
      return;
    }
    final cantidad = double.tryParse(_cantidad.text) ?? 0;
    final valor = double.tryParse(_valor.text) ?? 0;
    final mut = ref.read(dataMutationsProvider);
    final desc2 = _desc2.text.trim().isEmpty ? null : _desc2.text.trim();
    if (widget.existing == null) {
      await mut.addCompra(
        fecha: _fecha.text, desc: _desc.text.trim(), desc2: desc2,
        valor: valor, cantidad: cantidad, unidad: _unidad,
        cod: _cod.text.trim(), factura: _factura.text.trim(),
        proveedor: _proveedor.text.trim(), tipo: _tipo,
        soporteName: _soporteName,
      );
    } else {
      await mut.updateCompra(
        id: widget.existing!.id,
        fecha: _fecha.text, desc: _desc.text.trim(), desc2: desc2,
        valor: valor, cantidad: cantidad, unidad: _unidad,
        cod: _cod.text.trim(), factura: _factura.text.trim(),
        proveedor: _proveedor.text.trim(), tipo: _tipo,
        soporteName: _soporteName,
      );
    }
    if (!mounted) return;
    Navigator.pop(context);
    final isConsumible = const ['semilla', 'abono', 'pesticida'].contains(_tipo);
    final msg = widget.existing == null
        ? (isConsumible ? 'Compra guardada y agregada al inventario' : 'Compra guardada')
        : (isConsumible ? 'Compra actualizada · inventario ajustado' : 'Compra actualizada');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

class _CompraTile extends ConsumerWidget {
  const _CompraTile({required this.item, required this.onEdit});
  final Compra item;
  /// null = usuario sin permiso de edición → oculta el botón editar.
  final VoidCallback? onEdit;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sistema = ref.watch(unitSystemProvider);
    final disp = displayInSystem(item.cantidad, item.unidad, sistema);
    final dec = disp.value == disp.value.roundToDouble() ? 0 : 2;
    return Card(
      child: ListTile(
        title: Text(item.desc,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (item.desc2 != null)
              Text(item.desc2!,
                  style: TextStyle(color: Theme.of(context).hintColor)),
            Text('${item.proveedor} · ${item.factura} · ${item.fecha}'),
            if (item.createdByUserId != null &&
                item.createdByUserId!.isNotEmpty)
              AutorLabel(
                userId: item.createdByUserId!,
                prefix: 'Registrada por: ',
              ),
            Row(children: [
              _TipoChip(tipo: item.tipo),
              if (item.soporteName != null) ...[
                const SizedBox(width: 6),
                // B8: tocar el nombre abre el comprobante (PDF/imagen).
                Flexible(
                  child: InkWell(
                    onTap: () => abrirAdjunto(context, item.soporteName!),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.attach_file,
                          size: 14, color: Colors.teal),
                      Flexible(
                        child: Text(p.basename(item.soporteName!),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 11,
                                color: Colors.teal,
                                decoration: TextDecoration.underline)),
                      ),
                    ]),
                  ),
                ),
              ],
            ]),
          ],
        ),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text('\$ ${item.valor.toStringAsFixed(0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('${disp.value.toStringAsFixed(dec)} ${disp.codigo}',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
            ],
          ),
          if (onEdit != null)
            IconButton(icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
        ]),
        isThreeLine: true,
      ),
    );
  }
}

/// Muestra bajo la fila de cantidad+unidad la conversión a unidad base SI.
/// Ej: "= 25 kg" cuando el usuario ingresa "1 bulto50".
class _ConversionHint extends StatefulWidget {
  const _ConversionHint({required this.cantidadCtrl, required this.unidad});
  final TextEditingController cantidadCtrl;
  final String unidad;
  @override
  State<_ConversionHint> createState() => _ConversionHintState();
}

class _ConversionHintState extends State<_ConversionHint> {
  @override
  void initState() {
    super.initState();
    widget.cantidadCtrl.addListener(_update);
  }

  @override
  void dispose() {
    widget.cantidadCtrl.removeListener(_update);
    super.dispose();
  }

  void _update() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final cant = double.tryParse(widget.cantidadCtrl.text) ?? 0;
    final (baseVal, baseCode) = toBase(cant, widget.unidad);
    if (widget.unidad == baseCode || cant == 0) return const SizedBox(height: 4);
    final dec = baseVal == baseVal.roundToDouble() ? 0 : 3;
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Text('= ${baseVal.toStringAsFixed(dec)} $baseCode (guardado como unidad base)',
          style: TextStyle(fontSize: 11,
              color: Theme.of(context).colorScheme.primary,
              fontStyle: FontStyle.italic)),
    );
  }
}

class _TipoChip extends StatelessWidget {
  const _TipoChip({required this.tipo});
  final String tipo;
  static const _colors = <String, Color>{
    'semilla':     Color(0xFF1B7A3E),
    'abono':       Color(0xFF8B6F47),
    'pesticida':   Color(0xFFB91C1C),
    'herramienta': Color(0xFF2563EB),
    'servicio':    Color(0xFF7C3AED),
    'otro':        Color(0xFF6B7280),
  };
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: _colors[tipo] ?? _colors['otro']!,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(tipo,
            style: const TextStyle(
                color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
      );
}
