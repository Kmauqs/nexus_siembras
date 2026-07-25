// NEXUS Siembras — i18n en runtime (Fase B4, 2026-07-20).
//
// Por qué un cargador propio y no `gen_l10n`: el chequeo de gen_l10n de
// Flutter en Windows genera falsos "no read/write" incluso con permisos
// correctos (ver nota histórica en pubspec.yaml), y bloqueaba el build.
// Este cargador lee los mismos archivos ARB (`lib/l10n/*.arb`, declarados
// como assets) en tiempo de ejecución — sin generación de código.
//
// Uso en widgets:
//   context.t('menuHome')                    → 'Inicio'
//   context.t('dashFarmPurchases', {'year': '2026'})
//
// Comportamiento: si falta la clave en el idioma activo cae a español y,
// si tampoco existe, devuelve la propia clave (visible en QA, nunca
// rompe la UI).

import 'dart:convert';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../log.dart';

class AppLocalizations {
  AppLocalizations(this.locale, this._valores, this._fallback);

  final Locale locale;
  final Map<String, String> _valores;
  final Map<String, String> _fallback; // español, red de seguridad

  static const List<Locale> soportados = [
    Locale('es'),
    Locale('en'),
    Locale('pt'),
  ];

  static const _localeFallback = 'es';

  /// Caché por idioma: los ARB se leen una sola vez por sesión.
  static final Map<String, Map<String, String>> _cache = {};

  static AppLocalizations of(BuildContext context) =>
      Localizations.of<AppLocalizations>(context, AppLocalizations)!;

  /// Traduce [clave], sustituyendo `{placeholder}` por [args].
  String t(String clave, [Map<String, String>? args]) {
    var s = _valores[clave] ?? _fallback[clave];
    if (s == null) {
      // Clave sin traducir: devolverla tal cual permite detectarla en QA.
      if (kDebugMode) Log.d('[i18n] clave faltante: $clave');
      return clave;
    }
    if (args != null) {
      args.forEach((k, v) => s = s!.replaceAll('{$k}', v));
    }
    return s!;
  }

  /// Carga y parsea un ARB. Las claves de metadatos (`@…`) se descartan.
  static Future<Map<String, String>> _cargarArb(String code) async {
    if (_cache.containsKey(code)) return _cache[code]!;
    try {
      final raw = await rootBundle.loadString('lib/l10n/$code.arb');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final map = <String, String>{
        for (final e in json.entries)
          if (!e.key.startsWith('@') && e.value is String)
            e.key: e.value as String,
      };
      _cache[code] = map;
      return map;
    } catch (e) {
      Log.w('[i18n] no se pudo cargar $code.arb: $e');
      _cache[code] = const {};
      return const {};
    }
  }

  static Future<AppLocalizations> cargar(Locale locale) async {
    final code = locale.languageCode;
    final fallback = await _cargarArb(_localeFallback);
    final valores =
        code == _localeFallback ? fallback : await _cargarArb(code);
    return AppLocalizations(locale, valores, fallback);
  }
}

class AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => AppLocalizations.soportados
      .any((l) => l.languageCode == locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) =>
      AppLocalizations.cargar(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}

/// Azúcar sintáctico: `context.t('clave')`.
extension I18nContext on BuildContext {
  String t(String clave, [Map<String, String>? args]) =>
      AppLocalizations.of(this).t(clave, args);
}
