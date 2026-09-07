import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../data/match/fynn_match_engine.dart';
import '../../data/models/loan.dart';
import '../../data/models/match.dart';
import 'loan_controller.dart';
import '../../app/routes.dart';

/// Screen 13 — side by side, with the better value on each row marked.
class CompareScreen extends ConsumerWidget {
  const CompareScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(comparisonProvider);

    return FynnScaffold(
      title: 'Compare',
      subtitle: 'Marked where a figure is cheaper on that row',
      padHorizontal: false,
      actions: [
        TextButton(
          onPressed: () {
            ref.read(compareProvider.notifier).clear();
            context.pop();
          },
          style: TextButton.styleFrom(
            foregroundColor: AppColors.textTertiary,
            textStyle: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          child: const Text('Clear'),
        ),
      ],
      child: async.when(
        loading: () => const LoadingList(items: 2, itemHeight: 200),
        error: (e, _) => ErrorState(message: messageForLoad(e)),
        data: (matches) {
          if (matches.length < 2) {
            return EmptyState(
              icon: Icons.compare_arrows_rounded,
              title: 'Pick at least two',
              message:
                  'Add two or three offers from your options list and '
                  'we will lay the numbers out side by side.',
              actionLabel: 'Browse offers',
              onAction: () => context.push(Routes.loanOptions),
            );
          }
          return _Table(matches: matches);
        },
      ),
    );
  }
}

/// One scrollable grid: a fixed label column, then one column per offer.
class _Table extends StatelessWidget {
  const _Table({required this.matches});
  final List<ProductMatch> matches;

  List<LoanOffer> get offers => [for (final m in matches) m.offer];

  /// True once every column can show a projected EMI share, so the row can
  /// be ordered without comparing a real number against a missing one.
  bool get _canCompareEmiShare =>
      matches.every((m) => m.pricing.projectedEmiRatio != null);

