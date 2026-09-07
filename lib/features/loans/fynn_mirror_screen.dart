import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/sample_data_notice.dart';
import '../../data/engine/financial_engine.dart';
import '../../data/models/loan.dart';
import '../../data/models/match.dart';
import '../../data/models/user.dart';
import '../../data/services/finance_service.dart';
import '../profile/profile_controller.dart';
import 'loan_controller.dart';
import '../../app/routes.dart';

/// Screen 15 — the two futures, shown honestly. The point of this screen is
/// that "don't borrow" is a real option, presented with equal weight.
class FynnMirrorScreen extends ConsumerWidget {
  const FynnMirrorScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The simulated match, so the figures follow whatever Loan Detail is
    // currently modelling rather than describing a different loan.
    final offerAsync = ref.watch(simulatedMatchProvider(productId));
    final financialsAsync = ref.watch(financialProfileProvider);

    return FynnScaffold(
      title: 'FynnMirror',
      padHorizontal: false,
      glowPrimary: AppColors.warning,
      glowSecondary: AppColors.mint,
      child: offerAsync.when(
        loading: () => const LoadingList(items: 2, itemHeight: 220),
        error: (e, _) => ErrorState(message: messageForLoad(e)),
        data: (match) => financialsAsync.when(
          loading: () => const LoadingList(items: 2, itemHeight: 220),
          error: (e, _) => ErrorState(message: messageForLoad(e)),
          data: (financials) => _Mirror(match: match, financials: financials),
        ),
      ),
    );
  }
}

class _Mirror extends ConsumerWidget {
  const _Mirror({required this.match, required this.financials});

  final ProductMatch match;
  final FinancialProfile financials;

  LoanOffer get offer => match.offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final finance = ref.watch(financeServiceProvider);

    // Every before/after figure comes from the one projection the Financial
    // Engine produced for this loan. This screen derives none of its own.
    final projection = match.projection;
    final newEmi = projection.emi.rupees;

    final fund = finance.emergencyFund(
      monthlyExpenses: financials.monthlyExpenses,
      existingEmi: financials.existingEmi,
      savings: financials.savings,
      monthlySurplus: projection.currentSurplus.rupees,
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
      children: staggered([
        Text(
          'Before you borrow…',
          style: t.displaySmall?.copyWith(height: 1.2),
        ),
        const SizedBox(height: 8),
        Text(
          'The same month, two ways. Both are legitimate choices.',
          style: t.bodyMedium,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            const EstimateBadge(),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Worked out from the figures on your profile. Not an offer, '
                'and not a lender decision.',
                style: t.bodySmall?.copyWith(fontSize: 11.5, height: 1.45),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),

        _Path(
          tone: AppColors.warning,
          eyebrow: 'PATH A',
          title: 'If you take this loan',
          subtitle:
              '${offer.product.lender} · '
              '${Fmt.compactMoney(offer.amount)}',
          rows: [
            ('Monthly EMI added', Fmt.money(newEmi)),
            ('Total interest', Fmt.money(offer.emi.totalInterest)),
            (
              'Total repayment',
              Fmt.money(offer.emi.totalPayable + offer.processingFee),
            ),
            ('Committed for', Fmt.months(offer.tenureMonths)),
          ],
          footer: _CashFlow(
            label: 'Monthly cash-flow impact',
            projection: projection,
          ),
        ),

        const _OrDivider(),

        _Path(
          tone: AppColors.mint,
          eyebrow: 'PATH B',
          title: "If you don't",
          subtitle: 'Where you stand today',
          rows: [
            (
              'Monthly surplus kept',
              Fmt.money(projection.currentSurplus.rupees),
            ),
            (
              'EMI share of income',
              Fmt.ratio(projection.currentEmiRatio.value),
            ),
            ('Emergency cover', Fmt.monthsCovered(fund.monthsCovered)),
            ('Interest paid', '₹0'),
          ],
          footer: _Alternative(
            fund: fund,
            surplus: projection.currentSurplus.rupees,
          ),
        ),

        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rLg),
            gradient: AppColors.surfaceGradient,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              const Icon(
                Icons.balance_rounded,
                size: 24,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 14),
              Text(
                'Make the decision that fits your financial situation.',
                textAlign: TextAlign.center,
                style: t.titleLarge?.copyWith(height: 1.45),
              ),
              const SizedBox(height: 10),
              const Text(
                'FynnEdge does not earn more when you borrow more.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        // Having weighed both paths, taking one is the next step. The
        // Three ways on, none of them dominant.
        //
        // This screen's whole argument is that both paths are legitimate, so
        // it does not then make one of them the bright full-width button.
        // Applying stays available — it was the customer's idea, and hiding
        // it would be its own kind of steering — but Loan Detail is where
        // Apply is the primary action. Here it sits level with thinking
        // about it further and with walking away.
        //
        // The loan travels with the FynnTwin link so the simulation opens on
        // this loan rather than on defaults.
        SecondaryButton(
          label: 'Apply for this loan',
          icon: Icons.arrow_forward_rounded,
          onPressed: () => context.push(Routes.applyFor(match.product.id)),
        ),
        const SizedBox(height: 11),
        SecondaryButton(
          label: 'Simulate this in FynnTwin',
          icon: Icons.insights_rounded,
          onPressed: () => context.push(
            Routes.twinForLoan(
              productId: match.product.id,
              amount: match.pricing.amount,
              tenureMonths: match.pricing.tenureMonths,
            ),
          ),
        ),
        const SizedBox(height: 11),
        SecondaryButton(
          label: 'Talk it through with FynnAI',
          icon: Icons.auto_awesome_rounded,
          // Pushed, not switched to: this is a detour inside the decision,
          // and the customer must come back to where they were.
          onPressed: () => context.push(Routes.ai),
        ),
        const SizedBox(height: 16),
        // The decision this product exists to make possible, said plainly.
        // A customer who reads both panels and walks away has used FynnEdge
        // exactly as intended, and should not be left on a screen whose only
        // exits lead further in.
        _NotNow(),
      ], step: const Duration(milliseconds: 70)),
    );
  }
}

