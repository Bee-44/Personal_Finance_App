// Pruebas de funcionamiento de la base de datos local.
import 'package:flutter_test/flutter_test.dart';
import 'package:pennytree/models/book.dart';
import 'package:pennytree/models/month.dart';
import 'package:pennytree/models/movement.dart';
import 'package:pennytree/services/app_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late int bookId;

  setUp(() async {
    db = await openMemoryDb();
    bookId = (await db.getBooks()).single.id!;
  });
  tearDown(() => db.close());

  group('Libros', () {
    test('la primera vez se crea un libro mensual inicial', () async {
      final book = (await db.getBooks()).single;
      expect(book.name, AppDatabase.defaultBookName);
      expect(book.kind, BookKind.monthly);
      expect(book.colorValue, Book.palette.first.toARGB32());
      expect(book.entryCount, 0);
      expect(book.available, 0);
    });

    test('crear y editar un libro con nombre, color y tipo', () async {
      final id = await db.insertBook(
        name: '  Ahorros ',
        color: 0xFF2E4A72,
        kind: BookKind.ledger,
      );
      var book = (await db.getBook(id))!;
      expect(book.name, 'Ahorros'); // se recortan los espacios
      expect(book.colorValue, 0xFF2E4A72);
      expect(book.isLedger, isTrue);

      await db.updateBook(id, name: 'Fondo', color: 0xFF8C2B23);
      book = (await db.getBook(id))!;
      expect(book.name, 'Fondo');
      expect(book.colorValue, 0xFF8C2B23);
      expect(book.isLedger, isTrue); // el tipo no cambia al editar
    });

    test('detecta nombres repetidos sin distinguir mayúsculas', () async {
      final id = await db.insertBook(name: 'Casa', color: 0xFF56692F);
      expect(await db.bookNameExists('casa'), isTrue);
      expect(await db.bookNameExists(' CASA '), isTrue);
      expect(await db.bookNameExists('Casa', exceptId: id), isFalse);
      expect(await db.bookNameExists('Viaje'), isFalse);
      // La base de datos también lo impide por sí misma.
      expect(
        () => db.insertBook(name: 'CASA', color: 0xFF56692F),
        throwsA(anything),
      );
    });

    test('no se puede eliminar el único libro', () async {
      expect(() => db.deleteBook(bookId), throwsStateError);
      expect(await db.getBooks(), hasLength(1));
    });

    test('eliminar un libro borra todo lo suyo y nada más', () async {
      final keep = await db.openPeriod(bookId, 2026, 3);
      await db.insertItem(item(keep.id!, 'Luz', 20));

      final monthly = await db.insertBook(name: 'Viaje', color: 0xFF2E4A72);
      final period = await db.openPeriod(monthly, 2026, 3);
      await db.insertIncome(income(period.id!, 'Salario', 100));
      final fund = await db.insertItem(
        item(period.id!, 'Comidas', 50, envelope: true),
      );
      await db.addSpend(fund, 10);

      final ledger = await db.insertBook(
        name: 'Ahorros',
        color: 0xFF8C2B23,
        kind: BookKind.ledger,
      );
      await db.insertMovement(movement(ledger, 500));

      await db.deleteBook(monthly);
      await db.deleteBook(ledger);

      expect(await db.getPeriods(monthly), isEmpty);
      expect(await db.getMovements(ledger), isEmpty);
      expect(() => db.getMonthData(period.id!), throwsStateError);
      expect((await db.getMonthData(keep.id!)).items.single.name, 'Luz');
    });
  });

  group('Hoja mensual', () {
    late Period march;
    setUp(() async => march = await db.openPeriod(bookId, 2026, 3));

    test('abrir un mes dos veces devuelve la misma hoja', () async {
      final again = await db.openPeriod(bookId, 2026, 3);
      expect(again.id, march.id);
      expect(await db.getPeriods(bookId), hasLength(1));
      expect(march.label, 'Marzo 2026');
    });

    test('marcar un renglón lo resta del disponible', () async {
      await db.insertIncome(income(march.id!, 'Salario', 900));
      await db.insertIncome(income(march.id!, 'Extra', 50, recurring: false));
      final rent = await db.insertItem(item(march.id!, 'Préstamo', 75));
      await db.insertItem(item(march.id!, 'Jardín', 20));

      var data = await db.getMonthData(march.id!);
      expect(data.totalIncome, 950);
      expect(data.available, 950); // nada pagado todavía
      expect(data.pending, 95);
      expect(data.free, 855);
      expect(data.paidCount, 0);

      await db.setItemPaid(rent, true);
      data = await db.getMonthData(march.id!);
      expect(data.available, 875);
      expect(data.pending, 20);
      expect(data.free, 855); // lo libre no cambia al pagar lo planeado
      expect(data.paidCount, 1);

      await db.setItemPaid(rent, false);
      data = await db.getMonthData(march.id!);
      expect(data.available, 950);
    });

    test('un fondo descuenta solo lo que se va gastando', () async {
      await db.insertIncome(income(march.id!, 'Salario', 950));
      final food = await db.insertItem(
        item(march.id!, 'Súper', 300, envelope: true),
      );
      await db.addSpend(food, 120);
      final second = await db.addSpend(food, 30);

      var data = await db.getMonthData(march.id!);
      var fund = data.items.single;
      expect(fund.spent, 150);
      expect(fund.remaining, 150);
      expect(data.available, 800); // 950 - 150
      expect(data.pending, 150); // lo que queda del fondo
      expect(data.free, 650); // 950 - 300

      // Quitar un gasto lo devuelve.
      await db.deleteSpend(second);
      data = await db.getMonthData(march.id!);
      expect(data.items.single.remaining, 180);

      // Cerrar el fondo libera lo que sobró.
      await db.setItemPaid(food, true);
      data = await db.getMonthData(march.id!);
      expect(data.available, 830); // 950 - 120
      expect(data.pending, 0);
      expect(data.free, 830);

      // Un fondo puede excederse.
      await db.setItemPaid(food, false);
      await db.addSpend(food, 300);
      fund = (await db.getMonthData(march.id!)).items.single;
      expect(fund.remaining, -120);
      expect(fund.pending, 0);
    });

    test('un renglón puede no tener monto todavía', () async {
      final id = await db.insertItem(item(march.id!, 'Ahorro', 0));
      await db.setItemPaid(id, true);
      final data = await db.getMonthData(march.id!);
      expect(data.items.single.amount, 0);
      expect(data.available, 0);
    });

    test('separa lo disponible en banco y en efectivo', () async {
      await db.insertIncome(income(march.id!, 'Salario', 500));
      await db.insertIncome(income(march.id!, 'Venta', 80, method: 'cash'));
      await db.insertItem(item(march.id!, 'Luz', 60, paid: true));
      await db.insertItem(
        item(march.id!, 'Mercado', 30, paid: true, method: 'cash'),
      );
      final data = await db.getMonthData(march.id!);
      expect(data.availableBy('bank'), 440);
      expect(data.availableBy('cash'), 50);
      expect(data.available, 490);
    });

    test('editar y eliminar renglones e ingresos', () async {
      final salary = await db.insertIncome(income(march.id!, 'Salario', 500));
      final id = await db.insertItem(item(march.id!, 'Luz', 60, paid: true));

      await db.updateItem(
        BudgetItem(
          id: id,
          periodId: march.id!,
          name: 'Electricidad',
          amount: 75,
          method: 'cash',
          recurring: false,
        ),
      );
      await db.updateIncome(
        Income(id: salary, periodId: march.id!, name: 'Sueldo', amount: 550),
      );
      var data = await db.getMonthData(march.id!);
      final edited = data.items.single;
      expect(edited.name, 'Electricidad');
      expect(edited.amount, 75);
      expect(edited.method, 'cash');
      expect(edited.recurring, isFalse);
      expect(edited.paid, isTrue); // editar no desmarca
      expect(data.incomes.single.name, 'Sueldo');
      expect(data.available, 475);

      await db.setItemRecurring(id, true);
      expect((await db.getMonthData(march.id!)).items.single.recurring, isTrue);

      await db.deleteItem(id);
      await db.deleteIncome(salary);
      data = await db.getMonthData(march.id!);
      expect(data.items, isEmpty);
      expect(data.incomes, isEmpty);
    });

    test('los renglones conservan el orden en que se agregaron', () async {
      for (final name in ['Renta', 'Luz', 'Agua', 'Teléfono']) {
        await db.insertItem(item(march.id!, name, 10));
      }
      final names = (await db.getMonthData(march.id!)).items.map((i) => i.name);
      expect(names, ['Renta', 'Luz', 'Agua', 'Teléfono']);
    });
  });

  group('Mes nuevo', () {
    test('copia los recurrentes sin marcar y deja fuera lo demás', () async {
      final march = await db.openPeriod(bookId, 2026, 3);
      await db.insertIncome(income(march.id!, 'Salario', 900));
      await db.insertIncome(income(march.id!, 'Extra', 50, recurring: false));
      await db.insertItem(item(march.id!, 'Préstamo', 75, paid: true));
      final fund = await db.insertItem(
        item(march.id!, 'Súper', 300, envelope: true, paid: true),
      );
      await db.addSpend(fund, 120);
      await db.insertItem(
        item(march.id!, 'Regalo', 18, recurring: false, paid: true),
      );
      await db.insertItem(item(march.id!, 'Jardín', 20, method: 'cash'));

      final april = await db.openPeriod(bookId, 2026, 4);
      final data = await db.getMonthData(april.id!);

      expect(april.label, 'Abril 2026');
      expect(data.incomes.map((i) => i.name), ['Salario']);
      expect(data.items.map((i) => i.name), ['Préstamo', 'Súper', 'Jardín']);
      expect(data.items.every((i) => !i.paid), isTrue);
      expect(data.items.every((i) => i.recurring), isTrue);
      expect(data.items[1].envelope, isTrue);
      expect(data.items[1].spends, isEmpty); // el fondo arranca lleno
      expect(data.items[2].method, 'cash');
      expect(data.totalIncome, 900);
      expect(data.carryIn, 737); // sobrante de marzo: 950 - 213
      expect(data.available, 1637);
      expect(data.pending, 395);

      // El mes anterior queda intacto.
      final before = await db.getMonthData(march.id!);
      expect(before.items, hasLength(4));
      expect(before.paidCount, 3);
      expect(before.items[1].spent, 120);
    });

    test('si se saltan meses, copia del último que exista', () async {
      final january = await db.openPeriod(bookId, 2026, 1);
      await db.insertItem(item(january.id!, 'Renta', 700));

      final december = await db.openPeriod(bookId, 2026, 12);
      expect(
        (await db.getMonthData(december.id!)).items.single.name,
        'Renta',
      );

      // Cambio de año.
      final next = await db.openPeriod(bookId, 2027, 1);
      expect((await db.getMonthData(next.id!)).items.single.name, 'Renta');
      expect(
        (await db.getPeriods(bookId)).map((p) => p.label),
        ['Enero 2026', 'Diciembre 2026', 'Enero 2027'],
      );
    });

    test('rechaza meses no válidos y libros que no son mensuales', () async {
      expect(() => db.openPeriod(bookId, 2026, 13), throwsArgumentError);
      expect(() => db.openPeriod(bookId, 2026, 0), throwsArgumentError);
      expect(() => db.openPeriod(9999, 2026, 5), throwsStateError);
      final ledger = await db.insertBook(
        name: 'Ahorros',
        color: 0xFF2E4A72,
        kind: BookKind.ledger,
      );
      expect(() => db.openPeriod(ledger, 2026, 5), throwsStateError);
    });
  });

  group('Cuenta', () {
    late int ledger;
    setUp(() async {
      ledger = await db.insertBook(
        name: 'Ahorros',
        color: 0xFF2E4A72,
        kind: BookKind.ledger,
      );
    });

    test('abonos y retiros forman el saldo', () async {
      await db.insertMovement(movement(ledger, 1000, description: 'Fondo'));
      await db.insertMovement(movement(ledger, 250, description: 'Abono'));
      final out = await db.insertMovement(
        movement(ledger, -75.5, description: 'Renta', method: 'cash'),
      );

      var book = (await db.getBooks()).firstWhere((b) => b.id == ledger);
      expect(book.available, closeTo(1174.5, 1e-9));
      expect(book.entryCount, 3);

      await db.updateMovement(
        Movement(
          id: out,
          bookId: ledger,
          amount: -100,
          description: 'Renta ajustada',
          date: DateTime(2026, 2, 1),
        ),
      );
      final movements = await db.getMovements(ledger);
      expect(movements.first.description, 'Renta ajustada'); // más reciente
      expect(movements.first.isIncome, isFalse);

      await db.deleteMovement(out);
      book = (await db.getBooks()).firstWhere((b) => b.id == ledger);
      expect(book.available, 1250);
    });

    test('editar un movimiento no lo puede mover a otra cuenta', () async {
      final other = await db.insertBook(
        name: 'Otra',
        color: 0xFF8C2B23,
        kind: BookKind.ledger,
      );
      final id = await db.insertMovement(movement(ledger, 50));
      await db.updateMovement(
        Movement(
          id: id,
          bookId: other,
          amount: 1,
          description: 'movido',
          date: DateTime(2026),
        ),
      );
      expect(await db.getMovements(other), isEmpty);
      expect((await db.getMovements(ledger)).single.amount, 50);
    });
  });

  test('el listado resume el mes en curso de cada libro', () async {
    final march = await db.openPeriod(bookId, 2026, 3);
    await db.insertIncome(income(march.id!, 'Salario', 500));
    await db.insertItem(item(march.id!, 'Luz', 60, paid: true));
    await db.insertItem(item(march.id!, 'Agua', 20));
    final april = await db.openPeriod(bookId, 2026, 4);
    await db.setItemPaid(
      (await db.getMonthData(april.id!)).items.first.id!,
      true,
    );
    await db.setItemPaid(
      (await db.getMonthData(april.id!)).items.last.id!,
      true,
    );

    final inMarch = (await db.getBooks(now: DateTime(2026, 3, 20))).single;
    expect(inMarch.available, 440);
    expect(inMarch.entryCount, 2);
    expect(inMarch.paidCount, 1);

    final inApril = (await db.getBooks(now: DateTime(2026, 4, 2))).single;
    expect(inApril.available, 860); // 440 de sobrante + 500 - 80
    expect(inApril.paidCount, 2);

    // Si el mes en curso aún no se ha abierto, muestra el más reciente.
    final later = (await db.getBooks(now: DateTime(2026, 9, 1))).single;
    expect(later.available, 860);
  });

  test('los datos persisten en el dispositivo al reabrir la app', () async {
    final path = await tempDbPath();
    var fileDb = await AppDatabase.open(testFactory, path);
    final id = (await fileDb.getBooks()).single.id!;
    final period = await fileDb.openPeriod(id, 2026, 3);
    await fileDb.insertIncome(income(period.id!, 'Salario', 750));
    final fund = await fileDb.insertItem(
      item(period.id!, 'Súper', 200, envelope: true),
    );
    await fileDb.addSpend(fund, 42);
    await fileDb.close();

    fileDb = await AppDatabase.open(testFactory, path);
    final data = await fileDb.getMonthData(period.id!);
    expect(data.totalIncome, 750);
    expect(data.items.single.spent, 42);
    expect(data.available, 708);
    await fileDb.close();
  });

  test('actualiza una base de la versión 1 sin perder datos', () async {
    final path = await tempDbPath();
    // Esquema y datos tal como los dejaba la versión 1 de la app.
    final old = await testFactory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE books (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL COLLATE NOCASE UNIQUE,
              color INTEGER NOT NULL,
              card_budget REAL NOT NULL DEFAULT 0,
              cash_budget REAL NOT NULL DEFAULT 0,
              created_at INTEGER NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE expenses (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              book_id INTEGER NOT NULL REFERENCES books (id) ON DELETE CASCADE,
              amount REAL NOT NULL,
              description TEXT NOT NULL,
              date INTEGER NOT NULL,
              payment_method TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    final date = DateTime(2026, 2, 10).millisecondsSinceEpoch;
    final oldBook = await old.insert('books', {
      'name': 'Viaje',
      'color': 0xFF1565C0,
      'card_budget': 800.0,
      'cash_budget': 400.0,
      'created_at': date,
    });
    await old.insert('books', {'name': 'Vacío', 'color': 1, 'created_at': date});
    await old.insert('expenses', {
      'book_id': oldBook,
      'amount': 186.4,
      'description': 'Hotel',
      'date': date,
      'payment_method': 'card',
    });
    await old.insert('expenses', {
      'book_id': oldBook,
      'amount': 20.0,
      'description': 'Taxi',
      'date': date + 1,
      'payment_method': 'cash',
    });
    await old.close();

    final upgraded = await AppDatabase.open(testFactory, path);
    final books = await upgraded.getBooks();
    final trip = books.firstWhere((b) => b.name == 'Viaje');
    expect(trip.isLedger, isTrue);
    expect(trip.colorValue, 0xFF1565C0);
    // Mismo saldo que mostraba la versión 1: 1200 - 206.40
    expect(trip.available, closeTo(993.6, 1e-9));
    expect(trip.entryCount, 4);

    final movements = await upgraded.getMovements(trip.id!);
    final hotel = movements.firstWhere((m) => m.description == 'Hotel');
    expect(hotel.amount, -186.4);
    expect(hotel.method, 'bank');
    expect(
      movements.firstWhere((m) => m.description == 'Taxi').method,
      'cash',
    );
    expect(
      movements.where((m) => m.isIncome).map((m) => m.amount),
      containsAll([800.0, 400.0]),
    );

    final empty = books.firstWhere((b) => b.name == 'Vacío');
    expect(empty.entryCount, 0);

    // La base actualizada acepta todo lo nuevo.
    final monthly = await upgraded.insertBook(name: 'Casa', color: 0xFF56692F);
    final period = await upgraded.openPeriod(monthly, 2026, 3);
    await upgraded.insertItem(item(period.id!, 'Renta', 500));
    expect((await upgraded.getMonthData(period.id!)).pending, 500);
    await upgraded.close();
  });
}
