// Detalle de predio con listado de lotes.

import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/app_shell.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';

class PredioDetailScreen extends ConsumerWidget {
  const PredioDetailScreen({super.key, required this.predioId});
  final int predioId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final predios = ref.watch(prediosProvider);
    final lotes = ref.watch(lotesPorPredioProvider(predioId));
    return predios.when(
      loading: () => const AppShell(
          title: 'Predio', child: Center(child: CircularProgressIndicator())),
      error: (e, _) =>
          AppShell(title: 'Predio', child: Center(child: Text('Error: $e'))),
      data: (list) {
        final p =
            list.where((x) => x.id == predioId).cast<dynamic>().firstOrNull;
        if (p == null) {
          return AppShell(
            title: 'Predio',
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.search_off, size: 60, color: Colors.grey),
                const SizedBox(height: 12),
                const Text('Predio no encontrado'),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => context.go('/predios'),
                    child: const Text('Volver')),
              ]),
            ),
          );
        }
        return AppShell(
          title: p.nombre as String,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.landscape, color: Colors.green),
                        const SizedBox(width: 6),
                        Expanded(
                            child: Text(p.nombre as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18))),
                      ]),
                      const Divider(),
                      if (p.propietario != null)
                        _row('Propietario', p.propietario as String),
                      if (p.lat != null && p.lng != null)
                        _row('Coordenadas',
                            '${(p.lat as double).toStringAsFixed(6)}, ${(p.lng as double).toStringAsFixed(6)}'),
                      if (p.altM != null)
                        _row('Altitud',
                            '${(p.altM as double).toStringAsFixed(0)} msnm'),
                      if (p.notas != null) _row('Notas', p.notas as String),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                const Expanded(
                    child: Text('Lotes',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold))),
                if (ref.watch(soyPropietarioPredioProvider(predioId)))
                  FilledButton.icon(
                    onPressed: () =>
                        context.go('/predios/$predioId/lotes/new'),
                    icon: const Icon(Icons.add),
                    label: const Text('Nuevo lote'),
                  ),
              ]),
              const SizedBox(height: 8),
              lotes.when(
                loading: () => const LinearProgressIndicator(),
                error: (e, _) => Text('Error: $e'),
                data: (list) => list.isEmpty
                    ? Card(
                        child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                                child: Text('Sin lotes registrados',
                                    style: TextStyle(
                                        color: Theme.of(context).hintColor)))),
                      )
                    : Column(
                        children: list.map((l) => _LoteCard(
                          l: l,
                          predioId: predioId,
                          soyPropietario: ref.watch(
                              soyPropietarioPredioProvider(predioId)),
                          onEdit: () => context
                              .go('/predios/$predioId/lotes/${l.id}'),
                          onDelete: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                title: const Text('Eliminar lote'),
                                content: Text('¿Enviar "${l.nombre}" a la papelera?'),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('Cancelar')),
                                  FilledButton.tonal(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      style: FilledButton.styleFrom(
                                          foregroundColor: Colors.red),
                                      child: const Text('Eliminar')),
                                ],
                              ),
                            );
                            if (ok == true) {
                              await ref
                                  .read(dataMutationsProvider)
                                  .deleteLote(l.id as int);
                            }
                          },
                        )).toList(),
                      ),
              ),
              const SizedBox(height: 12),
              _ColaboradoresCard(predioId: predioId),
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
                width: 110,
                child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v)),
          ],
        ),
      );
}

class _LoteCard extends StatelessWidget {
  const _LoteCard({
    required this.l,
    required this.predioId,
    required this.onEdit,
    required this.onDelete,
    this.soyPropietario = true,
  });
  final dynamic l; // drift.Lote
  final int predioId;
  final VoidCallback onEdit, onDelete;
  final bool soyPropietario;

  @override
  Widget build(BuildContext context) {
    int numPuntos = 0;
    if (l.poligonoGeoJson != null) {
      try {
        numPuntos = (jsonDecode(l.poligonoGeoJson as String) as List).length;
      } catch (_) {}
    }
    return Card(
      child: InkWell(
        onTap: soyPropietario ? onEdit : null,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              const Icon(Icons.crop_free, color: Colors.brown),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.nombre as String,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    if (l.administrador != null)
                      Text('Admin.: ${l.administrador}',
                          style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).hintColor)),
                    Row(children: [
                      if (l.altitudMsnm != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 12),
                          child: Text(
                              '⛰️ ${(l.altitudMsnm as double).toStringAsFixed(0)} msnm',
                              style: const TextStyle(fontSize: 11)),
                        ),
                      Text('📐 $numPuntos punto(s)',
                          style: const TextStyle(fontSize: 11)),
                    ]),
                  ],
                ),
              ),
              if (soyPropietario)
                IconButton(
                    icon: const Icon(Icons.edit_outlined), onPressed: onEdit),
              if (soyPropietario)
                IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: onDelete),
            ],
          ),
        ),
      ),
    );
  }
}

