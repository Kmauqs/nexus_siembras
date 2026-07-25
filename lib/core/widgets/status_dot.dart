import 'package:flutter/material.dart';
import '../theme/themes.dart';
import '../../data/repositories/cultivo_repository.dart';

/// Círculo de estado clickable (verde/naranja/rojo).
class StatusDot extends StatelessWidget {
  const StatusDot({
    super.key,
    required this.estado,
    this.onTap,
    this.size = 14,
    this.tooltip,
  });

  final EstadoCultivo estado;
  final VoidCallback? onTap;
  final double size;
  final String? tooltip;

  Color get color {
    switch (estado) {
      case EstadoCultivo.verde:   return AppThemes.colorOk;
      case EstadoCultivo.naranja: return AppThemes.colorWarn;
      case EstadoCultivo.rojo:    return AppThemes.colorAlert;
    }
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 2,
          ),
        ],
      ),
    );

    final wrapped = tooltip != null
        ? Tooltip(message: tooltip!, child: dot)
        : dot;

    if (onTap == null) return wrapped;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(size),
      child: Padding(padding: const EdgeInsets.all(4), child: wrapped),
    );
  }
}
