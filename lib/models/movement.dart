import 'validation.dart';

/// Un abono (+) o un retiro (−) en un libro de tipo cuenta.
class Movement {
  final int? id;
  final int bookId;

  /// Con signo: positivo es abono, negativo es retiro. Nunca cero.
  final double amount;
  final String description;
  final DateTime date;
  final String method;

  const Movement({
    this.id,
    required this.bookId,
    required this.amount,
    required this.description,
    required this.date,
    this.method = PayMethod.bank,
  });

  bool get isIncome => amount > 0;

  Map<String, Object?> toMap() => {
    'book_id': bookId,
    'amount': amount,
    'description': description.trim(),
    'date': date.millisecondsSinceEpoch,
    'method': method,
  };

  factory Movement.fromMap(Map<String, Object?> map) {
    return Movement(
      id: map['id'] as int?,
      bookId: map['book_id'] as int,
      amount: (map['amount'] as num).toDouble(),
      description: map['description'] as String,
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] as int),
      method: map['method'] as String,
    );
  }
}
