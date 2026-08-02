import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/navigation/app_nav.dart';
import 'package:path/path.dart' as p;
import '../../core/widgets/acceso_denegado.dart';
import '../../core/widgets/app_shell.dart';
import '../../services/soporte_service.dart';
import '../../state/data_state.dart';

class AddSoilAnalysisScreen extends ConsumerStatefulWidget {
  const AddSoilAnalysisScreen({super.key, this.editId});
  final int? editId;

  @override
  ConsumerState<AddSoilAnalysisScreen> createState() =>
      _AddSoilAnalysisScreenState();
}

class _AddSoilAnalysisScreenState extends ConsumerState<AddSoilAnalysisScreen> {
  DateTime _fecha = DateTime.now();
  final _lote = TextEditingController();
  final _lab = TextEditingController();
  final _prof = TextEditingController(text: '20');
  String? _textura;
  final _densidad = TextEditingController();
  final _cond = TextEditingController();
  final _ph = TextEditingController();
  final _mo = TextEditingController();
  final _n = TextEditingController();
  final _p = TextEditingController();
  final _k = TextEditingController();
  final _ca = TextEditingController();
  final _mg = TextEditingController();
  final _na = TextEditingController();
  final _cic = TextEditingController();
  final _s = TextEditingController();
  final _b = TextEditingController();
  final _notas = TextEditingController();

  static const _texturas = [
    'arenoso',
    'franco-arenoso',
    'franco',
    'franco-arcilloso',
    'arcilloso',
    'limoso',
  ];

  @override
  void dispose() {
    for (final c in [
      _lote, _lab, _prof, _densidad, _cond, _ph, _mo,
      _n, _p, _k, _ca, _mg, _na, _cic, _s, _b, _notas,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Gating por rol: solo propietario puede crear/editar análisis.
    final puedeEditar = ref
        .watch(permisosPredioActivoProvider)
        .puedeEditarSueloYCondiciones;
    if (!puedeEditar) {
      return const AppShell(
        title: 'Análisis de suelo',
        child: AccesoDenegado(
            mensaje:
                'Solo el propietario del predio puede registrar o editar análisis de suelo.'),
      );
    }
    return AppShell(
      title: widget.editId == null ? 'Nuevo análisis' : 'Editar análisis',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Registro de análisis físico-químico de suelo',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          // Fecha + lote + laboratorio
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _fecha,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (picked != null) setState(() => _fecha = picked);
            },
            child: InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Fecha de muestreo',
                suffixIcon: Icon(Icons.calendar_today),
                border: OutlineInputBorder(),
              ),
              child: Text(_iso(_fecha)),
            ),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _lote,
                decoration: const InputDecoration(
                    labelText: 'Lote (opcional)',
                    hintText: 'Lote norte, Era 3…',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lab,
                decoration: const InputDecoration(
                    labelText: 'Laboratorio',
                    hintText: 'AGQ, Corpoica…',
                    border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _prof,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Profundidad (cm)',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _textura,
                items: _texturas
                    .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                    .toList(),
                onChanged: (v) => setState(() => _textura = v),
                decoration: const InputDecoration(
                    labelText: 'Textura', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          _sectionTitle('Físicas'),
          Row(children: [
            Expanded(child: _num(_densidad, 'Densidad (g/cm³)')),
            const SizedBox(width: 8),
            Expanded(child: _num(_cond, 'Conductividad (mS/cm)')),
          ]),
          const SizedBox(height: 16),

          _sectionTitle('Químicas principales'),
          Row(children: [
            Expanded(child: _num(_ph, 'pH')),
            const SizedBox(width: 8),
            Expanded(child: _num(_mo, 'MO (%)')),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: _num(_n, 'N (ppm)')),
            const SizedBox(width: 8),
            Expanded(child: _num(_p, 'P (ppm)')),
            const SizedBox(width: 8),
            Expanded(child: _num(_k, 'K (ppm)')),
          ]),
          const SizedBox(height: 16),

          _sectionTitle('Bases intercambiables (meq/100g)'),
          Row(children: [
            Expanded(child: _num(_ca, 'Ca')),
            const SizedBox(width: 8),
            Expanded(child: _num(_mg, 'Mg')),
            const SizedBox(width: 8),
            Expanded(child: _num(_na, 'Na')),
          ]),
          const SizedBox(height: 8),
          _num(_cic, 'CIC (meq/100g)'),
          const SizedBox(height: 16),

          _sectionTitle('Menores (opcional)'),
          Row(children: [
            Expanded(child: _num(_s, 'S (ppm)')),
            const SizedBox(width: 8),
            Expanded(child: _num(_b, 'B (ppm)')),
          ]),
          const SizedBox(height: 16),

          TextField(
            controller: _notas,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'Notas', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          // PDF del laboratorio (opcional, 2026-07-20). Se copia a
          // Documents/analisis_suelo/{año}/ y el path queda en la fila.
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _adjuntarPdfLab,
                icon: const Icon(Icons.picture_as_pdf_outlined),
                label: Text(
                  _soportePath == null
                      ? 'Adjuntar PDF del laboratorio (opcional)'
                      : p.basename(_soportePath!),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            if (_soportePath != null)
              IconButton(
                tooltip: 'Quitar PDF',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () => setState(() {
                  _soportePath = null;
                  _soporteTipo = null;
                }),
              ),
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
                onPressed: () => AppNav.popOrGo(context, '/soil-analysis'),
                child: const Text('Cancelar')),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: const Text('Guardar')),
          ]),
        ],
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

  String? _s2(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  String? _soportePath;
  String? _soporteTipo;

  /// Adjunta el PDF del laboratorio en analisis_suelo/{año}/{lab}-{fecha}.pdf
  Future<void> _adjuntarPdfLab() async {
    try {
      final srv = SoporteService.instance;
      final lab = _s2(_lab) ?? 'LAB';
      final nombreBase =
          '${srv.sanitizar(lab)}-${_iso(_fecha)}';
      final path = await srv.adjuntarPdf(
        anio: _fecha.year,
        nombreBase: nombreBase,
        subdir: 'analisis_suelo',
      );
      if (path != null && mounted) {
        setState(() {
          _soportePath = path;
          _soporteTipo = 'application/pdf';
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('No se pudo adjuntar: $e')));
    }
  }

  Future<void> _save() async {
    try {
      await ref.read(dataMutationsProvider).addAnalisisSuelo(
            fechaMuestreo: _fecha,
            lote: _s2(_lote),
            laboratorio: _s2(_lab),
            profundidadCm: _d(_prof),
            textura: _textura,
            densidadGCm3: _d(_densidad),
            conductividadMsCm: _d(_cond),
            ph: _d(_ph),
            materiaOrganicaPct: _d(_mo),
            nPpm: _d(_n),
            pPpm: _d(_p),
            kPpm: _d(_k),
            caMeq: _d(_ca),
            mgMeq: _d(_mg),
            naMeq: _d(_na),
            cicMeq: _d(_cic),
            sPpm: _d(_s),
            bPpm: _d(_b),
            soportePath: _soportePath,
            soporteTipo: _soporteTipo,
            notas: _s2(_notas),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Análisis guardado')));
      AppNav.popOrGo(context, '/soil-analysis');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  static String _iso(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';
}
