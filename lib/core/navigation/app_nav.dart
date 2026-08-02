import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Navegación centralizada: mantiene pila para Volver / botón atrás del
/// sistema, y reserva `go('/')` para Inicio (limpia el historial).
class AppNav {
  AppNav._();

  static String locationOf(BuildContext context) {
    try {
      return GoRouterState.of(context).uri.path;
    } catch (_) {
      return '/';
    }
  }

  static bool isHome(BuildContext context) {
    final path = locationOf(context);
    return path.isEmpty || path == '/';
  }

  /// Ir al Dashboard y vaciar el historial.
  static void home(BuildContext context) => context.go('/');

  /// Abrir una ruta apilándola (permite Volver). Si ya estamos en esa
  /// ruta exacta, no hace nada.
  static void open(BuildContext context, String path) {
    final current = locationOf(context);
    if (current == path) return;
    context.push(path);
  }

  /// Volver a la pantalla anterior; si no hay historial y no estamos en
  /// Inicio, ir al Dashboard.
  static void back(BuildContext context) {
    if (context.canPop()) {
      context.pop();
      return;
    }
    if (!isHome(context)) {
      context.go('/');
    }
  }

  /// Tras guardar / cancelar: pop si hay historial, si no `go(fallback)`.
  static void popOrGo(BuildContext context, String fallback) {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(fallback);
    }
  }
}
