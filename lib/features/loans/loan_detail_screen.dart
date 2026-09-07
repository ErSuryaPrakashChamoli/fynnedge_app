import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/session.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/error_text.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/sample_data_notice.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/engine/financial_engine.dart';
import '../../data/models/loan.dart';
import '../../data/match/fynn_match_engine.dart';
import '../../data/models/match.dart';
import 'loan_controller.dart';
import '../../app/routes.dart';

/// Screen 12 — the full cost of one offer, with both sides of the argument.
class LoanDetailScreen extends ConsumerWidget {
  const LoanDetailScreen({super.key, required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(simulatedMatchProvider(productId));

    return async.when(
      // A simulation in flight keeps the last figures on screen rather than
      // blanking the page under the customer's finger.
      skipLoadingOnRefresh: true,
      loading: () => const FynnScaffold(
        title: 'Loading offer',
        child: LoadingList(items: 3, itemHeight: 120),
      ),
      error: (e, _) => FynnScaffold(
        title: 'Offer',
        child: ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(fynnMatchProvider),
        ),
      ),
      data: (match) => _Detail(match: match),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.match});
  final ProductMatch match;

  LoanOffer get offer => match.offer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = offer.product;
    final e = offer.emi;
    final trustColor = AppColors.forScore(p.fynnTrust);
    final inCompare = ref.watch(compareProvider).contains(p.id);

