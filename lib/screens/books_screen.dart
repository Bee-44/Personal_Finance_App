import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/app_database.dart';
import '../services/backup_files.dart';
import '../theme/app_colors.dart';
import '../utils/backup.dart';
import '../utils/color_utils.dart';
import '../widgets/medieval.dart';
import 'book_form_screen.dart';
import 'ledger_screen.dart';
import 'month_screen.dart';

/// Pantalla de selección de libros contables.
class BooksScreen extends StatefulWidget {
  const BooksScreen({super.key});

  @override
  State<BooksScreen> createState() => _BooksScreenState();
}

class _BooksScreenState extends State<BooksScreen> {
  List<Book>? _books;

  @override
  void initState() {
    super.initState();
    _loadBooks();
  }

  Future<void> _loadBooks() async {
    // Apertura por calendario: si empezó un mes nuevo, se abre su hoja en
    // todos los libros mensuales.
    await AppDatabase.instance.openCurrentPeriods();
    final books = await AppDatabase.instance.getBooks();
    if (mounted) setState(() => _books = books);
  }

  void _showSnackBar(String message, {bool error = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: error ? AppColors.crimson : AppColors.forest,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  Future<void> _openBook(Book book) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            book.isLedger ? LedgerScreen(book: book) : MonthScreen(book: book),
      ),
    );
    // Al volver, los totales del libro pueden haber cambiado.
    _loadBooks();
  }

  Future<void> _openForm([Book? book]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => BookFormScreen(book: book)),
    );
    if (saved == true && mounted) {
      await _loadBooks();
      if (!mounted) return;
      _showSnackBar(
        book == null
            ? 'Libro creado correctamente'
            : 'Libro actualizado correctamente',
      );
    }
  }

  Future<void> _deleteBook(Book book) async {
    if ((_books?.length ?? 0) <= 1) {
      _showSnackBar('Debe existir al menos un libro', error: true);
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar libro'),
        content: Text(
          '¿Eliminar el libro "${book.name}" con todo su contenido? '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.crimson,
              foregroundColor: AppColors.vellum,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await AppDatabase.instance.deleteBook(book.id!);
    } on StateError {
      if (mounted) _showSnackBar('Debe existir al menos un libro', error: true);
      return;
    }
    if (!mounted) return;
    await _loadBooks();
    if (mounted) _showSnackBar('Libro eliminado correctamente', error: true);
  }

  // ------------------------------------------------- Importar y exportar

  Future<void> _export() async {
    final now = DateTime.now();
    final text = formatBackup(
      await AppDatabase.instance.exportBackup(),
      now: now,
    );
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'pennytree-${now.year}-${two(now.month)}-${two(now.day)}.txt';
    try {
      final saved = await BackupFiles.saveText(name, text);
      if (saved && mounted) _showSnackBar('Respaldo guardado');
    } catch (_) {
      if (mounted) _showSnackBar('No se pudo guardar el archivo', error: true);
    }
  }

  Future<void> _import() async {
    final String? text;
    try {
      text = await BackupFiles.pickText();
    } on FormatException catch (e) {
      if (mounted) _showSnackBar(e.message, error: true);
      return;
    } catch (_) {
      if (mounted) _showSnackBar('No se pudo abrir el archivo', error: true);
      return;
    }
    if (text == null || !mounted) return;
    await importBackupText(text);
  }

  /// Muestra lo que se encontró en [text] y, si el usuario acepta, lo guarda.
  @visibleForTesting
  Future<void> importBackupText(String text) async {
    final data = parseBackup(text);
    if (data.isEmpty) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sin libros'),
          content: const Text(
            'No se encontró ningún libro en el archivo. Cada libro debe '
            'empezar con una línea como:\n\n# Nombre del libro',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _showFormat();
              },
              child: const Text('Ver formato'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Entendido'),
            ),
          ],
        ),
      );
      return;
    }

    String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
    final lines = [
      count(data.books.length, 'libro', 'libros'),
      if (data.itemCount > 0) count(data.itemCount, 'renglón', 'renglones'),
      if (data.incomeCount > 0) count(data.incomeCount, 'ingreso', 'ingresos'),
      if (data.movementCount > 0)
        count(data.movementCount, 'movimiento', 'movimientos'),
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Importar archivo'),
        content: Text(
          'Se encontraron:\n'
          '${lines.map((l) => '•  $l').join('\n')}\n\n'
          '${data.ignoredLines > 0 ? '${count(data.ignoredLines, 'línea no se reconoció', 'líneas no se reconocieron')} y se omitirán.\n\n' : ''}'
          'No se borra nada: si ya tienes un libro con el mismo nombre, '
          'los datos se agregan a ese libro.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Importar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await AppDatabase.instance.importBackup(data);
    } catch (_) {
      if (mounted) {
        _showSnackBar('El archivo tiene datos no válidos', error: true);
      }
      return;
    }
    await _loadBooks();
    if (mounted) _showSnackBar('Archivo importado correctamente');
  }

  void _showFormat() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Formato del archivo'),
        content: const SingleChildScrollView(
          child: Text(
            'Un archivo de texto (.txt) con una línea por dato:\n\n'
            '# Casa\n'
            '+ 900 Salario\n'
            '[ ] 300 Súper ( -120 - 30 = 150 )\n'
            '[v] 75 Préstamo\n'
            '[ ] 20 Jardín #efectivo #unavez\n\n'
            '# Ahorros\n'
            '+ 250 Abono\n'
            '- 40 Compra\n\n'
            '•  # inicia un libro.\n'
            '•  [ ] es un renglón y [v] uno ya pagado.\n'
            '•  El paréntesis indica un fondo y sus gastos.\n'
            '•  + es un ingreso o abono; - es un retiro.\n'
            '•  #efectivo: se paga en efectivo.\n'
            '•  #unavez: no se repite cada mes.\n\n'
            'Un libro con casillas es mensual; uno con solo + y - es una '
            'cuenta. Lo demás se ignora.',
            style: TextStyle(fontSize: 16.5),
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Entendido'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final books = _books;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Mis Libros'),
        actions: [
          PopupMenuButton<VoidCallback>(
            tooltip: 'Importar y exportar',
            icon: const Icon(Icons.more_vert, color: AppColors.goldLight),
            onSelected: (action) => action(),
            itemBuilder: (context) => [
              PopupMenuItem(
                value: _import,
                child: const ListTile(
                  leading: Icon(Icons.file_open_outlined),
                  title: Text('Importar archivo de texto'),
                ),
              ),
              PopupMenuItem(
                value: _export,
                child: const ListTile(
                  leading: Icon(Icons.save_alt),
                  title: Text('Exportar respaldo'),
                ),
              ),
              PopupMenuItem(
                value: _showFormat,
                child: const ListTile(
                  leading: Icon(Icons.help_outline),
                  title: Text('Formato del archivo'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: ParchmentBackground(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          child: books == null
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 16, 14, 110),
                  itemCount: books.length + 1,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return const Padding(
                        padding: EdgeInsets.fromLTRB(6, 0, 6, 10),
                        child: Text(
                          'Elige el libro que quieres abrir',
                          style: TextStyle(
                            fontSize: 19,
                            fontStyle: FontStyle.italic,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      );
                    }
                    final book = books[index - 1];
                    return FadeSlideIn(
                      key: ValueKey(book.id),
                      index: index - 1,
                      child: _BookCard(
                        book: book,
                        onTap: () => _openBook(book),
                        onEdit: () => _openForm(book),
                        onDelete: () => _deleteBook(book),
                      ),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: MedievalButton(
        label: 'Nuevo libro',
        icon: Icons.add,
        onPressed: () => _openForm(),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _BookCard extends StatelessWidget {
  final Book book;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _BookCard({
    required this.book,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final color = book.color;
    final count = book.entryCount;
    final String detail;
    if (book.isLedger) {
      detail = count == 1 ? '1 movimiento' : '$count movimientos';
    } else if (count == 0) {
      detail = 'Lista del mes vacía';
    } else {
      detail = '${book.paidCount} de $count pagados';
    }
    return OrnateCard(
      margin: const EdgeInsets.symmetric(vertical: 7),
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Lomo del libro, con su color.
            Container(
              width: 68,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [darken(color, 0.3), color, darken(color, 0.12)],
                  stops: const [0, 0.45, 1],
                ),
                border: const Border(
                  right: BorderSide(color: AppColors.gold, width: 1.5),
                ),
              ),
              child: const Icon(
                Icons.history_edu,
                color: AppColors.goldLight,
                size: 32,
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 4, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      book.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail,
                      style: const TextStyle(
                        fontSize: 17,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    Text(
                      '${book.isLedger ? 'Saldo' : 'Disponible'}: '
                      '${formatMoney(book.available)}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: book.available < 0
                            ? AppColors.crimson
                            : AppColors.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Editar libro',
                    icon: const Icon(Icons.edit, size: 22),
                    onPressed: onEdit,
                  ),
                  IconButton(
                    tooltip: 'Eliminar libro',
                    icon: const Icon(
                      Icons.delete,
                      size: 22,
                      color: AppColors.crimson,
                    ),
                    onPressed: onDelete,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
