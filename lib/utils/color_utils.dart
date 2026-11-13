import 'package:flutter/material.dart';

/// Versión más oscura de [color]; [amount] va de 0 (igual) a 1 (negro).
/// Es proporcional, para que los colores ya oscuros no queden casi negros.
Color darken(Color color, [double amount = 0.2]) {
  final hsl = HSLColor.fromColor(color);
  return hsl
      .withLightness((hsl.lightness * (1 - amount)).clamp(0.0, 1.0))
      .toColor();
}

/// Color de texto legible (blanco o negro) sobre un fondo [background].
Color onColor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black87;
}

/// Da formato de dinero: `$12.50`, y `-$12.50` para negativos.
String formatMoney(double value) {
  final text = value.abs().toStringAsFixed(2);
  // Evita mostrar "-$0.00" por redondeo.
  final negative = value < 0 && text != '0.00';
  return '${negative ? '-' : ''}\$$text';
}

/// Convierte el texto de un campo de dinero a número. Acepta coma o punto
/// como separador decimal. Devuelve null si no es un número.
double? parseMoney(String text) {
  final value = double.tryParse(text.trim().replaceAll(',', '.'));
  if (value == null || value.isNaN || value.isInfinite) return null;
  return value;
}
