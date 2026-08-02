import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../i18n/app_localizations.dart';
import '../navigation/app_nav.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';

/// Scaffold reutilizable: AppBar con título a la izquierda + menú;
/// Volver / Inicio / Sync como botones flotantes al alcance del pulgar.
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
  /// Widget opcional anclado al pie (debajo de la barra de navegación).
  final Widget? bottomBar;

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    final atHome = AppNav.isHome(context);
    final showBack = canPop || !atHome;

    return PopScope(
      canPop: canPop || atHome,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        AppNav.home(context);
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          titleSpacing: 16,
          centerTitle: false,
          title: Text(
            title,
            maxLines: 2,
            softWrap: true,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            ...?actions,
            Builder(
              builder: (ctx) => IconButton(
                icon: const Icon(Icons.menu),
                tooltip: context.t('menuTitle'),
                onPressed: () => Scaffold.of(ctx).openEndDrawer(),
              ),
            ),
          ],
        ),
        endDrawer: const _MainDrawer(),
        body: child,
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Selector u otros bars van arriba; la nav del pulgar queda al borde.
            if (bottomBar != null) bottomBar!,
            AppThumbNav(showBack: showBack),
          ],
        ),
        floatingActionButton: floatingActionButton,
      ),
    );
  }
}

/// Barra inferior con Volver, Inicio y Sincronizar (zona del pulgar).
class AppThumbNav extends StatelessWidget {
  const AppThumbNav({super.key, required this.showBack});

  final bool showBack;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ThumbNavButton(
                icon: Icons.arrow_back,
                label: context.t('menuBack'),
                enabled: showBack,
                onPressed: showBack ? () => AppNav.back(context) : null,
              ),
              _ThumbNavButton(
                icon: Icons.home,
                label: context.t('menuHome'),
                onPressed: () => AppNav.home(context),
              ),
              const _SyncThumbButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThumbNavButton extends StatelessWidget {
  const _ThumbNavButton({
    required this.icon,
    required this.label,
    this.onPressed,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final active = enabled && onPressed != null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton.small(
          heroTag: 'thumb_$label',
          tooltip: label,
          backgroundColor:
              active ? scheme.primary : scheme.surfaceContainerHighest,
          foregroundColor:
              active ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.38),
          elevation: active ? 3 : 0,
          onPressed: onPressed,
          child: Icon(icon),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: 76,
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: active
                  ? scheme.onSurface
                  : scheme.onSurface.withValues(alpha: 0.38),
            ),
          ),
        ),
      ],
    );
  }
}

/// Sync como botón de la barra inferior (misma lógica que el antiguo badge).
class _SyncThumbButton extends ConsumerWidget {
  const _SyncThumbButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final logged = ref.watch(isLoggedInProvider);
    if (!logged) {
      return _ThumbNavButton(
        icon: Icons.cloud_outlined,
        label: context.t('menuSync'),
        onPressed: () => AppNav.open(context, '/auth'),
      );
    }

    final async = ref.watch(pendingSyncCountProvider);
    return async.when(
      loading: () => _ThumbNavButton(
        icon: Icons.cloud_queue,
        label: context.t('menuSync'),
        onPressed: () => AppNav.open(context, '/auth'),
      ),
      error: (_, __) => _ThumbNavButton(
        icon: Icons.cloud_off,
        label: context.t('menuSync'),
        onPressed: () => AppNav.open(context, '/auth'),
      ),
      data: (n) {
        final pending = n > 0;
        final label = pending
            ? context.t('syncPending', {'n': '$n'})
            : context.t('syncOk');
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                FloatingActionButton.small(
                  heroTag: 'thumb_sync',
                  tooltip: label,
                  backgroundColor:
                      pending ? scheme.tertiary : scheme.primary,
                  foregroundColor: scheme.onPrimary,
                  elevation: 3,
                  onPressed: () => AppNav.open(context, '/auth'),
                  child: Icon(
                    pending ? Icons.cloud_upload : Icons.cloud_done,
                  ),
                ),
                if (pending)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade700,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 18, minHeight: 16),
                      child: Text(
                        n > 99 ? '99+' : '$n',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            SizedBox(
              width: 76,
              child: Text(
                context.t('menuSync'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: scheme.onSurface),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _MainDrawer extends ConsumerWidget {
  const _MainDrawer();

  // Fase B4 (i18n): el 3.º elemento es la CLAVE ARB, no el literal.
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
                    if (path == '/') {
                      AppNav.home(context);
                    } else {
                      AppNav.open(context, path);
                    }
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
