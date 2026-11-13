import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/book.dart';
import '../models/month.dart';
import '../models/movement.dart';
import '../models/validation.dart';
import '../utils/backup.dart';
import '../utils/note_import.dart';

/// Base de datos local (SQLite) de la aplicación. Cada dispositivo guarda
/// sus propios datos; nada se envía a la nube.
///
/// Todas las consultas usan parámetros (`?`), nunca concatenación de texto,
/// y los datos se validan aquí además de en los formularios.
class AppDatabase {
  AppDatabase._(this._db);

  static const String fileName = 'control_gastos.db';
  static const String defaultBookName = 'Personal';
  static const int schemaVersion = 2;

  static AppDatabase? _instance;

  final Database _db;

  /// Instancia compartida por toda la app. Hay que llamar a [init] antes.
  static AppDatabase get instance {
    final db = _instance;
    if (db == null) {
      throw StateError('AppDatabase.init() no se ha ejecutado');
    }
    return db;
  }

  /// Abre (o crea) la base de datos del dispositivo.
  static Future<AppDatabase> init() async {
    final existing = _instance;
    if (existing != null) return existing;
    final path = p.join(await getDatabasesPath(), fileName);
    return _instance = await open(databaseFactory, path);
  }

  /// Abre una base de datos en una ruta concreta. Lo usan las pruebas.
  static Future<AppDatabase> open(DatabaseFactory factory, String path) async {
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: _create,
        onUpgrade: _upgrade,
      ),
    );
    return AppDatabase._(db);
  }

  /// Reemplaza la instancia compartida. Solo para pruebas.
  static void useForTesting(AppDatabase? db) => _instance = db;

  // --------------------------------------------------------------- Esquema

  static const _nameCheck =
      'CHECK (length(trim(name)) BETWEEN 1 AND $maxTextLength)';
  static const _methodCheck = "CHECK (method IN ('bank', 'cash'))";

  static Future<void> _create(Database db, int version) async {
    await db.execute('''
      CREATE TABLE books (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL COLLATE NOCASE UNIQUE
          CHECK (length(trim(name)) BETWEEN 1 AND ${Book.maxNameLength}),
        color INTEGER NOT NULL,
        kind TEXT NOT NULL DEFAULT 'monthly'
          CHECK (kind IN ('monthly', 'ledger')),
        created_at INTEGER NOT NULL
      )
    ''');
    await _createV2Tables(db);
    // Libro inicial para que la app sea utilizable desde el primer arranque.
    await db.insert('books', {
      'name': defaultBookName,
      'color': Book.palette.first.toARGB32(),
      'kind': BookKind.monthly,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Tablas que aparecieron en la versión 2 del esquema.
  static Future<void> _createV2Tables(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE periods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL REFERENCES books (id) ON DELETE CASCADE,
        year INTEGER NOT NULL CHECK (year BETWEEN 2000 AND 2200),
        month INTEGER NOT NULL CHECK (month BETWEEN 1 AND 12),
        UNIQUE (book_id, year, month)
      )
    ''');
    await db.execute('''
      CREATE TABLE incomes (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        period_id INTEGER NOT NULL REFERENCES periods (id) ON DELETE CASCADE,
        name TEXT NOT NULL $_nameCheck,
        amount REAL NOT NULL CHECK (amount > 0),
        method TEXT NOT NULL $_methodCheck,
        recurring INTEGER NOT NULL DEFAULT 1 CHECK (recurring IN (0, 1))
      )
    ''');
    await db.execute('''
      CREATE TABLE items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        period_id INTEGER NOT NULL REFERENCES periods (id) ON DELETE CASCADE,
        name TEXT NOT NULL $_nameCheck,
        amount REAL NOT NULL CHECK (amount >= 0),
        method TEXT NOT NULL $_methodCheck,
        recurring INTEGER NOT NULL DEFAULT 1 CHECK (recurring IN (0, 1)),
        paid INTEGER NOT NULL DEFAULT 0 CHECK (paid IN (0, 1)),
        envelope INTEGER NOT NULL DEFAULT 0 CHECK (envelope IN (0, 1)),
        position INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE spends (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_id INTEGER NOT NULL REFERENCES items (id) ON DELETE CASCADE,
        amount REAL NOT NULL CHECK (amount > 0),
        created_at INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        book_id INTEGER NOT NULL REFERENCES books (id) ON DELETE CASCADE,
        amount REAL NOT NULL CHECK (amount != 0),
        description TEXT NOT NULL
          CHECK (length(trim(description)) BETWEEN 1 AND $maxTextLength),
        date INTEGER NOT NULL,
        method TEXT NOT NULL $_methodCheck
      )
    ''');
    await db.execute('CREATE INDEX idx_incomes_period ON incomes (period_id)');
    await db.execute(
      'CREATE INDEX idx_items_period ON items (period_id, position)',
    );
    await db.execute('CREATE INDEX idx_spends_item ON spends (item_id)');
    await db.execute(
      'CREATE INDEX idx_movements_book ON movements (book_id, date DESC)',
    );
  }

  static Future<void> _upgrade(Database db, int from, int to) async {
    if (from < 2) await _migrateV1toV2(db);
  }

  /// La versión 1 tenía, por libro, un presupuesto (tarjeta y efectivo) y una
  /// lista de gastos. Eso equivale a una cuenta con saldo corrido, así que
  /// esos libros pasan a ser de tipo cuenta: el presupuesto se vuelve un
  /// abono y cada gasto un retiro. No se pierde ningún dato ni cambia el
  /// saldo que veía el usuario.
  static Future<void> _migrateV1toV2(Database db) async {
    await db.execute(
      "ALTER TABLE books ADD COLUMN kind TEXT NOT NULL DEFAULT 'monthly'",
    );
    await db.execute("UPDATE books SET kind = 'ledger'");
    await _createV2Tables(db);
    await db.execute('''
      INSERT INTO movements (book_id, amount, description, date, method)
      SELECT id, card_budget, 'Presupuesto en banco', created_at, 'bank'
      FROM books WHERE card_budget > 0
    ''');
    await db.execute('''
      INSERT INTO movements (book_id, amount, description, date, method)
      SELECT id, cash_budget, 'Presupuesto en efectivo', created_at, 'cash'
      FROM books WHERE cash_budget > 0
    ''');
    await db.execute('''
      INSERT INTO movements (book_id, amount, description, date, method)
      SELECT book_id, -amount, substr(trim(description), 1, $maxTextLength),
             date,
             CASE payment_method WHEN 'cash' THEN 'cash' ELSE 'bank' END
      FROM expenses
    ''');
    await db.execute('DROP TABLE expenses');
  }

  Future<void> close() async {
    await _db.close();
    if (identical(_instance, this)) _instance = null;
  }

  // ---------------------------------------------------------------- Libros

  /// Lista los libros con su resumen. [now] decide cuál es el mes en curso.
  Future<List<Book>> getBooks({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final rows = await _db.query('books', orderBy: 'created_at, id');
    final books = <Book>[];
    for (final row in rows) {
      final book = Book.fromMap(row);
      if (book.isLedger) {
        final sum = await _db.rawQuery(
          'SELECT COUNT(*) AS n, COALESCE(SUM(amount), 0) AS total '
          'FROM movements WHERE book_id = ?',
          [book.id],
        );
        books.add(
          book.withSummary(
            available: (sum.first['total'] as num).toDouble(),
            entryCount: sum.first['n'] as int,
          ),
        );
      } else {
        // El mes en curso si ya existe; si no, el más reciente.
        final period = await _db.rawQuery(
          'SELECT id FROM periods WHERE book_id = ? '
          'ORDER BY (year = ? AND month = ?) DESC, year DESC, month DESC '
          'LIMIT 1',
          [book.id, today.year, today.month],
        );
        if (period.isEmpty) {
          books.add(book);
        } else {
          final data = await getMonthData(period.first['id'] as int);
          books.add(
            book.withSummary(
              available: data.available,
              entryCount: data.items.length,
              paidCount: data.paidCount,
            ),
          );
        }
      }
    }
    return books;
  }

  Future<Book?> getBook(int id) async {
    final rows = await _db.query('books', where: 'id = ?', whereArgs: [id]);
    return rows.isEmpty ? null : Book.fromMap(rows.first);
  }

  /// Indica si ya existe otro libro con ese nombre (sin distinguir
  /// mayúsculas). [exceptId] excluye al libro que se está editando.
  Future<bool> bookNameExists(String name, {int? exceptId}) async {
    final rows = await _db.query(
      'books',
      columns: ['id'],
      where: 'name = ? AND id != ?',
      whereArgs: [name.trim(), exceptId ?? -1],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  Future<int> insertBook({
    required String name,
    required int color,
    String kind = BookKind.monthly,
  }) {
    _check(Book.validateName(name));
    _check(Book.validateKind(kind));
    return _db.insert('books', {
      'name': name.trim(),
      'color': Book.normalizeColor(color),
      'kind': kind,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  /// Cambia nombre y color. El tipo de libro no se puede cambiar.
  Future<void> updateBook(
    int id, {
    required String name,
    required int color,
  }) async {
    _check(Book.validateName(name));
    await _db.update(
      'books',
      {'name': name.trim(), 'color': Book.normalizeColor(color)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Elimina un libro y todo su contenido. Siempre debe quedar al menos uno.
  Future<void> deleteBook(int id) async {
    await _db.transaction((txn) async {
      final count = Sqflite.firstIntValue(
        await txn.rawQuery('SELECT COUNT(*) FROM books'),
      );
      if ((count ?? 0) <= 1) {
        throw StateError('No se puede eliminar el único libro');
      }
      await txn.delete('books', where: 'id = ?', whereArgs: [id]);
    });
  }

  // ------------------------------------------------------- Meses (mensual)

  /// Devuelve la hoja de ese mes; si no existe, la crea.
  ///
  /// Una hoja nueva arranca con los ingresos y renglones recurrentes de la
  /// hoja anterior más cercana, sin marcar y sin gastos parciales: lo mismo
  /// que copiar la lista del mes pasado y desmarcarla.
  Future<Period> openPeriod(int bookId, int year, int month) async {
    if (month < 1 || month > 12 || year < 2000 || year > 2200) {
      throw ArgumentError('Mes no válido');
    }
    return _db.transaction((txn) async {
      final existing = await txn.query(
        'periods',
        where: 'book_id = ? AND year = ? AND month = ?',
        whereArgs: [bookId, year, month],
      );
      if (existing.isNotEmpty) return Period.fromMap(existing.first);

      final book = await txn.query(
        'books',
        columns: ['kind'],
        where: 'id = ?',
        whereArgs: [bookId],
      );
      if (book.isEmpty) throw StateError('El libro no existe');
      if (book.first['kind'] != BookKind.monthly) {
        throw StateError('Este libro no se lleva por meses');
      }

      final previous = await txn.query(
        'periods',
        where: 'book_id = ? AND (year * 12 + month) < ?',
        whereArgs: [bookId, year * 12 + month],
        orderBy: 'year DESC, month DESC',
        limit: 1,
      );

      final id = await txn.insert('periods', {
        'book_id': bookId,
        'year': year,
        'month': month,
      });

      if (previous.isNotEmpty) {
        final prevId = previous.first['id'];
        await txn.rawInsert(
          '''
          INSERT INTO incomes (period_id, name, amount, method, recurring)
          SELECT ?, name, amount, method, 1
          FROM incomes WHERE period_id = ? AND recurring = 1 ORDER BY id
          ''',
          [id, prevId],
        );
        await txn.rawInsert(
          '''
          INSERT INTO items
            (period_id, name, amount, method, recurring, paid, envelope,
             position)
          SELECT ?, name, amount, method, 1, 0, envelope, position
          FROM items WHERE period_id = ? AND recurring = 1
          ORDER BY position, id
          ''',
          [id, prevId],
        );
      }
      return Period(id: id, bookId: bookId, year: year, month: month);
    });
  }

  /// Las hojas de un libro, de la más antigua a la más nueva.
  Future<List<Period>> getPeriods(int bookId) async {
    final rows = await _db.query(
      'periods',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'year, month',
    );
    return rows.map(Period.fromMap).toList();
  }

  Future<MonthData> getMonthData(int periodId) async {
    final period = await _db.query(
      'periods',
      where: 'id = ?',
      whereArgs: [periodId],
    );
    if (period.isEmpty) throw StateError('El mes no existe');

    final incomes = await _db.query(
      'incomes',
      where: 'period_id = ?',
      whereArgs: [periodId],
      orderBy: 'id',
    );
    final items = await _db.query(
      'items',
      where: 'period_id = ?',
      whereArgs: [periodId],
      orderBy: 'position, id',
    );
    final spends = await _db.rawQuery(
      '''
      SELECT s.* FROM spends s
      JOIN items i ON i.id = s.item_id
      WHERE i.period_id = ?
      ORDER BY s.id
      ''',
      [periodId],
    );
    final byItem = <int, List<Spend>>{};
    for (final row in spends) {
      final spend = Spend.fromMap(row);
      byItem.putIfAbsent(spend.itemId, () => []).add(spend);
    }

    final thisPeriod = Period.fromMap(period.first);
    final carry = await _carryInto(thisPeriod);

    return MonthData(
      period: thisPeriod,
      incomes: incomes.map(Income.fromMap).toList(),
      items: [
        for (final row in items)
          BudgetItem.fromMap(row, spends: byItem[row['id']] ?? const []),
      ],
      carryBank: carry[PayMethod.bank] ?? 0,
      carryCash: carry[PayMethod.cash] ?? 0,
    );
  }

  /// Sobrante que llega a [period] desde todos los meses anteriores del
  /// libro, por método: sus ingresos menos lo pagado y lo gastado de fondos.
  ///
  /// No se guarda: se calcula cada vez, así que corregir un mes cerrado
  /// actualiza solo el sobrante de los meses que le siguen.
  Future<Map<String, double>> _carryInto(Period period) async {
    const earlier =
        'p.book_id = ? AND (p.year * 12 + p.month) < ?';
    final args = [period.bookId, period.year * 12 + period.month];
    final totals = <String, double>{};

    void add(List<Map<String, Object?>> rows, int sign) {
      for (final row in rows) {
        final method = row['method'] as String;
        final total = (row['total'] as num?)?.toDouble() ?? 0;
        totals[method] = (totals[method] ?? 0) + sign * total;
      }
    }

    add(
      await _db.rawQuery(
        'SELECT i.method, SUM(i.amount) AS total FROM incomes i '
        'JOIN periods p ON p.id = i.period_id WHERE $earlier '
        'GROUP BY i.method',
        args,
      ),
      1,
    );
    // Pagos fijos ya marcados.
    add(
      await _db.rawQuery(
        'SELECT it.method, SUM(it.amount) AS total FROM items it '
        'JOIN periods p ON p.id = it.period_id WHERE $earlier '
        'AND it.envelope = 0 AND it.paid = 1 GROUP BY it.method',
        args,
      ),
      -1,
    );
    // Gastos anotados en fondos.
    add(
      await _db.rawQuery(
        'SELECT it.method, SUM(s.amount) AS total FROM spends s '
        'JOIN items it ON it.id = s.item_id '
        'JOIN periods p ON p.id = it.period_id WHERE $earlier '
        'AND it.envelope = 1 GROUP BY it.method',
        args,
      ),
      -1,
    );
    return totals;
  }

  /// Abre la hoja del mes en curso en todos los libros mensuales. Se llama
  /// al iniciar la app para que el mes nuevo empiece según el calendario,
  /// aunque no se entre a cada libro.
  Future<void> openCurrentPeriods({DateTime? now}) async {
    final today = now ?? DateTime.now();
    final books = await _db.query(
      'books',
      columns: ['id'],
      where: 'kind = ?',
      whereArgs: [BookKind.monthly],
    );
    for (final book in books) {
      await openPeriod(book['id'] as int, today.year, today.month);
    }
  }

  /// Todas las hojas de un libro con sus totales, de la más nueva a la más
  /// antigua.
  Future<List<MonthData>> getHistory(int bookId) async {
    final periods = await getPeriods(bookId);
    return [
      for (final period in periods.reversed) await getMonthData(period.id!),
    ];
  }

  // -------------------------------------------------------------- Ingresos

  Future<int> insertIncome(Income income) {
    _validateIncome(income);
    return _db.insert('incomes', income.toMap());
  }

  Future<void> updateIncome(Income income) async {
    final id = income.id;
    if (id == null) throw ArgumentError('El ingreso no tiene id');
    _validateIncome(income);
    await _db.update(
      'incomes',
      income.toMap()..remove('period_id'),
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteIncome(int id) async {
    await _db.delete('incomes', where: 'id = ?', whereArgs: [id]);
  }

  // ------------------------------------------------------------- Renglones

  /// Agrega un renglón al final de la lista del mes.
  Future<int> insertItem(BudgetItem item) {
    _validateItem(item);
    return _db.transaction((txn) => _insertItem(txn, item));
  }

  static Future<int> _insertItem(Transaction txn, BudgetItem item) async {
    final next = Sqflite.firstIntValue(
      await txn.rawQuery(
        'SELECT COALESCE(MAX(position), -1) + 1 FROM items '
        'WHERE period_id = ?',
        [item.periodId],
      ),
    );
    return txn.insert('items', item.toMap()..['position'] = next ?? 0);
  }

  /// Cambia los datos del renglón. No toca si está pagado ni su posición.
  Future<void> updateItem(BudgetItem item) async {
    final id = item.id;
    if (id == null) throw ArgumentError('El renglón no tiene id');
    _validateItem(item);
    await _db.update(
      'items',
      {
        'name': item.name.trim(),
        'amount': item.amount,
        'method': item.method,
        'recurring': item.recurring ? 1 : 0,
        'envelope': item.envelope ? 1 : 0,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Marca o desmarca un renglón.
  Future<void> setItemPaid(int id, bool paid) async {
    await _db.update(
      'items',
      {'paid': paid ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Decide si el renglón se copia al mes siguiente.
  Future<void> setItemRecurring(int id, bool recurring) async {
    await _db.update(
      'items',
      {'recurring': recurring ? 1 : 0},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteItem(int id) async {
    await _db.delete('items', where: 'id = ?', whereArgs: [id]);
  }

  /// Anota un gasto parcial en un fondo.
  Future<int> addSpend(int itemId, double amount) {
    _check(validateMoney(amount));
    return _db.insert('spends', {
      'item_id': itemId,
      'amount': amount,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<void> deleteSpend(int id) async {
    await _db.delete('spends', where: 'id = ?', whereArgs: [id]);
  }

  /// Agrega de una vez los renglones leídos de una lista pegada.
  /// Devuelve cuántos se agregaron.
  Future<int> importItems(
    int periodId,
    List<ParsedItem> parsed, {
    bool recurring = true,
  }) {
    return _db.transaction((txn) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final entry in parsed) {
        final item = BudgetItem(
          periodId: periodId,
          name: entry.name,
          amount: entry.amount,
          method: entry.method,
          recurring: recurring && entry.recurring,
          paid: entry.checked,
          envelope: entry.envelope,
        );
        await _insertParsedItem(txn, item, entry.spends, now);
      }
      return parsed.length;
    });
  }

  static Future<void> _insertParsedItem(
    Transaction txn,
    BudgetItem item,
    List<double> spends,
    int createdAt,
  ) async {
    _validateItem(item);
    final id = await _insertItem(txn, item);
    for (final amount in spends) {
      _check(validateMoney(amount));
      await txn.insert('spends', {
        'item_id': id,
        'amount': amount,
        'created_at': createdAt,
      });
    }
  }

  // ---------------------------------------------------- Movimientos (cuenta)

  /// Movimientos de una cuenta, del más reciente al más antiguo.
  Future<List<Movement>> getMovements(int bookId) async {
    final rows = await _db.query(
      'movements',
      where: 'book_id = ?',
      whereArgs: [bookId],
      orderBy: 'date DESC, id DESC',
    );
    return rows.map(Movement.fromMap).toList();
  }

  Future<int> insertMovement(Movement movement) {
    _validateMovement(movement);
    return _db.insert('movements', movement.toMap());
  }

  Future<void> updateMovement(Movement movement) async {
    final id = movement.id;
    if (id == null) throw ArgumentError('El movimiento no tiene id');
    _validateMovement(movement);
    // El libro también se filtra: un movimiento nunca cambia de libro.
    await _db.update(
      'movements',
      movement.toMap(),
      where: 'id = ? AND book_id = ?',
      whereArgs: [id, movement.bookId],
    );
  }

  Future<void> deleteMovement(int id) async {
    await _db.delete('movements', where: 'id = ?', whereArgs: [id]);
  }

  /// Agrega de una vez los movimientos leídos de una lista pegada, todos
  /// con la fecha [date]. Devuelve cuántos se agregaron.
  Future<int> importMovements(
    int bookId,
    List<ParsedMovement> parsed, {
    DateTime? date,
  }) {
    final when = date ?? DateTime.now();
    return _db.transaction((txn) async {
      for (final entry in parsed) {
        final movement = Movement(
          bookId: bookId,
          amount: entry.amount,
          description: entry.description,
          date: entry.date ?? when,
          method: entry.method,
        );
        _validateMovement(movement);
        await txn.insert('movements', movement.toMap());
      }
      return parsed.length;
    });
  }

  // --------------------------------------------------------------- Respaldo

  /// Reúne todos los libros con todo su contenido, listos para escribirse
  /// en un archivo de texto con `formatBackup`.
  Future<BackupData> exportBackup() async {
    final books = <BackupBook>[];
    final rows = await _db.query('books', orderBy: 'created_at, id');
    for (final row in rows) {
      final book = Book.fromMap(row);
      final backup = BackupBook(
        name: book.name,
        kind: book.kind,
        color: book.colorValue,
      );
      if (book.isLedger) {
        final movements = await _db.query(
          'movements',
          where: 'book_id = ?',
          whereArgs: [book.id],
          orderBy: 'date, id',
        );
        for (final m in movements.map(Movement.fromMap)) {
          backup.movements.add(
            ParsedMovement(
              description: m.description,
              amount: m.amount,
              method: m.method,
              date: m.date,
            ),
          );
        }
      } else {
        for (final period in await getPeriods(book.id!)) {
          final data = await getMonthData(period.id!);
          final month = BackupMonth(year: period.year, month: period.month);
          for (final income in data.incomes) {
            month.incomes.add(
              ParsedMovement(
                description: income.name,
                amount: income.amount,
                method: income.method,
                recurring: income.recurring,
              ),
            );
          }
          for (final item in data.items) {
            month.items.add(
              ParsedItem(
                name: item.name,
                amount: item.amount,
                checked: item.paid,
                envelope: item.envelope,
                spends: [for (final s in item.spends) s.amount],
                method: item.method,
                recurring: item.recurring,
              ),
            );
          }
          backup.months.add(month);
        }
      }
      books.add(backup);
    }
    return BackupData(books: books);
  }

  /// Guarda el contenido de un respaldo. Nunca borra ni reemplaza nada:
  /// - Un libro cuyo nombre y tipo ya existen recibe los datos nuevos.
  /// - Si el nombre existe pero con otro tipo, se crea con otro nombre.
  /// - Los demás libros se crean.
  ///
  /// Todo ocurre en una sola transacción: si algo falla, no se guarda nada.
  /// [now] decide el mes en curso y la fecha de los movimientos sin fecha.
  Future<ImportSummary> importBackup(BackupData data, {DateTime? now}) {
    final today = now ?? DateTime.now();
    final stamp = today.millisecondsSinceEpoch;

    return _db.transaction((txn) async {
      var created = 0;
      var updated = 0;
      var items = 0;
      var incomes = 0;
      var movements = 0;

      Future<Map<String, Object?>?> findBook(String name) async {
        final rows = await txn.query(
          'books',
          where: 'name = ?',
          whereArgs: [name],
          limit: 1,
        );
        return rows.isEmpty ? null : rows.first;
      }

      for (final book in data.books) {
        _check(Book.validateName(book.name));
        _check(Book.validateKind(book.kind));

        // Recorre "Casa", "Casa (2)", "Casa (3)"... hasta dar con un libro
        // del mismo tipo (se le agregan los datos) o con un nombre libre
        // (se crea).
        int? bookId;
        var name = book.name;
        for (var n = 2; bookId == null; n++) {
          final existing = await findBook(name);
          if (existing == null) break;
          if (existing['kind'] == book.kind) {
            bookId = existing['id'] as int;
            updated++;
            break;
          }
          final suffix = ' ($n)';
          final base = book.name.length + suffix.length > Book.maxNameLength
              ? book.name.substring(0, Book.maxNameLength - suffix.length)
              : book.name;
          name = '$base$suffix';
        }
        if (bookId == null) {
          final last = await txn.rawQuery(
            'SELECT COUNT(*) AS n, COALESCE(MAX(created_at), 0) AS latest '
            'FROM books',
          );
          final count = last.first['n'] as int;
          final latest = last.first['latest'] as int;
          bookId = await txn.insert('books', {
            'name': name,
            'color': Book.normalizeColor(
              book.color ??
                  Book.palette[count % Book.palette.length].toARGB32(),
            ),
            'kind': book.kind,
            // Siempre después de los libros que ya había, y en el orden
            // del archivo.
            'created_at': stamp > latest ? stamp : latest + 1,
          });
          created++;
        }

        for (final month in book.months) {
          final year = month.year ?? today.year;
          final monthNumber = month.month ?? today.month;
          final found = await txn.query(
            'periods',
            columns: ['id'],
            where: 'book_id = ? AND year = ? AND month = ?',
            whereArgs: [bookId, year, monthNumber],
          );
          final periodId = found.isNotEmpty
              ? found.first['id'] as int
              : await txn.insert('periods', {
                  'book_id': bookId,
                  'year': year,
                  'month': monthNumber,
                });

          for (final entry in month.incomes) {
            final income = Income(
              periodId: periodId,
              name: entry.description,
              amount: entry.amount,
              method: entry.method,
              recurring: entry.recurring,
            );
            _validateIncome(income);
            await txn.insert('incomes', income.toMap());
            incomes++;
          }
          for (final entry in month.items) {
            await _insertParsedItem(
              txn,
              BudgetItem(
                periodId: periodId,
                name: entry.name,
                amount: entry.amount,
                method: entry.method,
                recurring: entry.recurring,
                paid: entry.checked,
                envelope: entry.envelope,
              ),
              entry.spends,
              stamp,
            );
            items++;
          }
        }

        for (final entry in book.movements) {
          final movement = Movement(
            bookId: bookId,
            amount: entry.amount,
            description: entry.description,
            date: entry.date ?? today,
            method: entry.method,
          );
          _validateMovement(movement);
          await txn.insert('movements', movement.toMap());
          movements++;
        }
      }

      return ImportSummary(
        booksCreated: created,
        booksUpdated: updated,
        items: items,
        incomes: incomes,
        movements: movements,
      );
    });
  }

  // ------------------------------------------------------------ Validación

  static void _validateIncome(Income income) {
    _check(validateText(income.name));
    _check(validateMoney(income.amount));
    _check(validateMethod(income.method));
  }

  static void _validateItem(BudgetItem item) {
    _check(validateText(item.name));
    // Un renglón puede no tener monto todavía (p. ej. "Ahorro").
    _check(validateMoney(item.amount, allowZero: true));
    _check(validateMethod(item.method));
  }

  static void _validateMovement(Movement movement) {
    _check(validateText(movement.description));
    _check(validateMoney(movement.amount.abs()));
    _check(validateMethod(movement.method));
  }

  static void _check(String? error) {
    if (error != null) throw ArgumentError(error);
  }
}