  /// Every row is a fact from the catalogue or from the Financial Engine.
  ///
  /// Rows that can be ordered are marked where they are lower — or higher,
  /// where higher is the cheaper end. Nothing here picks an overall winner:
  /// no product rule in the catalogue supports that conclusion, and the
  /// trade-offs are the customer's to weigh.
  List<_Row> get _rows => [
    _Row(
      'Category',
      (m) => m.product.category.label,
      (m) => 0,
      lowerIsBetter: false,
      compare: false,
    ),
    _Row(
      'FynnMatch',
      (m) => m.category.label,
      (m) => 0,
      lowerIsBetter: false,
      compare: false,
    ),
    _Row(
      'Amount range',
      (m) =>
          '${Fmt.compactMoney(m.product.minAmount)} – '
          '${Fmt.compactMoney(m.product.maxAmount)}',
      (m) => 0,
      lowerIsBetter: false,
      compare: false,
    ),
    _Row(
      'Interest rate',
      (m) => Fmt.percent(m.product.interestRate),
      (m) => m.product.interestRate,
      lowerIsBetter: true,
    ),
    _Row(
      'Monthly EMI',
      (m) => Fmt.money(m.pricing.emi),
      (m) => m.pricing.emi,
      lowerIsBetter: true,
      emphasise: true,
    ),
    _Row(
      'Processing fee',
      (m) => Fmt.money(m.pricing.processingFee),
      (m) => m.pricing.processingFee,
      lowerIsBetter: true,
    ),
    _Row(
      'Fee cap',
      (m) => m.product.processingFeeCap == null
          ? 'None published'
          : Fmt.money(m.product.processingFeeCap!),
      (m) => 0,
      lowerIsBetter: false,
      compare: false,
    ),
    _Row(
      'Total interest',
      (m) => Fmt.money(m.pricing.totalInterest),
      (m) => m.pricing.totalInterest,
      lowerIsBetter: true,
    ),
    _Row(
      'Total repayment',
      (m) => Fmt.money(m.pricing.totalPayable + m.pricing.processingFee),
      (m) => m.pricing.totalPayable + m.pricing.processingFee,
      lowerIsBetter: true,
      emphasise: true,
    ),
    _Row(
      'Tenure',
      (m) => Fmt.months(m.pricing.tenureMonths),
      (m) => 0,
      lowerIsBetter: false,
      compare: false,
    ),
    _Row(
      'Tenure range',
      (m) =>
          '${Fmt.months(m.product.minTenureMonths)} – '
          '${Fmt.months(m.product.maxTenureMonths)}',
      (m) => 0,
      lowerIsBetter: false,
      compare: false,
    ),
    _Row(
      'Prepayment',
      (m) => m.product.prepaymentCharge.isEmpty
          ? 'Not published'
          : m.product.prepaymentCharge,
      (m) => 0,
      lowerIsBetter: false,
      compare: false,
    ),
    _Row(
      'EMI share after',
      (m) => m.pricing.projectedEmiRatio == null
          ? 'Not available'
          : Fmt.ratio(m.pricing.projectedEmiRatio!),
      (m) => m.pricing.projectedEmiRatio ?? 0,
      lowerIsBetter: true,
      // Only orderable once every column actually has the figure.
      compare: false,
    ),
    _Row(
      'FynnTrust',
      (m) => '${m.product.fynnTrust}',
      (m) => m.product.fynnTrust.toDouble(),
      lowerIsBetter: false,
      emphasise: true,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    // Two offers fit the phone without scrolling; three need the swipe.
    const labelWidth = 100.0;
    final columnWidth = matches.length == 2 ? 138.0 : 130.0;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Only the grid scrolls sideways. The prose below it stays
            // inside the phone's width, where it can be read.
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const SizedBox(width: labelWidth),
                      for (final match in matches)
                        SizedBox(
                          width: columnWidth,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8, bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // How each product lined up, so the cheapest
                                // column is never mistaken for the fitting one.
                                Text(
                                  match.category.label.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.9,
                                    color: switch (match.category) {
                                      MatchCategory.strongMatch =>
                                        AppColors.mint,
                                      MatchCategory.goodMatch =>
                                        AppColors.success,
                                      MatchCategory.review => AppColors.warning,
                                      MatchCategory.notAMatch =>
                                        AppColors.textTertiary,
                                    },
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  match.product.lender,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    height: 1.25,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  match.product.name,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    height: 1.3,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(AppTheme.rMd),
                      border: Border.all(color: AppColors.borderSoft),
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < _rows.length; i++)
                          _buildRow(
                            _rows[i],
                            labelWidth,
                            columnWidth,
                            last: i == _rows.length - 1,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            _TradeOffs(matches: matches),
            const SizedBox(height: 18),
            _Considerations(matches: matches),
            const SizedBox(height: 20),
            Text(
              FynnMatchEngine.disclaimer,
              style: const TextStyle(
                fontSize: 11,
                height: 1.5,
                color: AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(
    _Row row,
    double labelWidth,
    double columnWidth, {
    required bool last,
  }) {
    // Which column holds the lower (or, where noted, the higher) figure on
    // this row. A row-level fact, not a recommendation.
    int? marked;
    final comparable =
        row.compare || (row.label == 'EMI share after' && _canCompareEmiShare);

    if (comparable) {
      final values = matches.map(row.numeric).toList();
      final best = row.lowerIsBetter
          ? values.reduce((a, b) => a < b ? a : b)
          : values.reduce((a, b) => a > b ? a : b);
      // Only mark when the columns actually differ.
      if (values.toSet().length > 1) marked = values.indexOf(best);
    }

    return Container(
      decoration: BoxDecoration(
        border: last
            ? null
            : const Border(bottom: BorderSide(color: AppColors.borderSoft)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
      child: Row(
        children: [
          SizedBox(
            width: labelWidth - 12,
            child: Text(
              row.label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          for (var i = 0; i < matches.length; i++)
            SizedBox(
              width: columnWidth,
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        row.display(matches[i]),
                        style: TextStyle(
                          fontSize: row.emphasise ? 14.5 : 13,
                          fontWeight: row.emphasise
                              ? FontWeight.w800
                              : FontWeight.w600,
                          height: 1.3,
                          color: marked == i
                              ? AppColors.mint
                              : AppColors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    if (marked == i) ...[
                      const SizedBox(width: 5),
                      const Icon(
                        Icons.check_circle_rounded,
                        size: 13,
                        color: AppColors.mint,
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Row {
  const _Row(
    this.label,
    this.display,
    this.numeric, {
    required this.lowerIsBetter,
    this.emphasise = false,
    this.compare = true,
  });

  final String label;
  final String Function(ProductMatch) display;
  final double Function(ProductMatch) numeric;
  final bool lowerIsBetter;
  final bool emphasise;
  final bool compare;
}

/// The differences, stated as differences.
///
/// FynnEdge does not pick between these products: nothing in the catalogue
/// establishes which trade-off matters more to this customer. What it can do
/// is say plainly which column is cheaper on what.
class _TradeOffs extends StatelessWidget {
  const _TradeOffs({required this.matches});
  final List<ProductMatch> matches;

  @override
  Widget build(BuildContext context) {
    final lines = <String>[
      ..._lowest('the lower interest rate', (m) => m.product.interestRate),
      ..._lowest('the lower monthly EMI', (m) => m.pricing.emi),
      ..._lowest('the lower processing fee', (m) => m.pricing.processingFee),
      ..._lowest(
        'the lower total repayment',
        (m) => m.pricing.totalPayable + m.pricing.processingFee,
      ),
      ..._highest(
        'the higher FynnTrust',
        (m) => m.product.fynnTrust.toDouble(),
      ),
      ..._highest(
        'the wider amount range',
        (m) => m.product.maxAmount - m.product.minAmount,
      ),
      ..._highest(
        'the longer maximum term',
        (m) => m.product.maxTenureMonths.toDouble(),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        border: Border.all(color: AppColors.borderSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The trade-offs',
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w800,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Which one is right depends on what you are optimising for. '
            'FynnEdge does not choose for you.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          if (lines.isEmpty)
            const Text(
              'These products are identical on every figure we can compare.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle, size: 4, color: AppColors.mint),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      line,
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.5,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<String> _lowest(String what, double Function(ProductMatch) of) =>
      _extreme(what, of, lower: true);

  List<String> _highest(String what, double Function(ProductMatch) of) =>
      _extreme(what, of, lower: false);

  /// One line naming the product at the cheaper end — and nothing at all when
  /// the columns tie, because "they are the same" is not a trade-off.
  List<String> _extreme(
    String what,
    double Function(ProductMatch) of, {
    required bool lower,
  }) {
    final values = matches.map(of).toList();
    if (values.toSet().length < 2) return const [];

    final target = lower
        ? values.reduce((a, b) => a < b ? a : b)
        : values.reduce((a, b) => a > b ? a : b);

    return ['${matches[values.indexOf(target)].product.lender} has $what.'];
  }
}

/// What each provider says to watch for, kept in their words.
class _Considerations extends StatelessWidget {
  const _Considerations({required this.matches});
  final List<ProductMatch> matches;

  @override
  Widget build(BuildContext context) {
    final withPoints = matches
        .where((m) => m.product.considerations.isNotEmpty)
        .toList();
    if (withPoints.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Things to consider',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        for (final match in withPoints) ...[
          Text(
            match.product.lender,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          for (final point in match.product.considerations)
            Padding(
              padding: const EdgeInsets.only(bottom: 6, left: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.circle,
                      size: 4,
                      color: AppColors.warning,
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      point,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.5,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}
