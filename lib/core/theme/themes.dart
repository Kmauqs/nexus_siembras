import 'package:flutter/material.dart';

/// Estilo de UI seleccionado por el usuario en Configuración.
enum AppStyle { accesible, material }

/// Paletas y ThemeData para los dos estilos.
/// Ambos pasan WCAG AA en contraste texto/fondo y usan verde/naranja/rojo
/// distinguibles para deuteranopía.
class AppThemes {
  AppThemes._();

  // ---------- Colores de estado (compartidos) ----------
  static const Color colorOk = Color(0xFF1B7A3E);
  static const Color colorWarn = Color(0xFFD97706);
  static const Color colorAlert = Color(0xFFB91C1C);

  // ============================================================
  // ESTILO A — ACCESIBLE (mayores, una sola mano)
  // ============================================================
  static ThemeData get accesibleLight {
    const primary = Color(0xFF1B7A3E);
    const bg = Color(0xFFFFFFFF);
    const surface = Color(0xFFF4F7F2);
    const text = Color(0xFF0F1A14);
    const muted = Color(0xFF3A4A40);
    const divider = Color(0xFFC8D2CB);

    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: text,
      error: colorAlert,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: bg,
      dividerColor: divider,

      // Tipografía grande base (20 vs 16 estándar)
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 20, color: text),
        bodyMedium: TextStyle(fontSize: 18, color: text),
        bodySmall: TextStyle(fontSize: 17, color: muted),
        titleLarge: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: text),
        titleMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: text),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(88, 56), // touch target grande
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: divider),
        ),
        labelStyle: const TextStyle(fontSize: 18, color: muted),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
        iconTheme: IconThemeData(color: Colors.white, size: 30),
      ),
    );
  }

  // ============================================================
  // ESTILO B — MATERIAL DESIGN 3
  // ============================================================
  static ThemeData get materialLight {
    const primary = Color(0xFF0F5132);
    const bg = Color(0xFFFBFDF8);
    const surface = Color(0xFFFFFFFF);
    const text = Color(0xFF1A1C19);
    const muted = Color(0xFF43483F);
    const divider = Color(0xFFDDE5DC);

    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
      primary: primary,
      onPrimary: Colors.white,
      surface: surface,
      onSurface: text,
      error: colorAlert,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: base,
      scaffoldBackgroundColor: bg,
      dividerColor: divider,
      textTheme: const TextTheme(
        bodyLarge: TextStyle(fontSize: 16, color: text),
        bodyMedium: TextStyle(fontSize: 15, color: text),
        bodySmall: TextStyle(fontSize: 14, color: muted),
        titleLarge: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: text),
        titleMedium: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: text),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 44),
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: divider),
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleTextStyle: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: Colors.white),
      ),
    );
  }

  /// Devuelve el ThemeData correspondiente al estilo seleccionado.
  static ThemeData themeFor(AppStyle style) =>
      style == AppStyle.accesible ? accesibleLight : materialLight;

  /// Convierte el string persistido en enum.
  static AppStyle parse(String s) =>
      s == 'accesible' ? AppStyle.accesible : AppStyle.material;

  static String toStorage(AppStyle s) =>
      s == AppStyle.accesible ? 'accesible' : 'material';
}
