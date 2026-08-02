import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../core/navigation/app_nav.dart';
import '../../core/widgets/acceso_denegado.dart';
import '../../core/widgets/app_shell.dart';
import '../../core/widgets/duracion_field.dart';
import '../../core/widgets/unit_dropdown.dart';
import '../../state/data_state.dart';

class AddCropScreen extends ConsumerStatefulWidget {
  const AddCropScreen({super.key});
  @override
  ConsumerState<AddCropScreen> createState() => _AddCropScreenState();
}

class _AddCropScreenState extends ConsumerState<AddCropScreen> {
  int _selectedIdx = 0;
  DateTime _fecha = DateTime.now();
  final _loteCtrl = TextEditingController();
  final _areaCtrl = TextEditingController(text: '100');
  String _areaUnit = 'm2';
  final _semillaCtrl = TextEditingController(text: '1');
  String _semillaUnit = 'kg';
  final _hhCtrl = TextEditingController(text: '0');
  final _horaCtrl = TextEditingController(text: '6500');
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();
  final _altCtrl = TextEditingController();
  String _tipoCultivo = 'ciclo_unico';
  final _cosecha1DiasCtrl = DuracionController();
  final _cosecha2DiasCtrl = DuracionController();
  final _periodicidadCtrl = DuracionController();
  final _esperanzaVidaCtrl = DuracionController();
  int? _loteId;
  bool _obtainingGnss = false;

  @override
  void dispose() {
    _loteCtrl.dispose();
    _areaCtrl.dispose();
    _semillaCtrl.dispose();
    _hhCtrl.dispose();
    _horaCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    _altCtrl.dispose();
    _cosecha1DiasCtrl.dispose();
    _cosecha2DiasCtrl.dispose();
    _periodicidadCtrl.dispose();
    _esperanzaVidaCtrl.dispose();
    super.dispose();
  }

  int? _plantaHidratadaId;

