/// Convierte listas escritas a mano (por ejemplo, en una app de notas) en
/// renglones o movimientos, para no tener que teclearlos uno por uno.
library;

import '../models/validation.dart';

/// Un renglón leído de una lista con casillas.
class ParsedItem {
  final String name;
  final double amount;
  final bool checked;

  /// Verdadero si el renglón traía un paréntesis de gastos parciales.
  final bool envelope;
  final List<double> spends;
  final String method;
  final bool recurring;

  const ParsedItem({
    required this.name,
    required this.amount,
    required this.checked,
    this.envelope = false,
    this.spends = const [],
    this.method = PayMethod.bank,
    this.recurring = true,
  });
}

/// Un abono o retiro leído de una línea con signo. En un libro mensual,
/// una línea con `+` es un ingreso.
class ParsedMovement {
  final String description;

  /// Con signo.
  final double amount;
  final String method;

  /// Fecha escrita al inicio de la línea, si la había.
  final DateTime? date;

  /// Falso si la línea traía la etiqueta `#unavez` (solo para ingresos).
  final bool recurring;

  const ParsedMovement({
    required this.description,
    required this.amount,
    this.method = PayMethod.bank,
    this.date,
    this.recurring = true,
  });
}

// Etiquetas opcionales al final de una línea.
const String cashTag = '#efectivo';
const String onceTag = '#unavez';

final _checkbox = RegExp(r'^\s*\[\s*([^\]\s]?)\s*\]\s*(.*)$');
final _leadingAmount = RegExp(r'^\$?\s*(\d+(?:[.,]\d{1,2})?)(?!\d)\s*(.*)$');
// Solo cuenta como paréntesis de gastos si contiene únicamente números y
// signos, y al menos un `-` o un `=`; así nombres como "Renta (atrasada)" o
// "Cuota (2)" se quedan enteros.
final _spendsParenthesis = RegExp(r'\((?=[^)]*[\-=])([\s\d.,=+\-$]*)\)');
final _minusNumber = RegExp(r'-\s*\$?\s*(\d+(?:[.,]\d{1,2})?)');
final _signed = RegExp(
  r'^\s*(?:(\d{4})-(\d{1,2})-(\d{1,2})\s+)?'
  r'([+\-*])\s*\$?\s*(\d+(?:[.,]\d{1,2})?)(?!\d)\s*(.*)$',
);
final _tag = RegExp(r'(?:^|\s)#(efectivo|unavez)(?=\s|$)', caseSensitive: false);

double? _number(String text) {
  final value = double.tryParse(text.replaceAll(',', '.'));
  if (value == null || value.isNaN || value.isInfinite || value > maxMoney) {
    return null;
  }
  return value;
}

/// Limpia un texto y lo recorta al largo máximo permitido.
String clipText(String text, {int max = maxTextLength}) {
  final clean = text.replaceAll(RegExp(r'[\x00-\x1F\x7F]'), ' ').trim();
  return clean.length > max ? clean.substring(0, max).trim() : clean;
}

/// Separa las etiquetas del resto de la línea.
({String text, bool cash, bool once}) _takeTags(String text) {
  var cash = false;
  var once = false;
  final rest = text.replaceAllMapped(_tag, (m) {
    if (m.group(1)!.toLowerCase() == 'efectivo') {
      cash = true;
    } else {
      once = true;
    }
    return ' ';
  });
  return (text: rest.trim(), cash: cash, once: once);
}

/// Lee un renglón con casilla, o devuelve null si la línea no lo es.
///
///     [ ] 350 super ( -130 - 16 = 204 )
///     [v] 82 préstamo #efectivo
///     [ ] Ahorro
///
/// La casilla con cualquier marca cuenta como pagado. El número inicial es
/// el monto (0 si falta). Un paréntesis de números indica un fondo; los que
/// llevan signo menos antes del `=` son sus gastos parciales. `#efectivo`
/// indica que se paga en efectivo y `#unavez` que no se repite cada mes.
ParsedItem? parseItemLine(String line) {
  final box = _checkbox.firstMatch(line);
  if (box == null) return null;
  final checked = box.group(1)!.isNotEmpty;
  final tags = _takeTags(box.group(2)!.trim());
  var rest = tags.text;

  // Gastos parciales entre paréntesis.
  var envelope = false;
  final spends = <double>[];
  final paren = _spendsParenthesis.firstMatch(rest);
  if (paren != null) {
    envelope = true;
    final inside = paren.group(1)!.split('=').first;
    for (final m in _minusNumber.allMatches(inside)) {
      final value = _number(m.group(1)!);
      if (value != null && value > 0) spends.add(value);
    }
    rest = rest.replaceRange(paren.start, paren.end, ' ').trim();
  }

  var amount = 0.0;
  final lead = _leadingAmount.firstMatch(rest);
  if (lead != null) {
    amount = _number(lead.group(1)!) ?? 0;
    rest = lead.group(2)!;
  }

  var name = clipText(rest);
  while (name.endsWith(':')) {
    name = name.substring(0, name.length - 1).trim();
  }
  if (name.isEmpty) return null;

  return ParsedItem(
    name: name,
    amount: amount,
    checked: checked,
    envelope: envelope,
    spends: spends,
    method: tags.cash ? PayMethod.cash : PayMethod.bank,
    recurring: !tags.once,
  );
}

/// Lee una línea con signo, o devuelve null si la línea no lo es.
///
///     + 300 abono
///     - 75 renta #efectivo
///     * 1080 fondo inicial
///     2026-09-02 + 300 abono
///
/// `+` y `*` suman y `-` resta. La fecha al inicio es opcional.
ParsedMovement? parseMovementLine(String line) {
  final match = _signed.firstMatch(line);
  if (match == null) return null;
  final value = _number(match.group(5)!);
  if (value == null || value <= 0) return null;

  DateTime? date;
  if (match.group(1) != null) {
    final year = int.parse(match.group(1)!);
    final month = int.parse(match.group(2)!);
    final day = int.parse(match.group(3)!);
    final parsed = DateTime(year, month, day);
    // Rechaza fechas imposibles como 2026-02-31.
    if (year >= 2000 &&
        year <= 2200 &&
        parsed.month == month &&
        parsed.day == day) {
      date = parsed;
    }
  }

  final tags = _takeTags(match.group(6)!);
  final description = clipText(tags.text);
  return ParsedMovement(
    description: description.isEmpty ? 'Movimiento' : description,
    amount: match.group(4) == '-' ? -value : value,
    method: tags.cash ? PayMethod.cash : PayMethod.bank,
    date: date,
    recurring: !tags.once,
  );
}

/// Lee todos los renglones con casilla de un texto, uno por línea.
/// Las líneas que no empiezan con una casilla se ignoran.
List<ParsedItem> parseChecklist(String text) {
  return [
    for (final line in text.split('\n'))
      if (parseItemLine(line) case final item?) item,
  ];
}

/// Lee todos los abonos y retiros de un texto, uno por línea.
/// Las líneas sin signo se ignoran.
List<ParsedMovement> parseLedger(String text) {
  return [
    for (final line in text.split('\n'))
      if (parseMovementLine(line) case final movement?) movement,
  ];
}
