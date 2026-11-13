// Pruebas de la lectura de listas pegadas desde otra app.
import 'package:flutter_test/flutter_test.dart';
import 'package:pennytree/models/book.dart';
import 'package:pennytree/models/validation.dart';
import 'package:pennytree/utils/note_import.dart';

import 'helpers.dart';

const checklist = r'''
Salario: $900 + 50
Total: $ 950

[  ] Ahorro
[  ] 300 súper ( -120 - 30 = 150 )
[  ] 8 música
[v] 75 préstamo
[v] 10.50 película
[  ] 90 salidas/cine(- 20 - 10- 10 - 5 = 45 )
[  ] 40 Mascota ( = )
[x] $25 papelería y útiles
[v] Ahorro extra:

Restante: $ 60
''';

const ledger = r'''
CUENTA
$700.25 Disponible = 650.00
* 1000 fondo inicial
+ 250 abono 2 marzo
- 400 reparación techo
+10 varios
- 1234.56 pago anticipo
+ 99,90 devolución
''';

void main() {
  group('Lista con casillas', () {
    final items = parseChecklist(checklist);

    test('solo toma las líneas con casilla', () {
      expect(items.map((i) => i.name), [
        'Ahorro',
        'súper',
        'música',
        'préstamo',
        'película',
        'salidas/cine',
        'Mascota',
        'papelería y útiles',
        'Ahorro extra',
      ]);
    });

    test('lee montos, incluso con decimales, signo de dólar o sin monto', () {
      expect(items.map((i) => i.amount), [0, 300, 8, 75, 10.5, 90, 40, 25, 0]);
    });

    test('cualquier marca en la casilla cuenta como pagado', () {
      expect(items.map((i) => i.checked), [
        false, false, false, true, true, false, false, true, true, //
      ]);
    });

    test('un paréntesis indica un fondo con sus gastos parciales', () {
      final food = items[1];
      expect(food.envelope, isTrue);
      expect(food.spends, [120, 30]); // el 150 después del = no es un gasto

      final delivery = items[5];
      expect(delivery.envelope, isTrue);
      expect(delivery.spends, [20, 10, 10, 5]);

      final pet = items[6];
      expect(pet.envelope, isTrue);
      expect(pet.spends, isEmpty);

      expect(items[3].envelope, isFalse);
    });

    test('ignora texto que no es una lista', () {
      expect(parseChecklist(''), isEmpty);
      expect(parseChecklist('hola\n350 súper\n- 20 algo'), isEmpty);
      expect(parseChecklist('[ ]\n[v]   '), isEmpty); // sin nombre
    });

    test('recorta nombres demasiado largos', () {
      final long = parseChecklist('[ ] 10 ${'x' * 200}').single;
      expect(long.name.length, maxTextLength);
    });

    test('se guarda en el mes con sus marcas y gastos', () async {
      final db = await openMemoryDb();
      final bookId = (await db.getBooks()).single.id!;
      final period = await db.openPeriod(bookId, 2026, 3);

      final added = await db.importItems(period.id!, items);
      expect(added, 9);

      final data = await db.getMonthData(period.id!);
      expect(data.items, hasLength(9));
      expect(data.paidCount, 4);
      expect(data.items.every((i) => i.recurring), isTrue);
      final food = data.items[1];
      expect(food.remaining, 150);
      expect(data.items[5].remaining, 45);
      // Pagados: 75 + 10.50 + 25 + 0; fondos gastados: 150 + 45
      expect(data.deducted, closeTo(305.5, 1e-9));

      // También se pueden importar como gastos solo de este mes.
      await db.importItems(
        period.id!,
        parseChecklist('[v] 22 cena'),
        recurring: false,
      );
      expect(
        (await db.getMonthData(period.id!)).items.last.recurring,
        isFalse,
      );
      await db.close();
    });
  });

  group('Lista de abonos y retiros', () {
    final movements = parseLedger(ledger);

    test('lee el signo, el monto y la descripción', () {
      expect(movements.map((m) => m.amount), [
        1000, 250, -400, 10, -1234.56, 99.9, //
      ]);
      expect(movements.first.description, 'fondo inicial');
      expect(movements[1].description, 'abono 2 marzo');
      expect(movements[2].description, 'reparación techo');
    });

    test('ignora líneas sin signo y montos en cero', () {
      expect(parseLedger('CUENTA\n\$700.25 disponible\n+ 0 nada'), isEmpty);
      expect(parseLedger('+ 5').single.description, 'Movimiento');
    });

    test('se guarda en la cuenta con el saldo correcto', () async {
      final db = await openMemoryDb();
      final id = await db.insertBook(
        name: 'Ahorros',
        color: 0xFF2E4A72,
        kind: BookKind.ledger,
      );
      final added = await db.importMovements(
        id,
        movements,
        date: DateTime(2026, 3, 1),
      );
      expect(added, 6);

      final book = (await db.getBooks()).firstWhere((b) => b.id == id);
      expect(book.entryCount, 6);
      expect(
        book.available,
        closeTo(1000 + 250 - 400 + 10 - 1234.56 + 99.9, 1e-6),
      );
      await db.close();
    });
  });

  test('las reglas de AppDatabase aceptan lo que produce el lector', () async {
    // Cualquier línea reconocida debe poder guardarse sin error.
    final db = await openMemoryDb();
    final bookId = (await db.getBooks()).single.id!;
    final period = await db.openPeriod(bookId, 2026, 3);
    const tricky = '''
[ ] 999999999.99 máximo
[ ] 0.01 mínimo
[v] 12 con 'comillas' y "dobles"
[ ] 7 '; DROP TABLE items; --
[ ] 3 fondo (-1 -1 -1 -1 = )
''';
    final parsed = parseChecklist(tricky);
    expect(parsed, hasLength(5));
    await db.importItems(period.id!, parsed);
    final data = await db.getMonthData(period.id!);
    expect(data.items[3].name, "'; DROP TABLE items; --");
    expect(data.items.last.remaining, -1);
    await db.close();
  });
}
