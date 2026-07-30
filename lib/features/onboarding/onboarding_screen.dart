// Pantalla de primera ejecución — captura preferencias + datos del predio.
// Se muestra automáticamente cuando `primeraEjecucionProvider` es true.
// Al completar: crea el predio inicial, guarda las preferencias, marca
// `primera_ejecucion = false` y activa la app.

import 'dart:async' show TimeoutException, unawaited;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/log.dart';
import '../../core/theme/themes.dart';
import '../../services/eppo_client.dart';
import '../../services/geocoding_service.dart';
import '../../state/app_state.dart';
import '../../state/auth_state.dart';
import '../../state/data_state.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  int _step = 0;

  // Preferencias
  String _idioma = 'es';
  String _estilo = 'material';
  String _unidades = 'SI';
  String _moneda = 'COP';

  // Predio
  final _nombrePredio = TextEditingController();
  final _propietario = TextEditingController();
  int? _paisId;
  int? _regionId;
  int? _municipioId;
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _alt = TextEditingController();
  bool _obtainingGnss = false;
  // Detección país/región/municipio desde coordenadas (mejora 2026-07-19).
  bool _geoDetectando = false;
  String? _geoDetectMsg;
  bool _geoDetectOk = false;

  // Permisos — activados por defecto para que el usuario los conceda
  // al presionar "Siguiente" (se pedirán al SO en ese momento).
  bool _permCam = true;
  bool _permLoc = true;
  bool _permFiles = true;
  bool _permisosSolicitados = false;

  // Token EPPO Global Database (Fase 3f-1) — opcional.
  final _eppoToken = TextEditingController();
  bool _eppoObscure = true;
  // Health check del API EPPO (GET /status) — mejora 2026-07-19.
  bool _eppoHealthEnCurso = false;
  bool _eppoHealthOk = false;
  String? _eppoHealthMsg;

  // Consentimiento comunitario (Fase 3e) — opt-out por defecto activo
  bool _consentimientoPatologias = true;

  // Fase 3e: opt-in para trabajar solo sobre predios compartidos (sin
  // crear predio propio en el onboarding).
  bool _sinPredioPropio = false;

  // Paso Iniciar sesión (dentro del onboarding)
  final _emailAuth = TextEditingController();
  final _passwordAuth = TextEditingController();
  bool _authEsRegistro = false;
  bool _authProcesando = false;
  String? _authMensaje;
  bool _authExito = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header con logo NC
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              width: double.infinity,
              decoration: BoxDecoration(color: AppThemes.colorOk),
              child: const Column(children: [
                Text('🌱',
                    style: TextStyle(fontSize: 40, color: Colors.white)),
                Text('NEXUS Siembras',
                    style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text('Control agropecuario',
                    style: TextStyle(color: Colors.white70, fontSize: 13)),
              ]),
            ),
            // Indicador de paso
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(7, (i) {
                  final active = i <= _step;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: active ? 20 : 8, height: 8,
                    decoration: BoxDecoration(
                      color: active
                          ? AppThemes.colorOk : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
            Expanded(child: _buildStep()),
            // Botones navegación
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: () => setState(() => _step = _anteriorPaso(_step)),
                      child: const Text('Anterior'),
                    )
                  else
                    const SizedBox(width: 100),
                  if (_step == 3)
                    TextButton(
                      onPressed: () => setState(() => _step = 4),
                      child: const Text('Omitir'),
                    ),
                  FilledButton(
                    onPressed: _step < 6 ? _next : _finish,
                    child: Text(_step < 6 ? 'Siguiente' : 'Comenzar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0: return _stepIniciarSesion();
      case 1: return _stepPreferencias();
      case 2: return _stepPredio();
      case 3: return _stepUbicacion();
      case 4: return _stepPermisos();
      case 5: return _stepEppoToken();
      case 6: return _stepConsentimiento();
      default: return const SizedBox.shrink();
    }
  }

  Widget _stepPreferencias() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Preferencias',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Estas opciones se pueden cambiar después en Configuración.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          const Text('Idioma', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'es', label: Text('Español')),
              ButtonSegment(value: 'en', label: Text('English')),
              ButtonSegment(value: 'pt', label: Text('Português')),
            ],
            selected: {_idioma},
            onSelectionChanged: (s) => setState(() => _idioma = s.first),
          ),
          const SizedBox(height: 20),
          const Text('Estilo de interfaz', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'material',
                  label: Text('Material'), icon: Icon(Icons.design_services)),
              ButtonSegment(value: 'accesible',
                  label: Text('Accesible'), icon: Icon(Icons.accessibility)),
            ],
            selected: {_estilo},
            onSelectionChanged: (s) => setState(() => _estilo = s.first),
          ),
          const SizedBox(height: 20),
          const Text('Sistema de unidades',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _unidades,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'SI',       child: Text('Internacional (SI)', overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'imperial', child: Text('Imperial', overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'tecnico',  child: Text('Técnico (kgf)', overflow: TextOverflow.ellipsis)),
              DropdownMenuItem(value: 'cgs',      child: Text('Cegesimal (cgs)', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _unidades = v ?? 'SI'),
          ),
          const SizedBox(height: 12),
          const Text('Moneda', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          DropdownButtonFormField<String>(
            value: _moneda,
            isExpanded: true,
            decoration: const InputDecoration(border: OutlineInputBorder()),
            items: kSupportedCurrencies
                .map((c) => DropdownMenuItem(
                      value: c.code,
                      child: Text(c.label, overflow: TextOverflow.ellipsis),
                    ))
                .toList(),
            onChanged: (v) => setState(() => _moneda = v ?? 'COP'),
          ),
        ],
      );

  Widget _stepPredio() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Datos del predio',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text('Información básica de tu predio inicial. Podrás agregar más predios después.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          // Card informativa para cuentas colaboradoras
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: const [
                    Icon(Icons.people, color: Colors.blue, size: 20),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          '¿Vas a trabajar solo sobre predios compartidos?',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  const Text(
                      'Si eres colaborador (trabajador o consultor) y no tienes '
                      'un predio propio, puedes saltar este paso y acceder '
                      'directamente a los predios que te compartan otros '
                      'usuarios tras iniciar sesión.',
                      style: TextStyle(fontSize: 12)),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('No crear predio propio',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text(
                        'Solo trabajaré sobre predios compartidos.',
                        style: TextStyle(fontSize: 11)),
                    value: _sinPredioPropio,
                    onChanged: (v) => setState(() {
                      _sinPredioPropio = v ?? false;
                      // Si estaba en Ubicación y ya no creará predio, saltar.
                      if (_sinPredioPropio && _step == 3) _step = 4;
                    }),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Formulario del predio (deshabilitado si _sinPredioPropio)
          Opacity(
            opacity: _sinPredioPropio ? 0.4 : 1.0,
            child: IgnorePointer(
              ignoring: _sinPredioPropio,
              child: Column(children: [
                TextField(
                  controller: _nombrePredio,
                  decoration: InputDecoration(
                      labelText: _sinPredioPropio
                          ? 'Nombre del predio'
                          : 'Nombre del predio *',
                      hintText: 'Ej: Finca Villamariana',
                      border: const OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _propietario,
                  decoration: const InputDecoration(
                      labelText: 'Propietario',
                      border: OutlineInputBorder()),
                ),
              ]),
            ),
          ),
        ],
      );

  Widget _stepUbicacion() {
    final paisesAsync = ref.watch(paisesProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Ubicación',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Text(
            _sinPredioPropio
                ? 'Opcional — puedes omitir este paso si no creas un predio propio.'
                : 'País/región/municipio del predio + coordenadas si las conoces. '
                    'Puedes omitirlo y completarlo después.',
            style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),
        paisesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: $e'),
          data: (paises) => DropdownButtonFormField<int>(
            // Guard: si el id aún no está en la lista (fila recién creada
            // por la detección GPS y stream sin refrescar), no fijar value
            // para evitar el assert de DropdownButton.
            value: paises.any((p) => p.id == _paisId) ? _paisId : null,
            decoration: const InputDecoration(
                labelText: 'País', border: OutlineInputBorder()),
            items: paises
                .map((p) => DropdownMenuItem(value: p.id, child: Text(p.nombre)))
                .toList(),
            onChanged: (v) => setState(() {
              _paisId = v; _regionId = null; _municipioId = null;
            }),
          ),
        ),
        const SizedBox(height: 12),
        if (_paisId != null)
          Consumer(builder: (ctx, ref, _) {
            final regs = ref.watch(regionesProvider(_paisId!));
            return regs.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('Error: $e'),
              data: (regiones) => DropdownButtonFormField<int>(
                value: regiones.any((r) => r.id == _regionId) ? _regionId : null,
                decoration: const InputDecoration(
                    labelText: 'Región / Departamento',
                    border: OutlineInputBorder()),
                items: regiones
                    .map((r) => DropdownMenuItem(value: r.id, child: Text(r.nombre)))
                    .toList(),
                onChanged: (v) => setState(() {
                  _regionId = v; _municipioId = null;
                }),
              ),
            );
          }),
        const SizedBox(height: 12),
        if (_regionId != null)
          Consumer(builder: (ctx, ref, _) {
            final munis = ref.watch(municipiosProvider(_regionId!));
            return munis.when(
              loading: () => const SizedBox.shrink(),
              error: (e, _) => Text('Error: $e'),
              data: (municipios) => DropdownButtonFormField<int>(
                value: municipios.any((m) => m.id == _municipioId)
                    ? _municipioId
                    : null,
                decoration: const InputDecoration(
                    labelText: 'Municipio', border: OutlineInputBorder()),
                items: municipios
                    .map((m) => DropdownMenuItem(value: m.id, child: Text(m.nombre)))
                    .toList(),
                onChanged: (v) => setState(() => _municipioId = v),
              ),
            );
          }),
        // Estado de la detección automática país/región/municipio por GPS.
        if (_geoDetectando) ...[
          const SizedBox(height: 8),
          Row(children: const [
            SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 8),
            Text('Detectando ubicación desde coordenadas…',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ] else if (_geoDetectMsg != null) ...[
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(_geoDetectOk ? Icons.check_circle_outline : Icons.info_outline,
                size: 16, color: _geoDetectOk ? Colors.green : Colors.orange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(_geoDetectMsg!,
                  style: TextStyle(
                      fontSize: 12,
                      color: _geoDetectOk
                          ? Colors.green.shade700
                          : Colors.orange.shade800)),
            ),
          ]),
        ],
        // Botón manual: útil si el usuario escribió las coordenadas a mano.
        if (!_geoDetectando &&
            double.tryParse(_lat.text) != null &&
            double.tryParse(_lng.text) != null) ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _detectarGeografiaDesdeGps(
                  double.parse(_lat.text), double.parse(_lng.text)),
              icon: const Icon(Icons.travel_explore, size: 18),
              label: const Text('Detectar país/región desde coordenadas'),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Row(children: [
          const Expanded(
            child: Text('Coordenadas del predio',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          OutlinedButton.icon(
            onPressed: _obtainingGnss ? null : _obtenerCoordenadasGps,
            icon: _obtainingGnss
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location, size: 18),
            label: Text(_obtainingGnss ? 'Obteniendo…' : 'Obtener GPS'),
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _lat,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              // Rebuild para mostrar/ocultar el botón "Detectar…".
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Latitud',
                  hintText: 'Ej: 4.473252',
                  border: OutlineInputBorder()),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _lng,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true, signed: true),
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                  labelText: 'Longitud',
                  hintText: 'Ej: -75.698197',
                  border: OutlineInputBorder()),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        TextField(
          controller: _alt,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
              labelText: 'Altitud (msnm)',
              hintText: 'Ej: 1380',
              helperText:
                  'Se llena automáticamente al usar "Obtener GPS". Puedes editarlo.',
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(6)),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 18, color: Colors.blue),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                  'Las coordenadas y la altitud se usan para calcular '
                  'condiciones edafoclimáticas, piso térmico y '
                  'recomendaciones agronómicas.',
                  style: TextStyle(
                      fontSize: 11, color: Colors.blue.shade900)),
            ),
          ]),
        ),
      ],
    );
  }

  /// Captura lat/lng/altitud vía GNSS del dispositivo y llena los campos.
  ///
  /// Estrategia en cascada para evitar timeouts en cold-start del GPS:
  ///   1. Si hay `getLastKnownPosition` reciente (<10 min), la usamos
  ///      inmediatamente y disparamos un refinamiento en background.
  ///   2. Si no, pedimos posición con precisión `medium` (más rápida) con
  ///      timeout de 30 s.
  ///   3. Si eso también agota tiempo, caemos a `getLastKnownPosition` sin
  ///      restricción de antigüedad y advertimos al usuario.
  Future<void> _obtenerCoordenadasGps() async {
    setState(() => _obtainingGnss = true);
    try {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Activa el GPS del dispositivo e inténtalo de nuevo')));
        return;
      }
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
      Position? pos;
      String? aviso;
      try {
        pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.medium,
          timeLimit: const Duration(seconds: 30),
        );
      } catch (e) {
        // Timeout u otro error del sensor: intentar fallback a la última
        // posición conocida (puede estar cacheada por otras apps o por un
        // fix anterior). No garantiza precisión ni recencia.
        try {
          pos = await Geolocator.getLastKnownPosition();
        } catch (_) {}
        if (pos != null) {
          aviso = 'Usando última posición conocida — verifica precisión.';
        } else {
          rethrow;
        }
      }
      // Nota: el análisis de flujo garantiza pos != null aquí (la rama de
      // fallback hace rethrow si getLastKnownPosition tampoco devolvió).
      if (!mounted) return;
      setState(() {
        _lat.text = pos!.latitude.toStringAsFixed(6);
        _lng.text = pos.longitude.toStringAsFixed(6);
        if (!pos.altitude.isNaN && pos.altitude != 0) {
          _alt.text = pos.altitude.toStringAsFixed(0);
        }
      });
      // Mejora 2026-07-19: autollenar país/región/municipio desde las
      // coordenadas (fire-and-forget; muestra su propio estado inline).
      unawaited(
          _detectarGeografiaDesdeGps(pos.latitude, pos.longitude));
      final precisionTxt = pos.accuracy.isNaN
          ? ''
          : ' (±${pos.accuracy.toStringAsFixed(0)} m)';
      final altTxt = (!pos.altitude.isNaN && pos.altitude != 0)
          ? ' · alt ${pos.altitude.toStringAsFixed(0)} msnm'
          : '';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            (aviso ?? 'Coordenadas capturadas') + precisionTxt + altTxt),
        backgroundColor: aviso == null ? Colors.green : Colors.orange,
      ));
    } catch (e) {
      if (!mounted) return;
      final mensaje = e is TimeoutException
          ? 'El GPS tardó demasiado. Muévete al exterior, verifica que el '
              'GPS del sistema esté encendido y vuelve a intentar.'
          : 'No se pudo obtener la ubicación: $e';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(mensaje),
        duration: const Duration(seconds: 5),
      ));
    } finally {
      if (mounted) setState(() => _obtainingGnss = false);
    }
  }

  Widget _stepPermisos() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Permisos',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
              'Desmarca solo los que NO quieras conceder. Al pulsar '
              'Siguiente, el sistema te pedirá los permisos marcados.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          CheckboxListTile(
            title: const Text('Cámara'),
            subtitle: const Text('Para fotos de cultivos y detección de patologías'),
            secondary: const Icon(Icons.camera_alt),
            value: _permCam,
            onChanged: (v) => setState(() => _permCam = v ?? false),
          ),
          CheckboxListTile(
            title: const Text('Localización (GNSS)'),
            subtitle: const Text('Para coordenadas de cada lote'),
            secondary: const Icon(Icons.location_on),
            value: _permLoc,
            onChanged: (v) => setState(() => _permLoc = v ?? false),
          ),
          CheckboxListTile(
            title: const Text('Archivos'),
            subtitle: const Text('Para subir logo del predio, importar CSV, adjuntos de compras'),
            secondary: const Icon(Icons.folder),
            value: _permFiles,
            onChanged: (v) => setState(() => _permFiles = v ?? false),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8)),
            child: const Text(
                'ℹ️ En Windows/desktop no se muestran diálogos: los permisos '
                'del sistema se aplican al usar cada función.',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      );

  /// Solicita al SO los permisos marcados por el usuario y actualiza los
  /// checkboxes con el resultado. En desktop es no-op (se aprueba en uso).
  Future<void> _solicitarPermisosSO() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      _permisosSolicitados = true;
      return;
    }
    final aSolicitar = <Permission>[
      if (_permCam) Permission.camera,
      if (_permLoc) Permission.locationWhenInUse,
      // En Android 13+ los archivos van por scoped storage / photos.
      // Permission.storage cubre versiones anteriores; photos en modernas.
      if (_permFiles) Permission.photos,
      if (_permFiles) Permission.storage,
    ];
    if (aSolicitar.isEmpty) {
      _permisosSolicitados = true;
      return;
    }
    final resultados = await aSolicitar.request();
    if (!mounted) return;
    setState(() {
      _permCam = resultados[Permission.camera]?.isGranted ?? _permCam;
      _permLoc =
          resultados[Permission.locationWhenInUse]?.isGranted ?? _permLoc;
      final photos = resultados[Permission.photos]?.isGranted ?? false;
      final storage = resultados[Permission.storage]?.isGranted ?? false;
      _permFiles = photos || storage;
      _permisosSolicitados = true;
    });
  }

  Widget _stepIniciarSesion() {
    final logged = ref.watch(isLoggedInProvider);
    final user = ref.watch(currentUserProvider);
    final supabaseListo = ref.watch(supabaseInitProvider);
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Iniciar sesión',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        const Text(
            'Sincroniza tu predio entre dispositivos o accede a predios compartidos.',
            style: TextStyle(color: Colors.grey)),
        const SizedBox(height: 20),

        // Estado ya logueado
        if (logged && user != null)
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.check_circle, color: Colors.green),
                    const SizedBox(width: 6),
                    const Expanded(
                        child: Text('Sesión iniciada',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 15))),
                  ]),
                  const SizedBox(height: 4),
                  Text('Como: ${user.email ?? "?"}',
                      style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  Text(
                      'Al terminar el onboarding se sincronizarán tus predios '
                      'y colaboraciones automáticamente.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _authProcesando
                        ? null
                        : () async {
                            await Supabase.instance.client.auth.signOut();
                            if (mounted) {
                              setState(() {
                                _authMensaje = null;
                                _authExito = false;
                              });
                            }
                          },
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Cerrar sesión'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red),
                  ),
                ],
              ),
            ),
          )
        else ...[
          if (!supabaseListo)
            Card(
              color: Colors.orange.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  const Icon(Icons.warning_amber, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'La sincronización no está configurada. Puedes '
                          'continuar y usar la app en modo local.',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade900))),
                ]),
              ),
            ),
          if (!supabaseListo) const SizedBox(height: 12),

          // Formulario email + password
          TextField(
            controller: _emailAuth,
            enabled: supabaseListo && !_authProcesando,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(
                labelText: 'Correo electrónico',
                prefixIcon: Icon(Icons.email_outlined),
                border: OutlineInputBorder()),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _passwordAuth,
            enabled: supabaseListo && !_authProcesando,
            obscureText: true,
            autofillHints: _authEsRegistro
                ? const [AutofillHints.newPassword]
                : const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Contraseña',
              prefixIcon: const Icon(Icons.lock_outline),
              border: const OutlineInputBorder(),
              helperText: _authEsRegistro ? 'Mínimo 6 caracteres' : null,
            ),
          ),
          if (_authMensaje != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _authExito
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: _authExito ? Colors.green : Colors.red,
                    width: 0.5),
              ),
              child: Row(children: [
                Icon(_authExito ? Icons.check_circle : Icons.error_outline,
                    color: _authExito ? Colors.green : Colors.red,
                    size: 18),
                const SizedBox(width: 6),
                Expanded(
                    child: Text(_authMensaje!,
                        style: const TextStyle(fontSize: 13))),
              ]),
            ),
          ],
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: (_authProcesando || !supabaseListo) ? null : _authSubmit,
            icon: _authProcesando
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                : Icon(_authEsRegistro ? Icons.person_add : Icons.login),
            label: Text(_authEsRegistro ? 'Crear cuenta' : 'Iniciar sesión'),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _authProcesando
                ? null
                : () => setState(() {
                      _authEsRegistro = !_authEsRegistro;
                      _authMensaje = null;
                    }),
            child: Text(_authEsRegistro
                ? 'Ya tengo cuenta · Iniciar sesión'
                : 'No tengo cuenta · Crear una'),
          ),
          const Divider(),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6)),
            child: Row(children: [
              const Icon(Icons.offline_bolt, color: Colors.grey, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    'Puedes continuar sin iniciar sesión. En modo local tus '
                    'datos se guardan solo en este dispositivo.',
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade700)),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  Future<void> _authSubmit() async {
    final email = _emailAuth.text.trim().toLowerCase();
    final password = _passwordAuth.text;
    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _authMensaje = 'Ingresa un email válido.';
        _authExito = false;
      });
      return;
    }
    // Auditoría S7: mínimo 8 caracteres (configurar también en Supabase:
    // Auth → Settings → longitud mínima 8 + Leaked password protection).
    if (password.isEmpty ||
        (_authEsRegistro && password.length < 8)) {
      setState(() {
        _authMensaje = _authEsRegistro
            ? 'La contraseña debe tener al menos 8 caracteres.'
            : 'Ingresa tu contraseña.';
        _authExito = false;
      });
      return;
    }
    setState(() {
      _authProcesando = true;
      _authMensaje = null;
    });
    try {
      final client = Supabase.instance.client;
      if (_authEsRegistro) {
        final res =
            await client.auth.signUp(email: email, password: password);
        if (res.session != null) {
          setState(() {
            _authMensaje = '✓ Cuenta creada e iniciada.';
            _authExito = true;
          });
        } else {
          setState(() {
            _authMensaje =
                'Cuenta creada. Revisa tu correo para confirmar y luego '
                'inicia sesión.';
            _authExito = true;
            _authEsRegistro = false;
          });
        }
      } else {
        await client.auth.signInWithPassword(
            email: email, password: password);
        setState(() {
          _authMensaje = '✓ Sesión iniciada.';
          _authExito = true;
        });
      }
    } on AuthException catch (e) {
      setState(() {
        _authMensaje = _traducirAuthError(e.message);
        _authExito = false;
      });
    } catch (e) {
      setState(() {
        _authMensaje = 'Error inesperado: $e';
        _authExito = false;
      });
    } finally {
      if (mounted) setState(() => _authProcesando = false);
    }
  }

  String _traducirAuthError(String mensaje) {
    final m = mensaje.toLowerCase();
    if (m.contains('invalid login credentials')) {
      return 'Correo o contraseña incorrectos.';
    }
    if (m.contains('user already registered')) {
      return 'Ya existe una cuenta con ese correo. Inicia sesión.';
    }
    if (m.contains('email not confirmed')) {
      return 'Confirma tu correo antes de iniciar sesión.';
    }
    if (m.contains('rate limit')) {
      return 'Demasiados intentos. Espera un momento e inténtalo de nuevo.';
    }
    return mensaje;
  }

  Widget _stepEppoToken() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('EPPO Global Database',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
              'Conecta con el catálogo internacional de plagas y '
              'enfermedades (opcional).',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          Card(
            color: Colors.orange.shade50,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: const [
                    Icon(Icons.public, color: Colors.orange),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                          '¿Qué es EPPO Global Database?',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  const Text(
                      'Base de datos abierta de la European and Mediterranean '
                      'Plant Protection Organization. Contiene ~90 000 '
                      'organismos con nombres científicos normalizados, '
                      'hospederos, distribución y códigos EPPO.',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 6),
                  const Text('Ventajas al conectar:',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  _bullet('Autocompletado de nombres científicos'),
                  _bullet('Verificación de patologías reportadas'),
                  _bullet('Enriquecimiento del catálogo local al actualizar'),
                  _bullet('Códigos EPPO estándar para intercambio de datos'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: const [
                  Icon(Icons.vpn_key, size: 16, color: Colors.grey),
                  SizedBox(width: 6),
                  Text('¿Cómo obtengo un token?',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 12)),
                ]),
                const SizedBox(height: 4),
                const Text(
                    '1. Regístrate gratis en gd.eppo.int/user/register\n'
                    '2. En tu perfil, sección "API Access", copia tu token\n'
                    '3. Pégalo aquí',
                    style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _eppoToken,
            obscureText: _eppoObscure,
            decoration: InputDecoration(
              labelText: 'Token EPPO (opcional)',
              hintText: 'Pégalo aquí',
              prefixIcon: const Icon(Icons.vpn_key),
              suffixIcon: IconButton(
                icon: Icon(_eppoObscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined),
                tooltip: _eppoObscure ? 'Mostrar' : 'Ocultar',
                onPressed: () =>
                    setState(() => _eppoObscure = !_eppoObscure),
              ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          // Health check del servicio (GET /gd/v2/status). No requiere
          // token: permite distinguir "el API está caído / sin internet"
          // de "mi token es inválido" antes de continuar.
          Row(children: [
            OutlinedButton.icon(
              onPressed: _eppoHealthEnCurso ? null : _verificarEppoHealth,
              icon: _eppoHealthEnCurso
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.monitor_heart_outlined, size: 18),
              label: const Text('Verificar estado del servicio'),
            ),
          ]),
          if (_eppoHealthMsg != null) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(
                  _eppoHealthOk
                      ? Icons.check_circle_outline
                      : Icons.error_outline,
                  size: 16,
                  color: _eppoHealthOk ? Colors.green : Colors.red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(_eppoHealthMsg!,
                    style: TextStyle(
                        fontSize: 12,
                        color: _eppoHealthOk
                            ? Colors.green.shade700
                            : Colors.red.shade700)),
              ),
            ]),
          ],
          const SizedBox(height: 12),
          Text(
              _eppoToken.text.trim().isEmpty
                  ? 'Sin token: la app usará el catálogo local bundleado. '
                      'Podrás configurarlo después desde Configuración.'
                  : '✓ Token configurado. Al terminar podrás actualizar el '
                      'catálogo desde la pantalla de Patologías.',
              style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600)),
        ],
      );

  /// GET https://api.eppo.int/gd/v2/status — healthcheck del API EPPO.
  /// Muestra el resultado inline en el paso del token.
  Future<void> _verificarEppoHealth() async {
    setState(() {
      _eppoHealthEnCurso = true;
      _eppoHealthMsg = null;
    });
    final client = EppoClient(_eppoToken.text.trim());
    try {
      final st = await client.checkStatus();
      if (!mounted) return;
      setState(() {
        _eppoHealthOk = st.ok;
        if (st.ok) {
          final detalles = [
            if (st.version != null) 'v${st.version}',
            if (st.mensaje != null) st.mensaje!,
          ].join(' — ');
          _eppoHealthMsg =
              'Servicio EPPO en línea${detalles.isEmpty ? '' : ' ($detalles)'}.';
        } else {
          _eppoHealthMsg =
              'Servicio EPPO no disponible: ${st.mensaje ?? 'error desconocido'}. '
              'Puedes continuar sin token y configurarlo después.';
        }
      });
    } finally {
      client.close();
      if (mounted) setState(() => _eppoHealthEnCurso = false);
    }
  }

  Widget _stepConsentimiento() => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Comunidad NEXUS',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          const Text(
              'Ayúdanos a construir un control unificado de plagas para tu región.',
              style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 20),
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.public, color: Colors.green),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                          'Compartir reportes de patologías con la comunidad',
                          style: TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  const Text(
                      'Cuando reportes una patología (plaga, enfermedad, deficiencia) '
                      'la ubicación, foto y descripción se compartirán de forma '
                      'ANÓNIMA con otros productores.',
                      style: TextStyle(fontSize: 13)),
                  const SizedBox(height: 8),
                  const Text('Beneficios:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 4),
                  _bullet('Mapa de calor de plagas en tiempo real'),
                  _bullet('Alertas tempranas cuando aparezcan focos cerca'),
                  _bullet('Recomendaciones de tratamiento adaptadas a tu país'),
                  _bullet('Contribuyes a la investigación agropecuaria abierta'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: Colors.green.shade200),
                        borderRadius: BorderRadius.circular(6)),
                    child: Row(children: [
                      const Icon(Icons.privacy_tip_outlined,
                          color: Colors.green, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                            'No se comparte tu identidad, ni el nombre del predio, '
                            'ni tus datos de contacto. Solo la información del reporte.',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade700)),
                      ),
                    ]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            title: const Text('Sí, quiero contribuir a la comunidad'),
            subtitle: const Text(
                'Podrás desactivarlo en cualquier momento desde Configuración.'),
            value: _consentimientoPatologias,
            onChanged: (v) =>
                setState(() => _consentimientoPatologias = v ?? false),
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 8),
          Text(
              _consentimientoPatologias
                  ? 'Al terminar el onboarding empezarás a beneficiarte del mapa comunitario.'
                  : 'Podrás usar la app normalmente. Tus reportes de patologías '
                      'se guardarán solo en tu dispositivo.',
              style: TextStyle(
                  fontSize: 11,
                  fontStyle: FontStyle.italic,
                  color: Colors.grey.shade600)),
        ],
      );

  Widget _bullet(String txt) => Padding(
        padding: const EdgeInsets.only(left: 6, top: 2),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('• ', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(txt, style: const TextStyle(fontSize: 12))),
        ]),
      );

  /// Coordenadas → país/región/municipio (mejora 2026-07-19).
  /// Geocodificación inversa online (Nominatim) + alta automática en el
  /// catálogo local de las filas que falten. Si no hay red, informa y
  /// deja la selección manual.
  Future<void> _detectarGeografiaDesdeGps(double lat, double lng) async {
    if (_geoDetectando) return;
    setState(() {
      _geoDetectando = true;
      _geoDetectMsg = null;
      _geoDetectOk = false;
    });
    try {
      final lugar = await GeocodingService.reverse(lat, lng);
      if (!mounted) return;
      if (lugar == null || (lugar.iso2 == null && lugar.pais == null)) {
        setState(() {
          _geoDetectMsg =
              'No se pudo detectar la ubicación (¿sin internet?). '
              'Selecciona país/región/municipio manualmente.';
        });
        return;
      }
      final ids = await ref.read(dataMutationsProvider).asegurarGeografia(
            paisNombre: lugar.pais,
            iso2: lugar.iso2,
            regionNombre: lugar.region,
            municipioNombre: lugar.municipio,
          );
      if (!mounted) return;
      setState(() {
        if (ids.paisId != null) {
          _paisId = ids.paisId;
          _regionId = ids.regionId;
          _municipioId = ids.municipioId;
          _geoDetectOk = true;
          _geoDetectMsg = 'Ubicación detectada: $lugar';
        } else {
          _geoDetectMsg =
              'La ubicación detectada ($lugar) no se pudo registrar; '
              'selecciónala manualmente.';
        }
      });
    } catch (e) {
      Log.w('[onboarding] detección geográfica falló: $e');
      if (mounted) {
        setState(() {
          _geoDetectMsg =
              'No se pudo detectar la ubicación. Selecciónala manualmente.';
        });
      }
    } finally {
      if (mounted) setState(() => _geoDetectando = false);
    }
  }

  /// Paso siguiente respetando saltos (p. ej. omitir Ubicación sin predio).
  int _siguientePaso(int actual) {
    var next = actual + 1;
    if (_sinPredioPropio && next == 3) next = 4;
    return next;
  }

  /// Paso anterior respetando saltos.
  int _anteriorPaso(int actual) {
    var prev = actual - 1;
    if (_sinPredioPropio && prev == 3) prev = 2;
    return prev;
  }

  bool _canProceed() {
    // Orden actual de steps (definido en _buildStep):
    //   0: Iniciar sesión   (opcional)
    //   1: Preferencias
    //   2: Predio           (requiere nombre si no marca "sin predio propio")
    //   3: Ubicación
    //   4: Permisos
    //   5: EPPO Token       (opcional)
    //   6: Consentimiento
    switch (_step) {
      case 0: return true; // Iniciar sesión: opcional (puede saltarse)
      case 1: return true; // Preferencias
      case 2: return _sinPredioPropio || _nombrePredio.text.trim().isNotEmpty;
      case 3: return true; // Ubicación
      case 4: return true; // Permisos
      case 5: return true; // EPPO Token: opcional
      case 6: return true; // Consentimiento
      default: return true;
    }
  }

  Future<void> _next() async {
    if (!_canProceed()) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Completa los campos requeridos')));
      return;
    }
    // UX: en el paso 0 (Iniciar sesión), si el usuario escribió email y
    // contraseña pero no pulsó el botón del formulario, hacemos el login
    // automáticamente al presionar "Siguiente". Si no hay credenciales,
    // se salta el paso (modo local).
    if (_step == 0) {
      // Guard (fix P8): `Supabase.instance` lanza si la init diferida aún
      // no terminó (o no hay .env). En ese caso se salta el auto-login.
      final supabaseListo = ref.read(supabaseInitProvider);
      final tieneSesion = supabaseListo &&
          Supabase.instance.client.auth.currentSession != null;
      final tieneCredenciales = supabaseListo &&
          _emailAuth.text.trim().isNotEmpty &&
          _passwordAuth.text.isNotEmpty;
      if (!tieneSesion && tieneCredenciales && !_authProcesando) {
        // Ejecuta el login antes de avanzar. Si falla, no avanzamos.
        await _authSubmit();
        // _authSubmit actualiza _authExito según el resultado
        if (!_authExito) {
          // Error mostrado por el mensaje in-line; no avanzamos.
          return;
        }
      }
    }
    // UX: al salir del paso 4 (Permisos), solicita los permisos marcados
    // al SO en un solo bloque, solo la primera vez que se llega al paso.
    if (_step == 4 && !_permisosSolicitados) {
      await _solicitarPermisosSO();
    }
    setState(() => _step = _siguientePaso(_step));
  }

  Future<void> _finish() async {
    // Validación: solo si NO marcó "sin predio propio"
    // (case 2 en el switch actual — paso "Predio")
    if (!_sinPredioPropio && _nombrePredio.text.trim().isEmpty) {
      setState(() => _step = 2);
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El nombre del predio es requerido')));
      return;
    }
    final mut = ref.read(dataMutationsProvider);
    final tokenTrim = _eppoToken.text.trim();
    // Fix bug "Comenzar no hace nada" (2026-07-19): cualquier excepción en
    // las escrituras a la BD dejaba el botón mudo. Ahora el error se
    // muestra al usuario y queda en el log.
    try {
      await mut.savePreferences(
        idioma: _idioma,
        estiloUi: _estilo,
        sistemaUnidades: _unidades,
        monedaCodigo: _moneda,
        consentimientoPatologias: _consentimientoPatologias,
        // Solo enviar si el usuario escribió algo; null significa "no cambiar".
        eppoToken: tokenTrim.isEmpty ? null : tokenTrim,
      );
      if (_sinPredioPropio) {
        // Solo marca el onboarding como completado sin crear predio.
        // El usuario deberá iniciar sesión y aceptar predios compartidos.
        await mut.completeOnboardingSinPredio();
      } else {
        await mut.completeOnboarding(
          nombrePredio: _nombrePredio.text.trim(),
          propietario: _propietario.text.trim(),
          paisId: _paisId,
          regionId: _regionId,
          municipioId: _municipioId,
          lat: double.tryParse(_lat.text),
          lng: double.tryParse(_lng.text),
          altM: double.tryParse(_alt.text),
        );
      }
    } catch (e, st) {
      Log.e('[onboarding] _finish falló', e, st);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('No se pudo completar la configuración: $e'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 8),
        ));
      }
      return;
    }
    // Sincroniza providers UI con lo persistido
    ref.read(appStyleProvider.notifier).state = AppThemes.parse(_estilo);
    ref.read(localeProvider.notifier).state = Locale(_idioma);
    ref.read(unitSystemProvider.notifier).state = _unidades;
    ref.read(currencyProvider.notifier).state = _moneda;
    // Si el usuario inició sesión durante el onboarding, dispara un sync
    // inmediato para bajar predios compartidos y contenido remoto.
    final estaLogueado = ref.read(isLoggedInProvider);
    if (estaLogueado) {
      // Fire-and-forget: no bloquea la transición al Dashboard.
      // El AutoSyncService también hará su parte, pero disparar acá
      // asegura que el usuario ve los datos apenas entra al Dashboard.
      ref.read(syncServiceProvider).sincronizar();
    }
    if (_sinPredioPropio && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            estaLogueado
                ? 'Bienvenido. Sincronizando tus predios compartidos…'
                : 'Bienvenido. Inicia sesión desde Cuenta para acceder a '
                    'predios compartidos.'),
        backgroundColor: Colors.blue.shade700,
        duration: const Duration(seconds: 6),
      ));
    }
    // Ofrecer el Asistente paso a paso al llegar al Dashboard (la 1ª
    // sincronización ya quedó disparada arriba si hay sesión).
    ref.read(ofrecerWizardProvider.notifier).state = true;
    // El router en app.dart escuchará primeraEjecucionProvider y navegará al Dashboard.
  }
}
