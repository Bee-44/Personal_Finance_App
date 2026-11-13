import 'package:flutter/material.dart';

import '../models/month.dart';
import '../models/validation.dart';
import '../theme/app_colors.dart';
import '../utils/color_utils.dart';
import 'medieval.dart';

/// Casilla en forma de sello de cera: vacía o estampada.
class SealCheckbox extends StatelessWidget {
  final bool checked;

  /// Null: la casilla solo se muestra, no se puede tocar.
  final VoidCallback? onTap;
  final String tooltip;

  const SealCheckbox({
    super.key,
    required this.checked,
    required this.onTap,
    this.tooltip = 'Marcar como pagado',
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: checked,
      child: Tooltip(
        message: onTap == null
            ? (checked ? 'Pagado' : 'Sin pagar')
            : (checked ? 'Desmarcar' : tooltip),
        child: PressScale(
          scale: 0.8,
          enabled: onTap != null,
          child: InkResponse(
            onTap: onTap,
            radius: 26,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                // Sin rebote aquí: una curva que se pasa de 1 daría valores
                // negativos a la sombra. El rebote lo lleva el ícono.
                curve: Curves.easeOut,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: checked
                      ? const RadialGradient(
                          center: Alignment(-0.3, -0.4),
                          colors: [Color(0xFFB8443A), AppColors.crimson],
                        )
                      : null,
                  color: checked ? null : AppColors.parchment,
                  border: Border.all(
                    color: checked ? AppColors.gold : AppColors.goldDeep,
                    width: checked ? 2 : 1.5,
                  ),
                  boxShadow: checked
                      ? [
                          BoxShadow(
                            color: AppColors.ink.withValues(alpha: 0.3),
                            blurRadius: 5,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: AnimatedScale(
                  scale: checked ? 1 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  child: const Icon(
                    Icons.check,
                    size: 22,
                    color: AppColors.goldLight,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Un renglón de la lista del mes.
///
/// Tocar un pago fijo lo marca o desmarca. Tocar un fondo abre sus gastos.
class BudgetItemTile extends StatelessWidget {
  final BudgetItem item;
  final VoidCallback onToggle;
  final VoidCallback onOpenSpends;
  final VoidCallback onEdit;

  /// Falso en un mes cerrado: el renglón solo se muestra.
  final bool enabled;

  const BudgetItemTile({
    super.key,
    required this.item,
    required this.onToggle,
    required this.onOpenSpends,
    required this.onEdit,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final paid = item.paid;
    final faded = paid ? AppColors.inkSoft.withValues(alpha: 0.75) : null;

    return OrnateCard(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.fromLTRB(6, 6, 2, 6),
      color: paid ? AppColors.parchment : AppColors.vellum,
      onTap: !enabled ? null : (item.envelope ? onOpenSpends : onToggle),
      child: Row(
        children: [
          SealCheckbox(
            checked: paid,
            onTap: enabled ? onToggle : null,
            tooltip: item.envelope ? 'Cerrar fondo' : 'Marcar como pagado',
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 220),
                  style: TextStyle(
                    fontFamily: DefaultTextStyle.of(context).style.fontFamily,
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    color: faded ?? AppColors.ink,
                    decoration: paid ? TextDecoration.lineThrough : null,
                    decorationColor: AppColors.crimson,
                    decorationThickness: 2,
                  ),
                  child: Text(
                    item.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 2),
                if (item.envelope)
                  _EnvelopeStatus(item: item)
                else
                  _Tags(item: item),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            formatMoney(item.amount),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: faded ?? AppColors.bark,
            ),
          ),
          if (enabled)
            IconButton(
              tooltip: 'Editar renglón',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.edit, size: 20),
              onPressed: onEdit,
            )
          else
            const SizedBox(width: 12),
        ],
      ),
    );
  }
}

/// Etiquetas pequeñas: de dónde sale el dinero y si se repite.
class _Tags extends StatelessWidget {
  final BudgetItem item;

  const _Tags({required this.item});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontSize: 15, color: AppColors.inkSoft);
    return Row(
      children: [
        Icon(
          item.method == PayMethod.cash
              ? Icons.payments_outlined
              : Icons.account_balance,
          size: 15,
          color: AppColors.goldDeep,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            PayMethod.label(item.method),
            style: style,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (item.recurring) ...[
          const SizedBox(width: 10),
          const Icon(Icons.repeat, size: 15, color: AppColors.goldDeep),
          const SizedBox(width: 3),
          const Flexible(
            child: Text('Mensual', style: style, overflow: TextOverflow.ellipsis),
          ),
        ],
      ],
    );
  }
}

/// Lo que queda de un fondo, con su barra de avance.
class _EnvelopeStatus extends StatelessWidget {
  final BudgetItem item;

  const _EnvelopeStatus({required this.item});

  @override
  Widget build(BuildContext context) {
    final over = item.remaining < 0;
    final used = item.amount <= 0
        ? (item.spent > 0 ? 1.0 : 0.0)
        : (item.spent / item.amount).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          over
              ? 'Excedido por ${formatMoney(-item.remaining)}'
              : 'Quedan ${formatMoney(item.remaining)}',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: over ? AppColors.crimson : AppColors.forest,
          ),
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: used),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 6,
              backgroundColor: AppColors.parchmentDeep,
              color: over ? AppColors.crimson : AppColors.gold,
            ),
          ),
        ),
      ],
    );
  }
}
