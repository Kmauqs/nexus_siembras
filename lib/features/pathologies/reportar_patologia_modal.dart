// NEXUS Siembras — Modal para levantar un reporte de patología en un
// cultivo (Fase 3e-5).
//
// Uso desde otras pantallas:
//   showReportarPatologiaModal(context: ctx, cultivoId: c.id);
//
// El modal captura:
//   - Patología del catálogo (prioriza las asociadas a la especie del cultivo)
//   - Foto (cámara o galería)
//   - GNSS (Geolocator)
//   - Severidad (inicial / avanzada)
//   - Notas / síntomas observados
//   - Toggle "Compartir a comunidad" (respeta cfg.consentimientoPatologias)
//
// Si el usuario activa "compartir a comunidad" y el consent global está
// activo, la copia anonimizada se guarda también en PatologiasReportadas.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/location/gps_capture.dart';
import '../../core/theme/themes.dart';
import '../../data/database/database.dart' as drift;
import '../../services/patologia_foto_service.dart';
import '../../state/data_state.dart';

/// Abre el bottom sheet de reporte de patología para un cultivo.
void showReportarPatologiaModal({
  required BuildContext context,
  required int cultivoId,
}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ReportarPatologiaModal(cultivoId: cultivoId),
  );
}

class _ReportarPatologiaModal extends ConsumerStatefulWidget {
  const _ReportarPatologiaModal({required this.cultivoId});
  final int cultivoId;
  @override
  ConsumerState<_ReportarPatologiaModal> createState() =>
      _ReportarPatologiaModalState();
}

