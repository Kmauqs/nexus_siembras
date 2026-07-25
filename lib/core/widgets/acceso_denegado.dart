import 'package:flutter/material.dart';

/// Widget mostrado cuando un usuario con rol insuficiente entra a una
/// pantalla de edición (típicamente un consultor que llega por navegación
/// interna o por URL directa).
///
/// Se usa como reemplazo del cuerpo de la pantalla, dejando visible el
/// AppShell/AppBar para que el usuario pueda volver atrás sin quedar
/// atrapado en la pantalla.
class AccesoDenegado extends StatelessWidget {
  const AccesoDenegado({
    super.key,
    required this.mensaje,
    this.icono = Icons.visibility_off_outlined,
  });

  final String mensaje;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 56, color: theme.hintColor),
            const SizedBox(height: 16),
            Text(
              'Solo lectura',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.hintColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              mensaje,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
