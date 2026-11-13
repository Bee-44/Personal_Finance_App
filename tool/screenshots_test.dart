// Generates the README screenshots from the real screens, using made-up
// sample data in an in-memory database. No device or personal data involved.
//
//   flutter test tool/screenshots_test.dart
//
// Output: docs/screenshots/*.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pennytree/models/book.dart';
import 'package:pennytree/models/month.dart';
import 'package:pennytree/models/movement.dart';
import 'package:pennytree/screens/book_form_screen.dart';
import 'package:pennytree/screens/books_screen.dart';
import 'package:pennytree/screens/history_screen.dart';
import 'package:pennytree/screens/ledger_screen.dart';
import 'package:pennytree/screens/month_screen.dart';
import 'package:pennytree/screens/splash_screen.dart';
import 'package:pennytree/services/app_database.dart';
import 'package:pennytree/theme/app_theme.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _logicalSize = Size(390, 844);
const _pixelRatio = 2.0;
final _boundaryKey = GlobalKey();

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final file in files) {
    final bytes = File(file).readAsBytesSync();
    loader.addFont(
      Future.value(ByteData.view(Uint8List.fromList(bytes).buffer)),
    );
  }
  await loader.load();
}

/// Tests render with a placeholder font unless the real ones are loaded.
Future<void> _loadFonts() async {
  await _loadFont('CrimsonText', [
    'assets/fonts/CrimsonText-Regular.ttf',
    'assets/fonts/CrimsonText-Italic.ttf',
    'assets/fonts/CrimsonText-SemiBold.ttf',
    'assets/fonts/CrimsonText-Bold.ttf',
  ]);
  await _loadFont('CinzelDecorative', [
    'assets/fonts/CinzelDecorative-Regular.ttf',
    'assets/fonts/CinzelDecorative-Bold.ttf',
  ]);
  // The icon font ships with the Flutter SDK, next to the test engine:
  // bin/cache/artifacts/engine/<platform>/flutter_tester
  final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
  await _loadFont('MaterialIcons', [
    p.join(artifacts.path, 'material_fonts', 'MaterialIcons-Regular.otf'),
  ]);
}

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = _logicalSize * _pixelRatio;
  tester.view.devicePixelRatio = _pixelRatio;
  await tester.pumpWidget(
    RepaintBoundary(
      key: _boundaryKey,
      child: MaterialApp(
        key: UniqueKey(), // a fresh navigator for every screenshot
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        locale: const Locale('es'),
        supportedLocales: const [Locale('es')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: home,
      ),
    ),
  );
}

Future<void> _shoot(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: _pixelRatio);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(data!.buffer.asUint8List());
  });
}

Income _income(int period, String name, double amount, {bool once = false}) =>
    Income(periodId: period, name: name, amount: amount, recurring: !once);

BudgetItem _item(
  int period,
  String name,
  double amount, {
  bool paid = false,
  bool fund = false,
  bool once = false,
  bool cash = false,
}) => BudgetItem(
  periodId: period,
  name: name,
  amount: amount,
  paid: paid,
  envelope: fund,
  recurring: !once,
  method: cash ? 'cash' : 'bank',
);

