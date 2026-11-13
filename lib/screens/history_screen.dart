import 'package:flutter/material.dart';

import '../models/book.dart';
import '../models/month.dart';
import '../services/app_database.dart';
import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';
import '../widgets/medieval.dart';

/// Historial de un libro mensual: el resumen de cada mes, del más nuevo al
/// más antiguo. Tocar un mes lo abre; regresa su [Period] a la pantalla
/// anterior.
class HistoryScreen extends StatefulWidget {
  final Book book;

  /// Fecha que se toma como "hoy". Solo se cambia en pruebas.
  final DateTime? today;

  const HistoryScreen({super.key, required this.book, this.today});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<MonthData>? _months;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final months = await AppDatabase.instance.getHistory(widget.book.id!);
    if (mounted) setState(() => _months = months);
  }

  @override
  Widget build(BuildContext context) {
    final months = _months;
    final today = widget.today ?? DateTime.now();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: darken(widget.book.color, 0.35),
        title: const Text('Historial'),
      ),
      body: ParchmentBackground(
        child: months == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 32),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    child: Text(
                      months.length == 1
                          ? '${widget.book.name} · 1 mes'
                          : '${widget.book.name} · ${months.length} meses',
                      style: const TextStyle(
                        fontSize: 19,
                        fontStyle: FontStyle.italic,
                        color: AppColors.inkSoft,
                      ),
                    ),
                  ),
                  for (final (index, month) in months.indexed)
                    FadeSlideIn(
                      key: ValueKey(month.period.id),
                      index: index,
                      child: _MonthCard(
                        data: month,
                        status: month.statusAt(today),
                        onTap: () => Navigator.pop(context, month.period),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Resumen de un mes.
class _MonthCard extends StatelessWidget {
  final MonthData data;
  final MonthStatus status;
  final VoidCallback onTap;

  const _MonthCard({
    required this.data,
    required this.status,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final (label, tone, icon) = switch (status) {
      MonthStatus.closed => ('Cerrado', AppColors.inkSoft, Icons.lock_outline),
      MonthStatus.open => ('En curso', AppColors.forest, Icons.hourglass_bottom),
      MonthStatus.upcoming => ('Próximo', AppColors.royal, Icons.event),
    };
    // Parte de lo que entró (sobrante + ingresos) que ya se gastó.
    final entered = data.carryIn + data.totalIncome;
    final used = entered <= 0
        ? (data.deducted > 0 ? 1.0 : 0.0)
        : (data.deducted / entered).clamp(0.0, 1.0);
    final negative = data.available < 0;

    return OrnateCard(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(data.period.label, style: displayStyle(size: 18)),
              ),
              Icon(icon, size: 17, color: tone),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: tone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (data.carryIn != 0)
            _Line('Sobrante anterior', data.carryIn, signed: true),
          _Line('Ingresos', data.totalIncome),
          _Line('Gastado', -data.deducted, signed: true),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: used,
              minHeight: 6,
              backgroundColor: AppColors.parchmentDeep,
              color: negative ? AppColors.crimson : AppColors.gold,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  status == MonthStatus.closed ? 'Sobrante' : 'Disponible',
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                formatMoney(data.available),
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.w700,
                  color: negative ? AppColors.crimson : AppColors.forest,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            data.items.isEmpty
                ? 'Sin renglones'
                : '${data.paidCount} de ${data.items.length} pagados'
                    '${data.pending > 0 ? ' · ${formatMoney(data.pending)} sin pagar' : ''}',
            style: const TextStyle(fontSize: 16, color: AppColors.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _Line extends StatelessWidget {
  final String label;
  final double value;
  final bool signed;

  const _Line(this.label, this.value, {this.signed = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 17, color: AppColors.inkSoft),
            ),
          ),
          Text(
            '${signed && value > 0 ? '+' : ''}${formatMoney(value)}',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
