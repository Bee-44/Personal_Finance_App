import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_theme.dart';
import '../utils/color_utils.dart';
import 'medieval.dart';

/// Estandarte con el saldo del libro, en el color del libro.
class BalanceBanner extends StatelessWidget {
  final Color color;
  final String title;
  final double total;

  /// Desglose bajo el total, p. ej. `{'Banco': 120, 'Efectivo': 30}`.
  final Map<String, double> breakdown;

  /// Datos secundarios al pie, p. ej. `{'Por pagar': 80, 'Libre': 70}`.
  final Map<String, double> footer;

  const BalanceBanner({
    super.key,
    required this.color,
    required this.title,
    required this.total,
    this.breakdown = const {},
    this.footer = const {},
  });

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 17, color: AppColors.vellum);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.goldLight, AppColors.goldDeep, AppColors.goldLight],
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.ink.withValues(alpha: 0.28),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [color, darken(color, 0.4)],
          ),
        ),
        child: Column(
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: displayStyle(size: 19, color: AppColors.goldLight),
            ),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: AnimatedMoney(
                value: total,
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: AppColors.vellum,
                  height: 1.1,
                ),
              ),
            ),
            if (breakdown.isNotEmpty) ...[
              const SizedBox(height: 8),
              OrnamentDivider(
                width: 200,
                color: AppColors.goldLight.withValues(alpha: 0.7),
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.spaceAround,
                spacing: 18,
                children: [
                  for (final entry in breakdown.entries)
                    AnimatedMoney(
                      value: entry.value,
                      prefix: '${entry.key}: ',
                      style: small,
                    ),
                ],
              ),
            ],
            if (footer.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final entry in footer.entries)
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(
                          vertical: 7,
                          horizontal: 6,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.ink.withValues(alpha: 0.28),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: AppColors.goldLight.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              entry.key,
                              style: const TextStyle(
                                fontSize: 15,
                                color: AppColors.goldLight,
                              ),
                            ),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: AnimatedMoney(
                                value: entry.value,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.vellum,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
