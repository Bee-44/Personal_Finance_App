// Pruebas de seguridad: inyección SQL, validación de datos, integridad de
// la base de datos y ausencia de servicios en la nube.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pennytree/models/book.dart';
import 'package:pennytree/models/month.dart';
import 'package:pennytree/models/validation.dart';
import 'package:pennytree/services/app_database.dart';
import 'package:pennytree/utils/color_utils.dart';
import 'package:pennytree/utils/note_import.dart';

import 'helpers.dart';

const injections = [
  "'; DROP TABLE books; --",
  "x'); DELETE FROM items; --",
  "' OR '1'='1",
  '"; DROP TABLE movements; --',
  "Robert'); DROP TABLE periods;--",
  "1; UPDATE books SET name='hack'",
];

void main() {
  group('Inyección SQL', () {
    late AppDatabase db;
    late int bookId;
    late int periodId;
    late int ledgerId;

    setUp(() async {
      db = await openMemoryDb();
      bookId = (await db.getBooks()).single.id!;
      periodId = (await db.openPeriod(bookId, 2026, 3)).id!;
      await db.insertItem(item(periodId, 'Original', 10));
      ledgerId = await db.insertBook(
        name: 'Cuenta',
        color: 0xFF2E4A72,
        kind: BookKind.ledger,
      );
      await db.insertMovement(movement(ledgerId, 100, description: 'Inicial'));
    });
    tearDown(() => db.close());

    Future<void> expectIntact({int extraBooks = 0}) async {
      expect(await db.getBooks(), hasLength(2 + extraBooks));
      final names = (await db.getMonthData(periodId)).items.map((i) => i.name);
      expect(names, contains('Original'));
      final movements = await db.getMovements(ledgerId);
      expect(movements.map((m) => m.description), contains('Inicial'));
    }

    test('en el nombre del libro se guarda como texto literal', () async {
      for (final text in injections) {
        final id = await db.insertBook(name: text, color: 0xFF56692F);
        expect((await db.getBook(id))!.name, text);
      }
      await expectIntact(extraBooks: injections.length);
    });

    test('al editar un libro tampoco se ejecuta', () async {
      for (final text in injections) {
        await db.updateBook(bookId, name: text, color: 0xFF56692F);
        expect((await db.getBook(bookId))!.name, text);
      }
      await expectIntact();
    });

    test('en renglones e ingresos se guarda como texto', () async {
      for (final text in injections) {
        await db.insertItem(item(periodId, text, 5));
        await db.insertIncome(income(periodId, text, 5));
      }
      final data = await db.getMonthData(periodId);
      expect(data.items.map((i) => i.name), containsAll(injections));
      expect(data.incomes.map((i) => i.name), containsAll(injections));
      await expectIntact();
    });

    test('en movimientos de cuenta se guarda como texto', () async {
      for (final text in injections) {
        await db.insertMovement(movement(ledgerId, -1, description: text));
      }
      final saved = (await db.getMovements(ledgerId)).map((m) => m.description);
      expect(saved, containsAll(injections));
      await expectIntact();
    });

    test('en una lista pegada se guarda como texto', () async {
      final pasted = injections.map((t) => '[ ] 3 $t').join('\n');
      await db.importItems(periodId, parseChecklist(pasted));
      await db.importMovements(
        ledgerId,
        parseLedger(injections.map((t) => '- 3 $t').join('\n')),
      );
      final names = (await db.getMonthData(periodId)).items.map((i) => i.name);
      expect(names, containsAll(injections));
      await expectIntact();
    });

    test('la búsqueda de nombres repetidos no es manipulable', () async {
      expect(await db.bookNameExists("' OR '1'='1"), isFalse);
      expect(await db.bookNameExists("x' OR name LIKE '%"), isFalse);
      await expectIntact();
    });
  });

  group('Validación de datos', () {
    late AppDatabase db;
    late int bookId;
    late int periodId;

    setUp(() async {
      db = await openMemoryDb();
      bookId = (await db.getBooks()).single.id!;
      periodId = (await db.openPeriod(bookId, 2026, 3)).id!;
    });
    tearDown(() => db.close());

    test('rechaza nombres de libro vacíos o demasiado largos', () async {
      expect(Book.validateName(null), isNotNull);
      expect(Book.validateName(''), isNotNull);
      expect(Book.validateName('    '), isNotNull);
      expect(Book.validateName('a' * (Book.maxNameLength + 1)), isNotNull);
      expect(Book.validateName('a' * Book.maxNameLength), isNull);

      expect(() => db.insertBook(name: '  ', color: 0), throwsArgumentError);
      expect(
        () => db.insertBook(name: 'a' * 5000, color: 0),
        throwsArgumentError,
      );
      expect(
        () => db.updateBook(bookId, name: '', color: 0),
        throwsArgumentError,
      );
      expect(
        () => db.insertBook(name: 'Raro', color: 0, kind: 'otro'),
        throwsArgumentError,
      );
      expect(await db.getBooks(), hasLength(1));
    });

    test('rechaza montos no válidos', () async {
      for (final amount in [
        -1.0,
        -0.01,
        double.nan,
        double.infinity,
        double.negativeInfinity,
        maxMoney + 1,
      ]) {
        expect(validateMoney(amount), isNotNull, reason: '$amount');
        expect(
          () => db.insertItem(item(periodId, 'Luz', amount)),
          throwsArgumentError,
          reason: 'renglón $amount',
        );
        expect(
          () => db.insertIncome(income(periodId, 'Salario', amount)),
          throwsArgumentError,
          reason: 'ingreso $amount',
        );
        expect(
          () => db.addSpend(1, amount),
          throwsArgumentError,
          reason: 'gasto $amount',
        );
      }
      // Cero solo se acepta en renglones (monto por definir).
      expect(validateMoney(0), isNotNull);
      expect(validateMoney(0, allowZero: true), isNull);
      expect(
        () => db.insertIncome(income(periodId, 'Salario', 0)),
        throwsArgumentError,
      );
      expect(() => db.addSpend(1, 0), throwsArgumentError);
      expect(
        () => db.insertMovement(movement(bookId, 0)),
        throwsArgumentError,
      );
      expect(
        () => db.insertMovement(movement(bookId, double.nan)),
        throwsArgumentError,
      );
      expect(validateMoney(0.01), isNull);
      expect(validateMoney(maxMoney), isNull);

      final data = await db.getMonthData(periodId);
      expect(data.items, isEmpty);
      expect(data.incomes, isEmpty);
    });

    test('rechaza textos y métodos de pago no válidos', () async {
      expect(
        () => db.insertItem(item(periodId, '   ', 5)),
        throwsArgumentError,
      );
      expect(
        () => db.insertItem(item(periodId, 'x' * (maxTextLength + 1), 5)),
        throwsArgumentError,
      );
      expect(
        () => db.insertItem(item(periodId, 'Luz', 5, method: 'bitcoin')),
        throwsArgumentError,
      );
      expect(
        () => db.insertIncome(income(periodId, 'Pago', 5, method: 'card')),
        throwsArgumentError,
      );
      expect(
        () => db.insertMovement(movement(bookId, 5, description: '')),
        throwsArgumentError,
      );
      expect(
        () => db.updateItem(
          BudgetItem(id: 1, periodId: periodId, name: '', amount: 1),
        ),
        throwsArgumentError,
      );
      expect((await db.getMonthData(periodId)).items, isEmpty);
    });

    test('el texto de dinero se interpreta de forma segura', () {
      expect(parseMoney('12.50'), 12.5);
      expect(parseMoney(' 12,50 '), 12.5);
      expect(parseMoney(''), isNull);
      expect(parseMoney('abc'), isNull);
      expect(parseMoney('NaN'), isNull);
      expect(parseMoney('Infinity'), isNull);
      expect(parseMoney('1; DROP TABLE books'), isNull);
      expect(formatMoney(12.5), '\$12.50');
      expect(formatMoney(-12.5), '-\$12.50');
      expect(formatMoney(-0.001), '\$0.00');
    });

    test('el color siempre se guarda opaco', () async {
      final id = await db.insertBook(name: 'Color', color: 0x00123456);
      expect((await db.getBook(id))!.colorValue, 0xFF123456);
    });

    test('no acepta datos para un mes, renglón o libro inexistente', () async {
      expect(() => db.insertItem(item(987654, 'Luz', 5)), throwsA(anything));
      expect(
        () => db.insertIncome(income(987654, 'Salario', 5)),
        throwsA(anything),
      );
      expect(() => db.addSpend(987654, 5), throwsA(anything));
      expect(
        () => db.insertMovement(movement(987654, 5)),
        throwsA(anything),
      );
    });
  });

  group('Integridad a nivel de base de datos', () {
    // Aunque algún código futuro se salte las validaciones de Dart, las
    // restricciones del propio esquema SQL deben rechazar datos corruptos.
    test('las restricciones CHECK y de llave foránea están activas', () async {
      final path = await tempDbPath();
      final db = await AppDatabase.open(testFactory, path);
      final bookId = (await db.getBooks()).single.id!;
      final periodId = (await db.openPeriod(bookId, 2026, 3)).id!;
      final itemId = await db.insertItem(item(periodId, 'Luz', 5));
      await db.close();

      final raw = await testFactory.openDatabase(path);
      await raw.execute('PRAGMA foreign_keys = ON');
      final now = DateTime.now().millisecondsSinceEpoch;

      Future<void> mustFail(String table, Map<String, Object?> row) async {
        await expectLater(
          raw.insert(table, row),
          throwsA(anything),
          reason: '$table $row',
        );
      }

      Map<String, Object?> book(Map<String, Object?> changes) => {
        'name': 'Otro',
        'color': 1,
        'kind': 'monthly',
        'created_at': now,
        ...changes,
      };
      Map<String, Object?> entry(Map<String, Object?> changes) => {
        'period_id': periodId,
        'name': 'ok',
        'amount': 5.0,
        'method': 'bank',
        ...changes,
      };
      Map<String, Object?> move(Map<String, Object?> changes) => {
        'book_id': bookId,
        'amount': 5.0,
        'description': 'ok',
        'date': now,
        'method': 'bank',
        ...changes,
      };

      await mustFail('books', book({'name': ''}));
      await mustFail('books', book({'name': 'a' * 41}));
      await mustFail('books', book({'kind': 'otro'}));
      await mustFail('books', book({'name': 'personal'})); // repetido

      await mustFail('periods', {'book_id': bookId, 'year': 2026, 'month': 13});
      await mustFail('periods', {'book_id': bookId, 'year': 2026, 'month': 3});
      await mustFail('periods', {'book_id': 4242, 'year': 2026, 'month': 5});

      await mustFail('items', entry({'amount': -5.0}));
      await mustFail('items', entry({'name': '  '}));
      await mustFail('items', entry({'method': 'otro'}));
      await mustFail('items', entry({'paid': 2}));
      await mustFail('items', entry({'period_id': 4242}));

      await mustFail('incomes', entry({'amount': 0}));
      await mustFail('incomes', entry({'amount': -1}));
      await mustFail('incomes', entry({'recurring': 5}));

      await mustFail('spends', {
        'item_id': itemId,
        'amount': 0,
        'created_at': now,
      });
      await mustFail('spends', {'item_id': 4242, 'amount': 1, 'created_at': now});

      await mustFail('movements', move({'amount': 0}));
      await mustFail('movements', move({'description': ''}));
      await mustFail('movements', move({'method': 'card'}));
      await mustFail('movements', move({'book_id': 4242}));

      // Los registros válidos sí entran.
      await raw.insert('items', entry({}));
      await raw.insert('incomes', entry({}));
      await raw.insert('movements', move({'amount': -5.0}));
      expect(await raw.query('items'), hasLength(2));
      await raw.close();
    });
  });

  group('Sin servicios en la nube', () {
    String read(String path) => File(path).readAsStringSync();

    test('no quedan dependencias ni configuración de Firebase', () {
      final pubspec = read('pubspec.yaml').toLowerCase();
      for (final banned in ['firebase', 'firestore', 'http:', 'dio:']) {
        expect(pubspec.contains(banned), isFalse, reason: banned);
      }
      expect(File('android/app/google-services.json').existsSync(), isFalse);
      expect(File('lib/firebase_options.dart').existsSync(), isFalse);
      expect(File('firebase.json').existsSync(), isFalse);

      final gradle =
          read('android/app/build.gradle.kts') +
          read('android/build.gradle.kts') +
          read('android/settings.gradle.kts');
      expect(gradle.toLowerCase().contains('firebase'), isFalse);
      expect(gradle.toLowerCase().contains('google-services'), isFalse);
    });

    test('el código de la app no usa red ni claves de API', () {
      final sources = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      expect(sources, isNotEmpty);
      final banned = RegExp(
        r'firebase|firestore|http://|https://|HttpClient|Socket|apiKey|AIza',
        caseSensitive: false,
      );
      for (final file in sources) {
        expect(
          banned.hasMatch(file.readAsStringSync()),
          isFalse,
          reason: file.path,
        );
      }
    });

    test('la app Android no pide internet ni respalda datos fuera', () {
      final manifest = read('android/app/src/main/AndroidManifest.xml');
      expect(manifest.contains('android.permission.INTERNET'), isFalse);
      expect(manifest.contains('android:allowBackup="false"'), isTrue);
      expect(manifest.contains('usesCleartextTraffic="true"'), isFalse);
    });
  });
}
