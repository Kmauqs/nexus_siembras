// NEXUS Siembras — Widget reutilizable para tarjeta de detección activa
// de patología (Fase 3e-5). Se usa desde:
//   - Pantalla "Patologías" (lista global de detecciones activas del predio)
//   - Detalle de un cultivo (filtrado por ese cultivo específico)
//
// Encapsula la miniatura de la foto, chips de fecha/severidad/GNSS/
// "compartida", notas y las acciones "Intervención" y "Curada".

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/themes.dart';
import '../../data/database/database.dart' as drift;
import '../../state/data_state.dart';
import 'tratamientos_dialog.dart';

class PatologiaActivaCard extends ConsumerWidget {
  const PatologiaActivaCard({
    super.key,
    required this.cp,
    required this.plantaNombre,
    required this.lote,
  });
  final drift.CultivoPatologia cp;
  final String plantaNombre, lote;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = cp.severidad == 'avanzada'
        ? AppThemes.colorAlert
        : AppThemes.colorWarn;
    final asyncCat = ref.watch(patologiasCatalogoProvider);
    final patNombre = asyncCat.maybeWhen(
      data: (list) => list
          .firstWhere((p) => p.id == (cp.patologiaId ?? -1),
              orElse: () => list.isNotEmpty ? list.first : list.first)
          .nombreComun,
      orElse: () => 'Patología #${cp.patologiaId}',
    );
    final fotoPath = cp.fotoPath;
    final tieneFoto = fotoPath != null && fotoPath.isNotEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (tieneFoto) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(File(fotoPath),
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                            width: 56,
                            height: 56,
                            color: Colors.grey.shade200,
                            child: const Icon(Icons.broken_image),
                          )),
                ),
                const SizedBox(width: 10),
              ] else ...[
                Container(
                    width: 12,
                    height: 12,
                    decoration:
                        BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patNombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('$plantaNombre · $lote',
                        style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).hintColor,
                            fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.check_circle,
                    color: AppThemes.colorOk),
                tooltip: 'Registrar intervención',
                onPressed: () => _showInterventionModal(context, ref),
              ),
            ]),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                _chip(
                  icon: Icons.calendar_today,
                  label: _iso(cp.fechaDeteccion),
                ),
                _chip(
                  icon: cp.severidad == 'avanzada'
                      ? Icons.warning
                      : Icons.circle,
                  label: cp.severidad ?? '?',
                  color: color,
                ),
                if (cp.lat != null && cp.lng != null)
                  _chip(
                    icon: Icons.place,
                    label:
                        '${cp.lat!.toStringAsFixed(4)}, ${cp.lng!.toStringAsFixed(4)}',
                    color: Colors.blue.shade700,
                  ),
                if (cp.compartida)
                  _chip(
                    icon: Icons.public,
                    label: 'compartida',
                    color: Colors.green.shade700,
                  ),
              ],
            ),
            if ((cp.notas ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('📝 ${cp.notas}',
                  style: const TextStyle(
                      fontSize: 12, fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              if (cp.patologiaId != null)
                OutlinedButton.icon(
                  onPressed: () => showTratamientosDialog(
                      context, cp.patologiaId!, patNombre),
                  icon: Icon(Icons.medical_services_outlined,
                      size: 16, color: Colors.green.shade700),
                  label: const Text('Tratamientos'),
                ),
              OutlinedButton.icon(
                onPressed: () => _showInterventionModal(context, ref),
                icon: const Icon(Icons.medication_outlined, size: 16),
                label: const Text('Intervención'),
              ),
              FilledButton.icon(
                onPressed: () => _markCured(context, ref),
                icon: const Icon(Icons.eco, size: 16),
                label: const Text('Curada'),
                style: FilledButton.styleFrom(
                    backgroundColor: AppThemes.colorOk),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _chip({required IconData icon, required String label, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 12, color: color ?? Colors.grey.shade800),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 11,
                color: color ?? Colors.grey.shade800,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }

  void _showInterventionModal(BuildContext ctx, WidgetRef ref) {
    var fecha = DateTime.now();
    final notaCtrl = TextEditingController();
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      builder: (sheetCtx) => StatefulBuilder(
        builder: (sheetCtx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Registrar intervención',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: sheetCtx,
                    initialDate: fecha,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setModalState(() => fecha = picked);
                  }
                },
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Fecha',
                    suffixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder(),
                  ),
                  child: Text(_iso(fecha)),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: notaCtrl,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Anotaciones',
                    hintText: 'Producto aplicado, dosis, condiciones...',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              const Text(
                  '⚠ Estado permanece Naranja hasta confirmar cura con 🌿 Curada.',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    if (notaCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text('Indica las anotaciones')));
                      return;
                    }
                    await ref
                        .read(dataMutationsProvider)
                        .registrarIntervencionPatologia(
                          cpId: cp.id,
                          fecha: fecha,
                          nota: notaCtrl.text.trim(),
                        );
                    if (ctx.mounted) {
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                          content: Text(
                              'Intervención registrada · estado Naranja')));
                    }
                  },
                  child: const Text('Guardar'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _markCured(BuildContext ctx, WidgetRef ref) {
    showDialog<void>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Marcar como curada'),
        content: Text('¿Confirmas que $plantaNombre · $lote está curada? '
            'Esto regresa el estado del cultivo a Verde.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            onPressed: () async {
              await ref
                  .read(dataMutationsProvider)
                  .marcarPatologiaCurada(cp.id);
              if (ctx.mounted) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                    content:
                        Text('Planta marcada como Curada · estado Verde')));
              }
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}
