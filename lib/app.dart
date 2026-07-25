import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/i18n/app_localizations.dart';
import 'core/theme/themes.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'router.dart';
import 'state/app_state.dart';
import 'state/auth_state.dart';
import 'state/data_state.dart';

class NexusSiembrasApp extends ConsumerWidget {
  const NexusSiembrasApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appStyleProvider);
    final locale = ref.watch(localeProvider);
    // Hidratar providers UI desde config persistida (cuando llega).
    ref.listen(configProvider, (prev, next) {
      next.whenData((cfg) {
        if (cfg == null) return;
        ref.read(appStyleProvider.notifier).state = AppThemes.parse(cfg.estiloUi);
        ref.read(localeProvider.notifier).state = Locale(cfg.idioma);
        ref.read(unitSystemProvider.notifier).state = cfg.sistemaUnidades;
        ref.read(currencyProvider.notifier).state = cfg.monedaCodigo;
        // Reprograma notificaciones al arrancar y cada vez que cambie
        // config (habilitación, ventana de aviso).
        ref.read(eventNotificationSyncProvider).sincronizar();
      });
    });

    // Cuando el usuario está logueado, iniciar el auto-sync que escucha
    // cambios de conectividad y reintenta al recuperar red.
    ref.listen<bool>(isLoggedInProvider, (prev, next) {
      if (next) {
        ref.read(autoSyncServiceProvider).iniciar();
      } else {
        ref.read(autoSyncServiceProvider).detener();
      }
    });
    final firstRun = ref.watch(primeraEjecucionProvider);

    if (firstRun) {
      // Onboarding standalone — no usa el router principal.
      return MaterialApp(
        title: 'NEXUS Siembras',
        debugShowCheckedModeBanner: false,
        theme: AppThemes.themeFor(style),
        locale: locale,
        supportedLocales: const [Locale('es'), Locale('en'), Locale('pt')],
        localizationsDelegates: const [
          AppLocalizationsDelegate(), // Fase B4: ARB en runtime
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: const OnboardingScreen(),
      );
    }

    return MaterialApp.router(
      title: 'NEXUS Siembras',
      debugShowCheckedModeBanner: false,
      theme: AppThemes.themeFor(style),
      routerConfig: appRouter,
      locale: locale,
      supportedLocales: const [Locale('es'), Locale('en'), Locale('pt')],
      localizationsDelegates: const [
        AppLocalizationsDelegate(), // Fase B4: ARB en runtime
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
