import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/app_nav.dart';
import '../../core/widgets/acceso_denegado.dart';
import '../../core/widgets/app_shell.dart';
import '../../state/data_state.dart';

class PlotConditionsScreen extends ConsumerStatefulWidget {
  const PlotConditionsScreen({super.key});

  @override
  ConsumerState<PlotConditionsScreen> createState() =>
      _PlotConditionsScreenState();
}

class _PlotConditionsScreenState extends ConsumerState<PlotConditionsScreen> {
  final _altitud = TextEditingController();
  final _precip = TextEditingController();
  final _tempMedia = TextEditingController();
  final _tempMin = TextEditingController();
  final _tempMax = TextEditingController();
  final _humedad = TextEditingController();
  final _notas = TextEditingController();
  String? _zonaClimatica;
  String? _pisoTermico;
  String? _fuente;
  bool _hydrated = false;
  bool _saving = false;

  static const _zonas = [
    'tropical seco',
    'tropical húmedo',
    'subtropical',
    'templado',
    'frío',
    'páramo',
  ];
  static const _pisos = [
    'cálido (0–1000 msnm)',
    'templado (1000–2000 msnm)',
    'frío (2000–3000 msnm)',
    'páramo (>3000 msnm)',
  ];
  static const _fuentes = ['IDEAM', 'medición propia', 'estimación', 'otra'];

  @override
  void dispose() {
    for (final c in [
      _altitud, _precip, _tempMedia, _tempMin, _tempMax, _humedad, _notas
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(dynamic cond) {
    if (_hydrated || cond == null) return;
    _altitud.text = cond.altitudMsnm?.toStringAsFixed(0) ?? '';
    _precip.text = cond.precipitacionAnualMm?.toStringAsFixed(0) ?? '';
    _tempMedia.text = cond.tempMediaC?.toStringAsFixed(1) ?? '';
    _tempMin.text = cond.tempMinC?.toStringAsFixed(1) ?? '';
    _tempMax.text = cond.tempMaxC?.toStringAsFixed(1) ?? '';
    _humedad.text = cond.humedadRelativaPct?.toStringAsFixed(0) ?? '';
    _notas.text = cond.notas ?? '';
    _zonaClimatica = cond.zonaClimatica;
    _pisoTermico = cond.pisoTermico;
    _fuente = cond.fuente;
    _hydrated = true;
  }

  @override
  Widget build(BuildContext context) {
    // Gating por rol (revisión 2026-07-20, hallazgo #2): condiciones del
    // predio son R/W solo del propietario; bloquear acceso por URL.
    final puedeEditar = ref
        .watch(permisosPredioActivoProvider)
        .puedeEditarSueloYCondiciones;
    if (!puedeEditar) {
      return const AppShell(
        title: 'Condiciones del predio',
        child: AccesoDenegado(
            mensaje:
                'Solo el propietario del predio puede registrar o editar '
                'las condiciones edafoclimáticas.'),
      );
    }
    final async = ref.watch(condicionesPredioProvider);
    return AppShell(
      title: 'Condiciones del predio',
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (cond) {
          _hydrate(cond);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    const Icon(Icons.info_outline, color: Colors.blue),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          cond == null
                              ? 'Registra las condiciones edafoclimáticas de tu predio '
                                  'para obtener recomendaciones agronómicas precisas.'
                              : 'Última actualización: ${_iso(cond.fechaActualizacion as DateTime)}',
                          style: const TextStyle(fontSize: 12)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 12),
              _sectionTitle('Altitud y clima'),
              _num(_altitud, 'Altitud (msnm)'),
              const SizedBox(height: 8),
              _num(_precip, 'Precipitación anual (mm)'),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: _num(_tempMedia, 'Temp. media (°C)')),
                const SizedBox(width: 8),
                Expanded(child: _num(_tempMin, 'Temp. mín (°C)')),
                const SizedBox(width: 8),
                Expanded(child: _num(_tempMax, 'Temp. máx (°C)')),
              ]),
              const SizedBox(height: 8),
              _num(_humedad, 'Humedad relativa (%)'),
              const SizedBox(height: 16),

              _sectionTitle('Zona / clasificación'),
              DropdownButtonFormField<String>(
                value: _zonaClimatica,
                items: _zonas
                    .map((z) => DropdownMenuItem(value: z, child: Text(z)))
                    .toList(),
                onChanged: (v) => setState(() => _zonaClimatica = v),
                decoration: const InputDecoration(
                    labelText: 'Zona climática',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _pisoTermico,
                items: _pisos
                    .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                    .toList(),
                onChanged: (v) => setState(() => _pisoTermico = v),
                decoration: const InputDecoration(
                    labelText: 'Piso térmico', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 16),

              _sectionTitle('Fuente'),
              DropdownButtonFormField<String>(
                value: _fuente,
                items: _fuentes
                    .map((f) => DropdownMenuItem(value: f, child: Text(f)))
                    .toList(),
                onChanged: (v) => setState(() => _fuente = v),
                decoration: const InputDecoration(
                    labelText: 'Fuente del dato',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _notas,
                maxLines: 2,
                decoration: const InputDecoration(
                    labelText: 'Notas', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 20),
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton(
                    onPressed:
                        _saving ? null : () => AppNav.popOrGo(context, '/settings'),
                    child: const Text('Cancelar')),
                const SizedBox(width: 8),
                FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Guardar')),
              ]),
            ],
          );
        },
      ),
    );
  }

  Widget _sectionTitle(String s) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(s,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      );

  Widget _num(TextEditingController c, String label) => TextField(
        controller: c,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
            labelText: label, border: const OutlineInputBorder()),
      );

  double? _d(TextEditingController c) {
    final v = c.text.trim();
    if (v.isEmpty) return null;
    return double.tryParse(v.replaceAll(',', '.'));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ref.read(dataMutationsProvider).upsertCondicionesPredio(
            altitudMsnm: _d(_altitud),
            precipitacionAnualMm: _d(_precip),
            tempMediaC: _d(_tempMedia),
            tempMinC: _d(_tempMin),
            tempMaxC: _d(_tempMax),
            humedadRelativaPct: _d(_humedad),
            zonaClimatica: _zonaClimatica,
            pisoTermico: _pisoTermico,
            fuente: _fuente,
            notas: _notas.text.trim().isEmpty ? null : _notas.text.trim(),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Condiciones guardadas')));
      AppNav.popOrGo(context, '/settings');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}
