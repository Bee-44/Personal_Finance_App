/// Respaldo de todos los libros en un archivo de texto legible.
///
/// El mismo formato sirve para exportar, para importar en otro dispositivo y
/// para cargar listas escritas a mano en una app de notas:
///
///     # Casa
///     tipo: mensual
///     color: 56692F
///     == 2026-11
///     + 900 Salario
///     + 50 Extra #unavez
///     [ ] 300 Súper ( -120 - 30 = 150 )
///     [v] 75 Préstamo #efectivo
///
///     # Ahorros
///     tipo: cuenta
///     2026-09-02 + 250 Abono
///     2026-09-05 - 40 Compra #efectivo
///
/// Solo `# Nombre` es obligatorio. Si falta `tipo:`, un libro con casillas
/// es mensual y uno con solo líneas `+`/`-` es una cuenta. Si falta `==`,
/// los renglones van al mes en curso. Lo que no se reconoce se ignora.
library;

import '../models/book.dart';
import '../models/validation.dart';
import 'note_import.dart';

class BackupMonth {
  /// Null: el mes en curso al momento de importar.
  final int? year;
  final int? month;
  final List<ParsedMovement> incomes = [];
  final List<ParsedItem> items = [];

  BackupMonth({this.year, this.month});

  bool get isEmpty => incomes.isEmpty && items.isEmpty;
}

class BackupBook {
  final String name;
  String kind;

  /// Null: se asigna un color de la paleta al importar.
  int? color;
  final List<BackupMonth> months = [];
  final List<ParsedMovement> movements = [];

  BackupBook({required this.name, this.kind = BookKind.monthly, this.color});
}

class BackupData {
  final List<BackupBook> books;

  /// Líneas con texto que no se reconocieron.
  final int ignoredLines;

  const BackupData({required this.books, this.ignoredLines = 0});

  int get itemCount => books.fold(
    0,
    (sum, b) => sum + b.months.fold(0, (s, m) => s + m.items.length),
  );

  int get incomeCount => books.fold(
    0,
    (sum, b) => sum + b.months.fold(0, (s, m) => s + m.incomes.length),
  );

  int get movementCount => books.fold(0, (sum, b) => sum + b.movements.length);

  bool get isEmpty => books.isEmpty;
}

final _bookHeader = RegExp(r'^\s*#(?!#)\s*(.+?)\s*$');
final _monthHeader = RegExp(r'^\s*==\s*(\d{4})-(\d{1,2})\s*$');
final _kindLine = RegExp(r'^\s*tipo\s*:\s*(\S+)\s*$', caseSensitive: false);
final _colorLine = RegExp(
  r'^\s*color\s*:\s*#?([0-9a-fA-F]{6})\s*$',
  caseSensitive: false,
);

/// Lee un archivo de respaldo o una nota con encabezados `# Nombre`.
BackupData parseBackup(String text) {
  final books = <BackupBook>[];
  var ignored = 0;
  BackupBook? book;
  BackupMonth? month;
  // Tipo declarado con `tipo:`; si falta, se deduce del contenido.
  final declared = <BackupBook>{};
  // Líneas con signo leídas antes de saber si el libro es mensual o cuenta.
  final signed = <BackupBook, List<(BackupMonth?, ParsedMovement)>>{};

  // Quita la marca de orden de bytes y unifica saltos de línea.
  final clean = text.replaceAll('﻿', '').replaceAll('\r', '');

  for (final line in clean.split('\n')) {
    if (line.trim().isEmpty) continue;

    final header = _bookHeader.firstMatch(line);
    if (header != null) {
      final name = clipText(header.group(1)!, max: Book.maxNameLength);
      if (name.isEmpty) {
        ignored++;
        continue;
      }
      book = BackupBook(name: name);
      books.add(book);
      month = null;
      continue;
    }

    if (book == null) {
      ignored++; // texto antes del primer libro
      continue;
    }

    final kind = _kindLine.firstMatch(line);
    if (kind != null) {
      final value = kind.group(1)!.toLowerCase();
      if (value == 'cuenta' || value == BookKind.ledger) {
        book.kind = BookKind.ledger;
        declared.add(book);
      } else if (value == 'mensual' || value == BookKind.monthly) {
        book.kind = BookKind.monthly;
        declared.add(book);
      } else {
        ignored++;
      }
      continue;
    }

    final color = _colorLine.firstMatch(line);
    if (color != null) {
      book.color = 0xFF000000 | int.parse(color.group(1)!, radix: 16);
      continue;
    }

    final monthMatch = _monthHeader.firstMatch(line);
    if (monthMatch != null) {
      final m = int.parse(monthMatch.group(2)!);
      final y = int.parse(monthMatch.group(1)!);
      if (m < 1 || m > 12 || y < 2000 || y > 2200) {
        ignored++;
        month = null;
      } else {
        month = BackupMonth(year: y, month: m);
        book.months.add(month);
      }
      continue;
    }

    final item = parseItemLine(line);
    if (item != null) {
      if (month == null) {
        month = BackupMonth();
        book.months.add(month);
      }
      month.items.add(item);
      continue;
    }

    final movement = parseMovementLine(line);
    if (movement != null) {
      signed.putIfAbsent(book, () => []).add((month, movement));
      continue;
    }

    ignored++;
  }

  // Reparte las líneas con signo según el tipo de cada libro.
  for (final book in books) {
    final lines = signed[book] ?? const [];
    if (!declared.contains(book)) {
      final hasChecklist = book.months.any((m) => m.items.isNotEmpty);
      book.kind = hasChecklist || lines.isEmpty
          ? BookKind.monthly
          : BookKind.ledger;
    }
    if (book.kind == BookKind.ledger) {
      // Una cuenta no tiene meses ni casillas.
      ignored += book.months.fold(0, (sum, m) => sum + m.items.length);
      book.months.clear();
      book.movements.addAll(lines.map((entry) => entry.$2));
    } else {
      for (final (target, movement) in lines) {
        if (movement.amount < 0) {
          ignored++; // en un libro mensual los gastos van con casilla
          continue;
        }
        var month = target;
        if (month == null) {
          // Ingresos escritos antes de cualquier `==`: mes en curso.
          month = book.months.where((m) => m.year == null).firstOrNull;
          if (month == null) {
            month = BackupMonth();
            book.months.insert(0, month);
          }
        }
        month.incomes.add(movement);
      }
      book.months.removeWhere((m) => m.isEmpty && m.year == null);
    }
  }

  return BackupData(books: books, ignoredLines: ignored);
}

