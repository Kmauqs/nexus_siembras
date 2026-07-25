// Providers globales (Riverpod)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/themes.dart';
import '../data/database/database.dart';

/// Estilo de UI seleccionado (persistir a Configs en Fase 2c).
final appStyleProvider = StateProvider<AppStyle>((ref) => AppStyle.material);

/// Idioma actual.
final localeProvider = StateProvider<Locale>((ref) => const Locale('es'));

/// Sistema de unidades (SI | imperial | tecnico | cgs).
final unitSystemProvider = StateProvider<String>((ref) => 'SI');

/// Código ISO 4217 de la moneda para reportes y visualización.
final currencyProvider = StateProvider<String>((ref) => 'COP');

/// Catálogo de monedas soportadas (LATAM + Caribe).
const kSupportedCurrencies = <({String code, String label})>[
  (code: 'COP', label: 'COP — Colombia (Peso)'),
  (code: 'USD', label: 'USD — Estados Unidos / Ecuador / Puerto Rico (Dólar)'),
  (code: 'BRL', label: 'BRL — Brasil (Real)'),
  (code: 'MXN', label: 'MXN — México (Peso)'),
  (code: 'CLP', label: 'CLP — Chile (Peso)'),
  (code: 'ARS', label: 'ARS — Argentina (Peso)'),
  (code: 'UYU', label: 'UYU — Uruguay (Peso)'),
  (code: 'PYG', label: 'PYG — Paraguay (Guaraní)'),
  (code: 'PEN', label: 'PEN — Perú (Sol)'),
  (code: 'BOB', label: 'BOB — Bolivia (Boliviano)'),
  (code: 'PAB', label: 'PAB — Panamá (Balboa)'),
  (code: 'CRC', label: 'CRC — Costa Rica (Colón)'),
  (code: 'HNL', label: 'HNL — Honduras (Lempira)'),
  (code: 'GTQ', label: 'GTQ — Guatemala (Quetzal)'),
  (code: 'CUP', label: 'CUP — Cuba (Peso)'),
  (code: 'DOP', label: 'DOP — República Dominicana (Peso)'),
  (code: 'HTG', label: 'HTG — Haití (Gourde)'),
  (code: 'JMD', label: 'JMD — Jamaica (Dólar)'),
];

/// Predio activo.
final activeFarmProvider = StateProvider<int?>((ref) => null);

/// Asistente paso a paso (2026-07-20).
/// Paso actual — vive fuera del widget para que el avance NO se pierda al
/// navegar a otras pantallas (crear lote, proveedor, etc.) y volver.
final wizardStepProvider = StateProvider<int>((ref) => 0);

/// Bandera efímera: al completar el onboarding se enciende para que el
/// Dashboard ofrezca ejecutar el Asistente (tras la 1ª sincronización).
final ofrecerWizardProvider = StateProvider<bool>((ref) => false);

/// Instancia global de la BD (se cierra automáticamente cuando la app se destruye).
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
