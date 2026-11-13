import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/book.dart';
import '../models/movement.dart';
import '../models/validation.dart';
import '../services/app_database.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';
import '../widgets/balance_banner.dart';
import '../widgets/form_widgets.dart';
import '../widgets/medieval.dart';
import 'entry_forms.dart';
import 'import_screen.dart';

/// Libro de tipo cuenta: abonos y retiros con saldo corrido.
class LedgerScreen extends StatefulWidget {
  final Book book;

  const LedgerScreen({super.key, required this.book});

  @override
  State<LedgerScreen> createState() => _LedgerScreenState();
}

class _LedgerScreenState extends State<LedgerScreen> {
  List<Movement>? _movements;

  int get _bookId => widget.book.id!;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final movements = await AppDatabase.instance.getMovements(_bookId);
    if (mounted) setState(() => _movements = movements);
  }

  Future<void> _openForm([Movement? movement]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MovementFormScreen(bookId: _bookId, movement: movement),
      ),
    );
    if (saved == true && mounted) {
      await _load();
      if (mounted && movement == null) showNotice(context, 'Movimiento agregado');
    }
  }

  Future<void> _import() async {
    final added = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => ImportScreen.movements(bookId: _bookId)),
    );
    if (added != null && added > 0 && mounted) {
      await _load();
      if (mounted) {
        showNotice(
          context,
          added == 1
              ? 'Se agregó 1 movimiento'
              : 'Se agregaron $added movimientos',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.book.color;
    final movements = _movements;

    double sum(String method) => (movements ?? const <Movement>[])
        .where((m) => m.method == method)
        .fold(0.0, (total, m) => total + m.amount);
    final bank = sum(PayMethod.bank);
    final cash = sum(PayMethod.cash);

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
            tooltip: 'Pegar lista',
            icon: const Icon(Icons.content_paste_go, color: AppColors.goldLight),
            onPressed: _import,
          ),
        ],
      ),
      body: ParchmentBackground(
        child: movements == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 120),
                children: [
                  BalanceBanner(
                    color: color,
                    title: 'Saldo',
                    total: bank + cash,
                    breakdown: {'Banco': bank, 'Efectivo': cash},
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      const SizedBox(width: 6),
                      Text('Movimientos', style: displayStyle(size: 17)),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: OrnamentDivider(width: double.infinity),
                      ),
                      const SizedBox(width: 6),
                    ],
                  ),
                  const SizedBox(height: 6),
                  if (movements.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36, horizontal: 12),
                      child: Text(
                        'Aún no hay movimientos en esta cuenta',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 19,
                          fontStyle: FontStyle.italic,
                          color: AppColors.inkSoft,
                        ),
                      ),
                    )
                  else
                    for (final (index, movement) in movements.indexed)
                      FadeSlideIn(
                        key: ValueKey(movement.id),
                        index: index,
                        child: _MovementTile(
                          movement: movement,
                          onTap: () => _openForm(movement),
                        ),
                      ),
                ],
              ),
      ),
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: CoinButton(
          icon: Icons.add,
          tooltip: 'Nuevo movimiento',
          onPressed: () => _openForm(),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

/// Renglón de un abono o retiro. Tocarlo lo abre para editar.
class _MovementTile extends StatelessWidget {
  final Movement movement;
  final VoidCallback onTap;

  const _MovementTile({required this.movement, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final income = movement.isIncome;
    final tone = income ? AppColors.forest : AppColors.crimson;
    return OrnateCard(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: tone.withValues(alpha: 0.14),
              border: Border.all(color: tone, width: 1.5),
            ),
            child: Icon(income ? Icons.add : Icons.remove, size: 20, color: tone),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('dd/MM/yyyy').format(movement.date)} · '
                  '${PayMethod.label(movement.method)}',
                  style: const TextStyle(fontSize: 15, color: AppColors.inkSoft),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${income ? '+' : '-'}${formatMoney(movement.amount.abs())}',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}
