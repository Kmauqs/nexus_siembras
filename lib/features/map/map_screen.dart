import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../../core/theme/themes.dart';
import '../../core/widgets/app_shell.dart';
import '../../data/repositories/cultivo_repository.dart';
import '../../state/data_state.dart';
import '../pathologies/tratamientos_dialog.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  // Centro por defecto: Finca Villamariana (Calarcá, Quindío)
  static final _fincaDefault = LatLng(4.473252, -75.698197);

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

/// Modos de visualización disponibles para la capa base del mapa.
///
///  - [mapa]:          OpenStreetMap (calles y toponimia).
///  - [satelital]:     Esri World Imagery (imagen satelital).
///  - [catastroIgac]:  OSM + WMS del catastro IGAC + números catastrales
///                     (Colombia). Solo disponible para predios en CO.
enum _MapMode { mapa, satelital, catastroIgac }

/// Etiqueta catastral: centroide + número predial. Se rendere como
/// Marker sobre cada polígono del catastro IGAC.
class _PredioLabel {
  final LatLng centro;
  final String codigo;
  const _PredioLabel(this.centro, this.codigo);
}

class _MapScreenState extends ConsumerState<MapScreen> {
  /// Modo activo. Por defecto: mapa OSM (bajo consumo de datos).
  _MapMode _mode = _MapMode.mapa;

  // Fase 3e-6: capas de contenido (independientes del base map).
  bool _capaCultivosPredio = true;
  bool _capaTodosCultivos = false;
  bool _capaHeatmapPatologias = true;

  /// Habilita/deshabilita la opción "Catastro IGAC" en el menú.
  ///
  /// Actualmente en `false` porque el servicio de WMS del IGAC no cargó
  /// los polígonos prediales de forma consistente durante las pruebas.
  /// Todo el código (WMS + labels REST) queda intacto para poder reactivar
  /// esta capa en una fase futura cambiando esta bandera a `true`.
  static const bool _catastroIgacHabilitado = false;

  /// Controller para leer el bbox actual y disparar la consulta del REST
  /// API del IGAC (solo cuando el modo Catastro esté activo y el zoom
  /// permita mostrar labels de forma legible).
  final MapController _mapController = MapController();

  /// Etiquetas catastrales cargadas del REST API del IGAC.
  List<_PredioLabel> _catastroLabels = const [];

  /// Debouncer para no consultar el servidor en cada micro-movimiento.
  Timer? _labelFetchTimer;

  /// Bandera para mostrar un pequeño indicador mientras se cargan labels.
  bool _fetchingLabels = false;

  /// Zoom mínimo para mostrar los números catastrales (a menos zoom hay
  /// demasiados predios y el mapa se satura de texto).
  static const int _minZoomCatastroLabels = 15;

  /// Rotación actual del mapa (0° = norte arriba). Se actualiza en
  /// [onMapEvent] para orientar la brújula.
  double _rotacionMapa = 0;

  /// Posición GNSS más reciente del dispositivo (stream en tiempo real).
  Position? _posicionActual;

  /// Si true, el mapa sigue la posición GPS al recibir actualizaciones.
  bool _siguiendoUbicacion = false;

  /// Primera lectura del stream GPS en curso.
  bool _obteniendoGps = false;

  StreamSubscription<Position>? _gpsSub;

  static const _gpsSettings = LocationSettings(
    accuracy: LocationAccuracy.high,
    distanceFilter: 3,
  );