    return FynnScaffold(
      title: p.lender,
      subtitle: p.name,
      padHorizontal: false,
      glowPrimary: trustColor,
      bottomBar: Row(
        children: [
          Expanded(
            child: SecondaryButton(
              label: inCompare ? 'Added' : 'Compare',
              icon: inCompare
                  ? Icons.check_rounded
                  : Icons.compare_arrows_rounded,
              onPressed: () {
                ref.read(compareProvider.notifier).toggle(p.id);
                if (ref.read(compareProvider).length >= 2) {
                  context.push(Routes.compare);
                }
              },
            ),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: PrimaryButton(
              label: 'Apply',
              onPressed: () => _showApplySheet(context, p.id),
            ),
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: staggered([
          _HeadlineNumbers(offer: offer),
          const SizedBox(height: 20),

          // Trust score gets its own row so it is never buried in the table.
          _TrustRow(score: p.fynnTrust, color: trustColor, productId: p.id),
          const SizedBox(height: 22),

          if (p.isSampleData)
            const SampleDataNotice(margin: EdgeInsets.only(bottom: 18)),

          // How this product lined up, criterion by criterion, before any of
          // the marketing copy below it.
          const SectionHeader(title: 'How this fits you'),
          _MatchPanel(match: match),
          const SizedBox(height: 24),

          // Try a different amount or term. Estimates only: nothing here is
          // saved, and nothing is submitted to anyone.
          const SectionHeader(
            title: 'Try different numbers',
            subtitle: 'Estimates. Nothing is saved or sent anywhere.',
          ),
          _Simulator(match: match),
          const SizedBox(height: 24),

          const SectionHeader(
            title: 'Before and after',
            subtitle: 'Your position today, and with this loan on it',
          ),
          _ProjectionPanel(projection: match.projection),
          const SizedBox(height: 24),

          const SectionHeader(title: 'The full cost'),
          FynnCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Column(
              children: [
                DetailRow(label: 'Loan amount', value: Fmt.money(offer.amount)),
                const HairLine(),
                DetailRow(
                  label: 'Available range',
                  hint: 'What this product will lend',
                  value:
                      '${Fmt.compactMoney(p.minAmount)} – '
                      '${Fmt.compactMoney(p.maxAmount)}',
                ),
                const HairLine(),
                DetailRow(
                  label: 'Interest rate',
                  hint: 'Reducing balance, per year',
                  value: Fmt.percent(p.interestRate),
                ),
                const HairLine(),
                DetailRow(
                  label: 'Tenure',
                  value: Fmt.months(offer.tenureMonths),
                ),
                const HairLine(),
                DetailRow(
                  label: 'Available tenure',
                  value:
                      '${Fmt.months(p.minTenureMonths)} – '
                      '${Fmt.months(p.maxTenureMonths)}',
                ),
                const HairLine(),
                DetailRow(
                  label: 'Monthly EMI',
                  value: Fmt.money(e.emi),
                  emphasise: true,
                ),
                const HairLine(),
                DetailRow(
                  label: 'Processing fee',
                  hint: p.processingFeeCap == null
                      ? '${p.processingFeePercent}% of loan amount'
                      : '${p.processingFeePercent}%, capped at '
                            '${Fmt.money(p.processingFeeCap!)}',
                  value: Fmt.money(offer.processingFee),
                ),
                const HairLine(),
                DetailRow(
                  label: 'Total interest',
                  hint: '${e.interestShare.round()}% of what you borrow',
                  value: Fmt.money(e.totalInterest),
                  valueColor: AppColors.warning,
                ),
                const HairLine(),
                DetailRow(
                  label: 'Total repayment',
                  hint: 'Everything you pay back, fees included',
                  value: Fmt.money(e.totalPayable + offer.processingFee),
                  emphasise: true,
                ),
                const HairLine(),
                DetailRow(
                  label: 'Prepayment',
                  value: p.prepaymentCharge.isEmpty
                      ? 'Not stated'
                      : p.prepaymentCharge,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          if (p.suitedReasons.isNotEmpty) ...[
            const SectionHeader(title: 'Why this may suit you'),
            _PointList(
              points: p.suitedReasons,
              icon: Icons.check_rounded,
              color: AppColors.mint,
            ),
            const SizedBox(height: 22),
          ],

          if (p.considerations.isNotEmpty) ...[
            const SectionHeader(title: 'Things to consider'),
            _PointList(
              points: p.considerations,
              icon: Icons.priority_high_rounded,
              color: AppColors.warning,
            ),
            const SizedBox(height: 22),
          ],

          if (p.conditions.isNotEmpty) ...[
            const SectionHeader(title: 'Important conditions'),
            FynnCard(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Column(
                children: [
                  for (var i = 0; i < p.conditions.length; i++) ...[
                    if (i > 0) const HairLine(),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 4),
                            child: Icon(
                              Icons.circle,
                              size: 5,
                              color: AppColors.textTertiary,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              p.conditions[i],
                              style: const TextStyle(
                                fontSize: 13.5,
                                height: 1.5,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],

          _AskAiCard(lender: p.lender),
          const SizedBox(height: 14),
          _MirrorCard(onTap: () => context.push(Routes.mirrorFor(p.id))),
          const SizedBox(height: 20),
          Text(
            FynnMatchEngine.disclaimer,
            style: const TextStyle(
              fontSize: 11,
              height: 1.5,
              color: AppColors.textTertiary,
            ),
          ),
        ], step: const Duration(milliseconds: 55)),
      ),
    );
  }

  void _showApplySheet(BuildContext context, String productId) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.bgElevated,
      builder: (context) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          8,
          24,
          28 + MediaQuery.of(context).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.mint.withValues(alpha: 0.12),
              ),
              child: const Icon(
                Icons.description_outlined,
                size: 21,
                color: AppColors.mint,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Before you apply',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 10),
            const Text(
              'You will see exactly what you are asking for, and what it '
              'would cost you each month, before anything is recorded. '
              'Lender submission is not connected yet, so nothing is sent to '
              'a provider and no credit check of any kind is run.',
              style: TextStyle(
                fontSize: 13.5,
                height: 1.6,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 22),
            PrimaryButton(
              label: 'Review application',
              onPressed: () {
                Navigator.of(context).pop();
                context.push(Routes.applyFor(productId));
              },
            ),
            const SizedBox(height: 6),
            Center(
              child: GhostButton(
                label: 'Not yet',
                color: AppColors.textTertiary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeadlineNumbers extends StatelessWidget {
  const _HeadlineNumbers({required this.offer});
  final LoanOffer offer;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      gradient: AppColors.surfaceGradient,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YOU WOULD PAY',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
              color: AppColors.textTertiary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                Fmt.money(offer.emi.emi),
                style: const TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.8,
                  height: 1,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Text(
                '  / month',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'for ${Fmt.months(offer.tenureMonths)} on '
            '${Fmt.compactMoney(offer.amount)}',
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _TrustRow extends StatelessWidget {
  const _TrustRow({
    required this.score,
    required this.color,
    required this.productId,
  });

  final int score;
  final Color color;
  final String productId;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(Routes.fynnTrust(productId)),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(AppTheme.rMd),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            Icon(Icons.verified_outlined, size: 19, color: color),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FynnTrust $score / 100',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'See how this score was built',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, size: 20, color: color),
          ],
        ),
      ),
    );
  }
}

class _PointList extends StatelessWidget {
  const _PointList({
    required this.points,
    required this.icon,
    required this.color,
  });

  final List<String> points;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final point in points)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 21,
                  height: 21,
                  margin: const EdgeInsets.only(top: 1),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color.withValues(alpha: 0.13),
                  ),
                  child: Icon(icon, size: 12, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    point,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.55,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _AskAiCard extends StatelessWidget {
  const _AskAiCard({required this.lender});
  final String lender;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(Routes.ai),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.rLg),
          gradient: LinearGradient(
            colors: [
              AppColors.violet.withValues(alpha: 0.16),
              AppColors.blue.withValues(alpha: 0.06),
            ],
          ),
          border: Border.all(color: AppColors.violet.withValues(alpha: 0.28)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.aiGradient,
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 13),
            const Expanded(
              child: Text(
                'Ask FynnAI about this offer',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 17,
              color: AppColors.violet,
            ),
          ],
        ),
      ),
    );
  }
}

class _MirrorCard extends StatelessWidget {
  const _MirrorCard({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              color: AppColors.warning.withValues(alpha: 0.13),
            ),
            child: const Icon(
              Icons.compare_rounded,
              size: 18,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: 13),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'FynnMirror',
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'See your life with and without this loan',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: AppColors.textTertiary,
          ),
        ],
      ),
    );
  }
}

/// The criteria FynnMatch actually checked, in plain sight.
///
/// "Not assessed" is listed as loudly as the rest. A customer who cannot see
/// which rules went unchecked has been handed a verdict dressed up as a
/// complete one.
class _MatchPanel extends StatelessWidget {
  const _MatchPanel({required this.match});
  final ProductMatch match;

