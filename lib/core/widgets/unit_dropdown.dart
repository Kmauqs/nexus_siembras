import 'package:flutter/material.dart';
import '../units/units_catalog.dart';

/// Dropdown de unidad agrupado por dimensión (Peso / Volumen / Longitud / Unidad).
class UnitDropdown extends StatelessWidget {
  const UnitDropdown({
    super.key,
    required this.value,
    required this.onChanged,
    this.label = 'Unidad',
    this.dimensions,
    this.dense = false,
  });

  final String value;
  final ValueChanged<String?> onChanged;
  final String label;

  /// Restringe qué dimensiones mostrar. Si es null se muestran todas.
  final List<String>? dimensions;

  /// Compacta el dropdown para pantallas con espacio limitado.
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final dims = dimensions ?? const ['peso', 'volumen', 'longitud', 'area', 'unidad'];
    final items = <DropdownMenuItem<String>>[];
    for (final dim in dims) {
      final unidades = unidadesPorDimension(dim).toList();
      if (unidades.isEmpty) continue;
      items.add(DropdownMenuItem<String>(
        enabled: false,
        value: '__header_$dim',
        child: Text(
          _dimTitle(dim),
          style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 11,
              color: Colors.grey),
        ),
      ));
      for (final u in unidades) {
        items.add(DropdownMenuItem<String>(
          value: u.codigo,
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text('${u.codigo} — ${u.nombre}',
                style: TextStyle(fontSize: dense ? 13 : 14),
                overflow: TextOverflow.ellipsis),
          ),
        ));
      }
    }

    return DropdownButtonFormField<String>(
      value: unidadPorCodigo(value) != null ? value : 'und',
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        contentPadding: dense
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 8)
            : null,
        border: const OutlineInputBorder(),
      ),
      items: items,
      selectedItemBuilder: (ctx) => items.map((it) {
        if (it.value == null || it.value!.startsWith('__header_')) {
          return const SizedBox.shrink();
        }
        final u = unidadPorCodigo(it.value!);
        return Align(
          alignment: Alignment.centerLeft,
          child: Text(u?.codigo ?? '', style: TextStyle(fontSize: dense ? 13 : 14)),
        );
      }).toList(),
      onChanged: (v) {
        if (v == null || v.startsWith('__header_')) return;
        onChanged(v);
      },
    );
  }

  static String _dimTitle(String dim) => switch (dim) {
        'peso' => 'Peso',
        'volumen' => 'Volumen',
        'longitud' => 'Longitud',
        'area' => 'Área',
        'unidad' => 'Unidad',
        _ => dim,
      };
}
