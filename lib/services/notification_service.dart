// Servicio de notificaciones locales para NEXUS Siembras.
//
// Diseño defensivo: soporta Android e iOS de forma nativa. En Windows,
// macOS Desktop y Web, la inicialización es no-op para no romper la
// ejecución en escritorio durante desarrollo.

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _inicializado = false;

  /// Retorna true si la plataforma soporta notificaciones locales
  /// (Android o iOS). En web/desktop retorna false y todas las
  /// operaciones son no-op.
  bool get soportado {
    if (kIsWeb) return false;
    try {
      return Platform.isAndroid || Platform.isIOS;
    } catch (_) {
      return false;
    }
  }

  /// Inicializa el plugin y prepara la zona horaria. Idempotente.
  Future<void> init() async {
    if (_inicializado || !soportado) return;
    tzdata.initializeTimeZones();
    // Zona horaria por defecto: America/Bogota (UTC-5, sin DST).
    // En una fase futura se podría inferir del sistema.
    try {
      tz.setLocalLocation(tz.getLocation('America/Bogota'));
    } catch (_) {}

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
    );
    await _plugin.initialize(initSettings);
    _inicializado = true;
  }

  /// Solicita permisos al usuario (Android 13+ y iOS).
  Future<void> pedirPermisos() async {
    if (!soportado || !_inicializado) return;
    try {
      if (Platform.isAndroid) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
      } else if (Platform.isIOS) {
        await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.requestPermissions(alert: true, badge: true, sound: true);
      }
    } catch (_) {}
  }

  /// Programa una notificación para el momento indicado.
  /// El [id] debe ser único (usar eventoId de la BD).
  Future<void> programar({
    required int id,
    required DateTime cuando,
    required String titulo,
    required String cuerpo,
    String? payload,
  }) async {
    if (!soportado || !_inicializado) return;
    // No programar en el pasado
    final ahora = DateTime.now();
    if (cuando.isBefore(ahora)) return;
    const androidDetails = AndroidNotificationDetails(
      'nexus_siembras_eventos',
      'Alertas de cultivo',
      channelDescription:
          'Recordatorios de eventos programados (abono, cosecha, etc.)',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    const interpretation = UILocalNotificationDateInterpretation.absoluteTime;
    const scheduleMode = AndroidScheduleMode.inexactAllowWhileIdle;

    try {
      await _plugin.zonedSchedule(
        id,
        titulo,
        cuerpo,
        tz.TZDateTime.from(cuando, tz.local),
        details,
        uiLocalNotificationDateInterpretation: interpretation,
        androidScheduleMode: scheduleMode,
        payload: payload,
      );
    } catch (_) {
      // Silencioso: si falla (permisos denegados, dispositivo ahorro), ignora.
    }
  }

  /// Cancela una notificación por ID.
  Future<void> cancelar(int id) async {
    if (!soportado || !_inicializado) return;
    try {
      await _plugin.cancel(id);
    } catch (_) {}
  }

  /// Cancela todas las notificaciones programadas.
  Future<void> cancelarTodas() async {
    if (!soportado || !_inicializado) return;
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }

  /// Muestra una notificación inmediata (para el botón "Probar").
  Future<void> mostrarAhora({
    required String titulo,
    required String cuerpo,
  }) async {
    if (!soportado || !_inicializado) return;
    const androidDetails = AndroidNotificationDetails(
      'nexus_siembras_eventos',
      'Alertas de cultivo',
      channelDescription: 'Prueba de notificación',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@mipmap/ic_launcher',
    );
    const iosDetails = DarwinNotificationDetails();
    const details =
        NotificationDetails(android: androidDetails, iOS: iosDetails);
    try {
      await _plugin.show(0, titulo, cuerpo, details);
    } catch (_) {}
  }
}