String _amount(double value) {
  final fixed = value.toStringAsFixed(2);
  return fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
}

String _two(int value) => value.toString().padLeft(2, '0');

String _tags({required String method, bool recurring = true}) {
  return '${method == PayMethod.cash ? ' $cashTag' : ''}'
      '${recurring ? '' : ' $onceTag'}';
}

/// Escribe el respaldo como texto. [now] se anota en la primera línea.
String formatBackup(BackupData data, {DateTime? now}) {
  final when = now ?? DateTime.now();
  final out = StringBuffer()
    ..writeln(
      'PennyTree - respaldo del '
      '${when.year}-${_two(when.month)}-${_two(when.day)}',
    )
    ..writeln(
      'Para restaurarlo: Mis Libros > menú > Importar archivo de texto.',
    );

  for (final book in data.books) {
    out
      ..writeln()
      ..writeln('# ${book.name}')
      ..writeln(
        'tipo: ${book.kind == BookKind.ledger ? 'cuenta' : 'mensual'}',
      );
    final color = book.color;
    if (color != null) {
      final hex = (color & 0xFFFFFF).toRadixString(16).padLeft(6, '0');
      out.writeln('color: ${hex.toUpperCase()}');
    }

    for (final month in book.months) {
      if (month.year != null) {
        out.writeln('== ${month.year}-${_two(month.month!)}');
      }
      for (final income in month.incomes) {
        out.writeln(
          '+ ${_amount(income.amount)} ${income.description}'
          '${_tags(method: income.method, recurring: income.recurring)}',
        );
      }
      for (final item in month.items) {
        final spent = item.spends.fold(0.0, (sum, s) => sum + s);
        final fund = !item.envelope
            ? ''
            : ' ('
                '${item.spends.map((s) => ' -${_amount(s)}').join()}'
                ' = ${_amount(item.amount - spent)} )';
        out.writeln(
          '[${item.checked ? 'v' : ' '}] ${_amount(item.amount)} '
          '${item.name}$fund'
          '${_tags(method: item.method, recurring: item.recurring)}',
        );
      }
    }

    for (final movement in book.movements) {
      final date = movement.date;
      final prefix = date == null
          ? ''
          : '${date.year}-${_two(date.month)}-${_two(date.day)} ';
      out.writeln(
        '$prefix${movement.amount < 0 ? '-' : '+'} '
        '${_amount(movement.amount.abs())} ${movement.description}'
        '${_tags(method: movement.method)}',
      );
    }
  }
  return out.toString();
}

/// Resultado de una importación.
class ImportSummary {
  final int booksCreated;
  final int booksUpdated;
  final int items;
  final int incomes;
  final int movements;

  const ImportSummary({
    required this.booksCreated,
    required this.booksUpdated,
    required this.items,
    required this.incomes,
    required this.movements,
  });
}
