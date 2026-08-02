import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/app_nav.dart';
import 'package:path_provider/path_provider.dart';
import '../../core/theme/themes.dart';
import '../../core/widgets/app_shell.dart';
import '../../services/eppo_client.dart';
import '../../services/maintenance_service.dart';
import '../../services/notification_service.dart';
import '../../state/app_state.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(appStyleProvider);
    final locale = ref.watch(localeProvider);
    final unit = ref.watch(unitSystemProvider);
    final currency = ref.watch(currencyProvider);

    return AppShell(
      title: 'Configuración',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Estilo de interfaz', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  SegmentedButton<AppStyle>(
                    segments: const [
                      ButtonSegment(value: AppStyle.accesible, label: Text('Accesible'), icon: Icon(Icons.accessibility)),
                      ButtonSegment(value: AppStyle.material,  label: Text('Material'),  icon: Icon(Icons.design_services)),
                    ],
                    selected: {style},
                    onSelectionChanged: (s) =>
                        ref.read(appStyleProvider.notifier).state = s.first,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Idioma', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButton<Locale>(
                    value: locale,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: Locale('es'), child: Text('Español')),
                      DropdownMenuItem(value: Locale('en'), child: Text('English')),
                      DropdownMenuItem(value: Locale('pt'), child: Text('Português')),
                    ],
                    onChanged: (v) => v != null
                        ? ref.read(localeProvider.notifier).state = v
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sistema de unidades', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: unit,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'SI',       child: Text('Internacional (SI)')),
                      DropdownMenuItem(value: 'imperial', child: Text('Imperial')),
                      DropdownMenuItem(value: 'tecnico',  child: Text('Técnico (kgf)')),
                      DropdownMenuItem(value: 'cgs',      child: Text('Cegesimal (cgs)')),
                    ],
                    onChanged: (v) => v != null
                        ? ref.read(unitSystemProvider.notifier).state = v
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Moneda', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: currency,
                    isExpanded: true,
                    items: kSupportedCurrencies
                        .map((c) => DropdownMenuItem(
                              value: c.code,
                              child: Text(c.label, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) => v != null
                        ? ref.read(currencyProvider.notifier).state = v
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Ecuador, Panamá y Puerto Rico circulan USD; Panamá también emite Balboa (PAB) a la par.',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          const _ComunidadCard(),
          const SizedBox(height: 8),
          const _EppoCard(),
          const SizedBox(height: 8),
          const _NotificacionesCard(),
          const SizedBox(height: 8),
          const _BackupCard(),
          const SizedBox(height: 8),
          const _MantenimientoCard(),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Condiciones del predio',
                      style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: () => AppNav.open(context, '/plot-conditions'),
                    icon: const Icon(Icons.thermostat),
                    label: const Text('Editar condiciones edafoclim.'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Card de consentimiento comunitario (patologías compartidas).
class _ComunidadCard extends ConsumerWidget {
  const _ComunidadCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCfg = ref.watch(configProvider);
    return Card(
      color: Colors.green.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.public, color: Colors.green),
              const SizedBox(width: 6),
              Text('Comunidad NEXUS',
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 4),
            Text(
                'Contribuir con reportes anónimos de patologías al mapa '
                'de calor comunitario. Al desactivar, tus reportes '
                'previamente compartidos permanecen; los nuevos no se subirán.',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            asyncCfg.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (cfg) {
                if (cfg == null) return const SizedBox.shrink();
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Compartir patologías'),
                  subtitle: Text(cfg.consentimientoPatologias
                      ? 'Activo — contribuyes al mapa comunitario'
                      : 'Inactivo — tus reportes se guardan solo local'),
                  value: cfg.consentimientoPatologias,
                  onChanged: (v) => ref
                      .read(dataMutationsProvider)
                      .savePreferences(consentimientoPatologias: v),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de configuración de notificaciones locales.
class _NotificacionesCard extends ConsumerWidget {
  const _NotificacionesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCfg = ref.watch(configProvider);
    final soportado = NotificationService.instance.soportado;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.notifications_active, color: Colors.orange),
              const SizedBox(width: 6),
              Text('Notificaciones',
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            if (!soportado)
              Text(
                  'Las notificaciones locales solo están disponibles en Android e iOS. '
                  'En Windows / macOS / Web esta sección no tiene efecto.',
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).hintColor)),
            asyncCfg.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => Text('Error: $e'),
              data: (cfg) {
                if (cfg == null) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Recordatorios de eventos'),
                      subtitle: const Text(
                          'Alertas antes de abonar, cosechar, etc.'),
                      value: cfg.notificacionesHabilitadas,
                      onChanged: soportado
                          ? (v) => ref
                              .read(dataMutationsProvider)
                              .updateConfigNotificaciones(
                                  habilitadas: v,
                                  antelacionDias:
                                      cfg.notificacionAntelacionDias)
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Text('Avisar con antelación de',
                        style: TextStyle(
                            fontSize: 13,
                            color: Theme.of(context).hintColor)),
                    const SizedBox(height: 6),
                    DropdownButton<int>(
                      value: cfg.notificacionAntelacionDias,
                      isExpanded: true,
                      onChanged: (soportado && cfg.notificacionesHabilitadas)
                          ? (v) {
                              if (v == null) return;
                              ref
                                  .read(dataMutationsProvider)
                                  .updateConfigNotificaciones(
                                      habilitadas:
                                          cfg.notificacionesHabilitadas,
                                      antelacionDias: v);
                            }
                          : null,
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('1 día antes')),
                        DropdownMenuItem(
                            value: 3, child: Text('3 días antes (recomendado)')),
                        DropdownMenuItem(value: 7, child: Text('7 días antes')),
                        DropdownMenuItem(
                            value: 14, child: Text('14 días antes')),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      OutlinedButton.icon(
                        onPressed: soportado
                            ? () async {
                                await NotificationService.instance
                                    .pedirPermisos();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Permiso solicitado al sistema.')));
                                }
                              }
                            : null,
                        icon: const Icon(Icons.lock_open, size: 18),
                        label: const Text('Permisos'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: soportado
                            ? () async {
                                await ref
                                    .read(dataMutationsProvider)
                                    .mostrarNotifPrueba();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Notificación enviada.')));
                                }
                              }
                            : null,
                        icon: const Icon(Icons.notifications, size: 18),
                        label: const Text('Probar'),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text(
                        'El aviso se dispara a las 8:00 AM del día calculado. '
                        'Solo se notifican eventos de cultivos activos del predio.',
                        style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(context).hintColor)),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Card de export/import JSON del predio activo.
class _BackupCard extends ConsumerStatefulWidget {
  const _BackupCard();

  @override
  ConsumerState<_BackupCard> createState() => _BackupCardState();
}

class _BackupCardState extends ConsumerState<_BackupCard> {
  bool _exportando = false;
  bool _importando = false;

  Future<void> _exportar() async {
    setState(() => _exportando = true);
    try {
      final predioId = ref.read(activePredioIdProvider);
      final json = await ref
          .read(backupServiceProvider)
          .exportarPredio(predioId);
      // Guarda en el directorio "Documentos" (o Descargas si es Android).
      final dir = await _dirDeDescarga();
      final ts = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final file = File('${dir.path}/nexus_backup_$ts.json');
      await file.writeAsString(json);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Backup guardado en: ${file.path}'),
          duration: const Duration(seconds: 6)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _exportando = false);
    }
  }

  Future<Directory> _dirDeDescarga() async {
    try {
      // Android/iOS: Documents. Windows/macOS/Linux: Documents también.
      return await getApplicationDocumentsDirectory();
    } catch (_) {
      return Directory.systemTemp;
    }
  }

  Future<void> _importar() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
      dialogTitle: 'Seleccionar backup JSON',
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    // Confirmación destructiva
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Importar backup'),
        content: const Text(
            'Se creará un NUEVO predio con los datos del archivo. '
            'Tus predios actuales NO se modifican.\n\n'
            '¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Importar')),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _importando = true);
    try {
      final content = await File(path).readAsString();
      // Valida rápidamente que sea JSON antes de tocar la BD
      jsonDecode(content);
      final res = await ref
          .read(backupServiceProvider)
          .importarPredio(content, reemplazar: false);
      // Activa el predio recién importado
      await ref
          .read(dataMutationsProvider)
          .setPredioActivo(res.predioId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Importado: ${res.cultivos} cultivos · ${res.lotes} lotes · '
              '${res.eventos} eventos · ${res.tareas} tareas'),
          duration: const Duration(seconds: 6)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error al importar: $e')));
    } finally {
      if (mounted) setState(() => _importando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _exportando || _importando;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.backup, color: Colors.blue),
              const SizedBox(width: 6),
              Text('Backup y restauración',
                  style: Theme.of(context).textTheme.titleMedium),
            ]),
            const SizedBox(height: 8),
            Text(
                'Exporta el predio activo completo a un archivo JSON. '
                'Al importar, se crea un nuevo predio (no sobrescribe).',
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).hintColor)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: busy ? null : _exportar,
                  icon: _exportando
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.file_download, size: 18),
                  label:
                      Text(_exportando ? 'Exportando…' : 'Exportar predio'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: busy ? null : _importar,
                  icon: _importando
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.file_upload, size: 18),
                  label: Text(_importando ? 'Importando…' : 'Importar'),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Text(
                'Incluye: cultivos, eventos, tareas, insumos, inventario, '
                'compras, análisis de suelo, condiciones, lotes.',
                style: TextStyle(
                    fontSize: 11, color: Theme.of(context).hintColor)),
          ],
        ),
      ),
    );
  }
}

