import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/acceso_denegado.dart';
import '../../core/widgets/app_shell.dart';
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
  int? _loteId;
  bool _obtainingGnss = false;

  @override
  Widget build(BuildContext context) {
    final plantas = ref.watch(plantasProvider);
    final pl = plantas[_selectedIdx.clamp(0, plantas.length - 1)];
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
            items: List.generate(plantas.length, (i) =>
                DropdownMenuItem(value: i, child: Text(plantas[i].nombre))),
            onChanged: (v) => setState(() => _selectedIdx = v ?? 0),
          ),
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
              onPressed: () => context.go('/crops'),
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
    final plantas = ref.read(plantasProvider);
    if (plantas.isEmpty) return;
    final pl = plantas[_selectedIdx.clamp(0, plantas.length - 1)];
    final area = double.tryParse(_areaCtrl.text) ?? 0;
    final semilla = double.tryParse(_semillaCtrl.text) ?? 0;
    final hh = double.tryParse(_hhCtrl.text) ?? 0;
    final horaValor = double.tryParse(_horaCtrl.text) ?? 6500;
    final lat = double.tryParse(_latCtrl.text);
    final lng = double.tryParse(_lngCtrl.text);
    final alt = double.tryParse(_altCtrl.text.replaceAll(',', '.'));
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
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(semilla > 0
            ? 'Cultivo guardado · $semilla $_semillaUnit descontado(s) del inventario'
            : 'Cultivo guardado'),
      ));
      context.go('/crops');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')));
    }
  }
}
