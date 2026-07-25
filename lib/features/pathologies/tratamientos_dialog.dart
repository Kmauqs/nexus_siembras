// NEXUS Siembras — Diálogo "Tratamientos recomendados" (Fase 3e-8).
//
// Muestra los tratamientos de una patología agrupados por tipo (cultural,
// preventivo, biológico, orgánico, químico) con badges de sostenibilidad
// y filtrado implícito por país del predio activo (los del país aparecen
// primero, luego los globales, luego los de otros países).
//
// Uso:
//   showTratamientosDialog(context, patologiaId, patologiaNombre);

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/database.dart' as drift;
import '../../state/data_state.dart';

/// Abre el diálogo de tratamientos para una patología.
void showTratamientosDialog(
    BuildContext context, int patologiaId, String patologiaNombre) {
  showDialog<void>(
    context: context,
    builder: (_) => _TratamientosDialog(
      patologiaId: patologiaId,
      patologiaNombre: patologiaNombre,
    ),
  );
}

class _TratamientosDialog extends ConsumerWidget {
  const _TratamientosDialog({
    required this.patologiaId,
    required this.patologiaNombre,
  });
  final int patologiaId;
  final String patologiaNombre;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tratamientosPorPatologiaProvider(patologiaId));
    final paisIso = ref.watch(predioActivoIsoProvider).maybeWhen(
        data: (i) => i, orElse: () => null);
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                const Icon(Icons.medical_services_outlined,
                    color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tratamientos recomendados',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(patologiaNombre,
                          style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: Theme.of(context).hintColor)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ]),
              if (paisIso != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(
                      'País del predio activo: $paisIso · se priorizan tratamientos locales',
                      style: TextStyle(
                          fontSize: 11,
                          color: Theme.of(context).hintColor)),
                ),
              const Divider(),
              Expanded(
                child: async.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Text('Error: $e'),
                  data: (list) {
                    if (list.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text(
                              'No hay tratamientos registrados para esta '
                              'patología aún. Pulsa "Actualizar" en '
                              'Patologías para cargar el catálogo.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey)),
                        ),
                      );
                    }
                    // Agrupar por tipo, respetando el orden ya calculado.
                    final grupos = <String, List<drift.TratamientosPatologia>>{};
                    for (final t in list) {
                      grupos.putIfAbsent(t.tipo, () => []).add(t);
                    }
                    return ListView(
                      children: [
                        for (final entry in grupos.entries) ...[
                          _TipoHeader(tipo: entry.key),
                          ...entry.value.map((t) => _TratamientoCard(
                                t: t,
                                esDelPaisActivo: t.paisIso2 != null &&
                                    t.paisIso2 == paisIso,
                              )),
                          const SizedBox(height: 8),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TipoHeader extends StatelessWidget {
  const _TipoHeader({required this.tipo});
  final String tipo;

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;
    String label;
    switch (tipo) {
      case 'cultural':
        icon = Icons.spa;
        color = Colors.green.shade700;
        label = 'Prácticas culturales';
        break;
      case 'preventivo':
        icon = Icons.shield_outlined;
        color = Colors.blue.shade700;
        label = 'Preventivos';
        break;
      case 'biologico':
        icon = Icons.pest_control;
        color = Colors.teal.shade700;
        label = 'Control biológico';
        break;
      case 'organico':
        icon = Icons.eco;
        color = Colors.lightGreen.shade700;
        label = 'Orgánicos';
        break;
      case 'quimico':
        icon = Icons.science;
        color = Colors.orange.shade800;
        label = 'Químicos convencionales';
        break;
      default:
        icon = Icons.help_outline;
        color = Colors.grey.shade700;
        label = tipo;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 6),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: color)),
      ]),
    );
  }
}

class _TratamientoCard extends StatelessWidget {
  const _TratamientoCard({required this.t, required this.esDelPaisActivo});
  final drift.TratamientosPatologia t;
  final bool esDelPaisActivo;

  @override
  Widget build(BuildContext context) {
    final productos = _productos();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: esDelPaisActivo
            ? Colors.green.shade50
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: esDelPaisActivo
                ? Colors.green.shade300
                : Colors.grey.shade300,
            width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text(t.nombreCorto,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ),
            _sostenibilidadChip(t.sostenibilidad),
          ]),
          if (esDelPaisActivo)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                Icon(Icons.flag,
                    size: 10, color: Colors.green.shade700),
                const SizedBox(width: 3),
                Text('Tratamiento local (${t.paisIso2})',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600)),
              ]),
            )
          else if (t.paisIso2 != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('País de referencia: ${t.paisIso2}',
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).hintColor)),
            ),
          if ((t.descripcion ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(t.descripcion!, style: const TextStyle(fontSize: 12)),
          ],
          if (productos.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Productos:',
                style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).hintColor)),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: productos
                  .map((p) => Chip(
                        label:
                            Text(p, style: const TextStyle(fontSize: 10)),
                        visualDensity: VisualDensity.compact,
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ))
                  .toList(),
            ),
          ],
          if ((t.dosis ?? '').isNotEmpty ||
              (t.frecuencia ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            if ((t.dosis ?? '').isNotEmpty)
              _keyVal('Dosis', t.dosis!),
            if ((t.frecuencia ?? '').isNotEmpty)
              _keyVal('Frecuencia', t.frecuencia!),
          ],
          if ((t.notas ?? '').isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('⚠ ${t.notas}',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.orange.shade800,
                    fontStyle: FontStyle.italic)),
          ],
          if ((t.fuente ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Fuente: ${t.fuente}',
                  style: TextStyle(
                      fontSize: 10,
                      color: Theme.of(context).hintColor,
                      fontStyle: FontStyle.italic)),
            ),
        ],
      ),
    );
  }

  List<String> _productos() {
    final json = t.productos;
    if (json == null || json.isEmpty) return const [];
    try {
      final list = jsonDecode(json);
      if (list is List) {
        return list.map((e) => e.toString()).toList();
      }
    } catch (_) {}
    return const [];
  }

  Widget _sostenibilidadChip(String? nivel) {
    if (nivel == null) return const SizedBox.shrink();
    Color color;
    String texto;
    switch (nivel) {
      case 'alta':
        color = Colors.green.shade700;
        texto = '🌿 sostenibilidad alta';
        break;
      case 'media':
        color = Colors.amber.shade800;
        texto = '⚠ sostenibilidad media';
        break;
      case 'baja':
        color = Colors.red.shade700;
        texto = '⚗ sostenibilidad baja';
        break;
      default:
        color = Colors.grey;
        texto = nivel;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(texto,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }

  Widget _keyVal(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(fontSize: 11, color: Colors.black87),
            children: [
              TextSpan(
                  text: '$k: ',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: v),
            ],
          ),
        ),
      );
}