/// Deciding against the loan is a finished journey, not an abandoned one.
class _NotNow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const Text(
          'Deciding against this is a real answer. Nothing has been sent, '
          'and nothing changes if you leave it.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12.5,
            height: 1.55,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => context.push(Routes.goals),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.mint,
            textStyle: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          child: const Text('Put the money towards a goal instead'),
        ),
      ],
    );
  }
}

class _Path extends StatelessWidget {
  const _Path({
    required this.tone,
    required this.eyebrow,
    required this.title,
    required this.subtitle,
    required this.rows,
    required this.footer,
  });

  final Color tone;
  final String eyebrow;
  final String title;
  final String subtitle;
  final List<(String, String)> rows;
  final Widget footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppTheme.rLg),
        color: tone.withValues(alpha: 0.05),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  eyebrow,
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.4,
                    color: tone,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Column(
              children: [
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            label,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                        Text(
                          value,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.07),
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AppTheme.rLg - 1),
              ),
              border: Border(
                top: BorderSide(color: tone.withValues(alpha: 0.18)),
              ),
            ),
            child: footer,
          ),
        ],
      ),
    );
  }
}

class _CashFlow extends StatelessWidget {
  const _CashFlow({required this.label, required this.projection});

  final String label;
  final LoanProjection projection;

  @override
  Widget build(BuildContext context) {
    if (!projection.isMeasurable) {
      return const Text(
        'Add your monthly income on your financial profile and we can show '
        'what this would do to your month.',
        style: TextStyle(
          fontSize: 12.5,
          height: 1.5,
          color: AppColors.textSecondary,
        ),
      );
    }

    final tight = projection.exhaustsSurplus;
    final ceiling = Fmt.ratio(projection.ceilingPercent);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label.toUpperCase(),
          style: const TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 11),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            _Figure(
              label: 'Surplus now',
              value: Fmt.money(projection.currentSurplus.rupees),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(
                Icons.arrow_forward_rounded,
                size: 16,
                color: AppColors.textTertiary,
              ),
            ),
            _Figure(
              label: 'Surplus after',
              value: Fmt.money(projection.projectedSurplus.rupees),
              color: tight ? AppColors.danger : AppColors.warning,
            ),
          ],
        ),
        const SizedBox(height: 13),
        Text(
          // FynnEdge's own affordability reference. No claim is made about
          // what any lender does with this number.
          'EMIs would move from '
          '${Fmt.ratio(projection.currentEmiRatio.value)} to '
          '${Fmt.ratio(projection.projectedEmiRatio.value)} of '
          'your income. FynnEdge uses $ceiling as its affordability '
          'reference'
          '${projection.withinCeiling ? ', so this stays inside it.' : ', so this would be past it.'}',
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
            color: color ?? AppColors.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _Alternative extends StatelessWidget {
  const _Alternative({required this.fund, required this.surplus});

  final EmergencyFundResult fund;
  final double surplus;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'POTENTIAL ALTERNATIVE',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: AppColors.textTertiary,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          fund.shortfall <= 0
              ? 'Your emergency fund is already at target. The surplus could '
                    'go towards your goals instead.'
              : fund.canCloseFromSurplus
              ? 'Directing your ${Fmt.money(surplus)} surplus at the '
                    '${Fmt.money(fund.shortfall)} emergency-fund gap closes it '
                    'in about ${fund.monthsToClose} months.'
              : 'There is a ${Fmt.money(fund.shortfall)} gap to a six-month '
                    'emergency fund, and no monthly surplus to close it with '
                    'yet.',
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.55,
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 18),
      child: Row(
        children: [
          Expanded(child: Divider(color: AppColors.border)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'OR',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.6,
                color: AppColors.textTertiary,
              ),
            ),
          ),
          Expanded(child: Divider(color: AppColors.border)),
        ],
      ),
    );
  }
}
