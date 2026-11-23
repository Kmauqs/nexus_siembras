import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';
import 'core/log.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'services/variedades_comunitarias_service.dart';
import 'state/app_state.dart';
import 'state/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Config empaquetada. Android no incluye assets cuyo nombre empieza por
  // '.' (p. ej. `.env` en la raíz), así que la fuente canónica es
  // `assets/config/app.env`. `.env` en la raíz queda como respaldo en
  // desarrollo (Windows/desktop). Sin config → modo 100% local.
  var envCargado = false;
  for (final nombre in const ['assets/config/app.env', '.env']) {
    try {
      await dotenv.load(fileName: nombre);
      envCargado = true;
      break;
    } catch (_) {}
  }
  if (!envCargado) {
    // Sin archivo: la app arranca en modo local.
  }

  // Auditoría P8: pintar la UI primero. Supabase y notificaciones se
  // inicializan DESPUÉS del primer frame para no bloquear el arranque
  // visual (antes, una red lenta retrasaba el splash completo).
  // `supabaseReadyProvider` notifica a los providers de auth cuando la
  // init termina, así la sesión aparece de forma reactiva.
  final container = ProviderContainer();
  runApp(UncontrolledProviderScope(
    container: container,
    child: const NexusSiembrasApp(),
  ));

  WidgetsBinding.instance.addPostFrameCallback((_) {
    Future(() async {
      try {
        // Supabase (no-op si SUPABASE_URL no está configurada)
        await SupabaseService.instance.init();
        container.read(supabaseReadyProvider.notifier).state =
            SupabaseService.instance.isInitialized;
        // Banco comunitario de variedades → espejo local (v18).
        if (SupabaseService.instance.client?.auth.currentSession != null) {
          unawaited(VariedadesComunitariasService.sincronizarEnLocal(
              container.read(databaseProvider)));
        }
      } catch (e) {
        Log.e('[main] init Supabase diferida falló', e);
      } finally {
        // Marca fin del intento aunque falle: la UI deja de tratar
        // "pendiente" como "sin nube" y no bloquea los TextField.
        container.read(supabaseInitDoneProvider.notifier).state = true;
      }
      try {
        // Notificaciones locales (no-op en Windows/Web/macOS Desktop)
        await NotificationService.instance.init();
      } catch (e) {
        Log.e('[main] init notificaciones falló', e);
      }
    });
  });
}
