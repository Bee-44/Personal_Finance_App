// Pruebas de apertura y cierre de mes por calendario, del sobrante que se
// arrastra y de la pantalla de historial.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pennytree/models/book.dart';
import 'package:pennytree/models/month.dart';
import 'package:pennytree/screens/history_screen.dart';
import 'package:pennytree/screens/month_screen.dart';
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

  /// Enero: entran 1000, se pagan 300 → sobran 700.
  /// Febrero: entran 1000 más, se pagan 1900 → faltan 200.
  /// Marzo: entran 1000.
  Future<List<Period>> seedThreeMonths() async {
    final jan = await db.openPeriod(personal.id!, 2026, 1);
    await db.insertIncome(income(jan.id!, 'Salario', 1000));
    await db.insertItem(item(jan.id!, 'Renta', 300, paid: true));
    await db.insertItem(item(jan.id!, 'Luz', 50)); // quedó sin pagar

    final feb = await db.openPeriod(personal.id!, 2026, 2);
    final febItems = (await db.getMonthData(feb.id!)).items;
    await db.setItemPaid(febItems[0].id!, true);
    await db.insertItem(
      item(feb.id!, 'Reparación', 1600, paid: true, recurring: false),
    );

    final mar = await db.openPeriod(personal.id!, 2026, 3);
    return [jan, feb, mar];
  }

  group('Sobrante', () {
    test('el primer mes no trae sobrante', () async {
      final jan = await db.openPeriod(personal.id!, 2026, 1);
      await db.insertIncome(income(jan.id!, 'Salario', 1000));
      final data = await db.getMonthData(jan.id!);
      expect(data.carryIn, 0);
      expect(data.available, 1000);
    });

    test('lo que sobra pasa al mes siguiente, mes tras mes', () async {
      final [jan, feb, mar] = await seedThreeMonths();

      final january = await db.getMonthData(jan.id!);
      expect(january.available, 700);

      final february = await db.getMonthData(feb.id!);
      expect(february.carryIn, 700);
      expect(february.totalIncome, 1000);
      expect(february.deducted, 1900);
      expect(february.available, -200); // se gastó de más

      // El faltante también se arrastra.
      final march = await db.getMonthData(mar.id!);
      expect(march.carryIn, -200);
      expect(march.available, 800);
      expect(march.pending, 350); // Renta y Luz, sin marcar
      expect(march.free, 450);
    });

    test('lo que quedó sin pagar no se descuenta: ese dinero sigue', () async {
      final [jan, feb, _] = await seedThreeMonths();
      // "Luz" (50) quedó sin pagar en enero; sus 50 llegan a febrero.
      expect((await db.getMonthData(jan.id!)).pending, 50);
      expect((await db.getMonthData(feb.id!)).carryIn, 700);
    });

    test('se arrastra por separado en banco y en efectivo', () async {
      final jan = await db.openPeriod(personal.id!, 2026, 1);
      await db.insertIncome(income(jan.id!, 'Salario', 500));
      await db.insertIncome(income(jan.id!, 'Venta', 80, method: 'cash'));
      await db.insertItem(item(jan.id!, 'Luz', 60, paid: true));
      final fund = await db.insertItem(
        item(jan.id!, 'Mercado', 100, envelope: true, method: 'cash'),
      );
      await db.addSpend(fund, 30);

      final feb = await db.openPeriod(personal.id!, 2026, 2);
      final data = await db.getMonthData(feb.id!);
      expect(data.carryBank, 440);
      expect(data.carryCash, 50);
      // Febrero repite los dos ingresos y aún no gasta nada.
      expect(data.availableBy('bank'), 940);
      expect(data.availableBy('cash'), 130);
      expect(data.available, 1070);
    });

    test('corregir un mes cerrado ajusta los meses siguientes', () async {
      final [jan, _, mar] = await seedThreeMonths();
      final light = (await db.getMonthData(jan.id!)).items[1];

      await db.setItemPaid(light.id!, true); // se pagó la luz de enero
      expect((await db.getMonthData(mar.id!)).carryIn, -250);

      await db.setItemPaid(light.id!, false);
      expect((await db.getMonthData(mar.id!)).carryIn, -200);
    });

    test('los meses saltados no rompen la cadena', () async {
      final jan = await db.openPeriod(personal.id!, 2026, 1);
      await db.insertIncome(income(jan.id!, 'Salario', 1000));
      await db.insertItem(item(jan.id!, 'Renta', 300, paid: true));

      // Nadie abrió la app de febrero a mayo.
      final june = await db.openPeriod(personal.id!, 2026, 6);
      final data = await db.getMonthData(june.id!);
      expect(data.carryIn, 700);
      expect(data.available, 1700);
    });

    test('cada libro arrastra solo lo suyo', () async {
      await seedThreeMonths();
      final other = await db.insertBook(name: 'Viaje', color: 0xFF2E4A72);
      final march = await db.openPeriod(other, 2026, 3);
      expect((await db.getMonthData(march.id!)).carryIn, 0);
    });

    test('el resumen del libro incluye el sobrante', () async {
      await seedThreeMonths();
      final book = (await db.getBooks(now: DateTime(2026, 3, 10))).single;
      expect(book.available, 800);
    });
  });

  group('Calendario', () {
    test('un mes está cerrado, en curso o es próximo según la fecha', () async {
      final [jan, feb, mar] = await seedThreeMonths();
      final today = DateTime(2026, 2, 14);
      expect((await db.getMonthData(jan.id!)).statusAt(today), MonthStatus.closed);
      expect((await db.getMonthData(feb.id!)).statusAt(today), MonthStatus.open);
      expect(
        (await db.getMonthData(mar.id!)).statusAt(today),
        MonthStatus.upcoming,
      );
      // El último día del mes sigue en curso; el primero del siguiente, no.
      final data = await db.getMonthData(feb.id!);
      expect(data.statusAt(DateTime(2026, 2, 28, 23, 59)), MonthStatus.open);
      expect(data.statusAt(DateTime(2026, 3, 1)), MonthStatus.closed);
      // Cambio de año.
      expect(data.statusAt(DateTime(2027, 1, 1)), MonthStatus.closed);
    });

    test('al iniciar la app se abre el mes en todos los libros', () async {
      final jan = await db.openPeriod(personal.id!, 2026, 1);
      await db.insertItem(item(jan.id!, 'Renta', 300, paid: true));
      final trip = await db.insertBook(name: 'Viaje', color: 0xFF2E4A72);
      final ledger = await db.insertBook(
        name: 'Ahorros',
        color: 0xFF8C2B23,
        kind: BookKind.ledger,
      );

      final april = DateTime(2026, 4, 1);
      await db.openCurrentPeriods(now: april);
      await db.openCurrentPeriods(now: april); // repetirlo no duplica

      final mine = await db.getPeriods(personal.id!);
      expect(mine.map((p) => p.label), ['Enero 2026', 'Abril 2026']);
      final opened = await db.getMonthData(mine.last.id!);
      expect(opened.items.single.name, 'Renta');
      expect(opened.items.single.paid, isFalse);

      expect((await db.getPeriods(trip)).single.label, 'Abril 2026');
      expect(await db.getPeriods(ledger), isEmpty); // las cuentas no tienen meses
    });

    test('el historial va del mes más nuevo al más antiguo', () async {
      await seedThreeMonths();
      final history = await db.getHistory(personal.id!);
      expect(history.map((m) => m.period.label), [
        'Marzo 2026',
        'Febrero 2026',
        'Enero 2026',
      ]);
      expect(history.map((m) => m.available), [800, -200, 700]);
      expect(history.map((m) => m.paidCount), [0, 2, 1]);
    });
  });

  group('Pantallas', () {
    Future<void> pump(WidgetTester tester, Widget home) async {
      tester.view.physicalSize = const Size(1080, 2340);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(theme: buildAppTheme(), home: home));
      await tester.pumpAndSettle();
    }

    final march = DateTime(2026, 3, 15);

    testWidgets('el mes en curso muestra el sobrante que recibió', (
      tester,
    ) async {
      await seedThreeMonths();
      await pump(tester, MonthScreen(book: personal, today: march));

      expect(find.text('Marzo 2026'), findsOneWidget);
      expect(find.text('Saldo Disponible'), findsOneWidget);
      expect(find.textContaining('Mes cerrado'), findsNothing);
      // Entradas del mes: -200 de sobrante + 1000 de ingresos; como aún no
      // se paga nada, coincide con el saldo disponible.
      expect(find.text('\$800.00'), findsNWidgets(2));

      await tester.tap(find.text('Ingresos'));
      await tester.pumpAndSettle();
      expect(find.text('Sobrante anterior'), findsOneWidget);
      expect(find.text('-\$200.00'), findsOneWidget);
    });

    testWidgets('un mes pasado está cerrado y no se puede modificar', (
      tester,
    ) async {
      final [_, feb, _] = await seedThreeMonths();
      await pump(tester, MonthScreen(book: personal, today: march));

      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();

      expect(find.text('Febrero 2026'), findsOneWidget);
      expect(find.textContaining('Mes cerrado'), findsOneWidget);
      expect(find.text('Sobrante del Mes'), findsOneWidget);
      expect(find.byTooltip('Nuevo renglón'), findsNothing);
      expect(find.byTooltip('Editar renglón'), findsNothing);
      expect(find.byTooltip('Pegar lista'), findsNothing);

      // Tocar un renglón no lo cambia.
      await tester.tap(find.text('Luz'));
      await tester.pumpAndSettle();
      final light = (await db.getMonthData(feb.id!)).items[1];
      expect(light.paid, isFalse);
    });

    testWidgets('un mes cerrado se puede reabrir para corregirlo', (
      tester,
    ) async {
      final [_, feb, mar] = await seedThreeMonths();
      await pump(tester, MonthScreen(book: personal, today: march));
      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Reabrir'));
      await tester.pumpAndSettle();
      expect(find.text('Reabrir mes cerrado'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Reabrir'));
      await tester.pumpAndSettle();

      expect(find.text('Corrigiendo un mes cerrado'), findsOneWidget);
      expect(find.byTooltip('Nuevo renglón'), findsOneWidget);

      await tester.tap(find.text('Luz'));
      await tester.pumpAndSettle();
      expect((await db.getMonthData(feb.id!)).items[1].paid, isTrue);
      // La corrección llega al mes siguiente.
      expect((await db.getMonthData(mar.id!)).carryIn, -250);

      // Al cambiar de mes y volver, queda cerrado otra vez.
      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Mes anterior'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Mes cerrado'), findsOneWidget);
    });

    testWidgets('el mes siguiente se puede preparar por adelantado', (
      tester,
    ) async {
      await seedThreeMonths();
      await pump(tester, MonthScreen(book: personal, today: march));

      await tester.tap(find.byTooltip('Mes siguiente'));
      await tester.pumpAndSettle();
      expect(find.text('Abril 2026'), findsOneWidget);
      expect(find.textContaining('Mes próximo'), findsOneWidget);
      expect(find.byTooltip('Nuevo renglón'), findsOneWidget);
    });

    testWidgets('el historial resume cada mes y permite abrirlo', (
      tester,
    ) async {
      await seedThreeMonths();
      await pump(tester, MonthScreen(book: personal, today: march));

      await tester.tap(find.byTooltip('Historial'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsOneWidget);
      expect(find.text('Personal · 3 meses'), findsOneWidget);
      expect(find.text('En curso'), findsOneWidget);
      expect(find.text('Cerrado'), findsNWidgets(2));
      expect(find.text('\$700.00'), findsOneWidget); // sobrante de enero
      expect(find.text('-\$200.00'), findsNWidgets(2)); // feb y arrastre a mar
      expect(find.text('1 de 2 pagados · \$50.00 sin pagar'), findsOneWidget);

      await tester.tap(find.text('Enero 2026'));
      await tester.pumpAndSettle();
      expect(find.byType(HistoryScreen), findsNothing);
      expect(find.text('Enero 2026'), findsOneWidget);
      expect(find.textContaining('Mes cerrado'), findsOneWidget);
    });
  });
}