class _ReportarPatologiaModalState
    extends ConsumerState<_ReportarPatologiaModal> {
  final _notas = TextEditingController();
  int? _patologiaId;
  String _severidad = 'inicial';
  DateTime _fecha = DateTime.now();
  String? _fotoPath;
  double? _lat, _lng, _altM;
  bool _guardando = false;
  bool _capturandoGnss = false;
  bool _compartir = false;
  bool _hidratoCompartir = false;

  @override
  void dispose() {
    _notas.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cfgAsync = ref.watch(configProvider);
    final catalogoAsync = ref.watch(patologiasCatalogoProvider);
    final porPlantasAsync = ref.watch(patologiasPorPlantasProvider);
    final cultivo = _resolverCultivo(ref);
    final planta = _resolverPlanta(ref, cultivo?.plantaId);

    // Hidrata el toggle "compartir" con el consent global la primera vez.
    cfgAsync.whenData((cfg) {
      if (!_hidratoCompartir && cfg != null) {
        _hidratoCompartir = true;
        _compartir = cfg.consentimientoPatologias;
      }
    });

    return Padding(
      padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.bug_report, color: Colors.orange),
              const SizedBox(width: 8),
              Text('Reportar patología',
                  style: Theme.of(context).textTheme.titleLarge),
            ]),
            if (planta != null)
              Text('${planta.nombre} · ${cultivo?.lote ?? ""}',
                  style: TextStyle(color: Theme.of(context).hintColor)),
            const SizedBox(height: 14),

            // Selector de patología híbrido: por defecto muestra solo las
            // asociadas a la variedad del cultivo; toggle para expandir al
            // catálogo completo (Fase 3e-5+).
            _SelectorPatologia(
              plantaNombre: planta?.nombre,
              catalogoAsync: catalogoAsync,
              porPlantasAsync: porPlantasAsync,
              seleccionadaId: _patologiaId,
              onChanged: (v) => setState(() => _patologiaId = v),
            ),
            const SizedBox(height: 12),

            // Severidad
            const Text('Severidad',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'inicial',
                    label: Text('Inicial'),
                    icon: Icon(Icons.circle, color: AppThemes.colorWarn)),
                ButtonSegment(
                    value: 'avanzada',
                    label: Text('Avanzada'),
                    icon: Icon(Icons.warning, color: AppThemes.colorAlert)),
              ],
              selected: {_severidad},
              onSelectionChanged: (s) => setState(() => _severidad = s.first),
            ),
            const SizedBox(height: 12),

            // Fecha
            InkWell(
              onTap: () async {
                final d = await showDatePicker(
                  context: context,
                  initialDate: _fecha,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (d != null) setState(() => _fecha = d);
              },
              child: InputDecorator(
                decoration: const InputDecoration(
                    labelText: 'Fecha de detección',
                    suffixIcon: Icon(Icons.calendar_today),
                    border: OutlineInputBorder()),
                child: Text(
                    '${_fecha.year}-${_fecha.month.toString().padLeft(2, "0")}-${_fecha.day.toString().padLeft(2, "0")}'),
              ),
            ),
            const SizedBox(height: 12),

            // Foto
            _FotoRow(
              fotoPath: _fotoPath,
              onCambiar: (p) => setState(() => _fotoPath = p),
            ),
            const SizedBox(height: 12),

            // GNSS
            _GnssRow(
              lat: _lat,
              lng: _lng,
              alt: _altM,
              capturando: _capturandoGnss,
              onCapturar: _capturarGnss,
              onLimpiar: () => setState(() {
                _lat = null;
                _lng = null;
                _altM = null;
              }),
            ),
            const SizedBox(height: 12),

            // Notas
            TextField(
              controller: _notas,
              maxLines: 3,
              decoration: const InputDecoration(
                  labelText: 'Notas / síntomas observados',
                  hintText: 'Ej: manchas amarillas en el envés, pústulas…',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),

            // Compartir a comunidad
            cfgAsync.when(
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
              data: (cfg) {
                final consentGlobal =
                    cfg?.consentimientoPatologias ?? false;
                return Card(
                  color: consentGlobal
                      ? Colors.green.shade50
                      : Colors.grey.shade100,
                  margin: EdgeInsets.zero,
                  child: SwitchListTile(
                    value: _compartir && consentGlobal,
                    onChanged: consentGlobal
                        ? (v) => setState(() => _compartir = v)
                        : null,
                    title: const Text('Compartir a comunidad NEXUS',
                        style: TextStyle(fontSize: 14)),
                    subtitle: Text(
                      consentGlobal
                          ? 'Contribuyes al mapa comunitario. Solo se comparten '
                              'patología, coordenadas y fecha (sin datos personales).'
                          : 'Activa "Compartir patologías" en Configuración → '
                              'Comunidad NEXUS para habilitar esta opción.',
                      style: const TextStyle(fontSize: 11),
                    ),
                    dense: true,
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(
                  onPressed:
                      _guardando ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: _guardando ? null : () => _guardar(planta),
                icon: _guardando
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.save, size: 16),
                label: Text(_guardando ? 'Guardando…' : 'Guardar reporte'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  Cultivo? _resolverCultivo(WidgetRef ref) {
    final cultivos = ref.watch(cultivosActivosProvider) +
        ref.watch(cultivosFinalizadosProvider);
    for (final c in cultivos) {
      if (c.id == widget.cultivoId) return c;
    }
    return null;
  }

  Planta? _resolverPlanta(WidgetRef ref, int? plantaId) {
    if (plantaId == null) return null;
    final plantas = ref.watch(plantasProvider);
    for (final p in plantas) {
      if (p.id == plantaId) return p;
    }
    return null;
  }

  Future<void> _capturarGnss() async {
    setState(() => _capturandoGnss = true);
    try {
      final fix = await capturarGps();
      if (!mounted) return;
      setState(() {
        _lat = fix.latitude;
        _lng = fix.longitude;
        _altM = fix.altitudeMsnm;
      });
      final msg = fix.altitudeMsnm != null
          ? 'Coordenadas capturadas ${fix.detalle}'
          : 'Coordenadas capturadas ${fix.detalle}. '
              'No se obtuvo altitud.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } on GpsCaptureException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo obtener GNSS: $e')));
    } finally {
      if (mounted) setState(() => _capturandoGnss = false);
    }
  }

  Future<void> _guardar(Planta? planta) async {
    if (_patologiaId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Selecciona una patología')));
      return;
    }
    setState(() => _guardando = true);
    try {
      final catalogo = ref.read(patologiasCatalogoProvider).maybeWhen(
          data: (l) => l, orElse: () => const <drift.Patologia>[]);
      final pat =
          catalogo.where((p) => p.id == _patologiaId).cast<drift.Patologia?>().firstOrNull;
      final compartirEfectivo = _compartir &&
          (ref.read(configProvider).maybeWhen(
                data: (c) => c?.consentimientoPatologias ?? false,
                orElse: () => false,
              ));
      // País del predio activo (para denormalizar en el reporte comunitario).
      final paisIso = await _paisIsoActivo();
      await ref.read(dataMutationsProvider).reportarPatologia(
            cultivoId: widget.cultivoId,
            patologiaId: _patologiaId!,
            fechaDeteccion: _fecha,
            severidad: _severidad,
            fotoPath: _fotoPath,
            lat: _lat,
            lng: _lng,
            altM: _altM,
            notas:
                _notas.text.trim().isEmpty ? null : _notas.text.trim(),
            compartirAComunidad: compartirEfectivo && _lat != null,
            patologiaNombre: pat?.nombreComun,
            patologiaCientifico: pat?.nombreCientifico,
            plantaNombre: planta?.nombre,
            paisIso2: paisIso,
          );
      if (!mounted) return;
      Navigator.pop(context);
      final msg = compartirEfectivo && _lat != null
          ? 'Reporte guardado · compartido con la comunidad'
          : 'Reporte guardado';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  /// Resuelve el ISO2 del país del predio activo (para denormalizar en
  /// PatologiasReportadas). Silencioso si no está disponible.
  Future<String?> _paisIsoActivo() async {
    try {
      final async = ref.read(prediosProvider);
      final list = async.maybeWhen(
          data: (l) => l, orElse: () => const <drift.Predio>[]);
      final activeId = ref.read(activePredioIdProvider);
      final predio = list.firstWhere((p) => p.id == activeId,
          orElse: () => list.isNotEmpty
              ? list.first
              : throw StateError('sin predios'));
      final paisId = predio.paisId;
      if (paisId == null) return null;
      final paises = ref.read(paisesProvider).maybeWhen(
          data: (l) => l, orElse: () => const <drift.Paise>[]);
      final pais = paises.firstWhere((p) => p.id == paisId,
          orElse: () => throw StateError('pais no encontrado'));
      return pais.iso2;
    } catch (_) {
      return null;
    }
  }
}

// ============================================================
// Sub-widgets
// ============================================================

class _SelectorPatologia extends StatefulWidget {
  const _SelectorPatologia({
    required this.plantaNombre,
    required this.catalogoAsync,
    required this.porPlantasAsync,
    required this.seleccionadaId,
    required this.onChanged,
  });
  final String? plantaNombre;
  final AsyncValue<List<drift.Patologia>> catalogoAsync;
  final AsyncValue<Map<int, List<String>>> porPlantasAsync;
  final int? seleccionadaId;
  final ValueChanged<int?> onChanged;

  @override
  State<_SelectorPatologia> createState() => _SelectorPatologiaState();
}

class _SelectorPatologiaState extends State<_SelectorPatologia> {
  /// Toggle "ver todas" — desactivado por defecto (solo asociadas).
  bool _verTodas = false;

  @override
  Widget build(BuildContext context) {
    return widget.catalogoAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (e, _) => Text('Error catálogo: $e'),
      data: (catalogoCompleto) {
        final porPlantas = widget.porPlantasAsync.maybeWhen(
            data: (m) => m, orElse: () => const <int, List<String>>{});
        final planta = widget.plantaNombre?.trim() ?? '';

        // Set de IDs de patologías asociadas a esta variedad (por nombre
        // de planta match case-insensitive).
        final idsAsociadas = <int>{};
        if (planta.isNotEmpty) {
          porPlantas.forEach((patId, nombres) {
            if (nombres.any(
                (n) => n.trim().toLowerCase() == planta.toLowerCase())) {
              idsAsociadas.add(patId);
            }
          });
        }

        final asociadas = catalogoCompleto
            .where((p) => idsAsociadas.contains(p.id))
            .toList()
          ..sort((a, b) => a.nombreComun.compareTo(b.nombreComun));
        final todas = [...catalogoCompleto]
          ..sort((a, b) => a.nombreComun.compareTo(b.nombreComun));

        // Fallback automático a "todas" si no hay asociadas.
        final debeMostrarTodas = _verTodas || asociadas.isEmpty;
        final mostradas = debeMostrarTodas ? todas : asociadas;

        // Es la seleccionada una que NO está asociada a la variedad?
        final seleccionadaFueraDeAsociadas = widget.seleccionadaId != null &&
            planta.isNotEmpty &&
            !idsAsociadas.contains(widget.seleccionadaId);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header con contador y toggle
            Row(children: [
              Expanded(
                child: Text(
                  planta.isEmpty
                      ? '${todas.length} patologías en el catálogo'
                      : (asociadas.isEmpty
                          ? 'Sin patologías catalogadas para "$planta"'
                          : '${asociadas.length} conocidas para "$planta" · ${todas.length} en total'),
                  style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).hintColor),
                ),
              ),
              if (asociadas.isNotEmpty)
                InkWell(
                  onTap: () => setState(() => _verTodas = !_verTodas),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _verTodas
                          ? Colors.blue.shade50
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: _verTodas
                              ? Colors.blue.shade300
                              : Colors.grey.shade300,
                          width: 0.5),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                          _verTodas
                              ? Icons.filter_alt_off_outlined
                              : Icons.list,
                          size: 12,
                          color: Colors.blue.shade700),
                      const SizedBox(width: 3),
                      Text(
                          _verTodas
                              ? 'Solo asociadas'
                              : 'Ver todas (${todas.length})',
                          style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue.shade700,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ),
            ]),
            const SizedBox(height: 4),
            _AutocompletePatologia(
              mostradas: mostradas,
              seleccionadaId: widget.seleccionadaId,
              onChanged: widget.onChanged,
              helperText: debeMostrarTodas
                  ? '📚 Mostrando catálogo completo (${mostradas.length} patologías)'
                  : '🎯 Mostrando solo asociadas a la variedad (${mostradas.length})',
              helperColor: debeMostrarTodas
                  ? Colors.orange.shade800
                  : Colors.green.shade700,
            ),
            // Aviso si eligió una patología que no está asociada.
            if (seleccionadaFueraDeAsociadas)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                    '⚠ Esta patología no está catalogada como afectante '
                    'de esta especie. ¿Es correcto?',
                    style: TextStyle(
                        fontSize: 11,
                        color: Colors.orange.shade800,
                        fontWeight: FontWeight.w500)),
              ),
            // Aviso cuando cae automáticamente a "todas" por falta de asociadas.
            if (planta.isNotEmpty &&
                asociadas.isEmpty &&
                todas.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 4),
                child: Text(
                    'ℹ Aún no hay patologías catalogadas para esta variedad. '
                    'Mostrando el catálogo completo.',
                    style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).hintColor,
                        fontStyle: FontStyle.italic)),
              ),
          ],
        );
      },
    );
  }
}

