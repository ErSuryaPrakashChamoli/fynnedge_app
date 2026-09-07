import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/routes.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/error_text.dart';
import '../../core/widgets/buttons.dart';
import '../../core/widgets/entrance.dart';
import '../../core/widgets/fynn_scaffold.dart';
import '../../core/widgets/sample_data_notice.dart';
import '../../core/widgets/states.dart';
import '../../core/widgets/surfaces.dart';
import '../../data/models/application.dart';
import '../../data/models/match.dart';
import '../../data/services/application_service.dart';
import '../loans/loan_controller.dart';
import 'application_controller.dart';

/// Review — everything the customer is about to ask for, before they ask.
///
/// The figures are exactly the ones from the product they chose, priced by
/// the Financial Engine, and they stay estimates right up to and past
/// submission: FynnEdge does not decide, and does not pretend to.
class ApplicationReviewScreen extends ConsumerStatefulWidget {
  const ApplicationReviewScreen({super.key, required this.productId});

  final String productId;

  @override
  ConsumerState<ApplicationReviewScreen> createState() =>
      _ApplicationReviewScreenState();
}

class _ApplicationReviewScreenState
    extends ConsumerState<ApplicationReviewScreen> {
  @override
  void initState() {
    super.initState();
    // A fresh attempt each time the screen opens, so its idempotency key is
    // this attempt's and not the last one's.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(applicationFlowProvider.notifier).reset();
    });
  }

  @override
  Widget build(BuildContext context) {
    // The same simulated match the customer was looking at, so what they
    // review is what they saw.
    final async = ref.watch(simulatedMatchProvider(widget.productId));
    final flow = ref.watch(applicationFlowProvider);

    return async.when(
      loading: () => const FynnScaffold(
        title: 'Review',
        child: LoadingList(items: 3, itemHeight: 130),
      ),
      error: (e, _) => FynnScaffold(
        title: 'Review',
        child: ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(fynnMatchProvider),
        ),
      ),
      data: (match) => flow.isSubmitted
          ? _Submitted(application: flow.application!)
          : _Review(match: match, flow: flow),
    );
  }
}

class _Review extends ConsumerWidget {
  const _Review({required this.match, required this.flow});

  final ProductMatch match;
  final ApplicationFlowState flow;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = match.product;
    final pricing = match.pricing;
    final projection = match.projection;

