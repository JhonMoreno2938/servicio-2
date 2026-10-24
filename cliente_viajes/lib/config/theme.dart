// lib/config/theme.dart
//
// Tema institucional global de la Pizarra de Movilidad Rural.
// Requiere el paquete google_fonts:  flutter pub add google_fonts

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ============================================
// COLORES INSTITUCIONALES
// ============================================
class AppColors {
  AppColors._();

  static const Color verde = Color(0xFF007A33); // Principal
  static const Color rojo = Color(0xFFE20613); // Destructivo
  static const Color azul = Color(0xFF0085CA); // Informativo
  static const Color fondo = Color(0xFFF8F9FA); // Fondo
  static const Color texto = Color(0xFF212529); // Texto

  // Apoyo (contraste suficiente sobre fondo claro).
  static const Color textoSuave = Color(0xFF6C757D);
  static const Color borde = Color(0xFFDEE2E6);
}

// ============================================
// TEMA GLOBAL
// ============================================
class AppTheme {
  AppTheme._();

  static const double radioBoton = 8;
  static const double radioTarjeta = 12;
  static const double paddingTarjeta = 16;

  // Forma de tarjetas y cuadros de diálogo (radio ~12).
  static const RoundedRectangleBorder formaTarjeta = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(radioTarjeta)),
  );

  // Borde de los campos de texto (radio ~8).
  static const OutlineInputBorder bordeCampo = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(radioBoton)),
  );

  // Ancho de un cuadro de diálogo que nunca desborda la pantalla.
  static double anchoDialogo(BuildContext context, double maximo) {
    final disponible = MediaQuery.of(context).size.width - 96;
    return disponible < maximo ? disponible : maximo;
  }

  // Roboto para el cuerpo.
  static TextStyle? _cuerpo(TextStyle? estilo) {
    return GoogleFonts.roboto(
      textStyle: estilo,
      color: AppColors.texto,
    );
  }

  // Montserrat para los títulos.
  static TextStyle? _titulo(TextStyle? estilo, {double? tamano}) {
    return GoogleFonts.montserrat(
      textStyle: estilo,
      fontWeight: FontWeight.w600,
      fontSize: tamano ?? estilo?.fontSize,
      color: AppColors.texto,
    );
  }

  static ThemeData get theme {
    final esquema = ColorScheme.fromSeed(
      seedColor: AppColors.verde,
      brightness: Brightness.light,
    ).copyWith(
      primary: AppColors.verde,
      onPrimary: Colors.white,
      secondary: AppColors.azul,
      onSecondary: Colors.white,
      error: AppColors.rojo,
      onError: Colors.white,
      surface: Colors.white,
      onSurface: AppColors.texto,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: esquema);
    final t = base.textTheme;

    // Se arma el TextTheme estilo por estilo (en lugar de usar
    // GoogleFonts.robotoTextTheme) para no depender del tipo TextTheme
    // que usa el paquete.
    final textTheme = t.copyWith(
      displayLarge: _titulo(t.displayLarge),
      displayMedium: _titulo(t.displayMedium),
      displaySmall: _titulo(t.displaySmall),
      headlineLarge: _titulo(t.headlineLarge),
      headlineMedium: _titulo(t.headlineMedium),
      headlineSmall: _titulo(t.headlineSmall, tamano: 20),
      titleLarge: _titulo(t.titleLarge, tamano: 20),
      titleMedium: _titulo(t.titleMedium, tamano: 18),
      titleSmall: _titulo(t.titleSmall),
      bodyLarge: _cuerpo(t.bodyLarge),
      bodyMedium: _cuerpo(t.bodyMedium),
      bodySmall: _cuerpo(t.bodySmall),
      labelLarge: _cuerpo(t.labelLarge),
      labelMedium: _cuerpo(t.labelMedium),
      labelSmall: _cuerpo(t.labelSmall),
    );

    final formaBoton = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radioBoton),
    );
    const tamanoMinimo = Size(64, 48); // Área táctil accesible.

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.fondo,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.verde,
        foregroundColor: Colors.white,
        titleTextStyle: GoogleFonts.montserrat(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: formaBoton,
          minimumSize: tamanoMinimo,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: formaBoton,
          minimumSize: tamanoMinimo,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: formaBoton,
          minimumSize: tamanoMinimo,
        ),
      ),
    );
  }
}