/// Three months of a household budget, a trip budget and a savings account.
/// Everything here is invented.
Future<void> _seed(AppDatabase db, DateTime today) async {
  DateTime monthsAgo(int n) => DateTime(today.year, today.month - n);

  final home = (await db.getBooks()).single;
  await db.updateBook(
    home.id!,
    name: 'Hogar',
    color: Book.palette[0].toARGB32(),
  );

  // Two months ago: the recurring list is born here.
  final first = monthsAgo(2);
  final a = await db.openPeriod(home.id!, first.year, first.month);
  await db.insertIncome(_income(a.id!, 'Salario', 1850));
  await db.insertIncome(
    Income(
      periodId: a.id!,
      name: 'Clases de fin de semana',
      amount: 150,
      method: 'cash',
    ),
  );
  await db.insertItem(_item(a.id!, 'Renta', 620, paid: true));
  final food = await db.insertItem(_item(a.id!, 'Súper', 320, fund: true));
  await db.insertItem(_item(a.id!, 'Luz', 48.50, paid: true));
  await db.insertItem(_item(a.id!, 'Internet', 35, paid: true));
  final ride = await db.insertItem(
    _item(a.id!, 'Transporte', 60, fund: true, cash: true),
  );
  await db.insertItem(_item(a.id!, 'Gimnasio', 29.99, paid: true));
  await db.insertItem(_item(a.id!, 'Ahorro', 200, paid: true));
  await db.insertItem(_item(a.id!, 'Streaming', 12.99, paid: true));
  for (final spend in [92.30, 71.15, 88.40, 54.20]) {
    await db.addSpend(food, spend);
  }
  await db.addSpend(ride, 48);

  // Last month: copied from the previous one, plus a one-off repair.
  final second = monthsAgo(1);
  final b = await db.openPeriod(home.id!, second.year, second.month);
  final bItems = (await db.getMonthData(b.id!)).items;
  for (final item in bItems) {
    if (!item.envelope && item.name != 'Gimnasio') {
      await db.setItemPaid(item.id!, true);
    }
  }
  for (final spend in [110.75, 96.20, 84.10]) {
    await db.addSpend(bItems[1].id!, spend);
  }
  await db.addSpend(bItems[4].id!, 57.50);
  await db.insertItem(
    _item(b.id!, 'Reparación del auto', 380, paid: true, once: true),
  );

  // This month, in progress.
  final c = await db.openPeriod(home.id!, today.year, today.month);
  await db.insertIncome(_income(c.id!, 'Proyecto freelance', 240, once: true));
  final cItems = (await db.getMonthData(c.id!)).items;
  for (final name in ['Renta', 'Luz', 'Internet', 'Streaming']) {
    await db.setItemPaid(cItems.firstWhere((i) => i.name == name).id!, true);
  }
  await db.addSpend(cItems[1].id!, 86.40);
  await db.addSpend(cItems[1].id!, 54.15);
  await db.addSpend(cItems[4].id!, 22);
  await db.insertItem(
    _item(c.id!, 'Regalo de cumpleaños', 40, once: true, cash: true),
  );

  // A second monthly book.
  final trip = await db.insertBook(
    name: 'Viaje a la playa',
    color: Book.palette[1].toARGB32(),
  );
  final t = await db.openPeriod(trip, today.year, today.month);
  await db.insertIncome(
    _income(t.id!, 'Presupuesto del viaje', 900, once: true),
  );
  await db.insertItem(_item(t.id!, 'Hospedaje', 360, paid: true, once: true));
  await db.insertItem(_item(t.id!, 'Gasolina', 90, paid: true, once: true));
  final meals = await db.insertItem(
    _item(t.id!, 'Comidas', 220, fund: true, once: true),
  );
  await db.addSpend(meals, 64.50);
  await db.insertItem(_item(t.id!, 'Paseo en lancha', 75, once: true));
  await db.insertItem(_item(t.id!, 'Recuerdos', 50, once: true, cash: true));

  // A savings account.
  final savings = await db.insertBook(
    name: 'Ahorros',
    color: Book.palette[5].toARGB32(),
    kind: BookKind.ledger,
  );
  Future<void> move(
    double amount,
    String text,
    int daysAgo, {
    bool cash = false,
  }) {
    return db.insertMovement(
      Movement(
        bookId: savings,
        amount: amount,
        description: text,
        date: today.subtract(Duration(days: daysAgo)),
        method: cash ? 'cash' : 'bank',
      ),
    );
  }

  await move(1500, 'Fondo inicial', 75);
  await move(200, 'Abono mensual', 61);
  await move(-420, 'Lavadora nueva', 44);
  await move(200, 'Abono mensual', 31);
  await move(85.50, 'Venta de bicicleta', 18, cash: true);
  await move(-64.90, 'Regalos', 9, cash: true);
  await move(200, 'Abono mensual', 2);
}

void main() {
  final today = DateTime.now();
  late AppDatabase db;

  setUpAll(_loadFonts);

  setUp(() async {
    sqfliteFfiInit();
    db = await AppDatabase.open(
      databaseFactoryFfiNoIsolate,
      inMemoryDatabasePath,
    );
    AppDatabase.useForTesting(db);
    await _seed(db, today);
    debugDisableShadows = false; // real shadows, as on a device
  });

  tearDown(() async {
    debugDisableShadows = true;
    AppDatabase.useForTesting(null);
    await db.close();
  });

  Future<Book> book(String name) async =>
      (await db.getBooks()).firstWhere((b) => b.name == name);

  testWidgets('cover', (tester) async {
    await _pump(tester, const SplashScreen());
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/images/pennytree_logo.jpg'),
        tester.element(find.byType(SplashScreen)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 1200));
    await _shoot(tester, '01-cover');
    debugDisableShadows = true;
    await tester.pumpAndSettle(const Duration(seconds: 3));
  });

  testWidgets('books', (tester) async {
    await _pump(tester, const BooksScreen());
    await tester.pumpAndSettle();
    await _shoot(tester, '02-books');
    debugDisableShadows = true;
  });

  testWidgets('month', (tester) async {
    await _pump(tester, MonthScreen(book: await book('Hogar'), today: today));
    await tester.pumpAndSettle();
    await _shoot(tester, '03-month');

    // The incomes card, opened, with the carried-over balance.
    await tester.tap(find.text('Ingresos'));
    await tester.pumpAndSettle();
    await _shoot(tester, '04-carry-over');

    // A fund and its partial spends.
    await tester.tap(find.text('Ingresos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Súper'));
    await tester.pumpAndSettle();
    await _shoot(tester, '05-fund');
    debugDisableShadows = true;
  });

  testWidgets('closed month', (tester) async {
    await _pump(tester, MonthScreen(book: await book('Hogar'), today: today));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Mes anterior'));
    await tester.pumpAndSettle();
    await _shoot(tester, '06-closed-month');
    debugDisableShadows = true;
  });

  testWidgets('history', (tester) async {
    await _pump(tester, HistoryScreen(book: await book('Hogar'), today: today));
    await tester.pumpAndSettle();
    await _shoot(tester, '07-history');
    debugDisableShadows = true;
  });

  testWidgets('ledger', (tester) async {
    await _pump(tester, LedgerScreen(book: await book('Ahorros')));
    await tester.pumpAndSettle();
    await _shoot(tester, '08-ledger');
    debugDisableShadows = true;
  });

  testWidgets('new book', (tester) async {
    await _pump(tester, const BookFormScreen());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'Negocio');
    await tester.tap(find.bySemanticsLabel('Color').at(3));
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await _shoot(tester, '09-new-book');
    debugDisableShadows = true;
  });
}
