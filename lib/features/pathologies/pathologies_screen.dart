import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/app_nav.dart';
import '../../core/theme/themes.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/database/database.dart' as drift;
import '../../state/data_state.dart';
import 'agrupacion_patologias.dart';
import 'patologia_activa_card.dart';
import 'reclasificar_patologia_dialog.dart';
import 'reportar_patologia_modal.dart';
import 'tratamientos_dialog.dart';

class PathologiesScreen extends ConsumerWidget {
  const PathologiesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activas = ref.watch(patologiasActivasProvider);
    final catalogo = ref.watch(patologiasCatalogoProvider);
    final historico = ref.watch(patologiasHistoricoProvider);
    final cultivos = ref.watch(cultivosActivosProvider) +
        ref.watch(cultivosFinalizadosProvider);
    final plantas = ref.watch(plantasProvider);
    final cultivoById = {for (final c in cultivos) c.id: c};
    final plantaById = {for (final p in plantas) p.id: p};
    return AppShell(
      title: 'Patologías',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            FilledButton.icon(
              onPressed: () => _abrirReporte(context, cultivos, plantaById),
              icon: const Icon(Icons.bug_report),
              label: const Text('Reportar'),
            ),
            const SizedBox(width: 8),
            const _BotonActualizarCatalogo(),
          ]),
          const SizedBox(height: 20),
          const Text('🦠 Detecciones activas',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          activas.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
            data: (list) => list.isEmpty
                ? Text('— sin detecciones activas —',
                    style: TextStyle(color: Theme.of(context).hintColor))
                : Column(
                    children: list.map((cp) {
                      final cul = cultivoById[cp.cultivoId];
                      final pl = cul != null ? plantaById[cul.plantaId] : null;
                      return PatologiaActivaCard(
                        cp: cp,
                        plantaNombre: pl?.nombre ?? '?',
                        lote: cul?.lote ?? '?',
                      );
                    }).toList(),
                  ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            const Text('📚 Catálogo',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(width: 6),
            Text('(filtrado por plantas de la BD)',
                style: TextStyle(
                    fontSize: 11,
                    color: Theme.of(context).hintColor,
                    fontStyle: FontStyle.italic)),
          ]),
          const SizedBox(height: 8),
          Builder(builder: (_) {
            final porPlantas = ref.watch(patologiasPorPlantasProvider);
            return porPlantas.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('Error: $e'),
              data: (porPlantasMap) => catalogo.when(
                loading: () => const SizedBox.shrink(),
                error: (e, _) => Text('Error: $e'),
                data: (list) {
                  // Solo mostrar las que afectan a al menos una planta actual.
                  final filtradas =
                      list.where((p) => porPlantasMap.containsKey(p.id)).toList();
                  filtradas.sort((a, b) =>
                      (porPlantasMap[b.id]?.length ?? 0)
                          .compareTo(porPlantasMap[a.id]?.length ?? 0));
                  if (filtradas.isEmpty) {
                    return Text(
                        'Ninguna patología del catálogo afecta a las plantas actuales.\n'
                        'Pulsa "Actualizar" arriba para enriquecer el catálogo con '
                        'las patologías conocidas de las especies de tus variedades.',
                        style: TextStyle(
                            fontSize: 12, color: Theme.of(context).hintColor));
                  }
                  return _CatalogoAgrupado(
                    filtradas: filtradas,
                    porPlantasMap: porPlantasMap,
                  );
                },
              ),
            );
          }),
          const SizedBox(height: 20),
          historico.when(
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
            data: (list) => list.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✅ Histórico curadas',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ...list.map((cp) {
                        final cul = cultivoById[cp.cultivoId];
                        final pl = cul != null ? plantaById[cul.plantaId] : null;
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.check_circle,
                                color: AppThemes.colorOk),
                            title: Text('${pl?.nombre ?? "?"} · ${cul?.lote ?? ""}'),
                            subtitle: Text(
                                'Curada: ${_iso(cp.curaFecha ?? DateTime.now())}'),
                          ),
                        );
                      }),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

  /// Abre el modal de reporte de patología. Si no hay cultivos activos,
  /// redirige a /crops para que el usuario cree uno primero.
  static void _abrirReporte(
    BuildContext ctx,
    List<Cultivo> cultivos,
    Map<int, Planta> plantaById,
  ) {
    if (cultivos.isEmpty) {
      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
          content: Text('No hay cultivos activos. Crea uno primero.')));
      AppNav.open(ctx, '/crops');
      return;
    }
    if (cultivos.length == 1) {
      showReportarPatologiaModal(
          context: ctx, cultivoId: cultivos.first.id);
      return;
    }
    // Si hay varios, dejamos que el usuario elija.
    showModalBottomSheet<void>(
      context: ctx,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('¿En qué cultivo detectaste la patología?',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ...cultivos.map((c) {
              final variedad = plantaById[c.plantaId]?.nombre ?? '—';
              final lote = c.lote.isEmpty ? '—' : c.lote;
              return ListTile(
                leading: const Icon(Icons.eco),
                title: Text(variedad,
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('$lote · sembrado ${c.sembrado}'),
                onTap: () {
                  Navigator.pop(ctx);
                  showReportarPatologiaModal(
                      context: ctx, cultivoId: c.id);
                },
              );
            }),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Tarjeta del catálogo de patologías: nombre común + científico + grupo,
/// y chips con las plantas del predio que se ven afectadas.
class _CatCard extends StatelessWidget {
  const _CatCard({required this.p, required this.plantasAfectadas});
  final drift.Patologia p;
  final List<String> plantasAfectadas;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final grupo = grupoPorCodigo(grupoEfectivo(p));
    final esManual = reclasificadaManualmente(p);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.nombreComun,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                        '${p.nombreCientifico ?? "?"} · ${grupo.etiqueta}'
                        '${esManual ? " · reclasificada" : ""}',
                        style: TextStyle(
                            fontStyle: FontStyle.italic,
                            fontSize: 12,
                            color: theme.hintColor)),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                    esManual ? Icons.category : Icons.category_outlined,
                    color: esManual
                        ? theme.colorScheme.primary
                        : theme.hintColor,
                    size: 20),
                tooltip: esManual
                    ? 'Reclasificada en ${grupo.etiqueta} — pulsa para cambiar'
                    : 'Reclasificar en otro grupo',
                onPressed: () => showReclasificarPatologiaDialog(
                    context: context, patologia: p),
              ),
              IconButton(
                icon: Icon(Icons.medical_services_outlined,
                    color: Colors.green.shade700, size: 20),
                tooltip: 'Ver tratamientos recomendados',
                onPressed: () => showTratamientosDialog(
                    context, p.id, p.nombreComun),
              ),
            ]),
            if ((p.sintomas ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(p.sintomas!,
                  style: const TextStyle(fontSize: 12),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis),
            ],
            if (plantasAfectadas.isNotEmpty) ...[
              const SizedBox(height: 8),
              _ChipsPlantasAfectadas(
                plantasAfectadas: plantasAfectadas,
                colorBase: theme.colorScheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fase 3i-A: botón "Actualizar" que carga el catálogo bundleado y hace
/// merge idempotente en las tablas locales. Muestra progress y snackbar.
/// Chips compactos con nombres de plantas afectadas.
/// Por defecto muestra máximo 3 + "+N más"; expande al pulsar para ver todos.
class _ChipsPlantasAfectadas extends StatefulWidget {
  const _ChipsPlantasAfectadas({
    required this.plantasAfectadas,
    required this.colorBase,
  });
  final List<String> plantasAfectadas;
  final Color colorBase;

  @override
  State<_ChipsPlantasAfectadas> createState() =>
      _ChipsPlantasAfectadasState();
}

class _ChipsPlantasAfectadasState extends State<_ChipsPlantasAfectadas> {
  bool _expandido = false;
  static const _limite = 3;

  @override
  Widget build(BuildContext context) {
    final total = widget.plantasAfectadas.length;
    final visibles = _expandido || total <= _limite
        ? widget.plantasAfectadas
        : widget.plantasAfectadas.take(_limite).toList();
    final restantes = total - visibles.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Afecta a $total planta${total == 1 ? "" : "s"}:',
            style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 4),
        Wrap(
          spacing: 4,
          runSpacing: 4,
          children: [
            ...visibles.map((n) => _chipPlanta(n, widget.colorBase)),
            if (restantes > 0)
              InkWell(
                onTap: () => setState(() => _expandido = true),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: widget.colorBase.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: widget.colorBase.withOpacity(0.4),
                        width: 0.5),
                  ),
                  child: Text('+$restantes más',
                      style: TextStyle(
                          fontSize: 11,
                          color: widget.colorBase,
                          fontWeight: FontWeight.w600)),
                ),
              ),
            if (_expandido && total > _limite)
              InkWell(
                onTap: () => setState(() => _expandido = false),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  child: Text('ocultar',
                      style: TextStyle(
                          fontSize: 11,
                          color: widget.colorBase,
                          decoration: TextDecoration.underline)),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _chipPlanta(String nombre, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.4), width: 0.5),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.grass, size: 11, color: color),
          const SizedBox(width: 4),
          Text(nombre,
              style: TextStyle(
                  fontSize: 11,
                  color: color,
                  fontWeight: FontWeight.w600)),
        ]),
      );
}