/// Card de mantenimiento de la BD: depurar local (hard-delete de
/// soft-deletes) y reemplazar contenido de la nube con el local depurado.
class _MantenimientoCard extends ConsumerStatefulWidget {
  const _MantenimientoCard();

  @override
  ConsumerState<_MantenimientoCard> createState() =>
      _MantenimientoCardState();
}

class _MantenimientoCardState extends ConsumerState<_MantenimientoCard> {
  SoftDeleteStats? _stats;
  bool _cargandoStats = false;
  bool _depurando = false;
  bool _reemplazando = false;

  @override
  void initState() {
    super.initState();
    _refrescarStats();
  }

  Future<void> _refrescarStats() async {
    setState(() => _cargandoStats = true);
    try {
      final s = await ref.read(maintenanceServiceProvider).contarSoftDeletes();
      if (mounted) setState(() => _stats = s);
    } finally {
      if (mounted) setState(() => _cargandoStats = false);
    }
  }

  Future<void> _depurarLocal() async {
    final n = _stats?.total ?? 0;
    if (n == 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No hay registros con soft-delete para depurar')));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Depurar base de datos local'),
        content: Text(
            'Se eliminarán PERMANENTEMENTE $n registro(s) con marca de '
            'borrado, incluidos los que ya no aparecen en la Papelera. '
            'Esta acción no se puede deshacer.\n\n¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Depurar')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _depurando = true);
    try {
      final eliminados =
          await ref.read(maintenanceServiceProvider).depurarLocal();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$eliminados registro(s) eliminado(s) localmente'),
            backgroundColor: Colors.green));
      }
      await _refrescarStats();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _depurando = false);
    }
  }

  Future<void> _reemplazarNube() async {
    // Verifica si tengo predios compartidos donde NO soy propietario.
    // En ese caso la operación es peligrosa: al hacer push completo
    // duplica registros ajenos con mi owner_id.
    final predios = ref.read(prediosProvider).maybeWhen(
        data: (l) => l, orElse: () => const []);
    final currentUser = ref.read(currentUserProvider);
    final tienePrediosCompartidos = predios.any((p) =>
        p.ownerUserId != null &&
        currentUser != null &&
        p.ownerUserId != currentUser.id);
    if (tienePrediosCompartidos) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Operación no permitida'),
          content: const Text(
              'Tienes predios compartidos donde eres colaborador, no '
              'propietario. Ejecutar "Reemplazar nube con local" duplicaría '
              'esos predios en el servidor porque los subiría con tu '
              'usuario como dueño.\n\n'
              'Esta operación solo debe usarse en cuentas de PROPIETARIO '
              'con predios propios.'),
          actions: [
            FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Entendido')),
          ],
        ),
      );
      return;
    }

    final ok1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reemplazar datos en la nube'),
        content: const Text(
            'ACCIÓN DESTRUCTIVA:\n\n'
            '1. Se depurarán localmente todos los soft-deletes.\n'
            '2. Se ELIMINARÁN TODOS TUS DATOS en Supabase.\n'
            '3. Se subirá el estado local depurado como versión definitiva.\n\n'
            'Úsalo solo si el local es la fuente confiable y la nube '
            'quedó en un estado inconsistente.\n\n¿Continuar?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton.tonal(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Entiendo, continuar')),
        ],
      ),
    );
    if (ok1 != true) return;
    final ok2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('¿Estás seguro?'),
        content: const Text(
            'Esta es tu última oportunidad para cancelar. Los datos en '
            'Supabase se perderán y serán reemplazados por el estado local.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('SÍ, REEMPLAZAR')),
        ],
      ),
    );
    if (ok2 != true) return;

    setState(() => _reemplazando = true);
    try {
      final res =
          await ref.read(maintenanceServiceProvider).reemplazarNubeConLocal();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(res.exito
              ? '✓ Depurados: ${res.depuradosLocal} local · Subidos: ${res.subidos} a la nube'
              : 'Error: ${res.error}'),
          backgroundColor: res.exito ? Colors.green : Colors.red,
          duration: const Duration(seconds: 6),
        ));
      }
      await _refrescarStats();
    } finally {
      if (mounted) setState(() => _reemplazando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final logged = ref.watch(isLoggedInProvider);
    final busy = _depurando || _reemplazando;
    return Card(
      color: Colors.red.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.build, color: Colors.red),
              const SizedBox(width: 6),
              Text('Mantenimiento de BD',
                  style: theme.textTheme.titleMedium),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh, size: 18),
                tooltip: 'Actualizar estadísticas',
                onPressed: _cargandoStats ? null : _refrescarStats,
              ),
            ]),
            const SizedBox(height: 4),
            Text(
                'Operaciones destructivas para corregir inconsistencias. '
                'Úsalas solo si estás seguro.',
                style: TextStyle(fontSize: 12, color: theme.hintColor)),
            const SizedBox(height: 12),
            if (_cargandoStats)
              const LinearProgressIndicator()
            else if (_stats == null || _stats!.total == 0)
              const Text('✓ No hay registros con soft-delete pendientes.',
                  style: TextStyle(color: Colors.green, fontSize: 13))
            else ...[
              Text('Registros con soft-delete:',
                  style: theme.textTheme.bodyMedium),
              const SizedBox(height: 4),
              ..._stats!.porTabla.entries.map((e) => Padding(
                    padding: const EdgeInsets.only(left: 8, top: 2),
                    child: Row(children: [
                      const Icon(Icons.circle, size: 6, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text('${e.key}: ${e.value}',
                          style: const TextStyle(fontSize: 12)),
                    ]),
                  )),
              const SizedBox(height: 4),
              Text('Total: ${_stats!.total} registro(s)',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 13)),
            ],
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : _depurarLocal,
              icon: _depurando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cleaning_services, size: 18),
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.orange.shade700),
              label: Text(_depurando
                  ? 'Depurando…'
                  : 'Depurar base local (hard-delete)'),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: (busy || !logged) ? null : _reemplazarNube,
              icon: _reemplazando
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.cloud_upload, size: 18),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              label: Text(_reemplazando
                  ? 'Reemplazando nube…'
                  : 'Reemplazar nube con local'),
            ),
            if (!logged)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                    'Inicia sesión para reemplazar la nube.',
                    style: TextStyle(
                        fontSize: 11,
                        color: theme.hintColor,
                        fontStyle: FontStyle.italic)),
              ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Fase 3i-B — EPPO Global Database