  void _hidratarPeriodosDesdePlanta(Planta pl) {
    if (_plantaHidratadaId == pl.id) return;
    _plantaHidratadaId = pl.id;
    // Se invoca desde `build`: diferimos la mutación de controllers y el
    // setState al siguiente frame para no reconstruir durante el build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() {
        _tipoCultivo = pl.tipoCultivoDefault;
        _cosecha1DiasCtrl.setDias(pl.cosechaMin);
        if (pl.esPerenneDefault) {
          _periodicidadCtrl.setDias(pl.periodicidadCosechaDias ?? 90);
          _esperanzaVidaCtrl.setDias(pl.esperanzaVidaDias ?? 1095);
          _cosecha2DiasCtrl.limpiar();
        } else {
          _cosecha2DiasCtrl.setDias(pl.cosechaMax);
          _periodicidadCtrl.limpiar();
          _esperanzaVidaCtrl.limpiar();
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final plantas = ref.watch(plantasListadoProvider);
    if (plantas.isEmpty) {
      return AppShell(
        title: 'Agregar cultivo',
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'No hay variedades disponibles. Agrega una propia o '
                  'sincroniza el banco comunitario desde Plantas.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => AppNav.open(context, '/plants'),
                  icon: const Icon(Icons.grass),
                  label: const Text('Ir a Plantas'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final pl = plantas[_selectedIdx.clamp(0, plantas.length - 1)];
    _hidratarPeriodosDesdePlanta(pl);
    final esGerminador = pl.metodoSiembra == 'germinador';
    final lotes = ref.watch(lotesActivosProvider).maybeWhen(
        data: (l) => l, orElse: () => const []);

    // Gating por rol: un consultor entró aquí por URL o por un botón que
    // no debería estar visible — mostramos aviso y bloqueamos la creación.
    final permisos = ref.watch(permisosPredioActivoProvider);
    if (!permisos.puedeEditarCultivosYTareas) {
      return const AppShell(
        title: 'Agregar cultivo',
        child: AccesoDenegado(
            mensaje:
                'Tu rol en este predio es solo lectura. Pídele al propietario que te asigne rol "trabajador" para crear cultivos.'),
      );
    }

    return AppShell(
      title: 'Agregar cultivo',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Paso 2 de 2 — Datos del cultivo',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),

          DropdownButtonFormField<int>(
            decoration: const InputDecoration(
                labelText: 'Planta', border: OutlineInputBorder()),
            value: _selectedIdx,
            items: List.generate(
                plantas.length,
                (i) => DropdownMenuItem(
                      value: i,
                      child: Text(plantas[i].nombreEnSelector),
                    )),
            onChanged: (v) => setState(() {
              _selectedIdx = v ?? 0;
              _plantaHidratadaId = null;
            }),
          ),
          const SizedBox(height: 12),

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
          const SizedBox(height: 8),
          if (_tipoCultivo == 'ciclo_unico') ...[
            Text(
              'Periodos estimados desde la fecha base fenológica '
              '(siembra o trasplante):',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DuracionField(
                  controller: _cosecha1DiasCtrl,
                  label: 'Hasta Cosecha 1',
                  dense: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DuracionField(
                  controller: _cosecha2DiasCtrl,
                  label: 'Hasta Cosecha 2',
                  dense: true,
                ),
              ),
            ]),
          ] else ...[
            Text(
              'Periodos desde la fecha base fenológica (siembra o trasplante). '
              'La periodicidad de cosechas arranca tras la primera cosecha:',
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 8),
            DuracionField(
              controller: _cosecha1DiasCtrl,
              label: 'Tiempo hasta primera cosecha',
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: DuracionField(
                  controller: _periodicidadCtrl,
                  label: 'Periodicidad de cosecha',
                  helperText: 'Desde la primera cosecha en adelante',
                  dense: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DuracionField(
                  controller: _esperanzaVidaCtrl,
                  label: 'Esperanza de vida',
                  helperText: 'Hasta renovación del cultivo',
                  dense: true,
                ),
              ),
            ]),
          ],
          const SizedBox(height: 12),

          // Recomendación de método de siembra
          Card(
            color: esGerminador ? Colors.orange.shade50 : Colors.green.shade50,
            child: Container(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(
                    color: esGerminador ? Colors.orange : Colors.green,
                    width: 4)),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(esGerminador ? '🌱🪴' : '🌾',
                        style: const TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                          esGerminador
                              ? 'Requiere GERMINADOR (semillero + trasplante)'
                              : 'SIEMBRA DIRECTA',
                          style: TextStyle(fontWeight: FontWeight.bold,
                              color: esGerminador
                                  ? Colors.orange.shade900
                                  : Colors.green.shade900)),
                    ),
                    const Text('Fuente ICA/EPPO/FAO',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ]),
                  const SizedBox(height: 6),
                  Text(pl.fuenteMetodo,
                      style: const TextStyle(fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(esGerminador
                      ? 'El cultivo inicia en etapa GERMINADO. El trasplante '
                          'quedará agendado para dentro de ${pl.germinadorDias ?? "?"} '
                          'días y se registrará como actividad cuando lo ejecutes.'
                      : 'No requiere actividades adicionales de semillero/trasplante.',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          if (lotes.isNotEmpty) ...[
            DropdownButtonFormField<int?>(
              value: _loteId,
              items: [
                const DropdownMenuItem<int?>(
                    value: null, child: Text('— Sin lote definido —')),
                ...lotes.map<DropdownMenuItem<int?>>((l) => DropdownMenuItem(
                      value: l.id as int,
                      child: Text(l.nombre as String),
                    )),
              ],
              onChanged: (v) => setState(() {
                _loteId = v;
                // Al elegir un lote, prellena nombre y altitud desde el lote.
                if (v != null) {
                  final l = lotes.firstWhere((x) => x.id == v);
                  _loteCtrl.text = l.nombre as String;
                  if (l.altitudMsnm != null && _altCtrl.text.isEmpty) {
                    _altCtrl.text =
                        (l.altitudMsnm as double).toStringAsFixed(0);
                  }
                }
              }),
              decoration: const InputDecoration(
                  labelText: 'Lote registrado',
                  helperText: 'Elige un lote del predio o deja libre',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _loteCtrl,
            decoration: const InputDecoration(
                labelText: 'Nombre del lote (libre)',
                hintText: 'Lote norte, Era 3…',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),

          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _fecha,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) setState(() => _fecha = picked);
            },
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: esGerminador
                    ? 'Fecha de siembra en germinador'
                    : 'Fecha de siembra',
                helperText: esGerminador
                    ? 'Hoy se registra el semillero. El trasplante se agenda '
                        'automáticamente ${pl.germinadorDias ?? "?"} días después.'
                    : null,
                suffixIcon: const Icon(Icons.calendar_today),
                border: const OutlineInputBorder(),
              ),
              child: Text('${_fecha.year}-${_fecha.month.toString().padLeft(2, "0")}-${_fecha.day.toString().padLeft(2, "0")}'),
            ),
          ),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(
              child: TextField(
                controller: _areaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Área', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: UnitDropdown(
                label: 'Unidad área',
                value: _areaUnit,
                dimensions: const ['area'],
                onChanged: (v) => setState(() => _areaUnit = v ?? 'm2'),
              ),
            ),
          ]),
          const SizedBox(height: 12),

          Row(children: [
            Expanded(
              child: TextField(
                controller: _semillaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Cantidad semilla',
                    helperText: 'Se descuenta del inventario',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: UnitDropdown(
                label: 'Unidad semilla',
                value: _semillaUnit,
                dimensions: const ['peso', 'unidad'],
                onChanged: (v) => setState(() => _semillaUnit = v ?? 'kg'),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          const Text('Georreferenciación',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _latCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                    labelText: 'Latitud',
                    hintText: 'Ej: 4.473252',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lngCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                    labelText: 'Longitud',
                    hintText: 'Ej: -75.698197',
                    border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _altCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
                labelText: 'Altitud (msnm)',
                hintText: 'Se autocompleta al capturar GPS',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 6),
          Row(children: [
            OutlinedButton.icon(
              onPressed: _obtainingGnss ? null : _obtainerGnss,
              icon: _obtainingGnss
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.my_location, size: 18),
              label: Text(_obtainingGnss ? 'Obteniendo…' : 'Usar GNSS'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _latCtrl.clear();
                _lngCtrl.clear();
                _altCtrl.clear();
              }),
              icon: const Icon(Icons.clear, size: 18),
              label: const Text('Limpiar'),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
              'Se pueden ingresar manualmente o capturar desde GPS del dispositivo.',
              style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
          const SizedBox(height: 16),

          const Text('Mano de obra',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _hhCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'HH iniciales',
                    helperText: 'Se acumulan con cada tarea',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _horaCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                    labelText: 'Costo/hora (COP)', border: OutlineInputBorder()),
              ),
            ),
          ]),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
              onPressed: () => AppNav.popOrGo(context, '/crops'),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _save, child: const Text('Guardar')),
          ]),
        ],
      ),
    );
  }

  Future<void> _obtainerGnss() async {
    setState(() => _obtainingGnss = true);
    try {
      // Verifica que el servicio esté activo
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Activa el servicio de ubicación del sistema')));
        return;
      }
      // Permisos
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Permiso de ubicación denegado')));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _latCtrl.text = pos.latitude.toStringAsFixed(6);
        _lngCtrl.text = pos.longitude.toStringAsFixed(6);
        if (!pos.altitude.isNaN) {
          _altCtrl.text = pos.altitude.toStringAsFixed(0);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Coordenadas capturadas '
              '(precisión ±${pos.accuracy.toStringAsFixed(0)} m'
              '${!pos.altitude.isNaN ? " · alt ${pos.altitude.toStringAsFixed(0)} msnm" : ""})')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo obtener GNSS: $e — puedes ingresar manualmente')));
    } finally {
      if (mounted) setState(() => _obtainingGnss = false);
    }
  }

  Future<void> _save() async {
    final plantas = ref.read(plantasListadoProvider);
    if (plantas.isEmpty) return;
    final pl = plantas[_selectedIdx.clamp(0, plantas.length - 1)];
    final eraComunidad = pl.esComunidad;
    final area = double.tryParse(_areaCtrl.text) ?? 0;
    final semilla = double.tryParse(_semillaCtrl.text) ?? 0;
    final hh = double.tryParse(_hhCtrl.text) ?? 0;
    final horaValor = double.tryParse(_horaCtrl.text) ?? 6500;
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    final alt = double.tryParse(_altCtrl.text.replaceAll(',', '.'));

    int? cosecha1Dias;
    int? cosecha2Dias;
    int? periodicidad;
    int? esperanzaVida;
    if (_tipoCultivo == 'ciclo_unico') {
      cosecha1Dias = _cosecha1DiasCtrl.dias;
      cosecha2Dias = _cosecha2DiasCtrl.dias;
      if (cosecha1Dias == null || cosecha1Dias <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Indica el tiempo estimado hasta Cosecha 1')));
        return;
      }
    } else {
      cosecha1Dias = _cosecha1DiasCtrl.dias;
      periodicidad = _periodicidadCtrl.dias;
      esperanzaVida = _esperanzaVidaCtrl.dias;
      if (cosecha1Dias == null || cosecha1Dias <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Indica el tiempo estimado hasta la primera cosecha')));
        return;
      }
      if (periodicidad == null ||
          periodicidad <= 0 ||
          esperanzaVida == null ||
          esperanzaVida <= 0) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Indica periodicidad de cosecha y esperanza de vida')));
        return;
      }
    }

    try {
      await ref.read(dataMutationsProvider).addCultivo(
            plantaId: pl.id,
            lote: _loteCtrl.text,
            fechaSiembra: _fecha,
            areaValor: area,
            areaUnidad: _areaUnit,
            semillaValor: semilla,
            semillaUnidad: _semillaUnit,
            hhInicial: hh,
            horaValor: horaValor,
            lat: lat,
            lng: lng,
            altM: alt,
            loteId: _loteId,
            tipoCultivo: _tipoCultivo,
            cosecha1Dias: cosecha1Dias,
            cosecha2Dias: cosecha2Dias,
            periodicidadCosechaDias: periodicidad,
            esperanzaVidaDias: esperanzaVida,
          );
      if (!mounted) return;
      final sufijoComunidad = eraComunidad
          ? ' · "${pl.nombre}" copiada a tu catálogo'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(semilla > 0
            ? 'Cultivo guardado · $semilla $_semillaUnit descontado(s) del inventario$sufijoComunidad'
            : 'Cultivo guardado$sufijoComunidad'),
      ));
      AppNav.popOrGo(context, '/crops');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')));
    }
  }
}
