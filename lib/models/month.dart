import 'validation.dart';

const List<String> _monthNames = [
  'Enero', 'Febrero', 'Marzo', 'Abril', 'Mayo', 'Junio', //
  'Julio', 'Agosto', 'Septiembre', 'Octubre', 'Noviembre', 'Diciembre',
];

/// La hoja de un mes dentro de un libro mensual.
class Period {
  final int? id;
  final int bookId;
  final int year;
  final int month;

  const Period({
    this.id,
    required this.bookId,
    required this.year,
    required this.month,
  });

  /// Número que crece con el tiempo; sirve para comparar meses.
  int get index => year * 12 + (month - 1);

  static int indexOf(int year, int month) => year * 12 + (month - 1);

  String get label => '${_monthNames[month - 1]} $year';

  factory Period.fromMap(Map<String, Object?> map) {
    return Period(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      year: map['year'] as int,
      month: map['month'] as int,
    );
  }
}

/// Dinero que entra en el mes (salario, un extra...).
class Income {
  final int? id;
  final int periodId;
  final String name;
  final double amount;
  final String method;

  /// Si se copia al mes siguiente.
  final bool recurring;

  const Income({
    this.id,
    required this.periodId,
    required this.name,
    required this.amount,
    this.method = PayMethod.bank,
    this.recurring = true,
  });

  Map<String, Object?> toMap() => {
    'period_id': periodId,
    'name': name.trim(),
    'amount': amount,
    'method': method,
    'recurring': recurring ? 1 : 0,
  };

  factory Income.fromMap(Map<String, Object?> map) {
    return Income(
      id: map['id'] as int?,
      periodId: map['period_id'] as int,
      name: map['name'] as String,
      amount: (map['amount'] as num).toDouble(),
      method: map['method'] as String,
      recurring: map['recurring'] == 1,
    );
  }
}

/// Un gasto parcial anotado en un fondo.
class Spend {
  final int? id;
  final int itemId;
  final double amount;
  final DateTime createdAt;

  const Spend({
    this.id,
    required this.itemId,
    required this.amount,
    required this.createdAt,
  });

  factory Spend.fromMap(Map<String, Object?> map) {
    return Spend(
      id: map['id'] as int?,
      itemId: map['item_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
    );
  }
}

/// Un renglón de la lista del mes.
///
/// Hay dos clases:
/// - Pago fijo: se descuenta completo al marcarlo como pagado.
/// - Fondo ([envelope]): un monto apartado que se va gastando de a poco;
///   se descuenta lo gastado, y al marcarlo se da por cerrado.
class BudgetItem {
  final int? id;
  final int periodId;
  final String name;
  final double amount;
  final String method;

  /// Si se copia (sin marcar) al mes siguiente.
  final bool recurring;
  final bool paid;
  final bool envelope;
  final int position;
  final List<Spend> spends;

  const BudgetItem({
    this.id,
    required this.periodId,
    required this.name,
    required this.amount,
    this.method = PayMethod.bank,
    this.recurring = true,
    this.paid = false,
    this.envelope = false,
    this.position = 0,
    this.spends = const [],
  });

  /// Total de los gastos parciales.
  double get spent => spends.fold(0, (sum, s) => sum + s.amount);

  /// Lo que este renglón ya restó del dinero disponible.
  double get deducted => envelope ? spent : (paid ? amount : 0);

  /// Lo que todavía falta por salir.
  double get pending {
    if (paid) return 0;
    if (!envelope) return amount;
    final left = amount - spent;
    return left > 0 ? left : 0;
  }

  /// Lo que queda en el fondo (negativo si se pasó).
  double get remaining => amount - spent;

  Map<String, Object?> toMap() => {
    'period_id': periodId,
    'name': name.trim(),
    'amount': amount,
    'method': method,
    'recurring': recurring ? 1 : 0,
    'paid': paid ? 1 : 0,
    'envelope': envelope ? 1 : 0,
    'position': position,
  };

  factory BudgetItem.fromMap(
    Map<String, Object?> map, {
    List<Spend> spends = const [],
  }) {
    return BudgetItem(
      id: map['id'] as int?,
      periodId: map['period_id'] as int,
      name: map['name'] as String,
      amount: (map['amount'] as num).toDouble(),
      method: map['method'] as String,
      recurring: map['recurring'] == 1,
      paid: map['paid'] == 1,
      envelope: map['envelope'] == 1,
      position: map['position'] as int,
      spends: spends,
    );
  }
}

/// Todo lo de un mes, con sus totales.
class MonthData {
  final Period period;
  final List<Income> incomes;
  final List<BudgetItem> items;

  /// Sobrante de los meses anteriores que llegó en banco. Puede ser
  /// negativo si se gastó de más.
  final double carryBank;

  /// Sobrante de los meses anteriores que llegó en efectivo.
  final double carryCash;

  const MonthData({
    required this.period,
    required this.incomes,
    required this.items,
    this.carryBank = 0,
    this.carryCash = 0,
  });

  /// Sobrante arrastrado de los meses anteriores.
  double get carryIn => carryBank + carryCash;

  double get totalIncome => incomes.fold(0, (sum, i) => sum + i.amount);

  /// Lo ya pagado o gastado.
  double get deducted => items.fold(0, (sum, i) => sum + i.deducted);

  /// Dinero que queda: sobrante anterior más ingresos, menos lo gastado.
  /// Al cerrar el mes, este es el sobrante que pasa al siguiente.
  double get available => carryIn + totalIncome - deducted;

  /// Estado del mes según el calendario.
  MonthStatus statusAt(DateTime today) {
    final current = Period.indexOf(today.year, today.month);
    if (period.index < current) return MonthStatus.closed;
    return period.index == current ? MonthStatus.open : MonthStatus.upcoming;
  }

  /// Lo que falta por pagar de la lista.
  double get pending => items.fold(0, (sum, i) => sum + i.pending);

  /// Lo que sobrará después de pagar todo lo pendiente.
  double get free => available - pending;

  int get paidCount => items.where((i) => i.paid).length;

  /// Dinero que queda en banco o en efectivo.
  double availableBy(String method) {
    final income = incomes
        .where((i) => i.method == method)
        .fold(0.0, (sum, i) => sum + i.amount);
    final out = items
        .where((i) => i.method == method)
        .fold(0.0, (sum, i) => sum + i.deducted);
    final carry = method == PayMethod.cash ? carryCash : carryBank;
    return carry + income - out;
  }
}

/// Estado de una hoja mensual. Lo decide el calendario, no el usuario.
enum MonthStatus {
  /// Mes pasado: solo lectura; su sobrante ya pasó al siguiente.
  closed,

  /// El mes en curso.
  open,

  /// Mes futuro, preparado por adelantado.
  upcoming,
}
