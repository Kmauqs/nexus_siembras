import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/models/ciclo_abono.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/database/database.dart' as drift;
import '../../services/eppo_client.dart';
import '../../services/variedades_comunitarias_service.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';
import 'ciclos_abono_editor.dart';

class PlantsScreen extends ConsumerWidget {
  const PlantsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plantas = ref.watch(plantasProvider);
    return AppShell(
      title: 'Plantas',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: FilledButton.icon(
              onPressed: () => _showPlantaEditor(context, ref, null),
              icon: const Icon(Icons.add),
              label: const Text('Agregar variedad'),
            ),
          ),
          if (plantas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('Sin plantas en el catálogo')),
            )
          else
            ...plantas.map((p) => _PlantaCard(pl: p)),
        ],
      ),
    );
  }
}

class _PlantaCard extends ConsumerWidget {
  const _PlantaCard({required this.pl});
  final Planta pl;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final esGerm = pl.metodoSiembra == 'germinador';
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
                    Text(pl.nombre,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(pl.especie,
                        style: TextStyle(
                            fontStyle: FontStyle.italic,
                            color: Theme.of(context).hintColor)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'Editar variedad',
                onPressed: () => _showPlantaEditor(context, ref, pl),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.red),
                tooltip: 'Eliminar variedad',
                onPressed: () => _confirmDelete(context, ref, pl),
              ),
            ]),
            const Divider(),
            _row('Tipo cultivo', pl.tipoCultivoEtiqueta),
            if (pl.esPerenneDefault) ...[
              if (pl.cosechaMin != null)
                _row('1ª cosecha', '${pl.cosechaMin} d'),
              if (pl.periodicidadCosechaDias != null)
                _row('Periodicidad', '${pl.periodicidadCosechaDias} d'),
              if (pl.esperanzaVidaDias != null)
                _row('Vida útil', '${pl.esperanzaVidaDias} d'),
            ] else ...[
              if (pl.cosechaMin != null || pl.cosechaMax != null)
                _row(
                    'Cosechas',
                    '${pl.cosechaMin ?? "?"} / ${pl.cosechaMax ?? "?"} d '
                    '(verde · maduro)'),
            ],
            _row(
                'Método siembra',
                esGerm
                    ? '🌱🪴 Germinador (${pl.germinadorDias ?? "?"} d)'
                    : '🌾 Directa'),
            if (pl.ciclosAbono.any((c) => c.tipo.isNotEmpty))
              _row(
                  'Abonos',
                  pl.ciclosAbono
                      .where((c) => c.tipo.isNotEmpty)
                      .map((c) => '${c.tipo} (${c.dias} d)')
                      .join(' · '))
            else if (pl.tipoAbono1 != null || pl.tipoAbono2 != null)
              _row(
                  'Abonos',
                  [pl.tipoAbono1, pl.tipoAbono2]
                      .whereType<String>()
                      .join(' + ')),
            if (pl.fuenteMetodo.isNotEmpty) _row('Fuente', pl.fuenteMetodo),
            // Fase 3h: contador de patologías asociadas.
            Consumer(builder: (_, ref2, __) {
              final async = ref2.watch(patologiasAsociadasCountProvider(pl.id));
              return async.when(
                loading: () =>
                    _row('Patologías', '…', color: Colors.grey),
                error: (_, __) =>
                    _row('Patologías', '?', color: Colors.grey),
                data: (n) => _row(
                  'Patologías',
                  n == 0 ? 'ninguna asociada' : '🐛 $n conocida${n == 1 ? "" : "s"}',
                  color: n > 0 ? Colors.orange.shade900 : Colors.grey,
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _row(String k, String v, {Color? color}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
                width: 120,
                child: Text(k, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(v, style: TextStyle(color: color))),
          ],
        ),
      );

  Future<void> _confirmDelete(
      BuildContext ctx, WidgetRef ref, Planta pl) async {
    final usos = await ref.read(dataMutationsProvider).countCultivosPlanta(pl.id);
    if (!ctx.mounted) return;
    if (usos > 0) {
      ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
          content: Text(
              'No se puede eliminar: hay $usos cultivo(s) activo(s) usando '
              '"${pl.nombre}". Elimínalos o finalízalos antes.')));
      return;
    }
    final ok = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Eliminar variedad'),
        content: Text('¿Eliminar "${pl.nombre}" del catálogo de plantas?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(dataMutationsProvider).deletePlanta(pl.id);
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(content: Text('"${pl.nombre}" eliminada')));
    }
  }
}

