import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../../data/models/application.dart';
import 'application_controller.dart';
import 'documents/application_documents_card.dart';
import 'submission_card.dart';
import 'widgets/status_timeline.dart';
import '../../app/routes.dart';

/// Screen 20 — one application, with the status impossible to misread.
class ApplicationDetailScreen extends ConsumerWidget {
  const ApplicationDetailScreen({super.key, required this.id});

  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(applicationProvider(id));

    return async.when(
      loading: () => const FynnScaffold(
        title: 'Application',
        child: LoadingList(items: 3, itemHeight: 130),
      ),
      error: (e, _) => FynnScaffold(
        title: 'Application',
        child: ErrorState(
          message: messageForLoad(e),
          onRetry: () => ref.invalidate(applicationProvider(id)),
        ),
      ),
      data: (app) => _Detail(app: app),
    );
  }
}

class _Detail extends ConsumerWidget {
  const _Detail({required this.app});
  final LoanApplication app;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final color = statusColor(app.status);

    return FynnScaffold(
      title: app.productName,
      subtitle: app.reference,
      padHorizontal: false,
      glowPrimary: color,
      bottomBar: app.canSubmit
          ? PrimaryButton(
              label: 'Review and submit',
              icon: Icons.arrow_forward_rounded,
              onPressed: () => context.push(Routes.applyFor(app.productId)),
            )
          : app.canCancel
          ? SecondaryButton(
              label: 'Cancel this application',
              icon: Icons.close_rounded,
              onPressed: () => _confirmCancel(context, ref),
            )
          : null,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 26),
        children: staggered([
          // Status banner — the single most important thing on this screen.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppTheme.rLg),
              color: color.withValues(alpha: 0.09),
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: color,
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Wrapped rather than sized to its content: a status
                    // label is the server's sentence and can be as long as
                    // the truth requires, which "Submission status needs
                    // confirmation" already is on a 360-wide screen.
                    Expanded(
                      child: Text(
                        _statusLabel(app).toUpperCase(),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.4,
                          height: 1.4,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  _statusExplanation(app),
                  key: const Key('application_status_explanation'),
                  style: const TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),

          /*
           * The state this module exists to get right.
           *
           * FynnEdge sent the application and never heard back, so it does
           * not know whether the provider has it. That is a fact about
           * FynnEdge, not a failure of the customer's application — and the
           * one thing that must not appear here is an invitation to send it
           * again, which could create a second application at a provider
           * that may already hold the first.
           */
          if (app.customerStatus.isUnconfirmed) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                color: AppColors.warning.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.28),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.help_outline_rounded,
                    size: 18,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Please do not submit this again',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 5),
                        const Text(
                          'Sending it a second time could create two '
                          'applications with the provider. Support can '
                          'check what happened to the first one.',
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.55,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Sized to what is left after the icon and padding
                        // rather than to its natural width, which overflows
                        // a 360-wide screen inside this nested column.
                        SecondaryButton(
                          label: 'Contact support',
                          expand: false,
                          onPressed: () => context.push(Routes.support),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
          ],

          // Said plainly wherever the application is shown: nothing left
          // FynnEdge.
          if (app.isSimulated)
            const SampleDataNotice(
              margin: EdgeInsets.only(bottom: 18),
              message:
                  'Simulated submission. This application was recorded by '
                  'FynnEdge and sent to no provider — lender submission is '
                  'not connected yet.',
            ),
          const SectionHeader(title: 'The application'),
          FynnCard(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
            child: Column(
              children: [
                DetailRow(label: 'Reference', value: app.reference),
                const HairLine(),
                DetailRow(label: 'Provider', value: app.lender),
                const HairLine(),
                DetailRow(label: 'Product', value: app.productName),
                const HairLine(),
                DetailRow(
                  label: 'Requested amount',
                  value: Fmt.money(app.amount),
                  emphasise: true,
                ),
                const HairLine(),
                DetailRow(
                  label: 'Requested tenure',
                  value: Fmt.months(app.tenureMonths),
                ),
                const HairLine(),
                DetailRow(
                  label: 'Estimated EMI',
                  hint: 'At ${Fmt.percent(app.interestRate)}',
                  value: Fmt.money(app.emi),
                ),
                const HairLine(),
                DetailRow(
                  label: 'Estimated total repayment',
                  value: Fmt.money(app.totalPayable + app.processingFee),
                ),
                const HairLine(),
                DetailRow(label: 'Started', value: Fmt.date(app.createdAt)),
                if (app.submittedAt != null) ...[
                  const HairLine(),
                  DetailRow(
                    label: 'Submitted',
                    value: Fmt.date(app.submittedAt!),
                  ),
                ],
                if (app.updatedAt != null) ...[
                  const HairLine(),
                  DetailRow(
                    label: 'Last updated',
                    value: Fmt.date(app.updatedAt!),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          const SectionHeader(
            title: 'History',
            subtitle: 'What has actually happened, and who says so',
          ),
          FynnCard(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
            child: StatusTimeline(events: app.events),
          ),
          const SizedBox(height: 24),

          // Preparing the application comes before sending it, and is a
          // different thing: choosing documents happens entirely inside
          // FynnEdge and reaches nobody.
          ApplicationDocumentsCard(applicationId: app.id),
          const SizedBox(height: 24),

          // Deliberately its own section, below the application's own
          // status. What the customer did in FynnEdge and what an external
          // provider did are two facts, and one line would eventually be
          // read as though FynnEdge's acknowledgement were a provider's.
          SubmissionCard(applicationId: app.id),
          const SizedBox(height: 24),

          if (app.nextAction.isNotEmpty) ...[
            const SectionHeader(title: 'Next action'),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppTheme.rMd),
                color: AppColors.warning.withValues(alpha: 0.08),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.26),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.pending_actions_rounded,
                    size: 17,
                    color: AppColors.warning,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      app.nextAction,
                      style: const TextStyle(
                        fontSize: 13.5,
                        height: 1.55,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ], step: const Duration(milliseconds: 60)),
      ),
    );
  }

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgElevated,
        title: const Text('Cancel this application?'),
        content: const Text(
          'It will be marked cancelled and kept in your history. You can '
          'start a new one at any time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep it'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel it'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final cancelled = await ref.read(applicationActionsProvider).cancel(app.id);

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          cancelled == null
              ? 'That could not be cancelled. Please try again.'
              : 'Application cancelled.',
        ),
      ),
    );
  }

  /// What the status means, in FynnEdge's own voice.
  ///
  /// The provider-decision statuses describe what a provider reported. They
  /// are unreachable until a real gateway exists, and the copy does not
  /// pretend otherwise.
  /// The server's own words.
  ///
  /// Deliberately not derived here. This screen used to work the sentence
  /// out from the application status alone, which could not express the
  /// case that matters most — a submission whose fate FynnEdge does not
  /// know — and would have been a second answer to what a lender had said.
  static String _statusLabel(LoanApplication app) =>
      app.customerStatus.label.isNotEmpty ? app.customerStatus.label : app.label;

  static String _statusExplanation(LoanApplication app) =>
      app.customerStatus.description.isNotEmpty
      ? app.customerStatus.description
      : 'Your application is saved in FynnEdge.';
}