class _FotoRow extends StatelessWidget {
  const _FotoRow({required this.fotoPath, required this.onCambiar});
  final String? fotoPath;
  final ValueChanged<String?> onCambiar;

  Future<void> _tomar(BuildContext ctx) async {
    try {
      final path = await PatologiaFotoService.instance.tomarFoto();
      if (path != null) onCambiar(path);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text('Error cámara: $e')));
      }
    }
  }

  Future<void> _galeria(BuildContext ctx) async {
    try {
      final path = await PatologiaFotoService.instance.elegirDeGaleria();
      if (path != null) onCambiar(path);
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx)
            .showSnackBar(SnackBar(content: Text('Error galería: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          border: Border.all(color: Theme.of(context).dividerColor),
          borderRadius: BorderRadius.circular(8),
        ),
        child: fotoPath == null
            ? Icon(Icons.image_not_supported, color: Theme.of(context).hintColor)
            : ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(fotoPath!),
                    fit: BoxFit.cover, width: 68, height: 68),
              ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          OutlinedButton.icon(
            onPressed: () => _tomar(context),
            icon: const Icon(Icons.camera_alt, size: 16),
            label: const Text('Cámara'),
          ),
          OutlinedButton.icon(
            onPressed: () => _galeria(context),
            icon: const Icon(Icons.photo_library, size: 16),
            label: const Text('Galería'),
          ),
          if (fotoPath != null)
            OutlinedButton.icon(
              onPressed: () => onCambiar(null),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Quitar'),
            ),
        ]),
      ),
    ]);
  }
}

