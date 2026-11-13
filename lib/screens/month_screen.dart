import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/book.dart';
import '../models/month.dart';
import '../models/validation.dart';
import '../services/app_database.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';
import '../widgets/balance_banner.dart';
import '../widgets/budget_item_tile.dart';
import '../widgets/form_widgets.dart';
import '../widgets/medieval.dart';
import 'entry_forms.dart';
import 'history_screen.dart';
import 'import_screen.dart';

/// Hoja mensual de un libro: ingresos y la lista de renglones para marcar.
class MonthScreen extends StatefulWidget {
  final Book book;

  /// Fecha que se toma como "hoy". Solo se cambia en pruebas.
  final DateTime? today;

  const MonthScreen({super.key, required this.book, this.today});

  @override
  State<MonthScreen> createState() => _MonthScreenState();
}

class _MonthScreenState extends State<MonthScreen> {
  List<Period> _periods = const [];
  MonthData? _data;
  bool _incomesOpen = false;

  /// El usuario reabrió un mes cerrado para corregirlo. Dura hasta que
  /// cambia de mes.
  bool _unlocked = false;

  int get _bookId => widget.book.id!;
  DateTime get _today => widget.today ?? DateTime.now();

  MonthStatus get _status =>
      _data?.statusAt(_today) ?? MonthStatus.open;

  /// Un mes cerrado es de solo lectura, salvo que se haya reabierto.
  bool get _locked => _status == MonthStatus.closed && !_unlocked;

  /// Se puede preparar, como mucho, el mes siguiente al actual.
  int get _lastAllowedIndex => Period.indexOf(_today.year, _today.month) + 1;

  @override
  void initState() {
    super.initState();
    _openMonth(_today.year, _today.month, first: true);
  }

  Future<void> _openMonth(int year, int month, {bool first = false}) async {
    final db = AppDatabase.instance;
    final period = await db.openPeriod(_bookId, year, month);
    final periods = await db.getPeriods(_bookId);
    final data = await db.getMonthData(period.id!);
    if (!mounted) return;
    setState(() {
      _periods = periods;
      _data = data;
      _unlocked = false;
      // La primera vez, si aún no hay ingresos, se muestran abiertos.
      if (first) _incomesOpen = data.incomes.isEmpty;
    });
  }