  @override
  Widget build(BuildContext context) {
    return FynnCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(7),
                  border: Border.all(color: _color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  match.category.label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _color,
                  ),
                ),
              ),
              const Spacer(),
              // The EMI share is stated once, by the affordability criterion
              // below. Repeating it here at a different rounding made the
              // same number look like two.
              if (match.notAssessed.isNotEmpty)
                Text(
                  '${match.notAssessed.length} not checked',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppColors.textTertiary,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          for (final criterion in match.criteria) ...[
            _CriterionRow(criterion: criterion),
            if (criterion != match.criteria.last) const SizedBox(height: 11),
          ],
        ],
      ),
    );
  }

  Color get _color => switch (match.category) {
    MatchCategory.strongMatch => AppColors.mint,
    MatchCategory.goodMatch => AppColors.success,
    MatchCategory.review => AppColors.warning,
    MatchCategory.notAMatch => AppColors.danger,
  };
}

class _CriterionRow extends StatelessWidget {
  const _CriterionRow({required this.criterion});
  final MatchCriterion criterion;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (criterion.status) {
      CriterionStatus.passed => (Icons.check_circle_rounded, AppColors.success),
      CriterionStatus.failed => (Icons.cancel_rounded, AppColors.danger),
      CriterionStatus.caution => (
        Icons.error_outline_rounded,
        AppColors.warning,
      ),
      CriterionStatus.unavailable => (
        Icons.remove_circle_outline_rounded,
        AppColors.textTertiary,
      ),
    };

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    criterion.label,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  if (criterion.isUnavailable) ...[
                    const SizedBox(width: 6),
                    const Text(
                      'not checked',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                        color: AppColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                criterion.detail,
                style: const TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Amount and term sliders, bounded by what this product actually offers.
///
/// Everything it produces is an estimate: the customer's saved request is not
/// touched, and no figure here is submitted anywhere. Sliders commit on
/// release, so a drag never fires a stream of requests.
class _Simulator extends ConsumerWidget {
  const _Simulator({required this.match});
  final ProductMatch match;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = match.product;
    final inputs = ref.watch(simulationInputsProvider);
    final customised = inputs.appliesTo(p.id);

    final amount = customised ? inputs.amount : match.pricing.amount;
    final tenure = customised
        ? inputs.tenureMonths
        : match.pricing.tenureMonths;

    return FynnCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const EstimateBadge(),
              const Spacer(),
              if (customised)
                GestureDetector(
                  onTap: () =>
                      ref.read(simulationInputsProvider.notifier).reset(),
                  behavior: HitTestBehavior.opaque,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(
                      'Back to my request',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: AppColors.mint,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          _SimSlider(
            label: 'Amount',
            value: Fmt.money(amount),
            hint:
                '${Fmt.compactMoney(p.minAmount)} – '
                '${Fmt.compactMoney(p.maxAmount)}',
            current: amount.clamp(p.minAmount, p.maxAmount).toDouble(),
            min: p.minAmount,
            max: p.maxAmount,
            divisions: 40,
            onChanged: (v) => ref
                .read(simulationInputsProvider.notifier)
                .setAmount(match, _roundTo(v, 25000)),
          ),
          _SimSlider(
            label: 'Term',
            value: Fmt.months(tenure),
            hint:
                '${Fmt.months(p.minTenureMonths)} – '
                '${Fmt.months(p.maxTenureMonths)}',
            current: tenure
                .clamp(p.minTenureMonths, p.maxTenureMonths)
                .toDouble(),
            min: p.minTenureMonths.toDouble(),
            max: p.maxTenureMonths.toDouble(),
            divisions: ((p.maxTenureMonths - p.minTenureMonths) / 6).round(),
            onChanged: (v) => ref
                .read(simulationInputsProvider.notifier)
                .setTenure(match, (v / 6).round() * 6),
          ),
        ],
      ),
    );
  }

  static double _roundTo(double value, double step) =>
      (value / step).round() * step;
}

class _SimSlider extends StatefulWidget {
  const _SimSlider({
    required this.label,
    required this.value,
    required this.hint,
    required this.current,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String value;
  final String hint;
  final double current;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  State<_SimSlider> createState() => _SimSliderState();
}

class _SimSliderState extends State<_SimSlider> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final shown = _dragging ?? widget.current;

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                // Mid-drag this is the raw slider position, so the figure
                // under the thumb is never stale.
                _dragging == null ? widget.value : _preview(shown),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          Slider(
            value: shown.clamp(widget.min, widget.max),
            min: widget.min,
            max: widget.max,
            divisions: widget.divisions < 1 ? 1 : widget.divisions,
            onChanged: (v) => setState(() => _dragging = v),
            // Committed on release: one evaluation per adjustment, not one
            // per pixel.
            onChangeEnd: (v) {
              setState(() => _dragging = null);
              widget.onChanged(v);
            },
          ),
          Text(
            widget.hint,
            style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
          ),
        ],
      ),
    );
  }

  String _preview(double value) => widget.label == 'Term'
      ? Fmt.months(((value / 6).round() * 6).toInt())
      : Fmt.money((value / 25000).round() * 25000);
}