    return FynnScaffold(
      title: 'Review',
      subtitle: '${p.lender} · ${p.name}',
      padHorizontal: false,
      bottomBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (flow.error != null) ...[
            _SubmissionError(message: flow.error!),
            const SizedBox(height: 12),
          ],
          PrimaryButton(
            label: flow.busy ? 'Submitting…' : 'Submit application',
            icon: Icons.send_rounded,
            // Disabled while a request is in flight, but the guarantee that
            // one tap makes one application is the idempotency key, not this.
            onPressed: flow.acknowledged && !flow.busy
                ? () => _submit(context, ref)
                : null,
          ),
        ],
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
        children: staggered([
          if (p.isSampleData)
            const SampleDataNotice(margin: EdgeInsets.only(bottom: 18)),

          const SectionHeader(title: 'The product'),
          FynnCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Column(
              children: [
                DetailRow(label: 'Provider', value: p.lender),
                const HairLine(),
                DetailRow(label: 'Product', value: p.name),
                const HairLine(),
                DetailRow(label: 'Type', value: p.category.label),
                const HairLine(),
                DetailRow(
                  label: 'FynnMatch',
                  hint: 'How this lined up with what you asked for',
                  value: match.category.label,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SectionHeader(title: 'What you are asking for'),
          FynnCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Column(
              children: [
                DetailRow(
                  label: 'Amount',
                  value: Fmt.money(pricing.amount),
                  emphasise: true,
                ),
                const HairLine(),
                DetailRow(
                  label: 'Tenure',
                  value: Fmt.months(pricing.tenureMonths),
                  emphasise: true,
                ),
                const HairLine(),
                DetailRow(
                  label: 'Interest rate',
                  hint: 'Published by the provider, reducing balance',
                  value: Fmt.percent(p.interestRate),
                ),
                const HairLine(),
                DetailRow(
                  label: 'Processing fee',
                  hint: p.processingFeeCap == null
                      ? '${p.processingFeePercent}%, no cap published'
                      : '${p.processingFeePercent}%, capped at '
                            '${Fmt.money(p.processingFeeCap!)}',
                  value: Fmt.money(pricing.processingFee),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SectionHeader(
            title: 'What it would cost you',
            subtitle: 'Worked out from the figures on your profile',
          ),
          FynnCard(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
            child: Column(
              children: [
                const Align(
                  alignment: Alignment.centerLeft,
                  child: EstimateBadge(),
                ),
                const SizedBox(height: 6),
                DetailRow(
                  label: 'Monthly EMI',
                  value: Fmt.money(pricing.emi),
                  emphasise: true,
                ),
                const HairLine(),
                DetailRow(
                  label: 'Total interest',
                  value: Fmt.money(pricing.totalInterest),
                  valueColor: AppColors.warning,
                ),
                const HairLine(),
                DetailRow(
                  label: 'Total repayment',
                  hint: 'Everything you pay back, fee included',
                  value: Fmt.money(
                    pricing.totalPayable + pricing.processingFee,
                  ),
                  emphasise: true,
                ),
                if (projection.isMeasurable) ...[
                  const HairLine(),
                  DetailRow(
                    label: 'EMI share of income',
                    hint: 'Now ${Fmt.ratio(projection.currentEmiRatio.value)}',
                    value: Fmt.ratio(projection.projectedEmiRatio.value),
                    valueColor: projection.withinCeiling
                        ? null
                        : AppColors.warning,
                  ),
                  const HairLine(),
                  DetailRow(
                    label: 'Left over each month',
                    hint: 'Now ${Fmt.money(projection.currentSurplus.rupees)}',
                    value: Fmt.money(projection.projectedSurplus.rupees),
                    valueColor: projection.exhaustsSurplus
                        ? AppColors.danger
                        : null,
                  ),
                ],
              ],
            ),
          ),
          if (projection.isMeasurable) ...[
            const SizedBox(height: 10),
            Text(
              projection.withinCeiling
                  ? 'Based on the information you have given us, this stays '
                        'inside the ${Fmt.ratio(projection.ceilingPercent)} of '
                        'income FynnEdge uses as its affordability reference.'
                  : 'Based on the information you have given us, this would '
                        'put your EMIs past the '
                        '${Fmt.ratio(projection.ceilingPercent)} of income '
                        'FynnEdge uses as its affordability reference. That is '
                        'our reference, not a provider rule.',
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
          ],
          const SizedBox(height: 24),

          const SectionHeader(title: 'Before you submit'),
          _Acknowledgement(
            statements: MockApplicationService.acknowledgements,
            value: flow.acknowledged,
            onChanged: (v) =>
                ref.read(applicationFlowProvider.notifier).setAcknowledged(v),
          ),
          const SizedBox(height: 14),
          const Text(
            'Submitting records this application with FynnEdge. Lender '
            'submission is not connected yet, so nothing is sent to a '
            'provider and no credit check of any kind is run.',
            style: TextStyle(
              fontSize: 12,
              height: 1.55,
              color: AppColors.textTertiary,
            ),
          ),
        ], step: const Duration(milliseconds: 55)),
      ),
    );
  }

  Future<void> _submit(BuildContext context, WidgetRef ref) async {
    final controller = ref.read(applicationFlowProvider.notifier);

    // The draft is created on submit, not on arrival: a customer who looks
    // and leaves has not applied for anything.
    final draft = await controller.start(match);
    if (draft == null || !context.mounted) return;

    await controller.submit();
  }
}

/// Confirmed, with what actually happened stated plainly.
class _Submitted extends ConsumerWidget {
  const _Submitted({required this.application});
  final LoanApplication application;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FynnScaffold(
      title: 'Submitted',
      padHorizontal: false,
      glowPrimary: AppColors.mint,
      bottomBar: PrimaryButton(
        label: 'View application',
        icon: Icons.arrow_forward_rounded,
        onPressed: () => context.go(Routes.application(application.id)),
      ),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        children: staggered([
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.mint.withValues(alpha: 0.12),
            ),
            child: const Icon(
              Icons.check_rounded,
              size: 28,
              color: AppColors.mint,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Application recorded',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          Text(
            'Reference ${application.reference}',
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 20),
          if (application.isSimulated)
            const SampleDataNotice(
              message:
                  'Simulated submission. FynnEdge has recorded this, and no '
                  'provider has received it — lender submission is not '
                  'connected yet.',
            ),
          const SizedBox(height: 18),
          FynnCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Column(
              children: [
                DetailRow(label: 'Provider', value: application.lender),
                const HairLine(),
                DetailRow(
                  label: 'Amount',
                  value: Fmt.money(application.amount),
                ),
                const HairLine(),
                DetailRow(
                  label: 'Tenure',
                  value: Fmt.months(application.tenureMonths),
                ),
                const HairLine(),
                DetailRow(
                  label: 'Estimated EMI',
                  value: Fmt.money(application.emi),
                ),
              ],
            ),
          ),
          if (application.nextAction.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              application.nextAction,
              style: const TextStyle(
                fontSize: 13,
                height: 1.55,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ], step: const Duration(milliseconds: 60)),
      ),
    );
  }
}

/// The two statements, confirmed together.
///
/// Deliberately not a profile-wide consent toggle: this is about this
/// application. FynnEdge holds no bureau or lender consent, and nothing here
/// implies otherwise.
class _Acknowledgement extends StatelessWidget {
  const _Acknowledgement({
    required this.statements,
    required this.value,
    required this.onChanged,
  });

  final List<String> statements;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(AppTheme.rMd),
      child: InkWell(
        onTap: () => onChanged(!value),
        borderRadius: BorderRadius.circular(AppTheme.rMd),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppTheme.rMd),
            border: Border.all(
              color: value
                  ? AppColors.mint.withValues(alpha: 0.45)
                  : AppColors.borderSoft,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                value
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 20,
                color: value ? AppColors.mint : AppColors.textTertiary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final statement in statements)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          statement,
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
        ),
      ),
    );
  }
}

class _SubmissionError extends StatelessWidget {
  const _SubmissionError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.rSm),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
