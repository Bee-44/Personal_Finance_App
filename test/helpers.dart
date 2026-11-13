import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pennytree/models/month.dart';
import 'package:pennytree/models/movement.dart';
import 'package:pennytree/services/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Fábrica SQLite real (no simulada) que corre en el mismo hilo, para que
/// también funcione dentro de pruebas de widgets.
DatabaseFactory get testFactory {
  sqfliteFfiInit();
  return databaseFactoryFfiNoIsolate;
}

/// Base de datos nueva en memoria.
Future<AppDatabase> openMemoryDb() {
  return AppDatabase.open(testFactory, inMemoryDatabasePath);
}

/// Carpeta temporal para pruebas que necesitan un archivo real.
Future<String> tempDbPath() async {
  final dir = await Directory.systemTemp.createTemp('pennytree_test_');
  return p.join(dir.path, AppDatabase.fileName);
}

BudgetItem item(
  int periodId,
  String name,
  double amount, {
  bool recurring = true,
  bool paid = false,
  bool envelope = false,
  String method = 'bank',
}) {
  return BudgetItem(
    periodId: periodId,
    name: name,
    amount: amount,
    recurring: recurring,
    paid: paid,
    envelope: envelope,
    method: method,
  );
}

Income income(
  int periodId,
  String name,
  double amount, {
  bool recurring = true,
  String method = 'bank',
}) {
  return Income(
    periodId: periodId,
    name: name,
    amount: amount,
    recurring: recurring,
    method: method,
  );
}

Movement movement(
  int bookId,
  double amount, {
  String description = 'Movimiento',
  String method = 'bank',
  DateTime? date,
}) {
  return Movement(
    bookId: bookId,
    amount: amount,
    description: description,
    method: method,
    date: date ?? DateTime(2026, 1, 15),
  );
}