  Future<void> _reopen() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reabrir mes cerrado'),
        content: const Text(
          'Podrás corregir este mes. Lo que cambies ajustará el sobrante '
          'de los meses siguientes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reabrir'),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) setState(() => _unlocked = true);
  }

  Future<void> _openHistory() async {
    final period = await Navigator.push<Period>(
      context,
      MaterialPageRoute(
        builder: (_) => HistoryScreen(book: widget.book, today: widget.today),
      ),
    );
    if (period != null && mounted) _openMonth(period.year, period.month);
  }

  Future<void> _reload() async {
    final id = _data?.period.id;
    if (id == null) return;
    final data = await AppDatabase.instance.getMonthData(id);
    if (mounted) setState(() => _data = data);
  }

  int get _position =>
      _periods.indexWhere((p) => p.id == _data?.period.id);

  bool get _canGoBack => _position > 0;

  bool get _canGoForward {
    final data = _data;
    if (data == null) return false;
    return _position < _periods.length - 1 ||
        data.period.index < _lastAllowedIndex;
  }

  void _goBack() {
    final previous = _periods[_position - 1];
    _openMonth(previous.year, previous.month);
  }

  void _goForward() {
    if (_position < _periods.length - 1) {
      final next = _periods[_position + 1];
      _openMonth(next.year, next.month);
    } else {
      final index = _data!.period.index + 1;
      _openMonth(index ~/ 12, index % 12 + 1);
    }
  }

  Future<void> _push(Widget screen, {String? notice}) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
    if (saved == true && mounted) {
      await _reload();
      if (mounted && notice != null) showNotice(context, notice);
    }
  }

  Future<void> _toggle(BudgetItem item) async {
    await AppDatabase.instance.setItemPaid(item.id!, !item.paid);
    await _reload();
  }

  Future<void> _openSpends(BudgetItem item) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.vellum,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        side: BorderSide(color: AppColors.gold, width: 1.5),
      ),
      builder: (_) => _SpendsSheet(item: item),
    );
    await _reload();
  }

  Future<void> _import() async {
    final added = await Navigator.push<int>(
      context,
      MaterialPageRoute(
        builder: (_) => ImportScreen.items(periodId: _data!.period.id!),
      ),
    );
    if (added != null && added > 0 && mounted) {
      await _reload();
      if (mounted) {
        showNotice(
          context,
          added == 1 ? 'Se agregó 1 renglón' : 'Se agregaron $added renglones',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.book.color;
    final data = _data;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: darken(color, 0.35),
        leading: IconButton(
          tooltip: 'Cambiar de libro',
          icon: const Icon(Icons.history_edu, color: AppColors.goldLight),
          onPressed: () => Navigator.pop(context),
        ),
        title: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            widget.book.name,
            style: const TextStyle(
              fontFamily: bodyFont,
              fontWeight: FontWeight.w700,
              color: AppColors.goldLight,
              fontSize: 28,
            ),
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Historial',
            icon: const Icon(Icons.auto_stories, color: AppColors.goldLight),
            onPressed: data == null ? null : _openHistory,
          ),
          if (!_locked)
            IconButton(
              tooltip: 'Pegar lista',
              icon: const Icon(
                Icons.content_paste_go,
                color: AppColors.goldLight,
              ),
              onPressed: data == null ? null : _import,
            ),
        ],
      ),
      body: ParchmentBackground(
        child: data == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 120),
                children: [
                  _MonthBar(
                    label: data.period.label,
                    onBack: _canGoBack ? _goBack : null,
                    onForward: _canGoForward ? _goForward : null,
                  ),
                  _StatusStrip(
                    status: _status,
                    unlocked: _unlocked,
                    onReopen: _reopen,
                    onLock: () => setState(() => _unlocked = false),
                  ),
                  const SizedBox(height: 6),
                  BalanceBanner(
                    color: color,
                    title: _status == MonthStatus.closed
                        ? 'Sobrante del Mes'
                        : 'Saldo Disponible',
                    total: data.available,
                    breakdown: {
                      'Banco': data.availableBy(PayMethod.bank),
                      'Efectivo': data.availableBy(PayMethod.cash),
                    },
                    footer: {'Por pagar': data.pending, 'Libre': data.free},
                  ),
                  const SizedBox(height: 12),
                  _IncomesCard(
                    data: data,
                    locked: _locked,
                    open: _incomesOpen,
                    onToggle: () => setState(() => _incomesOpen = !_incomesOpen),
                    onAdd: () => _push(
                      IncomeFormScreen(periodId: data.period.id!),
                      notice: 'Ingreso agregado',
                    ),
                    onEdit: (income) => _push(
                      IncomeFormScreen(
                        periodId: data.period.id!,
                        income: income,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const SizedBox(width: 6),
                      Text('Lista del mes', style: displayStyle(size: 17)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: OrnamentDivider(width: double.infinity),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '${data.paidCount} / ${data.items.length}',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                          color: AppColors.inkSoft,
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (data.items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 36,
                        horizontal: 12,
                      ),
                      child: Text(
                        _locked
                            ? 'Este mes no tuvo renglones.'
                            : 'Aún no hay renglones este mes.\n'
                                'Agrega uno con la moneda o pega tu lista.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 19,
                          fontStyle: FontStyle.italic,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    )
                  else
                    for (final (index, item) in data.items.indexed)
                      FadeSlideIn(
                        key: ValueKey(item.id),
                        index: index,
                        child: BudgetItemTile(
                          item: item,
                          enabled: !_locked,
                          onToggle: () => _toggle(item),
                          onOpenSpends: () => _openSpends(item),
                          onEdit: () => _push(
                            ItemFormScreen(
                              periodId: data.period.id!,
                              item: item,
                            ),
                          ),
                        ),
                      ),
                ],
              ),
      ),
      floatingActionButton: data == null || _locked
          ? null
          : Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: CoinButton(
                icon: Icons.add,
                tooltip: 'Nuevo renglón',
                onPressed: () => _push(
                  ItemFormScreen(periodId: data.period.id!),
                  notice: 'Renglón agregado',
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

/// Selector de mes: ‹ Noviembre 2026 ›
class _MonthBar extends StatelessWidget {
  final String label;
  final VoidCallback? onBack;
  final VoidCallback? onForward;

  const _MonthBar({required this.label, this.onBack, this.onForward});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Mes anterior',
          icon: const Icon(Icons.chevron_left, size: 30),
          onPressed: onBack,
        ),
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            child: FittedBox(
              key: ValueKey(label),
              fit: BoxFit.scaleDown,
              child: Text(label, style: displayStyle(size: 20)),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Mes siguiente',
          icon: const Icon(Icons.chevron_right, size: 30),
          onPressed: onForward,
        ),
      ],
    );
  }
}

/// Franja que dice si el mes está cerrado, en curso o es futuro.
class _StatusStrip extends StatelessWidget {
  final MonthStatus status;
  final bool unlocked;
  final VoidCallback onReopen;
  final VoidCallback onLock;

  const _StatusStrip({
    required this.status,
    required this.unlocked,
    required this.onReopen,
    required this.onLock,
  });

  @override
  Widget build(BuildContext context) {
    if (status == MonthStatus.open) return const SizedBox.shrink();

    final closed = status == MonthStatus.closed;
    final tone = !closed
        ? AppColors.royal
        : (unlocked ? AppColors.crimson : AppColors.inkSoft);
    final text = !closed
        ? 'Mes próximo: puedes prepararlo desde ya'
        : (unlocked
            ? 'Corrigiendo un mes cerrado'
            : 'Mes cerrado: su sobrante pasó al siguiente');

    return Container(
      margin: const EdgeInsets.fromLTRB(2, 0, 2, 4),
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Icon(
            !closed
                ? Icons.event
                : (unlocked ? Icons.lock_open : Icons.lock_outline),
            size: 18,
            color: tone,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: tone,
                ),
              ),
            ),
          ),
          if (closed)
            TextButton(
              onPressed: unlocked ? onLock : onReopen,
              child: Text(unlocked ? 'Listo' : 'Reabrir'),
            ),
        ],
      ),
    );
  }
}