extension _First<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

/// Card de colaboradores del predio (Fase 3e).
class _ColaboradoresCard extends ConsumerWidget {
  const _ColaboradoresCard({required this.predioId});
  final int predioId;

  static const _roles = <String, String>{
    'propietario': 'Propietario · control total',
    'trabajador': 'Trabajador · crear y editar',
    'consultor': 'Consultor · solo lectura',
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(colaboradoresPorPredioProvider(predioId));
    final soyPropietario = ref.watch(soyPropietarioPredioProvider(predioId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.people, color: Colors.blue),
              const SizedBox(width: 6),
              Text('Colaboradores',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              if (soyPropietario)
                FilledButton.icon(
                  onPressed: () => _openInvitar(context, ref),
                  icon: const Icon(Icons.person_add, size: 18),
                  label: const Text('Invitar'),
                ),
            ]),
            const Divider(),
            async.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e',
                  style: const TextStyle(color: Colors.red)),
              data: (list) {
                final currentUser = ref.watch(currentUserProvider);
                // Filtro: si NO soy propietario, oculto MI propia fila
                // representativa (Fase 3e-9-13). Esa fila solo sirve para
                // que `rolEnPredioProvider` sepa mi rol — no tiene sentido
                // pintarla en la lista de colaboradores del predio ajeno.
                // En cambio, si SÍ soy propietario y por algún motivo hay
                // una fila conmigo mismo, sí la muestro (el `_propietarioSelfTile`
                // ya se encarga arriba).
                final filtered = (currentUser != null && !soyPropietario)
                    ? list
                        .where((c) => c.colaboradorUserId != currentUser.id)
                        .toList()
                    : list;
                // Deduplicar por colaboradorUserId (evita filas repetidas
                // que podían generar sync anteriores).
                final vistos = <String>{};
                final unicos = <dynamic>[];
                for (final c in filtered) {
                  final uid = c.colaboradorUserId as String?;
                  final key = uid ?? c.colaboradorEmail as String;
                  if (vistos.add(key)) unicos.add(c);
                }

                // Si soy propietario y NO estoy en la lista, me agrego al inicio.
                final tiles = <Widget>[];
                if (currentUser != null &&
                    soyPropietario &&
                    !unicos.any((c) =>
                        c.colaboradorUserId == currentUser.id &&
                        c.rol == 'propietario')) {
                  tiles.add(_propietarioSelfTile(context, currentUser.email));
                }
                for (final c in unicos) {
                  tiles.add(_colaboradorTile(context, ref, c, soyPropietario));
                }

                if (tiles.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                        soyPropietario
                            ? 'Sin colaboradores todavía. Invita a otros usuarios '
                                'por email para que puedan ver o gestionar este predio.'
                            : 'Este predio es solo para ti.',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(context).hintColor)),
                  );
                }
                return Column(children: tiles);
              },
            ),
            const SizedBox(height: 6),
            if (soyPropietario)
              Text(
                  'Al invitar, el colaborador debe tener cuenta en NEXUS y '
                  'estar sincronizado. El predio aparecerá en su selector '
                  'automáticamente.',
                  style: TextStyle(
                      fontSize: 11, color: Theme.of(context).hintColor))
            else
              Text(
                  'Solo el propietario del predio puede invitar o gestionar '
                  'colaboradores.',
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).hintColor,
                      fontStyle: FontStyle.italic)),
          ],
        ),
      ),
    );
  }

  Widget _propietarioSelfTile(BuildContext context, String? email) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Colors.green.shade100,
        child: const Icon(Icons.workspace_premium,
            color: Colors.green, size: 18),
      ),
      title: Row(children: [
        Flexible(
          child: Text(email ?? 'Tú',
              style: const TextStyle(fontSize: 14),
              overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.green.shade200)),
          child: const Text('Tú',
              style: TextStyle(fontSize: 9, color: Colors.green)),
        ),
      ]),
      subtitle: const Text('Propietario · control total',
          style: TextStyle(fontSize: 11)),
    );
  }

  Widget _colaboradorTile(
      BuildContext context, WidgetRef ref, dynamic c, bool puedeGestionar) {
    final currentUser = ref.watch(currentUserProvider);
    final esMiPropiaFila =
        currentUser != null && c.colaboradorUserId == currentUser.id;
    // Selector de rol solo aplica a filas NO propietarias (no tiene
    // sentido "cambiar el rol" de un propietario). Eliminar sí aplica a
    // cualquier fila que no sea la propia (permite al propietario purgar
    // filas fantasma con rol='propietario' generadas por syncs antiguos).
    final puedeCambiarRol =
        puedeGestionar && c.rol != 'propietario' && !esMiPropiaFila;
    final puedeEliminar = puedeGestionar && !esMiPropiaFila;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: c.rol == 'propietario'
            ? Colors.green.shade100
            : Colors.blue.shade100,
        child: c.rol == 'propietario'
            ? const Icon(Icons.workspace_premium,
                color: Colors.green, size: 18)
            : Text(
                (c.colaboradorEmail as String)
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(color: Colors.blue)),
      ),
      title: Text(c.colaboradorEmail as String,
          style: const TextStyle(fontSize: 14),
          overflow: TextOverflow.ellipsis),
      subtitle: Text(_roles[c.rol as String] ?? c.rol as String,
          style: const TextStyle(fontSize: 11)),
      trailing: (puedeCambiarRol || puedeEliminar)
          ? Row(mainAxisSize: MainAxisSize.min, children: [
              if (puedeCambiarRol)
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert, size: 20),
                  onSelected: (nuevoRol) => ref
                      .read(dataMutationsProvider)
                      .actualizarRolColaborador(
                          id: c.id as int, rol: nuevoRol),
                  itemBuilder: (_) => _roles.entries
                      .where((e) => e.key != 'propietario')
                      .map((e) => PopupMenuItem<String>(
                            value: e.key,
                            child: Row(children: [
                              if (c.rol == e.key)
                                const Icon(Icons.check,
                                    size: 16, color: Colors.green),
                              if (c.rol != e.key) const SizedBox(width: 16),
                              const SizedBox(width: 6),
                              Text(e.value,
                                  style: const TextStyle(fontSize: 12)),
                            ]),
                          ))
                      .toList(),
                ),
              if (puedeEliminar)
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      color: Colors.red, size: 20),
                  onPressed: () => _confirmarRemover(context, ref, c),
                ),
            ])
          : null,
    );
  }

  Future<void> _confirmarRemover(
      BuildContext context, WidgetRef ref, dynamic c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover colaborador'),
        content: Text(
            '¿Quitar a "${c.colaboradorEmail}" de este predio? '
            'Ya no podrá verlo ni gestionarlo.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Remover')),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(dataMutationsProvider)
          .removerColaborador(c.id as int);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Colaborador removido')));
      }
    }
  }

  Future<void> _openInvitar(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _InvitarColaboradorSheet(predioId: predioId),
    );
  }
}