// ============================================================

/// Card para configurar el token personal de EPPO Global Database.
/// Al guardarlo, el botón "Actualizar" de Patologías consulta también
/// la API remota para enriquecer el catálogo local.
class _EppoCard extends ConsumerStatefulWidget {
  const _EppoCard();
  @override
  ConsumerState<_EppoCard> createState() => _EppoCardState();
}

class _EppoCardState extends ConsumerState<_EppoCard> {
  final _ctrl = TextEditingController();
  bool _mostrar = false;
  bool _procesando = false;
  bool _hidratado = false;
  String? _mensaje;
  bool _mensajeOk = false;
  EppoStatus? _apiStatus;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _refrescarStatus(String token) async {
    if (token.isEmpty) return;
    final client = EppoClient(token);
    try {
      final s = await client.checkStatus();
      if (mounted) setState(() => _apiStatus = s);
    } finally {
      client.close();
    }
  }

  void _hidratarDesdeConfig(String? tokenActual) {
    if (_hidratado) return;
    _hidratado = true;
    _ctrl.text = tokenActual ?? '';
    if ((tokenActual ?? '').isNotEmpty) {
      // Fire-and-forget: refrescar status del API sin bloquear el build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _refrescarStatus(tokenActual!);
      });
    }
  }

  Future<void> _verificar() async {
    final token = _ctrl.text.trim();
    if (token.isEmpty) {
      setState(() {
        _mensaje = 'Ingresa un token para verificar.';
        _mensajeOk = false;
      });
      return;
    }
    setState(() {
      _procesando = true;
      _mensaje = null;
    });
    try {
      await EppoClient(token).verificarTokenConError();
      setState(() {
        _mensaje = '✓ Token válido — conexión con EPPO Data Portal OK.';
        _mensajeOk = true;
      });
      // Refresca el chip de status del API.
      unawaited(_refrescarStatus(token));
    } on EppoException catch (e) {
      setState(() {
        _mensaje = '✗ ${e.mensaje}';
        _mensajeOk = false;
      });
    } catch (e) {
      setState(() {
        _mensaje = 'Error de red: $e';
        _mensajeOk = false;
      });
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  Future<void> _guardar() async {
    final token = _ctrl.text.trim();
    setState(() => _procesando = true);
    try {
      await ref.read(dataMutationsProvider).savePreferences(eppoToken: token);
      if (mounted) {
        setState(() {
          _mensaje = token.isEmpty
              ? 'Token eliminado. La app volverá al catálogo local.'
              : '✓ Token guardado. El botón "Actualizar" de Patologías ya '
                  'complementará con datos de EPPO.';
          _mensajeOk = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _mensaje = 'Error al guardar: $e';
          _mensajeOk = false;
        });
      }
    } finally {
      if (mounted) setState(() => _procesando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configAsync = ref.watch(configProvider);
    return configAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (cfg) {
        _hidratarDesdeConfig(cfg?.eppoToken);
        final tieneToken = (cfg?.eppoToken ?? '').isNotEmpty;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.travel_explore,
                      color: theme.colorScheme.primary, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('EPPO Global Database',
                        style: theme.textTheme.titleMedium),
                  ),
                  if (_apiStatus != null) ...[
                    Chip(
                      avatar: Icon(
                        _apiStatus!.ok ? Icons.circle : Icons.error,
                        size: 12,
                        color: _apiStatus!.ok
                            ? Colors.green.shade700
                            : Colors.red.shade700,
                      ),
                      label: Text(
                        _apiStatus!.ok
                            ? 'API ${_apiStatus!.version ?? "OK"}'
                            : 'API caída',
                        style: const TextStyle(fontSize: 10),
                      ),
                      backgroundColor: _apiStatus!.ok
                          ? const Color(0xFFDCF5D6)
                          : Colors.red.shade50,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (tieneToken)
                    const Chip(
                      label: Text('activo',
                          style: TextStyle(fontSize: 10)),
                      backgroundColor: Color(0xFFDCF5D6),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                ]),
                const SizedBox(height: 6),
                Text(
                    'Registra tu token personal para complementar el catálogo '
                    'local con datos remotos de EPPO. Se consulta al pulsar '
                    '"Actualizar" en Patologías. Obtén tu token en tu perfil '
                    'de data.eppo.int.',
                    style:
                        TextStyle(fontSize: 12, color: theme.hintColor)),
                const SizedBox(height: 10),
                TextField(
                  controller: _ctrl,
                  obscureText: !_mostrar,
                  decoration: InputDecoration(
                    labelText: 'Authtoken EPPO',
                    hintText: 'Cadena alfanumérica de tu cuenta EPPO',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: Icon(_mostrar
                          ? Icons.visibility_off
                          : Icons.visibility),
                      tooltip: _mostrar ? 'Ocultar' : 'Mostrar',
                      onPressed: () =>
                          setState(() => _mostrar = !_mostrar),
                    ),
                  ),
                ),
                if (_mensaje != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: _mensajeOk
                          ? Colors.green.shade50
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: _mensajeOk
                              ? Colors.green.shade200
                              : Colors.red.shade200),
                    ),
                    child: Text(_mensaje!,
                        style: TextStyle(
                            fontSize: 12,
                            color: _mensajeOk
                                ? Colors.green.shade900
                                : Colors.red.shade900)),
                  ),
                ],
                const SizedBox(height: 10),
                Row(children: [
                  OutlinedButton.icon(
                    onPressed: _procesando ? null : _verificar,
                    icon: _procesando
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child:
                                CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering, size: 16),
                    label: const Text('Verificar'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _procesando ? null : _guardar,
                    icon: const Icon(Icons.save, size: 16),
                    label: const Text('Guardar'),
                  ),
                ]),
              ],
            ),
          ),
        );
      },
    );
  }
}