/// Catálogo de patologías agrupado por tipo en ExpansionTiles colapsables.
/// Orden solicitado: abiótica, hongo, bacteria, virus, plaga, nutricional, otra.
class _CatalogoAgrupado extends StatelessWidget {
  const _CatalogoAgrupado({
    required this.filtradas,
    required this.porPlantasMap,
  });
  final List<drift.Patologia> filtradas;
  final Map<int, List<String>> porPlantasMap;

  @override
  Widget build(BuildContext context) {
    // Agrupa por el tipo efectivo: la reclasificación manual del usuario
    // manda sobre el tipo taxonómico del catálogo.
    final porTipo = <String, List<drift.Patologia>>{};
    for (final p in filtradas) {
      porTipo.putIfAbsent(grupoEfectivo(p), () => []).add(p);
    }
    // Ordena cada grupo alfabéticamente por nombre científico (fallback
    // a nombre común). Esto agrupa naturalmente las especies del mismo
    // género (Atta cephalotes, Atta colombica, Atta laevigata…).
    for (final list in porTipo.values) {
      list.sort((a, b) {
        final ka =
            (a.nombreCientifico ?? a.nombreComun).toLowerCase().trim();
        final kb =
            (b.nombreCientifico ?? b.nombreComun).toLowerCase().trim();
        return ka.compareTo(kb);
      });
    }
    return Column(
      children: [
        for (final g in gruposPatologias)
          if ((porTipo[g.codigo] ?? const []).isNotEmpty)
            _GrupoExpansion(
              // Sin key, al reclasificar una patología (un grupo puede quedar
              // vacío y desaparecer) el estado de expansión se desplazaría al
              // grupo vecino.
              key: ValueKey(g.codigo),
              titulo: g.titulo,
              icono: g.icono,
              patologias: porTipo[g.codigo]!,
              porPlantasMap: porPlantasMap,
            ),
      ],
    );
  }
}

