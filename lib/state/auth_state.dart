// Providers Riverpod para el estado de autenticación Supabase.
//
// Diseño:
//   - `supabaseInitProvider`: bool que indica si Supabase se inicializó.
//     Si no (config .env ausente o inválida), la app queda en modo 100%
//     local y todos los providers de auth reportan "sin sesión".
//   - `authSessionProvider`: StreamProvider del Session actual de Supabase.
//   - `currentUserProvider`: usuario activo (o null si no logueado).
//   - `isLoggedInProvider`: bool derivado, útil para redirecciones.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';

/// Estado reactivo de la inicialización de Supabase (auditoría P8).
/// Antes era un `Provider` estático que quedaba congelado con el valor
/// del arranque; ahora `main.dart` lo actualiza cuando la init diferida
/// termina, y todos los providers derivados se reevalúan.
final supabaseReadyProvider =
    StateProvider<bool>((ref) => SupabaseService.instance.isInitialized);

/// True si Supabase se inicializó correctamente.
/// Si es false, la app funciona 100% local (sin sync ni auth).
/// (Conserva el tipo `Provider<bool>` para no tocar los call sites.)
final supabaseInitProvider =
    Provider<bool>((ref) => ref.watch(supabaseReadyProvider));

/// Stream reactivo del estado de sesión Supabase.
/// Emite cuando el usuario inicia/cierra sesión.
final authSessionProvider = StreamProvider<Session?>((ref) {
  final ready = ref.watch(supabaseInitProvider);
  if (!ready) {
    // Modo local: nunca hay sesión.
    return const Stream.empty();
  }
  final client = Supabase.instance.client;
  // Sesión actual (síncrono) + cambios futuros
  return Stream<Session?>.multi((controller) {
    controller.add(client.auth.currentSession);
    final sub = client.auth.onAuthStateChange.listen((event) {
      controller.add(event.session);
    });
    controller.onCancel = sub.cancel;
  });
});

/// Usuario Supabase actualmente logueado (o null).
///
/// Fuente única de verdad: `Supabase.instance.client.auth.currentSession`.
/// El StreamProvider se usa solo como TRIGGER de reevaluación: cualquier
/// evento en el stream (login/logout/refresh) marca este provider como
/// obsoleto y Riverpod re-lee la sesión de Supabase.
///
/// Por qué no usar el `data:` del stream directamente: durante la
/// transición del árbol de widgets (onboarding → router), el StreamProvider
/// puede emitir transitoriamente `data(null)` mientras se re-suscribe,
/// aunque la sesión real esté viva en Supabase. Al leer siempre desde
/// `Supabase.instance` evitamos ese race condition.
final currentUserProvider = Provider<User?>((ref) {
  // Trigger de reevaluación cuando Supabase emita cambios de auth.
  ref.watch(authSessionProvider);
  final ready = ref.watch(supabaseInitProvider);
  if (!ready) return null;
  return Supabase.instance.client.auth.currentSession?.user;
});

/// True si el usuario está logueado. Útil para redirecciones y UI.
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProvider) != null;
});
