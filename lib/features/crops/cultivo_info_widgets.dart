import 'package:flutter/material.dart';
import '../../core/theme/themes.dart';
import '../../state/data_state.dart';

/// Chip con el tipo de cultivo (ciclo único / perenne).
class TipoCultivoChip extends StatelessWidget {
  const TipoCultivoChip({super.key, required this.cultivo});
  final Cultivo cultivo;

  @override
  Widget build(BuildContext context) {
    return Chip(
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      avatar: Icon(
        cultivo.esPerenne ? Icons.park : Icons.timelapse,
        size: 16,
        color: cultivo.esPerenne ? Colors.green.shade700 : Colors.blue.shade700,
      ),
      label: Text(
        cultivo.tipoCultivoEtiqueta,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Lista de periodos configurados al crear el cultivo.
class PeriodosConfiguradosList extends StatelessWidget {
  const PeriodosConfiguradosList({super.key, required this.cultivo});
  final Cultivo cultivo;

  @override
  Widget build(BuildContext context) {
    final lineas = cultivo.lineasPeriodosConfigurados;
    if (lineas.isEmpty) {
      return Text(
        'Sin periodos configurados',
        style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: lineas
          .map((l) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(Icons.schedule,
                        size: 14, color: Theme.of(context).hintColor),
                    const SizedBox(width: 6),
                    Expanded(child: Text(l, style: const TextStyle(fontSize: 13))),
                  ],
                ),
              ))
          .toList(),
    );
  }
}

/// Cronograma de eventos programados/ejecutados de un cultivo.
///
/// Si [onTapEventoPendiente] no es null, los círculos de eventos aún no
/// ejecutados son clickeables (p. ej. para abrir "Registrar tarea").
class CronogramaCultivoList extends StatelessWidget {
  const CronogramaCultivoList({
    super.key,
    required this.eventos,
    this.onTapEventoPendiente,
  });
  final List<Evento> eventos;
  final ValueChanged<Evento>? onTapEventoPendiente;

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

  static bool _mismaFecha(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static String _etiquetaTipo(String tipo) => switch (tipo.toLowerCase()) {
        'siembra' => 'Siembra',
        'semillero' => 'Semillero',
        'trasplante' => 'Trasplante',
        'abono' => 'Abono',
        'control_fito' => 'Control fitosanitario',
        'observacion' => 'Observación',
        'cosecha' => 'Cosecha',
        'renovacion' => 'Renovación',
        'riego' => 'Riego',
        'poda' => 'Poda',
        _ => tipo.isEmpty
            ? 'Actividad'
            : '${tipo[0].toUpperCase()}${tipo.substring(1)}',
      };

  @override
  Widget build(BuildContext context) {
    if (eventos.isEmpty) {
      return Text(
        'Sin eventos en el cronograma',
        style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
      );
    }
    return Column(
      children: eventos.map((e) {
        final efectiva = e.fechaEfectiva;
        final reprogramado = e.ejecutada &&
            e.fechaEjecutada != null &&
            !_mismaFecha(e.fechaEjecutada!, e.fechaProgramada);
        final vencido = !e.ejecutada && efectiva.isBefore(DateTime.now());
        final color = e.ejecutada
            ? AppThemes.colorOk
            : (vencido ? AppThemes.colorAlert : Colors.grey.shade600);
        final clickable =
            onTapEventoPendiente != null && !e.ejecutada;

        final icon = Icon(
          e.ejecutada ? Icons.check_circle : Icons.radio_button_unchecked,
          size: 18,
          color: color,
        );

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (clickable)
                Tooltip(
                  message: 'Registrar tarea',
                  child: InkWell(
                    onTap: () => onTapEventoPendiente!(e),
                    borderRadius: BorderRadius.circular(16),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: icon,
                    ),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: icon,
                ),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.descripcion,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w500)),
                    Text(
                      reprogramado
                          ? '${_etiquetaTipo(e.tipo)} · Ejecutado: ${_iso(efectiva)} · prog. ${_iso(e.fechaProgramada)}'
                          : '${_etiquetaTipo(e.tipo)} · Fecha: ${_iso(efectiva)}',
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
