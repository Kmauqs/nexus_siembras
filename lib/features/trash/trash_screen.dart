import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/repositories/trash_repository.dart';
import '../../state/data_state.dart';

class TrashScreen extends ConsumerWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncItems = ref.watch(papeleraProvider);
    return AppShell(
      title: 'Papelera',
      child: asyncItems.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (items) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: items.isEmpty
                    ? null
                    : () => _confirmEmpty(context, ref),
                icon: const Icon(Icons.delete_forever),
                label: const Text('Vaciar papelera'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
              ),
            ),
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.delete_outline, size: 64,
                              color: Theme.of(context).hintColor),
                          const SizedBox(height: 12),
                          Text('La papelera está vacía',
                              style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: items.length,
                      itemBuilder: (_, i) => _TrashTile(
                        item: items[i],
                        onRecover: () => _recover(context, ref, items[i]),
                        onDelete: () => _hardDelete(context, ref, items[i]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _confirmEmpty(BuildContext ctx, WidgetRef ref) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Vaciar papelera'),
        content: const Text('¿Eliminar permanentemente todos los ítems? '
            'Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              final n = await ref.read(dataMutationsProvider).emptyTrash();
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text('$n ítem(s) eliminado(s) permanentemente')));
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  Future<void> _recover(BuildContext ctx, WidgetRef ref, TrashItem it) async {
    await ref.read(dataMutationsProvider).restoreTrash(it.tipo, it.id);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('${it.descripcion} restaurado')));
    }
  }

  Future<void> _hardDelete(BuildContext ctx, WidgetRef ref, TrashItem it) async {
    await ref.read(dataMutationsProvider).hardDeleteTrash(it.tipo, it.id);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('${it.descripcion} eliminado permanentemente')));
    }
  }
}

class _TrashTile extends StatelessWidget {
  const _TrashTile({
    required this.item,
    required this.onRecover,
    required this.onDelete,
  });
  final TrashItem item;
  final VoidCallback onRecover, onDelete;

  static const _tipoColors = <String, Color>{
    'cultivo':     Color(0xFF1B7A3E),
    'compra':      Color(0xFF2563EB),
    'inventario':  Color(0xFF8B6F47),
  };

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: _tipoColors[item.tipo] ?? Colors.grey,
            child: Text(item.tipo[0].toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          title: Text(item.descripcion,
              style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('Eliminado: ${_iso(item.fechaEliminacion)}'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              icon: const Icon(Icons.restore, color: Colors.green),
              tooltip: 'Restaurar',
              onPressed: onRecover,
            ),
            IconButton(
              icon: const Icon(Icons.delete_forever, color: Colors.red),
              tooltip: 'Eliminar permanentemente',
              onPressed: onDelete,
            ),
          ]),
        ),
      );

  String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}
