// Pruebas de exportar e importar todos los libros como archivo de texto.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennytree/models/book.dart';
import 'package:pennytree/screens/books_screen.dart';
import 'package:pennytree/services/app_database.dart';
import 'package:pennytree/services/backup_files.dart';
import 'package:pennytree/theme/app_theme.dart';
import 'package:pennytree/utils/backup.dart';
import 'package:pennytree/utils/note_import.dart';

import 'helpers.dart';

/// Una nota escrita a mano: solo encabezados y listas, sin `tipo:` ni mes.
const handwritten = r'''
Mis cuentas de este mes

# Casa
Salario: $900 + 50
+ 900 Salario
+ 50 Extra #unavez
[  ] Ahorro
[  ] 300 súper ( -120 - 30 = 150 )
[v] 75 préstamo
[v] 18 regalo #unavez
[  ] 20 jardín #efectivo
Restante: $ 60

# Ahorros
$700.25 disponible
* 1000 fondo inicial
+ 250 abono 2 marzo
- 400 reparación techo #efectivo
''';

final today = DateTime(2026, 3, 15);

void main() {
  group('Lectura del archivo', () {
    final data = parseBackup(handwritten);

    test('cada # inicia un libro y su tipo se deduce del contenido', () {
      expect(data.books.map((b) => b.name), ['Casa', 'Ahorros']);
      expect(data.books[0].kind, BookKind.monthly); // tiene casillas
      expect(data.books[1].kind, BookKind.ledger); // solo + y -
    });

    test('en un libro mensual, + es ingreso y [ ] es renglón', () {
      final month = data.books[0].months.single;
      expect(month.year, isNull); // sin ==: va al mes en curso
      expect(month.incomes.map((i) => i.description), ['Salario', 'Extra']);
      expect(month.incomes.map((i) => i.amount), [900, 50]);
      expect(month.incomes.map((i) => i.recurring), [true, false]);
      expect(month.items.map((i) => i.name), [
        'Ahorro',
        'súper',
        'préstamo',
        'regalo',
        'jardín',
      ]);
      expect(month.items[1].spends, [120, 30]);
      expect(month.items[3].recurring, isFalse);
      expect(month.items[4].method, 'cash');
    });

    test('en una cuenta, + y * abonan y - retira', () {
      final movements = data.books[1].movements;
      expect(movements.map((m) => m.amount), [1000, 250, -400]);
      expect(movements.last.method, 'cash');
      expect(movements.last.description, 'reparación techo');
    });

    test('cuenta las líneas que no reconoce', () {
      // Título, "Salario: ...", "Restante: ..." y "$700.25 disponible".
      expect(data.ignoredLines, 4);
      expect(data.itemCount, 5);
      expect(data.incomeCount, 2);
      expect(data.movementCount, 3);
    });

    test('respeta tipo, color y meses cuando vienen escritos', () {
      final parsed = parseBackup('''
# Negocio
tipo: mensual
color: 8C2B23
== 2026-01
+ 500 Ventas
== 2026-02
[v] 40 Insumos
== 2026-13
[ ] 1 mes imposible

# Caja
tipo: cuenta
color: #2E4A72
2026-02-28 + 10 Depósito
2026-02-31 - 5 fecha imposible
''');
      final business = parsed.books[0];
      expect(business.kind, BookKind.monthly);
      expect(business.color, 0xFF8C2B23);
      expect(business.months.map((m) => '${m.year}-${m.month}'), [
        '2026-1',
        '2026-2',
        'null-null', // lo que seguía al mes imposible va al mes en curso
      ]);
      expect(business.months[0].incomes.single.amount, 500);
      expect(business.months[1].items.single.checked, isTrue);

      final cash = parsed.books[1];
      expect(cash.kind, BookKind.ledger);
      expect(cash.color, 0xFF2E4A72);
      expect(cash.movements.first.date, DateTime(2026, 2, 28));
      expect(cash.movements.last.date, isNull); // se usará la fecha de hoy
      expect(parsed.ignoredLines, 1); // "== 2026-13"
    });

    test('un libro mensual sin casillas necesita decir su tipo', () {
      final declared = parseBackup('# Sueldo\ntipo: mensual\n+ 900 Salario');
      expect(declared.books.single.kind, BookKind.monthly);
      expect(declared.incomeCount, 1);

      final inferred = parseBackup('# Sueldo\n+ 900 Salario');
      expect(inferred.books.single.kind, BookKind.ledger);
      expect(inferred.movementCount, 1);
    });

    test('los paréntesis del nombre no se confunden con un fondo', () {
      final items = parseChecklist(
        '[ ] 50 Cuota (2)\n[ ] 700 Renta (atrasada)\n[ ] 40 Mascota ( = )',
      );
      expect(items.map((i) => i.name), [
        'Cuota (2)',
        'Renta (atrasada)',
        'Mascota',
      ]);
      expect(items.map((i) => i.envelope), [false, false, true]);
    });

    test('sin encabezados no hay libros', () {
      expect(parseBackup('').isEmpty, isTrue);
      expect(parseBackup('[ ] 5 algo\n+ 3 otro').isEmpty, isTrue);
      expect(parseBackup('#\n#   \n## no es libro').isEmpty, isTrue);
    });

    test('acepta archivos de Windows y con marca de orden de bytes', () {
      final parsed = parseBackup('﻿# Casa\r\n[v] 5 Luz\r\n');
      expect(parsed.books.single.name, 'Casa');
      expect(parsed.books.single.months.single.items.single.name, 'Luz');
    });
  });

  group('Importar', () {
    late AppDatabase db;
    setUp(() async => db = await openMemoryDb());
    tearDown(() => db.close());

    test('crea los libros de una nota escrita a mano', () async {
      final summary = await db.importBackup(
        parseBackup(handwritten),
        now: today,
      );
      expect(summary.booksCreated, 2);
      expect(summary.booksUpdated, 0);
      expect(summary.items, 5);
      expect(summary.incomes, 2);
      expect(summary.movements, 3);

      final books = await db.getBooks(now: today);
      expect(books.map((b) => b.name), ['Personal', 'Casa', 'Ahorros']);

      final house = books[1];
      final period = (await db.getPeriods(house.id!)).single;
      expect(period.label, 'Marzo 2026'); // el mes en curso
      final data = await db.getMonthData(period.id!);
      expect(data.totalIncome, 950);
      // Pagados: 75 + 18; gastado del fondo: 150.
      expect(data.available, 707);
      expect(data.items[1].remaining, 150);
      expect(data.paidCount, 2);
      expect(house.available, 707);

      final savings = books[2];
      expect(savings.isLedger, isTrue);
      expect(savings.available, 850);
      expect(
        (await db.getMovements(savings.id!)).every((m) => m.date == today),
        isTrue,
      );
    });

    test('agrega a un libro existente sin borrar lo que tenía', () async {
      final personal = (await db.getBooks()).single;
      final period = await db.openPeriod(personal.id!, 2026, 3);
      await db.insertItem(item(period.id!, 'Luz', 20, paid: true));

      final summary = await db.importBackup(
        parseBackup('# personal\n[ ] 30 Agua\n[v] 10 Gas'),
        now: today,
      );
      expect(summary.booksCreated, 0);
      expect(summary.booksUpdated, 1);

      expect(await db.getBooks(), hasLength(1));
      final names = (await db.getMonthData(period.id!)).items.map((i) => i.name);
      expect(names, ['Luz', 'Agua', 'Gas']); // en orden, sin duplicar el mes
    });

    test('si el nombre existe con otro tipo, crea un libro aparte', () async {
      await db.importBackup(parseBackup('# Personal\n+ 5 Abono'), now: today);
      await db.importBackup(parseBackup('# Personal\n+ 7 Otro'), now: today);

      final books = await db.getBooks();
      expect(books.map((b) => b.name), ['Personal', 'Personal (2)']);
      expect(books[0].kind, BookKind.monthly);
      expect(books[1].isLedger, isTrue);
      expect(books[1].entryCount, 2); // el segundo se agregó a "Personal (2)"
    });

    test('un mes nuevo copia los recurrentes de un mes importado', () async {
      await db.importBackup(
        parseBackup('# Casa\n== 2026-02\n+ 900 Salario\n[v] 75 Préstamo\n'
            '[v] 18 Regalo #unavez'),
        now: today,
      );
      final house = (await db.getBooks()).last;
      final march = await db.openPeriod(house.id!, 2026, 3);
      final data = await db.getMonthData(march.id!);
      expect(data.items.single.name, 'Préstamo');
      expect(data.items.single.paid, isFalse);
      expect(data.totalIncome, 900);
    });

    test('si un dato no es válido, no se guarda nada', () async {
      final bad = BackupData(
        books: [
          BackupBook(name: 'Bueno', kind: BookKind.ledger)
            ..movements.add(
              const ParsedMovement(description: 'ok', amount: 5),
            ),
          BackupBook(name: 'Malo', kind: BookKind.ledger)
            ..movements.add(
              const ParsedMovement(description: 'cero', amount: 0),
            ),
        ],
      );
      await expectLater(db.importBackup(bad), throwsArgumentError);
      expect((await db.getBooks()).map((b) => b.name), ['Personal']);
    });

    test('el texto malicioso se guarda como texto', () async {
      await db.importBackup(
        parseBackup(
          "# Libro'; DROP TABLE books; --\n"
          "[ ] 5 x'); DELETE FROM items; --\n"
          "# Cuenta\n- 3 '; DROP TABLE movements; --",
        ),
        now: today,
      );
      final books = await db.getBooks(now: today);
      expect(books, hasLength(3));
      expect(books[1].name, "Libro'; DROP TABLE books; --");
      final period = (await db.getPeriods(books[1].id!)).single;
      expect(
        (await db.getMonthData(period.id!)).items.single.name,
        "x'); DELETE FROM items; --",
      );
      expect(
        (await db.getMovements(books[2].id!)).single.description,
        "'; DROP TABLE movements; --",
      );
    });
  });

  group('Exportar', () {
    /// Llena una base con un poco de todo.
    Future<void> fill(AppDatabase db) async {
      final personal = (await db.getBooks()).single;
      final feb = await db.openPeriod(personal.id!, 2026, 2);
      await db.insertIncome(income(feb.id!, 'Salario', 900));
      await db.insertIncome(
        income(feb.id!, 'Venta', 50.25, recurring: false, method: 'cash'),
      );
      await db.insertItem(item(feb.id!, 'Ahorro', 0));
      final fund = await db.insertItem(
        item(feb.id!, 'Súper', 300, envelope: true),
      );
      await db.addSpend(fund, 120);
      await db.addSpend(fund, 30.5);
      await db.insertItem(item(feb.id!, 'Mascota', 40, envelope: true));
      await db.insertItem(item(feb.id!, 'Préstamo', 75, paid: true));
      await db.insertItem(
        item(feb.id!, 'Renta (atrasada)', 700, recurring: false, method: 'cash'),
      );
      await db.insertItem(item(feb.id!, 'Cuota (2)', 50));
      await db.insertItem(item(feb.id!, '2 boletos', 12.5, paid: true));
      final mar = await db.openPeriod(personal.id!, 2026, 3);
      await db.setItemPaid((await db.getMonthData(mar.id!)).items[1].id!, true);

      final ledger = await db.insertBook(
        name: 'Ahorros',
        color: 0xFF2E4A72,
        kind: BookKind.ledger,
      );
      await db.insertMovement(
        movement(ledger, 1000, description: 'Fondo', date: DateTime(2026, 1, 5)),
      );
      await db.insertMovement(
        movement(
          ledger,
          -250.5,
          description: '2da cuota',
          method: 'cash',
          date: DateTime(2026, 2, 28),
        ),
      );
      await db.insertBook(name: 'Vacío', color: 0xFF8C2B23);
    }

    test('el archivo es texto legible', () async {
      final db = await openMemoryDb();
      await fill(db);
      final text = formatBackup(await db.exportBackup(), now: today);
      await db.close();

      expect(text, startsWith('PennyTree - respaldo del 2026-03-15'));
      expect(text, contains('# Personal\ntipo: mensual\ncolor: 56692F\n'));
      expect(text, contains('== 2026-02\n+ 900 Salario\n'));
      expect(text, contains('+ 50.25 Venta #efectivo #unavez\n'));
      expect(text, contains('[ ] 0 Ahorro\n'));
      expect(text, contains('[ ] 300 Súper ( -120 -30.50 = 149.50 )\n'));
      expect(text, contains('[ ] 40 Mascota ( = 40 )\n'));
      expect(text, contains('[v] 75 Préstamo\n'));
      expect(text, contains('[ ] 700 Renta (atrasada) #efectivo #unavez\n'));
      expect(text, contains('== 2026-03\n'));
      expect(text, contains('# Ahorros\ntipo: cuenta\ncolor: 2E4A72\n'));
      expect(text, contains('2026-01-05 + 1000 Fondo\n'));
      expect(text, contains('2026-02-28 - 250.50 2da cuota #efectivo\n'));
      expect(text, contains('# Vacío\ntipo: mensual\n'));
    });

    test('exportar e importar en otro dispositivo conserva todo', () async {
      final source = await openMemoryDb();
      await fill(source);
      final original = formatBackup(await source.exportBackup(), now: today);
      final sourceBooks = await source.getBooks(now: today);
      await source.close();

      // "Otro dispositivo": una instalación nueva.
      final target = await openMemoryDb();
      final summary = await target.importBackup(
        parseBackup(original),
        now: today,
      );
      expect(summary.booksUpdated, 1); // el "Personal" inicial
      expect(summary.booksCreated, 2);

      final restored = formatBackup(await target.exportBackup(), now: today);
      expect(restored, original);

      final targetBooks = await target.getBooks(now: today);
      expect(targetBooks.map((b) => b.name), sourceBooks.map((b) => b.name));
      expect(
        targetBooks.map((b) => b.available),
        sourceBooks.map((b) => b.available),
      );
      expect(
        targetBooks.map((b) => b.colorValue),
        sourceBooks.map((b) => b.colorValue),
      );
      expect(parseBackup(original).ignoredLines, 2); // las 2 de encabezado
      await target.close();
    });
  });

  group('Archivos', () {
    test('lee texto UTF-8 con acentos', () {
      final bytes = Uint8List.fromList(utf8.encode('# Niños\n[ ] 5 Útiles'));
      expect(parseBackup(BackupFiles.decode(bytes)).books.single.name, 'Niños');
    });

    test('rechaza archivos demasiado grandes', () {
      final huge = Uint8List(BackupFiles.maxBytes + 1);
      expect(() => BackupFiles.decode(huge), throwsFormatException);
    });

    test('no falla con bytes que no son texto', () {
      final junk = Uint8List.fromList([0xFF, 0xFE, 0x00, 0x23, 0x20, 0xC3]);
      expect(parseBackup(BackupFiles.decode(junk)).isEmpty, isTrue);
    });
  });

  group('Pantalla', () {
    late AppDatabase db;

    setUp(() async {
      db = await openMemoryDb();
      AppDatabase.useForTesting(db);
    });
    tearDown(() async {
      AppDatabase.useForTesting(null);
      await db.close();
    });

    Future<void> pumpBooks(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const BooksScreen()),
      );
      await tester.pumpAndSettle();
    }

    /// Simula que el usuario eligió un archivo con ese contenido.
    void importText(WidgetTester tester, String text) {
      final dynamic state = tester.state(find.byType(BooksScreen));
      // ignore: avoid_dynamic_calls
      state.importBackupText(text);
    }

    testWidgets('el menú ofrece importar, exportar y ver el formato', (
      tester,
    ) async {
      await pumpBooks(tester);
      await tester.tap(find.byTooltip('Importar y exportar'));
      await tester.pumpAndSettle();

      expect(find.text('Importar archivo de texto'), findsOneWidget);
      expect(find.text('Exportar respaldo'), findsOneWidget);

      await tester.tap(find.text('Formato del archivo'));
      await tester.pumpAndSettle();
      expect(find.textContaining('# inicia un libro'), findsOneWidget);
    });

    testWidgets('muestra lo encontrado y lo importa al confirmar', (
      tester,
    ) async {
      await pumpBooks(tester);
      importText(tester, handwritten);
      await tester.pumpAndSettle();

      expect(find.textContaining('2 libros'), findsOneWidget);
      expect(find.textContaining('5 renglones'), findsOneWidget);
      expect(find.textContaining('2 ingresos'), findsOneWidget);
      expect(find.textContaining('3 movimientos'), findsOneWidget);
      expect(find.textContaining('4 líneas no se reconocieron'), findsOneWidget);

      await tester.tap(find.text('Importar'));
      await tester.pumpAndSettle();

      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Ahorros'), findsOneWidget);
      expect(find.text('Saldo: \$850.00'), findsOneWidget);
      expect(find.text('Archivo importado correctamente'), findsOneWidget);
      expect(await db.getBooks(), hasLength(3));
    });

    testWidgets('cancelar no importa nada', (tester) async {
      await pumpBooks(tester);
      importText(tester, handwritten);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(await db.getBooks(), hasLength(1));
    });

    testWidgets('avisa si el archivo no tiene libros', (tester) async {
      await pumpBooks(tester);
      importText(tester, 'una nota cualquiera\n[ ] 5 sin encabezado');
      await tester.pumpAndSettle();

      expect(find.text('Sin libros'), findsOneWidget);
      await tester.tap(find.text('Entendido'));
      await tester.pumpAndSettle();
      expect(await db.getBooks(), hasLength(1));
    });
  });
}
