import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// Unidad de tiempo seleccionable en los campos de duración.
///
/// La BD **siempre** almacena días (`cosecha1Dias`, `periodicidadCosechaDias`,
/// `ciclosAbonoJson[].dias`, …); estas unidades solo existen en la UI para
/// que el usuario no tenga que hacer la cuenta mentalmente.
///
/// Equivalencias fijas — mes = 30 días, año = 365 días. Son aproximaciones
/// agronómicas deliberadas: los periodos fenológicos son estimaciones y el
/// cronograma se reajusta con las fechas reales de las tareas registradas.
enum UnidadTiempo {
  dias('Días', 'd', 1),
  semanas('Semanas', 'sem', 7),
  meses('Meses', 'mes', 30),
  anios('Años', 'año', 365);

  const UnidadTiempo(this.etiqueta, this.abrev, this.enDias);

  /// Nombre completo para el menú desplegable.
  final String etiqueta;

  /// Abreviatura mostrada dentro del campo cuando está colapsado.
  final String abrev;

  /// Cuántos días equivale una unidad.
  final int enDias;
}

/// Estado de un campo de duración: valor digitado + unidad seleccionada.
///
/// Sustituye al `TextEditingController` que antes guardaba días crudos.
/// El consumidor solo necesita [dias] para persistir y [setDias] para
/// precargar valores existentes.
class DuracionController extends ChangeNotifier {
  DuracionController({int? dias, UnidadTiempo unidad = UnidadTiempo.dias})
      : texto = TextEditingController(),
        _unidad = unidad {
    if (dias != null) setDias(dias);
  }

  /// Controller del valor numérico (sin la unidad).
  final TextEditingController texto;

  UnidadTiempo _unidad;
  UnidadTiempo get unidad => _unidad;
  set unidad(UnidadTiempo u) {
    if (u == _unidad) return;
    _unidad = u;
    notifyListeners();
  }

  bool get vacio => texto.text.trim().isEmpty;

  /// Valor en DÍAS listo para guardar en la BD, o `null` si el campo está
  /// vacío o no es numérico. Acepta decimales ("1,5 meses" → 45 días).
  int? get dias {
    final raw = texto.text.trim().replaceAll(',', '.');
    if (raw.isEmpty) return null;
    final n = double.tryParse(raw);
    if (n == null) return null;
    return (n * _unidad.enDias).round();
  }

  /// Precarga un valor en días eligiendo la unidad más legible: 1095 días
  /// se muestra como "3 años", 90 como "3 meses", 14 como "2 semanas".
  void setDias(int? dias) {
    if (dias == null) {
      texto.clear();
      _unidad = UnidadTiempo.dias;
      notifyListeners();
      return;
    }
    final u = _unidadNatural(dias);
    _unidad = u;
    texto.text = _fmt(dias / u.enDias);
    notifyListeners();
  }

  void limpiar() => setDias(null);

  static UnidadTiempo _unidadNatural(int dias) {
    if (dias <= 0) return UnidadTiempo.dias;
    if (dias % UnidadTiempo.anios.enDias == 0) return UnidadTiempo.anios;
    if (dias % UnidadTiempo.meses.enDias == 0) return UnidadTiempo.meses;
    if (dias % UnidadTiempo.semanas.enDias == 0) return UnidadTiempo.semanas;
    return UnidadTiempo.dias;
  }

  static String _fmt(double v) {
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  void dispose() {
    texto.dispose();
    super.dispose();
  }
}

/// Campo numérico de duración con selector de unidad **dentro del mismo
/// campo** (días / semanas / meses / años).
///
/// El valor se convierte a días automáticamente: leer [DuracionController.dias]
/// devuelve siempre días, independientemente de la unidad elegida. Cuando la
/// unidad no es "días" el helper muestra la equivalencia calculada para que
/// el usuario confirme lo que se va a guardar.
class DuracionField extends StatefulWidget {
  const DuracionField({
    super.key,
    required this.controller,
    required this.label,
    this.helperText,
    this.hintText,
    this.onChanged,
    this.dense = false,
  });

  final DuracionController controller;
  final String label;

  /// Texto de ayuda propio. La equivalencia en días se añade aparte.
  final String? helperText;
  final String? hintText;
  final VoidCallback? onChanged;

  /// Compacta el campo para filas de dos columnas.
  final bool dense;

  @override
  State<DuracionField> createState() => _DuracionFieldState();
}

class _DuracionFieldState extends State<DuracionField> {
  @override
  void initState() {
    super.initState();
    _suscribir(widget.controller);
  }

  @override
  void didUpdateWidget(DuracionField old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _desuscribir(old.controller);
      _suscribir(widget.controller);
    }
  }

  @override
  void dispose() {
    _desuscribir(widget.controller);
    super.dispose();
  }

  void _suscribir(DuracionController c) {
    c.addListener(_refrescar);
    c.texto.addListener(_refrescar);
  }

  void _desuscribir(DuracionController c) {
    c.removeListener(_refrescar);
    c.texto.removeListener(_refrescar);
  }

  /// El controller puede mutarse durante el `build` del padre (precarga de
  /// periodos desde la variedad seleccionada); en esa fase hay que diferir
  /// el `setState` al siguiente frame para no romper el árbol.
  void _refrescar() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final equivalente = c.unidad == UnidadTiempo.dias ? null : c.dias;
    final helper = [
      if (widget.helperText != null) widget.helperText!,
      if (equivalente != null) '= $equivalente días',
    ].join(' · ');

    return TextField(
      controller: c.texto,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
      ],
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        helperText: helper.isEmpty ? null : helper,
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        isDense: widget.dense,
        suffixIcon: _selectorUnidad(context),
        suffixIconConstraints:
            const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
      onChanged: (_) => widget.onChanged?.call(),
    );
  }

  /// Menú emergente en lugar de `DropdownButton`: dentro de un `suffixIcon` el
  /// dropdown heredaría el ancho del botón (una abreviatura) y recortaría las
  /// etiquetas largas del menú.
  Widget _selectorUnidad(BuildContext context) {
    final theme = Theme.of(context);
    final c = widget.controller;
    return Padding(
      padding: const EdgeInsets.only(left: 4, right: 6),
      child: PopupMenuButton<UnidadTiempo>(
        initialValue: c.unidad,
        tooltip: 'Unidad de tiempo',
        position: PopupMenuPosition.under,
        padding: EdgeInsets.zero,
        borderRadius: BorderRadius.circular(8),
        itemBuilder: (_) => [
          for (final u in UnidadTiempo.values)
            PopupMenuItem(
              value: u,
              height: 40,
              child: Row(children: [
                Icon(
                  u == c.unidad ? Icons.check : null,
                  size: 16,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Text(u.etiqueta),
              ]),
            ),
        ],
        onSelected: (u) {
          c.unidad = u;
          widget.onChanged?.call();
        },
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(
            c.unidad.abrev,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: widget.dense ? 12 : 13,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          Icon(Icons.arrow_drop_down,
              size: 20, color: theme.colorScheme.primary),
        ]),
      ),
    );
  }
}
