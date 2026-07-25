import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'app.dart';
import 'core/log.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'state/auth_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Config (.env es opcional — la app funciona si no existe)
  try {
    await dotenv.load(fileName: '.env');
  } catch (_) {}

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
      } catch (e) {
        Log.e('[main] init Supabase diferida falló', e);
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