/// Today's position beside the same position with this loan on it.
///
/// Both columns come from one LoanProjection, so they cannot disagree.
class _ProjectionPanel extends StatelessWidget {
  const _ProjectionPanel({required this.projection});
  final LoanProjection projection;

  @override
  Widget build(BuildContext context) {
    if (!projection.isMeasurable) {
      return const FynnCard(
        padding: EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline_rounded,
              size: 16,
              color: AppColors.textTertiary,
            ),
            SizedBox(width: 11),
            Expanded(
              child: Text(
                'Add your monthly income on your financial profile and we can '
                'show what this loan would do to your month.',
                style: TextStyle(
                  fontSize: 13,
                  height: 1.5,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    final tight = projection.exhaustsSurplus;

    return FynnCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const EstimateBadge(),
          const SizedBox(height: 14),
          const Row(
            children: [
              SizedBox(width: 108),
              Expanded(child: _ColumnHead('NOW')),
              Expanded(child: _ColumnHead('WITH THIS LOAN')),
            ],
          ),
          const SizedBox(height: 4),
          _ProjectionRow(
            label: 'Monthly outgo',
            now: Fmt.money(projection.currentOutgo.rupees),
            after: Fmt.money(projection.projectedOutgo.rupees),
          ),
          _ProjectionRow(
            label: 'Left over',
            now: Fmt.money(projection.currentSurplus.rupees),
            after: Fmt.money(projection.projectedSurplus.rupees),
            afterColor: tight ? AppColors.danger : null,
          ),
          _ProjectionRow(
            label: 'EMI share',
            now: Fmt.ratio(projection.currentEmiRatio.value),
            after: Fmt.ratio(projection.projectedEmiRatio.value),
            afterColor: projection.withinCeiling ? null : AppColors.warning,
          ),
          const SizedBox(height: 12),
          const HairLine(),
          const SizedBox(height: 12),
          _HeadroomLine(projection: projection),
        ],
      ),
    );
  }
}

class _ColumnHead extends StatelessWidget {
  const _ColumnHead(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    textAlign: TextAlign.right,
    style: const TextStyle(
      fontSize: 9,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.9,
      color: AppColors.textTertiary,
    ),
  );
}

class _ProjectionRow extends StatelessWidget {
  const _ProjectionRow({
    required this.label,
    required this.now,
    required this.after,
    this.afterColor,
  });