/// Modal reutilizable para crear/editar plantas (variedades).
void _showPlantaEditor(BuildContext ctx, WidgetRef ref, Planta? existing) {
  showModalBottomSheet<void>(
    context: ctx,
    isScrollControlled: true,
    builder: (_) => _PlantaEditor(existing: existing),
  );
}

class _PlantaEditor extends ConsumerStatefulWidget {
  const _PlantaEditor({this.existing});
  final Planta? existing;
  @override
  ConsumerState<_PlantaEditor> createState() => _PlantaEditorState();
}

class _PlantaEditorState extends ConsumerState<_PlantaEditor> {
  late final TextEditingController _nombre;
  late final TextEditingController _especie;
  late final TextEditingController _cosechaMin;
  late final TextEditingController _cosechaMax;
  late final TextEditingController _periodicidad;
  late final TextEditingController _esperanzaVida;
  late final TextEditingController _germinadorDias;
  late final TextEditingController _fuente;
  late final TextEditingController _notas;
  final List<CicloAbonoEditorRow> _ciclosAbono = [];
  String _metodo = 'directa';
  String _tipoCultivo = 'ciclo_unico';
  bool _saving = false;
  // Fase 3h: preview de patologías conocidas para la especie ingresada.
  List<drift.Patologia> _patologiasConocidas = const [];
  // Verificación async contra EPPO Global Database.
  // null = aún no verificado (o sin token) · true = encontrado · false = no
  bool? _eppoNombreOk;
  bool? _eppoEspecieOk;
  Timer? _debounceEppo;
  // Banco comunitario de variedades (Fase B1, 2026-07-20).
  List<VariedadComunitaria> _sugerenciasComunidad = const [];
  Timer? _debounceComunidad;
  bool _compartirComunidad = true;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nombre = TextEditingController(text: e?.nombre ?? '');
    _especie = TextEditingController(text: e?.especie ?? '');
    _cosechaMin = TextEditingController(
        text: e?.cosechaMin?.toString() ?? '');
    _cosechaMax = TextEditingController(
        text: e?.cosechaMax?.toString() ?? '');
    _periodicidad = TextEditingController(
        text: e?.periodicidadCosechaDias?.toString() ?? '');
    _esperanzaVida = TextEditingController(
        text: e?.esperanzaVidaDias?.toString() ?? '');
    _germinadorDias =
        TextEditingController(text: e?.germinadorDias?.toString() ?? '');
    _fuente = TextEditingController(text: e?.fuenteMetodo ?? '');
    _notas = TextEditingController(text: '');
    _metodo = e?.metodoSiembra ?? 'directa';
    _tipoCultivo = e?.tipoCultivoDefault ?? 'ciclo_unico';
    _ciclosAbono.clear();
    if (e != null && e.ciclosAbono.isNotEmpty) {
      _ciclosAbono.addAll(
          e.ciclosAbono.map(CicloAbonoEditorRow.fromCiclo));
    } else {
      _ciclosAbono.add(CicloAbonoEditorRow(dias: '1'));
    }
    // Fase 3h: cuando cambie la especie, consultar patologías conocidas.
    _especie.addListener(_refrescarPatologiasConocidas);
    // Verificación EPPO con debounce cuando cambian nombre o especie.
    _nombre.addListener(_agendarVerificacionEppo);
    _especie.addListener(_agendarVerificacionEppo);
    // Banco comunitario: solo al CREAR (en edición no tiene sentido
    // sobreescribir con sugerencias).
    if (widget.existing == null) {
      _nombre.addListener(_agendarBusquedaComunidad);
    }
    // Cargar el preview inicial si ya hay especie (modo edición).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refrescarPatologiasConocidas();
      _agendarVerificacionEppo();
    });
  }

  @override
  void dispose() {
    _debounceEppo?.cancel();
    _debounceComunidad?.cancel();
    _especie.removeListener(_refrescarPatologiasConocidas);
    _nombre.removeListener(_agendarVerificacionEppo);
    _especie.removeListener(_agendarVerificacionEppo);
    _nombre.removeListener(_agendarBusquedaComunidad);
    _nombre.dispose();
    _especie.dispose();
    _cosechaMin.dispose();
    _cosechaMax.dispose();
    _periodicidad.dispose();
    _esperanzaVida.dispose();
    _germinadorDias.dispose();
    for (final c in _ciclosAbono) {
      c.dispose();
    }
    _fuente.dispose();
    _notas.dispose();
    super.dispose();
  }

  Future<void> _refrescarPatologiasConocidas() async {
    final esp = _especie.text.trim();
    if (esp.isEmpty) {
      if (_patologiasConocidas.isNotEmpty) {
        setState(() => _patologiasConocidas = const []);
      }
      return;
    }
    final list = await ref
        .read(dataMutationsProvider)
        .patologiasConocidasPorEspecie(esp);
    if (!mounted) return;
    setState(() => _patologiasConocidas = list);
  }

  /// Banco comunitario: busca variedades por nombre con debounce de
  /// 600 ms. Silencioso si no hay sesión o la migración 0008 no está.
  void _agendarBusquedaComunidad() {
    _debounceComunidad?.cancel();
    _debounceComunidad =
        Timer(const Duration(milliseconds: 600), _buscarEnComunidad);
  }

  Future<void> _buscarEnComunidad() async {
    final term = _nombre.text.trim();
    if (term.length < 2) {
      if (_sugerenciasComunidad.isNotEmpty && mounted) {
        setState(() => _sugerenciasComunidad = const []);
      }
      return;
    }
    final res = await VariedadesComunitariasService.buscar(term);
    if (!mounted) return;
    setState(() => _sugerenciasComunidad = res);
  }

  /// Aplica una sugerencia del banco: llena SOLO los campos vacíos (lo
  /// que el usuario ya escribió se respeta) y fija el método de siembra.
  void _aplicarSugerencia(VariedadComunitaria v) {
    setState(() {
      _nombre.text = v.nombre;
      if (_especie.text.trim().isEmpty && v.especie != null) {
        _especie.text = v.especie!;
      }
      if (_cosechaMin.text.trim().isEmpty && v.cosechaMinDias != null) {
        _cosechaMin.text = '${v.cosechaMinDias}';
      }
      if (_cosechaMax.text.trim().isEmpty && v.cosechaMaxDias != null) {
        _cosechaMax.text = '${v.cosechaMaxDias}';
      }
      if (v.metodoSiembra == 'directa' || v.metodoSiembra == 'germinador') {
        _metodo = v.metodoSiembra!;
      }
      if (_germinadorDias.text.trim().isEmpty && v.germinadorDias != null) {
        _germinadorDias.text = '${v.germinadorDias}';
      }
      if (_periodicidad.text.trim().isEmpty && v.cosechaMinDias != null) {
        _periodicidad.text = '${v.cosechaMinDias}';
      }
      if (v.tipoAbono1 != null && _ciclosAbono.isNotEmpty) {
        final row = _ciclosAbono.first;
        if (row.tipoResuelto.isEmpty) {
          if (tiposAbonoSugeridos.contains(v.tipoAbono1)) {
            row.tipoSeleccionado = v.tipoAbono1!;
          } else {
            row.tipoSeleccionado = 'Otro';
            row.tipoCustomCtrl.text = v.tipoAbono1!;
          }
        }
      }
      if (v.tipoAbono2 != null && v.abono2Dias != null) {
        if (_ciclosAbono.length < 2) {
          _ciclosAbono.add(CicloAbonoEditorRow(
            tipo: v.tipoAbono2,
            dias: '${v.abono2Dias}',
          ));
        }
      }
      if (_fuente.text.trim().isEmpty) {
        _fuente.text = v.fuente ?? 'Comunidad NEXUS';
      }
      _sugerenciasComunidad = const [];
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Datos de "${v.nombre}" aplicados desde el banco '
            'comunitario — revisa y ajusta antes de guardar')));
  }

  /// Programa una verificación contra EPPO Global Database con debounce
  /// de 700 ms. Silencioso si no hay token configurado.
  void _agendarVerificacionEppo() {
    _debounceEppo?.cancel();
    _debounceEppo = Timer(const Duration(milliseconds: 700), _verificarEppo);
  }

  /// Consulta EPPO para nombre común y especie ingresados. Actualiza
  /// `_eppoNombreOk` y `_eppoEspecieOk` con true/false/null.
  Future<void> _verificarEppo() async {
    final cfg = await ref.read(configProvider.future);
    final token = cfg?.eppoToken?.trim();
    if (token == null || token.isEmpty) {
      // Sin token → no marcamos error, dejamos ambos null.
      if (mounted && (_eppoNombreOk != null || _eppoEspecieOk != null)) {
        setState(() {
          _eppoNombreOk = null;
          _eppoEspecieOk = null;
        });
      }
      return;
    }
    final nombre = _nombre.text.trim();
    final especie = _especie.text.trim();
    if (nombre.isEmpty && especie.isEmpty) return;

    final client = EppoClient(token);
    try {
      bool? nombreOk;
      bool? especieOk;
      // El API v2 requiere mínimo 3 caracteres para keyword.
      if (nombre.length >= 3) {
        final r = await client.resolverEppoCodes([nombre]);
        nombreOk = r.isNotEmpty;
      }
      if (especie.length >= 3) {
        final r = await client.resolverEppoCodes([especie]);
        especieOk = r.isNotEmpty;
      }
      if (!mounted) return;
      setState(() {
        _eppoNombreOk = nombreOk;
        _eppoEspecieOk = especieOk;
      });
    } catch (_) {
      // Error de red o timeout: silencioso, dejamos null.
      if (mounted) {
        setState(() {
          _eppoNombreOk = null;
          _eppoEspecieOk = null;
        });
      }
    } finally {
      client.close();
    }
  }

  /// Al seleccionar un nombre común del autocomplete, si en la BD hay una
  /// planta con ese nombre exacto y la especie del formulario está vacía,
  /// autocompleta la especie.
  void _quizasAutocompletarEspecie(String nombreSeleccionado) {
    if (_especie.text.trim().isNotEmpty) return;
    final plantas = ref.read(plantasProvider);
    final match = plantas.firstWhere(
      (p) => p.nombre.toLowerCase() == nombreSeleccionado.toLowerCase(),
      orElse: () => plantas.isNotEmpty
          ? Planta(
              id: -1, nombre: '', especie: '',
              metodoSiembra: 'directa', fuenteMetodo: '')
          : throw StateError('sin plantas'),
    );
    if (match.id != -1 && match.especie.isNotEmpty) {
      _especie.text = match.especie;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final esGerm = _metodo == 'germinador';
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
            Text(isEdit ? 'Editar variedad' : 'Nueva variedad',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            _autocompleteNombreComun(),
            _mensajeEppo(
                ok: _eppoNombreOk,
                textoOk: '✓ Nombre reconocido en EPPO Global DB',
                textoWarn:
                    '⚠ Nombre común no encontrado en EPPO. Verifica la ortografía.',
                terminoDiagnostico: _nombre.text),
            // Banco comunitario de variedades (B1): sugerencias por nombre.
            if (!isEdit && _sugerenciasComunidad.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.teal.shade50,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: const [
                        Icon(Icons.public, color: Colors.teal, size: 18),
                        SizedBox(width: 6),
                        Text('Banco comunitario de variedades',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 13)),
                      ]),
                      const SizedBox(height: 2),
                      const Text(
                          'Toca una sugerencia para autocompletar los campos '
                          'vacíos con los datos aportados por la comunidad.',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey)),
                      const SizedBox(height: 4),
                      ..._sugerenciasComunidad.map((v) => ListTile(
                            dense: true,
                            visualDensity: VisualDensity.compact,
                            contentPadding: EdgeInsets.zero,
                            leading: const Icon(Icons.grass,
                                size: 18, color: Colors.teal),
                            title: Text(v.nombre,
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600)),
                            subtitle: Text(v.subtitulo,
                                style: const TextStyle(fontSize: 11)),
                            trailing: const Icon(Icons.download_outlined,
                                size: 16),
                            onTap: () => _aplicarSugerencia(v),
                          )),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            _autocompleteEspecie(),
            _mensajeEppo(
                ok: _eppoEspecieOk,
                textoOk: '✓ Especie reconocida en EPPO Global DB',
                textoWarn:
                    '⚠ Especie no encontrada en EPPO. Verifica el nombre científico.',
                terminoDiagnostico: _especie.text),
            if (_patologiasConocidas.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: Colors.amber.shade50,
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.bug_report,
                            color: Colors.orange, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                              'Patologías conocidas para "${_especie.text.trim()}"',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 13)),
                        ),
                      ]),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: _patologiasConocidas
                            .map((p) => Chip(
                                  label: Text(p.nombreComun,
                                      style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                          'Se añadirán automáticamente al catálogo de esta '
                          'variedad al guardar.',
                          style:
                              TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Text('Método de siembra',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'directa',
                    label: Text('Directa'),
                    icon: Icon(Icons.grass)),
                ButtonSegment(
                    value: 'germinador',
                    label: Text('Germinador'),
                    icon: Icon(Icons.spa)),
              ],
              selected: {_metodo},
              onSelectionChanged: (s) => setState(() => _metodo = s.first),
            ),
            if (esGerm) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _germinadorDias,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Días en germinador *',
                    hintText: 'Ej: 30',
                    border: OutlineInputBorder()),
              ),
            ],
            const SizedBox(height: 16),
            const Text('Tipo de cultivo',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'ciclo_unico',
                  label: Text('Ciclo único'),
                  icon: Icon(Icons.timelapse, size: 18),
                ),
                ButtonSegment(
                  value: 'perenne',
                  label: Text('Cultivo perenne'),
                  icon: Icon(Icons.park, size: 18),
                ),
              ],
              selected: {_tipoCultivo},
              onSelectionChanged: (s) =>
                  setState(() => _tipoCultivo = s.first),
            ),
            const SizedBox(height: 12),
            if (_tipoCultivo == 'perenne') ...[
              TextField(
                controller: _cosechaMin,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Días hasta primera cosecha',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _periodicidad,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Periodicidad entre cosechas (días)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _esperanzaVida,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Esperanza de vida (días)',
                      helperText: 'Hasta renovación',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ]),
            ] else ...[
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _cosechaMin,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cosecha 1 — verde/tierno (días)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _cosechaMax,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Cosecha 2 — maduro/seco (días)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ]),
            ],
            const SizedBox(height: 16),
            const Text('Fertilización',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            CiclosAbonoEditor(
              ciclos: _ciclosAbono,
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _fuente,
              decoration: const InputDecoration(
                  labelText: 'Fuente agronómica',
                  hintText: 'ICA / FAO / EPPO / Corpoica…',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
            // Opt-in de contribución al banco comunitario (B1). Solo tiene
            // efecto con sesión iniciada; sin sesión se explica y desactiva.
            Consumer(builder: (_, refC, __) {
              final logueado = refC.watch(isLoggedInProvider);
              return CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _compartirComunidad && logueado,
                onChanged: logueado
                    ? (v) =>
                        setState(() => _compartirComunidad = v ?? false)
                    : null,
                title: const Text(
                    'Compartir esta variedad con la comunidad',
                    style: TextStyle(fontSize: 13)),
                subtitle: Text(
                    logueado
                        ? 'Aporta los datos agronómicos (sin tu identidad) '
                            'al banco comunitario de variedades.'
                        : 'Requiere sesión iniciada.',
                    style: const TextStyle(fontSize: 11)),
              );
            }),
            const SizedBox(height: 8),
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              OutlinedButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar')),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(isEdit ? 'Guardar' : 'Crear'),
              ),
            ]),
          ],
        ),
      ),
    );
  }

  /// Autocomplete para el nombre común. Filtra por lo que ya se ha
  /// digitado, y si la especie ya está llenada, restringe a plantas que
  /// pertenezcan a esa especie.
  Widget _autocompleteNombreComun() {
    final plantas = ref.watch(plantasProvider);
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _nombre.text),
      optionsBuilder: (TextEditingValue tev) {
        final query = tev.text.trim().toLowerCase();
        final especieFiltro = _especie.text.trim().toLowerCase();
        Iterable<Planta> base = plantas;
        if (especieFiltro.isNotEmpty) {
          base = base.where(
              (p) => p.especie.toLowerCase().contains(especieFiltro));
        }
        // Únicos por nombre (evita duplicados si varias entradas comparten
        // nombreComun con distinta variedad).
        final set = <String>{};
        final salida = <String>[];
        for (final p in base) {
          final n = p.nombre;
          if (n.isEmpty) continue;
          if (query.isNotEmpty && !n.toLowerCase().contains(query)) continue;
          if (set.add(n.toLowerCase())) salida.add(n);
        }
        salida.sort();
        return salida.take(15);
      },
      onSelected: (v) {
        _nombre.text = v;
        _quizasAutocompletarEspecie(v);
        _agendarVerificacionEppo();
      },
      fieldViewBuilder: (ctx, controller, focus, onSubmit) {
        // Sincroniza el controller interno del Autocomplete con nuestro _nombre.
        controller.value = TextEditingValue(text: _nombre.text);
        controller.addListener(() {
          if (controller.text != _nombre.text) _nombre.text = controller.text;
        });
        return TextField(
          controller: controller,
          focusNode: focus,
          onSubmitted: (_) => onSubmit(),
          decoration: const InputDecoration(
              labelText: 'Nombre común *',
              hintText: 'Ej: Tomate, Frijol Cargamanto…',
              border: OutlineInputBorder()),
        );
      },
    );
  }

  /// Autocomplete para especie (nombre científico). Sugiere especies
  /// existentes en la BD, filtradas por lo digitado.
  Widget _autocompleteEspecie() {
    final plantas = ref.watch(plantasProvider);
    return Autocomplete<String>(
      initialValue: TextEditingValue(text: _especie.text),
      optionsBuilder: (TextEditingValue tev) {
        final query = tev.text.trim().toLowerCase();
        final set = <String>{};
        final salida = <String>[];
        for (final p in plantas) {
          final esp = p.especie;
          if (esp.isEmpty) continue;
          if (query.isNotEmpty && !esp.toLowerCase().contains(query)) continue;
          if (set.add(esp.toLowerCase())) salida.add(esp);
        }
        salida.sort();
        return salida.take(15);
      },
      onSelected: (v) {
        _especie.text = v;
        _agendarVerificacionEppo();
      },
      fieldViewBuilder: (ctx, controller, focus, onSubmit) {
        controller.value = TextEditingValue(text: _especie.text);
        controller.addListener(() {
          if (controller.text != _especie.text) _especie.text = controller.text;
        });
        return TextField(
          controller: controller,
          focusNode: focus,
          onSubmitted: (_) => onSubmit(),
          decoration: const InputDecoration(
              labelText: 'Especie (nombre científico)',
              hintText: 'Ej: Solanum lycopersicum',
              border: OutlineInputBorder()),
        );
      },
    );
  }

  /// Mensaje de estado de verificación EPPO bajo un campo. Muestra:
  ///   - null → sin verificación (o campo vacío) → nada.
  ///   - true → chip verde discreto.
  ///   - false → advertencia amarilla + botón de diagnóstico.
  Widget _mensajeEppo({
    required bool? ok,
    required String textoOk,
    required String textoWarn,
    String? terminoDiagnostico,
  }) {
    if (ok == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            ok ? textoOk : textoWarn,
            style: TextStyle(
              fontSize: 11,
              color:
                  ok ? Colors.green.shade700 : Colors.orange.shade800,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!ok &&
              terminoDiagnostico != null &&
              terminoDiagnostico.trim().isNotEmpty)
            TextButton.icon(
              onPressed: () =>
                  _mostrarDiagnosticoEppo(terminoDiagnostico.trim()),
              icon: const Icon(Icons.bug_report_outlined, size: 14),
              label: const Text('Diagnóstico EPPO',
                  style: TextStyle(fontSize: 11)),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 6, vertical: 0),
                minimumSize: const Size(0, 28),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
        ],
      ),
    );
  }

  /// Ejecuta debugSearch y muestra el resultado en un dialog con la URL,
  /// status, primeros resultados y match elegido. Sirve para diagnosticar
  /// por qué EPPO no reconoce un nombre.
  Future<void> _mostrarDiagnosticoEppo(String termino) async {
    final cfg = await ref.read(configProvider.future);
    final token = cfg?.eppoToken?.trim();
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Sin token EPPO'),
          content: const Text(
              'Configura tu API key de EPPO en Configuración → EPPO Global Database.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'))
          ],
        ),
      );
      return;
    }
    // Loader
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 40,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
    final client = EppoClient(token);
    late EppoDebugSearch res;
    try {
      res = await client.debugSearch(termino);
    } finally {
      client.close();
    }
    if (!mounted) return;
    Navigator.pop(context); // cierra loader
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Diagnóstico EPPO · "$termino"'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _kv('URL', res.url),
                _kv('Status HTTP', res.statusCode.toString()),
                _kv('Total resultados', res.totalEncontrados.toString()),
                _kv('Match elegido', res.matchElegido ?? '— ninguno —'),
                if (res.error != null) _kv('Error', res.error!),
                const SizedBox(height: 8),
                if (res.primerosResultados.isNotEmpty) ...[
                  const Text('Primeros resultados:',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  ...res.primerosResultados.map((m) => Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          m.entries
                              .map((e) => '${e.key}: ${e.value}')
                              .join('\n'),
                          style: const TextStyle(
                              fontFamily: 'monospace', fontSize: 11),
                        ),
                      )),
                ] else if (res.bodyPreview != null) ...[
                  const Text('Body raw (preview):',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(res.bodyPreview!,
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 11)),
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cerrar')),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: RichText(
          text: TextSpan(
            style: const TextStyle(
                fontSize: 11,
                color: Colors.black,
                fontFamily: 'monospace'),
            children: [
              TextSpan(
                  text: '$k: ',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              TextSpan(text: v),
            ],
          ),
        ),
      );

  int? _i(TextEditingController c) {
    final v = c.text.trim();
    if (v.isEmpty) return null;
    return int.tryParse(v);
  }

  String? _s(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    final nombre = _nombre.text.trim();
    if (nombre.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('El nombre común es obligatorio')));
      return;
    }
    if (_metodo == 'germinador' && (_i(_germinadorDias) ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Ingresa días en germinador (> 0) o cambia a siembra directa')));
      return;
    }
    if (_tipoCultivo == 'perenne') {
      if ((_i(_cosechaMin) ?? 0) <= 0 ||
          (_i(_periodicidad) ?? 0) <= 0 ||
          (_i(_esperanzaVida) ?? 0) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Indica días hasta 1ª cosecha, periodicidad y esperanza de vida')));
        return;
      }
    } else if ((_i(_cosechaMin) ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Indica los días hasta Cosecha 1 (verde/tierno)')));
      return;
    }

    final ciclos = <CicloAbono>[];
    for (var i = 0; i < _ciclosAbono.length; i++) {
      final c = _ciclosAbono[i].toCiclo();
      if (c == null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            behavior: SnackBarBehavior.floating,
            content: Text(
                'Revisa Abono ${i + 1}: indica el tipo y días válidos (≥ 0)')));
        return;
      }
      ciclos.add(c);
    }
    ciclos.sort((a, b) => a.dias.compareTo(b.dias));
    final ciclosJson = encodeCiclosAbonoJson(ciclos);
    final esPerenne = _tipoCultivo == 'perenne';

    setState(() => _saving = true);
    try {
      final mut = ref.read(dataMutationsProvider);
      int patologiasNuevas = 0;
      if (widget.existing == null) {
        final res = await mut.addPlanta(
          nombreComun: nombre,
          especie: _s(_especie),
          tiempoCosechaMinDias: _i(_cosechaMin),
          tiempoCosechaMaxDias: esPerenne ? null : _i(_cosechaMax),
          tipoCultivoDefault: _tipoCultivo,
          periodicidadCosechaDias: esPerenne ? _i(_periodicidad) : null,
          esperanzaVidaDias: esPerenne ? _i(_esperanzaVida) : null,
          ciclosAbonoJson: ciclosJson,
          metodoSiembra: _metodo,
          germinadorDias: _metodo == 'germinador' ? _i(_germinadorDias) : null,
          tipoAbono1: ciclos.isNotEmpty ? ciclos.first.tipo : null,
          tipoAbono2: ciclos.length > 1 ? ciclos[1].tipo : null,
          diasAbono2: ciclos.length > 1 ? ciclos[1].dias : null,
          fuenteMetodo: _s(_fuente),
          notas: _s(_notas),
        );
        patologiasNuevas = res.patologiasAutoAgregadas;
      } else {
        patologiasNuevas = await mut.updatePlanta(
          id: widget.existing!.id,
          nombreComun: nombre,
          especie: _s(_especie),
          tiempoCosechaMinDias: _i(_cosechaMin),
          tiempoCosechaMaxDias: esPerenne ? null : _i(_cosechaMax),
          tipoCultivoDefault: _tipoCultivo,
          periodicidadCosechaDias: esPerenne ? _i(_periodicidad) : null,
          esperanzaVidaDias: esPerenne ? _i(_esperanzaVida) : null,
          ciclosAbonoJson: ciclosJson,
          metodoSiembra: _metodo,
          germinadorDias: _metodo == 'germinador' ? _i(_germinadorDias) : null,
          tipoAbono1: ciclos.isNotEmpty ? ciclos.first.tipo : null,
          tipoAbono2: ciclos.length > 1 ? ciclos[1].tipo : null,
          diasAbono2: ciclos.length > 1 ? ciclos[1].dias : null,
          fuenteMetodo: _s(_fuente),
          notas: _s(_notas),
        );
      }
      if (_compartirComunidad) {
        unawaited(VariedadesComunitariasService.contribuir(
          nombre: nombre,
          especie: _s(_especie),
          metodoSiembra: _metodo,
          germinadorDias:
              _metodo == 'germinador' ? _i(_germinadorDias) : null,
          cosechaMinDias: _i(_cosechaMin),
          cosechaMaxDias: esPerenne ? null : _i(_cosechaMax),
          tipoAbono1: ciclos.isNotEmpty ? ciclos.first.tipo : null,
          tipoAbono2: ciclos.length > 1 ? ciclos[1].tipo : null,
          abono2Dias: ciclos.length > 1 ? ciclos[1].dias : null,
          fuente: _s(_fuente),
        ));
      }
      if (mounted) {
        Navigator.pop(context);
        final base = widget.existing == null
            ? 'Variedad "$nombre" creada'
            : 'Variedad "$nombre" actualizada';
        final suf = patologiasNuevas > 0
            ? ' · $patologiasNuevas patología${patologiasNuevas == 1 ? "" : "s"} añadida${patologiasNuevas == 1 ? "" : "s"} al catálogo'
            : '';
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$base$suf')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