/// Autocomplete tipo dropdown que se abre HACIA ABAJO (RawAutocomplete
/// controlado). Reemplaza a DropdownButtonFormField que en Material 3
/// abre hacia arriba cuando queda poco espacio debajo, tapando el campo.
///
/// Muestra el nombre común de la patología seleccionada como texto
/// readonly en el campo, y permite buscar/filtrar tipeando.
class _AutocompletePatologia extends StatefulWidget {
  const _AutocompletePatologia({
    required this.mostradas,
    required this.seleccionadaId,
    required this.onChanged,
    required this.helperText,
    required this.helperColor,
  });
  final List<drift.Patologia> mostradas;
  final int? seleccionadaId;
  final ValueChanged<int?> onChanged;
  final String helperText;
  final Color helperColor;

  @override
  State<_AutocompletePatologia> createState() =>
      _AutocompletePatologiaState();
}

class _AutocompletePatologiaState extends State<_AutocompletePatologia> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _sincronizarTexto();
  }

  @override
  void didUpdateWidget(covariant _AutocompletePatologia old) {
    super.didUpdateWidget(old);
    if (old.seleccionadaId != widget.seleccionadaId) {
      _sincronizarTexto();
    }
  }

  void _sincronizarTexto() {
    if (widget.seleccionadaId == null) {
      _ctrl.text = '';
      return;
    }
    final p = widget.mostradas.firstWhere(
        (x) => x.id == widget.seleccionadaId,
        orElse: () => widget.mostradas.isNotEmpty
            ? widget.mostradas.first
            : throw StateError('vacio'));
    _ctrl.text = _label(p);
  }

  String _label(drift.Patologia p) => '${p.nombreComun} · ${p.tipo ?? "?"}';

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<drift.Patologia>(
      textEditingController: _ctrl,
      focusNode: _focus,
      displayStringForOption: _label,
      optionsBuilder: (tev) {
        final q = tev.text.trim().toLowerCase();
        if (q.isEmpty) return widget.mostradas;
        return widget.mostradas.where((p) {
          return p.nombreComun.toLowerCase().contains(q) ||
              (p.nombreCientifico ?? '').toLowerCase().contains(q);
        });
      },
      onSelected: (p) {
        widget.onChanged(p.id);
        _focus.unfocus();
      },
      fieldViewBuilder: (ctx, controller, focus, onSubmit) {
        return TextField(
          controller: controller,
          focusNode: focus,
          decoration: InputDecoration(
            labelText: 'Patología detectada *',
            hintText: 'Buscar por nombre común o científico…',
            border: const OutlineInputBorder(),
            suffixIcon: (controller.text.isNotEmpty)
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Limpiar',
                    onPressed: () {
                      controller.clear();
                      widget.onChanged(null);
                    },
                  )
                : const Icon(Icons.arrow_drop_down),
            helperText: widget.helperText,
            helperStyle: TextStyle(
                fontSize: 11,
                color: widget.helperColor,
                fontWeight: FontWeight.w600),
          ),
          onTap: () {
            // Fuerza reevaluación de options para abrir el overlay
            controller.text = controller.text;
          },
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        // Panel de opciones abajo del campo, con altura limitada.
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(6),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: 260,
                maxWidth: MediaQuery.of(ctx).size.width - 32,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (_, i) {
                  final p = options.elementAt(i);
                  return ListTile(
                    dense: true,
                    visualDensity: VisualDensity.compact,
                    title: Text(p.nombreComun,
                        style: const TextStyle(fontSize: 13)),
                    subtitle: Text(
                        '${p.nombreCientifico ?? "?"} · ${p.tipo ?? "?"}',
                        style: const TextStyle(
                            fontSize: 11, fontStyle: FontStyle.italic)),
                    onTap: () => onSelected(p),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _GnssRow extends StatelessWidget {
  const _GnssRow({
    required this.lat,
    required this.lng,
    required this.alt,
    required this.capturando,
    required this.onCapturar,
    required this.onLimpiar,
  });
  final double? lat, lng, alt;
  final bool capturando;
  final VoidCallback onCapturar;
  final VoidCallback onLimpiar;

  @override
  Widget build(BuildContext context) {
    final tieneCoords = lat != null && lng != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        OutlinedButton.icon(
          onPressed: capturando ? null : onCapturar,
          icon: capturando
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.my_location, size: 16),
          label: Text(capturando ? 'Obteniendo…' : 'Usar GNSS'),
        ),
        const SizedBox(width: 8),
        if (tieneCoords)
          OutlinedButton.icon(
            onPressed: onLimpiar,
            icon: const Icon(Icons.clear, size: 16),
            label: const Text('Limpiar'),
          ),
      ]),
      if (tieneCoords)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              '📍 ${lat!.toStringAsFixed(6)}, ${lng!.toStringAsFixed(6)}'
              '${alt != null ? " · alt ${alt!.toStringAsFixed(0)} msnm" : ""}',
              style: const TextStyle(fontSize: 12)),
        )
      else
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
              'Sin coordenadas (opcional; requerido para compartir a comunidad)',
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).hintColor)),
        ),
    ]);
  }
}