  final String label;
  final String now;
  final String after;
  final Color? afterColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          SizedBox(
            width: 108,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          Expanded(
            child: Text(
              now,
              textAlign: TextAlign.right,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                color: AppColors.textTertiary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(
            child: Text(
              after,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: afterColor ?? AppColors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// What FynnEdge's affordability reference leaves room for — stated as our
/// own reference, never as an eligibility test or a lender's rule.
class _HeadroomLine extends StatelessWidget {
  const _HeadroomLine({required this.projection});
  final LoanProjection projection;

  @override
  Widget build(BuildContext context) {
    final ceiling = Fmt.ratio(projection.ceilingPercent);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          projection.withinCeiling
              ? Icons.check_circle_outline_rounded
              : Icons.error_outline_rounded,
          size: 15,
          color: projection.withinCeiling
              ? AppColors.success
              : AppColors.warning,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            projection.withinCeiling
                ? 'Based on the information you have given us, EMIs up to '
                      '${Fmt.money(projection.emiCeiling.rupees)} a month sit '
                      'inside the $ceiling of income FynnEdge uses as its '
                      'affordability reference. This loan would leave '
                      '${Fmt.money(projection.headroomAfter.rupees)} of that '
                      'room.'
                : 'Based on the information you have given us, this would put '
                      'your EMIs past the $ceiling of income FynnEdge uses as '
                      'its affordability reference. That is our own reference, '
                      'not a lender rule — the provider decides.',
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
