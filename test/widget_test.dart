// Pruebas de funcionamiento de las pantallas.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennytree/models/book.dart';
import 'package:pennytree/screens/book_form_screen.dart';
import 'package:pennytree/screens/books_screen.dart';
import 'package:pennytree/screens/ledger_screen.dart';
import 'package:pennytree/screens/month_screen.dart';
import 'package:pennytree/screens/splash_screen.dart';
import 'package:pennytree/services/app_database.dart';
import 'package:pennytree/theme/app_theme.dart';

import 'helpers.dart';

void main() {
  late AppDatabase db;
  late Book personal;

  setUp(() async {
    db = await openMemoryDb();
    AppDatabase.useForTesting(db);
    personal = (await db.getBooks()).single;
  });

  tearDown(() async {
    AppDatabase.useForTesting(null);
    await db.close();
  });

  /// Monta [home] en una pantalla del tamaño de un teléfono.
  Future<void> pumpApp(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: home));
  }

  final march = DateTime(2026, 3, 15);

  /// Abre la hoja de marzo del libro inicial.
  Future<void> pumpMonth(WidgetTester tester) async {
    await pumpApp(tester, MonthScreen(book: personal, today: march));
    await tester.pumpAndSettle();
  }

  group('Portada', () {
    testWidgets('muestra el nombre de la app y el crédito', (tester) async {
      await pumpApp(tester, const SplashScreen());

      expect(find.text('PennyTree'), findsOneWidget);
      expect(find.text('By Beatriz de Carbonero'), findsOneWidget);
      expect(find.textContaining('Elaborado por'), findsNothing);

      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('dura 2 segundos y pasa a la selección de libros', (
      tester,
    ) async {
      expect(SplashScreen.duration, const Duration(seconds: 2));
      await pumpApp(tester, const SplashScreen());

      await tester.pump(const Duration(milliseconds: 1900));
      expect(find.byType(BooksScreen), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(find.byType(BooksScreen), findsOneWidget);
      expect(find.byType(SplashScreen), findsNothing);
      expect(find.text('Mis Libros'), findsOneWidget);
    });
  });

  group('Libros', () {
    testWidgets('lista el libro inicial', (tester) async {
      await pumpApp(tester, const BooksScreen());
      await tester.pumpAndSettle();

      expect(find.text('Personal'), findsOneWidget);
      expect(find.text('Lista del mes vacía'), findsOneWidget);
      expect(find.text('Disponible: \$0.00'), findsOneWidget);
    });

    testWidgets('crear un libro con nombre, tipo y color', (tester) async {
      await pumpApp(tester, const BooksScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Nuevo libro'));
      await tester.pumpAndSettle();
      expect(find.byType(BookFormScreen), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Ahorros');
      await tester.tap(find.text('Cuenta'));
      await tester.pump();
      // Segundo color de la paleta.
      await tester.ensureVisible(find.bySemanticsLabel('Color').at(1));
      await tester.tap(find.bySemanticsLabel('Color').at(1));
      await tester.pump();
      await tester.ensureVisible(find.text('Crear libro'));
      await tester.tap(find.text('Crear libro'));
      await tester.pumpAndSettle();

      expect(find.byType(BookFormScreen), findsNothing);
      expect(find.text('Ahorros'), findsOneWidget);
      expect(find.text('0 movimientos'), findsOneWidget);
      expect(find.text('Saldo: \$0.00'), findsOneWidget);

      final created = (await db.getBooks()).last;
      expect(created.name, 'Ahorros');
      expect(created.isLedger, isTrue);
      expect(created.colorValue, Book.palette[1].toARGB32());
    });

    testWidgets('no permite nombre vacío ni repetido', (tester) async {
      await pumpApp(tester, const BookFormScreen());
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Crear libro'));
      await tester.tap(find.text('Crear libro'));
      await tester.pumpAndSettle();
      expect(find.text('Escribe un nombre para el libro'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'personal');
      await tester.ensureVisible(find.text('Crear libro'));
      await tester.tap(find.text('Crear libro'));
      await tester.pumpAndSettle();
      expect(find.text('Ya existe un libro con ese nombre'), findsOneWidget);

      expect(await db.getBooks(), hasLength(1));
    });

    testWidgets('editar el nombre y color sin cambiar el tipo', (tester) async {
      await pumpApp(tester, const BooksScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Editar libro'));
      await tester.pumpAndSettle();
      expect(find.text('Editar Libro'), findsOneWidget);
      expect(find.text('Tipo de libro'), findsNothing);

      await tester.enterText(find.byType(TextFormField), 'Hogar');
      await tester.tap(find.bySemanticsLabel('Color').at(5));
      await tester.pump();
      await tester.ensureVisible(find.text('Guardar cambios'));
      await tester.tap(find.text('Guardar cambios'));
      await tester.pumpAndSettle();

      expect(find.text('Hogar'), findsOneWidget);
      expect(find.text('Personal'), findsNothing);
      final book = (await db.getBooks()).single;
      expect(book.name, 'Hogar');
      expect(book.kind, BookKind.monthly);
      expect(book.colorValue, Book.palette[5].toARGB32());
    });

    testWidgets('eliminar un libro pide confirmación', (tester) async {
      await db.insertBook(name: 'Viaje', color: 0xFF2E4A72);
      await pumpApp(tester, const BooksScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Eliminar libro').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('con todo su contenido'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(await db.getBooks(), hasLength(2));

      await tester.tap(find.byTooltip('Eliminar libro').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(find.text('Viaje'), findsNothing);
      expect((await db.getBooks()).single.name, 'Personal');
    });

    testWidgets('no deja eliminar el último libro', (tester) async {
      await pumpApp(tester, const BooksScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Eliminar libro'));
      await tester.pumpAndSettle();

      expect(find.text('Debe existir al menos un libro'), findsOneWidget);
      expect(await db.getBooks(), hasLength(1));
    });
  });

  group('Hoja mensual', () {
    /// Marzo con un ingreso de 900, un pago fijo y un fondo.
    Future<int> seedMarch() async {
      final period = await db.openPeriod(personal.id!, 2026, 3);
      await db.insertIncome(income(period.id!, 'Salario', 900));
      await db.insertItem(item(period.id!, 'Préstamo', 75));
      await db.insertItem(item(period.id!, 'Súper', 300, envelope: true));
      await db.insertItem(item(period.id!, 'Regalo', 18, recurring: false));
      return period.id!;
    }

    testWidgets('muestra el mes, el saldo y la lista', (tester) async {
      await seedMarch();
      await pumpMonth(tester);

      expect(find.text('Marzo 2026'), findsOneWidget);
      expect(find.text('Préstamo'), findsOneWidget);
      expect(find.text('Súper'), findsOneWidget);
      expect(find.text('0 / 3'), findsOneWidget);
      expect(find.text('Quedan \$300.00'), findsOneWidget);
      // Disponible 900 (banner e ingresos); por pagar 393; libre 507.
      expect(find.text('\$900.00'), findsNWidgets(2));
      expect(find.text('\$393.00'), findsOneWidget);
      expect(find.text('\$507.00'), findsOneWidget);
    });

    testWidgets('un toque marca el renglón y lo resta', (tester) async {
      final periodId = await seedMarch();
      await pumpMonth(tester);

      await tester.tap(find.text('Préstamo'));
      await tester.pumpAndSettle();

      expect(find.text('\$825.00'), findsOneWidget); // 900 - 75
      expect(find.text('\$318.00'), findsOneWidget); // por pagar
      expect(find.text('1 / 3'), findsOneWidget);
      expect((await db.getMonthData(periodId)).items.first.paid, isTrue);

      // Otro toque lo desmarca.
      await tester.tap(find.text('Préstamo'));
      await tester.pumpAndSettle();
      expect(find.text('0 / 3'), findsOneWidget);
      expect((await db.getMonthData(periodId)).items.first.paid, isFalse);
    });

    testWidgets('anotar gastos en un fondo', (tester) async {
      final periodId = await seedMarch();
      await pumpMonth(tester);

      await tester.tap(find.text('Súper'));
      await tester.pumpAndSettle();
      expect(find.text('Fondo de \$300.00'), findsOneWidget);

      await tester.enterText(find.byType(TextField), '120');
      await tester.tap(find.text('Anotar'));
      await tester.pumpAndSettle();
      expect(find.text('Quedan \$180.00'), findsWidgets);
      expect(find.text('-\$120.00'), findsOneWidget);

      // Un monto no válido no se anota.
      await tester.tap(find.text('Anotar'));
      await tester.pumpAndSettle();
      expect(find.text('Ingresa un número válido'), findsOneWidget);

      // Cerrar la hoja inferior.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.text('\$780.00'), findsOneWidget); // 900 - 120
      final fund = (await db.getMonthData(periodId)).items[1];
      expect(fund.spent, 120);
    });

    testWidgets('agregar un renglón desde el formulario', (tester) async {
      final periodId = await seedMarch();
      await pumpMonth(tester);

      await tester.tap(find.byTooltip('Nuevo renglón'));
      await tester.pumpAndSettle();
      expect(find.text('Nuevo Renglón'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'Internet');
      await tester.enterText(find.byType(TextFormField).at(1), '35,50');
      await tester.tap(find.text('Efectivo'));
      await tester.pump();
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Internet'), findsOneWidget);
      final added = (await db.getMonthData(periodId)).items.last;
      expect(added.name, 'Internet');
      expect(added.amount, 35.5);
      expect(added.method, 'cash');
      expect(added.recurring, isTrue);
      expect(added.paid, isFalse);
    });

    testWidgets('el formulario exige un concepto', (tester) async {
      final periodId = await seedMarch();
      await pumpMonth(tester);

      await tester.tap(find.byTooltip('Nuevo renglón'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Campo requerido'), findsOneWidget);
      expect((await db.getMonthData(periodId)).items, hasLength(3));
    });

    testWidgets('eliminar un renglón desde su edición', (tester) async {
      final periodId = await seedMarch();
      await pumpMonth(tester);

      await tester.tap(find.byTooltip('Editar renglón').first);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Eliminar renglón'));
      await tester.tap(find.text('Eliminar renglón'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Eliminar'));
      await tester.pumpAndSettle();

      expect(find.text('Préstamo'), findsNothing);
      expect((await db.getMonthData(periodId)).items, hasLength(2));
    });

    testWidgets('agregar un ingreso', (tester) async {
      final periodId = (await db.openPeriod(personal.id!, 2026, 3)).id!;
      await pumpMonth(tester);

      // Sin ingresos, la tarjeta aparece abierta.
      await tester.tap(find.text('Agregar ingreso'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), 'Salario');
      await tester.enterText(find.byType(TextFormField).at(1), '950');
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      final data = await db.getMonthData(periodId);
      expect(data.incomes.single.name, 'Salario');
      expect(data.totalIncome, 950);
      expect(find.text('Salario'), findsOneWidget);
    });

    testWidgets('el mes siguiente trae los recurrentes sin marcar', (
      tester,
    ) async {
      final periodId = await seedMarch();
      final items = (await db.getMonthData(periodId)).items;
      for (final entry in items) {
        await db.setItemPaid(entry.id!, true);
      }
      await pumpMonth(tester);
      expect(find.text('3 / 3'), findsOneWidget);

      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();

      expect(find.text('Abril 2026'), findsOneWidget);
      expect(find.text('Préstamo'), findsOneWidget);
      expect(find.text('Súper'), findsOneWidget);
      expect(find.text('Regalo'), findsNothing); // era solo de marzo
      expect(find.text('0 / 2'), findsOneWidget);

      // Volver a marzo: sigue como estaba.
      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();
      expect(find.text('Marzo 2026'), findsOneWidget);
      expect(find.text('3 / 3'), findsOneWidget);
    });

    testWidgets('pegar una lista la convierte en renglones', (tester) async {
      final periodId = (await db.openPeriod(personal.id!, 2026, 3)).id!;
      await pumpMonth(tester);

      await tester.tap(find.byTooltip('Pegar lista'));
      await tester.pumpAndSettle();
      expect(find.text('Aún no se reconoce ningún renglón'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        '[ ] 300 súper ( -120 - 30 = 150 )\n[v] 75 préstamo\nuna nota suelta',
      );
      await tester.pumpAndSettle();
      expect(find.text('Se reconocieron 2 renglones'), findsOneWidget);

      await tester.ensureVisible(find.text('Agregar'));
      await tester.tap(find.text('Agregar'));
      await tester.pumpAndSettle();

      expect(find.text('súper'), findsOneWidget);
      expect(find.text('préstamo'), findsOneWidget);
      expect(find.text('1 / 2'), findsOneWidget);
      final data = await db.getMonthData(periodId);
      expect(data.items.first.remaining, 150);
      expect(data.items.last.paid, isTrue);
    });
  });

  group('Cuenta', () {
    late Book ledger;

    setUp(() async {
      final id = await db.insertBook(
        name: 'Ahorros',
        color: 0xFF2E4A72,
        kind: BookKind.ledger,
      );
      ledger = (await db.getBook(id))!;
    });

    testWidgets('muestra el saldo y los movimientos', (tester) async {
      await db.insertMovement(movement(ledger.id!, 1000, description: 'Fondo'));
      await db.insertMovement(
        movement(ledger.id!, -250.5, description: 'Reparación', method: 'cash'),
      );
      await pumpApp(tester, LedgerScreen(book: ledger));
      await tester.pumpAndSettle();

      expect(find.text('\$749.50'), findsOneWidget);
      expect(find.text('Banco: \$1000.00'), findsOneWidget);
      expect(find.text('Efectivo: -\$250.50'), findsOneWidget);
      expect(find.text('+\$1000.00'), findsOneWidget);
      expect(find.text('-\$250.50'), findsOneWidget);
    });

    testWidgets('agregar un abono', (tester) async {
      await pumpApp(tester, LedgerScreen(book: ledger));
      await tester.pumpAndSettle();
      expect(find.textContaining('Aún no hay movimientos'), findsOneWidget);

      await tester.tap(find.byTooltip('Nuevo movimiento'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abono'));
      await tester.pump();
      await tester.enterText(find.byType(TextFormField).at(0), '300');
      await tester.enterText(find.byType(TextFormField).at(1), 'Depósito');
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect(find.text('Depósito'), findsOneWidget);
      expect(find.text('+\$300.00'), findsOneWidget);
      final saved = (await db.getMovements(ledger.id!)).single;
      expect(saved.amount, 300);
      expect(saved.isIncome, isTrue);
    });

    testWidgets('por defecto un movimiento nuevo es un retiro', (tester) async {
      await pumpApp(tester, LedgerScreen(book: ledger));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Nuevo movimiento'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField).at(0), '40');
      await tester.enterText(find.byType(TextFormField).at(1), 'Compra');
      await tester.ensureVisible(find.text('Guardar'));
      await tester.tap(find.text('Guardar'));
      await tester.pumpAndSettle();

      expect((await db.getMovements(ledger.id!)).single.amount, -40);
      expect(find.text('-\$40.00'), findsWidgets);
    });

    testWidgets('desde la lista de libros se abre cada tipo', (tester) async {
      await pumpApp(tester, const BooksScreen());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ahorros'));
      await tester.pumpAndSettle();
      expect(find.byType(LedgerScreen), findsOneWidget);

      await tester.tap(find.byTooltip('Cambiar de libro'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Personal'));
      await tester.pumpAndSettle();
      expect(find.byType(MonthScreen), findsOneWidget);
    });
  });
}
