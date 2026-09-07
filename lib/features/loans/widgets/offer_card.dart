import 'package:flutter/material.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../data/models/loan.dart';
import '../../../data/models/match.dart';

/// A matched product as it appears in a list. Leads with the EMI, because
/// that is the number the customer actually lives with, and states how the
/// product lined up rather than implying anyone has approved it.
class OfferCard extends StatelessWidget {
  const OfferCard({
    super.key,
    required this.match,
    this.onTap,
    this.onCompareToggle,
    this.inCompare = false,
  });

  final ProductMatch match;
  final VoidCallback? onTap;
  final VoidCallback? onCompareToggle;
  final bool inCompare;

  LoanOffer get offer => match.offer;

  @override
  Widget build(BuildContext context) {
    final p = offer.product;
    final trustColor = AppColors.forScore(p.fynnTrust);
    final category = match.category;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          border: Border.all(
            color: inCompare
                ? AppColors.mint.withValues(alpha: 0.55)
                : AppColors.border,
            width: inCompare ? 1.4 : 1,
          ),
        ),
        child: Column(
          children: [
            _CategoryBanner(category: category),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 15, 16, 14),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              p.lender,
                              style: const TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _TrustBadge(score: p.fynnTrust, color: trustColor),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        flex: 5,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'MONTHLY EMI',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                                color: AppColors.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              Fmt.money(offer.emi.emi),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.7,
                                height: 1,
                                color: AppColors.textPrimary,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: _Stat(
                          label: 'RATE',
                          value: Fmt.percent(p.interestRate, decimals: 2),
                        ),
                      ),
                      Expanded(
                        flex: 4,
                        child: _Stat(
                          label: 'TENURE',
                          value: Fmt.months(offer.tenureMonths),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '${p.category.label} · '
                    '${Fmt.compactMoney(p.minAmount)}–'
                    '${Fmt.compactMoney(p.maxAmount)} · '
                    '${Fmt.months(p.minTenureMonths)}–'
                    '${Fmt.months(p.maxTenureMonths)}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: AppColors.textTertiary,
                    ),
                  ),
                  if (_headline != null) ...[
                    const SizedBox(height: 13),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          _headlineIcon,
                          size: 14,
                          color: _colorFor(category),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _headline!,
                            style: const TextStyle(
                              fontSize: 12,
                              height: 1.4,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (match.notAssessed.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.remove_circle_outline_rounded,
                          size: 13,
                          color: AppColors.textTertiary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Not checked: ${match.notAssessed.join(', ')}',
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (_consideration != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.priority_high_rounded,
                          size: 13,
                          color: AppColors.warning,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _consideration!,
                            style: const TextStyle(
                              fontSize: 11.5,
                              height: 1.4,
                              color: AppColors.textTertiary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${Fmt.money(offer.processingFee)} fee '
                          '(${p.processingFeePercent}%'
                          '${p.processingFeeCap == null ? ', no cap published' : ', capped'})',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textTertiary,
                          ),
                        ),
                      ),
                      if (onCompareToggle != null)
                        GestureDetector(
                          onTap: onCompareToggle,
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10),
                            child: Row(
                              children: [
                                Icon(
                                  inCompare
                                      ? Icons.check_circle_rounded
                                      : Icons.add_circle_outline_rounded,
                                  size: 16,
                                  color: inCompare
                                      ? AppColors.mint
                                      : AppColors.textTertiary,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  inCompare ? 'Added' : 'Compare',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: inCompare
                                        ? AppColors.mint
                                        : AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One line: what stops this, or what to weigh, or — where everything
  /// lined up — what it would cost against their income, which is the fit
  /// a customer actually feels.
  String? get _headline {
    if (match.blockers.isNotEmpty) return match.blockers.first;
    if (match.check.isNotEmpty) return match.check.first;

    for (final criterion in match.criteria) {
      if (criterion.key == 'affordability' && criterion.isPassed) {
        return criterion.detail;
      }
    }
    return match.fits.isEmpty ? null : match.fits.first;
  }

  /// The first thing the provider says to watch for, if they say anything.
  String? get _consideration => match.product.considerations.isEmpty
      ? null
      : match.product.considerations.first;

  IconData get _headlineIcon {
    if (match.blockers.isNotEmpty) return Icons.block_rounded;
    if (match.check.isNotEmpty) return Icons.info_outline_rounded;
    return Icons.check_circle_outline_rounded;
  }

  static Color _colorFor(MatchCategory category) => switch (category) {
    MatchCategory.strongMatch => AppColors.mint,
    MatchCategory.goodMatch => AppColors.success,
    MatchCategory.review => AppColors.warning,
    MatchCategory.notAMatch => AppColors.textTertiary,
  };
}

/// Says how the product lined up. Never "approved", never a probability.
class _CategoryBanner extends StatelessWidget {
  const _CategoryBanner({required this.category});
  final MatchCategory category;

  @override
  Widget build(BuildContext context) {
    final color = OfferCard._colorFor(category);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: category.isViable ? 0.14 : 0.07),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppTheme.rLg - 1),
        ),
      ),
      child: Text(
        category.label.toUpperCase(),
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.3,
          color: color,
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            height: 1.15,
            color: AppColors.textSecondary,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _TrustBadge extends StatelessWidget {
  const _TrustBadge({required this.score, required this.color});
  final int score;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        children: [
          Text(
            'FYNNTRUST',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.7,
              color: color.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '$score',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              height: 1.1,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
