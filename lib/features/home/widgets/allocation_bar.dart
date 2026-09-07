import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/home_snapshot.dart';

/// Where every rupee of income goes, as one stacked bar. Reads faster than
/// four separate figures and makes the surplus the visible headline.
class AllocationBar extends StatelessWidget {
  const AllocationBar({super.key, required this.financials});

  final HomeFinancials financials;

  @override
  Widget build(BuildContext context) {
    final income = financials.monthlyIncome;
    final surplus = financials.surplus;

    // A negative surplus is kept negative. The bar cannot draw a segment for
    // it — there is no room left in the income to draw it in — so it is named
    // for what it is instead of being clamped to a comforting zero.
    final shortfall = surplus < 0;
    final segments = <(String, double, Color)>[
      ('Expenses', financials.monthlyExpenses, AppColors.blue),
      ('Existing EMI', financials.existingEmi, AppColors.warning),
      if (financials.otherObligations > 0)
        ('Other', financials.otherObligations, AppColors.violet),
      if (!shortfall) ('Surplus', surplus, AppColors.mint),
    ];
    final surplusColor = shortfall ? AppColors.danger : AppColors.mint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'MONTHLY INCOME',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    Fmt.money(income),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.9,
                      height: 1,
                      color: AppColors.textPrimary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  shortfall ? 'SHORTFALL' : 'SURPLUS',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: surplusColor.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  Fmt.money(surplus),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                    height: 1.2,
                    color: surplusColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 900),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            final total = income <= 0 ? 1.0 : income;
            return ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: SizedBox(
                height: 9,
                child: Row(
                  children: [
                    for (final (_, value, color) in segments)
                      if (value > 0)
                        Expanded(
                          flex: ((value / total) * 1000 * t).round() + 1,
                          child: Container(
                            margin: const EdgeInsets.only(right: 2),
                            color: color,
                          ),
                        ),
                    if (t < 1)
                      Expanded(
                        flex: ((1 - t) * 1000).round() + 1,
                        child: const ColoredBox(color: AppColors.surfaceHigh),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 16,
          runSpacing: 8,
          children: [
            for (final (label, value, color) in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    Fmt.compactMoney(value),
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textSecondary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
