import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/reports/export_helpers.dart';
import '../../core/reports/report_data_builder.dart';
import '../../core/widgets/app_shell.dart';
import '../../state/data_state.dart';

class SuppliersScreen extends ConsumerWidget {
  const SuppliersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncProvs = ref.watch(proveedoresDriftProvider);
    return AppShell(
      title: 'Proveedores',
      child: asyncProvs.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (provs) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  FilledButton.icon(
                    onPressed: () => _openEditor(context, ref, null),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo proveedor'),
                  ),
                  const SizedBox(width: 8),
                  ExportButtons(
                      onExport: (fmt) => _exportar(context, ref, fmt)),
                ]),
              ),
            ),
            Expanded(
              child: provs.isEmpty
                  ? const Center(child: Text('Sin proveedores'))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: provs.length,
                      itemBuilder: (_, i) => _ProvCard(
                        p: provs[i],
                        onEdit: () => _openEditor(context, ref, provs[i]),
                        onDelete: () => _confirmDelete(context, ref, provs[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  /// Exportación CSV/PDF de proveedores (recolección centralizada).
  Future<void> _exportar(
      BuildContext context, WidgetRef ref, String fmt) async {
    final t = await buildProveedoresReporte(ref);
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

  Future<void> _openEditor(
      BuildContext context, WidgetRef ref, dynamic existing) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ProveedorEditor(existing: existing),
    );
    if (result == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(existing == null
              ? 'Proveedor creado'
              : 'Proveedor actualizado')));
    }
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, dynamic p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Eliminar proveedor'),
        content: Text(
            '¿Enviar "${p.nombre}" a la papelera? Se puede restaurar más tarde.'),
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
      await ref.read(dataMutationsProvider).deleteProveedor(p.id as int);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Proveedor eliminado')));
      }
    }
  }
}

class _ProvCard extends StatelessWidget {
  const _ProvCard({required this.p, required this.onEdit, required this.onDelete});
  final dynamic p; // drift.Proveedore
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(p.nombre as String,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              IconButton(
                  icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
              IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: onDelete),
            ]),
            if (p.nit != null ||
                p.telefono != null ||
                p.web != null ||
                p.direccion != null ||
                p.email != null)
              const Divider(),
            if (p.nit != null) _row('NIT', p.nit as String),
            if (p.telefono != null) _row('Teléfono', p.telefono as String),
            if (p.email != null) _row('Email', p.email as String),
            if (p.web != null) _row('Web', p.web as String),
            if (p.direccion != null) _row('Dirección', p.direccion as String),
            if (p.notas != null) _row('Notas', p.notas as String),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(
                width: 90,
                child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v)),
          ],
        ),
      );
}

class _ProveedorEditor extends ConsumerStatefulWidget {
  const _ProveedorEditor({this.existing});
  final dynamic existing;

  @override
  ConsumerState<_ProveedorEditor> createState() => _ProveedorEditorState();
}

class _ProveedorEditorState extends ConsumerState<_ProveedorEditor> {
  late final TextEditingController _nombre;
  late final TextEditingController _nit;
  late final TextEditingController _telefono;
  late final TextEditingController _email;
  late final TextEditingController _web;
  late final TextEditingController _direccion;
  late final TextEditingController _notas;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nombre = TextEditingController(text: e?.nombre ?? '');
    _nit = TextEditingController(text: e?.nit ?? '');
    _telefono = TextEditingController(text: e?.telefono ?? '');
    _email = TextEditingController(text: e?.email ?? '');
    _web = TextEditingController(text: e?.web ?? '');
    _direccion = TextEditingController(text: e?.direccion ?? '');
    _notas = TextEditingController(text: e?.notas ?? '');
  }

  @override
  void dispose() {
    _nombre.dispose();
    _nit.dispose();
    _telefono.dispose();
    _email.dispose();
    _web.dispose();
    _direccion.dispose();
    _notas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEdit ? 'Editar proveedor' : 'Nuevo proveedor',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _nombre,
              decoration: const InputDecoration(
                  labelText: 'Nombre *', border: OutlineInputBorder()),
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _nit,
                  decoration: const InputDecoration(
                      labelText: 'NIT / RUT', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _telefono,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                      labelText: 'Teléfono', border: OutlineInputBorder()),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Email', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _web,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                  labelText: 'Web',
                  hintText: 'https://…',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _direccion,
              decoration: const InputDecoration(
                  labelText: 'Dirección', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _notas,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Notas', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.pop(context, false),
                  child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(isEdit ? 'Guardar' : 'Crear'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  String? _n(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El nombre es obligatorio')));
      return;
    }
    setState(() => _saving = true);
    try {
      final mut = ref.read(dataMutationsProvider);
      if (widget.existing == null) {
        await mut.addProveedor(
          nombre: nombre,
          nit: _n(_nit),
          telefono: _n(_telefono),
          email: _n(_email),
          web: _n(_web),
          direccion: _n(_direccion),
          notas: _n(_notas),
        );
      } else {
        await mut.updateProveedor(
          id: widget.existing.id as int,
          nombre: nombre,
          nit: _n(_nit),
          telefono: _n(_telefono),
          email: _n(_email),
          web: _n(_web),
          direccion: _n(_direccion),
          notas: _n(_notas),
        );
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }
}