  @override
  void dispose() {
    _labelFetchTimer?.cancel();
    _gpsSub?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _actualizarRotacionMapa() {
    try {
      final r = _mapController.camera.rotation;
      if ((r - _rotacionMapa).abs() > 0.01) {
        setState(() => _rotacionMapa = r);
      }
    } catch (_) {}
  }

  void _orientarAlNorte() {
    try {
      _mapController.rotate(0);
      setState(() => _rotacionMapa = 0);
    } catch (_) {}
  }

  Future<bool> _asegurarPermisoGps() async {
    final servicioActivo = await Geolocator.isLocationServiceEnabled();
    if (!servicioActivo) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Activa el servicio de ubicación del sistema')));
      return false;
    }
    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Permiso de ubicación denegado')));
      return false;
    }
    return true;
  }

  Future<void> _activarUbicacionActual() async {
    if (!await _asegurarPermisoGps()) return;

    setState(() {
      _siguiendoUbicacion = true;
      _obteniendoGps = _posicionActual == null;
    });

    _gpsSub ??= Geolocator.getPositionStream(
      locationSettings: _gpsSettings,
    ).listen(
      _onActualizacionGps,
      onError: (Object e) {
        if (!mounted) return;
        setState(() {
          _obteniendoGps = false;
          _siguiendoUbicacion = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error GPS: $e')));
      },
    );

    if (_posicionActual != null) {
      _centrarEnPosicion(_posicionActual!);
    }
  }

  void _onActualizacionGps(Position pos) {
    if (!mounted) return;
    setState(() {
      _posicionActual = pos;
      _obteniendoGps = false;
    });
    if (_siguiendoUbicacion) {
      _centrarEnPosicion(pos);
    }
  }

  void _centrarEnPosicion(Position pos) {
    try {
      final zoom = _mapController.camera.zoom;
      _mapController.move(
        LatLng(pos.latitude, pos.longitude),
        zoom < 16 ? 16 : zoom,
      );
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final cultivos = ref.watch(cultivosActivosProvider);
    final plantas = ref.watch(plantasProvider);
    final plantasById = {for (final p in plantas) p.id: p};
    final lotes = ref.watch(lotesActivosProvider).maybeWhen(
        data: (l) => l, orElse: () => const []);

    // Parsea polígonos de lotes
    final polygons = <Polygon>[];
    final loteMarkers = <Marker>[];
    final allPolygonPoints = <LatLng>[];
    for (final l in lotes) {
      if (l.poligonoGeoJson == null) continue;
      final pts = <LatLng>[];
      try {
        final list = jsonDecode(l.poligonoGeoJson as String) as List<dynamic>;
        for (final item in list) {
          if (item is List && item.length >= 2) {
            pts.add(LatLng(
                (item[0] as num).toDouble(), (item[1] as num).toDouble()));
          }
        }
      } catch (_) {}
      if (pts.length < 3) continue;
      polygons.add(Polygon(
        points: pts,
        color: Colors.brown.withOpacity(0.15),
        borderColor: Colors.brown,
        borderStrokeWidth: 2,
      ));
      allPolygonPoints.addAll(pts);
      // Etiqueta del lote en el centroide del polígono
      final avgLat = pts.map((p) => p.latitude).reduce((a, b) => a + b) / pts.length;
      final avgLng = pts.map((p) => p.longitude).reduce((a, b) => a + b) / pts.length;
      loteMarkers.add(Marker(
        point: LatLng(avgLat, avgLng),
        width: 120,
        height: 22,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.brown.withOpacity(0.85),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(l.nombre as String,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold)),
        ),
      ));
    }
    // Determina centro basado en polígonos de lotes si existen, sino
    // en cultivos con coords, sino en la ubicación por defecto.
    LatLng centro = MapScreen._fincaDefault;
    if (allPolygonPoints.isNotEmpty) {
      final avgLat = allPolygonPoints.map((p) => p.latitude).reduce((a, b) => a + b) /
          allPolygonPoints.length;
      final avgLng = allPolygonPoints.map((p) => p.longitude).reduce((a, b) => a + b) /
          allPolygonPoints.length;
      centro = LatLng(avgLat, avgLng);
    } else {
      final withCoords = cultivos.where((c) => c.lat != null && c.lng != null).toList();
      if (withCoords.isNotEmpty) {
        final avgLat = withCoords.map((c) => c.lat!).reduce((a, b) => a + b) /
            withCoords.length;
        final avgLng = withCoords.map((c) => c.lng!).reduce((a, b) => a + b) /
            withCoords.length;
        centro = LatLng(avgLat, avgLng);
      }
    }

    // Marcadores: para cultivos con coordenadas, uno cada uno.
    // Fallback en cascada para cultivos sin GNSS:
    //   1. Centroide del lote asignado (si tiene polígono)
    //   2. Offset radial pequeño alrededor del centro (último recurso)
    final loteById = {for (final l in lotes) l.id as int: l};
    final markers = <Marker>[];
    if (!_capaCultivosPredio) {
      // Si la capa está desactivada, saltamos el llenado (dejamos vacío).
    }
    var offsetIdx = 0;
    for (final c in _capaCultivosPredio ? cultivos : const <Cultivo>[]) {
      final pl = plantasById[c.plantaId];
      final asyncEst = ref.watch(estadoCultivoProvider(c.id));
      final color = asyncEst.hasValue
          ? switch (asyncEst.value!.estado) {
              EstadoCultivo.verde   => AppThemes.colorOk,
              EstadoCultivo.naranja => AppThemes.colorWarn,
              EstadoCultivo.rojo    => AppThemes.colorAlert,
            }
          : Colors.grey;
      double lat, lng;
      if (c.lat != null && c.lng != null) {
        lat = c.lat!;
        lng = c.lng!;
      } else if (c.loteId != null &&
          centroideDeLote(loteById[c.loteId!]) != null) {
        final centro = centroideDeLote(loteById[c.loteId!])!;
        lat = centro.lat;
        lng = centro.lng;
      } else {
        // Último recurso: offset radial pequeño alrededor del centro (~30m).
        final angulo = (offsetIdx * 137.5) * 3.14159 / 180;
        lat = MapScreen._fincaDefault.latitude +
            0.00030 * (offsetIdx > 0 ? 1 : 0) * (angulo % 6.28) -
            0.00015;
        lng = MapScreen._fincaDefault.longitude +
            0.00030 * (offsetIdx > 0 ? 1 : 0) * (angulo % 6.28) -
            0.00015;
        offsetIdx++;
      }
      markers.add(Marker(
        point: LatLng(lat, lng),
        width: 44, height: 44,
        child: GestureDetector(
          onTap: () => _showInfo(context, c, pl?.nombre ?? '?',
              asyncEst.value?.nota ?? '—'),
          child: Container(
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white, width: 3),
              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
            ),
            child: Icon(
              asyncEst.hasValue && asyncEst.value!.estado == EstadoCultivo.rojo
                  ? Icons.local_florist : Icons.eco,
              color: Colors.white, size: 24,
            ),
          ),
        ),
      ));
    }

    // Fase 3e-6: capa "Todos mis cultivos" (marcadores azules, sin duplicar
    // con los del predio activo).
    final otrosCultivosMarkers = <Marker>[];
    if (_capaTodosCultivos) {
      final activePredioId = ref.watch(activePredioIdProvider);
      final todos = ref.watch(todosCultivosGeorreferenciadosProvider);
      for (final c in todos) {
        if (c.predioId == activePredioId) continue; // ya renderizado
        final pl = plantasById[c.plantaId];
        otrosCultivosMarkers.add(Marker(
          point: LatLng(c.lat!, c.lng!),
          width: 30,
          height: 30,
          child: GestureDetector(
            onTap: () => _showInfo(
                context, c, pl?.nombre ?? '?', '(cultivo de otro predio)'),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.blue.shade600,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
              ),
              child: const Icon(Icons.eco, color: Colors.white, size: 16),
            ),
          ),
        ));
      }
    }

    // Fase 3e-6: capa heatmap patologías (círculos naranja/rojo).
    final heatmapCircles = <CircleMarker>[];
    final heatmapPuntos = _capaHeatmapPatologias
        ? ref.watch(heatmapPatologiasProvider)
        : const <PuntoPatologia>[];
    for (final p in heatmapPuntos) {
      final avanzada = p.severidad == 'avanzada';
      heatmapCircles.add(CircleMarker(
        point: LatLng(p.lat, p.lng),
        radius: avanzada ? 50 : 35,
        useRadiusInMeter: true,
        color: (avanzada ? Colors.red : Colors.orange).withOpacity(0.28),
        borderColor:
            (avanzada ? Colors.red : Colors.orange).withOpacity(0.55),
        borderStrokeWidth: 1,
      ));
    }

    final sinContenido = cultivos.isEmpty &&
        polygons.isEmpty &&
        otrosCultivosMarkers.isEmpty &&
        heatmapCircles.isEmpty;

    return AppShell(
      title: 'Mapa',
      child: Column(
        children: [
          Expanded(
            child: _buildMapStack(
              context,
              centro,
              polygons,
              loteMarkers,
              markers,
              otrosCultivosMarkers,
              heatmapCircles,
              heatmapPuntos,
              sinContenido: sinContenido,
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            color: Theme.of(context).colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Leyenda',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                Wrap(spacing: 12, runSpacing: 4, children: [
                  _LegendDot(color: AppThemes.colorOk, label: 'Sin alertas'),
                  _LegendDot(color: AppThemes.colorWarn, label: 'Atención'),
                  _LegendDot(color: AppThemes.colorAlert, label: 'Crítico'),
                  if (_capaTodosCultivos)
                    _LegendDot(
                        color: Colors.blue.shade600, label: 'Otros predios'),
                  if (_capaHeatmapPatologias)
                    _LegendDot(
                        color: Colors.orange.withOpacity(0.7),
                        label: '🐛 Patologías'),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                            color: Colors.brown.withOpacity(0.3),
                            border:
                                Border.all(color: Colors.brown, width: 1))),
                    const SizedBox(width: 4),
                    const Text('Lote', style: TextStyle(fontSize: 12)),
                  ]),
                ]),
                const SizedBox(height: 4),
                Text(_atribucion(),
                    style: TextStyle(
                        fontSize: 10, color: Theme.of(context).hintColor)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Construye el Stack del mapa con la capa base según [_mode], el overlay
  /// del catastro IGAC cuando aplica, y el botón de toggle de capa.
  Widget _buildMapStack(
    BuildContext context,
    LatLng centro,
    List<Polygon> polygons,
    List<Marker> loteMarkers,
    List<Marker> markers,
    List<Marker> otrosCultivosMarkers,
    List<CircleMarker> heatmapCircles,
    List<PuntoPatologia> heatmapPuntos, {
    bool sinContenido = false,
  }) {
    // Detección de país del predio activo para habilitar la capa catastral
    // del IGAC (Colombia). Diseñado como extensible: en el futuro se podrán
    // añadir capas equivalentes para otros países consultando `iso`.
    final iso = ref.watch(predioActivoIsoProvider).maybeWhen(
        data: (i) => i, orElse: () => null);
    final catastroDisponible = _catastroIgacHabilitado && iso == 'CO';

    // Si el modo actual era Catastro IGAC y el nuevo predio no es Colombia,
    // revierte silenciosamente a satélite para evitar overlays inválidos.
    if (_mode == _MapMode.catastroIgac && !catastroDisponible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _mode = _MapMode.satelital);
      });
    }

    // Solo el modo satelital "puro" usa Esri. El modo Catastro IGAC usa
    // OSM como base (mayor legibilidad de los números catastrales sobre
    // fondo claro + menor consumo de datos).
    final esSatelite = _mode == _MapMode.satelital;

    return Stack(children: [
      FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: centro,
          initialZoom: 16,
          minZoom: 3,
          maxZoom: esSatelite ? 19 : 19,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all,
          ),
          onMapEvent: (evt) {
            if (evt is MapEventRotate ||
                evt is MapEventMoveEnd ||
                evt is MapEventFlingAnimationEnd) {
              _actualizarRotacionMapa();
            }
            // Al mover el mapa manualmente, dejar de seguir el GPS.
            if (_siguiendoUbicacion &&
                evt is MapEventMove &&
                evt.source == MapEventSource.onDrag) {
              setState(() => _siguiendoUbicacion = false);
            }
            // Refresca labels catastrales al terminar cualquier gesto de
            // movimiento (pan o zoom por rueda/gesto). MapEventMoveEnd
            // se emite tras Move, Fling y DoubleTapZoom.
            if (_mode == _MapMode.catastroIgac && evt is MapEventMoveEnd) {
              _scheduleFetchCatastroLabels();
            }
          },
          onMapReady: () {
            _actualizarRotacionMapa();
            if (_mode == _MapMode.catastroIgac) {
              _scheduleFetchCatastroLabels();
            }
          },
          // Fase 3e-7: tap sobre el mapa → detecta puntos del heatmap
          // dentro de un radio de ~120m y abre bottom sheet con los reportes.
          onTap: (tapPos, latlng) {
            if (!_capaHeatmapPatologias || heatmapPuntos.isEmpty) return;
            _abrirDetalleZona(context, latlng, heatmapPuntos);
          },
        ),
        children: [
          // Capa base: OSM tanto para modo Mapa como para Catastro.
          TileLayer(
            urlTemplate: esSatelite
                ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.nexuscreatio.siembras',
            maxNativeZoom: 19,
          ),
          // Overlay Catastro IGAC (Colombia) — WMS público, sin API key.
          // Servicio: "Dato Fundamental Catastro" (ArcGIS Server del IGAC).
          //
          // ── Sistema de referencia (CRS) ──
          // El servidor SOLO acepta las siguientes proyecciones:
          //   • CRS:84      (WGS84 lon/lat)
          //   • EPSG:4326   (WGS84 lat/lon)
          //   • EPSG:4686   (MAGNA-SIRGAS, oficial Colombia)
          // ¡NO soporta EPSG:3857 (Web Mercator)! Si le pedimos tiles en
          // 3857, responde con XML de error que flutter_map interpreta
          // como "Invalid image data". Por eso pasamos `crs: Epsg4326`
          // explícitamente: flutter_map convierte las peticiones al vuelo.
          //
          // ── Capas ──
          // En este WMS los `Name` son IDs numéricos, no los títulos:
          //   0 → U_TERRENO        (predios urbanos)
          //   1 → U_MANZANA        (manzanas urbanas)
          //   2 → U_CONSTRUCCION   (construcciones urbanas)
          //   3 → R_TERRENO        (predios rurales) ← foco pequeño productor
          //   4 → R_CONSTRUCCION   (construcciones rurales)
          //
          // Nota: solo municipios en jurisdicción IGAC. Grandes gestores
          // catastrales (UAECD Bogotá, Cali, Medellín, Barranquilla) no
          // publican por este endpoint — quedan para fase futura (#21).
          if (_mode == _MapMode.catastroIgac)
            TileLayer(
              wmsOptions: WMSTileLayerOptions(
                baseUrl:
                    'https://mapas.igac.gov.co/server/services/Dato_Fundamental_Catastro/MapServer/WMSServer?',
                layers: const ['3', '0', '1'],
                format: 'image/png',
                transparent: true,
                version: '1.3.0',
                crs: const Epsg4326(),
              ),
              userAgentPackageName: 'com.nexuscreatio.siembras',
            ),
          // Números catastrales (CODIGO) sobre el centroide de cada predio.
          // Consultados dinámicamente al REST API del IGAC en el bbox visible.
          if (_mode == _MapMode.catastroIgac && _catastroLabels.isNotEmpty)
            MarkerLayer(
              markers: _catastroLabels
                  .map((l) => Marker(
                        point: l.centro,
                        width: 90,
                        height: 20,
                        child: Container(
                          alignment: Alignment.center,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(3),
                            border: Border.all(
                                color: Colors.brown.shade700, width: 0.5),
                          ),
                          child: Text(
                            l.codigo,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.brown.shade900,
                            ),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          if (polygons.isNotEmpty) PolygonLayer(polygons: polygons),
          if (loteMarkers.isNotEmpty) MarkerLayer(markers: loteMarkers),
          // Heatmap primero (debajo de los marcadores)
          if (heatmapCircles.isNotEmpty)
            CircleLayer(circles: heatmapCircles),
          // Cultivos de otros predios (azul, tamaño pequeño)
          if (otrosCultivosMarkers.isNotEmpty)
            MarkerLayer(markers: otrosCultivosMarkers),
          // Cultivos del predio activo (encima de todo)
          MarkerLayer(markers: markers),
          // Ubicación GPS del dispositivo (tiempo real)
          if (_posicionActual != null) ...[
            CircleLayer(circles: [
              CircleMarker(
                point: LatLng(
                    _posicionActual!.latitude, _posicionActual!.longitude),
                radius: _posicionActual!.accuracy.clamp(5, 80),
                useRadiusInMeter: false,
                color: Colors.blue.withOpacity(0.15),
                borderColor: Colors.blue.withOpacity(0.35),
                borderStrokeWidth: 1,
              ),
            ]),
            MarkerLayer(markers: [
              Marker(
                point: LatLng(
                    _posicionActual!.latitude, _posicionActual!.longitude),
                width: 28,
                height: 28,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.shade600,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.person_pin_circle,
                      color: Colors.white, size: 16),
                ),
              ),
            ]),
          ],
        ],
      ),
      // Aviso cuando no hay cultivos/lotes (el mapa sigue usable con GPS).
      if (sinContenido)
        Positioned(
          top: 12,
          left: 12,
          right: 130,
          child: Material(
            color: Colors.black.withOpacity(0.65),
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                'Sin cultivos ni lotes registrados.\n'
                'Usa el botón de ubicación para ver dónde estás.',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ),
      // Hint: acerca el mapa para ver los números catastrales.
      if (_mode == _MapMode.catastroIgac &&
          !_fetchingLabels &&
          _catastroLabels.isEmpty)
        Positioned(
          top: 12,
          left: 130,
          child: Material(
            color: Colors.black.withOpacity(0.65),
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.zoom_in, color: Colors.white, size: 14),
                SizedBox(width: 4),
                Text('Acerca para ver números',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ]),
            ),
          ),
        ),
      // Indicador de carga de labels catastrales
      if (_mode == _MapMode.catastroIgac && _fetchingLabels)
        Positioned(
          top: 12,
          left: 130,
          child: Material(
            color: Colors.black.withOpacity(0.7),
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 6),
                Text('Cargando catastro…',
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ]),
            ),
          ),
        ),
      // Selector de capa (menú desplegable)
      Positioned(
        top: 12,
        right: 12,
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: PopupMenuButton<_MapMode>(
            tooltip: 'Cambiar capa del mapa',
            initialValue: _mode,
            onSelected: (m) {
              setState(() {
                _mode = m;
                if (m != _MapMode.catastroIgac) {
                  _catastroLabels = const [];
                }
              });
              if (m == _MapMode.catastroIgac) {
                _scheduleFetchCatastroLabels();
              }
            },
            offset: const Offset(0, 44),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8)),
            itemBuilder: (ctx) => [
              _menuItem(
                mode: _MapMode.mapa,
                icon: Icons.map_outlined,
                titulo: 'Mapa',
                subtitulo: 'OpenStreetMap · calles',
              ),
              _menuItem(
                mode: _MapMode.satelital,
                icon: Icons.satellite_alt,
                titulo: 'Satélite',
                subtitulo: 'Esri World Imagery',
              ),
              // Catastro IGAC: opción oculta hasta reactivar en fase futura.
              if (_catastroIgacHabilitado)
                _menuItem(
                  mode: _MapMode.catastroIgac,
                  icon: Icons.account_balance,
                  titulo: 'Catastro IGAC',
                  subtitulo: catastroDisponible
                      ? 'Predios y números catastrales'
                      : 'Solo disponible en Colombia',
                  enabled: catastroDisponible,
                ),
            ],
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_iconoModoActivo(), size: 18),
                const SizedBox(width: 6),
                Text(_nombreModoActivo(),
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 2),
                const Icon(Icons.arrow_drop_down, size: 20),
              ]),
            ),
          ),
        ),
      ),
      // Chip indicador del modo activo (esquina superior izquierda)
      if (_mode != _MapMode.mapa)
        Positioned(
          top: 12,
          left: 12,
          child: Material(
            color: _mode == _MapMode.catastroIgac
                ? Colors.orange.shade700
                : Colors.blue.shade700,
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                  _mode == _MapMode.catastroIgac
                      ? '🏛️ Catastro IGAC'
                      : '🛰️ Satélite',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold)),
            ),
          ),
        ),
      // Brújula: muestra el norte y al tocar reorienta el mapa.
      Positioned(
        left: 12,
        bottom: 132,
        child: _MapCompass(
          rotacionGrados: _rotacionMapa,
          onTap: _orientarAlNorte,
        ),
      ),
      // Ubicación GPS en tiempo real del dispositivo.
      Positioned(
        right: 12,
        bottom: 132,
        child: Material(
          color: _siguiendoUbicacion
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surface,
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: _activarUbicacionActual,
            borderRadius: BorderRadius.circular(8),
            child: Tooltip(
              message: _siguiendoUbicacion
                  ? 'Siguiendo tu ubicación (mueve el mapa para detener)'
                  : 'Centrar en mi ubicación GPS en tiempo real',
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: _obteniendoGps
                    ? SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      )
                    : Icon(
                        _siguiendoUbicacion
                            ? Icons.my_location
                            : Icons.location_searching,
                        size: 22,
                        color: _siguiendoUbicacion
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.onSurface,
                      ),
              ),
            ),
          ),
        ),
      ),
      // Panel de capas de contenido (Fase 3e-6). Esquina inferior derecha.
      Positioned(
        right: 12,
        bottom: 12,
        child: Material(
          color: Theme.of(context).colorScheme.surface.withOpacity(0.95),
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding:
                      EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  child: Text('Capas',
                      style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.bold)),
                ),
                _capaCheckbox(
                  color: AppThemes.colorOk,
                  icon: Icons.eco,
                  label: 'Cultivos del predio',
                  value: _capaCultivosPredio,
                  onChanged: (v) =>
                      setState(() => _capaCultivosPredio = v ?? true),
                ),
                _capaCheckbox(
                  color: Colors.blue.shade600,
                  icon: Icons.grid_view,
                  label: 'Todos mis cultivos',
                  value: _capaTodosCultivos,
                  onChanged: (v) =>
                      setState(() => _capaTodosCultivos = v ?? false),
                ),
                _capaCheckbox(
                  color: Colors.orange,
                  icon: Icons.bug_report,
                  label: 'Heatmap patologías',
                  value: _capaHeatmapPatologias,
                  onChanged: (v) =>
                      setState(() => _capaHeatmapPatologias = v ?? true),
                ),
              ],
            ),
          ),
        ),
      ),
    ]);
  }

  /// Fila de checkbox compacta para el panel de capas.
  Widget _capaCheckbox({
    required Color color,
    required IconData icon,
    required String label,
    required bool value,
    required ValueChanged<bool?> onChanged,
  }) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 20,
            height: 20,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ]),
      ),
    );
  }

  /// Ícono del modo actualmente activo (mostrado en el botón).
  IconData _iconoModoActivo() {
    switch (_mode) {
      case _MapMode.mapa:
        return Icons.map_outlined;
      case _MapMode.satelital:
        return Icons.satellite_alt;
      case _MapMode.catastroIgac:
        return Icons.account_balance;
    }
  }

  /// Nombre corto del modo activo (mostrado en el botón).
  String _nombreModoActivo() {
    switch (_mode) {
      case _MapMode.mapa:
        return 'Mapa';
      case _MapMode.satelital:
        return 'Satélite';
      case _MapMode.catastroIgac:
        return 'Catastro';
    }
  }

  /// Construye una entrada del menú desplegable. Marca la activa con ✓.
  PopupMenuItem<_MapMode> _menuItem({
    required _MapMode mode,
    required IconData icon,
    required String titulo,
    required String subtitulo,
    bool enabled = true,
  }) {
    final isActive = _mode == mode;
    return PopupMenuItem<_MapMode>(
      value: mode,
      enabled: enabled,
      child: Row(children: [
        Icon(icon,
            size: 20,
            color: !enabled
                ? Colors.grey
                : isActive
                    ? Colors.green
                    : null),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(titulo,
                  style: TextStyle(
                      fontWeight: isActive
                          ? FontWeight.bold
                          : FontWeight.normal,
                      color: !enabled ? Colors.grey : null)),
              Text(subtitulo,
                  style: TextStyle(
                      fontSize: 11,
                      color: !enabled ? Colors.grey : Colors.grey.shade600)),
            ],
          ),
        ),
        if (isActive)
          const Padding(
            padding: EdgeInsets.only(left: 8),
            child: Icon(Icons.check, color: Colors.green, size: 18),
          ),
      ]),
    );
  }

  String _atribucion() {
    switch (_mode) {
      case _MapMode.mapa:
        return 'Tiles: © OpenStreetMap contributors';
      case _MapMode.satelital:
        return 'Tiles: Esri, Maxar, Earthstar Geographics — World Imagery';
      case _MapMode.catastroIgac:
        return 'Base: © OpenStreetMap contributors · Catastro © IGAC / ICDE (Colombia)';
    }
  }

  /// Programa un fetch con debounce (400 ms) para no bombardear el servidor
  /// mientras el usuario está haciendo pan/zoom.
  void _scheduleFetchCatastroLabels() {
    _labelFetchTimer?.cancel();
    _labelFetchTimer =
        Timer(const Duration(milliseconds: 400), _fetchCatastroLabels);
  }

  /// Consulta el REST API del IGAC (Query en capas 3=R_TERRENO y 0=U_TERRENO)
  /// para el bbox actual del mapa. Devuelve polígonos con CODIGO (número
  /// predial), calcula el centroide de cada uno y guarda la lista.
  ///
  /// - Solo consulta si el zoom >= [_minZoomCatastroLabels] (evita traer
  ///   miles de features al ver el país completo).
  /// - Máximo 500 resultados por consulta (2 capas × 250).
  /// - Devuelve GeoJSON gracias al parámetro `f=geojson` de ArcGIS 10.5+.
  Future<void> _fetchCatastroLabels() async {
    if (!mounted || _mode != _MapMode.catastroIgac) return;
    MapCamera camera;
    try {
      camera = _mapController.camera;
    } catch (_) {
      // El mapa aún no está listo; reintenta cuando lo esté.
      return;
    }
    if (camera.zoom < _minZoomCatastroLabels) {
      // Alto nivel: limpia labels y muestra hint.
      if (_catastroLabels.isNotEmpty) {
        setState(() => _catastroLabels = const []);
      }
      return;
    }
    final bounds = camera.visibleBounds;
    setState(() => _fetchingLabels = true);

    Future<List<_PredioLabel>> queryLayer(int layerId) async {
      final uri = Uri.https(
        'mapas.igac.gov.co',
        '/server/rest/services/Dato_Fundamental_Catastro/MapServer/$layerId/query',
        {
          'where': '1=1',
          'geometry':
              '${bounds.west},${bounds.south},${bounds.east},${bounds.north}',
          'geometryType': 'esriGeometryEnvelope',
          'inSR': '4326',
          'spatialRel': 'esriSpatialRelIntersects',
          'outFields': 'CODIGO',
          'returnGeometry': 'true',
          'outSR': '4326',
          'f': 'geojson',
          'resultRecordCount': '250',
        },
      );
      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 10);
      try {
        final req = await client.getUrl(uri);
        req.headers.set('User-Agent', 'com.nexuscreatio.siembras');
        final resp = await req.close();
        if (resp.statusCode != 200) return const [];
        final body = await resp.transform(utf8.decoder).join();
        final data = jsonDecode(body) as Map<String, dynamic>;
        final feats = (data['features'] as List<dynamic>?) ?? const [];
        return feats
            .map((f) => _featureToLabel(f as Map<String, dynamic>))
            .whereType<_PredioLabel>()
            .toList();
      } catch (_) {
        return const [];
      } finally {
        client.close();
      }
    }

    // Consulta R_TERRENO (rural) + U_TERRENO (urbano) en paralelo.
    final results = await Future.wait([queryLayer(3), queryLayer(0)]);
    if (!mounted || _mode != _MapMode.catastroIgac) return;
    setState(() {
      _catastroLabels = [...results[0], ...results[1]];
      _fetchingLabels = false;
    });
  }

  /// Convierte un GeoJSON feature del ArcGIS Server IGAC a un [_PredioLabel]:
  /// extrae el CODIGO de las propiedades y calcula el centroide del anillo
  /// exterior del polígono (soporta Polygon y MultiPolygon).
  static _PredioLabel? _featureToLabel(Map<String, dynamic> feat) {
    final props = feat['properties'] as Map<String, dynamic>?;
    final geom = feat['geometry'] as Map<String, dynamic>?;
    if (props == null || geom == null) return null;
    final codigo = props['CODIGO'] as String?;
    if (codigo == null || codigo.trim().isEmpty) return null;
    final coords = geom['coordinates'] as List<dynamic>?;
    final tipo = geom['type'] as String?;
    if (coords == null || coords.isEmpty) return null;
    List<dynamic>? ring;
    if (tipo == 'Polygon') {
      ring = coords[0] as List<dynamic>?;
    } else if (tipo == 'MultiPolygon' && coords.first is List) {
      final first = coords.first as List<dynamic>;
      if (first.isNotEmpty) ring = first[0] as List<dynamic>?;
    }
    if (ring == null || ring.isEmpty) return null;
    double sumLat = 0, sumLng = 0;
    int n = 0;
    for (final p in ring) {
      if (p is List && p.length >= 2) {
        sumLng += (p[0] as num).toDouble();
        sumLat += (p[1] as num).toDouble();
        n++;
      }
    }
    if (n == 0) return null;
    // Muestra el CODIGO acortado: los últimos 6 dígitos suelen ser el
    // número de terreno (los primeros 24 son departamento+municipio+vereda).
    final display = codigo.length > 6
        ? codigo.substring(codigo.length - 6)
        : codigo;
    return _PredioLabel(LatLng(sumLat / n, sumLng / n), display);
  }

  /// Fase 3e-7: al tocar el mapa, busca puntos del heatmap dentro de
  /// [radioMetros] y, si hay al menos uno, abre un bottom sheet con la
  /// lista ordenada por proximidad al tap.
  void _abrirDetalleZona(
    BuildContext ctx,
    LatLng tap,
    List<PuntoPatologia> puntos, {
    double radioMetros = 120,
  }) {
    const distancia = Distance();
    final cercanos = <_PuntoConDistancia>[];
    for (final p in puntos) {
      final metros = distancia.as(
          LengthUnit.Meter, tap, LatLng(p.lat, p.lng));
      if (metros <= radioMetros) {
        cercanos.add(_PuntoConDistancia(punto: p, metros: metros));
      }
    }
    if (cercanos.isEmpty) return; // Silencioso: click en zona vacía.
    cercanos.sort((a, b) => a.metros.compareTo(b.metros));
    showModalBottomSheet<void>(
      context: ctx,
      isScrollControlled: true,
      builder: (_) => _DetalleZonaHeatmap(
        tap: tap,
        radioMetros: radioMetros,
        cercanos: cercanos,
        onCentrarEnPunto: (latlng) {
          Navigator.pop(ctx);
          try {
            final zoom = _mapController.camera.zoom;
            _mapController.move(latlng, zoom < 17 ? 17 : zoom);
          } catch (_) {}
        },
      ),
    );
  }

  static void _showInfo(BuildContext ctx, Cultivo c, String plantaNombre, String nota) {
    showModalBottomSheet<void>(
      context: ctx,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(plantaNombre,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text('Lote: ${c.lote}'),
            Text('Sembrado: ${c.sembrado}'),
            if (c.lat != null && c.lng != null)
              Text('Coordenadas: ${c.lat!.toStringAsFixed(4)}, ${c.lng!.toStringAsFixed(4)}')
            else
              Text('Sin coordenadas exactas',
                  style: TextStyle(color: Theme.of(ctx).hintColor)),
            const SizedBox(height: 8),
            Text(nota, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});
  final Color color;
  final String label;
  @override
  Widget build(BuildContext c) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          Text(label, style: const TextStyle(fontSize: 12)),
        ],
      );
}

