// Editor de lote con captura interactiva de coordenadas del polígono.
// Soporta agregar puntos manualmente o desde GPS (con altitud), reordenar,
// eliminar. Muestra el polígono en un mini-mapa.

import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/acceso_denegado.dart';
import '../../core/widgets/app_shell.dart';
import '../../state/data_state.dart';

class LoteEditorScreen extends ConsumerStatefulWidget {
  const LoteEditorScreen({super.key, required this.predioId, this.loteId});
  final int predioId;
  final int? loteId;

  @override
  ConsumerState<LoteEditorScreen> createState() => _LoteEditorScreenState();
}

class _LoteEditorScreenState extends ConsumerState<LoteEditorScreen> {
  final _nombre = TextEditingController();
  final _admin = TextEditingController();
  final _altitud = TextEditingController();
  final _area = TextEditingController();
  final _notas = TextEditingController();
  final _latIn = TextEditingController();
  final _lngIn = TextEditingController();

  final List<(double, double)> _puntos = [];
  bool _obteniendoGnss = false;
  bool _hydrated = false;
  bool _saving = false;
  /// Si true, el campo Área se actualiza automáticamente al cambiar los
  /// puntos del polígono. Se apaga cuando el usuario edita el campo a mano.
  bool _areaAutoCalc = true;

  @override
  void dispose() {
    _nombre.dispose();
    _admin.dispose();
    _altitud.dispose();
    _area.dispose();
    _notas.dispose();
    _latIn.dispose();
    _lngIn.dispose();
    super.dispose();
  }

  void _hydrate(dynamic l) {
    if (_hydrated || l == null) return;
    _nombre.text = l.nombre as String;
    _admin.text = l.administrador as String? ?? '';
    _altitud.text = l.altitudMsnm != null
        ? (l.altitudMsnm as double).toStringAsFixed(0)
        : '';
    _area.text = l.areaM2 != null
        ? (l.areaM2 as double).toStringAsFixed(0)
        : '';
    // Si venía con área guardada distinta a null, respetamos edición manual
    // hasta que el usuario dé "Recalcular".
    if (l.areaM2 != null) _areaAutoCalc = false;
    _notas.text = l.notas as String? ?? '';
    if (l.poligonoGeoJson != null) {
      try {
        final list = jsonDecode(l.poligonoGeoJson as String) as List<dynamic>;
        for (final item in list) {
          if (item is List && item.length >= 2) {
            _puntos.add(((item[0] as num).toDouble(),
                (item[1] as num).toDouble()));
          }
        }
      } catch (_) {}
    }
    // Si venía sin área guardada pero con puntos, calcula ahora.
    if (l.areaM2 == null && _puntos.length >= 3) {
      _refrescarAreaSiAuto();
    }
    _hydrated = true;
  }

