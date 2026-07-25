// Auto-retry de sincronización cuando la conexión vuelve.
//
// Escucha `Connectivity.onConnectivityChanged` y, cuando detecta que
// pasamos de sin-red a con-red (o el estado de red se aclara al arrancar
// la app), verifica si hay cambios locales pendientes y dispara un
// sync automático. Sin conexión: no hace nada, solo espera.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/log.dart';
import 'sync_service.dart';

class AutoSyncService {
  AutoSyncService(this.sync);
  final SyncService sync;

  StreamSubscription<List<ConnectivityResult>>? _sub;
  bool _huboOffline = true; // arranca asumiendo offline hasta que se confirme
  bool _sincronizando = false; // guard de reentrada (auditoría P6)
  DateTime? _ultimoAutoSync;

  /// Última auto-sincronización exitosa (para exponer en UI si se quiere).
  DateTime? get ultimoAutoSync => _ultimoAutoSync;

  /// Inicia la escucha. Idempotente.
  void iniciar() {
    _sub ??= Connectivity().onConnectivityChanged.listen(_onConnectivity);
    // Chequeo inicial
    Connectivity().checkConnectivity().then(_onConnectivity);
  }

  void detener() {
    _sub?.cancel();
    _sub = null;
  }

  Future<void> _onConnectivity(List<ConnectivityResult> results) async {
    final tieneRed = results.any((r) =>
        r == ConnectivityResult.wifi ||
        r == ConnectivityResult.mobile ||
        r == ConnectivityResult.ethernet ||
        r == ConnectivityResult.vpn);
    if (!tieneRed) {
      _huboOffline = true;
      return;
    }
    // Transición offline→online
    if (_huboOffline) {
      _huboOffline = false;
      await _intentarSync();
    }
  }

  Future<void> _intentarSync() async {
    // Guard de reentrada: el listener de conectividad y el chequeo inicial
    // de `iniciar()` pueden disparar esto casi a la vez (auditoría P6).
    if (_sincronizando) return;
    // No sync si no hay sesión de auth
    if (Supabase.instance.client.auth.currentSession == null) return;
    // Anti-spam: no reintentar más de 1 vez cada 30 segundos
    final ahora = DateTime.now();
    if (_ultimoAutoSync != null &&
        ahora.difference(_ultimoAutoSync!).inSeconds < 30) {
      return;
    }
    // Nota (auditoría P6): antes se llamaba `contarPendientes()` aquí y su
    // resultado se descartaba — era solo costo (full-scan de todas las
    // tablas). `sincronizar()` ya decide por sí mismo qué subir/bajar.
    _sincronizando = true;
    try {
      final res = await sync.sincronizar();
      if (res.exito) {
        _ultimoAutoSync = ahora;
      } else if (res.error != null) {
        Log.w('[auto-sync] fallo: ${res.error}');
      }
    } finally {
      _sincronizando = false;
    }
  }
}
