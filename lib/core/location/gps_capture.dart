// NEXUS Siembras — captura GNSS unificada (lat, lng, altitud).
//
// Varios formularios pedían GPS pero a menudo dejaban la altitud vacía:
// con precisión media/red el sensor suele devolver altitude=0/NaN.
// Aquí se pide un fix alto y, si falta altitud, se refina unos segundos
// con el stream antes de devolver el resultado.

import 'dart:async';

import 'package:geolocator/geolocator.dart';

class GpsCaptureException implements Exception {
  GpsCaptureException(this.message);
  final String message;

  @override
  String toString() => message;
}

class GpsFix {
  const GpsFix({
    required this.latitude,
    required this.longitude,
    this.altitudeMsnm,
    required this.accuracyM,
    this.fromCache = false,
  });

  final double latitude;
  final double longitude;
  /// Metros sobre el nivel del mar cuando el sensor la reportó.
  final double? altitudeMsnm;
  final double accuracyM;
  final bool fromCache;

  /// Texto corto para snackbars: precisión y altitud si hay.
  String get detalle {
    final prec =
        accuracyM.isNaN ? '' : '±${accuracyM.toStringAsFixed(0)} m';
    final alt = altitudeMsnm != null
        ? '${prec.isEmpty ? '' : ' · '}alt ${altitudeMsnm!.toStringAsFixed(0)} msnm'
        : '';
    if (prec.isEmpty && alt.isEmpty) return '';
    return '($prec$alt)';
  }
}

bool _altitudUtil(double alt) =>
    !alt.isNaN && !alt.isInfinite && alt.abs() >= 0.5;

/// Obtiene lat/lng y, en la medida de lo posible, altitud.
Future<GpsFix> capturarGps({
  Duration timeLimit = const Duration(seconds: 20),
}) async {
  final servicioActivo = await Geolocator.isLocationServiceEnabled();
  if (!servicioActivo) {
    throw GpsCaptureException(
        'Activa el servicio de ubicación del sistema');
  }
  var perm = await Geolocator.checkPermission();
  if (perm == LocationPermission.denied) {
    perm = await Geolocator.requestPermission();
  }
  if (perm == LocationPermission.denied ||
      perm == LocationPermission.deniedForever) {
    throw GpsCaptureException('Permiso de ubicación denegado');
  }

  Position? pos;
  var fromCache = false;
  Object? primerError;
  try {
    pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
      timeLimit: timeLimit,
    );
  } catch (e) {
    primerError = e;
    try {
      pos = await Geolocator.getLastKnownPosition();
      fromCache = pos != null;
    } catch (_) {}
    if (pos == null) {
      if (primerError is TimeoutException) {
        throw GpsCaptureException(
            'El GPS tardó demasiado. Muévete al exterior e inténtalo de nuevo.');
      }
      throw GpsCaptureException('No se pudo obtener la ubicación: $e');
    }
  }

  if (!_altitudUtil(pos.altitude)) {
    final refined = await _refinarConAltitud(
      seed: pos,
      maxWait: const Duration(seconds: 10),
    );
    if (refined != null) pos = refined;
  }

  return GpsFix(
    latitude: pos.latitude,
    longitude: pos.longitude,
    altitudeMsnm: _altitudUtil(pos.altitude) ? pos.altitude : null,
    accuracyM: pos.accuracy,
    fromCache: fromCache,
  );
}

Future<Position?> _refinarConAltitud({
  required Position seed,
  required Duration maxWait,
}) async {
  var best = seed;
  try {
    await for (final p in Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.best,
        distanceFilter: 0,
      ),
    ).timeout(maxWait)) {
      best = p;
      if (_altitudUtil(p.altitude)) return p;
    }
  } on TimeoutException {
    // Se queda con el mejor fix obtenido.
  } catch (_) {}
  return best;
}
