import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../i18n/app_localizations.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';

/// Scaffold reutilizable con AppBar (home button + menú), body y drawer.
class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.title,
    required this.child,
    this.actions,
    this.floatingActionButton,
    this.bottomBar,
  });

  final String title;
  final Widget child;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  /// Widget opcional anclado al pie de la pantalla (por debajo del scroll).
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Dos accesos a la izquierda: Inicio + Asistente paso a paso
        // (2026-07-20).
        leadingWidth: 96,
        leading: Row(children: [
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: context.t('menuHome'),
            onPressed: () => context.go('/'),
          ),
          IconButton(
            icon: const Icon(Icons.assistant_outlined),
            tooltip: context.t('menuWizard'),
            onPressed: () => context.go('/wizard'),
          ),
        ]),
        title: Text(title),
        centerTitle: true,
        actions: [
          ...?actions,
          const _SyncBadge(),
          // Ícono ☰ manual — Flutter no lo agrega solo para endDrawer.
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              tooltip: context.t('menuTitle'),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
        ],
      ),
      endDrawer: const _MainDrawer(),  // Menú desde la derecha (spec 2.8)
      body: child,
      bottomNavigationBar: bottomBar,
      floatingActionButton: floatingActionButton,
    );
  }
}

class _MainDrawer extends ConsumerWidget {
  const _MainDrawer();

  // Fase B4 (i18n): el 3.º elemento es la CLAVE ARB, no el literal.
  // El texto se resuelve en build con `context.t(...)`.
  static const _items = [
    ('/',            Icons.home,          'menuHome'),
    ('/wizard',      Icons.assistant,     'menuWizard'),
    ('/map',         Icons.map,           'menuMap'),
    ('/add',         Icons.add_circle,    'menuAdd'),
    ('/crops',       Icons.eco,           'menuCrops'),
    ('/schedule',    Icons.calendar_month,'menuSchedule'),
    ('/reports',     Icons.description,   'menuReports'),
    ('/inventory',   Icons.inventory_2,   'menuInventory'),
    ('/purchases',   Icons.receipt_long,  'menuPurchases'),
    ('/plants',      Icons.grass,         'menuPlants'),
    ('/suppliers',   Icons.storefront,    'menuSuppliers'),
    ('/pathologies', Icons.coronavirus,   'menuPathologies'),
    ('/soil-analysis', Icons.science,     'menuSoil'),
    ('/plot-conditions', Icons.thermostat,'menuConditions'),
    ('/predios',     Icons.landscape,     'menuFarms'),
    ('/auth',        Icons.cloud,         'menuAccount'),
    ('/settings',    Icons.settings,      'menuSettings'),
    ('/trash',       Icons.delete,        'menuTrash'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final puedeVerCompras =
        ref.watch(permisosPredioActivoProvider).puedeVerCompras;
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: Theme.of(context).colorScheme.primary),
            child: const Row(
              children: [
                Icon(Icons.eco, color: Colors.white, size: 40),
                SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('NEXUS Siembras',
                        style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                    Text('Control agropecuario',
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: _items.where((it) {
                if (it.$1 == '/purchases') return puedeVerCompras;
                return true;
              }).map((it) {
                final (path, icon, claveArb) = it;
                return ListTile(
                  leading: Icon(icon),
                  title: Text(context.t(claveArb)),
                  onTap: () {
                    Navigator.of(context).pop();
                    context.go(path);
                  },
                );
              }).toList(),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  'assets/images/nc_logo.jpg',
                  height: 32,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 4),
                // Versión leída del pubspec.yaml en runtime (2026-07-20):
                // se actualiza sola con cada release.
                FutureBuilder<PackageInfo>(
                  future: PackageInfo.fromPlatform(),
                  builder: (_, snap) => Text(
                    'v${snap.data?.version ?? '…'} · NEXUS CREATIO',
                    style: const TextStyle(
                        fontSize: 11, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Badge en el AppBar que muestra los cambios locales pendientes de subir
/// a la nube. Solo se muestra si hay sesión activa. Tap → va a /auth para
/// sincronizar.
class _SyncBadge extends ConsumerWidget {
  const _SyncBadge();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logged = ref.watch(isLoggedInProvider);
    if (!logged) return const SizedBox.shrink();
    final async = ref.watch(pendingSyncCountProvider);
    return async.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (n) {
        if (n == 0) {
          return IconButton(
            icon: const Icon(Icons.cloud_done, color: Colors.white70),
            tooltip: context.t('syncOk'),
            onPressed: () => context.go('/auth'),
          );
        }
        return Stack(
          alignment: Alignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.cloud_upload),
              tooltip: context.t('syncPending', {'n': '$n'}),
              onPressed: () => context.go('/auth'),
            ),
            Positioned(
              right: 6,
              top: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.orange,
                  borderRadius: BorderRadius.circular(8),
                ),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 14),
                child: Text(
                  n > 99 ? '99+' : '$n',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
