import 'package:flutter/material.dart';

/// Tipo de libro.
abstract final class BookKind {
  /// Presupuesto mensual: ingresos y una lista de renglones para marcar.
  static const String monthly = 'monthly';

  /// Cuenta: abonos y retiros con saldo corrido, sin cortes por mes.
  static const String ledger = 'ledger';

  static const List<String> values = [monthly, ledger];
}

/// Un libro contable: un registro independiente con su nombre y color.
class Book {
  static const int maxNameLength = 40;

  /// Colores que se ofrecen al crear o editar un libro.
  /// Son esmaltes heráldicos, a juego con el ícono de la app.
  static const List<Color> palette = [
    Color(0xFF56692F), // sinople (verde bosque)
    Color(0xFF2E4A72), // azur (azul real)
    Color(0xFF8C2B23), // gules (carmesí)
    Color(0xFF5B2A6B), // púrpura
    Color(0xFFB8860B), // oro viejo
    Color(0xFF6E1F35), // vino
    Color(0xFFB5561F), // cobre
    Color(0xFF2F6F6A), // verdigris
    Color(0xFF7A7A2B), // oliva
    Color(0xFF5A3B22), // corteza
    Color(0xFF4A5A6A), // pizarra
    Color(0xFF2D2E33), // sable (carbón)
  ];

  final int? id;
  final String name;
  final int colorValue;
  final String kind;
  final DateTime createdAt;

  // Datos de resumen; solo se llenan al listar los libros.

  /// Dinero disponible: del mes en curso (mensual) o saldo (cuenta).
  final double available;

  /// Renglones del mes (mensual) o movimientos (cuenta).
  final int entryCount;

  /// Renglones ya pagados del mes. Solo en libros mensuales.
  final int paidCount;

  const Book({
    this.id,
    required this.name,
    required this.colorValue,
    this.kind = BookKind.monthly,
    required this.createdAt,
    this.available = 0,
    this.entryCount = 0,
    this.paidCount = 0,
  });

  Color get color => Color(colorValue);

  bool get isLedger => kind == BookKind.ledger;

  Book withSummary({
    required double available,
    required int entryCount,
    int paidCount = 0,
  }) {
    return Book(
      id: id,
      name: name,
      colorValue: colorValue,
      kind: kind,
      createdAt: createdAt,
      available: available,
      entryCount: entryCount,
      paidCount: paidCount,
    );
  }

  /// Devuelve un mensaje de error si el nombre no es válido, o null si lo es.
  static String? validateName(String? value) {
    final name = value?.trim() ?? '';
    if (name.isEmpty) return 'Escribe un nombre para el libro';
    if (name.length > maxNameLength) {
      return 'Máximo $maxNameLength caracteres';
    }
    return null;
  }

  static String? validateKind(String? value) {
    return BookKind.values.contains(value) ? null : 'Tipo de libro no válido';
  }

  /// Fuerza el color a ser totalmente opaco.
  static int normalizeColor(int value) => (value & 0x00FFFFFF) | 0xFF000000;

  factory Book.fromMap(Map<String, Object?> map) {
    return Book(
      id: map['id'] as int?,
      name: map['name'] as String,
      colorValue: map['color'] as int,
      kind: map['kind'] as String? ?? BookKind.monthly,
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}