class _InvitarColaboradorSheet extends ConsumerStatefulWidget {
  const _InvitarColaboradorSheet({required this.predioId});
  final int predioId;

  @override
  ConsumerState<_InvitarColaboradorSheet> createState() =>
      _InvitarColaboradorSheetState();
}

class _InvitarColaboradorSheetState
    extends ConsumerState<_InvitarColaboradorSheet> {
  final _email = TextEditingController();
  String _rol = 'trabajador';
  bool _procesando = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _invitar() async {
    final email = _email.text.trim().toLowerCase();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _error = 'Ingresa un email válido');
      return;
    }
    setState(() {
      _procesando = true;
      _error = null;
    });
    try {
      final id = await ref.read(dataMutationsProvider).invitarColaborador(
            predioId: widget.predioId,
            email: email,
            rol: _rol,
          );
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _error = 'No se encontró usuario con ese email. '
              'Pídele que se registre en NEXUS primero.';
          _procesando = false;
        });
        return;
      }
      Navigator.pop(context, true);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Invitación enviada a $email · rol: $_rol'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Error: $e';
        _procesando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Invitar colaborador',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
                labelText: 'Email del colaborador',
                helperText: 'Debe tener cuenta activa en NEXUS',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _rol,
            isExpanded: true,
            decoration: const InputDecoration(
                labelText: 'Rol', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(
                  value: 'propietario',
                  child: Text('Propietario · control total incl. compras')),
              DropdownMenuItem(
                  value: 'trabajador',
                  child: Text('Trabajador · crear y editar')),
              DropdownMenuItem(
                  value: 'consultor',
                  child: Text('Consultor · solo lectura')),
            ],
            onChanged: (v) => setState(() => _rol = v ?? 'trabajador'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  border: Border.all(color: Colors.red.shade200),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(_error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
            ),
          ],
          const SizedBox(height: 16),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
                onPressed: _procesando
                    ? null
                    : () => Navigator.pop(context, false),
                child: const Text('Cancelar')),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _procesando ? null : _invitar,
              icon: _procesando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 18),
              label: Text(_procesando ? 'Enviando…' : 'Invitar'),
            ),
          ]),
        ],
      ),
    );
  }
}