/// ExpansionTile por tipo de patología. Colapsado por defecto (lazy: los
/// _CatCard solo se construyen al expandir la primera vez).
class _GrupoExpansion extends StatefulWidget {
  const _GrupoExpansion({
    super.key,
    required this.titulo,
    required this.icono,
    required this.patologias,
    required this.porPlantasMap,
  });
  final String titulo;
  final IconData icono;
  final List<drift.Patologia> patologias;
  final Map<int, List<String>> porPlantasMap;

  @override
  State<_GrupoExpansion> createState() => _GrupoExpansionState();
}

class _GrupoExpansionState extends State<_GrupoExpansion> {
  /// Marca si el grupo se ha expandido al menos una vez.
  /// Antes de la primera expansión no construimos los _CatCard (lazy).
  bool _yaExpandido = false;

  @override
  Widget build(BuildContext context) {
    final n = widget.patologias.length;
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: Icon(widget.icono, size: 20),
        title: Text(widget.titulo,
            style: const TextStyle(
                fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text('$n patología${n == 1 ? "" : "s"}',
            style: TextStyle(
                fontSize: 11, color: Theme.of(context).hintColor)),
        initiallyExpanded: false,
        maintainState: true, // preserva estado tras primera expansión
        onExpansionChanged: (open) {
          if (open && !_yaExpandido) {
            setState(() => _yaExpandido = true);
          }
        },
        children: _yaExpandido
            ? widget.patologias
                .map((p) => _CatCard(
                      p: p,
                      plantasAfectadas:
                          widget.porPlantasMap[p.id] ?? const [],
                    ))
                .toList()
            : const [SizedBox(height: 0)],
      ),
    );
  }
}

class _BotonActualizarCatalogo extends ConsumerStatefulWidget {
  const _BotonActualizarCatalogo();

  @override
  ConsumerState<_BotonActualizarCatalogo> createState() =>
      _BotonActualizarCatalogoState();
}

class _BotonActualizarCatalogoState
    extends ConsumerState<_BotonActualizarCatalogo> {
  bool _cargando = false;

  Future<void> _actualizar() async {
    setState(() => _cargando = true);
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
        content: Text('Actualizando catálogo de patologías…'),
        duration: Duration(seconds: 2)));
    try {
      final res = await ref
          .read(patologiaCatalogServiceProvider)
          .actualizarDesdeAsset();
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
          content: Text(res.resumen),
          backgroundColor:
              res.exito ? Colors.green.shade700 : Colors.red.shade700,
          duration: const Duration(seconds: 5)));
    } catch (e) {
      if (!mounted) return;
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(SnackBar(
          content: Text('Error al actualizar: $e'),
          backgroundColor: Colors.red.shade700));
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _cargando ? null : _actualizar,
      icon: _cargando
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.refresh),
      label: Text(_cargando ? 'Actualizando…' : 'Actualizar'),
    );
  }
}
