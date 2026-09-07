import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/score_dial.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../core/utils/formatters.dart';
import '../../data/models/loan.dart';
import '../../data/models/score.dart';
import 'loan_controller.dart';

/// Screen 14 — what FynnTrust is made of, factor by factor.
class FynnTrustScreen extends ConsumerWidget {
  const FynnTrustScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(matchProvider(productId));

    return async.when(
      loading: () => const FynnScaffold(
        title: 'FynnTrust',
        child: LoadingList(items: 3, itemHeight: 110),
      ),
      error: (e, _) => FynnScaffold(
        title: 'FynnTrust',
        child: ErrorState(message: messageForLoad(e)),
      ),
      data: (match) {
        final p = match.product;
        final color = AppColors.forScore(p.fynnTrust);
        final factors = p.trustBreakdown.all;

        return FynnScaffold(
          title: 'FynnTrust',
          subtitle: '${p.lender} · ${p.name}',
          padHorizontal: false,
          glowPrimary: color,
          // Understanding the product is the middle of a decision, not the
          // end of one. The next question is what it would do to their
          // month, and it carries this loan's own amount and term.
          bottomBar: PrimaryButton(
            label: 'See what it would do',
            icon: Icons.insights_rounded,
            onPressed: () => context.push(
              Routes.twinForLoan(
                productId: p.id,
                amount: match.pricing.amount,
                tenureMonths: match.pricing.tenureMonths,
              ),
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 28),
            children: staggered([
              Center(
                child: Column(
                  children: [
                    ScoreDial(
                      score: p.fynnTrust,
                      size: 186,
                      label: _band(p.fynnTrust),
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: 300,
                      child: Text(
                        _verdict(p.fynnTrust),
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 14.5,
                          height: 1.55,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),
              const SectionHeader(
                title: 'Breakdown',
                subtitle: 'The five factors published with this product',
              ),
              FynnCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    for (final f in factors)
                      FactorBar(
                        label: f.label,
                        value: f.value,
                        trailing: '${f.value}',
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              const SectionHeader(title: 'What each factor means'),
              for (final f in factors) _FactorExplainer(factor: f),
              const SizedBox(height: 8),

              const SectionHeader(
                title: 'What we know about this product',
                subtitle: 'And what nobody has told us',
              ),
              _KnownAndUnknown(product: p),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: AppColors.surface.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(AppTheme.rMd),
                  border: Border.all(color: AppColors.borderSoft),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline_rounded,
                      size: 15,
                      color: AppColors.textTertiary,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'FynnTrust is FynnEdge\'s own read on the offer, not '
                        'the lender, and it is independent of any commercial '
                        'arrangement. The overall value and the five factors '
                        'are both published with the product — FynnEdge does '
                        'not derive one from the other. It is not a promise '
                        'from the provider and says nothing about whether '
                        'they would approve you.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.55,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ], step: const Duration(milliseconds: 55)),
          ),
        );
      },
    );
  }

  static String _band(int score) {
    if (score >= 85) return 'EXCELLENT';
    if (score >= 70) return 'STRONG';
    if (score >= 55) return 'FAIR';
    return 'WEAK';
  }

  static String _verdict(int score) {
    if (score >= 85) {
      return 'One of the strongest offers we can show you. The pricing, fees '
          'and flexibility all hold up under scrutiny.';
    }
    if (score >= 70) {
      return 'A solid offer with no serious traps. Read the considerations '
          'before you commit.';
    }
    if (score >= 55) {
      return 'Workable, but you are paying for it somewhere. Compare this '
          'against a higher-scoring option before deciding.';
    }
    return 'This offer costs more than it should on several fronts. Only take '
        'it if nothing better is available to you.';
  }
}

class _FactorExplainer extends StatelessWidget {
  const _FactorExplainer({required this.factor});
  final ScoreFactor factor;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forScore(factor.value);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: color.withValues(alpha: 0.10),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Text(
              '${factor.value}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  factor.label,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  factor.explanation,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The product facts FynnEdge holds, beside the ones it does not.
///
/// A trust score built on partial information should say which parts are
/// missing. Everything listed as unavailable is genuinely absent from the
/// catalogue — no default has been substituted for it.
class _KnownAndUnknown extends StatelessWidget {
  const _KnownAndUnknown({required this.product});
  final LoanProduct product;

  @override
  Widget build(BuildContext context) {
    final known = <String>[
      'Interest rate: ${Fmt.percent(product.interestRate)}',
      'Amount: ${Fmt.compactMoney(product.minAmount)} – '
          '${Fmt.compactMoney(product.maxAmount)}',
      'Tenure: ${Fmt.months(product.minTenureMonths)} – '
          '${Fmt.months(product.maxTenureMonths)}',
      product.processingFeeCap == null
          ? 'Processing fee: ${product.processingFeePercent}%, no cap published'
          : 'Processing fee: ${product.processingFeePercent}%, capped at '
                '${Fmt.money(product.processingFeeCap!)}',
      if (product.prepaymentCharge.isNotEmpty)
        'Prepayment: ${product.prepaymentCharge}',
      if (product.minMonthlyIncome != null)
        'Minimum income: ${Fmt.money(product.minMonthlyIncome!)}',
      if (product.minAge != null || product.maxAgeAtMaturity != null)
        'Age: ${product.minAge ?? '—'} to '
            '${product.maxAgeAtMaturity ?? '—'} at maturity',
    ];

    final unknown = <String>[
      if (product.prepaymentCharge.isEmpty) 'Prepayment charge',
      if (product.processingFeeCap == null) 'Any cap on the processing fee',
      if (product.minMonthlyIncome == null) 'Minimum income requirement',
      if (product.maxAgeAtMaturity == null && product.minAge == null)
        'Age requirement',
      'Whether the rate shown is the one you would be offered',
      'Documents and checks the provider runs before deciding',
    ];

    return FynnCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _KnownHeading(
            icon: Icons.fact_check_outlined,
            color: AppColors.success,
            text: 'Published with this product',
          ),
          const SizedBox(height: 10),
          for (final line in known) _Bullet(text: line),
          const SizedBox(height: 16),
          const _KnownHeading(
            icon: Icons.help_outline_rounded,
            color: AppColors.textTertiary,
            text: 'Not published, so not scored',
          ),
          const SizedBox(height: 10),
          for (final line in unknown)
            _Bullet(text: line, color: AppColors.textTertiary),
        ],
      ),
    );
  }
}

class _KnownHeading extends StatelessWidget {
  const _KnownHeading({
    required this.icon,
    required this.color,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 8),
      Text(
        text,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
          color: color,
        ),
      ),
    ],
  );
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text, this.color});
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 7, left: 22),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Icon(
            Icons.circle,
            size: 4,
            color: color ?? AppColors.textTertiary,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: color ?? AppColors.textSecondary,
            ),
          ),
        ),
      ],
    ),
  );
}