  @override
  Widget build(BuildContext context) {
    // Gating por rol (revisión 2026-07-20, hallazgo #2): los lotes son
    // R/W solo del propietario. Sin este check, un colaborador podía
    // llegar por URL directa y persistir cambios locales que el sync
    // nunca subiría (estado inconsistente).
    final permisos = ref.watch(permisosPredioProvider(widget.predioId));
    if (!permisos.puedeEditarPredioYLotes) {
      return const AppShell(
        title: 'Lote',
        child: AccesoDenegado(
            mensaje:
                'Solo el propietario del predio puede crear o editar lotes.'),
      );
    }
    final isEdit = widget.loteId != null;
    final lotes = ref.watch(lotesPorPredioProvider(widget.predioId));
    if (isEdit) {
      lotes.whenData((list) {
        final l = list.where((x) => x.id == widget.loteId).cast<dynamic>();
        if (l.isNotEmpty) _hydrate(l.first);
      });
    }
    return AppShell(
      title: isEdit ? 'Editar lote' : 'Nuevo lote',
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nombre,
            decoration: const InputDecoration(
                labelText: 'Nombre del lote *',
                hintText: 'Lote norte, Era 3…',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _admin,
            decoration: const InputDecoration(
                labelText: 'Administrador',
                hintText: 'Nombre del responsable del lote',
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: _altitud,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                    labelText: 'Altitud (msnm)',
                    border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _area,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                // Al editar manualmente, sale del modo auto para no
                // pisar la entrada del usuario en siguientes cambios.
                onChanged: (_) {
                  if (_areaAutoCalc) setState(() => _areaAutoCalc = false);
                },
                decoration: InputDecoration(
                  labelText: _areaAutoCalc
                      ? 'Área (m²) · calculada'
                      : 'Área (m²) · manual',
                  helperText: _areaHelperText(),
                  border: const OutlineInputBorder(),
                  suffixIcon: _areaAutoCalc
                      ? const Tooltip(
                          message: 'Calculada del polígono',
                          child: Icon(Icons.auto_fix_high, size: 18))
                      : IconButton(
                          icon: const Icon(Icons.refresh, size: 18),
                          tooltip: 'Recalcular desde el polígono',
                          onPressed: () => setState(() {
                            _areaAutoCalc = true;
                            _refrescarAreaSiAuto();
                          }),
                        ),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),

          const Text('Coordenadas del polígono',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          Text(
              'Agrega al menos 3 puntos para dibujar el polígono. Los puntos se '
              'conectan en el orden mostrado y el polígono se cierra automáticamente.',
              style: TextStyle(
                  fontSize: 11, color: Theme.of(context).hintColor)),
          const SizedBox(height: 8),

          // Entrada manual
          Row(children: [
            Expanded(
              child: TextField(
                controller: _latIn,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                    labelText: 'Latitud', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _lngIn,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: const InputDecoration(
                    labelText: 'Longitud', border: OutlineInputBorder()),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.add),
              tooltip: 'Agregar punto manual',
              onPressed: _addManual,
            ),
          ]),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _obteniendoGnss ? null : _capturarGps,
            icon: _obteniendoGnss
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 18),
            label:
                Text(_obteniendoGnss ? 'Obteniendo…' : 'Capturar punto GPS'),
          ),
          const SizedBox(height: 12),

          // Lista de puntos
          if (_puntos.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('Sin puntos capturados aún',
                    style: TextStyle(color: Theme.of(context).hintColor)),
              ),
            )
          else
            Card(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                    children: List.generate(_puntos.length, (i) {
                  final (lat, lng) = _puntos[i];
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                        radius: 12,
                        child: Text('${i + 1}',
                            style: const TextStyle(fontSize: 11))),
                    title: Text(
                        '${lat.toStringAsFixed(6)}, ${lng.toStringAsFixed(6)}',
                        style: const TextStyle(fontSize: 13)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      IconButton(
                          icon: const Icon(Icons.arrow_upward, size: 18),
                          onPressed: i > 0
                              ? () => setState(() {
                                    final tmp = _puntos.removeAt(i);
                                    _puntos.insert(i - 1, tmp);
                                    _refrescarAreaSiAuto();
                                  })
                              : null),
                      IconButton(
                          icon: const Icon(Icons.arrow_downward, size: 18),
                          onPressed: i < _puntos.length - 1
                              ? () => setState(() {
                                    final tmp = _puntos.removeAt(i);
                                    _puntos.insert(i + 1, tmp);
                                    _refrescarAreaSiAuto();
                                  })
                              : null),
                      IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.red, size: 18),
                          onPressed: () => setState(() {
                                _puntos.removeAt(i);
                                _refrescarAreaSiAuto();
                              })),
                    ]),
                  );
                })),
              ),
            ),
          const SizedBox(height: 12),

          // Preview del polígono
          if (_puntos.length >= 2) ...[
            const Text('Vista previa',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            SizedBox(
              height: 220,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: FlutterMap(
                  options: MapOptions(
                    initialCenter: _centroide(),
                    initialZoom: 17,
                    minZoom: 3,
                    maxZoom: 19,
                  ),
                  children: [
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.nexuscreatio.siembras',
                    ),
                    if (_puntos.length >= 3)
                      PolygonLayer(polygons: [
                        Polygon(
                          points: _puntos
                              .map((p) => LatLng(p.$1, p.$2))
                              .toList(),
                          color: Colors.green.withOpacity(0.25),
                          borderColor: Colors.green,
                          borderStrokeWidth: 2,
                        ),
                      ]),
                    MarkerLayer(
                      markers: [
                        for (int i = 0; i < _puntos.length; i++)
                          Marker(
                            point: LatLng(_puntos[i].$1, _puntos[i].$2),
                            width: 22,
                            height: 22,
                            child: Container(
                              alignment: Alignment.center,
                              decoration: const BoxDecoration(
                                  color: Colors.red, shape: BoxShape.circle),
                              child: Text('${i + 1}',
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold)),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          TextField(
            controller: _notas,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'Notas', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton(
                onPressed: _saving
                    ? null
                    : () => context.go('/predios/${widget.predioId}'),
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
    );
  }

  /// Calcula el área del polígono en m² usando proyección equirrectangular
  /// local (precisa para lotes < 1 km²; error < 0.1% para áreas típicas de
  /// finca). Retorna null si hay menos de 3 puntos.
  double? _areaPoligonoM2() {
    if (_puntos.length < 3) return null;
    final latMedia =
        _puntos.map((p) => p.$1).reduce((a, b) => a + b) / _puntos.length;
    final cosLat = math.cos(latMedia * math.pi / 180.0);
    const metrosPorGradoLat = 111320.0; // aprox constante
    // Proyecta cada punto (lat, lng) a (x, y) en metros.
    final xy = _puntos
        .map((p) =>
            (p.$2 * metrosPorGradoLat * cosLat, p.$1 * metrosPorGradoLat))
        .toList();
    // Fórmula del zapatero (Shoelace)
    var sum = 0.0;
    for (int i = 0; i < xy.length; i++) {
      final j = (i + 1) % xy.length;
      sum += xy[i].$1 * xy[j].$2 - xy[j].$1 * xy[i].$2;
    }
    return sum.abs() / 2.0;
  }

  /// Actualiza el campo _area si estamos en modo auto y hay ≥3 puntos.
  void _refrescarAreaSiAuto() {
    if (!_areaAutoCalc) return;
    final a = _areaPoligonoM2();
    if (a != null) {
      _area.text = a.toStringAsFixed(0);
    } else {
      _area.text = '';
    }
  }

  /// Texto informativo bajo el campo de área. Muestra el área calculada
  /// del polígono en m², hectáreas y cuadras (unidad universal Colombia).
  String? _areaHelperText() {
    if (_puntos.length < 3) {
      return 'Agrega al menos 3 puntos para calcular el área';
    }
    final a = _areaPoligonoM2();
    if (a == null) return null;
    final ha = a / 10000.0;
    final cuadras = a / 6400.0;
    final parts = <String>[];
    if (ha >= 0.01) parts.add('${ha.toStringAsFixed(2)} ha');
    if (cuadras >= 0.01) parts.add('${cuadras.toStringAsFixed(2)} cuadras');
    final extras = parts.isEmpty ? '' : ' · ${parts.join(" · ")}';
    return 'Polígono: ${a.toStringAsFixed(0)} m²$extras';
  }

  LatLng _centroide() {
    if (_puntos.isEmpty) return LatLng(4.473252, -75.698197);
    final avgLat =
        _puntos.map((p) => p.$1).reduce((a, b) => a + b) / _puntos.length;
    final avgLng =
        _puntos.map((p) => p.$2).reduce((a, b) => a + b) / _puntos.length;
    return LatLng(avgLat, avgLng);
  }

  void _addManual() {
    final lat = double.tryParse(_latIn.text.replaceAll(',', '.'));
    final lng = double.tryParse(_lngIn.text.replaceAll(',', '.'));
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Ingresa latitud y longitud numéricas válidas')));
      return;
    }
    setState(() {
      _puntos.add((lat, lng));
      _latIn.clear();
      _lngIn.clear();
      _refrescarAreaSiAuto();
    });
  }

  Future<void> _capturarGps() async {
    setState(() => _obteniendoGnss = true);
    try {
      final ok = await Geolocator.isLocationServiceEnabled();
      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Activa el servicio de ubicación del sistema')));
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Permiso de ubicación denegado')));
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 15),
      );
      if (!mounted) return;
      setState(() {
        _puntos.add((pos.latitude, pos.longitude));
        // Si la altitud del lote está vacía, la rellena con el primer punto
        // capturado por GPS (representa la altura general del lote).
        if (_altitud.text.isEmpty && !pos.altitude.isNaN) {
          _altitud.text = pos.altitude.toStringAsFixed(0);
        }
        _refrescarAreaSiAuto();
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Punto ${_puntos.length} capturado (precisión ±${pos.accuracy.toStringAsFixed(0)} m)')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No se pudo obtener GPS: $e')));
    } finally {
      if (mounted) setState(() => _obteniendoGnss = false);
    }
  }

  double? _d(TextEditingController c) {
    final v = c.text.trim();
    if (v.isEmpty) return null;
    return double.tryParse(v.replaceAll(',', '.'));
  }

  String? _s(TextEditingController c) {
    final v = c.text.trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _save() async {
    if (_nombre.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El nombre del lote es obligatorio')));
      return;
    }
    setState(() => _saving = true);
    try {
      final polygonJson = _puntos.isEmpty
          ? null
          : jsonEncode(_puntos.map((p) => [p.$1, p.$2]).toList());
      final mut = ref.read(dataMutationsProvider);
      if (widget.loteId == null) {
        await mut.addLote(
          predioId: widget.predioId,
          nombre: _nombre.text.trim(),
          administrador: _s(_admin),
          altitudMsnm: _d(_altitud),
          areaM2: _d(_area),
          poligonoGeoJson: polygonJson,
          notas: _s(_notas),
        );
      } else {
        await mut.updateLote(
          id: widget.loteId!,
          nombre: _nombre.text.trim(),
          administrador: _s(_admin),
          altitudMsnm: _d(_altitud),
          areaM2: _d(_area),
          poligonoGeoJson: polygonJson,
          notas: _s(_notas),
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.loteId == null
              ? 'Lote creado'
              : 'Lote actualizado')));
      context.go('/predios/${widget.predioId}');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error: $e')));
      setState(() => _saving = false);
    }
  }
}