/// Brújula flotante: la aguja apunta al norte geográfico según la
/// rotación del mapa; al tocar, reorienta con el norte arriba.
class _MapCompass extends StatelessWidget {
  const _MapCompass({
    required this.rotacionGrados,
    required this.onTap,
  });

  final double rotacionGrados;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final desalineado = rotacionGrados.abs() > 0.5;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 4,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: Tooltip(
          message: 'Orientar al norte',
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Transform.rotate(
              angle: -rotacionGrados * math.pi / 180,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.navigation,
                    size: 22,
                    color: desalineado
                        ? Colors.red.shade700
                        : Colors.grey.shade600,
                  ),
                  Text(
                    'N',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: desalineado
                          ? Colors.red.shade700
                          : Colors.grey.shade700,
                      height: 1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Fase 3e-7 — Detalle de zonas calientes del heatmap
// ============================================================

class _PuntoConDistancia {
  final PuntoPatologia punto;
  final double metros;
  const _PuntoConDistancia({required this.punto, required this.metros});
}

/// Bottom sheet que muestra la lista de reportes de patologías dentro
/// del radio de tap en el mapa. Ordenados por proximidad.
class _DetalleZonaHeatmap extends StatelessWidget {
  const _DetalleZonaHeatmap({
    required this.tap,
    required this.radioMetros,
    required this.cercanos,
    required this.onCentrarEnPunto,
  });
  final LatLng tap;
  final double radioMetros;
  final List<_PuntoConDistancia> cercanos;
  final void Function(LatLng) onCentrarEnPunto;

  @override
  Widget build(BuildContext context) {
    final avanzadas =
        cercanos.where((c) => c.punto.severidad == 'avanzada').length;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      expand: false,
      builder: (ctx, scroll) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.bug_report, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        '${cercanos.length} reporte'
                        '${cercanos.length == 1 ? "" : "s"} en esta zona',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(
                        'Radio: ${radioMetros.toStringAsFixed(0)} m'
                        '${avanzadas > 0 ? " · $avanzadas avanzadas" : ""}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(ctx).hintColor)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(ctx),
              ),
            ]),
            const Divider(),
            Expanded(
              child: ListView.separated(
                controller: scroll,
                itemCount: cercanos.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) => _ReporteRow(
                  item: cercanos[i],
                  onCentrar: () => onCentrarEnPunto(
                      LatLng(cercanos[i].punto.lat, cercanos[i].punto.lng)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReporteRow extends StatelessWidget {
  const _ReporteRow({required this.item, required this.onCentrar});
  final _PuntoConDistancia item;
  final VoidCallback onCentrar;

  @override
  Widget build(BuildContext context) {
    final p = item.punto;
    final avanzada = p.severidad == 'avanzada';
    final colorSev = avanzada ? Colors.red.shade700 : Colors.orange.shade700;
    final fotoPath = p.fotoPath;
    final tieneFoto = fotoPath != null && fotoPath.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (tieneFoto)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.file(
              File(fotoPath),
              width: 52,
              height: 52,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                  width: 52,
                  height: 52,
                  color: Colors.grey.shade200,
                  child: const Icon(Icons.broken_image)),
            ),
          )
        else
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colorSev.withOpacity(0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(Icons.bug_report, color: colorSev, size: 28),
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p.patologiaNombre,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
              const SizedBox(height: 2),
              Wrap(spacing: 6, runSpacing: 4, children: [
                _tag(
                  icon: Icons.circle,
                  label: p.severidad.isEmpty ? '—' : p.severidad,
                  color: colorSev,
                ),
                _tag(
                  icon: Icons.calendar_today,
                  label:
                      '${p.fecha.year}-${p.fecha.month.toString().padLeft(2, "0")}-${p.fecha.day.toString().padLeft(2, "0")}',
                ),
                _tag(
                  icon: Icons.straighten,
                  label: '${item.metros.toStringAsFixed(0)} m',
                ),
                if (p.comunitario)
                  _tag(
                      icon: Icons.public,
                      label: 'comunidad',
                      color: Colors.green.shade700),
              ]),
              if (p.plantaNombre != null && p.plantaNombre!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('🌱 ${p.plantaNombre}',
                      style: const TextStyle(fontSize: 11)),
                ),
              if ((p.notas ?? '').isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text('📝 ${p.notas}',
                      style: const TextStyle(
                          fontSize: 11, fontStyle: FontStyle.italic),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          if (p.patologiaId != null)
            IconButton(
              icon: Icon(Icons.medical_services_outlined,
                  color: Colors.green.shade700),
              tooltip: 'Tratamientos recomendados',
              onPressed: () => showTratamientosDialog(
                  context, p.patologiaId!, p.patologiaNombre),
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            icon: const Icon(Icons.gps_fixed),
            tooltip: 'Centrar en el mapa',
            onPressed: onCentrar,
            visualDensity: VisualDensity.compact,
          ),
        ]),
      ]),
    );
  }

  Widget _tag({required IconData icon, required String label, Color? color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (color ?? Colors.grey).withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 10, color: color ?? Colors.grey.shade800),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(
                fontSize: 10,
                color: color ?? Colors.grey.shade800,
                fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