/// Tarjeta plegable con lo que entra en el mes: el sobrante anterior y los
/// ingresos.
class _IncomesCard extends StatelessWidget {
  final MonthData data;
  final bool locked;
  final bool open;
  final VoidCallback onToggle;
  final VoidCallback onAdd;
  final ValueChanged<Income> onEdit;

  const _IncomesCard({
    required this.data,
    required this.locked,
    required this.open,
    required this.onToggle,
    required this.onAdd,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return OrnateCard(
      padding: EdgeInsets.zero,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topCenter,
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                child: Row(
                  children: [
                    Text('Ingresos', style: displayStyle(size: 17)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: AnimatedMoney(
                          value: data.carryIn + data.totalIncome,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: AppColors.forest,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    AnimatedRotation(
                      turns: open ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: const Icon(Icons.expand_more, color: AppColors.bark),
                    ),
                  ],
                ),
              ),
            ),
            if (open) ...[
              if (data.carryIn != 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.redo,
                        size: 18,
                        color: AppColors.goldDeep,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'Sobrante anterior',
                          style: TextStyle(
                            fontSize: 18,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      Text(
                        formatMoney(data.carryIn),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: data.carryIn < 0 ? AppColors.crimson : null,
                        ),
                      ),
                    ],
                  ),
                ),
              for (final income in data.incomes)
                InkWell(
                  onTap: locked ? null : () => onEdit(income),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                    child: Row(
                      children: [
                        Icon(
                          income.method == PayMethod.cash
                              ? Icons.payments_outlined
                              : Icons.account_balance,
                          size: 18,
                          color: AppColors.goldDeep,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            income.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 18),
                          ),
                        ),
                        if (income.recurring)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.repeat,
                              size: 16,
                              color: AppColors.goldDeep,
                            ),
                          ),
                        Text(
                          formatMoney(income.amount),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (locked)
                const SizedBox(height: 8)
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Agregar ingreso'),
                    onPressed: onAdd,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Hoja inferior de un fondo: anota gastos parciales y muestra lo que queda.
class _SpendsSheet extends StatefulWidget {
  final BudgetItem item;

  const _SpendsSheet({required this.item});

  @override
  State<_SpendsSheet> createState() => _SpendsSheetState();
}

class _SpendsSheetState extends State<_SpendsSheet> {
  final _amount = TextEditingController();
  late List<Spend> _spends = List.of(widget.item.spends);
  String? _error;

  double get _spent => _spends.fold(0, (sum, s) => sum + s.amount);
  double get _remaining => widget.item.amount - _spent;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final value = parseMoney(_amount.text);
    final error = validateMoney(value);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    final id = await AppDatabase.instance.addSpend(widget.item.id!, value!);
    if (!mounted) return;
    setState(() {
      _error = null;
      _amount.clear();
      _spends = [
        ..._spends,
        Spend(
          id: id,
          itemId: widget.item.id!,
          amount: value,
          createdAt: DateTime.now(),
        ),
      ];
    });
  }

  Future<void> _remove(Spend spend) async {
    await AppDatabase.instance.deleteSpend(spend.id!);
    if (!mounted) return;
    setState(() => _spends = _spends.where((s) => s.id != spend.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final over = _remaining < 0;
    return Padding(
      padding: EdgeInsets.only(
        left: 22,
        right: 22,
        top: 18,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.item.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 2),
            Text(
              'Fondo de ${formatMoney(widget.item.amount)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 17, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 8),
            Center(
              child: AnimatedMoney(
                value: _remaining.abs(),
                prefix: over ? 'Excedido por ' : 'Quedan ',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: over ? AppColors.crimson : AppColors.forest,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [MoneyField.formatter],
                    style: const TextStyle(fontSize: 20),
                    decoration: InputDecoration(
                      labelText: 'Gasto',
                      hintText: '0.00',
                      prefixText: '\$ ',
                      errorText: _error,
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                const SizedBox(width: 14),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: MedievalButton(label: 'Anotar', onPressed: _add),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_spends.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Aún no hay gastos anotados',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontStyle: FontStyle.italic,
                    color: AppColors.inkSoft,
                  ),
                ),
              )
            else
              for (final spend in _spends.reversed)
                Row(
                  key: ValueKey(spend.id),
                  children: [
                    Text(
                      DateFormat('dd/MM').format(spend.createdAt),
                      style: const TextStyle(
                        fontSize: 16,
                        color: AppColors.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '-${formatMoney(spend.amount)}',
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        color: AppColors.crimson,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Quitar gasto',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => _remove(spend),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }
}
