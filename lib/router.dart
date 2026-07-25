import 'package:go_router/go_router.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/crops/crops_list_screen.dart';
import 'features/crops/add_crop_screen.dart';
import 'features/crops/crop_detail_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/map/map_screen.dart';
import 'features/schedule/schedule_screen.dart';
import 'features/inventory/inventory_screen.dart';
import 'features/purchases/purchases_screen.dart';
import 'features/plants/plants_screen.dart';
import 'features/suppliers/suppliers_screen.dart';
import 'features/pathologies/pathologies_screen.dart';
import 'features/trash/trash_screen.dart';
import 'features/soil/soil_analysis_list_screen.dart';
import 'features/soil/add_soil_analysis_screen.dart';
import 'features/soil/soil_analysis_detail_screen.dart';
import 'features/soil/plot_conditions_screen.dart';
import 'features/predios/predios_admin_screen.dart';
import 'features/predios/predio_detail_screen.dart';
import 'features/predios/lote_editor_screen.dart';
import 'features/auth/auth_screen.dart';
import 'features/reports/reports_screen.dart';
import 'features/wizard/wizard_screen.dart';

final appRouter = GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(path: '/',            builder: (_, __) => const DashboardScreen()),
    GoRoute(path: '/crops',       builder: (_, __) => const CropsListScreen()),
    GoRoute(
      path: '/crops/:id',
      builder: (_, state) => CropDetailScreen(
        cultivoId: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(path: '/add',         builder: (_, __) => const AddCropScreen()),
    GoRoute(path: '/settings',    builder: (_, __) => const SettingsScreen()),
    GoRoute(path: '/map',         builder: (_, __) => const MapScreen()),
    GoRoute(path: '/schedule',    builder: (_, __) => const ScheduleScreen()),
    GoRoute(path: '/inventory',   builder: (_, __) => const InventoryScreen()),
    GoRoute(path: '/purchases',   builder: (_, __) => const PurchasesScreen()),
    GoRoute(path: '/plants',      builder: (_, __) => const PlantsScreen()),
    GoRoute(path: '/suppliers',   builder: (_, __) => const SuppliersScreen()),
    GoRoute(path: '/pathologies', builder: (_, __) => const PathologiesScreen()),
    GoRoute(path: '/trash',       builder: (_, __) => const TrashScreen()),
    GoRoute(path: '/soil-analysis',
        builder: (_, __) => const SoilAnalysisListScreen()),
    GoRoute(path: '/soil-analysis/add',
        builder: (_, __) => const AddSoilAnalysisScreen()),
    GoRoute(
      path: '/soil-analysis/:id',
      builder: (_, state) => SoilAnalysisDetailScreen(
        id: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(path: '/plot-conditions',
        builder: (_, __) => const PlotConditionsScreen()),
    GoRoute(path: '/predios',
        builder: (_, __) => const PrediosAdminScreen()),
    GoRoute(
      path: '/predios/:id',
      builder: (_, state) => PredioDetailScreen(
        predioId: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(
      path: '/predios/:id/lotes/new',
      builder: (_, state) => LoteEditorScreen(
        predioId: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(
      path: '/predios/:id/lotes/:loteId',
      builder: (_, state) => LoteEditorScreen(
        predioId: int.tryParse(state.pathParameters['id'] ?? '0') ?? 0,
        loteId: int.tryParse(state.pathParameters['loteId'] ?? '0') ?? 0,
      ),
    ),
    GoRoute(path: '/auth', builder: (_, __) => const AuthScreen()),
    GoRoute(path: '/wizard', builder: (_, __) => const WizardScreen()),
    GoRoute(path: '/reports', builder: (_, __) => const ReportsScreen()),
  ],
);
