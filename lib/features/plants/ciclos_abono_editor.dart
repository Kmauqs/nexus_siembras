import 'package:flutter/material.dart';
import '../../core/models/ciclo_abono.dart';

/// Fila editable de un ciclo de abono en el formulario de variedad.
class CicloAbonoEditorRow {
  CicloAbonoEditorRow({String? tipo, String? dias})
      : tipoSeleccionado = _tipoInicial(tipo),
        tipoCustomCtrl = TextEditingController(
          text: _esOtro(tipo) ? (tipo ?? '') : '',
        ),
        diasCtrl = TextEditingController(text: dias ?? '');

  String tipoSeleccionado;
  final TextEditingController tipoCustomCtrl;
  final TextEditingController diasCtrl;

  static String _tipoInicial(String? tipo) {
    if (tipo == null || tipo.trim().isEmpty) return tiposAbonoSugeridos.first;
    if (tiposAbonoSugeridos.contains(tipo)) return tipo;
    return 'Otro';
  }

  static bool _esOtro(String? tipo) =>
      tipo != null &&
      tipo.trim().isNotEmpty &&
      !tiposAbonoSugeridos.contains(tipo);

  String get tipoResuelto => tipoSeleccionado == 'Otro'
      ? tipoCustomCtrl.text.trim()
      : tipoSeleccionado;

  CicloAbono? toCiclo() {
    final dias = int.tryParse(diasCtrl.text.trim());
    // 0 = abono al momento de siembra/trasplante (válido).
    if (dias == null || dias < 0) return null;
    final tipo = tipoResuelto;
    if (tipo.isEmpty) return null;
    return CicloAbono(tipo: tipo, dias: dias);
  }

  void dispose() {
    tipoCustomCtrl.dispose();
    diasCtrl.dispose();
  }

  static CicloAbonoEditorRow fromCiclo(CicloAbono c) => CicloAbonoEditorRow(
        tipo: c.tipo,
        dias: '${c.dias}',
      );
}

class CiclosAbonoEditor extends StatelessWidget {
  const CiclosAbonoEditor({
    super.key,
    required this.ciclos,
    required this.onChanged,
  });

  final List<CicloAbonoEditorRow> ciclos;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < ciclos.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _CicloAbonoCard(
            index: i,
            row: ciclos[i],
            puedeEliminar: ciclos.length > 1,
            onChanged: onChanged,
            onEliminar: () {
              ciclos[i].dispose();
              ciclos.removeAt(i);
              onChanged();
            },
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () {
              ciclos.add(CicloAbonoEditorRow(
                dias: ciclos.isEmpty
                    ? '1'
                    : '${(int.tryParse(ciclos.last.diasCtrl.text) ?? 30) + 30}',
              ));
              onChanged();
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Agregar ciclo de abono'),
          ),
        ),
      ],
    );
  }
}

class _CicloAbonoCard extends StatelessWidget {
  const _CicloAbonoCard({
    required this.index,
    required this.row,
    required this.puedeEliminar,
    required this.onChanged,
    required this.onEliminar,
  });

  final int index;
  final CicloAbonoEditorRow row;
  final bool puedeEliminar;
  final VoidCallback onChanged;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final esOtro = row.tipoSeleccionado == 'Otro';
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Abono ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                const Spacer(),
                if (puedeEliminar)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: Colors.red),
                    tooltip: 'Quitar ciclo',
                    onPressed: onEliminar,
                  ),
              ],
            ),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: row.tipoSeleccionado,
              decoration: const InputDecoration(
                labelText: 'Tipo de abono',
                border: OutlineInputBorder(),
              ),
              items: tiposAbonoSugeridos
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) {
                row.tipoSeleccionado = v ?? tiposAbonoSugeridos.first;
                onChanged();
              },
            ),
            if (esOtro) ...[
              const SizedBox(height: 8),
              TextField(
                controller: row.tipoCustomCtrl,
                decoration: const InputDecoration(
                  labelText: 'Especificar tipo de abono',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) => onChanged(),
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: row.diasCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Días desde siembra/trasplante',
                helperText: '0 = al siembra/trasplante · >0 = días después',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => onChanged(),
            ),
          ],
        ),
      ),
    );
  }
}
